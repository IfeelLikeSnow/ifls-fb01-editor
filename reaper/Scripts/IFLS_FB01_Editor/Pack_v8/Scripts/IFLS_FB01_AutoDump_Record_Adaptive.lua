-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_AutoDump_Record_Adaptive.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_AutoDump_Record_Adaptive.lua
-- V51: Request FB-01 dump, record, and AUTO-STOP when SysEx stream goes quiet.
--
-- How it works:
-- 1) Start transport record
-- 2) Send dump request (requires SWS)
-- 3) Find the newest recording item on the armed/selected track and watch its SysEx event count
-- 4) When SysEx count hasn't changed for QUIET_MS after at least MIN_SEC, stop recording.
--
-- Notes:
-- - Requires: SWS to send request (SNM_SendSysEx).
-- - For best results: Select the MIDI track that is receiving FB-01 MIDI IN and arm it.
-- - REAPER records SysEx as type=-1 events in the MIDI take; payload may be unframed (no F0/F7).

local r = reaper
local DevPorts=nil
pcall(function() DevPorts=dofile(r.GetResourcePath().."/Scripts/IFLS FB-01 Editor/Workbench/MIDINetwork/Lib/IFLS_DevicePortDefaults.lua") end)


local function has_sws()
  return r.SNM_SendSysEx ~= nil
end

