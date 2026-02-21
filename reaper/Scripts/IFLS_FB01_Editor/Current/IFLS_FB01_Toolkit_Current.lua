-- @description IFLS Workbench - FB-01 Toolkit (Current)
-- @version 0.77.0
-- @author IfeelLikeSnow
--
-- Stable entry point that forwards to the current FB-01 toolset.
-- Currently forwards to: Workbench/FB01/Pack_v8/IFLS_FB01_Toolkit.lua

local r = reaper

local function wb_root()
  return r.GetResourcePath().."/Scripts/IFLS FB-01 Editor"
end

local target = wb_root().."/Pack_v8/IFLS_FB01_Toolkit.lua"
local f = io.open(target,"rb")
if not f then
  r.MB("Missing current FB-01 toolkit:\n"..target, "FB-01 Current", 0)
  return
end
f:close()

local ok, err = pcall(dofile, target)
if not ok then
  r.MB("Failed to run current FB-01 toolkit:\n"..tostring(err), "FB-01 Current", 0)
end


-- V89_GUARD
-- If v8 toolkit is missing, fallback to Pack_v7 toolkit.
