# caption-editor.nvim

Edit caption files with ease. Automatically splits comma-separated tags into separate lines for easier editing, and joins them back when saving.

## Features

- **Toggle On/Off**: Split tags into lines for easy editing
- **Auto-split**: Automatically split when toggled on
- **Auto-unsplit**: Automatically unsplit when toggled off
- **Buffer Switching**: Unsplit old buffer, split new buffer
- **Save Handling**: Unsplit before save, resplit after
- **Tag Cleaning**: Strip whitespace from tags

## Installation

### Lazy.nvim

```lua
{
    "uwidev/caption-editor.nvim",
    config = function()
        require('caption-editor').setup({
            keymaps = {
                toggle = "<leader>ce",
            },
            delimiter = ", ",
            auto_split = true,
            auto_unsplit = true,
        })
    end
}