local function hex_to_bytes(hex)
  local bytes = {}
  for b in hex:gmatch("%x%x") do
    bytes[#bytes+1] = string.char(tonumber(b,16))
  end
  return table.concat(bytes)
end

local function send_sysex_hex(hex)
  if not has_sws() then return false end
  r.SNM_SendSysEx(hex_to_bytes(hex))
  return true
end

local function get_target_track()
  local tr = r.GetSelectedTrack(0,0)
  if tr then return tr end
  -- fallback: first armed track
  local track_count = r.CountTracks(0)
  for i=0,track_count-1 do
    local t = r.GetTrack(0,i)
    if r.GetMediaTrackInfo_Value(t, "I_RECARM") == 1 then
      return t
    end
  end
  return nil
end

local function get_latest_item_take(track)
  local n = r.CountTrackMediaItems(track)
  if n == 0 then return nil end
  local item = r.GetTrackMediaItem(track, n-1)
  if not item then return nil end
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then return nil end
  return take
end


local function get_latest_item(track)
  local n = r.CountTrackMediaItems(track)
  if n == 0 then return nil end
  return r.GetTrackMediaItem(track, n-1)
end

local function select_item(item)
  if not item then return end
  r.Main_OnCommand(40289,0) -- Unselect all items
  r.SetMediaItemSelected(item, true)
  r.UpdateArrange()
end

local function export_item_sysex_to_syx(item, out_path)
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then return false, "Latest item is not a MIDI take." end
  local _, _, _, textsz = r.MIDI_CountEvts(take)
  local msgs = {}
  for i=0,textsz-1 do
    local ok, sel, mut, ppq, typ, msgbin = r.MIDI_GetTextSysexEvt(take, i)
    if ok and typ==-1 and msgbin and #msgbin>0 then
      if msgbin:byte(1) ~= 0xF0 then
        msgbin = string.char(0xF0) .. msgbin .. string.char(0xF7)
      end
      msgs[#msgs+1] = msgbin
    end
  end
  if #msgs == 0 then return false, "No SysEx events found." end
  local f = io.open(out_path, "wb")
  if not f then return false, "Failed to write file." end
  for _,m in ipairs(msgs) do f:write(m) end
  f:close()
  return true, "Exported "..#msgs.." messages."
end

local function count_sysex_events(take)
  local _, _, _, textsz = r.MIDI_CountEvts(take)
  local count = 0
  for i=0,textsz-1 do
    local ok, sel, mut, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
    if ok and typ == -1 and msg and #msg > 0 then count = count + 1 end
  end
  return count
end

if not has_sws() then
  r.MB("SWS not found (SNM_SendSysEx missing).\nInstall SWS to send dump requests.", "FB-01 AutoDump Adaptive", 0)
  return
end

local ok, vals = r.GetUserInputs("FB-01 AutoDump Adaptive (V52)", 6,
  "Dump:1=VB00 2=VB01 3=Config,Min seconds,Quiet ms,Send delay ms,Auto-export .syx (0/1),Export base name",
  "1,4,900,200,1,fb01_dump")
if not ok then return end
local d_s, min_s, quiet_ms, send_delay_ms, autoexp_s, basename = vals:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),(.+)")
local dump_type = tonumber(d_s) or 1
min_s = tonumber(min_s) or 4
quiet_ms = tonumber(quiet_ms) or 900
send_delay_ms = tonumber(send_delay_ms) or 200
local auto_export = (tonumber(autoexp_s) or 1) ~= 0
basename = (basename and basename:gsub('[^%w%-%_]+','_')) or 'fb01_dump'
if min_s < 1 then min_s = 1 elseif min_s > 120 then min_s = 120 end
if quiet_ms < 200 then quiet_ms = 200 elseif quiet_ms > 5000 then quiet_ms = 5000 end
if send_delay_ms < 0 then send_delay_ms = 0 elseif send_delay_ms > 2000 then send_delay_ms = 2000 end

local req
if dump_type == 1 then
  req = "F0 43 75 00 20 00 00 F7" -- voice bank 00
elseif dump_type == 2 then
  req = "F0 43 75 00 20 00 01 F7" -- voice bank 01
else
  req = "F0 43 75 00 20 03 00 F7" -- all configs
end

local tr = get_target_track()
if not tr then
  r.MB("No selected or armed track found.\nSelect/arm the MIDI track receiving FB-01 MIDI IN, then rerun.", "FB-01 AutoDump Adaptive", 0)
  return
end

-- Start record
r.Main_OnCommand(1013, 0) -- Transport: Record

local start_time = r.time_precise()
local sent = false
local last_count = 0
local last_change_t = start_time

local function loop()
  local now = r.time_precise()

  if not sent and (now - start_time) * 1000 >= send_delay_ms then
    send_sysex_hex(req)
    sent = true
  end

  local take = get_latest_item_take(tr)
  if take then
    local c = count_sysex_events(take)
    if c ~= last_count then
      last_count = c
      last_change_t = now
    end
  end

  local elapsed = now - start_time
  local quiet_elapsed_ms = (now - last_change_t) * 1000

  if elapsed >= min_s and sent and quiet_elapsed_ms >= quiet_ms then
    r.Main_OnCommand(1016, 0) -- Transport: Stop

local item = get_latest_item(tr)
if item then
  select_item(item)
  if auto_export then
    local _, projfn = r.EnumProjects(-1, "")
    local dir = projfn:match("^(.*)[/\\].-$") or r.GetResourcePath()
    local ts = os.date("!%Y%m%d_%H%M%S")
    local out_path = dir .. "/" .. basename .. "_" .. ts .. ".syx"
    local okx, msgx = export_item_sysex_to_syx(item, out_path)
    if okx then
      r.MB("AutoDump finished.\n\nRecorded SysEx events: "..tostring(last_count).."\n\n"..msgx.."\nSaved:\n"..out_path, "FB-01 AutoDump Adaptive", 0)
      return
    else
      r.MB("AutoDump finished.\n\nRecorded SysEx events: "..tostring(last_count).."\n\nExport failed: "..tostring(msgx), "FB-01 AutoDump Adaptive", 0)
      return
    end
  end
end

    r.MB("AutoDump finished.\n\nRecorded SysEx events: "..tostring(last_count).."\n\nSelect the recorded MIDI item and run:\n- IFLS_FB01_SysEx_Analyzer_SelectedItem.lua\n- IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua\n", "FB-01 AutoDump Adaptive", 0)
    return
  end

  r.defer(loop)
end

r.defer(loop)
