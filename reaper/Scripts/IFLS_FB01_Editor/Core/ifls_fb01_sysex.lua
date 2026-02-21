-- @description IFLS FB-01 Core SysEx Library
-- @version 0.90.0
-- @author IFLS
-- @about
--   SysEx builders for Yamaha FB-01 (derived from open-source editors).
--   Provides parameter-change and dump-request messages.
--
--   Notes:
--   - Voice/Operator values are encoded as 8-bit values split into 2 nibbles (lo/hi), each 0..15.
--   - Instrument values are 7-bit (0..127).
--   - Checksum for bulk dumps: (-sum(data)) & 0x7F

local M = {}
-- B2.8: nibble packing helper (FB-01 voice data uses 2 bytes: low nibble first, then high nibble)
local function pack_nibbles_lohi(data7)
  local lo = data7 & 0x0F
  local hi = (data7 >> 4) & 0x0F
  return lo, hi
end


-- Yamaha Manufacturer ID
local ID_YAMAHA = 0x43

-- FB-01 model group byte used by the editors
local FB01_GROUP = 0x75

-- Default SysEx channel (0..15). The editors call this SysChannel.
M.DEFAULT_SYSCH = 0 -- you can override in caller

-- Helpers
local function b(x) return string.char(x & 0xFF) end

function M.pack_nibbles(v8)
  v8 = math.floor(tonumber(v8) or 0)
  if v8 < 0 then v8 = 0 elseif v8 > 255 then v8 = 255 end
  local lo = v8 & 0x0F
  local hi = (v8 >> 4) & 0x0F
  return lo, hi
end

function M.unpack_nibbles(lo, hi)
  lo = (tonumber(lo) or 0) & 0x0F
  hi = (tonumber(hi) or 0) & 0x0F
  return (hi << 4) | lo
end

function M.checksum_neg_sum(bytes_tbl)
  local sum = 0
  for i=1,#bytes_tbl do sum = sum + (bytes_tbl[i] & 0x7F) end
  return (-sum) & 0x7F
end

-- Frame a SysEx body into a complete message
function M.frame(body)
  return b(0xF0) .. body .. b(0xF7)
end

-- Voice parameter change (8-bit value, nibble-split)
-- Format from Voice::Envoyer in both repos:
-- F0 43 75 sysCh (0x18 + (instId&7)) (0x40+param) lo hi F7
function M.voice_param(sysCh, instId, param, value8)
  sysCh = tonumber(sysCh) or M.DEFAULT_SYSCH
  instId = tonumber(instId) or 0
  param = tonumber(param) or 0
  local lo, hi = M.pack_nibbles(value8)
  local body = b(ID_YAMAHA) .. b(FB01_GROUP) .. b(sysCh & 0x0F)
            .. b(0x18 + (instId & 0x07))
            .. b(0x40 + (param & 0x7F))
            .. b(lo) .. b(hi)
  return M.frame(body)
end

-- Operator parameter change (8-bit value, nibble-split)
-- Operateur::Envoyer computes an address:
-- addr = param + (3-opId)*8 + 0x50   (since OPERATOR_LEN_SYSEX=0x10, /2 = 8)
-- Then sends same format as voice param, but address is (0x40+addr)
function M.operator_param(sysCh, instId, opId, param, value8)
  sysCh = tonumber(sysCh) or M.DEFAULT_SYSCH
  instId = tonumber(instId) or 0
  opId = tonumber(opId) or 0 -- 0..3 (OP1..OP4)
  param = tonumber(param) or 0
  local addr = (param & 0x7F) + (3 - (opId & 0x03)) * 8 + 0x50
  local lo, hi = M.pack_nibbles(value8)
  local body = b(ID_YAMAHA) .. b(FB01_GROUP) .. b(sysCh & 0x0F)
            .. b(0x18 + (instId & 0x07))
            .. b(0x40 + (addr & 0x7F))
            .. b(lo) .. b(hi)
  return M.frame(body)
end

