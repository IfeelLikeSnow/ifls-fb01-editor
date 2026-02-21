-- ifls_fb01_paramschema.lua
-- Loads Data/IFLS_Workbench/FB01_param_schema_v1.json as Lua table.
local function script_path()
  local src = debug.getinfo(1, "S").source
  if src:sub(1,1) == "@" then src = src:sub(2) end
  return src
end

local function find_repo_root()
  local p = script_path():gsub("\\", "/")
  local root = p:match("^(.*)/Scripts/IFLS_Workbench/.*$")
  return root
end

local root = find_repo_root()
if not root then error("FB01 schema loader: could not locate repo root") end

local SlotCore = dofile(root .. "/Scripts/IFLS FB-01 Editor/Workbench/_Shared/IFLS_SlotCore.lua")
local schema_path = root .. "/Data/IFLS_Workbench/FB01_param_schema_v1.json"

local function load()
  local raw = SlotCore.read_all(schema_path)
  if not raw or raw == "" then return nil, "Schema JSON not found: " .. schema_path end
  local t = SlotCore.json_decode(raw)
  if type(t) ~= "table" then return nil, "Schema JSON decode failed" end
  return t
end

return { load = load, path = schema_path }
