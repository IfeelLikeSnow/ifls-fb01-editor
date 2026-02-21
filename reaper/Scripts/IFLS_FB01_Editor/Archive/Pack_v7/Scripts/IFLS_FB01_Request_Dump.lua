-- @description IFLS Workbench - Workbench/FB01/Pack_v7/Scripts/IFLS_FB01_Request_Dump.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Request_Dump.lua
-- Sends FB-01 dump requests via SWS (SNM_SendSysEx).
-- You must RECORD the incoming SysEx on a MIDI track (FB-01 MIDI OUT -> your MIDI IN).
--
-- Dump examples used here:
-- - Dump all config: F0 43 75 00 20 03 00 F7
-- - Dump voice bank 0: F0 43 75 00 20 00 00 F7
-- - Dump voice bank 1: F0 43 75 00 20 00 01 F7
--
-- Requires: SWS

local r = reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "IFLS FB-01 Dump Request", 0)
  return
end

local function hex_to_bytes(hex)
  local bytes = {}
  for b in hex:gmatch("%x%x") do
    bytes[#bytes+1] = string.char(tonumber(b,16))
  end
  return table.concat(bytes)
end

local function send(hex)
  r.SNM_SendSysEx(hex_to_bytes(hex))
end

local opts = "All Config,Voice Bank 0,Voice Bank 1"
local ok, choice = r.GetUserInputs("FB-01 Dump Request", 1, "Type (1=Config,2=VB0,3=VB1)", "1")
if not ok then return end
choice = tonumber(choice) or 1

if choice == 1 then
  send("F0 43 75 00 20 03 00 F7")
  r.MB("Requested: ALL CONFIG dump.\nNow record the incoming SysEx on a MIDI track.", "FB-01 Dump Request", 0)
elseif choice == 2 then
  send("F0 43 75 00 20 00 00 F7")
  r.MB("Requested: VOICE BANK 0 dump.\nNow record the incoming SysEx on a MIDI track.", "FB-01 Dump Request", 0)
else
  send("F0 43 75 00 20 00 01 F7")
  r.MB("Requested: VOICE BANK 1 dump.\nNow record the incoming SysEx on a MIDI track.", "FB-01 Dump Request", 0)
end
