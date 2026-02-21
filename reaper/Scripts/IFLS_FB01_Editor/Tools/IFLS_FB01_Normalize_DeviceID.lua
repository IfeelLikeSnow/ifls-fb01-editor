-- @description IFLS FB-01 - Normalize Device ID / SysEx Channel in .syx
-- @version 0.99.0
-- @author IFLS
local r=reaper

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

local ok, inpath = r.GetUserFileNameForRead("", "Select .syx file to normalize", ".syx")
if not ok or inpath=="" then return end
local data = read_all(inpath)
if not data then r.MB("Cannot read.", "Normalize", 0); return end

local ok2, csv = r.GetUserInputs("Normalize SysEx", 1, "SysEx Channel/DeviceID (0-15)", r.GetExtState("IFLS_FB01","SYSCH")~="" and r.GetExtState("IFLS_FB01","SYSCH") or "0")
if not ok2 then return end
local sysch = tonumber(csv) or 0
if sysch<0 then sysch=0 elseif sysch>15 then sysch=15 end
r.SetExtState("IFLS_FB01","SYSCH", tostring(sysch), true)

local msgs = split_sysex(data)
if #msgs==0 then r.MB("No SysEx found.", "Normalize", 0); return end

local out={}
local changed=0
for _,m in ipairs(msgs) do
  if #m>=5 and m:byte(1)==0xF0 and m:byte(2)==0x43 then
    -- Common Yamaha format uses byte 4 as device id (varies by model). FB-01 often: F0 43 75 <dev> ...
    -- In our observed dumps: F0 43 75 <dev> <cmd> ...
    if m:byte(3)==0x75 then
      local devpos=4
      local cur=m:byte(devpos)
      local nm = m:sub(1,devpos-1) .. string.char(sysch) .. m:sub(devpos+1)
      out[#out+1]=nm
      if cur~=sysch then changed=changed+1 end
    else
      out[#out+1]=m
    end
  else
    out[#out+1]=m
  end
end

local ok3, outpath = r.GetUserFileNameForWrite("", "Save normalized .syx", ".syx")
if not ok3 or outpath=="" then return end
local blob=table.concat(out,"")
if not write_all(outpath, blob) then r.MB("Cannot write.", "Normalize", 0); return end
r.MB("Normalized "<<changed.." messages (best-effort)\nSaved:\n"..outpath, "Normalize", 0)
