-- tags.lua

local M = {}
local ns = vim.api.nvim_create_namespace("caption-tags")
local editor = require("caption-editor.editor")
local config = require("caption-editor.config")

-- State
local valid_tags = {}
local tag_file_path = ""
local suggestion_cache = {}
local diagnostic_cache = {}
local validate_timer = nil
local spell_ns = vim.api.nvim_create_namespace("caption-spell")
local quickfix_open = false

-- Build search command based on program
local function build_search_command(query, limit, program, tag_file)
	local limit_arg = limit and limit > 0 and ("-m " .. limit) or ""
	local escaped_query = query:gsub('"', '\\"')

	if program == "rg" or program == "ripgrep" then
		return string.format('rg -i -N %s "%s" "%s" 2>/dev/null', limit_arg, escaped_query, tag_file)
	elseif program == "ag" then
		return string.format('ag -i --nocolor --nogroup %s "%s" "%s" 2>/dev/null', limit_arg, escaped_query, tag_file)
	elseif program == "ack" then
		return string.format(
			'ack -i --no-color --no-group %s "%s" "%s" 2>/dev/null',
			limit_arg,
			escaped_query,
			tag_file
		)
	elseif program == "git" or program == "git grep" then
		return string.format(
			'git -C "%s" grep -i -n %s "%s" 2>/dev/null',
			vim.fn.fnamemodify(tag_file, ":h"),
			limit_arg,
			escaped_query
		)
	else
		return string.format('grep -i -n %s "%s" "%s" 2>/dev/null', limit_arg, escaped_query, tag_file)
	end
end

-- Levenshtein distance (Lua implementation)
local function levenshtein_lua(a, b)
	if a == b then
		return 0
	end
	local len_a, len_b = #a, #b
	if len_a == 0 then
		return len_b
	end
	if len_b == 0 then
		return len_a
	end
	local matrix = {}
	for i = 0, len_a do
		matrix[i] = { [0] = i }
	end
	for j = 0, len_b do
		matrix[0][j] = j
	end
	for i = 1, len_a do
		for j = 1, len_b do
			local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
			matrix[i][j] = math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
		end
	end
	return matrix[len_a][len_b]
end

-- Use vim's built-in levenshtein if available
local function levenshtein_distance(a, b)
	if vim.fn.has("levenshtein") == 1 then
		return vim.fn.levenshtein(a, b)
	end
	return levenshtein_lua(a, b)
end

