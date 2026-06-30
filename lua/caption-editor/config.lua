-- config.lua - Configuration management

local defaults = {
	keymaps = {
		toggle = "<leader>ce",  -- Caption Editor toggle
	},
	auto_split = true,          -- Auto-split when toggled on
	auto_unsplit = true,        -- Auto-unsplit when toggled off or buffer changes
	delimiter = ",",            -- Delimiter for splitting tags
	space_after_delimiter = true, -- Add space after delimiter when joining
	section_delimiter = "|||",  -- Delimiter between sections
	section_types = {           -- Define type for each section (1-indexed)
		"tags",  -- Section 1: tags
		"tags",  -- Section 2: tags
		"nl",    -- Section 3: natural language passage
		-- Sections 4+ default to "tags"
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
