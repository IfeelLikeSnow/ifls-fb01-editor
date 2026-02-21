-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_StoreDump_To_ExtState.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_StoreDump_To_ExtState.lua
-- Stores all SysEx messages from selected MIDI item into ExtState as hex (portable).
-- Later can replay via Replay script.
--
-- Note: ExtState size is limited; for large dumps prefer exporting to .syx.
-- Still useful for small config dumps.

local r = reaper

local function get_take()
  local item = r.GetSelectedMediaItem(0,0)
  if not item then return nil, "No item selected." end
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then return nil, "Selected item is not MIDI." end
  return take
end

local function bin_to_hex(bin)
  local t={}
  for i=1,#bin do t[#t+1]=string.format("%02X", bin:byte(i)) end
  return table.concat(t)
end

local take, err = get_take()
if not take then
  r.MB(err, "FB-01 Store Dump", 0)
  return
end

local ok, vals = r.GetUserInputs("Store Dump to ExtState", 2, "Slot (1-8),Label", "1,FB01 Dump")
if not ok then return end
local slot_s, label = vals:match("([^,]+),(.+)")
local slot = tonumber(slot_s) or 1
if slot < 1 then slot = 1 elseif slot > 8 then slot = 8 end
label = label or "FB01 Dump"

local _, _, _, textsz = r.MIDI_CountEvts(take)
local hex_msgs={}
local count=0
local bytes=0
for i=0,textsz-1 do
  local ok2, sel, mut, ppq, typ, msgbin = r.MIDI_GetTextSysexEvt(take, i)
  if ok2 and typ==-1 and msgbin and #msgbin>0 then
    local b1 = msgbin:byte(1)
    if b1 ~= 0xF0 then
      msgbin = string.char(0xF0) .. msgbin .. string.char(0xF7)
    end
    hex_msgs[#hex_msgs+1]=bin_to_hex(msgbin)
    count=count+1
    bytes=bytes+#msgbin
  end
end
if count==0 then
  r.MB("No SysEx events found.", "FB-01 Store Dump", 0)
  return
end

local section="IFLS_FB01_DUMP_V8"
local key=string.format("slot_%02d", slot)
local payload = label.."|"..table.concat(hex_msgs, "\n")
r.SetExtState(section, key, payload, true)

r.MB("Stored "..count.." SysEx messages ("..bytes.." bytes) into ExtState slot "..slot..".\n\nIf this is a big voice-bank dump, prefer exporting to .syx too.", "FB-01 Store Dump", 0)
