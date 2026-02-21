-- @description IFLS Workbench - Workbench/FB01/Pack_v5/Scripts/IFLS_FB01_VoiceMacro_GUI.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_VoiceMacro_GUI.lua
-- REAPER ReaImGui voice macro panel for Yamaha FB-01 (SWS SysEx send)
-- Focus: fast IDM-friendly shaping, recallable.
--
-- SysEx format used (Config/Instrument change by System Ch + Instrument):
--   F0 43 75 0s (18+inst0) pp 0y 0x F7
--   y/x are low/high nibbles of the data byte (0..255), sent low first.
--
-- Requires:
--   - SWS (SNM_SendSysEx)
--   - ReaImGui

local r = reaper

-- -------- guards
if not r.SNM_SendSysEx then
  r.MB("SWS extension not found (SNM_SendSysEx missing).\nInstall SWS, then rerun.", "IFLS FB-01 Voice Macro", 0)
  return
end
if not r.ImGui_CreateContext then
  r.MB("ReaImGui not found.\nInstall ReaImGui, then rerun.", "IFLS FB-01 Voice Macro", 0)
  return
end

-- -------- utilities
local function hex_to_bytes(hex)
  local bytes = {}
  for b in hex:gmatch("%x%x") do
    bytes[#bytes+1] = string.char(tonumber(b,16))
  end
  return table.concat(bytes)
end

local function send_sysex_hex(hex)
  r.SNM_SendSysEx(hex_to_bytes(hex))
end

local function nibble_split(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = 0 elseif v > 255 then v = 255 end
  local high = math.floor(v / 16)
  local low  = v - 16*high
  return low, high
end

local function twos_complement_8bit(n)
  n = math.floor(tonumber(n) or 0)
  if n < -128 then n = -128 elseif n > 127 then n = 127 end
  if n < 0 then return 256 + n end
  return n
end

local function fmt2(n) return string.format("%02X", n) end

local function build_cfg_change(system_ch, instrument, pp, value)
  local s = (tonumber(system_ch) or 1) - 1
  if s < 0 then s = 0 elseif s > 15 then s = 15 end
  local inst0 = (tonumber(instrument) or 1) - 1
  if inst0 < 0 then inst0 = 0 elseif inst0 > 7 then inst0 = 7 end
  local zz = 0x18 + inst0
  local low, high = nibble_split(value)
  -- 0y 0x (low then high)
  return string.format("F0 43 75 %s %s %s 0%X 0%X F7", fmt2(s), fmt2(zz), fmt2(pp), low, high)
end

local function send_pp(system_ch, instrument, pp, value)
  local hex = build_cfg_change(system_ch, instrument, pp, value)
  send_sysex_hex(hex)
  return hex
end

-- -------- state
local state = {
  system_ch = 1,
  instrument = 1,      -- part 1..8
  algorithm = 1,       -- 1..8 (packed into pp=0x4C low 3 bits)
  feedback = 0,        -- 0..7 (packed into pp=0x4C bits 3..5)
  op_en = {true,true,true,true}, -- bitmap pp=0x4B (we assume bit0..3)
  tl = {80, 90, 90, 80}, -- OP total levels 0..127 (0 loud, 127 quiet)
  transpose = 0,       -- semis -64..63 (pp=0x4F as two's complement)
  last_sent = "",
  slot = 1,
}

local EXT_SECTION = "IFLS_FB01_VOICE_MACRO_V5"

local function op_bitmap()
  local v = 0
  for i=1,4 do
    if state.op_en[i] then v = v + (1 << (i-1)) end
  end
  return v
end

local function pack_alg_fb()
  -- Conservative packing: alg (0..7) in bits 0..2, feedback (0..7) in bits 3..5.
  -- Leaves upper bits 6..7 untouched (0). Many docs show extra bits (L/R/ccc), but this is safe for macro work.
  local alg0 = math.max(0, math.min(7, (state.algorithm or 1)-1))
  local fb0  = math.max(0, math.min(7, state.feedback or 0))
  return alg0 + (fb0 << 3)
end

local function send_all()
  -- Operator enable bitmap
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x4B, op_bitmap())
  -- Algorithm/Feedback packed
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x4C, pack_alg_fb())
  -- Transpose
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x4F, twos_complement_8bit(state.transpose))
  -- OP TLs (pp IDs chosen per common tables; if your unit differs, we can remap in V6)
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x50, state.tl[1])
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x60, state.tl[2])
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x68, state.tl[3])
  state.last_sent = send_pp(state.system_ch, state.instrument, 0x70, state.tl[4])
