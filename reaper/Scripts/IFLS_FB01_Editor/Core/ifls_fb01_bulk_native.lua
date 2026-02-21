-- @description IFLS FB-01 Native Bulk Builder (Phase 10)
-- @version 1.0.0
-- @author IFLS
-- @about
--   Best-effort native bulk SysEx builders based on Yamaha FB-01 Service Manual.
--   These builders are OPTIONAL/EXPERIMENTAL; preferred workflow remains capture+replay for maximum compatibility.
--
--   Manual notes (see service manual):
--   - Bulk data uses nibble-encoded payload (low nibble then high nibble) and Yamaha 7-bit checksum.
--   - Larger bulks should be sent in multiple messages with >100ms interval.

local M = {}

local function checksum7(bytes)
  local s = 0
  for i=1,#bytes do s = (s + (bytes[i] & 0x7F)) & 0x7F end
  return ((-s) & 0x7F)
end

-- Compute Yamaha-style 7-bit checksum over a slice of an array.
-- start_i/end_i are 1-based inclusive indices.
local function checksum7_slice(bytes, start_i, end_i)
  local s = 0
  start_i = start_i or 1
  end_i = end_i or #bytes
  for i=start_i,end_i do s = (s + (bytes[i] & 0x7F)) & 0x7F end
  return ((-s) & 0x7F)
end

-- Convenience: validate that sum(slice + checksum) == 0 (mod 128)
local function validate_checksum7(bytes, start_i, end_i, checksum_byte)
  local s = 0
  for i=start_i,end_i do s = (s + (bytes[i] & 0x7F)) & 0x7F end
  s = (s + (checksum_byte & 0x7F)) & 0x7F
  return s == 0
end

local function pack_nibbles_lohi(b)
  return (b & 0x0F), ((b >> 4) & 0x0F)
end

local function is_table(t) return type(t) == "table" end

local function append(dst, src)
  for i=1,#src do dst[#dst+1]=src[i] end
end

