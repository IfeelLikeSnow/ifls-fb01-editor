-- @description IFLS Workbench - Workbench/FB01/Pack_v2/Scripts/IFLS_FB01_CC_MixPanel.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_CC_MixPanel.lua
-- Sends standard MIDI controls to Yamaha FB-01.
-- - Volume CC7
-- - Pan CC10
-- - Expression CC11
-- - Program Change
-- Uses ReaImGui if available; otherwise prompts via GetUserInputs.
--
-- Requires: none (ReaImGui recommended for UI).

local r = reaper

if not r.ImGui_CreateContext then
  r.MB("ReaImGui not found. Install ReaImGui, then rerun.", "IFLS", 0)
  return
end

local function send_cc(hwout, ch, cc, val)
  -- send to selected HW out using StuffMIDIMessage? That sends to "virtual keyboard" output.
  -- Better: insert into track MIDI hardware out by sending to track with I_MIDIHWOUT configured.
  -- We'll send to the first selected track, assuming it already routes to the correct HW out/channel.
  local tr = r.GetSelectedTrack(0,0)
  if not tr then return end
  local msg1 = 0xB0 + (ch-1)
  r.StuffMIDIMessage(0, msg1, cc, val)
end

local function send_pc(ch, prog)
  local msg1 = 0xC0 + (ch-1)
  r.StuffMIDIMessage(0, msg1, prog, 0)
end

local function ui_prompt()
  local ok, vals = r.GetUserInputs("FB-01 CC MixPanel (select a Part track first)", 4,
    "MIDI Channel(1-16),Volume(0-127),Pan(0-127),Prog(0-127)", "1,100,64,0")
  if not ok then return end
  local ch, vol, pan, prog = vals:match("([^,]+),([^,]+),([^,]+),([^,]+)")
  ch = tonumber(ch) or 1
  vol = tonumber(vol) or 100
  pan = tonumber(pan) or 64
  prog = tonumber(prog) or 0

  -- Send (requires track routing; user should select the correct Part track)
  r.StuffMIDIMessage(0, 0xB0+(ch-1), 7, math.max(0, math.min(127, vol)))
  r.StuffMIDIMessage(0, 0xB0+(ch-1), 10, math.max(0, math.min(127, pan)))
  r.StuffMIDIMessage(0, 0xC0+(ch-1), math.max(0, math.min(127, prog)), 0)
end

-- Try ReaImGui
local has_imgui = r.ImGui_CreateContext ~= nil
if not has_imgui then
  ui_prompt()
  return
end

local ctx = r.ImGui_CreateContext('FB-01 Mix/Assign CC Panel')
local ch, vol, pan, expr, prog = 1, 100, 64, 127, 0

local function clamp(v) v=math.floor(v+0.5); if v<0 then v=0 elseif v>127 then v=127 end; return v end

local function loop()
  local visible, open = r.ImGui_Begin(ctx, 'FB-01 Mix/Assign (select a Part track)', true)
  if visible then
    local tr = r.GetSelectedTrack(0,0)
    if tr then
      local _, name = r.GetTrackName(tr)
      r.ImGui_Text(ctx, "Selected: "..name)
    else
      r.ImGui_Text(ctx, "No track selected. Select an FB-01 Part track.")
    end

    local changed
    changed, ch = r.ImGui_SliderInt(ctx, "MIDI Channel", ch, 1, 16)
    changed, vol = r.ImGui_SliderInt(ctx, "Volume (CC7)", vol, 0, 127)
    if changed then r.StuffMIDIMessage(0, 0xB0+(ch-1), 7, clamp(vol)) end
    changed, pan = r.ImGui_SliderInt(ctx, "Pan (CC10)", pan, 0, 127)
    if changed then r.StuffMIDIMessage(0, 0xB0+(ch-1), 10, clamp(pan)) end
    changed, expr = r.ImGui_SliderInt(ctx, "Expression (CC11)", expr, 0, 127)
    if changed then r.StuffMIDIMessage(0, 0xB0+(ch-1), 11, clamp(expr)) end

    changed, prog = r.ImGui_SliderInt(ctx, "Program (PC)", prog, 0, 127)
    if r.ImGui_Button(ctx, "Send Program Change") then
      r.StuffMIDIMessage(0, 0xC0+(ch-1), clamp(prog), 0)
    end

    r.ImGui_Separator(ctx)
    r.ImGui_TextWrapped(ctx, "Tip: For best results, select the Part track that already routes to your 1824c MIDI OUT on that channel.")
    r.ImGui_End(ctx)
  end

  if open then
    r.defer(loop)
  else
    r.ImGui_DestroyContext(ctx)
  end
end

r.defer(loop)
