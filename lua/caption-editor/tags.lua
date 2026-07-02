-- tags.lua

local M = {}
local ns = vim.api.nvim_create_namespace("caption-tags")
local editor = require("caption-editor.editor")
local config = require("caption-editor.config")

-- State
local valid_tags = {}
local tag_files = {}
local tags_loaded = false
local suggestion_cache = {} -- key -> { results = [...], timestamp = number }
local diagnostic_cache = {}
local validate_timer = nil
local spell_ns = vim.api.nvim_create_namespace("caption-spell")
local quickfix_open = false

-- Store the list of tag files
function M.set_tag_files(files)
	tag_files = files or {}
	tags_loaded = false
end

-- Helper to load a single file
local function load_single_file(filepath, file_label)
	if not filepath or filepath == "" then
		return {}
	end
	local lines = vim.fn.readfile(filepath)
	if not lines then
		vim.notify("caption-editor: Failed to load " .. file_label .. " tag file: " .. filepath, vim.log.levels.WARN)
		return {}
	end
	local tags = {}
	for _, line in ipairs(lines) do
		local tag = line:match("^%s*(.-)%s*$")
		if tag and tag ~= "" then
			tags[tag] = true
		end
	end
	return tags
end

-- Load tags from all files (lazy)
function M.load_tags()
	valid_tags = {}
	local loaded_count = 0
	local success = false
	local errors = {}

	if #tag_files == 0 then
		vim.notify("caption-editor: No tag files provided. Set tag_validation.tag_files.", vim.log.levels.WARN)
		return false
	end

	for idx, filepath in ipairs(tag_files) do
		local label = "file " .. idx
		local ok, result = pcall(load_single_file, filepath, label)
		if not ok then
			table.insert(errors, filepath .. ": " .. result)
		else
			local file_tags = result
			for tag, _ in pairs(file_tags) do
				valid_tags[tag] = true
			end
			loaded_count = loaded_count + vim.tbl_count(file_tags)
			if vim.tbl_count(file_tags) > 0 then
				vim.notify(
					"caption-editor: Loaded " .. vim.tbl_count(file_tags) .. " tags from " .. filepath,
					vim.log.levels.INFO
				)
			end
		end
	end

	if loaded_count > 0 then
		vim.notify("caption-editor: Total " .. vim.tbl_count(valid_tags) .. " tags loaded", vim.log.levels.INFO)
		success = true
	else
		vim.notify("caption-editor: Failed to load any tags from " .. #tag_files .. " file(s)", vim.log.levels.ERROR)
		if #errors > 0 then
			for _, err in ipairs(errors) do
				vim.notify("caption-editor: " .. err, vim.log.levels.ERROR)
			end
		end
	end

	suggestion_cache = {}
	diagnostic_cache = {}
	return success
end

-- Ensure tags are loaded
function M.ensure_tags_loaded()
	if tags_loaded then
		return true
	end
	if #tag_files == 0 then
		vim.notify("caption-editor: No tag files configured. Set tag_validation.tag_files.", vim.log.levels.WARN)
		return false
	end
	local ok, err = pcall(M.load_tags)
	if not ok then
		vim.notify("caption-editor: Failed to load tags: " .. err, vim.log.levels.ERROR)
		return false
	end
	tags_loaded = true
	return true
end

-- Check if tag is valid
function M.is_valid_tag(tag)
	if not M.ensure_tags_loaded() then
		return false
	end
	if not tag or tag == "" then
		return false
	end
	return valid_tags[tag] or false
end

-- Generate query variations for broader search
local function generate_query_variations(query)
	local variations = { query }
	local seen = {}
	seen[query] = true

	-- Remove trailing 's' (plural to singular)
	if query:match("s$") then
		local alt = query:sub(1, -2)
		if not seen[alt] then
			table.insert(variations, alt)
			seen[alt] = true
		end
	end

	-- Remove trailing '_s' (booru plural format)
	if query:match("_s$") then
		local alt = query:sub(1, -3)
		if not seen[alt] then
			table.insert(variations, alt)
			seen[alt] = true
		end
	end

	-- If query has multiple words, try removing the last word
	local words = {}
	for w in query:gmatch("%S+") do
		table.insert(words, w)
	end
	if #words > 1 then
		local alt = table.concat(words, " ", 1, #words - 1)
		if not seen[alt] and alt ~= "" then
			table.insert(variations, alt)
			seen[alt] = true
		end
	end

	return variations
end

-- Fetch candidates from search tool with query variations
local function fetch_candidates(query, max_candidates, program)
	local candidates = {}
	local seen = {}

	-- Generate variations
	local variations = generate_query_variations(query)

	for _, q in ipairs(variations) do
		local cmd = build_search_command(q, max_candidates, program, tag_files)
		if cmd then
			local handle = io.popen(cmd)
			if handle then
				for line in handle:lines() do
					local tag = line:match("^%s*(.-)%s*$")
					if tag and tag ~= "" and not seen[tag] then
						seen[tag] = true
						table.insert(candidates, tag)
					end
				end
				handle:close()
			end
		end
	end

	return candidates
end

-- Build search command (supports multiple files, suppresses file names)
local function build_search_command(query, limit, program, files)
	local limit_arg = limit and limit > 0 and ("-m " .. limit) or ""
	local escaped_query = query:gsub('"', '\\"')

	if #files == 0 then
		return nil
	end

	local file_args = table.concat(files, " ")

	if program == "rg" or program == "ripgrep" then
		return string.format('rg -i -N --no-filename %s "%s" %s 2>/dev/null', limit_arg, escaped_query, file_args)
	elseif program == "ag" then
		return string.format(
			'ag -i --nocolor --nogroup --nofilename %s "%s" %s 2>/dev/null',
			limit_arg,
			escaped_query,
			file_args
		)
	elseif program == "ack" then
		return string.format(
			'ack -i --no-color --no-group --no-filename %s "%s" %s 2>/dev/null',
			limit_arg,
			escaped_query,
			file_args
		)
	elseif program == "git" or program == "git grep" then
		if #files > 0 then
			local git_file = files[1]
			return string.format(
				'git -C "%s" grep -i -n -h %s "%s" 2>/dev/null',
				vim.fn.fnamemodify(git_file, ":h"),
				limit_arg,
				escaped_query
			)
		end
		return nil
	else
		return string.format('grep -i -n -h %s "%s" %s 2>/dev/null', limit_arg, escaped_query, file_args)
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

local function score_levenshtein(query, tag)
	local dist = levenshtein_distance(query:lower(), tag:lower())
	local score = 100 - (dist / math.max(#query, #tag) * 100)
	if tag:lower() == query:lower() then
		score = 1000
	end
	if tag:lower():find(query:lower(), 1, true) == 1 then
		score = score + 20
	end
	return score
end

local function score_token(query, tag)
	return token_similarity_score(query, tag)
end

local function score_hybrid(query, tag)
	local lev_score =
		math.max(0, 100 - (levenshtein_distance(query:lower(), tag:lower()) / math.max(#query, #tag) * 100))
	local tok_score = token_similarity_score(query, tag)
	local exact_bonus = (tag:lower() == query:lower()) and 100 or 0
	local prefix_bonus = (tag:lower():find(query:lower(), 1, true) == 1) and 20 or 0
	return (lev_score * 0.35) + (tok_score * 0.35) + exact_bonus + prefix_bonus
end

-- Prune suggestion cache to stay within limit
local function prune_suggestion_cache()
	local opts = config.get()
	local limit = opts.tag_validation.suggestion_cache_limit or 100
	local keys = {}
	for key, _ in pairs(suggestion_cache) do
		table.insert(keys, key)
	end
	if #keys > limit then
		table.sort(keys, function(a, b)
			return suggestion_cache[a].timestamp < suggestion_cache[b].timestamp
		end)
		for i = limit + 1, #keys do
			suggestion_cache[keys[i]] = nil
		end
	end
end

-- Generate query variations for broader search
local function generate_query_variations(query)
	local variations = { query }
	local seen = {}
	seen[query] = true

	-- Remove trailing 's' (plural to singular)
	if query:match("s$") then
		local alt = query:sub(1, -2)
		if not seen[alt] then
			table.insert(variations, alt)
			seen[alt] = true
		end
	end

	-- Remove trailing '_s' (booru plural format)
	if query:match("_s$") then
		local alt = query:sub(1, -3)
		if not seen[alt] then
			table.insert(variations, alt)
			seen[alt] = true
		end
	end

	-- If query has multiple words, try removing the last word
	local words = {}
	for w in query:gmatch("%S+") do
		table.insert(words, w)
	end
	if #words > 1 then
		local alt = table.concat(words, " ", 1, #words - 1)
		if not seen[alt] and alt ~= "" then
			table.insert(variations, alt)
			seen[alt] = true
		end
	end

	-- Try splitting by underscores if present
	if query:find("_") then
		local parts = {}
		for p in query:gmatch("[^_]+") do
			table.insert(parts, p)
		end
		if #parts > 1 then
			-- Try without the last part
			local alt = table.concat(parts, "_", 1, #parts - 1)
			if not seen[alt] and alt ~= "" then
				table.insert(variations, alt)
				seen[alt] = true
			end
		end
	end

	return variations
end

-- Fetch candidates from search tool with query variations
local function fetch_candidates(query, max_candidates, program)
	local candidates = {}
	local seen = {}

	local variations = generate_query_variations(query)

	for _, q in ipairs(variations) do
		local cmd = build_search_command(q, max_candidates, program, tag_files)
		if cmd then
			local handle = io.popen(cmd)
			if handle then
				for line in handle:lines() do
					local tag = line:match("^%s*(.-)%s*$")
					if tag and tag ~= "" and not seen[tag] then
						seen[tag] = true
						table.insert(candidates, tag)
					end
				end
				handle:close()
			end
		end
	end

	return candidates
end

-- Get suggestions from search program (with algorithm selection and caching)
function M.get_suggestions(query, limit)
	if not M.ensure_tags_loaded() then
		return {}
	end
	if not query or query == "" or #tag_files == 0 then
		return {}
	end

	-- Check cache
	local opts = config.get()
	local ttl = opts.tag_validation.suggestion_cache_ttl or 300
	local now = os.time()
	local cache_entry = suggestion_cache[query]
	if cache_entry then
		if now - cache_entry.timestamp < ttl then
			return cache_entry.results
		else
			suggestion_cache[query] = nil
		end
	end

	limit = limit or 10
	local program = opts.tag_validation.search_tool or "rg"
	local algorithm = opts.tag_validation.rank_method or "raw"
	local max_candidates = opts.tag_validation.max_candidates or 200

	local results = {}

	-- Fetch candidates using the improved function (with query variations)
	local candidates = fetch_candidates(query, max_candidates, program)

	if algorithm == "levenshtein" then
		local scored = {}
		for _, tag in ipairs(candidates) do
			table.insert(scored, { tag = tag, score = score_levenshtein(query, tag) })
		end
		table.sort(scored, function(a, b)
			return a.score > b.score
		end)
		for i = 1, math.min(limit, #scored) do
			table.insert(results, scored[i].tag)
		end
	elseif algorithm == "token" then
		local scored = {}
		for _, tag in ipairs(candidates) do
			table.insert(scored, { tag = tag, score = score_token(query, tag) })
		end
		table.sort(scored, function(a, b)
			return a.score > b.score
		end)
		for i = 1, math.min(limit, #scored) do
			table.insert(results, scored[i].tag)
		end
	elseif algorithm == "hybrid" then
		local scored = {}
		for _, tag in ipairs(candidates) do
			table.insert(scored, { tag = tag, score = score_hybrid(query, tag) })
		end
		table.sort(scored, function(a, b)
			return a.score > b.score
		end)
		for i = 1, math.min(limit, #scored) do
			table.insert(results, scored[i].tag)
		end
	else
		-- raw (original behavior)
		results = candidates
	end

	suggestion_cache[query] = {
		results = results,
		timestamp = now,
	}
	prune_suggestion_cache()

	return results
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
	if not M.ensure_tags_loaded() then
		return
	end
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
	if not M.ensure_tags_loaded() then
		return
	end
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	else
		buf = tonumber(buf)
	end

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

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

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local tag_diagnostics = {}
	local spell_diagnostics = {}

	for line_num, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")

		if trimmed and trimmed ~= "" and trimmed ~= "|||" then
			local in_tags_section = M.is_in_tags_section(buf, line_num - 1)

			if in_tags_section then
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

-- Get tag under cursor (assumes each line is a single tag in split view)
function M.get_tag_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local trimmed = line:match("^%s*(.-)%s*$")

	if trimmed == "" then
		return nil, 0, 0
	end

	-- Find the position of the trimmed tag within the original line
	local start = line:find(trimmed) - 1  -- 0-indexed column
	local end_pos = start + #trimmed

	return trimmed, start, end_pos
end

-- Quick fix
function M.fix_tag()
	if not M.ensure_tags_loaded() then
		return
	end
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
		M.validate_buffer(buf)
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
-- If reset_idx is true, the selection index is set to 1 (first entry),
-- otherwise it preserves the current selection index.
function M.list_invalid_tags(buf, reset_idx)
	if not M.ensure_tags_loaded() then
		return
	end
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	else
		buf = tonumber(buf)
	end

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local qf_list = {}

	local saved_idx = 1
	if not reset_idx then
		local info = vim.fn.getqflist({ idx = 0 })
		if info and info.idx then
			saved_idx = info.idx
		end
	end

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

	local clamped_idx = math.min(saved_idx, #qf_list)

	vim.fn.setqflist({}, "r", {
		items = qf_list,
		idx = clamped_idx,
	})

	if not quickfix_open then
		vim.cmd("copen")
		quickfix_open = true
		vim.fn.setqflist({}, "a", { idx = clamped_idx })
	end
end

-- Close quickfix
function M.close_quickfix()
	if quickfix_open then
		vim.cmd("cclose")
		quickfix_open = false
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

	vim.diagnostic.reset(ns, buf)
	vim.diagnostic.reset(spell_ns, buf)
end

-- Refresh both diagnostics and quickfix list (manual refresh)
function M.refresh_all(buf)
	if not M.ensure_tags_loaded() then
		return
	end
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	else
		buf = tonumber(buf)
	end

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	M.validate_buffer(buf)
	M.list_invalid_tags(buf, false)
end

return M
