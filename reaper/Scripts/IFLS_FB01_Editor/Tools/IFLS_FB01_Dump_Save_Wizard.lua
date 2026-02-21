-- @description IFLS FB-01 - Dump Save Wizard (Voice/Set/Bank → .syx)
-- @version 0.93.0
-- @author IFLS
-- @about
--   One-button workflow to request a dump from FB-01, record incoming SysEx into a MIDI item,
--   then export the recorded item to a .syx file.
--
-- Requirements:
--   - SWS (SNM_SendSysEx for request; recording uses REAPER)
--   - REAPER: must have at least one track; uses selected track (creates one if none)
--
-- Notes:
--   Bank dumps are large; increase record time if needed.

local r = reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "FB-01 Dump Save Wizard", 0)
  return
end

local wb_root = r.GetResourcePath().."/Scripts/IFLS FB-01 Editor"
local Syx = dofile(wb_root.."/Core/ifls_fb01_sysex.lua")

local function ensure_track()
  local tr = r.GetSelectedTrack(0,0)
  if tr then return tr end
  r.InsertTrackAtIndex(r.CountTracks(0), true)
  tr = r.GetTrack(0, r.CountTracks(0)-1)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", "FB-01 Dump Record", true)
  r.SetOnlyTrackSelected(tr)
  return tr
end

local function arm_and_set_input(tr)
  r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  -- Set input to MIDI: all channels. value is 4096 + 0 (midi) typically; leave as-is if user already configured.
  -- We won't force input device; user should set track input to the correct MIDI in port in REAPER.
end

local function last_item_on_track(tr)
  local item = nil
  local cnt = r.CountTrackMediaItems(tr)
  if cnt>0 then item = r.GetTrackMediaItem(tr, cnt-1) end
  return item
end

local function export_selected_item_to_syx(path)
  -- reuse existing exporter if present
  r.SetExtState("IFLS_FB01","EXPORT_SYX_PATH", path, false)
  local exporter = wb_root.."/Pack_v8/Scripts/IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua"
  local f=io.open(exporter,"rb")
  if f then f:close(); dofile(exporter)
  else
    r.MB("Exporter not found:\n"..exporter, "FB-01 Dump Save Wizard", 0)
  end
end

local ok, csv = r.GetUserInputs("FB-01 Dump Save Wizard", 4,
  "Type (voice/set/bank),SysEx Channel (0-15),Instrument (0-7 for voice),BankId (0-7 for bank)", "voice,0,0,0")
if not ok then return end
local t, sysch_s, inst_s, bank_s = csv:match("^([^,]+),([^,]+),([^,]+),([^,]+)$")
if not t then r.MB("Invalid input.", "FB-01 Dump Save Wizard", 0); return end
t = (t or "voice"):lower()
local sysch = tonumber(sysch_s) or 0
local inst = tonumber(inst_s) or 0
local bankId = tonumber(bank_s) or 0


local ok_rt, rt = r.GetUserInputs("Record Duration", 1, "Override record seconds (blank=default)", "")
if ok_rt and rt ~= "" then
  local v = tonumber(rt)
  if v and v > 0 then record_secs = v end
end

-- (legacy defaults removed below)
-- local record_secs = 3
if t=="set" then record_secs = 4 end
if t=="bank" then record_secs = 12 end

local ok2, outpath = r.GetUserFileNameForWrite("", "Save dump as .syx", ".syx")
if not ok2 or not outpath or outpath=="" then return end

local tr = ensure_track()
arm_and_set_input(tr)

-- Start recording
r.Main_OnCommand(1013, 0) -- Transport: Record
r.Sleep(250)

-- Send request
local msg
if t=="voice" then msg = Syx.request_voice(sysch, inst)
elseif t=="set" then msg = Syx.request_set(sysch)
elseif t=="bank" then msg = Syx.request_bank(sysch, bankId)
else
  r.MB("Unknown type: "..t, "FB-01 Dump Save Wizard", 0)
  return
end
r.SNM_SendSysEx(msg)

-- wait and stop
r.Sleep(record_secs*1000)
r.Main_OnCommand(1016, 0) -- Stop

r.Sleep(250)
local item = last_item_on_track(tr)
if not item then
  r.MB("No recorded item found. Ensure track input is set to your FB-01 MIDI IN.", "FB-01 Dump Save Wizard", 0)
  return
end

-- select item and export
r.SelectAllMediaItems(0, false)
r.SetMediaItemSelected(item, true)
r.UpdateArrange()

export_selected_item_to_syx(outpath)
r.MB("Done. Export attempted to:\n"..outpath, "FB-01 Dump Save Wizard", 0)