-- Build ONE VOICE BULK as a single message (EXPERIMENTAL).
-- Format is based on service manual table; some devices/interfaces may prefer capture+replay.
-- voice64: 64 source bytes (0..255)
function M.build_one_voice_bulk(sys_ch, inst_no, voice64, opts)
  opts = opts or {}
  sys_ch = tonumber(sys_ch) or 0
  inst_no = tonumber(inst_no) or 0
  if not is_table(voice64) or #voice64 < 64 then return nil, "voice64 must be a 64-byte table" end

  local msgno = 0x08 + (inst_no & 0x07) -- 00001iii

  -- Header fields (best-effort):
  -- op0/op1 fixed 00 00, then a bytecount marker 01, then 00 (reserved)
  local body = {0x43, 0x75, (sys_ch & 0x0F), msgno, 0x00, 0x00, 0x01, 0x00}

  -- Nibble payload low/high sequential
  for i=1,64 do
    local lo,hi = pack_nibbles_lohi(voice64[i] & 0xFF)
    body[#body+1]=lo
    body[#body+1]=hi
  end

  -- Checksum region can be device-dependent; default is msgno..end.
  local cs_start = opts.checksum_from_body_index or 4
  local cs = checksum7_slice(body, cs_start, #body)
  if opts.strict_checksum then
    if not validate_checksum7(body, cs_start, #body, cs) then
      return nil, "checksum self-check failed"
    end
  end
  body[#body+1]=cs

  -- Wrap SysEx
  local out = {0xF0}
  append(out, body)
  out[#out+1]=0xF7
  return out
end

-- Build BANK BULK as multiple messages with per-message bytecount.
-- voices: array of 48 voice blocks (each 64 bytes)
-- Returns: list of sysex byte tables
function M.build_bank_bulk(sys_ch, bank_no, voices, chunk_source_bytes, opts)
  opts = opts or {}
  sys_ch = tonumber(sys_ch) or 0
  bank_no = tonumber(bank_no) or 0
  chunk_source_bytes = tonumber(chunk_source_bytes) or 48 -- 48 source bytes => 96 nibble bytes (<=127)

  if not is_table(voices) or #voices < 1 then return nil, "voices must be a table of voice blocks" end

  -- Flatten payload (48*64 = 3072 source bytes)
  local src = {}
  for v=1,#voices do
    local vb = voices[v]
    if is_table(vb) and #vb >= 64 then
      for i=1,64 do src[#src+1] = vb[i] & 0xFF end
    end
  end
  if #src == 0 then return nil, "no voice data" end

  local msgs = {}
  local pos = 1
  -- Manual indicates MessageNo=00H and Operation=00H for bank bulk; bank number present.
  local msgno = 0x00
  local op0, op1 = 0x00, 0x00

  while pos <= #src do
    local n = math.min(chunk_source_bytes, #src - pos + 1)
    local nibcnt = (n * 2)
    local body
    if opts.bytecount_two_bytes then
      local bc_m = ((nibcnt >> 7) & 0x7F)
      local bc_l = (nibcnt & 0x7F)
      body = {0x43, 0x75, (sys_ch & 0x0F), msgno, op0, op1, (bank_no & 0x7F), bc_m, bc_l}
    else
      local bytecount = (nibcnt & 0x7F)
      body = {0x43, 0x75, (sys_ch & 0x0F), msgno, op0, op1, (bank_no & 0x7F), bytecount}
    end

    for i=0,n-1 do
      local lo,hi = pack_nibbles_lohi(src[pos+i])
      body[#body+1]=lo
      body[#body+1]=hi
    end

    local cs_start = opts.checksum_from_body_index or 4
    local cs = checksum7_slice(body, cs_start, #body)
    if opts.strict_checksum then
      if not validate_checksum7(body, cs_start, #body, cs) then
        return nil, "checksum self-check failed"
      end
    end
    body[#body+1]=cs

    local out = {0xF0}
    append(out, body)
    out[#out+1]=0xF7
    msgs[#msgs+1]=out

    pos = pos + n
  end

  return msgs
end


-- Build CONFIG MEMORY BULK (best-effort, EXPERIMENTAL).
-- type_no: 0..15 (service manual 'configuration memory dump' types)
-- data: byte array (source bytes)
-- This builder is conservative and intended for advanced testing; default workflow remains capture+replay.
function M.build_config_memory_bulk(sys_ch, type_no, data, chunk_source_bytes, opts)
  opts = opts or {}
  sys_ch = tonumber(sys_ch) or 0
  type_no = tonumber(type_no) or 0
  chunk_source_bytes = tonumber(chunk_source_bytes) or 48

  if not is_table(data) or #data < 1 then return nil, "data must be a byte table" end

  local src = {}
  for i=1,#data do src[#src+1] = data[i] & 0xFF end

  local msgs = {}
  local pos = 1
  local msgno = 0x00
  local op0, op1 = 0x00, 0x00  -- placeholder; some manuals use op codes per config class

  while pos <= #src do
    local n = math.min(chunk_source_bytes, #src - pos + 1)
    local nibcnt = (n * 2)
    local body
    if opts.bytecount_two_bytes then
      local bc_m = ((nibcnt >> 7) & 0x7F)
      local bc_l = (nibcnt & 0x7F)
      body = {0x43, 0x75, (sys_ch & 0x0F), msgno, op0, op1, (type_no & 0x7F), bc_m, bc_l}
    else
      body = {0x43, 0x75, (sys_ch & 0x0F), msgno, op0, op1, (type_no & 0x7F), (nibcnt & 0x7F)}
    end

    for i=0,n-1 do
      local lo,hi = pack_nibbles_lohi(src[pos+i])
      body[#body+1]=lo
      body[#body+1]=hi
    end

    local cs_start = opts.checksum_from_body_index or 4
    local cs = checksum7_slice(body, cs_start, #body)
    if opts.strict_checksum then
      if not validate_checksum7(body, cs_start, #body, cs) then
        return nil, "checksum self-check failed"
      end
    end
    body[#body+1]=cs

    local out = {0xF0}
    append(out, body)
    out[#out+1]=0xF7
    msgs[#msgs+1]=out

    pos = pos + n
  end

  return msgs
end

return M
