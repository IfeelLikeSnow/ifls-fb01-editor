
-- ifls_fb01_bank.lua
-- B2.4: FB-01 Voice Bank (.syx) decoder (48 voices) + name extraction.
-- Conservative/robust: nibble-payload detection, checksum heuristic, 48x64 voice blocks.

local M = {}

local function is_nibble(b) return b ~= nil and b >= 0 and b < 16 end

local function slice(t, a, b)
  local out = {}
  for i=a,b do out[#out+1]=t[i] end
  return out
end

local function find_payload_start(msg, start_i, end_i)
  start_i = start_i or 1
  end_i = end_i or #msg
  for i=start_i, end_i-8 do
    local ok = true
    for k=0,7 do
      if not is_nibble(msg[i+k]) then ok=false break end
    end
    if ok then return i end
  end
  return nil
end

local function decode_nibbles(nibs)
  local out={}
  local n = #nibs - (#nibs % 2)
  for i=1,n,2 do
    local l = nibs[i] & 0x0F
    local h = nibs[i+1] & 0x0F
    out[#out+1] = ((h << 4) | l) & 0xFF
  end
  return out
end

local function checksum_ok_yamaha7(range)
  -- Yamaha: 7-bit sum of bytes including checksum == 0 mod 128
  local sum = 0
  for i=1,#range do sum = sum + (range[i] & 0x7F) end
  return (sum & 0x7F) == 0
end

local function to_string(bytes, a, n)
  local s={}
  for i=a,a+n-1 do
    local b = bytes[i] or 32
    if b < 32 or b > 126 then b = 32 end
    s[#s+1]=string.char(b)
  end
  local str = table.concat(s):gsub("%s+$","")
  return str
end

local function find_largest_sysex(bytes)
  -- bytes may contain multiple sysex messages; return largest F0..F7 slice
  local best=nil
  local i=1
  while i<=#bytes do
    if bytes[i]==0xF0 then
      local j=i+1
      while j<=#bytes and bytes[j]~=0xF7 do j=j+1 end
      if j<=#bytes and bytes[j]==0xF7 then
        local msg=slice(bytes,i,j)
        if not best or #msg > #best then best=msg end
        i=j+1
      else
        break
      end
    else
      i=i+1
    end
  end
  return best
end

function M.decode_voice_bank_from_sysex(msg)
  if not msg or #msg < 8 then return nil, "sysex too short" end
  if msg[1] ~= 0xF0 or msg[#msg] ~= 0xF7 then return nil, "not a sysex" end

  local payload_start = find_payload_start(msg, 1, #msg-2)
  if not payload_start then return nil, "no nibble payload detected" end

  local template = {prefix = slice(msg, 1, payload_start-1)}

  local nibs = slice(msg, payload_start, #msg-3) -- exclude checksum and F7
  local decoded = decode_nibbles(nibs)

  -- Heuristic: voice bank payload should contain at least 32 + 48*64 = 3104 bytes
  local NEED = 32 + (48*64)
  if #decoded < NEED then
    return nil, "decoded payload too small ("..tostring(#decoded)..")"
  end

  local payload = slice(decoded, 1, NEED)
  local bank_name = to_string(payload, 1, 8)

  local voices={}
  for v=0,47 do
    local base = 33 + (v*64) -- 1-based; skip 32 bytes header
    local name = to_string(payload, base, 8)
    voices[#voices+1] = {index=v, name=name, bytes=slice(payload, base, base+63)}
  end

  -- checksum heuristic range: bytes from manufacturer (0x43) to checksum inclusive
  local chk_ok = checksum_ok_yamaha7(slice(msg, 2, #msg-1))

  return {
    bank_name = bank_name,
    voices = voices,
    payload = payload,
    checksum_ok = chk_ok,
    decoded_len = #decoded,
    payload_start = payload_start,
    template = template
  }
end

function M.decode_voice_bank_from_filebytes(filebytes)
  local msg = find_largest_sysex(filebytes)
  if not msg then return nil, "no sysex message found" end
  return M.decode_voice_bank_from_sysex(msg)
end



-- B2.7: Template-based bank export (reuse original prefix, recompute checksum)
local function encode_nibbles(bytes)
  local out = {}
  for i=1,#bytes do
    local b = bytes[i] & 0xFF
    out[#out+1] = b & 0x0F
    out[#out+1] = (b >> 4) & 0x0F
  end
  return out
end

local function checksum_byte_yamaha7(bytes_no_f0)
  -- checksum = (-sum(bytes)) & 0x7F
  local sum = 0
  for i=1,#bytes_no_f0 do sum = sum + (bytes_no_f0[i] & 0x7F) end
  return ((-sum) & 0x7F)
end

function M.build_sysex_from_template(template, payload_bytes)
  if not template or not template.prefix then return nil, "no template" end
  if not payload_bytes then return nil, "no payload" end
  local nibs = encode_nibbles(payload_bytes)
  local msg = {}
  for i=1,#template.prefix do msg[#msg+1] = template.prefix[i] end
  for i=1,#nibs do msg[#msg+1] = nibs[i] end
  local chk_range = {}
  for i=2,#msg do chk_range[#chk_range+1] = msg[i] end
  local chk = checksum_byte_yamaha7(chk_range)
  msg[#msg+1] = chk
  msg[#msg+1] = 0xF7
  return msg
end

function M.payload_from_voice_blocks(bank_name, voice_blocks_48x64)
  -- payload length: 32 + 48*64 = 3104 bytes (8 bank name + 24 reserved + voices)
  local payload = {}
  local bn = tostring(bank_name or ""):sub(1,8)
  while #bn < 8 do bn = bn .. " " end
  for i=1,8 do payload[#payload+1] = string.byte(bn, i) end
  for i=1,24 do payload[#payload+1] = 0 end
  for v=1,48 do
    local blk = voice_blocks_48x64[v] or {}
    for i=1,64 do payload[#payload+1] = (blk[i] or 0) & 0xFF end
  end
  return payload
end

return M
