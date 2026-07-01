-- config.lua - Configuration management

local defaults = {
	keymaps = {
		toggle = "<leader>ce",
	},
	auto_split = true,
	auto_unsplit = true,
	delimiter = ",",
	space_after_delimiter = true,
	section_delimiter = "|||",
	section_types = {
		"tags",
		"tags",
		"nl",
	},
	tag_validation = {
		enabled = false,
		tag_file = "",
		auto_validate = true,
		show_suggestions = true,
		debounce_ms = 200,
		search_program = "rg",
		force_spellcheck = nil,  -- nil = respect user, true = force on, false = force off
	},
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

	if valid.space_after_delimiter ~= nil and type(valid.space_after_delimiter) ~= "boolean" then
		vim.notify("caption-editor: space_after_delimiter must be a boolean, using default", vim.log.levels.WARN)
		valid.space_after_delimiter = defaults.space_after_delimiter
	end

	if valid.section_delimiter and type(valid.section_delimiter) ~= "string" then
		vim.notify("caption-editor: section_delimiter must be a string, using default", vim.log.levels.WARN)
		valid.section_delimiter = defaults.section_delimiter
	end

	if valid.section_types then
		if type(valid.section_types) ~= "table" then
			vim.notify("caption-editor: section_types must be a table, using default", vim.log.levels.WARN)
			valid.section_types = defaults.section_types
		else
			for i, type in ipairs(valid.section_types) do
				if type ~= "tags" and type ~= "nl" then
					vim.notify(
						"caption-editor: section " .. i .. " has invalid type '" .. type .. "', using 'tags'",
						vim.log.levels.WARN
					)
					valid.section_types[i] = "tags"
				end
			end
		end
	end

	if valid.tag_validation then
		if valid.tag_validation.enabled ~= nil and type(valid.tag_validation.enabled) ~= "boolean" then
			vim.notify("caption-editor: tag_validation.enabled must be a boolean, using default", vim.log.levels.WARN)
			valid.tag_validation.enabled = defaults.tag_validation.enabled
		end

		if valid.tag_validation.tag_file and type(valid.tag_validation.tag_file) ~= "string" then
			vim.notify("caption-editor: tag_validation.tag_file must be a string, using default", vim.log.levels.WARN)
			valid.tag_validation.tag_file = defaults.tag_validation.tag_file
		end

		if valid.tag_validation.auto_validate ~= nil and type(valid.tag_validation.auto_validate) ~= "boolean" then
			vim.notify("caption-editor: tag_validation.auto_validate must be a boolean, using default", vim.log.levels.WARN)
			valid.tag_validation.auto_validate = defaults.tag_validation.auto_validate
		end

		if valid.tag_validation.show_suggestions ~= nil and type(valid.tag_validation.show_suggestions) ~= "boolean" then
			vim.notify("caption-editor: tag_validation.show_suggestions must be a boolean, using default", vim.log.levels.WARN)
			valid.tag_validation.show_suggestions = defaults.tag_validation.show_suggestions
		end

		if valid.tag_validation.debounce_ms and type(valid.tag_validation.debounce_ms) ~= "number" then
			vim.notify("caption-editor: tag_validation.debounce_ms must be a number, using default", vim.log.levels.WARN)
			valid.tag_validation.debounce_ms = defaults.tag_validation.debounce_ms
		end

		if valid.tag_validation.search_program and type(valid.tag_validation.search_program) ~= "string" then
			vim.notify("caption-editor: tag_validation.search_program must be a string, using default", vim.log.levels.WARN)
			valid.tag_validation.search_program = defaults.tag_validation.search_program
		end

		if valid.tag_validation.force_spellcheck ~= nil and type(valid.tag_validation.force_spellcheck) ~= "boolean" then
			vim.notify("caption-editor: tag_validation.force_spellcheck must be a boolean, using default", vim.log.levels.WARN)
			valid.tag_validation.force_spellcheck = defaults.tag_validation.force_spellcheck
		end
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
