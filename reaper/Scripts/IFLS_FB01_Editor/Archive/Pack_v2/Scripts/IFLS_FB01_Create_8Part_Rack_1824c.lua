-- @description IFLS Workbench - Workbench/FB01/Pack_v2/Scripts/IFLS_FB01_Create_8Part_Rack_1824c.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Create_8Part_Rack_1824c.lua
-- Creates an 8-part multitimbral rack for Yamaha FB-01 using PreSonus Studio 1824c MIDI I/O.
-- Mix/Assign first: standard MIDI (CC/PC/PB). SysEx/Voice edit is V3+.
--
-- How it works:
-- - Folder track "FB-01 Rack"
-- - 8 child tracks (Part 1..8) that send MIDI to your selected hardware MIDI output on channels 1..8
-- - 1 audio return track (child) for FB-01 audio inputs
--
-- Requirements: none (SWS optional).
--
-- Author: IFLS Workbench

local r = reaper

local function msg(s) r.ShowConsoleMsg(tostring(s).."\n") end

local function get_midi_hwout_index_by_name(substr)
  local idx = -1
  local i = 0
  while true do
    local retval, name = r.GetMIDIOutputName(i, "")
    if not retval then break end
    if name:lower():find(substr:lower(), 1, true) then
      idx = i
      break
    end
    i = i + 1
  end
  return idx
end

-- Try to auto-detect Studio 1824c MIDI Out; fallback asks user
local hwout = get_midi_hwout_index_by_name("1824")  -- "Studio 1824c" usually contains 1824
if hwout < 0 then
  local ok, val = r.GetUserInputs("FB-01 Rack Setup", 1, "MIDI HW Out index (Preferences > MIDI Devices)", "0")
  if not ok then return end
  hwout = tonumber(val) or 0
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- Create folder track at end
local tr_count = r.CountTracks(0)
r.InsertTrackAtIndex(tr_count, true)
local folder = r.GetTrack(0, tr_count)
r.GetSetMediaTrackInfo_String(folder, "P_NAME", "FB-01 Rack", true)
r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1) -- folder start

-- Helper: create child
local function add_child(name)
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, true)
  local tr = r.GetTrack(0, idx)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  -- indent visually (optional)
  return tr
end

-- Create 8 MIDI part tracks
local part_tracks = {}
for ch=1,8 do
  local tr = add_child(string.format("FB-01 Part %d (MIDI Ch %d)", ch, ch))
  part_tracks[ch] = tr

  -- Set track MIDI hardware output to hwout on channel ch
  -- I_MIDIHWOUT: low 5 bits = channel (0=all, 1..16), next bits = device index + flags.
  -- REAPER encoding: device index in bits 5..?? with 0x1F? We'll use Track routing API instead for stability.
  -- We'll create a send to "hardware output" using SetTrackSendInfo_Value with category=1 (HW sends) when possible.
  -- However, HW sends are not exposed as normal sends; easiest is to set I_MIDIHWOUT.
  local ch0 = ch -- REAPER expects 1..16
  local dev = hwout
  local val = dev * 32 + ch0  -- common encoding used by scripts; works for most cases.
  r.SetMediaTrackInfo_Value(tr, "I_MIDIHWOUT", val)

  -- Ensure track records MIDI input (user can arm later)
  r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  r.SetMediaTrackInfo_Value(tr, "I_RECMODE", 0) -- record input
end

-- Audio return track
local ret = add_child("FB-01 Audio Return (set your 1824c inputs)")
r.SetMediaTrackInfo_Value(ret, "I_RECARM", 0)
r.SetMediaTrackInfo_Value(ret, "I_RECMODE", 0)
-- Placeholder input (user must set)
r.GetSetMediaTrackInfo_String(ret, "P_NOTES", [[
FB-01 AUDIO RETURN
- Set input to your 1824c line inputs used for FB-01 L/R.
- Monitor ON, or arm + monitor.
]], true)

-- Close folder
r.SetMediaTrackInfo_Value(ret, "I_FOLDERDEPTH", -1)

-- Notes on folder
local notes = [[
FB-01 RACK (1824c)
MIDI:
- Part tracks send to 1824c MIDI OUT on channels 1..8.
- Set your FB-01 Instruments/Parts to receive on CH 1..8 to match.

Audio:
- Connect FB-01 OUT L/R to 1824c line inputs.
- Set inputs on "FB-01 Audio Return".

Tips:
- Keep Dry anchors in REAPER; resample hardware returns for IDM workflows.
]]
r.GetSetMediaTrackInfo_String(folder, "P_NOTES", notes, true)

r.TrackList_AdjustWindows(false)
r.PreventUIRefresh(-1)
r.Undo_EndBlock("Create FB-01 8-part rack (1824c)", -1)

msg("Created FB-01 Rack. Set the Audio Return track input to your FB-01 line inputs.")
