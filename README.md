# caption-editor.nvim

Edit caption files with ease. Automatically splits sections into separate lines for easier editing, and joins them back when saving.

## Installation

### vim.pack (Neovim 0.12+)
```lua
vim.pack.add { gh 'uwidev/caption-editor.nvim' }
require('caption-editor').setup {
	keymaps = {
		toggle = "<leader>ce",
		fix_tag = "<leader>tf",
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
		tag_files = { "/path/to/danbooru_tags.txt" },
		auto_validate = true,
		show_suggestions = true,
		debounce_ms = 200,
		search_tool = "rg",
		force_spellcheck = nil,
		rank_method = "hybrid",
		max_candidates = 200,
		suggestion_cache_ttl = 300,
		suggestion_cache_limit = 100,
	},
}
```

### Lazy.nvim
```lua
{
	"uwidev/caption-editor.nvim",
	config = function()
		require('caption-editor').setup({
			keymaps = {
				toggle = "<leader>ce",
				fix_tag = "<leader>tf",
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
				tag_files = { "/path/to/danbooru_tags.txt" },
				auto_validate = true,
				show_suggestions = true,
				debounce_ms = 200,
				search_tool = "rg",
				force_spellcheck = nil,
				rank_method = "hybrid",
				max_candidates = 200,
				suggestion_cache_ttl = 300,
				suggestion_cache_limit = 100,
			},
		})
	end
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `keymaps.toggle` | `string` | `"<leader>ce"` | Keymap to toggle editor mode |
| `keymaps.fix_tag` | `string` | `"<leader>tf"` | Keymap to fix or suggest similar tag |
| `auto_split` | `boolean` | `true` | Auto-split when toggled on |
| `auto_unsplit` | `boolean` | `true` | Auto-unsplit when toggled off or buffer changes |
| `delimiter` | `string` | `","` | Delimiter for splitting tags |
| `space_after_delimiter` | `boolean` | `true` | Add space after delimiter when joining |
| `section_delimiter` | `string` | `"|||"` | Delimiter between sections |
| `section_types` | `table` | `{"tags", "tags", "nl"}` | Type for each section (`"tags"` or `"nl"`) |
| `tag_validation.enabled` | `boolean` | `false` | Enable tag validation |
| `tag_validation.tag_files` | `table` | `{}` | List of tag database file paths |
| `tag_validation.auto_validate` | `boolean` | `true` | Auto-validate on text changes |
| `tag_validation.show_suggestions` | `boolean` | `true` | Show suggestions in diagnostic messages |
| `tag_validation.debounce_ms` | `number` | `200` | Debounce delay in milliseconds |
| `tag_validation.search_tool` | `string` | `"rg"` | Tool to fetch candidates: `rg`, `grep`, `ag`, `ack`, `git grep` |
| `tag_validation.force_spellcheck` | `boolean` or `nil` | `nil` | `nil` = respect user, `true` = force on, `false` = force off |
| `tag_validation.rank_method` | `string` | `"hybrid"` | Ranking: `raw`, `levenshtein`, `token`, `hybrid` |
| `tag_validation.max_candidates` | `number` | `200` | Candidate pool size for ranking |
| `tag_validation.suggestion_cache_ttl` | `number` | `300` | Time-to-live for suggestion cache in seconds |
| `tag_validation.suggestion_cache_limit` | `number` | `100` | Max number of cached queries |

## Usage

Toggle editor mode on/off with `<leader>ce>`.

### Example

**Before:**
```
@my special tag ||| 1girl, solo, looking at viewer, short hair ||| A girl with short hair. She is looking at the viewer.
```

**After toggle:**
```
@my special tag
|||
1girl
solo
looking at viewer
short hair
|||
A girl with short hair.
She is looking at the viewer.
```

**After toggling off:**
```
@my special tag ||| 1girl, solo, looking at viewer, short hair ||| A girl with short hair. She is looking at the viewer.
```

### Section Types

- **`"tags"`**: Split by `delimiter`
- **`"nl"`**: Split by sentences (`.`, `!`, `?`)

### Tag Validation Commands

| Command/Keymap | Description |
|----------------|-------------|
| `<leader>tv` / `:CaptionValidateTags` | Validate tags and refresh quickfix list |
| `<leader>tf` / `:CaptionFixTag` | Fix tag under cursor (or suggest similar tags for any tag) |
| `:CaptionEditorClearCache` | Clear suggestion cache (useful after tag file update) |
| `:CaptionEditorReloadTags` | Reload tag files without restarting Neovim |

## Commands

- `:CaptionEditorToggle` - Toggle editor mode
- `:CaptionValidateTags` - Validate tags and refresh quickfix
- `:CaptionFixTag` - Fix tag under cursor (or suggest similar tags for any tag)
- `:CaptionEditorClearCache` - Clear suggestion cache
- `:CaptionEditorReloadTags` - Reload tag files

## Save Behavior

When the plugin is toggled on and you write (`:w`) the file, the plugin automatically:
- Unsplits the buffer (joins all lines into a single line)
- Writes the file (single-line format)
- Resplits the buffer back to multi-line view
- Refreshes the quickfix list (if open)

This ensures that the file is always saved in the correct single-line format, while you continue editing in the split view. No manual toggling off is required before saving.

## Notes

- Tags are loaded lazily (only on first validation/fix) to reduce startup overhead.
- Suggestion results are cached for faster repeated queries. Cache TTL and size are configurable.
- Multiple tag files can be provided; they are unioned for validation and suggestions.
- `<leader>tf` works on any tag (valid or invalid) to find similar tags.

---

**Disclaimer:** This plugin was created with the assistance of AI. While efforts have been made to ensure quality, use at your own risk. Please report any issues on the GitHub repository.
