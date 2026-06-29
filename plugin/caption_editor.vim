" caption_editor.vim - Load the plugin

if exists('g:loaded_caption_editor')
    finish
endif
let g:loaded_caption_editor = 1

lua require('caption-editor')
