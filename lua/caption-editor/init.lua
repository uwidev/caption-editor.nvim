-- init.lua - Main entry point

local config = require('caption-editor.config')
local editor = require('caption-editor.editor')

local M = {}

function M.setup(opts)
	config.setup(opts)

	-- Create user commands
	vim.api.nvim_create_user_command("CaptionEditorToggle", editor.toggle, {})

	-- Create keymaps
	local opts_config = config.get()
	local keymaps = opts_config.keymaps or {}

	if keymaps.toggle then
		vim.api.nvim_set_keymap("n", keymaps.toggle, ":CaptionEditorToggle<CR>", {
			silent = true,
			noremap = true,
			desc = "Toggle caption editor mode",
		})
	end

	-- Set up autocommands
	local group = vim.api.nvim_create_augroup('CaptionEditor', { clear = true })

	-- Handle buffer changes
	vim.api.nvim_create_autocmd('BufEnter', {
		group = group,
		pattern = '*.txt',
		callback = function()
			editor.on_buffer_change()
		end,
	})

	-- Handle writes (save)
	vim.api.nvim_create_autocmd('BufWritePre', {
		group = group,
		pattern = '*.txt',
		callback = function()
			editor.on_buffer_write()
		end,
	})

	-- Handle buffer deletion
	vim.api.nvim_create_autocmd('BufDelete', {
		group = group,
		callback = function(args)
			editor.on_buffer_delete(tonumber(args.buf))
		end,
	})

	-- Handle Vim leaving
	vim.api.nvim_create_autocmd('VimLeavePre', {
		group = group,
		callback = function()
			if editor.get_state().active then
				-- Unsplit before exit
				local state = editor.get_state()
				if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
					require('caption-editor.editor').on_buffer_change()
				end
			end
		end,
	})
end

M.config = config
M.editor = editor

return M