-- Instrument parameter change (7-bit value)
-- Instrument::Envoyer: F0 43 75 sysCh (0x18+(instId&7)) (param&0x1F) value F7
function M.instrument_param(sysCh, instId, param, value7)
  sysCh = tonumber(sysCh) or M.DEFAULT_SYSCH
  instId = tonumber(instId) or 0
  param = tonumber(param) or 0
  value7 = math.floor(tonumber(value7) or 0)
  if value7 < 0 then value7=0 elseif value7>127 then value7=127 end
  local body = b(ID_YAMAHA) .. b(FB01_GROUP) .. b(sysCh & 0x0F)
            .. b(0x18 + (instId & 0x07))
            .. b(param & 0x1F)
            .. b(value7 & 0x7F)
  return M.frame(body)
end

-- Requests
-- Voice request: F0 43 75 sysCh (0x20 + ((instId+0x08)&0x0F)) 00 00 F7
function M.request_voice(sysCh, instId)
  sysCh = tonumber(sysCh) or M.DEFAULT_SYSCH
  instId = tonumber(instId) or 0
  local body = b(ID_YAMAHA) .. b(FB01_GROUP) .. b(sysCh & 0x0F)
            .. b(0x20 + ((instId + 0x08) & 0x0F))
            .. b(0x00) .. b(0x00)
  return M.frame(body)
end

-- Set request: F0 43 75 sysCh 20 01 00 F7
function M.request_set(sysCh)
  sysCh = tonumber(sysCh) or M.DEFAULT_SYSCH
  local body = b(ID_YAMAHA) .. b(FB01_GROUP) .. b(sysCh & 0x0F)
            .. b(0x20) .. b(0x01) .. b(0x00)
  return M.frame(body)
end

-- Bank request: F0 43 75 sysCh 20 00 bankId F7 (bankId 0..7)
function M.request_bank(sysCh, bankId)
  sysCh = tonumber(sysCh) or M.DEFAULT_SYSCH
  bankId = tonumber(bankId) or 0
  local body = b(ID_YAMAHA) .. b(FB01_GROUP) .. b(sysCh & 0x0F)
            .. b(0x20) .. b(0x00) .. b(bankId & 0x07)
  return M.frame(body)
end



-- System/Config parameter change (1 byte)
-- F0 43 75 ss 10 pp dd F7
function M.config_param(sys_ch, param_no, data7)
  sys_ch = sys_ch or 0
  param_no = param_no or 0
  data7 = data7 or 0
  local msg = {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x10, (param_no & 0x7F), (data7 & 0x7F), 0xF7}
  return msg
end


-- ===== Dump Requests (B2.2) =====
-- Based on classic FB-01 SysEx request formats:
-- F0 43 75 ss 20 00 x  F7   Dump Voice Bank x (0..6)
-- F0 43 75 ss 20 01 00 F7   Dump Current Configuration Buffer
-- F0 43 75 ss 20 02 xx F7   Dump Configuration Buffer xx (0..20)
-- F0 43 75 ss 20 03 00 F7   Dump All Configuration Memory
-- F0 43 75 ss 20 04 00 F7   Dump ID Number
-- F0 43 75 ss 2i 05 00 F7   Dump Instrument i Voice Data (i = 8+instNo 0..7)

function M.request_current_config(sys_ch)
  sys_ch = sys_ch or 0
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x20, 0x01, 0x00, 0xF7}
end

function M.request_config(sys_ch, cfg_no)
  sys_ch = sys_ch or 0
  cfg_no = cfg_no or 0
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x20, 0x02, (cfg_no & 0x7F), 0xF7}
end

function M.request_all_configs(sys_ch)
  sys_ch = sys_ch or 0
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x20, 0x03, 0x00, 0xF7}
end

function M.request_id(sys_ch)
  sys_ch = sys_ch or 0
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x20, 0x04, 0x00, 0xF7}
end

