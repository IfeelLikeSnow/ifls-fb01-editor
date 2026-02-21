-- @description IFLS FB-01 - Bank Send Wizard (49 packets + delay + progress)
-- @version 1.00.0
-- @author IFLS
-- @about
--   Sends a FB-01 bank dump as 49 packets with delay between packets (Edisyn-style).
--   This improves reliability on interfaces/routers that drop long SysEx.
--   Best-effort: expects a bank dump .syx containing a single long SysEx message.
--
-- Requirements: SWS (SNM_SendSysEx)

local r = reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS.", "FB-01 Bank Send Wizard", 0)
  return
end

local function read_all(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local d=f:read("*all"); f:close(); return d
end

local function split_sysex(data)
  local msgs={}
  local i=1
  while true do
    local s=data:find(string.char(0xF0), i, true); if not s then break end
    local e=data:find(string.char(0xF7), s+1, true); if not e then break end
    msgs[#msgs+1]=data:sub(s,e)
    i=e+1
  end
  return msgs
end

local function bytes_to_hex(s, n)
  n=n or 14
  local out={}
  for i=1, math.min(#s,n) do out[#out+1]=string.format("%02X", s:byte(i)) end
  return table.concat(out," ")
end

-- Heuristic packetization:
-- Many FB-01 bank dumps can be re-sent as one big message, but to improve reliability we chunk
-- into 49 F0...F7 messages by rewrapping internal data slices.
-- For true Edisyn-compat, we'd parse the exact bank format and rebuild 49 packets.
-- Here we implement a safe chunking strategy:
--  - Keep Yamaha header bytes (first 10 bytes) as a prefix
--  - Chunk remaining payload into ~120 bytes blocks
--  - Each packet: F0 + prefix + payload_chunk + checksum? + F7
-- This is best-effort and intended for transports that accept chunked messages as raw stream.
-- If your FB-01 rejects it, use single-message send or the bank dump request/write workflow.

local ok, inpath = r.GetUserFileNameForRead("", "Select FB-01 bank .syx to send", ".syx")
if not ok or not inpath or inpath=="" then return end

local ok2, csv = r.GetUserInputs("Bank Send Wizard", 2,
  "Delay ms between packets,Send mode (single|chunk49)", "120,chunk49")
if not ok2 then return end
local delay_ms, mode = csv:match("^([^,]+),([^,]+)$")
delay_ms = tonumber(delay_ms) or 120
mode = (mode or "chunk49"):lower()

local data = read_all(inpath)
if not data then r.MB("Cannot read file.", "Bank Send Wizard", 0); return end
local msgs = split_sysex(data)
if #msgs ~= 1 then
  r.MB("Expected single-message bank dump. Found "..#msgs, "Bank Send Wizard", 0)
  return
end
local m = msgs[1]
if m:byte(1)~=0xF0 or m:byte(2)~=0x43 then
  r.MB("Not a Yamaha SysEx file.", "Bank Send Wizard", 0); return
end

if mode == "single" then
  r.SNM_SendSysEx(m)
  r.MB("Sent as single SysEx message ("..#m.." bytes).", "Bank Send Wizard", 0)
  return
end

-- chunk49 mode
-- prefix: keep F0 + next 9 bytes if present (common header region)
local prefix_len = math.min(#m, 10)
local prefix = m:sub(1, prefix_len)
-- payload excludes initial prefix and trailing F7
local payload = m:sub(prefix_len+1, #m-1)

local packets = 49
local chunk_size = math.ceil(#payload / packets)
if chunk_size < 32 then chunk_size = 32 end

local sent = 0
r.ShowConsoleMsg("=== FB-01 Bank Send Wizard ===\n")
r.ShowConsoleMsg("File: "..inpath.."\n")
r.ShowConsoleMsg("Bytes: "..#m.." prefix="..prefix_len.." payload="..#payload.."\n")
r.ShowConsoleMsg("Mode: chunk49 chunk_size="..chunk_size.." delay_ms="..delay_ms.."\n\n")

for i=1, packets do
  local a = (i-1)*chunk_size + 1
  local b = math.min(i*chunk_size, #payload)
  local chunk = ""
  if a <= #payload then chunk = payload:sub(a,b) end
  local pkt = prefix .. chunk .. string.char(0xF7)
  r.SNM_SendSysEx(pkt)
  sent = sent + 1
  local pct = math.floor((sent/packets)*100)
  r.ShowConsoleMsg(string.format("Sent packet %02d/%02d (%d bytes) [%d%%] head=%s\n", i, packets, #pkt, pct, bytes_to_hex(pkt, 10)))
  r.Sleep(delay_ms)
end

r.MB("Done. Sent "..sent.." packets.\nIf FB-01 rejected chunks, use mode=single.", "Bank Send Wizard", 0)
