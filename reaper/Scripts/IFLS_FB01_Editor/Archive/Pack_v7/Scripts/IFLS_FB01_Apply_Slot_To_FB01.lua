-- @description IFLS Workbench - Workbench/FB01/Pack_v7/Scripts/IFLS_FB01_Apply_Slot_To_FB01.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Apply_Slot_To_FB01.lua
-- Loads a V5-compatible slot from ExtState and sends mapped parameters to the FB-01 via SWS SysEx.
--
-- Requires: SWS (SNM_SendSysEx)

local r = reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "IFLS FB-01 Apply Slot", 0)
  return
end

local EXT_SECTION = "IFLS_FB01_VOICE_MACRO_V5"

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

local function fmt2(n) return string.format("%02X", n) end

local function nibble_split(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = 0 elseif v > 255 then v = 255 end
  local high = math.floor(v / 16)
  local low  = v - 16*high
  return low, high
end

local function build_cfg_change(system_ch, instrument, pp, value)
  local s = (tonumber(system_ch) or 1) - 1
  if s < 0 then s = 0 elseif s > 15 then s = 15 end
  local inst0 = (tonumber(instrument) or 1) - 1
  if inst0 < 0 then inst0 = 0 elseif inst0 > 7 then inst0 = 7 end
  local zz = 0x18 + inst0
  local low, high = nibble_split(value)
  return string.format("F0 43 75 %s %s %s 0%X 0%X F7", fmt2(s), fmt2(zz), fmt2(pp), low, high)
end

local function twos_complement_8bit(n)
  n = math.floor(tonumber(n) or 0)
  if n < -128 then n = -128 elseif n > 127 then n = 127 end
  if n < 0 then return 256 + n end
  return n
end

local function parse_slot(s)
  if not s or s == "" then return nil end
  local function num(k, default)
    local v = s:match('"'..k..'":([%-0-9]+)')
    v = tonumber(v)
    if v == nil then return default end
    return v
  end
  local st = {}
  st.system_ch = num("system_ch", 1)
  st.instrument = num("instrument", 1)
  st.algorithm = num("algorithm", 1)
  st.feedback = num("feedback", 0)
  st.transpose = num("transpose", 0)

  local op = s:match('"op_en"%s*:%s*%[([^%]]+)%]')
  st.op_en = {true,true,true,true}
  if op then
    local vals = {}
    for tok in op:gmatch("([01])") do vals[#vals+1] = (tok=="1") end
    for i=1,4 do if vals[i]~=nil then st.op_en[i]=vals[i] end end
  end
  local tl = s:match('"tl"%s*:%s*%[([^%]]+)%]')
  st.tl = {80,90,90,80}
  if tl then
    local vals = {}
    for tok in tl:gmatch("([%-0-9]+)") do vals[#vals+1] = tonumber(tok) end
    for i=1,4 do if vals[i]~=nil then st.tl[i]=vals[i] end end
  end
  return st
end

local function op_bitmap(st)
  local v = 0
  for i=1,4 do
    if st.op_en[i] then v = v + (1 << (i-1)) end
  end
  return v
end

local function pack_alg_fb(st)
  local alg0 = math.max(0, math.min(7, (st.algorithm or 1)-1))
  local fb0  = math.max(0, math.min(7, st.feedback or 0))
  return alg0 + (fb0 << 3)
end

local ok, vals = r.GetUserInputs("FB-01 Apply Slot", 1, "Slot (1-8)", "1")
if not ok then return end
local slot = tonumber(vals) or 1
if slot < 1 then slot = 1 elseif slot > 8 then slot = 8 end

local key = string.format("slot_%02d", slot)
local s = r.GetExtState(EXT_SECTION, key)
local st = parse_slot(s)
if not st then
  r.MB("Slot is empty: "..key, "FB-01 Apply Slot", 0)
  return
end

-- send mapped params
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x4B, op_bitmap(st)))
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x4C, pack_alg_fb(st)))
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x4F, twos_complement_8bit(st.transpose)))
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x50, st.tl[1]))
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x60, st.tl[2]))
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x68, st.tl[3]))
send_sysex_hex(build_cfg_change(st.system_ch, st.instrument, 0x70, st.tl[4]))

r.MB("Applied Slot "..slot.." to FB-01 (mapped macro params).", "FB-01 Apply Slot", 0)
