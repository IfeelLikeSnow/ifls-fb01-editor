-- @description IFLS Workbench - Workbench/FB01/Pack_v5/Scripts/IFLS_FB01_SysEx_Toolkit.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_SysEx_Toolkit.lua
-- Yamaha FB-01 SysEx toolkit for REAPER.
--
-- Features:
-- 1) Config/Instrument param change by System Channel + Instrument:
--    F0 43 75 0s zz pp 0y 0x F7
--    s  = system number (0..15) representing system channel 1..16
--    zz = 0x18 + instrumentNumber (instrument 1..8 -> 0..7)
--    pp = parameter number (1 byte, hex)
--    data xy split into nibbles as 0y 0x (low then high)
--    Source explanation incl. nibble order: https://midi.org/.../more-difficult-message-fb-01-sysex citeturn2view1
--
-- 2) Signed Transpose helper (two's complement encoding) based on same thread.
-- 3) Dump requests (config + voice banks) based on examples:
--    - F0 43 75 00 20 03 00 F7 (dump all config)
--    - F0 43 75 00 20 00 00 F7 (dump voice bank 0)
--    - F0 43 75 00 20 00 01 F7 (dump voice bank 1)
--    Source: https://nerdlypleasures.blogspot.com/... citeturn2view2
-- 4) Bank select helper (known pattern shared by users):
--    F0 43 75 01 18 04 xx F7 (xx=00..06) citeturn2view3
--
-- Requirements: SWS for SNM_SendSysEx is recommended.
-- If SWS missing, script will show a message and exit.

local r = reaper

if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "IFLS", 0)
  return
end

if not r.ImGui_CreateContext then
  r.MB("ReaImGui not found. Install ReaImGui, then rerun.", "IFLS", 0)
  return
end

local function has_sws()
  return r.SNM_SendSysEx ~= nil
end

local function hex_to_bytes(hex)
  local bytes = {}
  for b in hex:gmatch("%x%x") do
    table.insert(bytes, string.char(tonumber(b,16)))
  end
  return table.concat(bytes)
end

local function send_sysex_hex(hex)
  if not has_sws() then
    r.MB("SWS extension not found (SNM_SendSysEx missing).\nInstall SWS to send SysEx reliably from scripts.\n\nYou can still use CC/PC (V2 scripts).","IFLS FB-01 SysEx Toolkit",0)
    return false
  end
  local data = hex_to_bytes(hex)
  r.SNM_SendSysEx(data)
  return true
end

local function nibble_split(v)
  -- v: 0..255 -> low nibble then high nibble (0y 0x)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = 0 elseif v > 255 then v = 255 end
  local high = math.floor(v / 16)
  local low  = v - 16 * high
  return low, high
end

local function twos_complement_8bit(n)
  -- n in -128..127 -> 0..255
  n = math.floor(tonumber(n) or 0)
  if n < -128 then n = -128 elseif n > 127 then n = 127 end
  if n < 0 then return 256 + n end
  return n
end

local function fmt2(n) return string.format("%02X", n) end

local function build_cfg_change(system_ch, instrument, pp_hex, value)
  -- system_ch: 1..16
  -- instrument: 1..8
  -- pp_hex: "4F" etc
  local s = (tonumber(system_ch) or 1) - 1
  if s < 0 then s = 0 elseif s > 15 then s = 15 end
  local inst0 = (tonumber(instrument) or 1) - 1
  if inst0 < 0 then inst0 = 0 elseif inst0 > 7 then inst0 = 7 end
  local zz = 0x18 + inst0
  local pp = tonumber(pp_hex, 16) or 0x00
  if pp < 0 then pp = 0 elseif pp > 255 then pp = 255 end

  local low, high = nibble_split(value)
  -- F0 43 75 0s zz pp 0y 0x F7
  return string.format("F0 43 75 %s %s %s 0%s 0%s F7",
    fmt2(s), fmt2(zz), fmt2(pp), fmt2(low):sub(2,2), fmt2(high):sub(2,2))
end

local function send_cfg_change(system_ch, instrument, pp_hex, value)
  local hex = build_cfg_change(system_ch, instrument, pp_hex, value)
  send_sysex_hex(hex)
  return hex
end

local function send_transpose(system_ch, instrument, semis)
  -- transpose pp=4F per MIDI.org thread citeturn2view1
  local v = twos_complement_8bit(semis)
  return send_cfg_change(system_ch, instrument, "4F", v)
end

local function send_dump_config()
  return send_sysex_hex("F0 43 75 00 20 03 00 F7")
end

local function send_dump_voice_bank(bank)
  -- bank 0/1 examples from NerdlyPleasures citeturn2view2
  bank = tonumber(bank) or 0
  if bank < 0 then bank = 0 elseif bank > 1 then bank = 1 end
  return send_sysex_hex(string.format("F0 43 75 00 20 00 %s F7", fmt2(bank)))
end

