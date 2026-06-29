-- config.lua - Configuration management

local defaults = {
	keymaps = {
		toggle = "<leader>ce",  -- Caption Editor toggle
	},
	auto_split = true,  -- Auto-split when toggled on
	auto_unsplit = true,  -- Auto-unsplit when toggled off or buffer changes
	delimiter = ", ",  -- Delimiter for joining tags
}

local M = {}
M.options = vim.tbl_deep_extend("force", {}, defaults)

local function validate_config(opts)
	local valid = vim.tbl_deep_extend("force", {}, opts)

	if valid.keymaps and valid.keymaps.toggle and type(valid.keymaps.toggle) ~= "string" then
		vim.notify("caption-editor: keymaps.toggle must be a string, using default", vim.log.levels.WARN)
		valid.keymaps.toggle = defaults.keymaps.toggle
	end

	if valid.auto_split ~= nil and type(valid.auto_split) ~= "boolean" then
		vim.notify("caption-editor: auto_split must be a boolean, using default", vim.log.levels.WARN)
		valid.auto_split = defaults.auto_split
	end

	if valid.auto_unsplit ~= nil and type(valid.auto_unsplit) ~= "boolean" then
		vim.notify("caption-editor: auto_unsplit must be a boolean, using default", vim.log.levels.WARN)
		valid.auto_unsplit = defaults.auto_unsplit
	end

	if valid.delimiter and type(valid.delimiter) ~= "string" then
		vim.notify("caption-editor: delimiter must be a string, using default", vim.log.levels.WARN)
		valid.delimiter = defaults.delimiter
	end

	return valid
end

function M.setup(opts)
	local user_opts = validate_config(opts or {})
	M.options = vim.tbl_deep_extend("force", {}, defaults, user_opts)
end

function M.get()
	return vim.tbl_deep_extend("force", {}, M.options)
end

return M
