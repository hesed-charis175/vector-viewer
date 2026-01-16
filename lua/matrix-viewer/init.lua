-- matrix_viewer main module
local M = {}
local ts_parser_ok, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
local parsers_ok, parsers = pcall(require, "nvim-treesitter.parsers")
local ui = require("matrix_viewer.ui")
local ts = require("matrix_viewer.treesitter")

local config = {
  max_chars = 300,             -- don't show arrays whose serialized text > max_chars
  max_rows = 40,               -- max rows to display
  max_cols = 60,               -- max columns to display
  float_opts = {
    border = "rounded",
    offset = { row = 0, col = 1 }, -- show right beside cursor
    zindex = 50,
  },
  debounce_ms = 120,
  enabled_filetypes = { "python", "cpp", "c", "hpp", "cxx", "h", "cc" },
}

local timer = nil
local floating_win = nil

local function is_ft_allowed()
  local ft = vim.bo.filetype
  for _, f in ipairs(config.enabled_filetypes) do
    if f == ft then return true end
  end
  return false
end

local function show_for_node(bufnr, node_info)
  if not node_info then return end
  local text = node_info.text or ""
  if #text > config.max_chars then return end
  local ok, parsed = pcall(ts.parse_literal, text, node_info.lang)
  if not ok or not parsed then return end
  -- Convert parsed structure to a 2D matrix for display
  local matrix, rows = ts.normalize_to_2d(parsed)
  if not matrix or #matrix == 0 then return end
  if #matrix > config.max_rows then return end
  -- render
  floating_win = ui.open_matrix_win(matrix, config.float_opts, config)
end

local function clear_win()
  if floating_win and vim.api.nvim_win_is_valid(floating_win) then
    pcall(vim.api.nvim_win_close, floating_win, true)
  end
  floating_win = nil
end

local function on_cursor_moved()
  if not is_ft_allowed() then
    clear_win()
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  -- debounce
  if timer then timer:stop(); timer:close(); timer = nil end
  timer = vim.loop.new_timer()
  timer:start(config.debounce_ms, 0, vim.schedule_wrap(function()
    timer:stop(); timer:close(); timer = nil
    -- check if cursor is only on a variable name or literal
    local node_info = nil
    if parsers_ok and parsers.has_parser() and ts_parser_ok then
      node_info = ts.find_relevant_node(bufnr, row - 1, col)
    else
      node_info = ts.simple_fallback_find(bufnr, row - 1, col)
    end
    clear_win()
    if node_info then show_for_node(bufnr, node_info) end
  end))
end

--- Public setup
-- opts: override config
function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do config[k] = v end
  end
  -- setup autocmds
  vim.api.nvim_create_augroup("MatrixViewer", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "BufWinEnter" }, {
    group = "MatrixViewer",
    callback = function() on_cursor_moved() end,
  })
  -- close on buffer leave or moving
  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
    group = "MatrixViewer",
    callback = function() if floating_win then clear_win() end end,
  })
  -- tidy up on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = "MatrixViewer",
    callback = function() clear_win() end,
  })
end

return M