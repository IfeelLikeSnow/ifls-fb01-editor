
-- ifls_fb01_voice_map.lua
-- B2.6: Formal Voice <-> 64-byte block mapping per FB-01 Service Manual (Parameter list 6).
-- Decodes a 64-byte voice block (params 0x40..0x7F) into:
--   voice_vals (by MVP voice param indices)
--   op_vals[1..4] (by MVP operator param indices)
-- and can encode back to a 64-byte block (roundtrip-safe).

local M = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function u8(v) return v & 0xFF end

local function get_bits(v, hi, lo)
  return (v >> lo) & ((1 << (hi-lo+1)) - 1)
end

local function set_bits(v, hi, lo, x)
  local mask = ((1 << (hi-lo+1)) - 1) << lo
  v = v & (~mask)
  v = v | ((x << lo) & mask)
  return u8(v)
end

local function hi_nib(v) return (v >> 4) & 0x0F end
local function lo_nib(v) return v & 0x0F end
local function pack_nibs(hi, lo) return u8(((hi & 0x0F) << 4) | (lo & 0x0F)) end

-- MVP indices (from fb01_params_mvp.json)
M.VOICE = {
  algorithm=0,
  feedback=1,
  transpose=2,
  poly_mode=3,
  portamento_time=4,
  pitchbend_range=5,
  controller_set=6,
  lfo_speed=7,
  lfo_wave=8,
  lfo_load=9,
  lfo_key_sync=10,
  lfo_amd=11,
  lfo_ams=12,
  lfo_pmd=13,
  lfo_pms=14,
  op1_enable=15,
  op2_enable=16,
  op3_enable=17,
  op4_enable=18,
}

M.OP = {
  volume=0,
  level_curb=1,
  level_velocity=2,
  level_depth=3,
  adjust=4,
  fine=5,
  multiple=6,
  rate_depth=7,
  attack=8,
  modulator=9,
  attack_velocity=10,
  decay1=11,
  coarse=12,
  decay2=13,
  sustain=14,
  release=15,
}

local function decode_global(bytes)
  local v = {}
  v[M.VOICE.lfo_speed] = bytes[9] or 0

  local b9 = bytes[10] or 0
  v[M.VOICE.lfo_load] = get_bits(b9, 7, 7)
  v[M.VOICE.lfo_amd]  = get_bits(b9, 6, 0)

  local b10 = bytes[11] or 0
  v[M.VOICE.lfo_key_sync] = get_bits(b10, 7, 7)
  v[M.VOICE.lfo_pmd]      = get_bits(b10, 6, 0)

  local b11 = bytes[12] or 0
  local mask = get_bits(b11, 6, 3) & 0x0F
  v[M.VOICE.op1_enable] = (mask & 0x01) ~= 0 and 1 or 0
  v[M.VOICE.op2_enable] = (mask & 0x02) ~= 0 and 1 or 0
  v[M.VOICE.op3_enable] = (mask & 0x04) ~= 0 and 1 or 0
  v[M.VOICE.op4_enable] = (mask & 0x08) ~= 0 and 1 or 0

  local b12 = bytes[13] or 0
  v[M.VOICE.feedback]  = clamp(get_bits(b12, 5, 3), 0, 6)
  v[M.VOICE.algorithm] = clamp(get_bits(b12, 2, 0), 0, 7)

  local b13 = bytes[14] or 0
  v[M.VOICE.lfo_pms] = clamp(get_bits(b13, 5, 3), 0, 7)
  v[M.VOICE.lfo_ams] = clamp(get_bits(b13, 1, 0), 0, 3)

  local b14 = bytes[15] or 0
  v[M.VOICE.lfo_wave] = clamp(get_bits(b14, 6, 5), 0, 3)

  v[M.VOICE.transpose] = bytes[16] or 0

  local b7a = bytes[59] or 0
  v[M.VOICE.poly_mode] = get_bits(b7a,7,7)
  v[M.VOICE.portamento_time] = get_bits(b7a,6,0)

  local b7b = bytes[60] or 0
  v[M.VOICE.controller_set] = clamp(get_bits(b7b,6,4), 0, 4)
  v[M.VOICE.pitchbend_range]= clamp(get_bits(b7b,3,0), 0, 12)

  return v
end

