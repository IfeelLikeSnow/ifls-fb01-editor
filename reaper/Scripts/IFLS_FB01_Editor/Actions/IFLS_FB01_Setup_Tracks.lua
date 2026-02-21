-- @description IFLS FB-01: Setup Tracks (Workbench)
-- @version 0.1.2
-- @author IFLS
-- @about
--   Minimal project scaffolding for FB-01 workbench.
local r = reaper

local function ensure_track_named(name)
  local n = r.CountTracks(0)
  for i=0,n-1 do
    local tr = r.GetTrack(0,i)
    local _, tn = r.GetTrackName(tr, "")
    if tn == name then return tr end
  end
  r.InsertTrackAtIndex(n, true)
  local tr = r.GetTrack(0,n)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

r.Undo_BeginBlock()
ensure_track_named("FB-01 MIDI OUT")
ensure_track_named("FB-01 AUDIO IN")
ensure_track_named("FB-01 CAPTURE")
r.TrackList_AdjustWindows(false)
r.Undo_EndBlock("IFLS FB-01: Setup tracks", -1)

r.ShowMessageBox(
  "Tracks created/ensured:\n\n- FB-01 MIDI OUT\n- FB-01 AUDIO IN\n- FB-01 CAPTURE\n\nNext: set MIDI hardware output on 'FB-01 MIDI OUT' and audio input on 'FB-01 AUDIO IN'.",
  "IFLS FB-01 Setup Tracks",
  0
)
