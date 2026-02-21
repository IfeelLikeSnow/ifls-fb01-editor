-- @description IFLS FB-01 - Safe Audition (backup current voice -> audition -> revert)
-- @version 1.00.0
-- @author IFLS
-- @about
--   Tries to back up current voice via SysEx request (recording) into a temporary .syx,
--   then sends selected audition voice, and offers revert by re-sending the backup.
--
-- Requirements:
--   - SWS (SNM_SendSysEx)
--   - Track input configured to FB-01 MIDI IN for SysEx capture

local r=reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found.", "Safe Audition", 0); return
end

local root = r.GetResourcePath().."/Scripts/IFLS FB-01 Editor"
local Syx = dofile(root.."/Core/ifls_fb01_sysex.lua")

local function ensure_track()
  local tr = r.GetSelectedTrack(0,0)
  if tr then return tr end
  r.InsertTrackAtIndex(r.CountTracks(0), true)
  tr = r.GetTrack(0, r.CountTracks(0)-1)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", "FB-01 SysEx Capture", true)
  r.SetOnlyTrackSelected(tr)
  return tr
end

local function last_item_on_track(tr)
  local item=nil
  local cnt=r.CountTrackMediaItems(tr)
  if cnt>0 then item=r.GetTrackMediaItem(tr, cnt-1) end
  return item
end

local function export_selected_item_to_syx(path)
  r.SetExtState("IFLS_FB01","EXPORT_SYX_PATH", path, false)
  local exporter = root.."/Pack_v8/Scripts/IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua"
  local f=io.open(exporter,"rb"); if not f then r.MB("Exporter missing.", "Safe Audition", 0); return end
  f:close()
  dofile(exporter)
end

local function send_file(path)
  r.SetExtState("IFLS_FB01","SYX_PATH", path, false)
  dofile(root.."/Pack_v8/Scripts/IFLS_FB01_Replay_SYX_File_FromPath.lua")
end

local ok, csv = r.GetUserInputs("Safe Audition", 3, "SysEx Channel (0-15),Instrument (0-7),Capture seconds", "0,0,3")
if not ok then return end
local sysch_s, inst_s, sec_s = csv:match("^([^,]+),([^,]+),([^,]+)$")
local sysch = tonumber(sysch_s) or 0
local inst = tonumber(inst_s) or 0
local secs = tonumber(sec_s) or 3

local ok2, audition_path = r.GetUserFileNameForRead("", "Select audition voice .syx", ".syx")
if not ok2 or audition_path=="" then return end

-- Create temp backup path
local ts = os.date("!%Y%m%d_%H%M%S")
local backup_path = r.GetResourcePath().."/Scripts/IFLS FB-01 Editor/Docs/Reports/FB01_AuditionBackup_"..ts..".syx"

local tr = ensure_track()
r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)

-- record
r.Main_OnCommand(1013, 0) -- record
r.Sleep(200)

-- request current voice dump
local req = Syx.request_voice(sysch, inst)
r.SNM_SendSysEx(req)

r.Sleep(secs*1000)
r.Main_OnCommand(1016, 0) -- stop
r.Sleep(250)

local item = last_item_on_track(tr)
if not item then
  r.MB("No recorded SysEx item. Ensure track input is set to FB-01 MIDI IN.", "Safe Audition", 0)
  return
end

r.SelectAllMediaItems(0, false)
r.SetMediaItemSelected(item, true)
r.UpdateArrange()
export_selected_item_to_syx(backup_path)

local ret = r.MB("Backup captured to:\n"..backup_path.."\n\nSend audition voice now?", "Safe Audition", 4)
if ret ~= 6 then return end

send_file(audition_path)

local ret2 = r.MB("Audition sent. Revert to backup now?", "Safe Audition", 4)
if ret2 == 6 then
  send_file(backup_path)
  r.MB("Reverted by re-sending backup:\n"..backup_path, "Safe Audition", 0)
end
