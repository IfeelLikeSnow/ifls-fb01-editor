-- @description IFLS FB-01 - Retarget Bank Dump (Bank1 <-> Bank2)
-- @version 0.99.0
-- @author IFLS
showmsg = reaper.MB
local r = reaper

local function read_all(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local d=f:read("*all"); f:close(); return d
end
local function write_all(path, data)
  local f=io.open(path,"wb"); if not f then return false end
  f:write(data); f:close(); return true
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

local ok, inpath = r.GetUserFileNameForRead("", "Select FB-01 Bank .syx", ".syx")
if not ok or inpath=="" then return end
local data = read_all(inpath)
if not data then r.MB("Cannot read file.", "Retarget", 0); return end
local msgs = split_sysex(data)
if #msgs ~= 1 then r.MB("Expected single-message bank dump. Found "..#msgs, "Retarget", 0); return end
local m = msgs[1]
if #m < 20 or m:byte(1)~=0xF0 or m:byte(2)~=0x43 then
  r.MB("Not Yamaha SysEx.", "Retarget", 0); return
end

-- Heuristic: many FB-01 bank dumps store bank id at byte 7 (1-indexed)
local b = m:byte(7) or 0
local cur = (b==0) and 1 or ((b==1) and 2 or nil)
if not cur then
  r.MB("Cannot determine BankId at byte 7. Value="..tostring(b).."\nThis tool currently supports common dumps where byte7 is 0/1.", "Retarget", 0)
  return
end
local target = (cur==1) and 2 or 1
local nb = (target==1) and 0 or 1

local outmsg = m:sub(1,6) .. string.char(nb) .. m:sub(8)
local outdata = outmsg -- single message
local ok2, outpath = r.GetUserFileNameForWrite("", "Save retargeted bank dump", ".syx")
if not ok2 or outpath=="" then return end
if not write_all(outpath, outdata) then r.MB("Cannot write output.", "Retarget", 0); return end
r.MB("Retargeted Bank "..cur.." -> "..target.."\nSaved:\n"..outpath, "Retarget", 0)
