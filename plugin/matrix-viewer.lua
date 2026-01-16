-- Minimal loader so that when plugin is installed it can optionally auto-configure.
-- It only sets up with defaults. Users can also call require('matrix_viewer').setup() manually.
local ok, mv = pcall(require, "matrix_viewer")
if ok and mv and type(mv.setup) == "function" then
  -- do not auto-setup to avoid surprising behavior in some plugin managers.
  -- If you want auto-setup, uncomment the next line:
  -- mv.setup()
end