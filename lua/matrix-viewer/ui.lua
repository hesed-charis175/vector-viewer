-- UI helper: create floating window and render a matrix nicely
local M = {}

local function pad(s, w)
  s = tostring(s)
  if #s >= w then return s end
  return s .. string.rep(" ", w - #s)
end

local function compute_col_widths(matrix)
  local cols = 0
  for _, row in ipairs(matrix) do
    if #row > cols then cols = #row end
  end
  local widths = {}
  for c = 1, cols do widths[c] = 0 end
  for _, row in ipairs(matrix) do
    for c = 1, cols do
      local v = row[c] or ""
      local len = #tostring(v)
      if len > widths[c] then widths[c] = len end
    end
  end
  return widths
end

local function build_lines(matrix)
  local widths = compute_col_widths(matrix)
  local lines = {}
  for _, row in ipairs(matrix) do
    local parts = {}
    for c = 1, #widths do
      local v = row[c] or ""
      table.insert(parts, pad(v, widths[c]))
    end
    table.insert(lines, table.concat(parts, "  "))
  end
  return lines
end

-- open floating window near cursor
-- float_opts: { border = "rounded", offset = { row = 0, col = 1 }, zindex = 50 }
function M.open_matrix_win(matrix, float_opts, config)
  local lines = build_lines(matrix)
  -- sanitize size limit
  if #lines == 0 then return end
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local width = 0
  for _, l in ipairs(lines) do if #l > width then width = #l end end
  local height = #lines
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local opts = {
    relative = "cursor",
    row = float_opts.offset and (float_opts.offset.row or 0) or 0,
    col = float_opts.offset and (float_opts.offset.col or 1) or 1,
    anchor = "NW",
    width = math.min(width, config.max_cols),
    height = math.min(height, config.max_rows),
    style = "minimal",
    border = float_opts.border or nil,
    zindex = float_opts.zindex or 50,
  }
  local win = vim.api.nvim_open_win(bufnr, false, opts)
  -- set highlights
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "matrixviewer")
  return win
end

return M