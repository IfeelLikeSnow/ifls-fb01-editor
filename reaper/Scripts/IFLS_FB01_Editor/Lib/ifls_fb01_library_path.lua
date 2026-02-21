-- IFLS FB-01 Library Path Resolver
-- Determines where the external FB-01 patch library is located.

local r = reaper

local M = {}

-- ExtState override: IFLS_FB01 / LIBRARY_PATH
function M.get()
  local override = r.GetExtState("IFLS_FB01", "LIBRARY_PATH")
  if override and override ~= "" then return override end

  -- default install location
  local p = r.GetResourcePath().."/Scripts/IFLS_FB01_PatchLibrary"
  return p
end

function M.exists_dir(path)
  local ok = os.rename(path, path)
  if ok then return true end
  -- On Windows, os.rename fails for directories sometimes; fallback to trying to list
  local f = io.popen('cd "'..path..'" 2>nul && echo ok')
  if f then
    local out = f:read("*all") or ""
    f:close()
    return out:find("ok") ~= nil
  end
  return false
end

return M
