-- @description IFLS Workbench - Workbench/FB01/PatchLibrary/Scripts/IFLS_FB01_Send_SYX_File.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Send_SYX_File.lua
-- Sends a .syx (raw SysEx) file to your MIDI outputs via SWS SNM_SendSysEx.
-- Use this to load Internet patch banks into the Yamaha FB-01.
--
-- Requirements: SWS installed.

local r = reaper
local DevPorts=nil
pcall(function() DevPorts=dofile(r.GetResourcePath().."/Scripts/IFLS FB-01 Editor/Workbench/MIDINetwork/Lib/IFLS_DevicePortDefaults.lua") end)

if DevPorts and DevPorts.get_out_idx then
  if (out_dev == nil) and (device_out == nil) then
    local d = DevPorts.get_out_idx("fb01")
    if d then out_dev = d; device_out = d end
  end
end

if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "Send .SYX", 0)
  return
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*all")
  f:close()
  return data
end

-- File picker (JS_ReaScriptAPI if present)
local path
if r.JS_Dialog_BrowseForOpenFiles then
  local retval, file = r.JS_Dialog_BrowseForOpenFiles("Select .syx to send", "", "", "SysEx (*.syx)\0*.syx\0", false)
  if not retval then return end
  path = file
else
  local ok, name = r.GetUserInputs("Send .syx (JS_ReaScriptAPI not installed)", 1, "Full path to .syx", "")
  if not ok or name=="" then return end
  path = name
end

local data = read_file(path)
if not data then
  r.MB("Failed to read:\n"..tostring(path), "Send .SYX", 0)
  return
end

-- Some files contain multiple SysEx messages concatenated; SNM_SendSysEx can handle sending
-- one message at a time. We'll split by F0..F7 and send sequentially with a small delay.
local function split_msgs(bin)
  local msgs = {}
  local i = 1
  while true do
    local s = bin:find(string.char(0xF0), i, true)
    if not s then break end
    local e = bin:find(string.char(0xF7), s, true)
    if not e then break end
    msgs[#msgs+1] = bin:sub(s, e)
    i = e + 1
  end
  return msgs
end

local msgs = split_msgs(data)
if #msgs == 0 then
  -- try sending whole blob
  if data:byte(1) ~= 0xF0 then data = string.char(0xF0)..data..string.char(0xF7) end
  r.SNM_SendSysEx(data)
  r.MB("Sent raw data (no F0/F7 framing detected).", "Send .SYX", 0)
  return
end

local ok, d = r.GetUserInputs("Inter-message delay (ms)", 1, "Delay ms (0..200)", "10")
if not ok then return end
local delay_ms = tonumber(d) or 10
if delay_ms < 0 then delay_ms = 0 elseif delay_ms > 200 then delay_ms = 200 end

local idx = 1
local function step()
  if idx > #msgs then
    r.MB("Done.\nSent "..#msgs.." SysEx messages.\n\nIf the FB-01 didn't load them, check:\n- MIDI cabling\n- Memory Protect OFF for writes\n- correct device/system settings", "Send .SYX", 0)
    return
  end
  local m = msgs[idx]
  if m:byte(1) ~= 0xF0 then m = string.char(0xF0)..m..string.char(0xF7) end
  r.SNM_SendSysEx(m)
  idx = idx + 1
  if delay_ms == 0 then
    r.defer(step)
  else
    local t0 = r.time_precise()
    local function wait()
      if (r.time_precise() - t0) * 1000 >= delay_ms then
        r.defer(step)
      else
        r.defer(wait)
      end
    end
    r.defer(wait)
  end
end

r.defer(step)
