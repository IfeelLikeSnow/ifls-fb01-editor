-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_ReplayDump_From_ExtState.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_ReplayDump_From_ExtState.lua
-- Replays a stored dump from ExtState (created by StoreDump script) back to FB-01 via SWS.
--
-- Requires: SWS

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
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "FB-01 Replay Dump", 0)
  return
end

local section="IFLS_FB01_DUMP_V8"

local function hex_to_bin(hex)
  local bytes={}
  for b in hex:gmatch("%x%x") do bytes[#bytes+1]=string.char(tonumber(b,16)) end
  return table.concat(bytes)
end

local ok, vals = r.GetUserInputs("Replay Dump", 2, "Slot (1-8),Inter-message delay ms", "1,10")
if not ok then return end
local slot_s, delay_s = vals:match("([^,]+),([^,]+)")
local slot = tonumber(slot_s) or 1
if slot<1 then slot=1 elseif slot>8 then slot=8 end
local delay_ms = tonumber(delay_s) or 10
if delay_ms < 0 then delay_ms = 0 elseif delay_ms > 200 then delay_ms = 200 end

local key=string.format("slot_%02d", slot)
local payload = r.GetExtState(section, key)
if not payload or payload=="" then
  r.MB("Slot is empty: "..key, "FB-01 Replay Dump", 0)
  return
end

local label, rest = payload:match("^(.-)|(.+)$")
rest = rest or ""
local lines={}
for line in rest:gmatch("[^\n]+") do lines[#lines+1]=line end
if #lines==0 then
  r.MB("No messages in slot.", "FB-01 Replay Dump", 0)
  return
end

local i=1
local function step()
  if i > #lines then
    r.MB("Replay complete.\nLabel: "..tostring(label).."\nMessages sent: "..#lines, "FB-01 Replay Dump", 0)
    return
  end
  local bin = hex_to_bin(lines[i])
  r.SNM_SendSysEx(bin)
  i = i + 1
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
