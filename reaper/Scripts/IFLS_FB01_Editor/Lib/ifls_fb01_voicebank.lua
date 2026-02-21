local M = {}

local function is_printable7(bytes7)
  for i=1,7 do
    local c = bytes7[i] or 0
    if c < 32 or c > 126 then return false end
  end
  return true
end

local function nibble_decode(nibs)
  local out={}
  local n = #nibs
  local i=1
  while i<=n-1 do
    local lo = nibs[i] & 0x0F
    local hi = nibs[i+1] & 0x0F
    out[#out+1] = ((hi<<4) | lo)
    i=i+2
  end
  return out
end

-- Deterministic decode of 48-voice bank dumps commonly found in .syx archives (size ~6363 bytes).
-- Layout (derived from real-world bank dumps):
--   Sysex: F0 43 75 0s 00 00 <bankNo> <bankHeader(66 bytes)> <48 blocks * 131 bytes> <checksum> F7
--   Each 131-byte block: <marker u7> + <130 nibbles> => 65 decoded bytes (voice payload),
--   voice name is first 7 bytes of decoded payload.
function M.decode_voicebank_from_sysex(bytes)
  if not bytes or #bytes < 100 then return nil, "too short" end
  if bytes[1] ~= 0xF0 or bytes[2] ~= 0x43 or bytes[3] ~= 0x75 or bytes[#bytes] ~= 0xF7 then
    return nil, "not Yamaha FB-01 sysex"
  end
  -- expect bulk bank data in many archives
  if bytes[5] ~= 0x00 or bytes[6] ~= 0x00 then
    return nil, "not bulk voicebank (op/type mismatch)"
  end
  local payload = {}
  for i=7, (#bytes-2) do payload[#payload+1] = bytes[i] end -- include bankNo at payload[1]
  if #payload < (67 + 48*131) then
    return nil, "payload too short"
  end
  local bank_no = payload[1] or 0
  local voice0 = 68 -- 1-based index inside payload where voice blocks start (offset 67)
  local voices={}
  local p = voice0
  for v=1,48 do
    local marker = payload[p]
    local nibs={}
    for i=p+1, p+130 do nibs[#nibs+1] = payload[i] end
    local decoded = nibble_decode(nibs) -- 65 bytes
    local name_bytes={}
    for i=1,7 do name_bytes[i]=decoded[i] or 32 end
    local name="???????"
    if is_printable7(name_bytes) then
      local chars={}
      for i=1,7 do chars[i]=string.char(name_bytes[i]) end
      name = table.concat(chars)
    end
    voices[#voices+1] = { index=v-1, name=name, marker=marker, payload_bytes=decoded }
    p = p + 131
  end
  return { kind="voicebank", bank_no=bank_no, voices=voices, checksum=bytes[#bytes-1], size=#bytes }, nil
end

return M