-- Token similarity: split by underscores and compare overlap
local function token_similarity_score(query, tag)
	if not query or query == "" or not tag or tag == "" then
		return 0
	end

	local function split_tokens(str)
		local tokens = {}
		for token in str:gmatch("[^_]+") do
			if token ~= "" then
				table.insert(tokens, token:lower())
			end
		end
		return tokens
	end

	local query_tokens = split_tokens(query)
	local tag_tokens = split_tokens(tag)

	if #query_tokens == 0 or #tag_tokens == 0 then
		return 0
	end

	local query_set = {}
	for _, t in ipairs(query_tokens) do
		query_set[t] = true
	end

	local matches = 0
	for _, t in ipairs(tag_tokens) do
		if query_set[t] then
			matches = matches + 1
		end
	end

	local max_tokens = math.max(#query_tokens, #tag_tokens)
	local score = (matches / max_tokens) * 100

	if #query_tokens == #tag_tokens and matches == #query_tokens then
		score = 100
	end

	if tag:lower():find(query:lower(), 1, true) == 1 then
		score = score + 10
	end

	return score
end

-- Load tags from file
function M.load_tags(filepath)
	if not filepath or filepath == "" then
		return
	end

	tag_file_path = filepath

	local lines = vim.fn.readfile(filepath)
	if not lines then
		vim.notify("caption-editor: Failed to load tag file: " .. filepath, vim.log.levels.ERROR)
		return
	end

	valid_tags = {}
	for _, line in ipairs(lines) do
		local tag = line:match("^%s*(.-)%s*$")
		if tag and tag ~= "" then
			valid_tags[tag] = true
		end
	end

	vim.notify("caption-editor: Loaded " .. vim.tbl_count(valid_tags) .. " tags", vim.log.levels.INFO)
end

-- Check if tag is valid
function M.is_valid_tag(tag)
	if not tag or tag == "" then
		return false
	end
	return valid_tags[tag] or false
end

-- Check if a line is in a tags section
function M.is_in_tags_section(buf, line_num)
	local opts = config.get()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	local section_index = 1
	local separator_count = 0

	for i = 0, line_num - 1 do
		local trimmed = lines[i + 1] and lines[i + 1]:match("^%s*(.-)%s*$") or ""
		if trimmed == opts.section_delimiter then
			separator_count = separator_count + 1
			if i < line_num then
				section_index = separator_count + 1
			end
		end
	end

	local section_type = "tags"
	if section_index <= #opts.section_types then
		section_type = opts.section_types[section_index]
	end

	return section_type == "tags"
end

-- Get suggestions from search program (with algorithm selection)
function M.get_suggestions(query, limit)
	if not query or query == "" or tag_file_path == "" then
		return {}
	end

	if suggestion_cache[query] then
		return suggestion_cache[query]
	end

	-- Get suggestions from search tool (with ranking selection)
	limit = limit or 10
	local opts = config.get()
	local program = opts.tag_validation.search_tool or "rg"
	local algorithm = opts.tag_validation.rank_method or "raw" -- raw, no ranking, just raw output from search_tool
	local max_candidates = opts.tag_validation.max_candidates or 200

	local results = {}

	if algorithm == "levenshtein" or algorithm == "token" or algorithm == "hybrid" then
		local cmd = build_search_command(query, max_candidates, program, tag_file_path)
		local handle = io.popen(cmd)
		if handle then
			local candidates = {}
			for line in handle:lines() do
				local tag = line:match("^%s*(.-)%s*$")
				if tag and tag ~= "" then
					tag = tag:gsub("^%d+:", "")
					tag = tag:match("^%s*(.-)%s*$")
					if tag and tag ~= "" then
						table.insert(candidates, tag)
					end
				end
			end
			handle:close()

			local scored = {}
			for _, tag in ipairs(candidates) do
				local lev_score = 0
				local token_score = 0
				local final_score = 0

				if algorithm == "levenshtein" then
					local dist = levenshtein_distance(query:lower(), tag:lower())
					lev_score = 100 - (dist / math.max(#query, #tag) * 100)
					if tag:lower() == query:lower() then
						lev_score = 1000
					end
					if tag:lower():find(query:lower(), 1, true) == 1 then
						lev_score = lev_score + 20
					end
					final_score = lev_score
				elseif algorithm == "token" then
					token_score = token_similarity_score(query, tag)
					final_score = token_score
				else -- hybrid
					-- Levenshtein score (normalized 0-100)
					local dist = levenshtein_distance(query:lower(), tag:lower())
					lev_score = math.max(0, 100 - (dist / math.max(#query, #tag) * 100))

					-- Token score (0-100)
					token_score = token_similarity_score(query, tag)

					-- Exact match bonus
					local exact_bonus = 0
					if tag:lower() == query:lower() then
						exact_bonus = 100
					end

					-- Prefix bonus
					local prefix_bonus = 0
					if tag:lower():find(query:lower(), 1, true) == 1 then
						prefix_bonus = 20
					end

					-- Combine: 40% Levenshtein + 40% Token + 20% bonuses
					final_score = (lev_score * 0.35) + (token_score * 0.35) + exact_bonus + prefix_bonus
				end

				table.insert(scored, { tag = tag, score = final_score })
			end

			table.sort(scored, function(a, b)
				if a.score ~= b.score then
					return a.score > b.score
				end
				return #a.tag < #b.tag
			end)

			for i = 1, math.min(limit, #scored) do
				table.insert(results, scored[i].tag)
			end
		end
	else
		-- raw (original behavior)
		local cmd = build_search_command(query, limit, program, tag_file_path)
		local handle = io.popen(cmd)
		if handle then
			for line in handle:lines() do
				local tag = line:match("^%s*(.-)%s*$")
				if tag and tag ~= "" then
					tag = tag:gsub("^%d+:", "")
					tag = tag:match("^%s*(.-)%s*$")
					if tag and tag ~= "" then
						table.insert(results, tag)
					end
				end
			end
			handle:close()
		end
	end

	suggestion_cache[query] = results
	return results
end

-- Get words from a line with their positions
local function get_words(line)
	local words = {}
	for word in line:gmatch("[%a']+") do
		local start_pos = line:find(word)
		if start_pos then
			table.insert(words, { word = word, start = start_pos })
		end
	end
	return words
end

-- Get diagnostic message
local function get_diagnostic_message(tag)
	local opts = config.get()
	local show_suggestions = opts.tag_validation and opts.tag_validation.show_suggestions

	if not show_suggestions then
		return "Not a booru tag: " .. tag
	end

	if diagnostic_cache[tag] then
		return diagnostic_cache[tag]
	end

	local all = M.get_suggestions(tag)
	local display = {}
	for i = 1, math.min(5, #all) do
		table.insert(display, all[i])
	end

	local msg = "Not a booru tag: " .. tag
	if #display > 0 then
		local suffix = #all > 5 and (" (+" .. (#all - 5) .. " more)") or ""
		msg = msg .. " (suggestions: " .. table.concat(display, ", ") .. suffix .. ")"
	end

	diagnostic_cache[tag] = msg
	return msg
end

-- Clear caches
function M.clear_cache()
	suggestion_cache = {}
	diagnostic_cache = {}
end

-- Schedule validation with configurable debounce
function M.schedule_validate(buf)
	if validate_timer then
		validate_timer:stop()
		validate_timer:close()
		validate_timer = nil
	end

	local opts = config.get()
	local debounce_ms = opts.tag_validation.debounce_ms or 200

	validate_timer = vim.defer_fn(function()
		validate_timer = nil
		M.validate_buffer(buf)
	end, debounce_ms)
end

-- Validate buffer
function M.validate_buffer(buf)
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	end

	-- Skip validation during saving
	if editor.get_state().saving then
		return
	end

	vim.diagnostic.reset(ns, buf)
	vim.diagnostic.reset(spell_ns, buf)

	if not editor.get_state().active or vim.tbl_count(valid_tags) == 0 then
		return
	end

	local opts = config.get()
	local force_spellcheck = opts.tag_validation.force_spellcheck

	-- Handle spellcheck based on user config
	local win = vim.api.nvim_get_current_win()
	local spell_enabled = vim.api.nvim_get_option_value("spell", { win = win })

	if force_spellcheck == true then
		if not spell_enabled then
			vim.api.nvim_set_option_value("spell", true, { win = win })
			spell_enabled = true
		end
	elseif force_spellcheck == false then
		if spell_enabled then
			vim.api.nvim_set_option_value("spell", false, { win = win })
			spell_enabled = false
		end
	end
	-- nil: respect user's existing settings, do nothing

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local tag_diagnostics = {}
	local spell_diagnostics = {}

	for line_num, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")

		if trimmed and trimmed ~= "" and trimmed ~= "|||" then
			local in_tags_section = M.is_in_tags_section(buf, line_num - 1)

			if in_tags_section then
				-- Tags section: validate against booru tags
				if not M.is_valid_tag(trimmed) then
					local col = line:find(trimmed) or 1

					table.insert(tag_diagnostics, {
						bufnr = buf,
						lnum = line_num - 1,
						col = col - 1,
						end_col = col + #trimmed - 1,
						severity = vim.diagnostic.severity.WARN,
						message = get_diagnostic_message(trimmed),
						source = "caption-editor",
					})
				end
			else
				-- NL section: use spellcheck if enabled
				if spell_enabled then
					for _, word_info in ipairs(get_words(line)) do
						local word = word_info.word
						if vim.fn.spellbadword(word) == word then
							local col = word_info.start - 1
							table.insert(spell_diagnostics, {
								bufnr = buf,
								lnum = line_num - 1,
								col = col,
								end_col = col + #word,
								severity = vim.diagnostic.severity.WARN,
								message = "Misspelled word: " .. word,
								source = "spell",
							})
						end
					end
				end
			end
		end
	end

	if #tag_diagnostics > 0 then
		vim.diagnostic.set(ns, buf, tag_diagnostics)
	end

	if #spell_diagnostics > 0 then
		vim.diagnostic.set(spell_ns, buf, spell_diagnostics)
	end
end

-- Get tag under cursor
function M.get_tag_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]

	local start = col
	while start > 0 and line:sub(start, start):match("[%a%d_%s]") do
		start = start - 1
	end
	if start > 0 and (line:sub(start, start) == " " or line:sub(start, start) == ",") then
		start = start + 1
	end

	local end_pos = col
	while end_pos < #line and line:sub(end_pos + 1, end_pos + 1):match("[%a%d_%s]") do
		end_pos = end_pos + 1
	end

	local tag = line:sub(start + 1, end_pos)
	return tag, start, end_pos
end

-- Quick fix
function M.fix_tag()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)

	if not M.is_in_tags_section(buf, cursor[1] - 1) then
		vim.notify("Not in a tags section", vim.log.levels.WARN)
		return
	end

	local tag, start, end_pos = M.get_tag_under_cursor()
	if not tag or tag == "" then
		vim.notify("No tag under cursor", vim.log.levels.WARN)
		return
	end

	if M.is_valid_tag(tag) then
		vim.notify("Tag is valid: " .. tag, vim.log.levels.INFO)
		return
	end

	local suggestions = M.get_suggestions(tag)
	if #suggestions == 0 then
		vim.notify("No suggestions found for: " .. tag, vim.log.levels.WARN)
		return
	end

	local function apply_fix(choice)
		vim.api.nvim_buf_set_text(buf, cursor[1] - 1, start, cursor[1] - 1, end_pos, { choice })
		vim.api.nvim_win_set_cursor(0, { cursor[1], start + #choice })
		M.schedule_validate(buf)
		vim.notify("Fixed: " .. tag .. " -> " .. choice, vim.log.levels.INFO)
	end

	if #suggestions == 1 then
		apply_fix(suggestions[1])
		return
	end

	vim.ui.select(suggestions, {
		prompt = "Replace '" .. tag .. "' with (" .. #suggestions .. " matches):",
	}, function(choice)
		if choice then
			apply_fix(choice)
		end
	end)
end

-- Check if quickfix is open
function M.is_quickfix_open()
	return quickfix_open
end

-- List invalid tags in quickfix
function M.list_invalid_tags()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local qf_list = {}

	if not editor.get_state().active then
		if quickfix_open then
			vim.cmd("cclose")
			quickfix_open = false
		end
		return
	end

	for line_num, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" and trimmed ~= "|||" then
			if M.is_in_tags_section(buf, line_num - 1) and not M.is_valid_tag(trimmed) then
				local col = line:find(trimmed) or 1
				local all = M.get_suggestions(trimmed)
				local display = {}
				for i = 1, math.min(3, #all) do
					table.insert(display, all[i])
				end

				local text = "Not a booru tag: " .. trimmed
				if #display > 0 then
					local suffix = #all > 3 and (" (+" .. (#all - 3) .. " more)") or ""
					text = text .. " (suggestions: " .. table.concat(display, ", ") .. suffix .. ")"
				end

				table.insert(qf_list, {
					bufnr = buf,
					lnum = line_num,
					col = col,
					text = text,
					type = "W",
				})
			end
		end
	end

	if #qf_list == 0 then
		if quickfix_open then
			vim.fn.setqflist({}, "r")
			vim.cmd("cclose")
			quickfix_open = false
		end
		return
	end

	vim.fn.setqflist(qf_list, "r")

	if not quickfix_open then
		vim.cmd("copen")
		quickfix_open = true
	end
end

-- Close quickfix
function M.close_quickfix()
	if quickfix_open then
		vim.cmd("cclose")
		quickfix_open = false
	end
end

-- Fix all invalid tags
function M.fix_all_tags()
	local qf_list = vim.fn.getqflist()
	local fixed = 0
	local buf = vim.api.nvim_get_current_buf()

	for _, item in ipairs(qf_list) do
		local item_buf = item.bufnr
		local line_num = item.lnum
		local col = item.col

		if item_buf and vim.api.nvim_buf_is_valid(item_buf) then
			local lines = vim.api.nvim_buf_get_lines(item_buf, line_num - 1, line_num, false)
			if #lines > 0 then
				local line = lines[1]
				local start = col - 1
				local end_pos = start
				while end_pos < #line and line:sub(end_pos + 1, end_pos + 1):match("[%a%d_%s]") do
					end_pos = end_pos + 1
				end

				local tag = line:sub(start + 1, end_pos):match("^%s*(.-)%s*$")
				if tag then
					local suggestions = M.get_suggestions(tag, 1)
					if #suggestions > 0 then
						vim.api.nvim_buf_set_text(
							item_buf,
							line_num - 1,
							start,
							line_num - 1,
							end_pos,
							{ suggestions[1] }
						)
						fixed = fixed + 1
					end
				end
			end
		end
	end

	if fixed > 0 then
		M.schedule_validate(buf)
		vim.notify("Fixed " .. fixed .. " invalid tags", vim.log.levels.INFO)
		M.list_invalid_tags()
	else
		vim.notify("No tags could be fixed", vim.log.levels.WARN)
	end
end

-- Clear all diagnostics for a buffer
function M.clear_all_diagnostics(buf)
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	end

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- Clear tag diagnostics
	vim.diagnostic.reset(ns, buf)

	-- Clear spell diagnostics
	vim.diagnostic.reset(spell_ns, buf)
end

return M
