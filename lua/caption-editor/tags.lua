-- tags.lua - Tag validation and suggestions

local M = {}
local valid_tags = {}
local ns = vim.api.nvim_create_namespace("caption-tags")
local editor = require('caption-editor.editor')
local config = require('caption-editor.config')

-- Load tags from file
function M.load_tags(filepath)
	if not filepath or filepath == '' then
		return
	end

	local lines = vim.fn.readfile(filepath)
	if not lines then
		vim.notify("caption-editor: Failed to load tag file: " .. filepath, vim.log.levels.ERROR)
		return
	end

	valid_tags = {}
	for _, line in ipairs(lines) do
		local tag = line:match("^%s*(.-)%s*$")
		if tag and tag ~= '' then
			valid_tags[tag] = true
		end
	end

	vim.notify("caption-editor: Loaded " .. vim.tbl_count(valid_tags) .. " tags", vim.log.levels.INFO)
end

-- Check if tag is valid
function M.is_valid_tag(tag)
	if not tag or tag == '' then
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
		local trimmed = lines[i+1] and lines[i+1]:match("^%s*(.-)%s*$") or ""
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

-- Find similar tags for suggestions
function M.suggest_tags(tag, max_suggestions)
	max_suggestions = max_suggestions or 5
	local suggestions = {}
	local tag_lower = tag:lower()

	for valid_tag, _ in pairs(valid_tags) do
		if #suggestions >= max_suggestions then
			break
		end

		-- Exact match (case insensitive)
		if valid_tag:lower() == tag_lower then
			table.insert(suggestions, valid_tag)
		-- Starts with (case insensitive)
		elseif valid_tag:lower():find(tag_lower, 1, true) then
			table.insert(suggestions, valid_tag)
		-- Similar length and character overlap
		elseif #valid_tag >= #tag - 2 and #valid_tag <= #tag + 2 then
			local matches = 0
			for i = 1, math.min(#tag, #valid_tag) do
				if tag_lower:sub(i, i) == valid_tag:lower():sub(i, i) then
					matches = matches + 1
				end
			end
			if matches >= #tag - 2 then
				table.insert(suggestions, valid_tag)
			end
		end
	end

	-- Sort suggestions by relevance
	table.sort(suggestions, function(a, b)
		local a_score = 0
		local b_score = 0
		local tag_lower = tag:lower()

		if a:lower() == tag_lower then a_score = 100 end
		if a:lower():find(tag_lower, 1, true) then a_score = 50 end
		if #a == #tag then a_score = 10 end

		if b:lower() == tag_lower then b_score = 100 end
		if b:lower():find(tag_lower, 1, true) then b_score = 50 end
		if #b == #tag then b_score = 10 end

		return a_score > b_score
	end)

	return suggestions
end

-- Validate buffer and show diagnostics
function M.validate_buffer(buf)
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	end

	vim.diagnostic.reset(ns, buf)

	if not editor.get_state().active then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local diagnostics = {}

	for line_num, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")

		if trimmed and trimmed ~= '' and trimmed ~= "|||" then
			if M.is_in_tags_section(buf, line_num - 1) then
				if not M.is_valid_tag(trimmed) then
					local col = line:find(trimmed) or 1
					local suggestions = M.suggest_tags(trimmed, 3)
					local msg = "Invalid tag: " .. trimmed
					if #suggestions > 0 then
						msg = msg .. " (suggestions: " .. table.concat(suggestions, ", ") .. ")"
					end

					table.insert(diagnostics, {
						bufnr = buf,
						lnum = line_num - 1,
						col = col - 1,
						end_col = col + #trimmed - 1,
						severity = vim.diagnostic.severity.WARN,
						message = msg,
						source = "caption-editor",
					})
				end
			end
		end
	end

	if #diagnostics > 0 then
		vim.diagnostic.set(ns, buf, diagnostics)
	end
end

-- Get the tag under cursor
function M.get_tag_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local col = cursor[2]

	-- Find start of word
	local start = col
	while start > 0 and line:sub(start, start):match("[%a%d_%s]") do
		start = start - 1
	end
	if start > 0 and (line:sub(start, start) == " " or line:sub(start, start) == ",") then
		start = start + 1
	end

	-- Find end of word
	local end_pos = col
	while end_pos < #line and line:sub(end_pos + 1, end_pos + 1):match("[%a%d_%s]") do
		end_pos = end_pos + 1
	end

	local tag = line:sub(start + 1, end_pos)
	return tag, start, end_pos
end

-- Quick fix: Replace invalid tag with suggestion
function M.fix_tag()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	local col = cursor[2]

	-- Only fix if in a tags section
	if not M.is_in_tags_section(buf, cursor[1] - 1) then
		vim.notify("Not in a tags section", vim.log.levels.WARN)
		return
	end

	-- Find start of word (0-indexed for nvim_buf_set_text)
	local start = col
	while start > 0 and line:sub(start, start):match("[%a%d_%s]") do
		start = start - 1
	end
	-- If we stopped at a space or comma, move past it
	if start > 0 and (line:sub(start, start) == " " or line:sub(start, start) == ",") then
		start = start + 1
	end

	-- Find end of word
	local end_pos = col
	while end_pos < #line and line:sub(end_pos + 1, end_pos + 1):match("[%a%d_%s]") do
		end_pos = end_pos + 1
	end

	local tag = line:sub(start + 1, end_pos):match("^%s*(.-)%s*$")
	if not tag or tag == '' then
		vim.notify("No tag under cursor", vim.log.levels.WARN)
		return
	end

	if M.is_valid_tag(tag) then
		vim.notify("Tag is valid: " .. tag, vim.log.levels.INFO)
		return
	end

	local suggestions = M.suggest_tags(tag, 5)
	if #suggestions == 0 then
		vim.notify("No suggestions found for: " .. tag, vim.log.levels.WARN)
		return
	end

	-- Apply fix using nvim_buf_set_text
	local function apply_fix(choice)
		-- nvim_buf_set_text uses 0-indexed line, 0-indexed column
		-- start and end_pos are 0-indexed in this function
		vim.api.nvim_buf_set_text(buf, cursor[1] - 1, start, cursor[1] - 1, end_pos, { choice })
		vim.api.nvim_win_set_cursor(0, { cursor[1], start + #choice })
		vim.defer_fn(function()
			M.validate_buffer(buf)
		end, 100)
		vim.notify("Fixed: " .. tag .. " -> " .. choice, vim.log.levels.INFO)
	end

	if #suggestions == 1 then
		apply_fix(suggestions[1])
		return
	end

	vim.ui.select(suggestions, {
		prompt = "Replace '" .. tag .. "' with:",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice then
			apply_fix(choice)
		end
	end)
end

-- List all invalid tags in buffer
-- List all invalid tags in buffer and populate quickfix
function M.list_invalid_tags()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local qf_list = {}

	for line_num, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= '' and trimmed ~= "|||" then
			if M.is_in_tags_section(buf, line_num - 1) then
				if not M.is_valid_tag(trimmed) then
					local col = line:find(trimmed) or 1
					local suggestions = M.suggest_tags(trimmed, 3)

					local text = "Invalid tag: " .. trimmed
					if #suggestions > 0 then
						text = text .. " (suggestions: " .. table.concat(suggestions, ", ") .. ")"
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
	end

	if #qf_list == 0 then
		vim.notify("All tags are valid!", vim.log.levels.INFO)
		return
	end

	-- Set quickfix list
	vim.fn.setqflist(qf_list, 'r')
	vim.cmd('copen')  -- Open quickfix window

	vim.notify("Found " .. #qf_list .. " invalid tags in quickfix list", vim.log.levels.WARN)
end

-- Fix all invalid tags in quickfix list
function M.fix_all_tags()
	local qf_list = vim.fn.getqflist()
	local fixed = 0

	for _, item in ipairs(qf_list) do
		local buf = item.bufnr
		local line_num = item.lnum
		local col = item.col

		if buf and vim.api.nvim_buf_is_valid(buf) then
			local lines = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)
			if #lines > 0 then
				local line = lines[1]
				-- Find the tag at the reported position
				local start = col - 1  -- 0-indexed
				local end_pos = start
				while end_pos < #line and line:sub(end_pos + 1, end_pos + 1):match("[%a%d_%s]") do
					end_pos = end_pos + 1
				end

				local tag = line:sub(start + 1, end_pos):match("^%s*(.-)%s*$")
				if tag then
					local suggestions = M.suggest_tags(tag, 1)
					if #suggestions > 0 then
						-- Fix the tag
						vim.api.nvim_buf_set_text(buf, line_num - 1, start, line_num - 1, end_pos, { suggestions[1] })
						fixed = fixed + 1
					end
				end
			end
		end
	end

	-- Re-validate the buffer
	if fixed > 0 then
		M.validate_buffer(buf)
		vim.notify("Fixed " .. fixed .. " invalid tags", vim.log.levels.INFO)
		-- Refresh quickfix list
		M.list_invalid_tags()
	else
		vim.notify("No tags could be fixed", vim.log.levels.WARN)
	end
end

return M