local function decode_op(bytes, base)
  local o = {}
  local b50 = bytes[base+1] or 0
  o[M.OP.volume] = clamp(get_bits(b50,6,0), 0, 127)

  local b51 = bytes[base+2] or 0
  local type0 = get_bits(b51,7,7)
  o[M.OP.level_velocity] = clamp(get_bits(b51,6,4), 0, 7)

  local b52 = bytes[base+3] or 0
  o[M.OP.level_depth] = clamp(hi_nib(b52), 0, 15)
  o[M.OP.adjust]      = clamp(lo_nib(b52), 0, 15)

  local b53 = bytes[base+4] or 0
  local type1 = get_bits(b53,7,7)
  o[M.OP.level_curb] = (type1<<1) | type0
  o[M.OP.fine]   = clamp(get_bits(b53,6,4), 0, 7)
  o[M.OP.coarse] = clamp(get_bits(b53,3,0), 0, 15)

  local b54 = bytes[base+5] or 0
  o[M.OP.rate_depth] = clamp(get_bits(b54,7,6), 0, 3)
  o[M.OP.attack]     = clamp(get_bits(b54,4,0), 0, 31)

  local b55 = bytes[base+6] or 0
  local carrier = get_bits(b55,7,7)
  o[M.OP.modulator] = carrier==1 and 0 or 1
  o[M.OP.attack_velocity] = clamp(get_bits(b55,6,5), 0, 3)
  o[M.OP.decay1]          = clamp(get_bits(b55,4,0), 0, 31)

  local b56 = bytes[base+7] or 0
  o[M.OP.multiple] = clamp(get_bits(b56,7,6), 0, 3)
  o[M.OP.decay2]   = clamp(get_bits(b56,4,0), 0, 31)

  local b57 = bytes[base+8] or 0
  o[M.OP.sustain] = clamp(hi_nib(b57), 0, 15)
  o[M.OP.release] = clamp(lo_nib(b57), 0, 15)

  return o
end


