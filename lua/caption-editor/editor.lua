-- editor.lua - Core editing logic

local M = {}
local config = require("caption-editor.config")

vim.g.caption_editor_invalid_count = 0

local state = {
	active = false,
	buf = nil,
	original_content = nil,
	saving = false,
}

-- Table to store prefixed buffers and their original names + last count
-- key: buffer number, value: { orig_name, last_count }
local prefixed_buffers = {}

-- Restore original name for all prefixed buffers
local function restore_all_prefixed_buffers()
	for buf, data in pairs(prefixed_buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(function()
				vim.api.nvim_buf_set_name(buf, data.orig_name)
			end)
		end
	end
	prefixed_buffers = {}
end

-- Temporarily restore original names for all prefixed buffers (for saving)
local function restore_original_names_for_write()
	for buf, data in pairs(prefixed_buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(function()
				vim.api.nvim_buf_set_name(buf, data.orig_name)
			end)
		end
	end
end

-- Reapply prefixed names after write
local function reapply_prefixed_names()
	for buf, data in pairs(prefixed_buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(function()
				local tail = vim.fn.fnamemodify(data.orig_name, ":t")
				local count = vim.g.caption_editor_invalid_count or 0
				local opts = config.get()
				local show_count = opts.tag_validation and opts.tag_validation.show_invalid_count or true
				local new_name
				if show_count and count > 0 then
					new_name = "[CE: " .. count .. "] " .. tail
				elseif show_count and count == 0 then
					new_name = "[CE: ✓] " .. tail
				else
					new_name = "[CE] " .. tail
				end
				vim.api.nvim_buf_set_name(buf, new_name)
				prefixed_buffers[buf].last_count = count
			end)
		end
	end
end

-- Set buffer name with indicator
local function set_buffer_name(buf, active)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local current = vim.api.nvim_buf_get_name(buf)
	if current == "" then
		return
	end

	if not active then
		local data = prefixed_buffers[buf]
		if data then
			vim.api.nvim_buf_set_name(buf, data.orig_name)
			prefixed_buffers[buf] = nil
		else
			local stripped = current:gsub("^%[CE[^]]*%] ", "")
			if stripped ~= current then
				vim.api.nvim_buf_set_name(buf, stripped)
			end
		end
		return
	end

	if not prefixed_buffers[buf] then
		local stripped = current:gsub("^%[CE[^]]*%] ", "")
		prefixed_buffers[buf] = { orig_name = stripped, last_count = 0 }
	end

	local data = prefixed_buffers[buf]
	local orig_path = data.orig_name
	local tail = vim.fn.fnamemodify(orig_path, ":t")
	local count = vim.g.caption_editor_invalid_count or 0
	local opts = config.get()
	local show_count = opts.tag_validation and opts.tag_validation.show_invalid_count or true

	local new_name
	if show_count and count > 0 then
		new_name = "[CE: " .. count .. "] " .. tail
	elseif show_count and count == 0 then
		new_name = "[CE: ✓] " .. tail
	else
		new_name = "[CE] " .. tail
	end

	if current ~= new_name or data.last_count ~= count then
		vim.api.nvim_buf_set_name(buf, new_name)
		data.last_count = count
	end
end

-- Generic split function
local function split(content, delimiter, keep_empty)
	if not content then
		return {}
	end

	if keep_empty == nil then
		keep_empty = true
	end

	local parts = {}
	local start = 1
	local delim_len = #delimiter

	if content == "" then
		if keep_empty then
			return { "" }
		end
		return {}
	end

	while true do
		local pos = content:find(delimiter, start, true)
		if not pos then
			local part = content:sub(start)
			if keep_empty then
				table.insert(parts, part)
			else
				local cleaned = part:match("^%s*(.-)%s*$")
				if cleaned and cleaned ~= "" then
					table.insert(parts, cleaned)
				end
			end
			break
		else
			local part = content:sub(start, pos - 1)
			if keep_empty then
				table.insert(parts, part)
			else
				local cleaned = part:match("^%s*(.-)%s*$")
				if cleaned and cleaned ~= "" then
					table.insert(parts, cleaned)
				end
			end
			start = pos + delim_len
		end
	end

	return parts
end

-- Split text by sentences (., !, ?)
local function split_sentences(text)
	if not text or text == "" then
		return {}
	end

	if not text:find("[.!?]") then
		local cleaned = text:match("^%s*(.-)%s*$")
		return cleaned and cleaned ~= "" and { cleaned } or {}
	end

	local sentences = {}
	local current = ""
	local i = 1

	while i <= #text do
		local char = text:sub(i, i)

		if char:match("[.!?]") then
			local prev_char = i > 1 and text:sub(i - 1, i - 1) or ""
			local next_char = i < #text and text:sub(i + 1, i + 1) or ""

			if prev_char:match("%d") and next_char:match("%d") then
				current = current .. char
				i = i + 1
			else
				current = current .. char
				local cleaned = current:match("^%s*(.-)%s*$")
				if cleaned and cleaned ~= "" then
					table.insert(sentences, cleaned)
				end
				current = ""
				i = i + 1

				while i <= #text and text:sub(i, i):match("%s") do
					i = i + 1
				end
			end
		else
			current = current .. char
			i = i + 1
		end
	end

	if current ~= "" then
		local cleaned = current:match("^%s*(.-)%s*$")
		if cleaned and cleaned ~= "" then
			table.insert(sentences, cleaned)
		end
	end

	if #sentences == 0 and text ~= "" then
		local cleaned = text:match("^%s*(.-)%s*$")
		return cleaned and cleaned ~= "" and { cleaned } or {}
	end

	return sentences
end

-- Join sentences
local function join_sentences(sentences)
	if not sentences or #sentences == 0 then
		return ""
	end

	local cleaned = {}
	for _, s in ipairs(sentences) do
		local stripped = s:match("^%s*(.-)%s*$")
		if stripped and stripped ~= "" then
			table.insert(cleaned, stripped)
		end
	end

	return table.concat(cleaned, " ")
end

-- Split tags by delimiter
local function split_tags(content, delimiter)
	if content == nil or content == "" then
		return {}
	end

	local raw_tags = split(content, delimiter, true)
	local tags = {}
	for _, tag in ipairs(raw_tags) do
		local cleaned = tag:match("^%s*(.-)%s*$")
		if cleaned and cleaned ~= "" then
			table.insert(tags, cleaned)
		end
	end
	return tags
end

-- Join tags
local function join_tags(tags, delimiter, space_after)
	if not tags or #tags == 0 then
		return ""
	end

	local cleaned = {}
	for _, tag in ipairs(tags) do
		local stripped = tag:match("^%s*(.-)%s*$")
		if stripped and stripped ~= "" then
			table.insert(cleaned, stripped)
		end
	end

	local join_str = delimiter
	if space_after then
		join_str = delimiter .. " "
	end

	return table.concat(cleaned, join_str)
end

-- Get section type
local function get_section_type(index, section_types)
	if not section_types or #section_types == 0 then
		return "tags"
	end

	if index <= #section_types then
		return section_types[index]
	end

	return "tags"
end

-- Split a section based on its type
local function split_section(section, section_type, delimiter)
	if section_type == "nl" then
		return split_sentences(section)
	else
		return split_tags(section, delimiter)
	end
end

-- Join a section based on its type
local function join_section(section, section_type, delimiter, space_after)
	if section_type == "nl" then
		return join_sentences(section)
	else
		return join_tags(section, delimiter, space_after)
	end
end

-- Get buffer content
local function get_buffer_content(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return ""
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, "\n")
end

-- Set buffer content
local function set_buffer_content(buf, content, no_undo)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	local lines = {}
	for line in content:gmatch("[^\n]*") do
		if line ~= "" then
			table.insert(lines, line)
		end
	end

	if no_undo then
		pcall(vim.cmd, "undojoin")
	end

	if #lines == 0 then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
	else
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end

	vim.api.nvim_set_option_value("modifiable", was_modifiable, { buf = buf })
end

-- Create an undo marker that the split/unsplit can join with
local function create_undo_marker(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local changedtick = vim.api.nvim_buf_get_changedtick(buf)
	if changedtick == 0 then
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		if #lines > 0 then
			local line = lines[1] or ""
			vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line .. " " })
			pcall(vim.cmd, "undojoin")
			vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line })
		end
	end
