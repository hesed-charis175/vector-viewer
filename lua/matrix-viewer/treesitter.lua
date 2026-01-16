-- treesitter helpers and literal parser
local M = {}

local ts_utils_ok, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
local parsers_ok, parsers = pcall(require, "nvim-treesitter.parsers")

-- Get raw text for a node
local function node_text(bufnr, node)
  local srow, scol, erow, ecol = node:range()
  local lines = vim.api.nvim_buf_get_lines(bufnr, srow, erow + 1, false)
  if #lines == 0 then return "" end
  lines[1] = string.sub(lines[1], scol + 1)
  lines[#lines] = string.sub(lines[#lines], 1, ecol)
  return table.concat(lines, "\n")
end

-- Try to find a relevant node near cursor: named variable with list initializer or an unnamed literal list
-- Returns { text = "<literal text>", lang = "python"/"cpp" }
function M.find_relevant_node(bufnr, row, col)
  local ft = vim.bo[bufnr].filetype
  local parser = parsers.get_parser(bufnr, ft)
  if not parser then return nil end
  local tree = parser:parse()[1]
  if not tree then return nil end
  local root = tree:root()
  local node = ts_utils.get_node_at_cursor()
  if not node then return nil end

  -- Helper to check python list literal and assignment
  if ft == "python" then
    -- If cursor on identifier which is left side of assignment with list on right
    local ancestor = node
    while ancestor do
      local t = ancestor:type()
      if t == "assignment" or t == "annassign" then
        -- assignment: targets and value
        for child in ancestor:iter_children() do
          if child:type() == "list" or child:type() == "atom" or child:type() == "testlist" then
            local text = node_text(bufnr, child)
            if text and string.find(text, "^%s*%[") then
              return { text = text, lang = "python", node = child }
            end
          end
        end
      end
      ancestor = ancestor:parent()
    end
    -- If cursor is on a list literal (unnamed)
    local cur = node
    while cur do
      if cur:type() == "list" or cur:type() == "atom" then
        local text = node_text(bufnr, cur)
        if text and string.find(text, "^%s*%[") then
          return { text = text, lang = "python", node = cur }
        end
      end
      cur = cur:parent()
    end
  end

  -- C/C++ heuristics
  if ft:match("^c") or ft == "cpp" or ft == "cxx" or ft == "c++" then
    local cur = node
    while cur do
      local t = cur:type()
      if t == "init_declarator" or t == "init_declarator_clause" or t == "declarator" then
        -- check children for brace init
        for child in cur:iter_children() do
          if child:type():match("initializer") or child:type() == "initializer_list" or child:type() == "braced_init_list" or child:type() == "init_list" then
            local text = node_text(bufnr, child)
            if text and (text:find("{") or text:find("%{")) then
              return { text = text, lang = "cpp", node = child }
            end
          end
        end
      end
      -- unnamed braced init somewhere near
      if t == "initializer_list" or t == "braced_init_list" or t == "init_list" then
        local text = node_text(bufnr, cur)
        if text and text:find("{") then
          return { text = text, lang = "cpp", node = cur }
        end
      end
      cur = cur:parent()
    end
  end

  return nil
end

-- Simple fallback: try to detect bracketed region at cursor char using text
function M.simple_fallback_find(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local ch = line:sub(col, col)
  if ch == "[" then
    -- try to extract until matching ]
    local txt = line:sub(col)
    return { text = txt, lang = "python" }
  elseif ch == "{" then
    local txt = line:sub(col)
    return { text = txt, lang = "cpp" }
  end
  return nil
end

-- Parse literal text (Python lists [..] or C++ braced {..}) into Lua table
-- This is a conservative parser (does not execute code). It handles numbers, quoted strings and nested lists/braces.
function M.parse_literal(text, lang)
  if not text or text == "" then return nil end
  local s = text
  local open_char = s:match("^%s*(%[)") or s:match("^%s*(%{)")
  if not open_char then
    -- try find first bracket
    local p = s:find("%[") or s:find("{")
    if not p then return nil end
    s = s:sub(p)
    open_char = s:sub(1,1)
  end
  local close_char = (open_char == "[" and "]") or "}"
  -- Basic tokenizer and recursive descent parse
  local i = 1
  local len = #s
  local function peek() return s:sub(i,i) end
  local function nextc() local c = s:sub(i,i); i = i + 1; return c end
  local function skip_ws()
    while i <= len and s:sub(i,i):match("%s") do i = i + 1 end
  end

  local function parse_value()
    skip_ws()
    if i > len then return nil end
    local c = peek()
    if c == '"' or c == "'" then
      local quote = nextc()
      local acc = {}
      while i <= len do
        local ch = nextc()
        if ch == quote then break end
        table.insert(acc, ch)
      end
      return table.concat(acc)
    elseif c == "[" or c == "{" then
      return parse_array()
    else
      -- parse number-like or bare token until comma or closing bracket
      local acc = {}
      while i <= len do
        local ch = peek()
        if ch == "," or ch == "]" or ch == "}" then break end
        if ch == "[" or ch == "{" then break end
        table.insert(acc, nextc())
      end
      local raw = vim.trim(table.concat(acc) or "")
      if raw == "" then return nil end
      -- try number
      local num = tonumber(raw)
      if num then return num end
      -- else return as string token (strip trailing commas/spaces)
      return raw
    end
  end

  function parse_array()
    local arr = {}
    local startc = nextc() -- consume [ or {
    while true do
      skip_ws()
      if i > len then break end
      local c = peek()
      if c == "]" or c == "}" then
        nextc()
        break
      elseif c == "," then
        nextc()
      else
        local v = parse_value()
        if v ~= nil then table.insert(arr, v) end
        skip_ws()
        local pc = peek()
        if pc == "," then nextc() end
      end
    end
    return arr
  end

  -- kick off parse
  local ok, result = pcall(function()
    i = 1
    return parse_array()
  end)
  if ok then return result end
  return nil
end

-- Normalize parsed result to a 2D matrix (array of rows, each row is an array)
-- If parsed is 1D (flat) -> single row. If parsed is 2D (each element is array) -> return as-is.
function M.normalize_to_2d(parsed)
  if type(parsed) ~= "table" then return nil end
  -- detect if elements are tables -> 2D
  local is2d = true
  for _, v in ipairs(parsed) do
    if type(v) ~= "table" then is2d = false; break end
  end
  if is2d then
    return parsed, #parsed
  else
    -- one row with all elements
    return { parsed }, 1
  end
end

return M