-- B2.16: Voice name (7 bytes) + user code (1 byte) + preserve unknown bytes via base block
local function decode_name_and_meta(bytes)
  local chars = {}
  for i=1,7 do
    local c = bytes[i] or 0
    if c < 32 or c > 126 then c = 32 end
    chars[#chars+1] = string.char(c)
  end
  local name = table.concat(chars)
  local user_code = bytes[8] or 0
  local breath = bytes[61] or 0 -- placeholder until confirmed
  return name, user_code, breath
end

local function encode_name_and_meta(bytes, name, user_code, breath)
  name = tostring(name or "")
  if #name < 7 then name = name .. string.rep(" ", 7-#name) end
  if #name > 7 then name = string.sub(name, 1, 7) end
  for i=1,7 do
    bytes[i] = u8(string.byte(name, i) or 32)
  end
  bytes[8] = u8(user_code or 0)
  if breath ~= nil then bytes[61] = u8(breath or 0) end
end

function M.decode_voice_block(bytes64)
  local bytes = bytes64 or {}
  local voice_vals = decode_global(bytes)
  local op_vals = {{},{},{},{}}
  op_vals[1] = decode_op(bytes, 16)
  op_vals[2] = decode_op(bytes, 24)
  op_vals[3] = decode_op(bytes, 32)
  op_vals[4] = decode_op(bytes, 40)
  local name, user_code, breath = decode_name_and_meta(bytes)
  local meta = {name=name, user_code=user_code, breath=breath}
  return voice_vals, op_vals, meta, bytes
end

local function encode_global(voice_vals, bytes)
  local v = voice_vals or {}
  bytes[9]  = u8(v[M.VOICE.lfo_speed] or 0)

  local b9 = 0
  b9 = set_bits(b9,7,7, v[M.VOICE.lfo_load] or 0)
  b9 = set_bits(b9,6,0, v[M.VOICE.lfo_amd]  or 0)
  bytes[10] = b9

  local b10 = 0
  b10 = set_bits(b10,7,7, v[M.VOICE.lfo_key_sync] or 0)
  b10 = set_bits(b10,6,0, v[M.VOICE.lfo_pmd]      or 0)
  bytes[11] = b10

  local mask = 0
  if (v[M.VOICE.op1_enable] or 0) ~= 0 then mask = mask | 0x01 end
  if (v[M.VOICE.op2_enable] or 0) ~= 0 then mask = mask | 0x02 end
  if (v[M.VOICE.op3_enable] or 0) ~= 0 then mask = mask | 0x04 end
  if (v[M.VOICE.op4_enable] or 0) ~= 0 then mask = mask | 0x08 end
  bytes[12] = u8((mask & 0x0F) << 3)

  local b12 = 0
  b12 = set_bits(b12,5,3, clamp(v[M.VOICE.feedback] or 0, 0, 6))
  b12 = set_bits(b12,2,0, clamp(v[M.VOICE.algorithm] or 0, 0, 7))
  bytes[13] = b12

  local b13 = 0
  b13 = set_bits(b13,5,3, clamp(v[M.VOICE.lfo_pms] or 0, 0, 7))
  b13 = set_bits(b13,1,0, clamp(v[M.VOICE.lfo_ams] or 0, 0, 3))
  bytes[14] = b13

  local b14 = 0
  b14 = set_bits(b14,6,5, clamp(v[M.VOICE.lfo_wave] or 0, 0, 3))
  bytes[15] = b14

  bytes[16] = u8(v[M.VOICE.transpose] or 0)

  local b7a = 0
  b7a = set_bits(b7a,7,7, v[M.VOICE.poly_mode] or 0)
  b7a = set_bits(b7a,6,0, v[M.VOICE.portamento_time] or 0)
  bytes[59] = b7a

  local b7b = 0
  b7b = set_bits(b7b,6,4, clamp(v[M.VOICE.controller_set] or 0, 0, 4))
  b7b = set_bits(b7b,3,0, clamp(v[M.VOICE.pitchbend_range] or 0, 0, 12))
  bytes[60] = b7b
end

local function encode_op(o, bytes, base)
  o = o or {}
  bytes[base+1] = u8(clamp(o[M.OP.volume] or 0, 0, 127))

  local type = clamp(o[M.OP.level_curb] or 0, 0, 3)
  local type0 = type & 0x01
  local type1 = (type >> 1) & 0x01

  local b51 = 0
  b51 = set_bits(b51,7,7, type0)
  b51 = set_bits(b51,6,4, clamp(o[M.OP.level_velocity] or 0, 0, 7))
  bytes[base+2] = b51

  bytes[base+3] = pack_nibs(clamp(o[M.OP.level_depth] or 0,0,15), clamp(o[M.OP.adjust] or 0,0,15))

  local b53 = 0
  b53 = set_bits(b53,7,7, type1)
  b53 = set_bits(b53,6,4, clamp(o[M.OP.fine] or 0, 0, 7))
  b53 = set_bits(b53,3,0, clamp(o[M.OP.coarse] or 0, 0, 15))
  bytes[base+4] = b53

  local b54 = 0
  b54 = set_bits(b54,7,6, clamp(o[M.OP.rate_depth] or 0, 0, 3))
  b54 = set_bits(b54,4,0, clamp(o[M.OP.attack] or 0, 0, 31))
  bytes[base+5] = b54

  local b55 = 0
  local mod = (o[M.OP.modulator] or 0) ~= 0 and 1 or 0
  local carrier = mod==1 and 0 or 1
  b55 = set_bits(b55,7,7, carrier)
  b55 = set_bits(b55,6,5, clamp(o[M.OP.attack_velocity] or 0, 0, 3))
  b55 = set_bits(b55,4,0, clamp(o[M.OP.decay1] or 0, 0, 31))
  bytes[base+6] = b55

  local b56 = 0
  b56 = set_bits(b56,7,6, clamp(o[M.OP.multiple] or 0, 0, 3))
  b56 = set_bits(b56,4,0, clamp(o[M.OP.decay2] or 0, 0, 31))
  bytes[base+7] = b56

  bytes[base+8] = pack_nibs(clamp(o[M.OP.sustain] or 0,0,15), clamp(o[M.OP.release] or 0,0,15))
end

function M.encode_voice_block(voice_vals, op_vals, base_bytes, meta)
  local bytes={}
  if base_bytes and type(base_bytes)=="table" then
    for i=1,64 do bytes[i]=u8(base_bytes[i] or 0) end
  else
    for i=1,64 do bytes[i]=0 end
  end
  if meta then
    encode_name_and_meta(bytes, meta.name, meta.user_code, meta.breath)
  end
  encode_global(voice_vals, bytes)
  op_vals = op_vals or {{},{},{},{}}
  encode_op(op_vals[1], bytes, 16)
  encode_op(op_vals[2], bytes, 24)
  encode_op(op_vals[3], bytes, 32)
  encode_op(op_vals[4], bytes, 40)
  return bytes
end

return M