end

-- Check if caption file (uses original name from prefixed_buffers if available)
local function is_caption_file(buf)
	local filepath
	local data = prefixed_buffers[buf]
	if data then
		filepath = data.orig_name
	else
		filepath = vim.api.nvim_buf_get_name(buf)
	end
	if filepath == "" then
		return false
	end
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	return ext == "txt"
end

-- Check if section is empty
local function is_empty_section(section)
	if not section then
		return true
	end
	local trimmed = section:match("^%s*(.-)%s*$")
	return trimmed == nil or trimmed == ""
end

-- Check if buffer content is in split format (multi-line)
local function is_buffer_split(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines == 0 then
		return false
	end

	local content = table.concat(lines, "\n")
	return content:find("\n") ~= nil
end

-- Sync state with buffer content
function M.sync_state(buf)
	if state.saving then
		return
	end

	if not buf then
		buf = vim.api.nvim_get_current_buf()
	end

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	if not is_caption_file(buf) then
		return
	end

	if buf ~= state.buf then
		return
	end

	local is_split = is_buffer_split(buf)

	if state.active and not is_split then
		state.active = false
		state.buf = nil
		state.original_content = nil

		restore_all_prefixed_buffers()
		vim.g.caption_editor_invalid_count = 0

		local tags = require("caption-editor.tags")
		tags.clear_all_diagnostics(buf)
		tags.close_quickfix()
	end
end

-- Split buffer
local function split_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local opts = config.get()
	local content = get_buffer_content(buf)
	if content:sub(-1) == "\n" then
		content = content:sub(1, -2)
	end

	if content == "" then
		return
	end

	if not state.original_content then
		state.original_content = content
	end

	local lines = {}
	local raw_sections = split(content, opts.section_delimiter, true)
	local sections = {}
	for _, section in ipairs(raw_sections) do
		local cleaned = section:match("^%s*(.-)%s*$")
		if cleaned ~= nil then
			table.insert(sections, cleaned)
		else
			table.insert(sections, "")
		end
	end

	local num_sections = #sections

	for i, section in ipairs(sections) do
		local is_empty = is_empty_section(section)
		local section_type = get_section_type(i, opts.section_types)

		if not is_empty then
			local items = split_section(section, section_type, opts.delimiter)
			for _, item in ipairs(items) do
				table.insert(lines, item)
			end
		end

		if i < num_sections then
			table.insert(lines, opts.section_delimiter)
		end
	end

	while #lines > 0 and lines[#lines] == opts.section_delimiter do
		table.remove(lines)
	end

	local new_content = table.concat(lines, "\n")
	set_buffer_content(buf, new_content, true)
end

-- Unsplit buffer
local function unsplit_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local opts = config.get()
	local content = get_buffer_content(buf)
	if content:sub(-1) == "\n" then
		content = content:sub(1, -2)
	end

	if content == "" then
		return
	end

	local lines = {}
	for line in content:gmatch("[^\n]*") do
		table.insert(lines, line)
	end

	if #lines == 0 then
		set_buffer_content(buf, "", true)
		return
	end

	local sections = {}
	local current_section = {}

	for _, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed == opts.section_delimiter then
			table.insert(sections, current_section)
			current_section = {}
		else
			table.insert(current_section, line)
		end
	end
	table.insert(sections, current_section)

	local parts = {}

	for i, section in ipairs(sections) do
		local is_empty = true
		for _, line in ipairs(section) do
			local trimmed = line:match("^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" then
				is_empty = false
				break
			end
		end

		local section_type = get_section_type(i, opts.section_types)

		if not is_empty then
			local joined = join_section(section, section_type, opts.delimiter, opts.space_after_delimiter)
			table.insert(parts, joined)
		else
			table.insert(parts, "")
		end
	end

	local section_join_str = " " .. opts.section_delimiter .. " "
	local new_content = table.concat(parts, section_join_str)

	set_buffer_content(buf, new_content, true)
end

function M.toggle()
	local current_buf = vim.api.nvim_get_current_buf()

	if not is_caption_file(current_buf) then
		return
	end

	M.sync_state(current_buf)

	if state.active then
		local opts = config.get()

		create_undo_marker(state.buf)

		if opts.auto_unsplit then
			unsplit_buffer(state.buf)
		end

		local tags = require("caption-editor.tags")
		tags.clear_all_diagnostics(state.buf)
		tags.close_quickfix()

		restore_all_prefixed_buffers()
		vim.g.caption_editor_invalid_count = 0

		state.active = false
		state.buf = nil
		state.original_content = nil
	else
		local opts = config.get()

		create_undo_marker(current_buf)

		state.buf = current_buf
		state.original_content = get_buffer_content(current_buf)

		if opts.auto_split then
			split_buffer(current_buf)
		end

		state.active = true

		local tags = require("caption-editor.tags")
		tags.validate_buffer(current_buf)
		M.update_buffer_display(current_buf)
	end
end

function M.on_buffer_change()
	if not state.active then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()

	if state.buf == current_buf then
		return
	end

	if not is_caption_file(current_buf) then
		return
	end

	local opts = config.get()

	if state.buf and vim.api.nvim_buf_is_valid(state.buf) and opts.auto_unsplit then
		unsplit_buffer(state.buf)
	end

	state.buf = current_buf
	state.original_content = get_buffer_content(current_buf)

	if opts.auto_split then
		split_buffer(current_buf)
	end

	local tags = require("caption-editor.tags")
	tags.validate_buffer(current_buf)
	M.update_buffer_display(current_buf)
end

function M.on_buffer_write()
	if not state.active then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	if state.buf ~= current_buf then
		return
	end

	state.saving = true

	local opts = config.get()
	local content = get_buffer_content(current_buf)

	if content:find("\n") then
		local view = vim.fn.winsaveview()

		restore_original_names_for_write()

		unsplit_buffer(current_buf)

		vim.schedule(function()
			if state.active then
				reapply_prefixed_names()
			end
			if state.active and state.buf == current_buf and opts.auto_split then
				split_buffer(current_buf)
				vim.fn.winrestview(view)
			end
			state.saving = false
		end)
	else
		state.saving = false
	end
end

function M.on_buffer_delete(buf)
	if state.active and state.buf == buf then
		state.active = false
		state.buf = nil
		state.original_content = nil
	end

	if prefixed_buffers[buf] then
		prefixed_buffers[buf] = nil
	end
end

function M.get_state()
	return state
end

function M.get_status()
	return state.active and "[CE]" or ""
end

function M.update_winbar()
	if not config.get().tag_validation.show_status then
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	if not is_caption_file(buf) then
		vim.opt_local.winbar = ""
		return
	end

	if state.active then
		vim.opt_local.winbar = "[CE]"
	else
		vim.opt_local.winbar = ""
	end
end

function M.update_buffer_display(buf)
	if not buf then
		buf = vim.api.nvim_get_current_buf()
	end
	if state.active then
		set_buffer_name(buf, true)
	else
		set_buffer_name(buf, false)
	end
end

return M
