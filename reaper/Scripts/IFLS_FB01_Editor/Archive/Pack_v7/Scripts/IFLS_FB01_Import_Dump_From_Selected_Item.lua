-- @description IFLS Workbench - Workbench/FB01/Pack_v7/Scripts/IFLS_FB01_Import_Dump_From_Selected_Item.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Import_Dump_From_Selected_Item.lua
-- Parses SysEx events from the first selected media item (MIDI item) and stores parameters into ExtState slots
-- compatible with IFLS_FB01_VoiceMacro_GUI.lua (V5+).
--
-- Focuses on Param-Change messages of the form:
--   F0 43 75 0s zz pp 0y 0x F7
-- where value byte is encoded in low/high nibble as 0y 0x (low first).
--
-- No SWS required for parsing.

local r = reaper

local EXT_SECTION = "IFLS_FB01_VOICE_MACRO_V5"

local function get_selected_midi_take()
  local item = r.GetSelectedMediaItem(0, 0)
  if not item then return nil, "No item selected." end
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then
    return nil, "Selected item is not a MIDI take."
  end
  return take, nil
end

local function bytes_to_hex(msg)
  local t = {}
  for i=1,#msg do
    t[#t+1] = string.format("%02X", msg:byte(i))
  end
  return table.concat(t, " ")
end

local function parse_param_change(msg)
  -- REAPER provides SysEx payload WITHOUT bounding F0/F7.
  -- Accept both framed and unframed.
  if not msg or #msg < 7 then return nil end

  local framed = (msg:byte(1) == 0xF0)
  local b = { msg:byte(1, #msg) }

  local function at(i) return b[i] end
  local offset = 0

  if framed then
    if #b < 9 then return nil end
    if at(1) ~= 0xF0 or at(2) ~= 0x43 or at(3) ~= 0x75 then return nil end
    if at(#b) ~= 0xF7 then return nil end
    offset = 0
  else
    -- unframed starts at 0x43 0x75 ...
    if at(1) ~= 0x43 or at(2) ~= 0x75 then return nil end
    offset = -1 -- indices shift left by 1 vs framed
  end

  -- pattern: F0 43 75 0s zz pp 0y 0x F7
  local s  = at(4+offset)
  local zz = at(5+offset)
  local pp = at(6+offset)
  local low_n  = at(7+offset)
  local high_n = at(8+offset)
  if not (s and zz and pp and low_n and high_n) then return nil end

  if (low_n & 0xF0) ~= 0x00 or (high_n & 0xF0) ~= 0x00 then return nil end
  local low  = low_n & 0x0F
  local high = high_n & 0x0F
  local value = low + high * 16

  local inst0 = zz - 0x18
  if inst0 < 0 or inst0 > 7 then return nil end

  return {
    system_ch = (s or 0) + 1,
    instrument = inst0 + 1,
    pp = pp,
    value = value
  }
end

local function load_slot_string(slot)
  local key = string.format("slot_%02d", slot)
  return r.GetExtState(EXT_SECTION, key)
end

local function save_slot_string(slot, s)
  local key = string.format("slot_%02d", slot)
  r.SetExtState(EXT_SECTION, key, s, true)
end

local function build_slot_from_params(params, defaults)
  -- Only map parameters we use in V5 GUI:
  -- pp=0x4B op bitmap
  -- pp=0x4C alg+fb packed
  -- pp=0x4F transpose (two's complement)
  -- pp=0x50/60/68/70 tl for op1..4
  local st = defaults or {
    system_ch = 1, instrument = 1, algorithm = 1, feedback = 0,
    op_en = {true,true,true,true}, tl = {80,90,90,80}, transpose = 0
  }

  local function set_from_pp(pp, v)
    if pp == 0x4B then
      st.op_en = {
        (v & 0x01) ~= 0,
        (v & 0x02) ~= 0,
        (v & 0x04) ~= 0,
        (v & 0x08) ~= 0
      }
    elseif pp == 0x4C then
      local alg0 = v & 0x07
      local fb0 = (v >> 3) & 0x07
      st.algorithm = alg0 + 1
      st.feedback = fb0
    elseif pp == 0x4F then
      -- two's complement to signed
      if v >= 128 then st.transpose = v - 256 else st.transpose = v end
      -- clamp to GUI range
      if st.transpose < -64 then st.transpose = -64 end
      if st.transpose > 63 then st.transpose = 63 end
    elseif pp == 0x50 then st.tl[1] = v
    elseif pp == 0x60 then st.tl[2] = v
    elseif pp == 0x68 then st.tl[3] = v
    elseif pp == 0x70 then st.tl[4] = v
    end
  end

  for _,p in ipairs(params) do
    st.system_ch = p.system_ch
    st.instrument = p.instrument
    set_from_pp(p.pp, p.value)
  end
  return st
end

local function slot_to_string(st)
  local function b(x) return x and "1" or "0" end
  return string.format(
    '{"system_ch":%d,"instrument":%d,"algorithm":%d,"feedback":%d,"op_en":[%s,%s,%s,%s],"tl":[%d,%d,%d,%d],"transpose":%d}',
    st.system_ch, st.instrument, st.algorithm, st.feedback,
    b(st.op_en[1]), b(st.op_en[2]), b(st.op_en[3]), b(st.op_en[4]),
    st.tl[1], st.tl[2], st.tl[3], st.tl[4], st.transpose
  )
end

-- main
local take, err = get_selected_midi_take()
if not take then
  r.MB(err, "FB-01 Import Dump", 0)
  return
end

local ok, slot_s = r.GetUserInputs("FB-01 Import Dump", 2,
  "Target Slot (1-8),Write Track Notes? (0/1)",
  "1,1")
if not ok then return end
local slot_str, write_notes_str = slot_s:match("([^,]+),([^,]+)")
local slot = tonumber(slot_str) or 1
local write_notes = (tonumber(write_notes_str) or 1) ~= 0
if slot < 1 then slot = 1 elseif slot > 8 then slot = 8 end

local _, _, _, textsz = r.MIDI_CountEvts(take)
local params = {}
for i=0, textsz-1 do
  local retval, selected, muted, ppqpos, type_, msg = r.MIDI_GetTextSysexEvt(take, i)
  if retval and type_ == -1 and msg and #msg > 0 then
    local p = parse_param_change(msg)
    if p then
      params[#params+1] = p
    end
  end
end

if #params == 0 then
  r.MB("No recognized FB-01 param-change SysEx events found in this item.\n\nTip: Ensure you're recording SysEx, and the FB-01 is sending param-change style messages.\nIf you recorded a different dump format, we can extend the parser in V8.", "FB-01 Import Dump", 0)
  return
end

-- Build slot state from parsed params
local st = build_slot_from_params(params, nil)
local out = slot_to_string(st)
save_slot_string(slot, out)

if write_notes then
  local item = r.GetSelectedMediaItem(0,0)
  local tr = r.GetMediaItemTrack(item)
  if tr then
    local okn, cur = r.GetSetMediaTrackInfo_String(tr, "P_NOTES", "", false)
    local notes = "\n[FB-01 Dump Import V7]\nSlot: "..slot.."\n"..
      "System Ch: "..st.system_ch.."\nInstrument: "..st.instrument.."\n"..
      "Algorithm: "..st.algorithm.."\nFeedback: "..st.feedback.."\n"..
      string.format("TL OP1..4: %d, %d, %d, %d\n", st.tl[1], st.tl[2], st.tl[3], st.tl[4])..
      "Transpose: "..st.transpose.."\n"
    r.GetSetMediaTrackInfo_String(tr, "P_NOTES", (cur or "")..notes, true)
  end
end

r.MB("Imported "..#params.." param-change messages.\nSaved to Slot "..slot..".\nOpen V5 GUI and Load Slot to view.", "FB-01 Import Dump", 0)
