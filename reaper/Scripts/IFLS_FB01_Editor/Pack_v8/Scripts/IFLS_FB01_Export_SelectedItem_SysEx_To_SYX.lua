-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua
-- Exports all SysEx events from selected MIDI item into a single .syx file (binary).
-- This makes dumps portable (for librarians, archiving, etc.)

local r = reaper

local function get_take()
  local item = r.GetSelectedMediaItem(0,0)
  if not item then return nil, "No item selected." end
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then return nil, "Selected item is not MIDI." end
  return take
end

local take, err = get_take()
if not take then
  r.MB(err, "FB-01 Export .SYX", 0)
  return
end

local path
if r.JS_Dialog_BrowseForSaveFile then
  local retval
  retval, path = r.JS_Dialog_BrowseForSaveFile("Save SysEx dump as .syx", "", "fb01_dump.syx", "SysEx (*.syx)\0*.syx\0")
  if not retval then return end
else
  local ok, name = r.GetUserInputs("Save .syx (JS_ReaScriptAPI not installed)", 1, "Filename (saved in project dir)", "fb01_dump.syx")
  if not ok then return end
  local _, projfn = r.EnumProjects(-1, "")
  local dir = projfn:match("^(.*)[/\\].-$") or r.GetResourcePath()
  path = dir .. "/" .. name
end

local _, _, _, textsz = r.MIDI_CountEvts(take)
local blobs = {}
local count = 0
for i=0,textsz-1 do
  local ok, sel, mut, ppq, typ, msgbin = r.MIDI_GetTextSysexEvt(take, i)
  if ok and typ==-1 and msgbin and #msgbin>0 then
    local b1 = msgbin:byte(1)
    if b1 ~= 0xF0 then
      msgbin = string.char(0xF0) .. msgbin .. string.char(0xF7)
    end
    blobs[#blobs+1] = msgbin
    count = count + 1
  end
end

if count == 0 then
  r.MB("No SysEx events found in item.", "FB-01 Export .SYX", 0)
  return
end

local f = io.open(path, "wb")
if not f then
  r.MB("Failed to open file for writing:\n"..tostring(path), "FB-01 Export .SYX", 0)
  return
end
for _,b in ipairs(blobs) do f:write(b) end
f:close()

r.MB("Exported "..count.." SysEx messages to:\n"..path, "FB-01 Export .SYX", 0)
