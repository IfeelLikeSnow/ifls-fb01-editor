
-- FB-01 Dump Decoder (B2.3)
-- Heuristic decoder for Yamaha nibblized bulk dumps + checksum verification.
-- Provides:
--   decode_last_dump(syx_bytes) -> {ok, checksum_ok, decoded, names, info}

local M = {}

local function is_nibble(b) return b ~= nil and b >= 0 and b < 16 end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function slice(t, a, b)
  local out = {}
  for i=a,b do out[#out+1]=t[i] end
  return out
end

local function bytes_to_hex(t, maxn)
  maxn = maxn or #t
  local n = math.min(#t, maxn)
  local s={}
  for i=1,n do s[#s+1]=string.format("%02X", t[i] & 0xFF) end
  if #t > n then s[#s+1]="…" end
  return table.concat(s," ")
end

-- Yamaha bulk checksum rule (7-bit):
-- sum of bytes from SS..KK inclusive == 0 (mod 128)
-- We verify on a range that includes the checksum byte.
local function checksum_ok(range)
  local sum = 0
  for i=1,#range do sum = (sum + (range[i] & 0x7F)) end
  return (sum & 0x7F) == 0
end

-- Find start index of nibble-encoded payload:
-- look for first index where next 8 bytes are all nibbles (<16)
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

local function extract_printable_runs(data, min_len, max_len, want)
  min_len = min_len or 6
  max_len = max_len or 12
  want = want or 48
  local names={}
  local i=1
  while i <= #data do
    local b=data[i]
    if b >= 32 and b <= 126 then
      local j=i
      while j<=#data and data[j] >= 32 and data[j] <= 126 do j=j+1 end
      local len = j - i
      if len >= min_len then
        local take = clamp(len, min_len, max_len)
        local s={}
        for k=i,i+take-1 do s[#s+1]=string.char(data[k]) end
        local str = table.concat(s)
        -- basic cleanup
        str = str:gsub("%s+$","")
        if #str >= min_len then
          names[#names+1]=str
          if #names >= want then break end
        end
      end
      i=j
    else
      i=i+1
    end
  end
  return names
end

function M.decode_sysex(msg)
  if not msg or #msg < 8 then
    return {ok=false, error="msg too short"}
  end
  if msg[1] ~= 0xF0 or msg[#msg] ~= 0xF7 then
    return {ok=false, error="not a sysex (missing F0/F7)"}
  end

  local info = {
    header = bytes_to_hex(slice(msg, 1, math.min(12, #msg))),
    len = #msg
  }

  -- Find candidate checksum byte: last before F7
  local checksum = msg[#msg-1]
  info.checksum_byte = checksum

  -- Try to locate nibble payload start
  local start = find_payload_start(msg, 1, #msg-2)
  if not start then
    return {ok=false, error="no nibble payload found", info=info}
  end

  -- Payload nibble bytes = start..(#msg-2-1) (exclude checksum)
  local nibs = slice(msg, start, #msg-2-1)
  local decoded = decode_nibbles(nibs)

  -- Checksum verify range heuristic:
  -- take bytes from manufacturer (0x43) up to checksum byte inclusive, but 7-bit masked
  local chk_range = slice(msg, 2, #msg-1)
  local chk_ok = checksum_ok(chk_range)

  info.payload_start = start
  info.payload_nibbles = #nibs
  info.decoded_len = #decoded
  info.checksum_ok = chk_ok

  -- Extract name-like printable runs
  local names = extract_printable_runs(decoded, 6, 12, 48)
  info.names_found = #names

  return {ok=true, checksum_ok=chk_ok, decoded=decoded, names=names, info=info}
end

return M
