-- @description IFLS FB-01 - Send SysEx from ExtState (no UI)
-- @version 0.90.0
-- @author IFLS
-- @about
--   Internal helper for the Sound Editor: reads a framed SysEx message from ExtState and sends it via SWS SNM_SendSysEx.

local r = reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "FB-01 SysEx Send", 0)
  return
end

local NS = "IFLS_FB01"
local key = "SYSEX_PAYLOAD"
local msg = r.GetExtState(NS, key)
if not msg or msg == "" then
  r.MB("No SysEx payload in ExtState.", "FB-01 SysEx Send", 0)
  return
end

-- payload is stored as a binary string encoded as hex for safety
local function hex_to_bin(hex)
  hex = hex:gsub("%s+","")
  local out = {}
  for i=1,#hex,2 do
    local b = tonumber(hex:sub(i,i+1), 16)
    if b then out[#out+1] = string.char(b) end
  end
  return table.concat(out)
end

local bin = hex_to_bin(msg)
if #bin == 0 then
  r.MB("SysEx payload decoded to empty.", "FB-01 SysEx Send", 0)
  return
end

r.SNM_SendSysEx(bin)