local function send_bank_select(bank)
  -- User-shared pattern: F0 43 75 01 18 04 xx F7 citeturn2view3
  bank = tonumber(bank) or 0
  if bank < 0 then bank = 0 elseif bank > 6 then bank = 6 end
  return send_sysex_hex(string.format("F0 43 75 01 18 04 %s F7", fmt2(bank)))
end

-- UI (ReaImGui optional)
local has_imgui = r.ImGui_CreateContext ~= nil

local state = {
  system_ch = 1,
  instrument = 1,
  pp_hex = "00",
  value = 0,
  transpose = 0,
  bank = 0,
  dump_bank = 0,
}

local function prompt_mode()
  local ok, vals = r.GetUserInputs("FB-01 SysEx Toolkit (SWS required)", 5,
    "SystemCh(1-16),Instrument(1-8),ParamHex(pp),Value(0-255),Transpose(-64..63)",
    string.format("%d,%d,%s,%d,%d", state.system_ch, state.instrument, state.pp_hex, state.value, state.transpose))
  if not ok then return end
  local a,b,c,d,e = vals:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
  state.system_ch = tonumber(a) or 1
  state.instrument = tonumber(b) or 1
  state.pp_hex = (c or "00"):gsub("%s",""):upper()
  state.value = tonumber(d) or 0
  state.transpose = tonumber(e) or 0

  local hex = send_cfg_change(state.system_ch, state.instrument, state.pp_hex, state.value)
  r.ShowMessageBox("Sent Config Change:\n"..hex.."\n\nTip: Transpose uses pp=4F.", "FB-01 SysEx Toolkit", 0)
end

if not has_sws() then
  r.MB("SWS extension not found (SNM_SendSysEx missing).\n\nInstall SWS, then rerun this script.\n\nTip: You can still use V2 CC/PC scripts without SWS.", "IFLS FB-01 SysEx Toolkit", 0)
  return
end

if not has_imgui then
  prompt_mode()
  return
end

local ctx = r.ImGui_CreateContext('FB-01 SysEx Toolkit')

local function clamp_int(v, lo, hi)
  v = math.floor(tonumber(v) or lo)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local last_sent = ""

local function loop()
  local visible, open = r.ImGui_Begin(ctx, 'FB-01 SysEx Toolkit (SWS)', true)
  if visible then
    r.ImGui_Text(ctx, "Config/Instrument Change: F0 43 75 0s (18+inst) pp 0y 0x F7")
    r.ImGui_Separator(ctx)

    local changed
    changed, state.system_ch = r.ImGui_SliderInt(ctx, "System Channel", state.system_ch, 1, 16)
    changed, state.instrument = r.ImGui_SliderInt(ctx, "Instrument (Part)", state.instrument, 1, 8)

    -- Param hex input
    local buf = state.pp_hex
    changed, buf = r.ImGui_InputText(ctx, "Parameter (pp hex)", buf)
    if changed then
      buf = buf:gsub("[^0-9A-Fa-f]",""):upper()
      if #buf > 2 then buf = buf:sub(1,2) end
      if #buf == 0 then buf = "00" end
      state.pp_hex = buf
    end

    changed, state.value = r.ImGui_SliderInt(ctx, "Value (0-255)", state.value, 0, 255)

    if r.ImGui_Button(ctx, "Send Config Change") then
      last_sent = send_cfg_change(state.system_ch, state.instrument, state.pp_hex, state.value)
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send Transpose (pp=4F)") then
      last_sent = send_transpose(state.system_ch, state.instrument, state.transpose)
    end

    changed, state.transpose = r.ImGui_SliderInt(ctx, "Transpose (semitones)", state.transpose, -64, 63)

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Dump Requests (FB-01 must have Memory Protect OFF to receive writes; dumps can ACK/error).")
    if r.ImGui_Button(ctx, "Request Dump: ALL Config") then
      send_dump_config()
      last_sent = "F0 43 75 00 20 03 00 F7"
    end
    r.ImGui_SameLine(ctx)
    changed, state.dump_bank = r.ImGui_SliderInt(ctx, "Voice Bank (0-1)", state.dump_bank, 0, 1)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Request Dump: Voice Bank") then
      send_dump_voice_bank(state.dump_bank)
      last_sent = string.format("F0 43 75 00 20 00 %02X F7", state.dump_bank)
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Bank Select helper (xx 00..06): F0 43 75 01 18 04 xx F7")
    changed, state.bank = r.ImGui_SliderInt(ctx, "Bank (0-6)", state.bank, 0, 6)
    if r.ImGui_Button(ctx, "Send Bank Select") then
      send_bank_select(state.bank)
      last_sent = string.format("F0 43 75 01 18 04 %02X F7", state.bank)
    end

    r.ImGui_Separator(ctx)
    r.ImGui_TextWrapped(ctx, "Last sent:")
    r.ImGui_Text(ctx, last_sent)

    r.ImGui_End(ctx)
  end

  if open then
    r.defer(loop)
  else
    r.ImGui_DestroyContext(ctx)
  end
end

r.defer(loop)
