
-- FB-01 SysEx Receiver (B2.2)
-- Polls REAPER global MIDI input history (MIDI_GetRecentInputEvent) and assembles SysEx.
-- Handles ACK/NAK/CANCEL and exposes last received dump as raw bytes.

local r = reaper
local M = {}

M.state = {
  last_seq = 0,
  syx_collecting = false,
  syx_buf = {},
  last_msg = nil,         -- {bytes=..., kind=..., ts=..., dev=...}
  last_handshake = nil,   -- "ACK"/"NAK"/"CANCEL"
  last_error = nil,
}

local function bytes_from_string(buf)
  local t = {}
  for i = 1, #buf do t[#t+1] = string.byte(buf, i) end
  return t
end

local function find_byte(t, b)
  for i=1,#t do if t[i]==b then return i end end
  return nil
end

local function slice(t, a, b)
  local out = {}
  for i=a,b do out[#out+1]=t[i] end
  return out
end

local function hex(t, maxn)
  maxn = maxn or #t
  local n = math.min(#t, maxn)
  local s = {}
  for i=1,n do s[#s+1]=string.format("%02X", t[i]) end
  if #t > n then s[#s+1] = "…" end
  return table.concat(s, " ")
end

local function classify(msg)
  -- Handshake: F0 43 6s 02/03/04 F7
  if #msg == 6 and msg[1]==0xF0 and msg[2]==0x43 and (msg[3] & 0xF0)==0x60 and msg[6]==0xF7 then
    if msg[4]==0x02 then return "ACK" end
    if msg[4]==0x03 then return "NAK" end
    if msg[4]==0x04 then return "CANCEL" end
  end
  -- Dump response: starts with F0 43 and ends with F7
  if #msg >= 8 and msg[1]==0xF0 and msg[2]==0x43 and msg[#msg]==0xF7 then
    return "DUMP"
  end
  return "OTHER"
end

function M.poll(max_events)
  max_events = max_events or 64

  -- Always call idx=0 to latch latest
  local ok, buf, ts, dev, projPos, loopCnt = r.MIDI_GetRecentInputEvent(0)
  if ok == 0 then return end

  for idx=0, max_events-1 do
    local seq, buf2, ts2, dev2 = r.MIDI_GetRecentInputEvent(idx)
    if seq == 0 then break end
    if seq <= M.state.last_seq then break end

    local b = bytes_from_string(buf2)
    -- Assemble sysex possibly split across events
    local f0 = find_byte(b, 0xF0)
    local f7 = find_byte(b, 0xF7)

    if f0 then
      M.state.syx_collecting = true
      M.state.syx_buf = {}
      for i=f0,#b do M.state.syx_buf[#M.state.syx_buf+1]=b[i] end
      if f7 and f7 > f0 then
        -- complete in same event
        local msg = slice(b, f0, f7)
        local kind = classify(msg)
        if kind=="ACK" or kind=="NAK" or kind=="CANCEL" then
          M.state.last_handshake = kind
        elseif kind=="DUMP" then
          M.state.last_msg = {bytes=msg, kind=kind, ts=ts2, dev=dev2, preview=hex(msg, 24)}
        end
        M.state.syx_collecting = false
        M.state.syx_buf = {}
      end
    elseif M.state.syx_collecting then
      for i=1,#b do M.state.syx_buf[#M.state.syx_buf+1]=b[i] end
      local f7b = find_byte(b, 0xF7)
      if f7b then
        local msg = M.state.syx_buf
        local kind = classify(msg)
        if kind=="ACK" or kind=="NAK" or kind=="CANCEL" then
          M.state.last_handshake = kind
        elseif kind=="DUMP" then
          M.state.last_msg = {bytes=msg, kind=kind, ts=ts2, dev=dev2, preview=hex(msg, 24)}
        end
        M.state.syx_collecting = false
        M.state.syx_buf = {}
      end
    end

    M.state.last_seq = seq
  end
end

function M.get_last_dump()
  return M.state.last_msg
end

function M.clear_last_dump()
  M.state.last_msg = nil
  M.state.last_handshake = nil
  M.state.last_error = nil
end

function M.save_last_dump_to_file(filepath)
  local m = M.state.last_msg
  if not m or not m.bytes then return false, "no dump" end
  local f = io.open(filepath, "wb")
  if not f then return false, "cannot open file" end
  for i=1,#m.bytes do f:write(string.char(m.bytes[i] & 0xFF)) end
  f:close()
  return true
end



-- =========================
-- Take-based SysEx capture
-- =========================
-- REAPER does not guarantee that large SysEx shows up in MIDI_GetRecentInputEvent().
-- This backend scans recent MIDI takes for SysEx events and imports the newest one into last_msg.

M.take_state = M.take_state or {
  last_sig = nil,
  last_import_at = 0,
}

local function get_guid(obj, key)
  local ok, s = r.GetSetMediaItemInfo_String(obj, key or "GUID", "", false)
  if ok then return s end
  return ""
end

local function get_take_guid(take)
  local ok, s = r.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
  if ok then return s end
  return ""
end

local function item_endpos(item)
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  return pos + len
end

local function find_most_recent_midi_take_with_sysex()
  local n = r.CountMediaItems(0)
  local best = nil
  local best_end = -1

  for i=0,n-1 do
    local item = r.GetMediaItem(0, i)
    if item then
      local take = r.GetActiveTake(item)
      if take and r.TakeIsMIDI(take) then
        local _, _, textsyx = r.MIDI_CountEvts(take)
        if textsyx and textsyx > 0 then
          local e = item_endpos(item)
          if e > best_end then
            best_end = e
            best = {item=item, take=take, textsyx=textsyx, endpos=e}
          end
        end
      end
    end
  end

  return best
end

local function extract_last_sysex_bytes_from_take(take)
  local _, _, textsyx = r.MIDI_CountEvts(take)
  if not textsyx or textsyx <= 0 then return nil, "no text/sysex evts" end

  -- iterate from end: newest event is often last
  for idx = textsyx-1, 0, -1 do
    local ok, selected, muted, ppqpos, typ, msg = r.MIDI_GetTextSysexEvt(take, idx)
    if ok and typ == -1 and msg and #msg > 0 then
      local b = bytes_from_string(msg)
      -- Must be SysEx and end with F7
      if #b >= 6 and b[1] == 0xF0 and b[#b] == 0xF7 then
        return b
      end
    end
  end

  return nil, "no sysex found"
end

function M.poll_take_backend()
  local best = find_most_recent_midi_take_with_sysex()
  if not best then return end

  local item_guid = get_guid(best.item, "GUID")
  local take_guid = get_take_guid(best.take)
  local sig = string.format("%s|%s|%d|%.3f", item_guid, take_guid, best.textsyx or 0, best.endpos or 0)

  if sig == M.take_state.last_sig then return end

  local bytes, err = extract_last_sysex_bytes_from_take(best.take)
  if not bytes then
    M.take_state.last_sig = sig -- still advance to avoid re-scanning same empty content
    return
  end

  local kind = classify(bytes)
  if kind=="ACK" or kind=="NAK" or kind=="CANCEL" then
    M.state.last_handshake = kind
  elseif kind=="DUMP" then
    M.state.last_msg = {
      bytes = bytes,
      kind = "DUMP",
      ts = r.time_precise(),
      dev = -1,
      preview = hex(bytes, 24),
      backend = "TAKE",
    }
  end

  M.take_state.last_sig = sig
  M.take_state.last_import_at = r.time_precise()
end

return M
