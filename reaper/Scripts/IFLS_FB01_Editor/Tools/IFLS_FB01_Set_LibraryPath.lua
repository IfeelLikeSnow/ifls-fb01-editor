-- @description IFLS FB-01 - Set Patch Library Path
-- @version 0.91.0
-- @author IFLS
-- @about
--   Sets ExtState IFLS_FB01/LIBRARY_PATH (optional). Leave blank to use default autodetected path.

local r = reaper
local ok, val = r.GetUserInputs("FB-01 Patch Library Path", 1, "Absolute path (blank=default)", r.GetExtState("IFLS_FB01","LIBRARY_PATH") or "")
if not ok then return end
if val == "" then
  r.SetExtState("IFLS_FB01","LIBRARY_PATH","", true)
  r.MB("Cleared override. Workbench will use default:\n"..(r.GetResourcePath().."/Scripts/IFLS_FB01_PatchLibrary"), "FB-01 Library Path", 0)
else
  r.SetExtState("IFLS_FB01","LIBRARY_PATH", val, true)
  r.MB("Set override to:\n"..val, "FB-01 Library Path", 0)
end
