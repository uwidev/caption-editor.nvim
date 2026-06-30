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

## Commands

- `:CaptionEditorToggle` - Toggle editor mode
