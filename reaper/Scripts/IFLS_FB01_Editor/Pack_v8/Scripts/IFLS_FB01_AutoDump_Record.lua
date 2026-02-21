-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_AutoDump_Record.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_AutoDump_Record.lua
-- Requests an FB-01 dump via SysEx and starts REAPER recording for N seconds,
-- so the incoming SysEx lands in a MIDI item.
--
-- Requires: SWS for SNM_SendSysEx (sending). Recording works regardless.

local r = reaper
local DevPorts=nil
pcall(function() DevPorts=dofile(r.GetResourcePath().."/Scripts/IFLS FB-01 Editor/Workbench/MIDINetwork/Lib/IFLS_DevicePortDefaults.lua") end)


local function hex_to_bytes(hex)
  local bytes = {}
  for b in hex:gmatch("%x%x") do
    bytes[#bytes+1] = string.char(tonumber(b,16))
  end
  return table.concat(bytes)
end

local function send_sysex_hex(hex)
  if DevPorts and DevPorts.get_out_idx then
  if (out_dev == nil) and (device_out == nil) then
    local d = DevPorts.get_out_idx("fb01")
    if d then out_dev = d; device_out = d end
  end
end

if not r.SNM_SendSysEx then
    r.MB("SWS not found (SNM_SendSysEx missing). Install SWS to send dump requests.", "FB-01 Auto Dump", 0)
    return false
  end
  r.SNM_SendSysEx(hex_to_bytes(hex))
  return true
end

local ok, vals = r.GetUserInputs("FB-01 Auto Dump Record", 2,
  "Dump type: 1=VoiceBank00 2=VoiceBank01 3=AllConfigs,Record seconds",
  "1,8")
if not ok then return end
local t, secs = vals:match("([^,]+),([^,]+)")
t = tonumber(t) or 1
secs = tonumber(secs) or 8
if secs < 2 then secs = 2 end
if secs > 120 then secs = 120 end

-- Pick request message (SysexDB-documented requests) citeturn1view0
local req
if t == 1 then
  req = "F0 43 75 00 20 00 00 F7"  -- voice bank 00
elseif t == 2 then
  req = "F0 43 75 00 20 00 01 F7"  -- voice bank 01
else
  req = "F0 43 75 00 20 03 00 F7"  -- all configs
end

-- Start recording
-- Command 1013 = Transport: Record
-- Command 1016 = Transport: Stop
r.Main_OnCommand(1013, 0)

-- Send dump request (after record starts, small delay)
local start_time = r.time_precise()
local sent = false

local function defer_loop()
  local now = r.time_precise()
  if not sent and (now - start_time) > 0.2 then
    send_sysex_hex(req)
    sent = true
  end
  if (now - start_time) >= secs then
    r.Main_OnCommand(1016, 0) -- stop
    r.MB("Done.\nSelect the recorded MIDI item and run:\n- IFLS_FB01_SysEx_Analyzer_SelectedItem.lua\n- IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua\n- IFLS_FB01_StoreDump_To_ExtState.lua", "FB-01 Auto Dump", 0)
    return
  end
  r.defer(defer_loop)
end

r.defer(defer_loop)
