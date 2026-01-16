# matrix-viewer

Neovim plugin (Lua) that shows a small overlay with an array/matrix when the cursor is on:
- the variable name of a vector/list that has an initializer (named vector),
- or when the cursor is on an unnamed list/initializer literal.

It supports:
- Python lists (1D and nested 2D)
- C/C++ braced initializer lists (1D and nested 2D)

Features:
- Uses nvim-treesitter when available for accurate detection.
- Floating overlay appears to the right of the cursor and renders the data in a simple monospaced table.
- Debounced to avoid excessive popups.
- Lazy-compatible: call require("matrix_viewer").setup() in your config.

Installation (lazy.nvim)
Example:
```lua
-- in your lazy spec list
{
  "yourusername/matrix-viewer", -- replace with repo path or local plugin path
  config = function()
    require("matrix_viewer").setup({
      -- optional overrides
      max_chars = 400,
      enabled_filetypes = { "python", "cpp" },
    })
  end,
}
```

Usage:
- Put the cursor on an identifier that was assigned a list/initializer:
  - Python: `arr = [1, 2, 3]` -> put cursor over `arr`
  - C++: `std::vector<int> v = {1,2,3}` or `auto v = { {1,2}, {3,4} }` -> put cursor over `v`
- Or put the cursor on a list literal itself (unnamed list/initializer).
- The overlay will appear automatically (CursorMoved event; debounced).

Notes & Limitations:
- The parser is conservative: it does not evaluate code and only parses textual list/brace literals (numbers, quoted strings, nested lists/braces).
- Complex expressions inside initializers (function calls, macros, expressions) will be shown as their textual tokens where possible but the plugin does not run user code.
- Very large arrays are truncated by default (max_chars/max_rows/max_cols). Tweak via setup().
- Treesitter grammars vary; the plugin uses heuristics for C++/Python to detect initializer lists and assignments. If you notice cases not detected, please open an issue with an example snippet.

License: MIT