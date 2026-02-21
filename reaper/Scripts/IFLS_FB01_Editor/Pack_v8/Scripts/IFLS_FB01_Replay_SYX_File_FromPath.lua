-- @description IFLS FB-01 - Replay SYX File (From Path)
-- @version 0.92.0
-- @author IFLS
-- @about
--   Reads a file path from ExtState IFLS_FB01/SYX_PATH and sends it via SWS SNM_SendSysEx.
--   Intended for integration with the Workbench FB-01 Library Browser.

local r = reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing).", "FB-01 Replay SYX FromPath", 0)
  return
end

local path = r.GetExtState("IFLS_FB01", "SYX_PATH")
if not path or path == "" then
  r.MB("No SYX_PATH in ExtState.", "FB-01 Replay SYX FromPath", 0)
  return
end

local f = io.open(path, "rb")
if not f then
  r.MB("Cannot open file:\n"..path, "FB-01 Replay SYX FromPath", 0)
  return
end
local data = f:read("*all")
f:close()

-- Optional simple chunking to reduce driver choke:
local CHUNK = 1024
if #data <= CHUNK then
  r.SNM_SendSysEx(data)
else
  local i=1
  while i <= #data do
    local chunk = data:sub(i, i+CHUNK-1)
    r.SNM_SendSysEx(chunk)
    r.Sleep(10)
    i = i + CHUNK
  end
end

r.MB("Sent SysEx from:\n"..path, "FB-01 Replay SYX FromPath", 0)
