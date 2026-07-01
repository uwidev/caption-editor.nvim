# caption-editor.nvim

Edit caption files with ease. Automatically splits sections into separate lines for easier editing, and joins them back when saving.

## Installation

### vim.pack (Neovim 0.12+)
```lua
vim.pack.add { gh 'uwidev/caption-editor.nvim' }
require('caption-editor').setup {
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
| `auto_split` | `boolean` | `true` | Auto-split when toggled on |
| `auto_unsplit` | `boolean` | `true` | Auto-unsplit when toggled off or buffer changes |
| `delimiter` | `string` | `","` | Delimiter for splitting tags |
| `space_after_delimiter` | `boolean` | `true` | Add space after delimiter when joining |
| `section_delimiter` | `string` | `"|||"` | Delimiter between sections |
| `section_types` | `table` | `{"tags", "tags", "nl"}` | Type for each section (`"tags"` or `"nl"`) |
| `tag_validation.enabled` | `boolean` | `false` | Enable tag validation |
| `tag_validation.tag_file` | `string` | `""` | Path to danbooru tags file |
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
| `<leader>tf` / `:CaptionFixTag` | Fix tag under cursor |
| `:CaptionEditorClearCache` | Clear suggestion cache (useful after tag file update) |

## Commands

- `:CaptionEditorToggle` - Toggle editor mode
- `:CaptionValidateTags` - Validate tags and refresh quickfix
- `:CaptionFixTag` - Fix tag under cursor
- `:CaptionEditorClearCache` - Clear suggestion cache

## Notes

- Tags are loaded lazily (only on first validation/fix) to reduce startup overhead.
- Suggestion results are cached for faster repeated queries. Cache TTL and size are configurable.

---

**Disclaimer:** This plugin was created with the assistance of AI. While efforts have been made to ensure quality, use at your own risk. Please report any issues on the GitHub repository.
