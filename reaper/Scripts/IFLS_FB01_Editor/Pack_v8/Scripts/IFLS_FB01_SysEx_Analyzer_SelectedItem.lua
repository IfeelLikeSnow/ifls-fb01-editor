-- @description IFLS Workbench - Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_SysEx_Analyzer_SelectedItem.lua
-- @version 0.63.0
-- @author IfeelLikeSnow


-- IFLS_FB01_SysEx_Analyzer_SelectedItem.lua
-- Analyzes SysEx events in the selected MIDI item:
-- - counts messages
-- - prints unique headers (first few bytes)
-- - detects FB-01 param-change pattern: F0 43 75 0s zz pp 0y 0x F7
-- - detects dump request/ack patterns
--
-- Output goes to REAPER console.

local r = reaper
local function msg(s) r.ShowConsoleMsg(tostring(s).."\n") end

local function get_take()
  local item = r.GetSelectedMediaItem(0,0)
  if not item then return nil, "No item selected." end
  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then return nil, "Selected item is not MIDI." end
  return take
end

local function hex_prefix(bin, n)
  local t={}
  local len = math.min(#bin, n)
  for i=1,len do t[#t+1]=string.format("%02X", bin:byte(i)) end
  return table.concat(t," ")
end

local function is_param_change(bin)
  -- REAPER returns SysEx payload WITHOUT bounding F0/F7.
  -- Accept both framed and unframed.
  if not bin or #bin < 6 then return false end
  local b1 = bin:byte(1)
  local framed = (b1 == 0xF0)
  local function byte_at(n)
    return bin:byte(n)
  end
  if framed then
    if #bin < 9 then return false end
    if byte_at(1)~=0xF0 or byte_at(2)~=0x43 or byte_at(3)~=0x75 then return false end
    if byte_at(#bin)~=0xF7 then return false end
    local low_n, high_n = byte_at(7), byte_at(8)
    if (low_n & 0xF0)~=0 or (high_n & 0xF0)~=0 then return false end
    return true
  else
    -- unframed: starts at manufacturer id 43 75 ...
    if byte_at(1)~=0x43 or byte_at(2)~=0x75 then return false end
    -- expect at least: 43 75 0s zz pp 0y 0x
    if #bin < 8 then return false end
    local low_n, high_n = byte_at(6), byte_at(7)
    -- In unframed payload, positions shift by -1 (no F0)
    if (low_n & 0xF0)~=0 or (high_n & 0xF0)~=0 then return false end
    return true
  end
end

local take, err = get_take()
if not take then
  r.MB(err, "FB-01 SysEx Analyzer", 0)
  return
end

r.ShowConsoleMsg("")
msg("=== FB-01 SysEx Analyzer (Selected Item) ===")

local _, _, _, textsz = r.MIDI_CountEvts(take)
msg("Text/SysEx events: "..textsz)

local headers = {}
local param_count=0
local total_len=0
for i=0,textsz-1 do
  local ok, sel, mut, ppq, typ, msgbin = r.MIDI_GetTextSysexEvt(take, i)
  if ok and typ==-1 and msgbin and #msgbin>0 then
    total_len = total_len + #msgbin
    local h = hex_prefix(msgbin, 8)
    headers[h] = (headers[h] or 0) + 1
    if is_param_change(msgbin) then param_count = param_count + 1 end
  end
end

msg("Total SysEx bytes (sum): "..total_len)
msg("Detected param-change-like messages: "..param_count)
msg("")
msg("Top headers (first 8 bytes) -> count:")
local items={}
for k,v in pairs(headers) do items[#items+1]={k,v} end
table.sort(items, function(a,b) return a[2]>b[2] end)
for i=1,math.min(#items,20) do
  msg(string.format("%4d  %s", items[i][2], items[i][1]))
end
msg("=== end ===")