end

local function snapshot_to_string()
  -- simple JSON-ish (manual)
  local function b(x) return x and "1" or "0" end
  return string.format(
    '{"system_ch":%d,"instrument":%d,"algorithm":%d,"feedback":%d,"op_en":[%s,%s,%s,%s],"tl":[%d,%d,%d,%d],"transpose":%d}',
    state.system_ch, state.instrument, state.algorithm, state.feedback,
    b(state.op_en[1]), b(state.op_en[2]), b(state.op_en[3]), b(state.op_en[4]),
    state.tl[1], state.tl[2], state.tl[3], state.tl[4], state.transpose
  )
end

local function load_from_string(s)
  if not s or s == "" then return false end
  local ok = true
  local function num(k, default)
    local v = s:match('"'..k..'":([%-0-9]+)')
    v = tonumber(v)
    if v == nil then ok = false; return default end
    return v
  end
  state.system_ch = num("system_ch", state.system_ch)
  state.instrument = num("instrument", state.instrument)
  state.algorithm = num("algorithm", state.algorithm)
  state.feedback = num("feedback", state.feedback)
  state.transpose = num("transpose", state.transpose)

  local op = s:match('"op_en"%s*:%s*%[([^%]]+)%]')
  if op then
    local vals = {}
    for tok in op:gmatch("([01])") do vals[#vals+1] = (tok=="1") end
    for i=1,4 do if vals[i]~=nil then state.op_en[i]=vals[i] end end
  end
  local tl = s:match('"tl"%s*:%s*%[([^%]]+)%]')
  if tl then
    local vals = {}
    for tok in tl:gmatch("([%-0-9]+)") do vals[#vals+1] = tonumber(tok) end
    for i=1,4 do if vals[i]~=nil then state.tl[i]=vals[i] end end
  end
  return ok
end

local function save_slot(slot)
  local key = string.format("slot_%02d", slot)
  r.SetExtState(EXT_SECTION, key, snapshot_to_string(), true)
end

local function load_slot(slot)
  local key = string.format("slot_%02d", slot)
  local s = r.GetExtState(EXT_SECTION, key)
  return load_from_string(s)
end

local function write_track_notes()
  local tr = r.GetSelectedTrack(0,0)
  if not tr then
    r.MB("Select a track first (e.g. your FB-01 Part track or the folder).", "IFLS FB-01 Voice Macro", 0)
    return
  end
  local notes = "[FB-01 Voice Macro V5]\n" ..
    "System Ch: "..state.system_ch.."\n" ..
    "Instrument: "..state.instrument.."\n" ..
    "Algorithm: "..state.algorithm.."\n" ..
    "Feedback: "..state.feedback.."\n" ..
    "OP Enable: "..(state.op_en[1] and "1" or "0")..(state.op_en[2] and "1" or "0")..(state.op_en[3] and "1" or "0")..(state.op_en[4] and "1" or "0").."\n" ..
    string.format("TL OP1..4: %d, %d, %d, %d\n", state.tl[1], state.tl[2], state.tl[3], state.tl[4]) ..
    "Transpose: "..state.transpose.."\n"
  local ok, cur = r.GetSetMediaTrackInfo_String(tr, "P_NOTES", "", false)
  local combined = (cur or "") .. "\n" .. notes
  r.GetSetMediaTrackInfo_String(tr, "P_NOTES", combined, true)
end

-- -------- macro buttons (IDM-friendly)
local function macro_apply(name)
  -- These are intentionally simple and reproducible: they only touch our mapped params.
  if name == "Glass Pluck" then
    state.algorithm = 5
    state.feedback = 1
    state.op_en = {true,true,false,false}
    state.tl = {40, 90, 120, 120}
    state.transpose = 0
  elseif name == "Metal Bell" then
    state.algorithm = 7
    state.feedback = 3
    state.op_en = {true,true,true,false}
    state.tl = {55, 70, 85, 120}
    state.transpose = -12
  elseif name == "Noisy Drone" then
    state.algorithm = 8
    state.feedback = 6
    state.op_en = {true,true,true,true}
    state.tl = {80, 75, 75, 80}
    state.transpose = 0
  elseif name == "Soft Pad" then
    state.algorithm = 2
    state.feedback = 0
    state.op_en = {true,true,true,false}
    state.tl = {85, 95, 95, 127}
    state.transpose = 0
  elseif name == "Bite Bass" then
    state.algorithm = 6
    state.feedback = 4
    state.op_en = {true,true,true,false}
    state.tl = {45, 65, 95, 127}
    state.transpose = -24
  end
end

-- -------- ImGui
local ctx = r.ImGui_CreateContext("FB-01 Voice Macro (V5)")
local function clamp(v, lo, hi)
  v = math.floor(tonumber(v) or lo)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function loop()
  local visible, open = r.ImGui_Begin(ctx, "FB-01 Voice Macro (V5) — SysEx via SWS", true)
  if visible then
    r.ImGui_Text(ctx, "Target")
    local changed
    changed, state.system_ch = r.ImGui_SliderInt(ctx, "System Channel", state.system_ch, 1, 16)
    changed, state.instrument = r.ImGui_SliderInt(ctx, "Instrument (Part)", state.instrument, 1, 8)

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Voice Macro Controls (fast)")
    changed, state.algorithm = r.ImGui_SliderInt(ctx, "Algorithm (1-8)", state.algorithm, 1, 8)
    changed, state.feedback  = r.ImGui_SliderInt(ctx, "Feedback (0-7)", state.feedback, 0, 7)

    if r.ImGui_Button(ctx, "Send Alg+FB") then
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x4C, pack_alg_fb())
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send ALL") then
      send_all()
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Operators")
    for i=1,4 do
      local label = "OP"..i.." Enable"
      local v = state.op_en[i]
      local chg; chg, v = r.ImGui_Checkbox(ctx, label, v)
      if chg then state.op_en[i]=v end
    end
    if r.ImGui_Button(ctx, "Send OP Enable Bitmap") then
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x4B, op_bitmap())
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Total Level (0 loud .. 127 quiet)")
    for i=1,4 do
      local chg; chg, state.tl[i] = r.ImGui_SliderInt(ctx, "TL OP"..i, state.tl[i], 0, 127)
    end
    if r.ImGui_Button(ctx, "Send TLs") then
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x50, state.tl[1])
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x60, state.tl[2])
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x68, state.tl[3])
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x70, state.tl[4])
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Transpose")
    changed, state.transpose = r.ImGui_SliderInt(ctx, "Semitones", state.transpose, -64, 63)
    if r.ImGui_Button(ctx, "Send Transpose") then
      state.last_sent = send_pp(state.system_ch, state.instrument, 0x4F, twos_complement_8bit(state.transpose))
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Quick Macros (IDM starting points)")
    if r.ImGui_Button(ctx, "Glass Pluck") then macro_apply("Glass Pluck"); send_all() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Metal Bell") then macro_apply("Metal Bell"); send_all() end
    if r.ImGui_Button(ctx, "Noisy Drone") then macro_apply("Noisy Drone"); send_all() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Soft Pad") then macro_apply("Soft Pad"); send_all() end
    if r.ImGui_Button(ctx, "Bite Bass") then macro_apply("Bite Bass"); send_all() end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Preset Slots (ExtState)")
    changed, state.slot = r.ImGui_SliderInt(ctx, "Slot", state.slot, 1, 8)
    if r.ImGui_Button(ctx, "Save Slot") then
      save_slot(state.slot)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Load Slot") then
      load_slot(state.slot)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Load + Send") then
      load_slot(state.slot)
      send_all()
    end

    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Write Track Notes (Recall)") then
      write_track_notes()
    end

    r.ImGui_Separator(ctx)
    r.ImGui_TextWrapped(ctx, "Last sent: "..(state.last_sent or ""))
    r.ImGui_TextWrapped(ctx, "Tip: Select your FB-01 Part track so notes land where you expect. Keep a dry anchor in REAPER; resample hardware returns for IDM workflows.")

    r.ImGui_End(ctx)
  end

  if open then
    r.defer(loop)
  else
    r.ImGui_DestroyContext(ctx)
  end
end

r.defer(loop)
