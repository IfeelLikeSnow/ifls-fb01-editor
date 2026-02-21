-- @description IFLS FB-01 Hardware Roundtrip Test (B2.14) – Template Harness
-- @version 0.1
--
-- IMPORTANT:
-- REAPER's native ReaScript API is limited for raw SysEx output on many setups.
-- This file is a harness/template to be integrated with the editor's existing send path.
--
-- Goal:
--   Dump -> decode -> apply -> re-dump -> diff last64 == 0

local r = reaper
local Syx = require("ifls_fb01_sysex")
local VoiceDump = require("ifls_fb01_voice_dump")
local VoiceMap = require("ifls_fb01_voice_map")

local function msgbox(s) r.ShowMessageBox(s, "FB-01 Roundtrip Test", 0) end

local function bytes_from_recent_input(timeout_ms)
  local t0 = r.time_precise()
  while (r.time_precise() - t0) * 1000.0 < timeout_ms do
    local ok, dev, msg, ts = r.MIDI_GetRecentInputEvent(0)
    if ok and msg and #msg > 0 then
      local b = {}
      for i=1,#msg do b[#b+1] = string.byte(msg, i) end
      if b[1] == 0xF0 and b[#b] == 0xF7 then
        return b
      end
    end
    r.defer(function() end)
  end
  return nil
end

local function extract_last64(payload_bytes)
  if not payload_bytes or #payload_bytes < 64 then return nil end
  local out = {}
  for i=#payload_bytes-63, #payload_bytes do out[#out+1] = payload_bytes[i] end
  return out
end

local function diff64(a,b)
  local diffs = {}
  for i=1,64 do
    local av = a[i] or 0
    local bv = b[i] or 0
    if av ~= bv then diffs[#diffs+1] = {i=i-1, a=av, b=bv} end
  end
  return diffs
end

-- Config
local sys_ch = 0
local inst_no = 0

msgbox("B2.14 Roundtrip harness (template).\n\n1) Use the editor to request a voice dump.\n2) This harness can capture received SysEx via MIDI_GetRecentInputEvent.\n\nIt will now wait for a SysEx dump (3s).")

local rx1 = bytes_from_recent_input(3000)
if not rx1 then
  msgbox("No SysEx received.\nTip: Enable SysEx on your MIDI interface and ensure FB-01 sends into REAPER input.")
  return
end

local res1, err1 = VoiceDump.decode_voice_from_sysex(rx1)
if not res1 then msgbox("Decode failed: "..tostring(err1)); return end

local before64 = extract_last64(res1.payload_bytes)
if not before64 then msgbox("Payload too short."); return end

-- Identity apply example (replace with editor's current UI voice bytes)
local new_voice64 = res1.voice_bytes
local new_payload = VoiceDump.replace_voice_bytes(res1.payload_bytes, res1.voice_offset, new_voice64)
local msg, err = VoiceDump.build_voice_sysex_from_template(res1.template, new_payload)
if not msg then msgbox("Build failed: "..tostring(err)); return end

msgbox("Template built.\n\nNext steps:\n- Send this msg using the editor's send queue\n- Re-dump and compare with Tools/FB01/diff_voice_dump64.py")
