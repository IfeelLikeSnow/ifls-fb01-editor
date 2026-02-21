-- @description IFLS FB-01 Toolkit (Pack v8)
-- @version 0.89.0
-- @author IFLS
-- @about
--   Launcher for FB-01 tools (Pack v8). Provides a simple menu to open common scripts.
--
-- Requirements:
--   - REAPER 6+
--   - (optional) SWS for shell-open conveniences

local r = reaper

local function wb_root()
  return r.GetResourcePath().."/Scripts/IFLS FB-01 Editor"
end

local function script(p)
  return wb_root().."/Pack_v8/Scripts/"..p
end

local function exists(p)
  local f=io.open(p,"rb"); if f then f:close(); return true end
  return false
end

local function run(p)
  if not exists(p) then
    r.MB("Missing script:\n"..p, "FB-01 Toolkit (v8)", 0)
    return
  end
  local ok,err = pcall(dofile, p)
  if not ok then r.MB("Script error:\n"..tostring(err), "FB-01 Toolkit (v8)", 0) end
end

local items = {
  {label="AutoDump: Record (SysEx)", file="IFLS_FB01_AutoDump_Record.lua"},
  {label="AutoDump: Record (Adaptive)", file="IFLS_FB01_AutoDump_Record_Adaptive.lua"},
  {label="Store Dump → ExtState (Project Recall)", file="IFLS_FB01_StoreDump_To_ExtState.lua"},
  {label="Replay Dump ← ExtState (Apply/Recall)", file="IFLS_FB01_ReplayDump_From_ExtState.lua"},
  {label="Replay .syx File (Safe)", file="IFLS_FB01_Replay_SYX_File_Safe.lua"},
  {label="Export selected SysEx item → .syx", file="IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua"},
  {label="Analyze selected SysEx item", file="IFLS_FB01_SysEx_Analyzer_SelectedItem.lua"},
}

local menu = "IFLS FB-01 Toolkit (Pack v8)|"
for i,it in ipairs(items) do
  menu = menu .. it.label .. (i<#items and "|" or "")
end

local choice = r.ShowMessageBox(
  "FB-01 Pack v8 tools launcher.\n\nChoose a tool from the next menu dialog.",
  "FB-01 Toolkit (v8)", 0
)
-- Always show menu; messagebox is informational only.

-- Use gfx menu for compatibility (no ReaImGui dependency)
gfx.init("FB-01 Toolkit (v8)", 0, 0, 0, 0)
local sel = gfx.showmenu(menu)
gfx.quit()
if sel and sel > 0 and items[sel] then
  run(script(items[sel].file))
end
