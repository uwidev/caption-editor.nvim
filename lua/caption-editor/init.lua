-- init.lua - Main entry point

local config = require("caption-editor.config")
local editor = require("caption-editor.editor")
local tags = require("caption-editor.tags")

local M = {}

function M.setup(opts)
	config.setup(opts)

	local opts_config = config.get()

	-- Load tag validation
	if opts_config.tag_validation and opts_config.tag_validation.enabled then
		local tag_file = opts_config.tag_validation.tag_file
		if tag_file and tag_file ~= "" then
			tags.load_tags(tag_file)

			-- Validation autocmds (with buffer validation)
			if opts_config.tag_validation and opts_config.tag_validation.enabled then
				if opts_config.tag_validation.auto_validate ~= false then
					vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
						group = group,
						callback = function()
							local state = editor.get_state()
							if state.active then
								local buf = vim.api.nvim_get_current_buf()
								local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
								local filepath = vim.api.nvim_buf_get_name(buf)
								local ext = vim.fn.fnamemodify(filepath, ":e"):lower()

								if buftype == "" and filepath ~= "" and ext == "txt" then
									tags.schedule_validate(buf)
								end
							end
						end,
					})
				end
			end
		end
	end

	-- Create user commands
	vim.api.nvim_create_user_command("CaptionEditorToggle", editor.toggle, {})
	vim.api.nvim_create_user_command("CaptionValidateTags", function()
		tags.refresh_all()
	end, {})
	vim.api.nvim_create_user_command("CaptionFixTag", tags.fix_tag, {})

	-- Create keymaps
	local keymaps = opts_config.keymaps or {}

	if keymaps.toggle then
		vim.api.nvim_set_keymap("n", keymaps.toggle, ":CaptionEditorToggle<CR>", {
			silent = true,
			noremap = true,
			desc = "Toggle caption editor mode",
		})
	end

	-- Validation keymaps (only if enabled)
	if opts_config.tag_validation and opts_config.tag_validation.enabled then
		vim.api.nvim_set_keymap("n", "<leader>tv", ":CaptionValidateTags<CR>", {
			silent = true,
			noremap = true,
			desc = "Validate tags (quickfix)",
		})

		vim.api.nvim_set_keymap("n", "<leader>tf", ":CaptionFixTag<CR>", {
			silent = true,
			noremap = true,
			desc = "Fix tag under cursor",
		})
	end

	-- Set up editor autocommands
	local group = vim.api.nvim_create_augroup("CaptionEditor", { clear = true })

	-- Consolidated: State sync on buffer enter AND text changes (handles undo in same buffer)
	vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "*.txt",
		callback = function()
			local current_buf = vim.api.nvim_get_current_buf()
			if current_buf then
				editor.sync_state(current_buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = "*.txt",
		callback = function()
			editor.on_buffer_change()
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePre", {
		group = group,
		pattern = "*.txt",
		callback = function()
			editor.on_buffer_write()
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			editor.on_buffer_delete(tonumber(args.buf))
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if editor.get_state().active then
				local state = editor.get_state()
				if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
					require("caption-editor.editor").on_buffer_change()
				end
			end
		end,
	})
end

M.config = config
M.editor = editor
M.tags = tags

return M
