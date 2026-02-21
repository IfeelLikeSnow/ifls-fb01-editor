-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_Replay_SYX_File_Safe.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Replay_SYX_File_Safe.lua
-- V51: Replay a .syx file with safer pacing + progress.
-- - Splits concatenated SysEx messages (F0..F7) and sends sequentially.
-- - Optional adaptive delay: base delay + extra per message length.
--
-- Requires: SWS (SNM_SendSysEx)

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
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "FB-01 Safe Replay", 0)
  return
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*all")
  f:close()
  return data
end

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

local path
if r.JS_Dialog_BrowseForOpenFiles then
  local retval, file = r.JS_Dialog_BrowseForOpenFiles("Select .syx to replay (safe)", "", "", "SysEx (*.syx)\0*.syx\0", false)
  if not retval then return end
  path = file
else
  local ok, name = r.GetUserInputs("Replay .syx (JS_ReaScriptAPI missing)", 1, "Full path to .syx", "")
  if not ok or name=="" then return end
  path = name
end

local data = read_file(path)
if not data then
  r.MB("Failed to read:\n"..tostring(path), "FB-01 Safe Replay", 0)
  return
end

local msgs = split_msgs(data)
if #msgs == 0 then
  -- if unframed blob, frame it and send as single
  if data:byte(1) ~= 0xF0 then
    data = string.char(0xF0) .. data .. string.char(0xF7)
  end
  msgs = {data}
end

local ok, vals = r.GetUserInputs("Safe Replay Settings", 3,
  "Base delay ms (0..200),Extra ms per 100 bytes (0..50),Show console progress (0/1)",
  "10,2,1")
if not ok then return end
local base_s, extra_s, con_s = vals:match("([^,]+),([^,]+),([^,]+)")
local base = tonumber(base_s) or 10
local extra = tonumber(extra_s) or 2
local show = (tonumber(con_s) or 1) ~= 0
if base < 0 then base=0 elseif base>200 then base=200 end
if extra < 0 then extra=0 elseif extra>50 then extra=50 end

local function console(s)
  if show then r.ShowConsoleMsg(tostring(s).."\n") end
end

console("")
console("=== FB-01 Safe Replay ===")
console("Messages: "..#msgs)

local idx = 1
local function step()
  if idx > #msgs then
    r.MB("Replay complete.\nMessages sent: "..#msgs, "FB-01 Safe Replay", 0)
    return
  end

  local m = msgs[idx]
  r.SNM_SendSysEx(m)

  console(string.format("Sent %d/%d (len=%d)", idx, #msgs, #m))

  local delay_ms = base + math.floor((#m / 100) * extra)
  idx = idx + 1

  if delay_ms <= 0 then
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
