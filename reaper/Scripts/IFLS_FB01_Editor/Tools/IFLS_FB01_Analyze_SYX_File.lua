-- @description IFLS FB-01 - Analyze .SYX file (types, message count, lengths)
-- @version 0.97.0
-- @author IFLS
-- @about
--   Opens a .syx file, splits into SysEx messages, classifies common FB-01 types,
--   prints summary to REAPER console.

local r = reaper

local function split_sysex(data)
  local msgs = {}
  local i=1
  while true do
    local s = data:find(string.char(0xF0), i, true)
    if not s then break end
    local e = data:find(string.char(0xF7), s+1, true)
    if not e then break end
    msgs[#msgs+1] = data:sub(s, e)
    i = e + 1
  end
  return msgs
end

local function hex_prefix(msg, n)
  n = n or 16
  local out={}
  for i=1, math.min(#msg, n) do out[#out+1]=string.format("%02X", msg:byte(i)) end
  return table.concat(out, " ")
end

local function classify(msg)
  if #msg < 6 then return "unknown", nil end
  local b1,b2,b3,b4,b5 = msg:byte(1,5)
  if b1 ~= 0xF0 then return "unknown", nil end
  if b2==0x43 and b3==0x75 then
    local cmd = b5
    if #msg >= 6300 then
      local bankId = msg:byte(7)
      return "bank_dump", bankId
    end
    if cmd >= 0x18 and cmd <= 0x1F then return "param_change", nil end
    if cmd == 0x20 then return "dump_request", nil end
    return "fb01_sysex", nil
  end
  return "other_sysex", nil
end

local ok, path = r.GetUserFileNameForRead("", "Analyze SYX file", ".syx")
if not ok or not path or path=="" then return end

local f=io.open(path,"rb")
if not f then r.MB("Cannot open:\n"..path, "SYX Analyze", 0); return end
local data=f:read("*all"); f:close()

local msgs = split_sysex(data)

r.ShowConsoleMsg("=== IFLS FB-01 SYX Analyze ===\n")
r.ShowConsoleMsg("File: "..path.."\n")
r.ShowConsoleMsg("Bytes: "..tostring(#data).."\n")
r.ShowConsoleMsg("SysEx messages: "..tostring(#msgs).."\n\n")

local counts={}
for i,m in ipairs(msgs) do
  local k,bid = classify(m)
  counts[k] = (counts[k] or 0) + 1
  if i<=5 then
    r.ShowConsoleMsg(string.format("#%d len=%d type=%s bankId=%s head=%s\n", i, #m, k, tostring(bid), hex_prefix(m, 14)))
  end
end

r.ShowConsoleMsg("\nType counts:\n")
for k,v in pairs(counts) do
  r.ShowConsoleMsg(string.format("  %s: %d\n", k, v))
end
r.ShowConsoleMsg("\nNotes:\n")
r.ShowConsoleMsg(" - param_stream typically shows as many short messages (param_change).\n")
r.ShowConsoleMsg(" - bank_dump usually shows a single long message (~6363 bytes).\n")
