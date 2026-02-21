-- @description IFLS FB-01: Register Actions (one-time)
-- @version 0.1.0
-- @author IFLS
-- @about
--   Run once after installing via ReaPack. This registers the IFLS FB-01 actions into REAPER's Action List.

local r = reaper

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1,1) == "@" then src = src:sub(2) end
  return src:match("^(.*[\\/])") or ""
end

local function join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. "/" .. b
end

local function norm(p) return (p:gsub("\\","/")) end

local base = norm(script_dir()) -- .../Scripts/IFLS FB-01 Editor/
local actions = norm(join(base, "Actions"))

local to_add = {
  join(actions, "IFLS_FB01_Open_Editor.lua"),
  join(actions, "IFLS_FB01_Open_AutoCalibration.lua"),
  join(actions, "IFLS_FB01_Setup_Tracks.lua"),
  join(actions, "IFLS_FB01_Panic_AllNotesOff.lua"),
}

local ok = 0
for i=1,#to_add do
  local cmd = r.AddRemoveReaScript(true, 0, to_add[i], i == #to_add)
  if cmd and cmd ~= 0 then ok = ok + 1 end
end

r.ShowMessageBox(("Registered %d/%d IFLS FB-01 actions.\n\nNow open Actions list and search: IFLS FB-01\nYou can add them to a toolbar."):format(ok, #to_add), "IFLS FB-01", 0)
