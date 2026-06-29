-- editor.lua - Core editing logic

local M = {}
local config = require('caption-editor.config')

local state = {
	active = false,
	buf = nil,  -- Current buffer being edited
	original_content = nil,  -- Store original content for restore
}

-- Split tags into separate lines
local function split_tags(content, delimiter)
	if not content or content == '' then
		return {}
	end

	local tags = {}
	for tag in string.gmatch(content, "[^" .. delimiter .. "]+") do
		local cleaned = tag:match("^%s*(.-)%s*$")  -- Strip whitespace
		if cleaned and cleaned ~= '' then
			table.insert(tags, cleaned)
		end
	end
	return tags
end

-- Join tags back into single line
local function join_tags(tags, delimiter)
	if not tags or #tags == 0 then
		return ""
	end

	-- Strip whitespace from each tag
	local cleaned = {}
	for _, tag in ipairs(tags) do
		local stripped = tag:match("^%s*(.-)%s*$")
		if stripped and stripped ~= '' then
			table.insert(cleaned, stripped)
		end
	end

	return table.concat(cleaned, delimiter)
end

-- Get current buffer content
local function get_buffer_content(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return ""
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, "\n")
end

-- Set buffer content
local function set_buffer_content(buf, content)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local was_modifiable = vim.api.nvim_get_option_value('modifiable', { buf = buf })
	vim.api.nvim_set_option_value('modifiable', true, { buf = buf })

	local lines = {}
	for line in string.gmatch(content, "[^\n]*") do
		table.insert(lines, line)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_set_option_value('modifiable', was_modifiable, { buf = buf })
end

-- Check if buffer is a caption file
local function is_caption_file(buf)
	local filepath = vim.api.nvim_buf_get_name(buf)
	if filepath == '' then
		return false
	end
	local ext = vim.fn.fnamemodify(filepath, ':e'):lower()
	return ext == 'txt'
end

-- Split current buffer's tags into separate lines
local function split_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local opts = config.get()
	local content = get_buffer_content(buf)

	-- Check if content has commas
	if not content:find(",") then
		return  -- Already split or no commas
	end

	-- Store original content for restoration
	if not state.original_content then
		state.original_content = content
	end

	local tags = split_tags(content, opts.delimiter)
	local new_content = table.concat(tags, "\n")
	set_buffer_content(buf, new_content)

	vim.notify("caption-editor: Split tags into " .. #tags .. " lines", vim.log.levels.INFO)
end

-- Unsplit buffer back to single line
local function unsplit_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local opts = config.get()
	local content = get_buffer_content(buf)

	-- Check if content has newlines (already split)
	if not content:find("\n") then
		return  -- Already on single line
	end

	local tags = {}
	for line in string.gmatch(content, "[^\n]*") do
		local cleaned = line:match("^%s*(.-)%s*$")
		if cleaned and cleaned ~= '' then
			table.insert(tags, cleaned)
		end
	end

	local new_content = join_tags(tags, opts.delimiter)
	set_buffer_content(buf, new_content)
end

-- Toggle editing mode on/off
function M.toggle()
	local current_buf = vim.api.nvim_get_current_buf()

	-- If not in a caption file, do nothing
	if not is_caption_file(current_buf) then
		vim.notify("caption-editor: Not a caption file", vim.log.levels.WARN)
		return
	end

	if state.active then
		-- Turn off: unsplit if auto_unsplit is enabled
		local opts = config.get()
		if opts.auto_unsplit then
			unsplit_buffer(state.buf)
		end
		state.active = false
		state.buf = nil
		state.original_content = nil
		vim.notify("caption-editor: Disabled", vim.log.levels.INFO)
	else
		-- Turn on: split if auto_split is enabled
		local opts = config.get()
		state.buf = current_buf
		state.original_content = get_buffer_content(current_buf)

		if opts.auto_split then
			split_buffer(current_buf)
		end

		state.active = true
		vim.notify("caption-editor: Enabled", vim.log.levels.INFO)
	end
end

-- Handle buffer changes (unsplit old, split new)
function M.on_buffer_change()
	if not state.active then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()

	-- If we're already editing this buffer, do nothing
	if state.buf == current_buf then
		return
	end

	-- If not a caption file, do nothing
	if not is_caption_file(current_buf) then
		return
	end

	local opts = config.get()

	-- Unsplit the previous buffer
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) and opts.auto_unsplit then
		unsplit_buffer(state.buf)
	end

	-- Split the new buffer
	state.buf = current_buf
	state.original_content = get_buffer_content(current_buf)

	if opts.auto_split then
		split_buffer(current_buf)
	end

	vim.notify("caption-editor: Switched to " .. vim.api.nvim_buf_get_name(current_buf), vim.log.levels.INFO)
end

-- Handle buffer writes (unsplit before save, split after)
function M.on_buffer_write()
	if not state.active then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	if state.buf ~= current_buf then
		return
	end

	local opts = config.get()

	-- Get current content before unsplitting
	local content = get_buffer_content(current_buf)

	-- If content has newlines, unsplit for saving
	if content:find("\n") then
		unsplit_buffer(current_buf)
		-- Schedule resplit after save
		vim.defer_fn(function()
			if state.active and state.buf == current_buf and opts.auto_split then
				split_buffer(current_buf)
			end
		end, 50)
	end
end

-- Clean up on close
function M.on_buffer_delete(buf)
	if state.active and state.buf == buf then
		state.active = false
		state.buf = nil
		state.original_content = nil
		vim.notify("caption-editor: Disabled (buffer closed)", vim.log.levels.INFO)
	end
end

function M.get_state()
	return state
end

return M
