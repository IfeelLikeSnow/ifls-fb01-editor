local M = {}
local function slice(t,a,b) local o={} for i=a,b do o[#o+1]=t[i] end return o end
local function all_nibbles(tbl, start_i, count)
  for i=start_i, start_i+count-1 do local v=tbl[i]; if v==nil or v<0 or v>15 then return false end end
  return true
end
local function decode_nibbles_to_bytes(nibbles)
  local out={}
  local i=1
  while i<=#nibbles-1 do
    local lo=nibbles[i]&0x0F; local hi=nibbles[i+1]&0x0F
    out[#out+1]=(hi<<4)|lo
    i=i+2
  end
  return out
end
local function encode_bytes_to_nibbles(bytes)
  local out={}
  for i=1,#bytes do local b=bytes[i]&0xFF; out[#out+1]=b&0x0F; out[#out+1]=(b>>4)&0x0F end
  return out
end
local function checksum_byte_yamaha7(bytes_no_f0)
  local sum=0
  for i=1,#bytes_no_f0 do sum = sum + (bytes_no_f0[i] & 0x7F) end
  return ((-sum) & 0x7F)
end
local function detect_payload_start(msg)
  for i=1,#msg-8 do if all_nibbles(msg,i,8) then return i end end
  return nil
end
function M.decode_voice_from_sysex(msg)
  if not msg or #msg<16 then return nil,"short msg" end
  if msg[1]~=0xF0 or msg[#msg]~=0xF7 then return nil,"not sysex" end
  local payload_start = detect_payload_start(msg)
  if not payload_start then return nil,"no nibble payload detected" end
  local checksum_pos = #msg-1
  local nibs = slice(msg, payload_start, checksum_pos-1)
  local payload_bytes = decode_nibbles_to_bytes(nibs)
  if #payload_bytes < 64 then return nil,"payload too short" end
  local voice_offset = #payload_bytes - 64
  local voice_bytes = slice(payload_bytes, voice_offset+1, voice_offset+64)
  local chars={}
      for i=1,7 do
        local c=(voice_bytes[i] or 32) & 0xFF
        if c<32 or c>126 then c=32 end
        chars[#chars+1]=string.char(c)
      end
      local meta={name=table.concat(chars), user_code=(voice_bytes[8] or 0)&0xFF, breath=(voice_bytes[61] or 0)&0xFF}
      return {payload_start=payload_start, payload_bytes=payload_bytes, voice_bytes=voice_bytes, voice_offset=voice_offset, meta=meta,
          template={prefix=slice(msg,1,payload_start-1)}}
end
function M.build_voice_sysex_from_template(template, payload_bytes)
  if not template or not template.prefix then return nil,"no template" end
  if not payload_bytes then return nil,"no payload" end
  local nibs = encode_bytes_to_nibbles(payload_bytes)
  local msg={}
  for i=1,#template.prefix do msg[#msg+1]=template.prefix[i] end
  for i=1,#nibs do msg[#msg+1]=nibs[i] end
  local chk_range={}
  for i=2,#msg do chk_range[#chk_range+1]=msg[i] end
  local chk=checksum_byte_yamaha7(chk_range)
  msg[#msg+1]=chk; msg[#msg+1]=0xF7
  return msg
end
function M.replace_voice_bytes(payload_bytes, voice_offset, new_voice_64)
  local out={}
  for i=1,#payload_bytes do out[i]=payload_bytes[i]&0xFF end
  for i=1,64 do out[voice_offset+i]=(new_voice_64[i] or 0) & 0xFF end
  return out
end


-- B2.27: Build a deterministic "Instrument Voice Data" SysEx message from a 64-byte voice payload.
-- Header matches the documented "Dump Instrument i Voice Data" request, but with nibble payload appended:
--   F0 43 75 0s 2i 05 00 <nibbles...> <checksum> F7
-- NOTE: This is used for exporting/sending single-voice data. Some devices/tools treat this as a bulk write.
function M.build_inst_voice_sysex(sys_ch, inst_no, voice_64)
  sys_ch = tonumber(sys_ch) or 0
  inst_no = tonumber(inst_no) or 0
  local inst_byte = 0x20 + (inst_no & 0x07)
  local prefix = {0xF0, 0x43, 0x75, (sys_ch & 0x0F), inst_byte, 0x05, 0x00}
  local payload_bytes = {}
  for i=1,64 do payload_bytes[i] = (voice_64[i] or 0) & 0xFF end
  local nibs = encode_bytes_to_nibbles(payload_bytes)
  local msg={}
  for i=1,#prefix do msg[#msg+1]=prefix[i] end
  for i=1,#nibs do msg[#msg+1]=nibs[i] end
  local chk_range={}
  for i=2,#msg do chk_range[#chk_range+1]=msg[i] end
  local chk=checksum_byte_yamaha7(chk_range)
  msg[#msg+1]=chk
  msg[#msg+1]=0xF7
  return msg
end



-- B2.28: Decode "Instrument Voice Data" SysEx, returning sys_ch, inst_no, and voice64 bytes.
function M.decode_inst_voice_from_sysex(bytes)
  if not bytes or #bytes < 16 then return nil, "too short" end
  if bytes[1] ~= 0xF0 or bytes[2] ~= 0x43 or bytes[3] ~= 0x75 or bytes[#bytes] ~= 0xF7 then
    return nil, "not FB-01 sysex"
  end
  local sys_ch = bytes[4] & 0x0F
  local inst_byte = bytes[5] & 0x7F
  local inst_no = inst_byte - 0x20
  if inst_no < 0 or inst_no > 7 then inst_no = inst_no & 0x07 end
  -- reuse generic decoder (nibble data at end)
  local v, err = M.decode_voice_from_sysex(bytes)
  if not v then return nil, err end
  return {sys_ch=sys_ch, inst_no=inst_no, voice_bytes=v.voice_bytes}, nil
end

return M