function M.request_instrument_voice(sys_ch, inst_no_1based)
  sys_ch = sys_ch or 0
  local inst0 = (inst_no_1based or 1) - 1
  if inst0 < 0 then inst0 = 0 end
  if inst0 > 7 then inst0 = 7 end
  local i = 0x28 + inst0 -- 0x28..0x2F corresponds to "2i" where i=8+inst
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), i, 0x05, 0x00, 0xF7}
end


-- B2.8: Voice parameter change by System Channel + Instrument number
-- F0 43 75 0s 1(1iii) pp 0(lo) 0(hi) F7 , pp is 0x40..0x7F
function M.voice_param_inst(sys_ch, inst_no, param_no, data7)
  sys_ch = sys_ch or 0
  inst_no = inst_no or 0 -- 0..7
  param_no = param_no or 0
  data7 = data7 or 0
  local lo, hi = pack_nibbles_lohi(data7)
  local inst_byte = 0x18 | (inst_no & 0x07)
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), inst_byte, (0x40 + (param_no & 0x3F)) & 0x7F, 0x00 | lo, 0x00 | hi, 0xF7}
end

-- B2.8: Configuration parameter change by System Channel + Instrument number (byte data)
-- F0 43 75 0s 1(1iii) pp dd F7 , pp is 0x00..0x17
function M.conf_param_inst(sys_ch, inst_no, param_no, data7)
  sys_ch = sys_ch or 0
  inst_no = inst_no or 0
  param_no = param_no or 0
  data7 = data7 or 0
  local inst_byte = 0x18 | (inst_no & 0x07)
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), inst_byte, (param_no & 0x7F), (data7 & 0x7F), 0xF7}
end





