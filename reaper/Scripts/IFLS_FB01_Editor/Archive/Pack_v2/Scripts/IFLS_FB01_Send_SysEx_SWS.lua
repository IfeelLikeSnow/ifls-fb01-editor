-- @description IFLS Workbench - Workbench/FB01/Pack_v2/Scripts/IFLS_FB01_Send_SysEx_SWS.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Send_SysEx_SWS.lua
-- Optional helper: send raw SysEx via SWS (SNM_SendSysEx) if installed.
-- Usage: edit the sysex hex string below or prompt.
--
-- Notes:
-- - SysEx is required for deep FB-01 editing (voice/operator params).
-- - Standard MIDI (CC/PC) covers Mix/Assign; this script is for advanced workflows.

local r = reaper

if not r.SNM_SendSysEx then
  r.MB("SWS extension not found (SNM_SendSysEx missing).\nInstall SWS if you need live SysEx from scripts.\n\nYou can still use CC/PC scripts without SWS.", "IFLS FB-01 SysEx", 0)
  return
end

local ok, hex = r.GetUserInputs("Send SysEx (hex bytes, spaced)", 1, "Sysex bytes (e.g. F0 43 ... F7)", "F0 43 75 00 01 00 00 F7")
if not ok then return end

-- Convert "F0 43 ..." -> binary string
local bytes = {}
for b in hex:gmatch("%x%x") do
  table.insert(bytes, string.char(tonumber(b,16)))
end
local syx = table.concat(bytes)

-- send to all MIDI outputs (SWS function expects string + optional device? Many builds broadcast.
-- We'll just call with the sysex data; user can route via REAPER MIDI device settings.
r.SNM_SendSysEx(syx)
