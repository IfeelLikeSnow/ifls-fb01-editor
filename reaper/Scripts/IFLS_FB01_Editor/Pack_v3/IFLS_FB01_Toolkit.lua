-- @description IFLS Workbench - FB-01 Pack Redirect (Pack_v3)
-- @version 0.78.0
-- @author IfeelLikeSnow
--
-- This pack was archived to: Workbench/FB01/Archive/Pack_v3/
-- This stub keeps old toolbar/actions working.

local r = reaper

local function wb_root()
  return r.GetResourcePath().."/Scripts/IFLS FB-01 Editor"
end

local target = wb_root().."/Archive/Pack_v3/IFLS_FB01_Toolkit.lua"
local f = io.open(target, "rb")
if not f then
  r.MB("Archived pack target missing:\n"..target, "FB-01 Redirect", 0)
  return
end
f:close()

local ok, err = pcall(dofile, target)
if not ok then
  r.MB("Failed to run archived pack:\n"..tostring(err), "FB-01 Redirect", 0)
end