-- B2.20: System Parameter Change
-- Format: F0 43 75 0s 10 pp dd F7
function M.sys_param(sys_ch, param_no, data7)
  sys_ch = tonumber(sys_ch) or M.DEFAULT_SYSCH
  param_no = tonumber(param_no) or 0
  data7 = tonumber(data7) or 0
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x10, (param_no & 0x7F), (data7 & 0x7F), 0xF7}
end
-- B2.9: Event List wrapper
function M.event_list(events)
  local msg = {0xF0, 0x43, 0x75, 0x70}
  if events then
    for i=1,#events do
      local ev = events[i]
      for j=1,#ev do msg[#msg+1] = ev[j] & 0x7F end
    end
  end
  msg[#msg+1] = 0xF7
  return msg
end

function M.ev_inst_param2(sys_ch, param_no, data7)
  sys_ch = sys_ch or 0
  param_no = param_no or 0
  data7 = data7 or 0
  local lo, hi = pack_nibbles_lohi(data7)
  return {0x70 | (sys_ch & 0x0F), (param_no & 0x7F), (0x00 | lo), (0x00 | hi)}
end

function M.ev_inst_param1(sys_ch, param_no, data7)
  sys_ch = sys_ch or 0
  param_no = param_no or 0
  data7 = data7 or 0
  return {0x70 | (sys_ch & 0x0F), (param_no & 0x7F), (data7 & 0x7F)}
end



-- B2.22: Event List (System Exclusive Event List)
-- Header: F0 43 75 70  (terminated by F7)
-- Events are packed inside the same SysEx message.
function M.event_list_begin()
  return {0xF0, 0x43, 0x75, 0x70}
end

function M.event_list_end(msg)
  msg[#msg+1] = 0xF7
  return msg
end

-- Helpers to append common event types (see Service Manual / SynthZone)
-- Note Off with Fraction: 0n kk ff
function M.ev_note_off_frac(msg, sys_ch, key, frac)
  msg[#msg+1] = (0x00 | (sys_ch & 0x0F))
  msg[#msg+1] = (key & 0x7F)
  msg[#msg+1] = (frac & 0x7F)
  return msg
end

-- Note On/Off with Fraction: 1n kk ff vv
function M.ev_note_onoff_frac(msg, sys_ch, key, frac, vel)
  msg[#msg+1] = (0x10 | (sys_ch & 0x0F))
  msg[#msg+1] = (key & 0x7F)
  msg[#msg+1] = (frac & 0x7F)
  msg[#msg+1] = (vel & 0x7F)
  return msg
end

-- Note On/Off with Fraction and Duration: 2n kk ff vv yy xx
function M.ev_note_dur(msg, sys_ch, key, frac, vel, yy, xx)
  msg[#msg+1] = (0x20 | (sys_ch & 0x0F))
  msg[#msg+1] = (key & 0x7F)
  msg[#msg+1] = (frac & 0x7F)
  msg[#msg+1] = (vel & 0x7F)
  msg[#msg+1] = (yy & 0x7F)
  msg[#msg+1] = (xx & 0x7F)
  return msg
end

-- Control Change: 3n cc vv
function M.ev_cc(msg, sys_ch, cc, val)
  msg[#msg+1] = (0x30 | (sys_ch & 0x0F))
  msg[#msg+1] = (cc & 0x7F)
  msg[#msg+1] = (val & 0x7F)
  return msg
end

-- Program Change: 4n pp
function M.ev_program(msg, sys_ch, prog)
  msg[#msg+1] = (0x40 | (sys_ch & 0x0F))
  msg[#msg+1] = (prog & 0x7F)
  return msg
end

-- After Touch: 5n vv
function M.ev_aftertouch(msg, sys_ch, val)
  msg[#msg+1] = (0x50 | (sys_ch & 0x0F))
  msg[#msg+1] = (val & 0x7F)
  return msg
end

-- Pitch Bend: 6n py px
function M.ev_pitchbend(msg, sys_ch, py, px)
  msg[#msg+1] = (0x60 | (sys_ch & 0x0F))
  msg[#msg+1] = (py & 0x7F)
  msg[#msg+1] = (px & 0x7F)
  return msg
end

-- Inst. Param. Change (1-byte): 7n pa dd
function M.ev_inst_param_1(msg, sys_ch, pa, dd)
  msg[#msg+1] = (0x70 | (sys_ch & 0x0F))
  msg[#msg+1] = (pa & 0x7F)
  msg[#msg+1] = (dd & 0x7F)
  return msg
end

-- Inst. Param. Change (2-byte): 7n pa 0y 0x (low nibbles in y/x)
function M.ev_inst_param_2(msg, sys_ch, pa, y, x)
  msg[#msg+1] = (0x70 | (sys_ch & 0x0F))
  msg[#msg+1] = (pa & 0x7F)
  msg[#msg+1] = (y & 0x0F)
  msg[#msg+1] = (x & 0x0F)
  return msg
end



-- B2.25: Voice dump request helpers
-- Dump Voice Bank "x" (0..6): F0 43 75 0s 20 00 0x F7
function M.dump_voice_bank(sys_ch, bank_no)
  sys_ch = tonumber(sys_ch) or M.DEFAULT_SYSCH
  bank_no = tonumber(bank_no) or 0
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), 0x20, 0x00, (bank_no & 0x7F), 0xF7}
end

-- Dump Instrument "i" Voice Data: F0 43 75 0s 2i 05 00 F7
-- where 2i = 0x20 + instrument (i=8+inst# in Yamaha docs, but most dumps use 0x20+inst)
function M.dump_inst_voice(sys_ch, inst_no)
  sys_ch = tonumber(sys_ch) or M.DEFAULT_SYSCH
  inst_no = tonumber(inst_no) or 0
  local inst_byte = 0x20 + (inst_no & 0x07)
  return {0xF0, 0x43, 0x75, (sys_ch & 0x0F), inst_byte, 0x05, 0x00, 0xF7}
end



-- Phase 25: Back-compat aliases used by editor UI
function M.dump_config_slot(sys_ch, cfg_no) return M.request_config(sys_ch, cfg_no) end
function M.dump_all_config(sys_ch) return M.request_all_configs(sys_ch) end
function M.dump_inst_voice(sys_ch, inst_no0) return M.request_instrument_voice(sys_ch, (inst_no0 or 0)+1) end


return M
