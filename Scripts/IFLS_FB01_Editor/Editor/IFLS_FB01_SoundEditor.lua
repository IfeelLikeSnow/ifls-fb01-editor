-- @description IFLS FB-01 Editor & Librarian (ReaImGui)
-- @version 0.1.8
-- @author IfeelLikeSnow
-- @about
--   Yamaha FB-01 editor/librarian for REAPER. Includes capture/verify, patch browser, A/B audition, scan/queue, session bundles, and algorithm calibration.
-- @changelog
--   - GitHub/ReaPack-ready packaging.
--

-- =========================
-- PHASE 33/34 SELECT RESULT: select by entry (source/file/voice) and optional auto-audition
-- =========================
local function _select_result_entry(ent)
  if not (ent and ent.source and ent.file and ent.voice) then return false end
  local res = _lib_load_bank(ent.source, ent.file)
  if not (res and res.bank and res.bank.voices and res.bank.voices[ent.voice]) then return false end
  LIBRARY.file_sel = ent.file
  LIBRARY.file_sel_name = ent.file:match("([^/\\]+)$") or ent.file
  LIBRARY.file_sel_meta = res.meta or {}
  LIBRARY.selected_voice = ent.voice
  LIBRARY.selected_voice_bytes = res.bank.voices[ent.voice]
  -- recent push (reuse existing logic by building rkey)
  local rkey = _lib_entry_key(ent.source, LIBRARY.file_sel_name, ent.voice)
  if LIBRARY.user_meta then _lib_recent_push(LIBRARY.user_meta, rkey); _lib_save_user_meta(LIBRARY.user_meta) end
  -- optional auto audition
  if LIBRARY.auto_audition then
    send_inst_voice_temp(LIBRARY.selected_voice_bytes, 0)
  end
  return true
end

local function _queue_sig_from_results()
  if not (LIBRARY and LIBRARY.search_results) then return "" end
  local n = #LIBRARY.search_results
  if n == 0 then return "0" end
  local first = LIBRARY.search_results[1]
  local last  = LIBRARY.search_results[n]
  local function k(it)
    return tostring(it.source or "").."|"..tostring(it.file or "").."|"..tostring(it.voice or "")
  end
  return tostring(n) .. ":" .. k(first) .. ":" .. k(last)
end

local function _queue_build_from_current_results(force)
  local sig = _queue_sig_from_results()
  if (not force) and LIBRARY.queue_list and LIBRARY.queue_last_sig == sig and #LIBRARY.queue_list > 0 then
    return #LIBRARY.queue_list
  end
  local q = {}
  if LIBRARY and LIBRARY.search_results then
    for _,it in ipairs(LIBRARY.search_results) do
      if it.source and it.file and it.voice then
        q[#q+1] = { source=it.source, file=it.file, voice=it.voice }
      end
    end
  end
  LIBRARY.queue_list = q
  LIBRARY.queue_pos = 0
  LIBRARY.queue_last_sig = sig
  return #q
end

local function _queue_next()
  if not LIBRARY then return false end
  if (LIBRARY.queue_auto_rebuild) then _queue_build_from_current_results(false) end
  if not (LIBRARY.queue_list and #LIBRARY.queue_list>0) then return false end
  local n = #LIBRARY.queue_list
  local pos = (LIBRARY.queue_pos or 0) + 1
  if pos > n then
    if LIBRARY.queue_wrap ~= false then pos = 1 else pos = n end
  end
  LIBRARY.queue_pos = pos
  return _select_result_entry(LIBRARY.queue_list[pos])
end

local function _queue_prev()
  if not LIBRARY then return false end
  if (LIBRARY.queue_auto_rebuild) then _queue_build_from_current_results(false) end
  if not (LIBRARY.queue_list and #LIBRARY.queue_list>0) then return false end
  local n = #LIBRARY.queue_list
  local pos = (LIBRARY.queue_pos or 1) - 1
  if pos < 1 then
    if LIBRARY.queue_wrap ~= false then pos = n else pos = 1 end
  end
  LIBRARY.queue_pos = pos
  return _select_result_entry(LIBRARY.queue_list[pos])
end
  

-- Phase 30: send a 64-byte voice block as InstVoice SysEx (temporary audition)
local function send_inst_voice_temp(voice_block64, inst0)

-- =========================
-- PHASE 31 AB DIFF: decode A/B and show param diffs; apply diffs to current
-- =========================
local function _ab_decode(block64)
  if not block64 then return nil end
  if VoiceMap and VoiceMap.decode_voice_block then
    local v, ops = VoiceMap.decode_voice_block(block64)
    return v, ops
  end
  return nil
end

local function _ab_collect_diffs(va, oa, vb, ob)
  local diffs = {}
  local function cmp(prefix, ta, tb)
    ta = ta or {}; tb = tb or {}
    for k,v in pairs(ta) do
      if tb[k] ~= v then
        diffs[#diffs+1] = { path=prefix..k, a=v, b=tb[k] }
      end
    end
    for k,v in pairs(tb) do
      if ta[k] == nil then
        diffs[#diffs+1] = { path=prefix..k, a=nil, b=v }
      end
    end
  end
  cmp("voice.", va, vb)
  for op=1,4 do
    cmp(("op%d."):format(op), oa and oa["op"..op], ob and ob["op"..op])
  end
  table.sort(diffs, function(x,y) return x.path < y.path end)
  return diffs
end

local function _ab_apply_diffs_to_current(diffs, target_voice, target_ops, fromA)
  if not diffs then return end
  local src = fromA and "a" or "b"
  for _,d in ipairs(diffs) do
    local val = d[src]
    local pfx, key = d.path:match("^([^%.]+)%.(.+)$")
    if pfx == "voice" then
      target_voice[key] = val
    else
      local opn = pfx:match("^op(%d+)$")
      if opn then
        local okey = "op"..opn
        target_ops[okey] = target_ops[okey] or {}
        target_ops[okey][key] = val
      end
    end
  end
end

  if not voice_block64 then return false end
  local sys = CAPTURE_CFG and CAPTURE_CFG.sys_ch or 0
  local inst = inst0 or 0
  local msg = VoiceDump.build_inst_voice_sysex(voice_block64, sys, inst)
  if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
  _log_add("send", "InstVoice temp send (inst "..tostring(inst)..")")
  if LIBRARY then LIBRARY.last_send_ts = os.date("%Y-%m-%d %H:%M:%S") end
  return true
end

-- =========================
-- PHASE 29 ALGORITHM MAP: Carrier/Modulator map per algorithm + session bundle export/import
-- =========================
-- FB-01 has 8 algorithms. Map carriers (audible) vs modulators (usually not directly audible).
-- NOTE: This mapping is best-effort and can be adjusted if you confirm exact FB-01 algo graphs.
ALGO_MAP = {
  [0] = { carriers={1}, mods={2,3,4} },
  [1] = { carriers={1,3}, mods={2,4} },
  [2] = { carriers={1,2}, mods={3,4} },
  [3] = { carriers={1,4}, mods={2,3} },
  [4] = { carriers={1,2,3,4}, mods={} }, -- parallel
  [5] = { carriers={1,2}, mods={3,4} },
  [6] = { carriers={1}, mods={2,3,4} },
  [7] = { carriers={1,2}, mods={3,4} },
}

-- =========================
-- PHASE 36.7 TONEFIX CHAIN + AUTOCAL-ONLY MODE + NOISE-AWARE TREBLE
-- - Exports a real .RfxChain by creating a temp track, inserting ToneFix, then extracting FXCHAIN chunk.
-- - "AutoCal-only" mode: enable ToneFix only during AutoCal, then bypass afterwards.
-- - Noise-aware treble boost: sets ToneFix high-shelf based on baseline noise stats (MAD/StdDev -> margin_reco).
-- =========================
local function _clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function _tonefix_calc_hsdb()
  -- Use baseline-derived margin as a proxy for noise. Higher noise => less treble boost.
  local m = (AUTOCAL and (AUTOCAL.margin_reco or AUTOCAL.margin_db)) or 12.0
  if not m then m = 12.0 end
  -- Map margin 6..24 dB -> boost 10..2 dB
  local t = (m - 6.0) / 18.0
  t = _clamp(t, 0.0, 1.0)
  local boost = 10.0 - 8.0 * t
  return _clamp(boost, 2.0, 10.0)
end

local function _jsfx_norm(val, minv, maxv)
  if maxv == minv then return 0.0 end
  return _clamp((val - minv) / (maxv - minv), 0.0, 1.0)
end

local function _tonefix_apply_params(aud_tr, fxidx)
  if not aud_tr or fxidx == nil then return end
  if not r.TrackFX_SetParam then return end
  -- Slider mapping (JSFX): slider1..5 -> params 0..4 (0..1 normalized)
  local hsdb = _tonefix_calc_hsdb()
  -- keep defaults for others; only set high shelf gain (slider4 range -12..18)
  r.TrackFX_SetParam(aud_tr, fxidx, 3, _jsfx_norm(hsdb, -12.0, 18.0))
end

local function _tonefix_set_enabled(aud_tr, enabled)
  if not aud_tr then return end
  if not r.TrackFX_AddByName then return end
  local fxname = "JS: IFLS FB-01 ToneFix"
  local idx = r.TrackFX_AddByName(aud_tr, fxname, false, 0)
  if idx < 0 then return end
  if r.TrackFX_SetEnabled then
    r.TrackFX_SetEnabled(aud_tr, idx, enabled and true or false)
  end
  if enabled then _tonefix_apply_params(aud_tr, idx) end
end

local function _rfxchain_extract_from_track_chunk(chunk)
  if not chunk then return nil end
  local fx = chunk:match("<FXCHAIN\n(.-)\n>") -- captures FXCHAIN inner text
  return fx
end

local function _write_file(path, content)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

local function _install_tonefix_rfxchain()
  local rp = r.GetResourcePath()
  local dir = rp .. "/FXChains/IFLS"
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(dir, 0) end
  local path = dir .. "/IFLS_FB01_ToneFix.RfxChain"

  -- Build chain on a temp track (end of project)
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, true)
  local tr = r.GetTrack(0, idx)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", "__IFLS_TMP_TONEFIX__", true)

  -- Add ToneFix
  local fxidx = -1
  if r.TrackFX_AddByName then
    fxidx = r.TrackFX_AddByName(tr, "JS: IFLS FB-01 ToneFix", false, -1)
    if fxidx >= 0 then
      _tonefix_apply_params(tr, fxidx)
    end
  end

  -- Extract FXCHAIN chunk
  local ok, chunk = r.GetTrackStateChunk(tr, "", false)
  local fxchain = ok and _rfxchain_extract_from_track_chunk(chunk) or nil

  -- Cleanup temp track
  r.DeleteTrack(tr)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()

  if not fxchain then return nil end
  local wrote = _write_file(path, fxchain)
  if not wrote then return nil end
  return path
end

-- =========================
-- PHASE 36.6 ULTRA-PRO
-- - SysEx send for test patch can optionally use SendMIDIMessageToHardware() (bypasses track routing)
-- - Baseline stats: median + MAD + stddev -> recommended margin
-- - Device lock: store MIDI output name and remap if indices change
-- - Audio Return FX: auto-insert JSFX "IFLS FB-01 ToneFix" (treble rolloff compensation, optional)
-- =========================
local function _mean_std(vals)
  if not vals or #vals == 0 then return nil, nil end
  local sum = 0.0
  for _,v in ipairs(vals) do sum = sum + v end
  local mean = sum / #vals
  local ss = 0.0
  for _,v in ipairs(vals) do
    local d = v - mean
    ss = ss + d*d
  end
  local var = ss / math.max(1, (#vals-1))
  return mean, math.sqrt(var)
end

local function _mad(vals, med)
  if not vals or #vals == 0 then return nil end
  med = med or _median(vals) or 0
  local dev = {}
  for i,v in ipairs(vals) do dev[i] = math.abs(v - med) end
  return _median(dev)
end

local function _recommend_margin_db(mad, std)
  -- Heuristic: keep it conservative (avoid false positives from noise).
  -- MAD is robust to outliers; std catches broader noise floors.
  local m = 6.0
  if mad and mad > 0 then m = math.max(m, mad * 6.0) end
  if std and std > 0 then m = math.max(m, std * 4.0) end
  if m > 24.0 then m = 24.0 end
  return m
end

local function _find_midi_out_idx_by_name(name)
  if not name or name == "" then return nil end
  local outs = _list_midi_outputs()
  for _,o in ipairs(outs) do
    if o.name == name then return o.idx end
  end
  return nil
end

local function _ensure_tonefix_fx(aud_tr)
  if not aud_tr then return end
  if not r.TrackFX_AddByName then return end
  local fxname = "JS: IFLS FB-01 ToneFix"
  local idx = r.TrackFX_AddByName(aud_tr, fxname, false, 0) -- 0=find only
  if idx < 0 then
    idx = r.TrackFX_AddByName(aud_tr, fxname, false, -1) -- add
    if idx >= 0 then
      -- Store a note in extstate
      r.SetExtState("IFLS_FB01","TONEFIX_INSTALLED","1", true)
    end
  end
end

-- =========================
-- PHASE 36.5 BASELINE MEDIAN + MIDI PREFS BEST-EFFORT + SendMIDIMessageToHardware()
-- - Baseline noise is measured as median of N samples for robustness
-- - MIDI autodetect: best-effort "enabled-only" (REAPER typically enumerates enabled devices; if not, user can filter via preferred substring)
-- - Optional: use SendMIDIMessageToHardware() when available, otherwise StuffMIDIMessage()
-- References:
--   - REAPER changelog: "ReaScript: add SendMIDIMessageToHardware()" (REAPER 6.x era)
--   - StuffMIDIMessage external device mode: dest = 16 + out_idx
-- =========================
local function _median(vals)
  if not vals or #vals == 0 then return nil end
  table.sort(vals)
  local n = #vals
  if (n % 2) == 1 then
    return vals[(n+1)//2]
  end
  return (vals[n//2] + vals[n//2 + 1]) * 0.5
end

local function _midi_send_raw(out_idx, bytes)
  if not bytes then return end
  if r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware and out_idx ~= nil then
    local msg = string.char(table.unpack(bytes))
    -- output is hardware MIDI output device index
    r.SendMIDIMessageToHardware(tonumber(out_idx), msg)
    return
  end
  -- fallback: StuffMIDIMessage expects separate bytes; only supports 3-byte channel messages
  if #bytes >= 3 then
    local dest = 0
    if AUTOCAL and AUTOCAL.midi_use_hw and AUTOCAL.midi_out_idx ~= nil then dest = 16 + tonumber(AUTOCAL.midi_out_idx) end
    r.StuffMIDIMessage(dest, bytes[1], bytes[2], bytes[3])
  end
end

-- =========================
-- PHASE 36.4 AUTO-DETECT IO (Audio Return + MIDI Out)
-- - Audio: choose a valid stereo input pair automatically if 7/8 doesn't exist
-- - MIDI: if only one MIDI output device exists, auto-select it for StuffMIDIMessage hardware mode
--   and (optional) set I_MIDIHWOUT on the "FB-01 MIDI OUT" track.
-- References:
--   - StuffMIDIMessage hardware destination: 16+deviceIndex (Ultraschall docs)
--   - I_MIDIHWOUT bitfield: low 5 bits channels, next 5 bits output device index
-- =========================
local function _get_num_audio_inputs()
  if r.GetNumAudioInputs then return r.GetNumAudioInputs() end
  return nil
end

local function _autodetect_audio_in_l()
  local n = _get_num_audio_inputs()
  if not n or n < 2 then return 1 end
  -- choose highest stereo pair start (1-based odd): 1/2, 3/4, 5/6, ...
  local inL = n - 1
  if inL < 1 then inL = 1 end
  if (inL % 2) == 0 then inL = inL - 1 end
  if inL < 1 then inL = 1 end
  return inL
end

local function _list_midi_outputs()
  local out = {}
  if not r.GetNumMIDIOutputs or not r.GetMIDIOutputName then return out end
  local n = r.GetNumMIDIOutputs()
  for i=0,(n-1) do
    local ok, name = r.GetMIDIOutputName(i, "")
    if ok then out[#out+1] = {idx=i, name=name} end
  end
  return out
end

local function _autodetect_midi_output(preferred_substr)
  local outs = _list_midi_outputs()
  if #outs == 0 then return nil end
  if #outs == 1 then return outs[1].idx end

  local pref = preferred_substr
  if pref and pref ~= "" then
    local p = pref:lower()
    for _,o in ipairs(outs) do
      if (o.name or ""):lower():find(p, 1, true) then return o.idx end
    end
  end

  -- heuristic: pick first that mentions mioXM / Yamaha / FB-01 if present
  local hints = {"mioxm","yamaha","fb-01","fb01"}
  for _,h in ipairs(hints) do
    for _,o in ipairs(outs) do
      if (o.name or ""):lower():find(h, 1, true) then return o.idx end
    end
  end

  return outs[1].idx
end

local function _set_track_midi_hwout(track, out_idx, chan)
  -- I_MIDIHWOUT: low 5 bits channels (0=all, 1-16), next 5 bits are output device index (0-31)
  -- If out_idx is >31 we do not set (REAPER field limited per docs).
  if not track or not out_idx then return false end
  if out_idx < 0 or out_idx > 31 then return false end
  local ch = chan or 0
  if ch < 0 then ch = 0 end
  if ch > 16 then ch = 0 end
  local v = (out_idx << 5) | (ch & 31)
  r.SetMediaTrackInfo_Value(track, "I_MIDIHWOUT", v)
  return true
end

-- =========================
-- PHASE 36.3 ROBUST AUTOCAL + AUTO-ENSURE TRACKS
-- Improvements:
--  - Optional: auto-create/ensure workbench tracks for AutoCal (idempotent)
--  - Optional: measure noise baseline and use (baseline + margin) threshold
--  - Repeats per OP and retry logic for borderline cases
-- =========================
local function _ensure_track(name)
  local n = r.CountTracks(0)
  for i=0,n-1 do
    local tr = r.GetTrack(0,i)
    local ok, tn = r.GetTrackName(tr, "")
    if ok and tn == name then return tr end
  end
  r.InsertTrackAtIndex(n, true)
  local tr = r.GetTrack(0,n)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local function _autocal_ensure_tracks()
    local aud=_find_track_by_name(AUTOCAL.track_name or "FB-01 Audio Return")
    if aud and AUTOCAL.tonefix_fx then
      local mode = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
      if mode == "autocal" then _tonefix_set_enabled(aud, true) end
    end
  -- Creates/ensures the 3 workbench tracks used across the project.
  -- NOTE: We do NOT force MIDI HW out (device indices vary per system).
  local midi_tr = _ensure_track("FB-01 MIDI OUT")
  local aud_tr  = _ensure_track("FB-01 Audio Return")
  local cap_tr  = _ensure_track("FB-01 CAPTURE")

  -- Audio Return: set monitoring ON, set stereo input if configured
  r.SetMediaTrackInfo_Value(aud_tr, "I_RECMON", 1)
  local inL = tonumber(r.GetExtState("IFLS_FB01","AUDIO_IN_L") or "") or 7
  local n_in = _get_num_audio_inputs()
  if not n_in or n_in < inL+1 then
    inL = _autodetect_audio_in_l()
    r.SetExtState("IFLS_FB01","AUDIO_IN_L", tostring(inL), true)
  end
  -- I_RECINPUT stereo flag = 1024 + (inL-1)
  r.SetMediaTrackInfo_Value(aud_tr, "I_RECINPUT", 1024 + (inL-1))

  -- Optional: arm off by default
  r.SetMediaTrackInfo_Value(aud_tr, "I_RECARM", 0)
  if AUTOCAL and AUTOCAL.tonefix_fx then _ensure_tonefix_fx(aud_tr) end
  if AUTOCAL and AUTOCAL.tonefix_fx then
    local mode = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
    local en = (mode ~= "autocal") or (AUTOCAL.running == true)
    _tonefix_set_enabled(aud_tr, en)
  end

  
  -- MIDI HW out: optional (only if a single or selected device is known)
  if AUTOCAL and AUTOCAL.midi_set_track_hwout and AUTOCAL.midi_out_idx ~= nil then
    _set_track_midi_hwout(midi_tr, tonumber(AUTOCAL.midi_out_idx), 0)
  end

r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  return midi_tr, aud_tr, cap_tr
end

local function _autocal_threshold_db()
  local thr = AUTOCAL.thresh_db or -45.0
  if AUTOCAL.use_baseline and AUTOCAL.baseline_db then
    thr = AUTOCAL.baseline_db + (AUTOCAL.margin_db or 12.0)
  end
  return thr
end

-- =========================
-- PHASE 36.2 AUTO METER CAL: automatic algorithm calibration using audio return track peak meters
-- Requirements:
--   - FB-01 audio return routed into a REAPER track (monitoring on)
--   - MIDI note can be sent to the instrument (hardware MIDI out configured)
-- =========================
AUTOCAL = AUTOCAL or {
  running=false,
  algo=0, op=1,
  phase="idle",
  t0=0,
  note=60, vel=100, chan=0,
  note_len=0.8, pause=0.35,
  thresh_db=-45.0,
  track_name="FB-01 Audio Return",
  audible = {},
  last_db = nil,
  status = "",
}

local function _db_from_peak(peak)
  if not peak or peak <= 0 then return -150.0 end
  return 20.0 * math.log(peak, 10)
end

local function _find_track_by_name(name)
  local n = r.CountTracks(0)
  for i=0,n-1 do
    local tr = r.GetTrack(0,i)
    local ok, tn = r.GetTrackName(tr, "")
    if ok and tn == name then return tr end
  end
  return nil
end

local function _list_track_names()
  local out = {}
  local n = r.CountTracks(0)
  for i=0,n-1 do
    local tr = r.GetTrack(0,i)
    local ok, tn = r.GetTrackName(tr, "")
    if ok and tn and tn ~= "" then out[#out+1]=tn end
  end
  table.sort(out)
  return out
end

local function _peak_hold_db(tr, clear)
  -- Prefer hold in dB*0.01 when available (more stable)
  if r.Track_GetPeakHoldDB then
    local l = r.Track_GetPeakHoldDB(tr, 0, clear and 1 or 0) -- returns dB*0.01
    local rdb = r.Track_GetPeakHoldDB(tr, 1, clear and 1 or 0)
    local ld = (l or -15000) / 100.0
    local rd = (rdb or -15000) / 100.0
    return math.max(ld, rd)
  end
  -- Fallback: instantaneous peak
  if r.Track_GetPeakInfo then
    local lp = r.Track_GetPeakInfo(tr, 0)
    local rp = r.Track_GetPeakInfo(tr, 1)
    return math.max(_db_from_peak(lp), _db_from_peak(rp))
  end
  return -150.0
end

local function _send_test_note(chan, note, vel, on)
  local status = (on and 0x90 or 0x80) + (chan or 0)
  local n = note or 60
  local v = vel or 100
  if AUTOCAL and AUTOCAL.midi_use_hw and AUTOCAL.midi_out_idx ~= nil and AUTOCAL.midi_use_send_to_hw then
    _midi_send_raw(AUTOCAL.midi_out_idx, {status, n, v})
    return
  end
  -- StuffMIDIMessage fallback (supports device dest=16+idx or VKB/track routing dest=0)
  local dest = 0
  if AUTOCAL and AUTOCAL.midi_use_hw and AUTOCAL.midi_out_idx ~= nil then dest = 16 + tonumber(AUTOCAL.midi_out_idx) end
  r.StuffMIDIMessage(dest, status, n, v)
end

local function _autocal_reset()
  AUTOCAL.running=false
  AUTOCAL.phase="idle"
  AUTOCAL.status="Idle"
  AUTOCAL.last_db=nil
  local mode = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
  if AUTOCAL.tonefix_fx and mode == "autocal" then
    local aud=_find_track_by_name(AUTOCAL.track_name or "FB-01 Audio Return")
    if aud then _tonefix_set_enabled(aud, false) end
  end
end

local function _autocal_init()
  AUTOCAL.running=true
  AUTOCAL.phase= (AUTOCAL.use_baseline and "baseline" or "prep_algo")
  AUTOCAL.algo=0
  AUTOCAL.op=1
  AUTOCAL.audible = {}
  for a=0,7 do AUTOCAL.audible[a] = { [1]=false,[2]=false,[3]=false,[4]=false } end
  AUTOCAL.status="Starting..."
  AUTOCAL.t0 = r.time_precise()
end

local function _autocal_step()
    -- Phase 36.3 robustness controls
    local c2
    c2, AUTOCAL.auto_ensure_tracks = r.ImGui_Checkbox(ctx, "Auto-ensure tracks", AUTOCAL.auto_ensure_tracks)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Ensure tracks now", 150, 0) then
      _autocal_ensure_tracks()
    local aud=_find_track_by_name(AUTOCAL.track_name or "FB-01 Audio Return")
    if aud and AUTOCAL.tonefix_fx then
      local mode = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
      if mode == "autocal" then _tonefix_set_enabled(aud, true) end
    end
    end

    c2, AUTOCAL.use_baseline = r.ImGui_Checkbox(ctx, "Use noise baseline", AUTOCAL.use_baseline)

    -- Phase 36.5: baseline median controls
    local changed5, v5 = r.ImGui_InputInt(ctx, "Baseline samples (median)", AUTOCAL.baseline_samples or 9, 1, 2)

    if AUTOCAL.baseline_db and AUTOCAL.margin_reco then
      r.ImGui_Text(ctx, string.format("Baseline stats: median %.1f dB, MAD %.1f, std %.1f", AUTOCAL.baseline_db, AUTOCAL.baseline_mad or -1, AUTOCAL.baseline_std or -1))
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, string.format("Use recommended margin (%.1f dB)", AUTOCAL.margin_reco), 240, 0) then
        AUTOCAL.margin_db = AUTOCAL.margin_reco
      end
    end

    if changed5 then AUTOCAL.baseline_samples = math.max(3, math.min(51, v5)) end
    r.ImGui_SameLine(ctx)
    changed5, v5 = r.ImGui_InputDouble(ctx, "Sample interval (s)", AUTOCAL.baseline_interval or 0.10, 0.01, 0.05, "%.2f")
    if changed5 then AUTOCAL.baseline_interval = math.max(0.05, math.min(0.50, v5)) end

    r.ImGui_SameLine(ctx)
    local changed2, v2 = r.ImGui_InputDouble(ctx, "Margin dB", AUTOCAL.margin_db or 12.0, 1.0, 3.0, "%.1f")
    if changed2 then AUTOCAL.margin_db = v2 end

    changed2, v2 = r.ImGui_InputInt(ctx, "Repeats per OP", AUTOCAL.repeats or 2, 1, 1)
    if changed2 then AUTOCAL.repeats = math.max(1, math.min(5, v2)) end
    r.ImGui_SameLine(ctx)
    changed2, v2 = r.ImGui_InputInt(ctx, "Retries (borderline)", AUTOCAL.retries or 1, 1, 1)
    if changed2 then AUTOCAL.retries = math.max(0, math.min(3, v2)) end
    r.ImGui_SameLine(ctx)
    changed2, v2 = r.ImGui_InputDouble(ctx, "Near dB", AUTOCAL.near_db or 3.0, 0.5, 1.0, "%.1f")
    if changed2 then AUTOCAL.near_db = math.max(0.5, math.min(12.0, v2)) end

  if not AUTOCAL.running then return end
  local now = r.time_precise()
  local tr = _find_track_by_name(AUTOCAL.track_name)
  if not tr then
    AUTOCAL.status = "ERROR: audio return track not found: "..tostring(AUTOCAL.track_name)
    AUTOCAL.running=false
    return
  end

  if AUTOCAL.phase == "baseline" and (AUTOCAL.baseline_db == nil) then
    _peak_hold_db(tr, true) -- clear
    AUTOCAL.t0 = now
    AUTOCAL.baseline_db = -99999 -- sentinel to indicate started
    return
  end
  if AUTOCAL.baseline_db == -99999 then
    -- baseline measurement will read after settle in baseline phase
    AUTOCAL.baseline_db = nil
  local tm = r.GetExtState("IFLS_FB01","TONEFIX_MODE")
  if tm ~= "" then AUTOCAL.tonefix_mode = tm end

  -- Auto-detect MIDI out if requested (single-device setups)
  if AUTOCAL.midi_use_hw and (AUTOCAL.midi_out_idx == nil) then
    local pref = AUTOCAL.midi_pref_substr or r.GetExtState("IFLS_FB01","MIDI_OUT_PREF") or ""
    local idx = _autodetect_midi_output(pref)
    if idx ~= nil then
      AUTOCAL.midi_out_idx = idx
      r.SetExtState("IFLS_FB01","MIDI_OUT_IDX", tostring(idx), true)
    local outs=_list_midi_outputs(); for _,o in ipairs(outs) do if o.idx==idx then AUTOCAL.midi_out_name=o.name; r.SetExtState("IFLS_FB01","MIDI_OUT_NAME",o.name,true) break end end
    end
  end

  end

  
  if AUTOCAL.phase == "baseline" then
    local N = tonumber(AUTOCAL.baseline_samples) or 9
    if N < 3 then N = 3 end
    if N > 51 then N = 51 end
    local dt = tonumber(AUTOCAL.baseline_interval) or 0.10
    if dt < 0.05 then dt = 0.05 end
    if dt > 0.50 then dt = 0.50 end

    AUTOCAL._bvals = AUTOCAL._bvals or {}
    AUTOCAL.status = string.format("Measuring noise baseline (%d/%d)... keep silent", #AUTOCAL._bvals, N)

    if (now - AUTOCAL.t0) < dt then return end
    AUTOCAL.t0 = now

    -- use instantaneous peak for baseline sampling (more representative than hold)
    local db = -150.0
    if r.Track_GetPeakInfo then
      local lp = r.Track_GetPeakInfo(tr, 0)
      local rp = r.Track_GetPeakInfo(tr, 1)
      db = math.max(_db_from_peak(lp), _db_from_peak(rp))
    else
      db = _peak_hold_db(tr, false)
    end
    AUTOCAL._bvals[#AUTOCAL._bvals+1] = db

    if #AUTOCAL._bvals < N then return end

    local med = _median(AUTOCAL._bvals) or db
    local mean, std = _mean_std(AUTOCAL._bvals)
    local mad = _mad(AUTOCAL._bvals, med)
    AUTOCAL.baseline_db = med
    AUTOCAL.baseline_mad = mad
    AUTOCAL.baseline_std = std
    AUTOCAL.margin_reco = _recommend_margin_db(mad, std)
    -- update ToneFix treble based on noise stats if enabled
    if AUTOCAL.tonefix_fx then
      local aud=_find_track_by_name(AUTOCAL.track_name or "FB-01 Audio Return")
      if aud then
        local fxidx = r.TrackFX_AddByName and r.TrackFX_AddByName(aud, "JS: IFLS FB-01 ToneFix", false, 0) or -1
        if fxidx and fxidx >= 0 then _tonefix_apply_params(aud, fxidx) end
      end
    end
    AUTOCAL._bvals = nil
    AUTOCAL.status = string.format("Baseline median %.1f dB (MAD %.1f, std %.1f). Reco margin %.1f dB. Thr %.1f dB",
      med, mad or -1, std or -1, AUTOCAL.margin_reco or -1, (med + (AUTOCAL.margin_db or 12.0)))
    AUTOCAL.phase = "prep_algo"
    AUTOCAL.t0 = now
    return
  end
    local db = _peak_hold_db(tr, false)
    AUTOCAL.baseline_db = db
    AUTOCAL.status = string.format("Baseline %.1f dB, threshold %.1f dB", db, _autocal_threshold_db())
    AUTOCAL.phase = "prep_algo"
    AUTOCAL.t0 = now
    return
  end

if AUTOCAL.phase == "prep_algo" then
    AUTOCAL.status = string.format("Algo %d / OP %d: sending solo-op test patch...", AUTOCAL.algo, AUTOCAL.op)
    local v, ops = _voice_clone_defaults(); v.algorithm = AUTOCAL.algo; _voice_set_solo_op(v, ops, AUTOCAL.op)
    local bytes64 = VoiceMap.encode_voice_block(v, ops)
    send_inst_voice_temp(bytes64, 0)
    _peak_hold_db(tr, true) -- clear hold
    AUTOCAL.t0 = now
    AUTOCAL.phase = "note_on"
    return
  end

  if AUTOCAL.phase == "note_on" then
    -- small settle delay after sysex send
    if (now - AUTOCAL.t0) < 0.15 then return end
    AUTOCAL.status = string.format("Algo %d / OP %d: note on...", AUTOCAL.algo, AUTOCAL.op)
    _send_test_note(AUTOCAL.chan, AUTOCAL.note, AUTOCAL.vel, true)
    AUTOCAL.t0 = now
    AUTOCAL.phase = "note_hold"
    return
  end

  if AUTOCAL.phase == "note_hold" then
    if (now - AUTOCAL.t0) < (AUTOCAL.note_len or 0.8) then return end
    AUTOCAL.status = string.format("Algo %d / OP %d: note off...", AUTOCAL.algo, AUTOCAL.op)
    _send_test_note(AUTOCAL.chan, AUTOCAL.note, 0, false)
    AUTOCAL.t0 = now
    AUTOCAL.phase = "measure"
    return
  end

  if AUTOCAL.phase == "measure" then
    -- allow meter hold to latch
    if (now - AUTOCAL.t0) < 0.10 then return end

    AUTOCAL._rep = AUTOCAL._rep or 1
    AUTOCAL._best = AUTOCAL._best or -150.0

    local db = _peak_hold_db(tr, false)
    AUTOCAL._best = math.max(AUTOCAL._best, db)
    AUTOCAL.last_db = db

    -- Repeat measurement cycles for robustness (multiple note hits per OP)
    if AUTOCAL._rep < (AUTOCAL.repeats or 1) then
      AUTOCAL._rep = AUTOCAL._rep + 1
      AUTOCAL.t0 = now
      AUTOCAL.phase = "pause" -- use pause as inter-repeat gap, then back to note_on
      AUTOCAL._next_after_pause = "note_on"
      return
    end

    local thr = _autocal_threshold_db()
    local best = AUTOCAL._best
    local audible = (best >= thr)

    -- Retry logic: if close to threshold, do another full pass (patch+note) up to retries
    AUTOCAL._try = AUTOCAL._try or 0
    if (not audible) and (AUTOCAL.retries or 0) > 0 then
      if best >= (thr - (AUTOCAL.near_db or 3.0)) and AUTOCAL._try < (AUTOCAL.retries or 0) then
        AUTOCAL._try = AUTOCAL._try + 1
        AUTOCAL._rep = 1
        AUTOCAL._best = -150.0
        _log_add("algo", string.format("AutoCal retry %d: algo %d op %d (best %.1f dB near thr %.1f)", AUTOCAL._try, AUTOCAL.algo, AUTOCAL.op, best, thr))
        AUTOCAL.t0 = now
        AUTOCAL.phase = "prep_algo"
        return
      end
    end

    AUTOCAL.audible[AUTOCAL.algo][AUTOCAL.op] = audible
    _log_add("algo", string.format("AutoCal algo %d op %d best=%.1f dB thr=%.1f -> %s", AUTOCAL.algo, AUTOCAL.op, best, thr, audible and "AUDIBLE" or "no"))
    AUTOCAL.status = string.format("Algo %d / OP %d: best %.1f dB (thr %.1f) %s", AUTOCAL.algo, AUTOCAL.op, best, thr, audible and "AUDIBLE" or "no")

    -- reset per-op counters
    AUTOCAL._rep = 1
    AUTOCAL._best = -150.0
    AUTOCAL._try = 0

    AUTOCAL.t0 = now
    AUTOCAL.phase = "pause"
    AUTOCAL._next_after_pause = nil
    return
  end
    local db = _peak_hold_db(tr, false)
    AUTOCAL.last_db = db
    local audible = (db >= (AUTOCAL.thresh_db or -45.0))
    AUTOCAL.audible[AUTOCAL.algo][AUTOCAL.op] = audible
    _log_add("algo", string.format("AutoCal algo %d op %d peak=%.1f dB -> %s", AUTOCAL.algo, AUTOCAL.op, db, audible and "AUDIBLE" or "no"))
    AUTOCAL.status = string.format("Algo %d / OP %d: peak %.1f dB (%s)", AUTOCAL.algo, AUTOCAL.op, db, audible and "AUDIBLE" or "no")
    AUTOCAL.t0 = now
    AUTOCAL.phase = "pause"
    return
  end

  if AUTOCAL.phase == "pause" then
    if (now - AUTOCAL.t0) < (AUTOCAL.pause or 0.35) then return end

    if AUTOCAL._next_after_pause then
      AUTOCAL.phase = AUTOCAL._next_after_pause
      AUTOCAL._next_after_pause = nil
      AUTOCAL.t0 = now
      return
    end

    -- advance to next operator/algorithm
    AUTOCAL.op = AUTOCAL.op + 1
    if AUTOCAL.op > 4 then
      AUTOCAL.op = 1
      AUTOCAL.algo = AUTOCAL.algo + 1
      if AUTOCAL.algo > 7 then
        AUTOCAL.phase = "finish"
      else
        AUTOCAL.phase = "prep_algo"
      end
    else
      AUTOCAL.phase = "prep_algo"
    end
    return
  end
    -- advance
    AUTOCAL.op = AUTOCAL.op + 1
    if AUTOCAL.op > 4 then
      AUTOCAL.op = 1
      AUTOCAL.algo = AUTOCAL.algo + 1
      if AUTOCAL.algo > 7 then
        AUTOCAL.phase = "finish"
      else
        AUTOCAL.phase = "prep_algo"
      end
    else
      AUTOCAL.phase = "prep_algo"
    end
    return
  end

  if AUTOCAL.phase == "finish" then
    AUTOCAL.status = "AutoCal finished. Applying carriers + exporting report..."
    -- apply per algo
    for a=0,7 do
      _algo_apply_carriers_from_checks(a, AUTOCAL.audible[a])
    end
    local p = _algo_export_calibration_report()
    if p and LIBRARY then LIBRARY.status = "AutoCal exported: " .. p end
    AUTOCAL.status = "Done. Exported: " .. tostring(p or "(failed)")
    
    local mode = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
    if AUTOCAL.tonefix_fx and mode == "autocal" then
      local aud=_find_track_by_name(AUTOCAL.track_name or "FB-01 Audio Return")
      if aud then _tonefix_set_enabled(aud, false) end
    end
AUTOCAL.running=false
    AUTOCAL.phase="idle"
    return
  end
end

-- =========================
-- PHASE 36 ALGO CALIBRATION: guided listening tests to finalize carriers per algorithm
-- =========================
local function _voice_clone_defaults()
  -- Build a simple audible test voice using existing enc/dec path.
  -- We decode current selected voice if available; else decode a zero voice and fill safe defaults.
  local base = (LIBRARY and LIBRARY.selected_voice_bytes) or nil
  local v, ops = nil, nil
  if base and VoiceMap and VoiceMap.decode_voice_block then
    v, ops = VoiceMap.decode_voice_block(base)
  end
  if not v then
    v = { algorithm=0, feedback=0, transpose=0, lfo_speed=0, lfo_delay=0, lfo_pmd=0, lfo_amd=0, pms=0, ams=0 }
    ops = { op1={}, op2={}, op3={}, op4={} }
  end
  -- ensure ops
  ops = ops or { op1={}, op2={}, op3={}, op4={} }
  for i=1,4 do
    local o = ops["op"..i] or {}
    ops["op"..i] = o
    -- safe simple sine, audible envelope-ish
    o.multiple = o.multiple or 1
    o.detune = o.detune or 0
    o.attack_rate = o.attack_rate or 31
    o.decay1_rate = o.decay1_rate or 20
    o.decay2_rate = o.decay2_rate or 0
    o.release_rate = o.release_rate or 10
    o.sustain_level = o.sustain_level or 99
    o.key_velocity_sens = o.key_velocity_sens or 0
    o.output_level = o.output_level or 99
  end
  return v, ops
end

local function _voice_set_solo_op(v, ops, solo_op)
  -- Make a voice where only solo_op is "loud"; others quiet. Modulation routing still depends on algo.
  for i=1,4 do
    local o = ops["op"..i]
    if o then
      if i == solo_op then
        o.output_level = 99
        o.sustain_level = 99
      else
        o.output_level = 0
        o.sustain_level = 0
      end
    end
  end
  -- keep algorithm as-is; this is what we are testing
  return v, ops
end

local function _algo_apply_carriers_from_checks(algo, checked)
  -- checked: table op->bool
  local carr = {}
  for op=1,4 do if checked[op] then carr[#carr+1]=op end end
  if #carr == 0 then return false end
  table.sort(carr)
  ALGO_MAP[algo] = ALGO_MAP[algo] or { carriers={1}, mods={2,3,4} }
  ALGO_MAP[algo].carriers = carr
  local seen={}
  for _,op in ipairs(carr) do seen[op]=true end
  local mods={}
  for op=1,4 do if not seen[op] then mods[#mods+1]=op end end
  ALGO_MAP[algo].mods = mods
  _algo_save_overrides()
  _log_add("algo", "Calibrated carriers for algo "..tostring(algo)..": "..table.concat(carr,","))
  return true
end

local function _algo_export_calibration_report()
  local dir = _lib_exports_dir() .. "/AlgoCalibration"
  r.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "/algo_map_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
  local f = io.open(path, "wb"); if not f then return nil end
  for a=0,7 do
    local carr = (ALGO_MAP[a] and ALGO_MAP[a].carriers) or {}
    f:write(("algo %d carriers: %s\n"):format(a, table.concat(carr, ",")))
  end
  f:close()
  return path
end

-- Phase 31: Algorithm map overrides (persist)
local function _algo_load_overrides()
  local s = _ext_get("fb01_algo_map_override", "")
  if not s or s == "" then return end
  for algo, carr in s:gmatch("(%d+)%:([%d,]+)") do
    local a = tonumber(algo)
    local t = {}
    for n in tostring(carr):gmatch("(%d+)") do t[#t+1]=tonumber(n) end
    if a and #t>0 and ALGO_MAP[a] then
      ALGO_MAP[a].carriers = t
      -- rebuild mods as complement
      local seen={}
      for _,op in ipairs(t) do seen[op]=true end
      local mods={}
      for op=1,4 do if not seen[op] then mods[#mods+1]=op end end
      ALGO_MAP[a].mods = mods
    end
  end
end

local function _algo_save_overrides()
  local parts = {}
  for a=0,7 do
    local carr = ALGO_MAP[a] and ALGO_MAP[a].carriers or {1}
    local s = tostring(a) .. ":" .. table.concat(carr, ",")
    parts[#parts+1] = s
  end
  _ext_set("fb01_algo_map_override", table.concat(parts, ";"))
end

_algo_load_overrides()

local function _algo_carriers(algo)
  local m = ALGO_MAP[tonumber(algo) or 0]
  return (m and m.carriers) or {1}
end
local function _algo_mods(algo)
  local m = ALGO_MAP[tonumber(algo) or 0]
  return (m and m.mods) or {}
end

local function _apply_algo_roles(voice_vals, op_vals)
  -- sets op.modulator based on algo map
  if not (voice_vals and op_vals) then return end
  local algo = tonumber(voice_vals.algorithm or 0) or 0
  local carriers = {}
  for _,op in ipairs(_algo_carriers(algo)) do carriers[op]=true end
  for op=1,4 do
    local o = op_vals["op"..op]
    if o then o.modulator = carriers[op] and 0 or 1 end
  end
end

-- Phase 29: Session bundle (export/import) including meta and seed
local function _bundle_path(ts)
  return _lib_exports_dir() .. "/SessionBundle_" .. (ts or os.date("%Y%m%d_%H%M%S"))
end

-- =========================
-- PHASE 38 TOOLBAR INSTALL (Pro Option C)
-- - Registers IFLS action scripts
-- - Generates a .ReaperMenu toolbar file with correct _RS... action IDs
-- - Writes it to <REAPER resource path>/MenuSets and offers to open the folder
-- =========================
local function _path_join(a,b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a..b end
  return a.."/"..b
end

local function _ensure_dir(p)
  if r.RecursiveCreateDirectory then
    r.RecursiveCreateDirectory(p, 0)
    return true
  end
  return os.execute('mkdir "'..p..'"') == 0
end

local function _register_script(abs_path)
  -- section 0 = main
  local cmd = r.AddRemoveReaScript(true, 0, abs_path, true)
  if not cmd or cmd == 0 then return nil, "AddRemoveReaScript failed: "..abs_path end
  local named = r.ReverseNamedCommandLookup(cmd)
  if not named or named == "" then return nil, "ReverseNamedCommandLookup failed for cmd "..tostring(cmd) end
  return named, nil
end

local function _build_toolbar_reapermenu(toolbar_num, actions)
  -- actions: { {icon="text", id="_RS...", label="..."}, ... }
  local parts = {}
  parts[#parts+1] = string.format("[Floating toolbar %d]", toolbar_num)
  for i,a in ipairs(actions) do
    parts[#parts+1] = string.format("icon_%d=%s", i-1, a.icon or "text")
  end
  for i,a in ipairs(actions) do
    parts[#parts+1] = string.format("item_%d=%s %s", i-1, a.id, a.label)
  end
  return table.concat(parts, " ") .. "\n"
end

local function _install_ifls_toolbar(toolbar_num)
  toolbar_num = tonumber(toolbar_num) or 1
  if toolbar_num < 1 then toolbar_num = 1 end
  if toolbar_num > 16 then toolbar_num = 16 end

  local rp = r.GetResourcePath()
  local menusets = _path_join(rp, "MenuSets")
  _ensure_dir(menusets)

  local base = _path_join(rp, "Scripts/IFLS FB-01 Editor/Actions")

  local open_id, e1 = _register_script(_path_join(base, "IFLS_FB01_Open_Editor.lua"))
  local cal_id,  e2 = _register_script(_path_join(base, "IFLS_FB01_Open_AutoCalibration.lua"))
  local set_id,  e3 = _register_script(_path_join(base, "IFLS_FB01_Setup_Tracks.lua"))
  local pan_id,  e4 = _register_script(_path_join(base, "IFLS_FB01_Panic_AllNotesOff.lua"))

  local errs = {}
  for _,e in ipairs({e1,e2,e3,e4}) do if e then errs[#errs+1]=e end end
  if #errs > 0 then
    r.ShowMessageBox(table.concat(errs, "\n"), "IFLS Toolbar install failed", 0)
    return false
  end

  local actions = {
    {icon="text", id=open_id, label="IFLS FB-01: Open Editor"},
    {icon="text", id=cal_id,  label="IFLS FB-01: Auto Calibration"},
    {icon="text", id=set_id,  label="IFLS FB-01: Setup Tracks"},
    {icon="text", id=pan_id,  label="IFLS FB-01: Panic (All Notes Off)"},
  }

  local file = _path_join(menusets, string.format("IFLS_FB01_Toolbar_Floating_%d.ReaperMenu", toolbar_num))
  local content = _build_toolbar_reapermenu(toolbar_num, actions)
  local ok = r.file_write(file, content)
  if not ok then
    -- fallback
    local f = io.open(file, "w")
    if not f then
      r.ShowMessageBox("Could not write:\n"..file, "IFLS Toolbar install failed", 0)
      return false
    end
    f:write(content); f:close()
  end

  local msg =
    "Toolbar file created:\n\n" .. file ..
    "\n\nNext steps:\n" ..
    "1) Options â†’ Customize menus/toolbarsâ€¦\n" ..
    "2) Choose 'Floating toolbar "..tostring(toolbar_num).."' in the dropdown\n" ..
    "3) Click Importâ€¦ and pick the file above\n\n" ..
    "Tip: You can rightâ€‘click any toolbar area â†’ Open toolbar â†’ Floating toolbar "..tostring(toolbar_num)

  r.ShowMessageBox(msg, "IFLS FB-01 Toolbar installed", 0)

  -- open MenuSets folder if possible (SWS), otherwise best-effort
  if r.CF_ShellExecute then r.CF_ShellExecute(menusets) end
  return true
end

-- =========================
-- PHASE 37 REAPACK INFO (Release polish): show repository info + ReaPack import URL (optional)
-- =========================
local REPO_URL = "https://github.com/IfeelLikeSnow/ifls-fb01-editor"
local REAPACK_INDEX_URL = REPO_URL .. "/raw/main/index.xml"
local IFLS_VERSION = "0.1.1"

local function _ui_reapack_info()
  if not (r and r.ImGui_CollapsingHeader) then return end
  if r.ImGui_CollapsingHeader(ctx, "About / ReaPack", r.ImGui_TreeNodeFlags_DefaultOpen()) then
    r.ImGui_Text(ctx, "IFLS FB-01 Editor v" .. IFLS_VERSION)
    r.ImGui_Text(ctx, "ReaPack index URL:")
    r.ImGui_Text(ctx, REAPACK_INDEX_URL)

    -- Toolbar install (Option C)
    local tb_num = tonumber(r.GetExtState("IFLS_FB01", "TOOLBAR_NUM") or "") or 1
    local changed, new_tb = r.ImGui_InputInt(ctx, "Toolbar slot (1-16)", tb_num, 1, 4)
    if changed then
      if new_tb < 1 then new_tb = 1 end
      if new_tb > 16 then new_tb = 16 end
      r.SetExtState("IFLS_FB01", "TOOLBAR_NUM", tostring(new_tb), true)
      tb_num = new_tb
    end
    if r.ImGui_Button(ctx, "Install IFLS Toolbar", 180, 0) then
      _install_ifls_toolbar(tb_num)
    end

    if r.ImGui_Button(ctx, "Open Repo (browser)", 180, 0) then
      if r.CF_ShellExecute then r.CF_ShellExecute(REPO_URL)
      else
        -- best effort fallback
        local cmd = (reaper.GetOS():match("Win") and ('start "" "'..REPO_URL..'"')) or ('open "'..REPO_URL..'"')
        os.execute(cmd)
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Open index.xml", 140, 0) then
      if r.CF_ShellExecute then r.CF_ShellExecute(REAPACK_INDEX_URL)
      else
        local cmd = (reaper.GetOS():match("Win") and ('start "" "'..REAPACK_INDEX_URL..'"')) or ('open "'..REAPACK_INDEX_URL..'"')
        os.execute(cmd)
      end
    end
  end
end

-- =========================
-- PHASE 36.2 FS ENUM: Use REAPER EnumerateFiles/Subdirectories when available (portable, safer than shell)
-- =========================
local function _fs_enum_files(dir)
  local out = {}
  if r.EnumerateFiles then
    local i = 0
    while true do
      local f = r.EnumerateFiles(dir, i)
      if not f then break end
      out[#out+1] = f
      i = i + 1
    end
    return out
  end
  -- fallback: no enumerate API (very old REAPER)
  local p = io.popen('dir "'..dir..'" /b 2>nul')
  if p then
    for line in p:lines() do out[#out+1]=line end
    p:close()
  end
  return out
end

local function _fs_enum_dirs(dir)
  local out = {}
  if r.EnumerateSubdirectories then
    local i = 0
    while true do
      local d = r.EnumerateSubdirectories(dir, i)
      if not d then break end
      out[#out+1] = d
      i = i + 1
    end
    return out
  end
  local p = io.popen('dir "'..dir..'" /b /ad 2>nul')
  if p then
    for line in p:lines() do out[#out+1]=line end
    p:close()
  end
  return out
end

-- =========================
-- PHASE 35 AUDIT LOG: operation log + commit pipeline helpers
-- =========================
LOG = LOG or { items={}, max=200 }

local function _log_add(kind, msg, extra)
  local t = os.date("%Y-%m-%d %H:%M:%S")
  local e = extra or {}
  LOG.items[#LOG.items+1] = { ts=t, kind=kind or "info", msg=msg or "", extra=e }
  while #LOG.items > (LOG.max or 200) do table.remove(LOG.items, 1) end
end

local function _log_export()
  local dir = _lib_exports_dir() .. "/Logs"
  r.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "/fb01_log_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
  local f = io.open(path, "wb"); if not f then return nil end
  for _,it in ipairs(LOG.items) do
    f:write(("[%s] [%s] %s\n"):format(it.ts, it.kind, it.msg))
  end
  f:close()
  return path
end

local function _write_bytes_file(path, bytes_tbl)
  local f = io.open(path, "wb"); if not f then return false end
  for i=1,#bytes_tbl do f:write(string.char(bytes_tbl[i] & 0xFF)) end
  f:close(); return true
end

local function _read_bytes_file(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*all"); f:close()
  local t = {}
  for i=1,#s do t[#t+1] = string.byte(s, i) end
  return t
end

local function _meta_path() return _lib_db_dir() .. "/library_user_meta.json" end
local function _tags_path() return _lib_db_dir() .. "/library_tags.json" end
local function _cache_path() return _lib_db_dir() .. "/library_cache.json" end

local function _copy_file(srcp, dstp)
  local f = io.open(srcp, "rb"); if not f then return false end
  local s = f:read("*all"); f:close()
  local g = io.open(dstp, "wb"); if not g then return false end
  g:write(s); g:close(); return true
end

-- =========================
-- PHASE 22 MUSICAL RANDOMIZER: carrier/modulator aware shaping + style profiles
-- =========================
RANDOM_STYLE = RANDOM_STYLE or { style = "Pad", variations = 8 }

local function _style_limits(style)
  -- returns conservative ranges / constraints
  if style == "Bass" then return { algo_lock=false, fb_max=6, lfo_max=50, detune_max=4, env_fast=true }
  elseif style == "Bell" then return { fb_max=4, lfo_max=40, detune_max=3, env_fast=false }
  elseif style == "Perc" then return { fb_max=7, lfo_max=30, detune_max=2, env_fast=true }
  elseif style == "FX" then return { fb_max=7, lfo_max=110, detune_max=7, env_fast=false }
  else return { fb_max=5, lfo_max=70, detune_max=5, env_fast=false } end -- Pad
end

local function _apply_musical_shaping(style, voice_vals, op_vals)
  local lim = _style_limits(style or "Pad")
  if not (voice_vals and op_vals) then return end

  -- feedback/lfo clamp
  if voice_vals.feedback ~= nil then voice_vals.feedback = math.min(voice_vals.feedback, lim.fb_max) end
  if voice_vals.lfo_speed ~= nil then voice_vals.lfo_speed = math.min(voice_vals.lfo_speed, lim.lfo_max) end
  if voice_vals.lfo_amd ~= nil then voice_vals.lfo_amd = math.min(voice_vals.lfo_amd, lim.lfo_max) end
  if voice_vals.lfo_pmd ~= nil then voice_vals.lfo_pmd = math.min(voice_vals.lfo_pmd, lim.lfo_max) end

  -- Phase 29: apply algo roles
  _apply_algo_roles(voice_vals, op_vals)

  -- ensure at least one operator enabled
  local enabled = {}
  for op=1,4 do
    local ekey = "op"..op.."_enable"
    local ev = voice_vals[ekey]
    if ev == nil or ev == 1 then enabled[#enabled+1]=op end
  end
  if #enabled == 0 then voice_vals.op1_enable = 1; enabled={1} end

  -- carrier/modulator aware level shaping: use op.modulator flag if present (0=carrier, 1=mod)
  for op=1,4 do
    local o = op_vals["op"..op]
    if o then
      if o.detune ~= nil then o.detune = math.min(o.detune, lim.detune_max) end
      local is_mod = (o.modulator == 1)
      if o.volume ~= nil then
        if is_mod then
          o.volume = math.min(o.volume, 70 + math.random(0,40))
        else
          o.volume = math.max(o.volume, 85 + math.random(0,42))
        end
      end
      -- env hint
      if lim.env_fast and o.attack_rate ~= nil then
        o.attack_rate = math.max(o.attack_rate, 22 + math.random(0,9))
      end
    end
  end

  -- style-specific tweaks
  if style == "Bell" then
    voice_vals.transpose = voice_vals.transpose or 24
    for op=1,4 do
      local o = op_vals["op"..op]
      if o and o.multiple ~= nil then
        if o.modulator == 1 then o.multiple = math.min(15, math.max(2, o.multiple + math.random(0,6))) end
      end
    end
  elseif style == "Bass" then
    voice_vals.transpose = 12
  elseif style == "Pad" then
    -- slower envelopes
    for op=1,4 do
      local o = op_vals["op"..op]
      if o and o.attack_rate ~= nil then o.attack_rate = math.min(o.attack_rate, 18 + math.random(0,10)) end
    end
  end
end

-- Phase 11.4: Param-based verify report export (JSON/TXT)
local function _get_project_dir()
  local ok, p = pcall(r.GetProjectPath, "")
  if ok and p and p ~= "" then return p end
  return r.GetResourcePath()
end

local function _ensure_dir(dir)
  -- best effort; REAPER on Windows supports this via recursive create when writing, but we attempt anyway
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(dir, 0) end
end

local function _write_text_file(path, content)
  local f = io.open(path, "wb")
  if not f then return false, "cannot open file: " .. tostring(path) end
  f:write(content or "")
  f:close()
  return true
end

local function _json_escape(s)
  s = tostring(s)
  s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
  return s
end

local function _json_encode(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then return tostring(v)
  elseif t == "string" then return "\"" .. _json_escape(v) .. "\""
  elseif t == "table" then
    -- array?
    local is_arr = true
    local n = 0
    for k,_ in pairs(v) do
      if type(k) ~= "number" then is_arr = false break end
      if k > n then n = k end
    end
    if is_arr then
      local out = {}
      for i=1,n do out[#out+1] = _json_encode(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    else
      local out = {}
      for k,val in pairs(v) do
        out[#out+1] = "\"" .. _json_escape(k) .. "\":" .. _json_encode(val)
      end
      return "{" .. table.concat(out, ",") .. "}"
    end
  else
    return "\"" .. _json_escape(tostring(v)) .. "\""
  end
end

local function _settings_snapshot()
  return {
    sysex_delay_ms = CAPTURE_CFG and CAPTURE_CFG.sysex_delay_ms or nil,
    bulk_delay_ms  = CAPTURE_CFG and CAPTURE_CFG.bulk_delay_ms or nil,
    retry_instvoice = CAPTURE_CFG and CAPTURE_CFG.retry_count_instvoice or nil,
    retry_config    = CAPTURE_CFG and CAPTURE_CFG.retry_count_config or nil,
    retry_bank      = CAPTURE_CFG and CAPTURE_CFG.retry_count_bank or nil,
    native_strict   = CAPTURE_CFG and CAPTURE_CFG.native_strict_checksum or nil,
    native_two_bytecount = CAPTURE_CFG and CAPTURE_CFG.native_bytecount_two or nil,
    native_chunk_source_bytes = CAPTURE_CFG and CAPTURE_CFG.native_chunk_source_bytes or nil,
  }
end

local function _format_param_diffs_txt(kind, diffs, meta)
  -- Phase 11.4: export param diff report (JSON/TXT) when available
  if VERIFY and VERIFY.result and VERIFY.result.param_diffs and #VERIFY.result.param_diffs > 0 then
    if r.ImGui_Button(ctx, "Export Param Diff Report (JSON+TXT)", 320, 0) then
      local ok, err, base = _export_param_diff_report(VERIFY.kind or "verify", VERIFY.result.param_diffs, {
        backend = VERIFY.result.backend,
        settings = _settings_snapshot(),
      })
      if ok then
        r.MB("Exported to:\n" .. tostring(base) .. ".json\n" .. tostring(base) .. ".txt", "Export OK", 0)
      else
        r.MB("Export failed: " .. tostring(err), "Export Error", 0)
      end
    end
  end

  local lines = {}
  lines[#lines+1] = "IFLS FB-01 Verify Param Diff Report"
  lines[#lines+1] = "kind: " .. tostring(kind)
  lines[#lines+1] = "timestamp: " .. tostring(meta and meta.timestamp or os.date("%Y-%m-%d %H:%M:%S"))
  lines[#lines+1] = "backend: " .. tostring(meta and meta.backend or "")
  lines[#lines+1] = ""
  if meta and meta.settings then
    lines[#lines+1] = "settings:"
    for k,v in pairs(meta.settings) do
      lines[#lines+1] = "  - " .. tostring(k) .. ": " .. tostring(v)
    end
    lines[#lines+1] = ""
  end
  for i=1,(diffs and #diffs or 0) do
    local d = diffs[i]
    lines[#lines+1] = string.format("%s: %s -> %s",
      tostring(d.path or d.label or ("diff"..i)),
      tostring(d.a), tostring(d.b))
  end
  return table.concat(lines, "\n")
end

local function _export_param_diff_report(kind, diffs, meta)
  local dir = _get_project_dir() .. "/IFLS_FB01_Reports"
  _ensure_dir(dir)
  local ts = os.date("%Y%m%d_%H%M%S")
  local base = dir .. "/IFLS_FB01_ParamDiff_" .. tostring(kind or "verify") .. "_" .. ts
  local payload = {
    kind = kind,
    timestamp = meta and meta.timestamp or os.date("%Y-%m-%d %H:%M:%S"),
    backend = meta and meta.backend or nil,
    settings = (meta and meta.settings) or _settings_snapshot(),
    diffs = diffs or {},
  }
  local ok1, e1 = _write_text_file(base .. ".json", _json_encode(payload))
  local ok2, e2 = _write_text_file(base .. ".txt", _format_param_diffs_txt(kind, diffs, payload))
  return ok1 and ok2, (not ok1 and e1) or (not ok2 and e2) or nil, base
end

-- Phase 11.3: Schema-driven UI helpers (fallback-safe)
local SchemaUI = {}

function SchemaUI.slider_int(ctx, label, value, path, fallback_min, fallback_max, fmt)
  local def = Schema and Schema.get and Schema.get(path) or nil
  local mn = (def and def.min) or fallback_min or 0
  local mx = (def and def.max) or fallback_max or 127
  local changed, v = r.ImGui_SliderInt(ctx, label, value or 0, mn, mx, fmt)
  return changed, v, def
end

function SchemaUI.slider_double(ctx, label, value, path, fallback_min, fallback_max, fmt)
  local def = Schema and Schema.get and Schema.get(path) or nil
  local mn = (def and def.min) or fallback_min or 0.0
  local mx = (def and def.max) or fallback_max or 1.0
  local changed, v = r.ImGui_SliderDouble(ctx, label, value or 0.0, mn, mx, fmt or "%.3f")
  return changed, v, def
end

function SchemaUI.combo_enum(ctx, label, value, path, fallback_items)
  local def = Schema and Schema.get and Schema.get(path) or nil
  local items = (def and def.enum_items) or fallback_items
  if not items then
    return r.ImGui_InputInt(ctx, label, value or 0)
  end
  local cur = value or 0
  local preview = items[cur+1] or tostring(cur)
  if r.ImGui_BeginCombo(ctx, label, preview) then
    for i=1,#items do
      local sel = (cur == (i-1))
      if r.ImGui_Selectable(ctx, items[i], sel) then cur = i-1 end
      if sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  return true, cur, def
end

  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Phase 8: Transport robustness / presets")
  local _ch
  _ch, CAPTURE_CFG.sysex_delay_ms = r.ImGui_SliderInt(ctx, "Sysex send delay (ms)", CAPTURE_CFG.sysex_delay_ms or 10, 0, 500)
  if _ch then _ext_set("sysex_delay_ms", tostring(CAPTURE_CFG.sysex_delay_ms)) end

  local function _cleanup_combo(label, val)
    local items = "Use global\0Keep\0Delete\0Archive\0\0"
    local v = (val or -1) + 1
    local changed; changed, v = r.ImGui_Combo(ctx, label, v, items)
    if changed then return v-1 end
    return val
  end

  CAPTURE_CFG.cleanup_instvoice = _cleanup_combo("Cleanup InstVoice", CAPTURE_CFG.cleanup_instvoice)
  _ext_set("capture_cleanup_instvoice", tostring(CAPTURE_CFG.cleanup_instvoice))
  CAPTURE_CFG.cleanup_config    = _cleanup_combo("Cleanup Config", CAPTURE_CFG.cleanup_config)
  _ext_set("capture_cleanup_config", tostring(CAPTURE_CFG.cleanup_config))
  CAPTURE_CFG.cleanup_bank      = _cleanup_combo("Cleanup Bank", CAPTURE_CFG.cleanup_bank)
  _ext_set("capture_cleanup_bank", tostring(CAPTURE_CFG.cleanup_bank))

  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Mapping presets (project folder / IFLS_FB01_Presets)")
  _ch, preset_name = r.ImGui_InputText(ctx, "Preset name", preset_name or "default")
  if r.ImGui_Button(ctx, "Save mapping preset", 180, 0) then
    local preset = {
      version = 1,
      created = os.date("%Y-%m-%d %H:%M:%S"),
      mapping = mapping_table or {},
      verify_each = verify_each_voice or false,
      delay_ms = CAPTURE_CFG.sysex_delay_ms or 0,
    }
    local ok, err, path = _save_mapping_preset(preset_name, preset)
    if ok then r.ShowConsoleMsg("Saved preset: "..path.."\n") else r.MB("Save failed: "..tostring(err), "Preset", 0) end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Load mapping preset", 180, 0) then
    local t, err, path = _load_mapping_preset(preset_name)
    if t then
      mapping_table = t.mapping or mapping_table
      verify_each_voice = t.verify_each or verify_each_voice
      if t.delay_ms then CAPTURE_CFG.sysex_delay_ms = tonumber(t.delay_ms) or CAPTURE_CFG.sysex_delay_ms end
      r.ShowConsoleMsg("Loaded preset: "..path.."\n")
    else
      r.MB("Load failed: "..tostring(err), "Preset", 0)
    end
  end

-- =========================
-- Phase 7: report export / drilldown / mapping send
-- =========================
local function _safe_write_file(path, content)
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  f:write(content or "")
  f:close()
  return true
end

local function _json_escape(s)
  s = tostring(s or "")
  s = s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\r","\\r"):gsub("\n","\\n")
  return s
end

local function _to_json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "number" then return tostring(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t == "string" then return '"'.._json_escape(v)..'"' end
  if t == "table" then
    local is_arr = true
    local n = 0
    for k,_ in pairs(v) do
      if type(k) ~= "number" then is_arr=false; break end
      if k > n then n = k end
    end
    if is_arr then
      local out = {}
      for i=1,n do out[#out+1] = _to_json(v[i]) end
      return "["..table.concat(out,",").."]"
    else
      local out = {}
      for k,val in pairs(v) do
        out[#out+1] = '"'.._json_escape(k)..'":'.._to_json(val)
      end
      return "{"..table.concat(out,",").."}"
    end
  end
  return '"'.._json_escape(tostring(v))..'"'
end

local function _project_dir()
  local p = reaper.GetProjectPath("") or ""
  if p == "" then p = reaper.GetResourcePath() end
  return p
end

local function _export_bank_verify_report_csv(rep)
  if not rep then return false, "no report" end
  local p = _project_dir() .. "/IFLS_FB01_BankVerifyReport_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
  local lines = {}
  lines[#lines+1] = "voice_index,diff_bytes,positions"
  local voices = rep.voices or {}
  for i=1,#voices do
    local v = voices[i]
    local pos = ""
    if v.positions and #v.positions > 0 then pos = table.concat(v.positions, " ") end
    lines[#lines+1] = string.format("%d,%d,%s", (v.voice_index or (i-1)), (v.diff_bytes or 0), pos)
  end
  return _safe_write_file(p, table.concat(lines, "\n")), p
end

local function _export_bank_verify_report_json(rep)
  if not rep then return false, "no report" end
  local p = _project_dir() .. "/IFLS_FB01_BankVerifyReport_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
  local ok, err = _safe_write_file(p, _to_json(rep))
  return ok, (ok and p or err)
end

local function _sorted_keys(t)
  local ks = {}
  for k,_ in pairs(t or {}) do ks[#ks+1]=k end
  table.sort(ks, function(a,b) return tostring(a) < tostring(b) end)
  return ks
end

local function 
local function _structured_param_diff_lines(a64, b64)
  local a_voice, a_ops = VoiceMap.decode_voice_block(a64)
  local b_voice, b_ops = VoiceMap.decode_voice_block(b64)
  local lines = {}
  local function cmp_table(prefix, ta, tb)
    for k,va in pairs(ta or {}) do
      local vb = (tb or {})[k]
      if vb ~= va then
        lines[#lines+1] = ("%s%s: %s -> %s"):format(prefix, tostring(k), tostring(va), tostring(vb))
      end
    end
    for k,vb in pairs(tb or {}) do
      if (ta or {})[k] == nil then
        lines[#lines+1] = ("%s%s: (nil) -> %s"):format(prefix, tostring(k), tostring(vb))
      end
    end
  end
  cmp_table("voice.", a_voice, b_voice)
  for i=1,4 do
    cmp_table(("op%d."):format(i), a_ops[i] or {}, b_ops[i] or {})
  end
  table.sort(lines)
  return lines
end
_diff_structured_voice(a64, b64)
  if not VoiceMap or not VoiceMap.decode_voice_block then return nil end
  local va, oa = VoiceMap.decode_voice_block(a64)
  local vb, ob = VoiceMap.decode_voice_block(b64)
  if not va or not vb then return nil end
  local diffs = {}
  for _,k in ipairs(_sorted_keys(va)) do
    if va[k] ~= vb[k] then diffs[#diffs+1] = { path="voice."..tostring(k), a=va[k], b=vb[k] } end
  end
  for op=1,4 do
    local oa1, ob1 = oa and oa[op], ob and ob[op]
    if oa1 and ob1 then
      for _,k in ipairs(_sorted_keys(oa1)) do
        if oa1[k] ~= ob1[k] then diffs[#diffs+1] = { path="op"..op.."."..tostring(k), a=oa1[k], b=ob1[k] } end
      end
    end
  end
  return diffs
end

local function bytes_to_string(t)
  return string.char(table.unpack(t))
end

local r = reaper

local root = r.GetResourcePath() .. "/Scripts/IFLS FB-01 Editor"
local BUNDLED_ARCHIVES_DIR = root .. "/Library/Archives"

-- Forward declarations for modules (assigned later)
local Syx
local Rx
local VoiceDump
local VoiceMap
local ParamSchema
local VoiceSpec
local BankA
local VoiceBank
local SlotCore

-- =========================
-- Phase 2.5: Verify State Machine (instvoice/config)
-- =========================

-- Phase 12: Library / Patch archive indexing
local LIBRARY = {
  -- Phase 34: live queue from current results
  queue_auto_rebuild = true,
  queue_last_sig = "",
  queue_wrap = true,
  -- Phase 33: Queue from current results + Send+Verify pipeline
  queue_list = nil,
  queue_pos = 0,
  -- Phase 31: Auto-audition + A/B diff
  auto_audition = false,
  auto_audition_ms = 350,
  last_auto_audition_t = 0,
  ab_diff = nil,

  -- Phase 30: Audition A/B buffers
  auditionA = nil,
  auditionB = nil,
  last_send_ts = "",
  search = "",
  tags = nil,
  tag_edit = "",
  auto_export_reports = false,
  tag_filter = "",
  selected_set = {},
  bulk_tag_edit = "",
  cache = nil,

  batch_map = nil,

-- =========================
-- PHASE 20 STABILITY: Real-time pacing (time_precise), multipart bank dump assist, compare progress, per-interface profiles
-- =========================
local function _now() return (r.time_precise and r.time_precise()) or os.clock() end

local function _profiles_path()
  return _lib_db_dir() .. "/midi_interface_profiles.json"
end

local function _profiles_load()
  local f = io.open(_profiles_path(), "rb")
  if not f then return {} end
  local s = f:read("*all"); f:close()
  if not s or s=="" then return {} end
  local t = {}
  for name, body in s:gmatch('"%s*([^"]+)%s*"%s*:%s*(%b{})') do
    local p = {}
    p.bulk_delay_ms = tonumber(body:match('"%s*bulk_delay_ms%s*"%s*:%s*(%d+)') or "") or nil
    p.retry_count   = tonumber(body:match('"%s*retry_count%s*"%s*:%s*(%d+)') or "") or nil
    p.capture_timeout_voice = tonumber(body:match('"%s*capture_timeout_voice%s*"%s*:%s*(%d+)') or "") or nil
    p.capture_timeout_bank  = tonumber(body:match('"%s*capture_timeout_bank%s*"%s*:%s*(%d+)') or "") or nil
    p.chunk = tonumber(body:match('"%s*chunk%s*"%s*:%s*(%d+)') or "") or nil
    t[name] = p
  end
  return t
end

local function _profiles_save(t)
  local f = io.open(_profiles_path(), "wb"); if not f then return false end
  f:write("{\n")
  local first = true
  for name,p in pairs(t or {}) do
    if not first then f:write(",\n") end
    first = false
    local n = tostring(name):gsub("\\","\\\\"):gsub('"','\\"')
    f:write(('  "%s": { "bulk_delay_ms":%s, "retry_count":%s, "capture_timeout_voice":%s, "capture_timeout_bank":%s, "chunk":%s }'):format(
      n,
      tostring(p.bulk_delay_ms or "null"),
      tostring(p.retry_count or "null"),
      tostring(p.capture_timeout_voice or "null"),
      tostring(p.capture_timeout_bank or "null"),
      tostring(p.chunk or "null")
    ))
  end
  f:write("\n}\n"); f:close()
  return true
end

local function _current_interface_key()
  -- Best effort: use preferred MIDI input name if available, else "default"
  local key = "default"
  if CAPTURE_CFG and CAPTURE_CFG.preferred_midi_in_name and CAPTURE_CFG.preferred_midi_in_name ~= "" then
    key = CAPTURE_CFG.preferred_midi_in_name
  elseif CAPTURE_CFG and CAPTURE_CFG.preferred_midi_in and tonumber(CAPTURE_CFG.preferred_midi_in) then
    key = "midi_in_" .. tostring(CAPTURE_CFG.preferred_midi_in)
  end
  return key
end

local function _apply_profile(p)
  if not p then return end
  if p.bulk_delay_ms then CAPTURE_CFG.bulk_delay_ms = p.bulk_delay_ms end
  if p.retry_count then CAPTURE_CFG.retry_count = p.retry_count end
  if p.capture_timeout_voice then CAPTURE_CFG.capture_timeout_voice_ms = p.capture_timeout_voice end
  if p.capture_timeout_bank then CAPTURE_CFG.capture_timeout_bank_ms = p.capture_timeout_bank end
  if p.chunk then LIBRARY.export_bank_chunk = p.chunk end
end

local function _maybe_reassemble_bank_dump()
  -- If bank dump capture produced multiple chunks, try to rebuild from cached msgs if available.
  -- This is intentionally best-effort to avoid breaking existing flow.
  if _maybe_reassemble_bank_dump() then -- Phase 20: multipart assist
       return true end
  if last_rx_voicebank_msgs and type(last_rx_voicebank_msgs) == "table" then
    local cat = _sysex_msgs_concat(_midi_reassemble_sysex_packets(last_rx_voicebank_msgs))
    local bank = _decode_bank_any_from_bytes(cat)
    if bank and bank.voices and #bank.voices == 48 then
      last_rx_voicebank = bank
      return true
    end
  end
  return false
end
-- =========================
-- PHASE 19 ROUNDTRIP: Exportâ†’Sendâ†’Dumpâ†’Compare for Bank, ROM-safety, Write-to-instrument workflow
-- =========================
local function _is_rom_bank(bank_no)
  -- Practical safety default: treat 1..2 as writable (RAM), 3..7 as ROM
  -- (can be made configurable later)
  return (bank_no or 0) >= 3
end

local function _roundtrip_state_reset()
  ROUNDTRIP = {
    active = false,
    stage = "idle",
    mode = "current",
    export_path = nil,
    bank_no = 1,
    inst_no = 0,
    verify = true,
    error = nil,
    started_ts = os.time(),
    expected_bank = nil,
  }
end

_roundtrip_state_reset()

local function _roundtrip_start(mode)
  _roundtrip_state_reset()
  ROUNDTRIP.active = true
  ROUNDTRIP.stage = "export"
  ROUNDTRIP.mode = mode or "current"
  ROUNDTRIP.bank_no = tonumber(LIBRARY.export_bank_no or 1) or 1
  ROUNDTRIP.inst_no = tonumber(LIBRARY.roundtrip_inst_no or 0) or 0
  ROUNDTRIP.verify = (LIBRARY.roundtrip_verify ~= false)
end

local function _roundtrip_tick()
  if not ROUNDTRIP.active then return end

  if ROUNDTRIP.stage == "export" then
    local ok, msg = _export_bank_bulk_syx(ROUNDTRIP.mode)
    if not ok then
      ROUNDTRIP.error = msg
      ROUNDTRIP.stage = "error"
      return
    end
    ROUNDTRIP.export_path = msg
    -- also keep expected bank voices in memory for compare
    local voices, err = _build_bank_voices_from_mode(ROUNDTRIP.mode)
    if not voices then
      ROUNDTRIP.error = err
      ROUNDTRIP.stage = "error"
      return
    end
    ROUNDTRIP.expected_bank = { voices = voices }
    ROUNDTRIP.stage = "send_bank"
    return
  end

  if ROUNDTRIP.stage == "send_bank" then
    -- Safety: warn/abort ROM banks unless override enabled
    local bno = ROUNDTRIP.bank_no
    if _is_rom_bank(bno) and not LIBRARY.allow_rom_bank_write then
      ROUNDTRIP.error = "Refusing to write ROM bank " .. tostring(bno) .. " (enable override to proceed)."
      ROUNDTRIP.stage = "error"
      return
    end
    -- Send bank bulk to instrument (native bulk), throttled by existing bulk delay.
    if not (BulkNative and BulkNative.build_bank_bulk) then
      ROUNDTRIP.error = "BulkNative.build_bank_bulk unavailable"
      ROUNDTRIP.stage = "error"
      return
    end
    local sys_ch = (CAPTURE_CFG and CAPTURE_CFG.sys_ch) or 0
    local chunk = tonumber(LIBRARY.export_bank_chunk or 48) or 48
    local opts = {
      strict_checksum = (LIBRARY.export_bank_strict_checksum == true),
      bytecount_two_bytes = (LIBRARY.export_bank_bytecount2 == true),
      checksum_from_body_index = (LIBRARY.export_bank_cs_from or 4),
    }
    local msgs, berr = BulkNative.build_bank_bulk(sys_ch, bno, ROUNDTRIP.expected_bank.voices, chunk, opts)
    if not msgs then
      ROUNDTRIP.error = berr
      ROUNDTRIP.stage = "error"
      return
    end
    -- enqueue all messages for send with bulk delay
    roundtrip_send_msgs = { msgs = msgs, i = 1, started = os.time(), next_send_time = _now() }
    ROUNDTRIP.stage = "sending_msgs"
    return
  end

  if ROUNDTRIP.stage == "sending_msgs" then
    if not roundtrip_send_msgs or not roundtrip_send_msgs.msgs then
      ROUNDTRIP.error = "internal send queue missing"
      ROUNDTRIP.stage = "error"
      return
    end
    -- Send one message per tick using existing throttled send helper if available; else raw send
    local i = roundtrip_send_msgs.i
    local now = _now()
    local nxt = roundtrip_send_msgs.next_send_time or now
    if now < nxt then return end

    if i > #roundtrip_send_msgs.msgs then
      ROUNDTRIP.stage = "dump_bank"
      roundtrip_send_msgs = nil
      return
    end
    local m = roundtrip_send_msgs.msgs[i]
    local bin = _bytes_to_bin(m)
    if Send and Send.send_sysex_string then
      Send.send_sysex_string(bin)
    elseif r.StuffMIDIMessage then
      -- fallback: send bytes as sysex via StuffMIDIMessage if your code supports it
      -- (kept as fallback; preferred is existing Send module)
      -- no-op here to avoid breaking unknown env
    end
    roundtrip_send_msgs.i = i + 1
    local delay = tonumber(CAPTURE_CFG and CAPTURE_CFG.bulk_delay_ms) or 120
    roundtrip_send_msgs.next_send_time = _now() + (delay / 1000.0)

    -- throttle: use bulk delay
    local delay = tonumber(CAPTURE_CFG and CAPTURE_CFG.bulk_delay_ms) or 120
    r.defer(function() end) -- keep UI alive; timing handled by tick cadence + delay in existing loops
    return
  end

  if ROUNDTRIP.stage == "dump_bank" then
    -- request bank dump and capture/verify using existing pipeline
    -- We reuse existing "dump_voice_bank" workflow in your editor (Phase 5+)
    if dump_voice_bank then
      dump_voice_bank(ROUNDTRIP.bank_no)
      ROUNDTRIP.stage = "waiting_dump"
      ROUNDTRIP.wait_started = os.time()
      return
    else
      ROUNDTRIP.error = "dump_voice_bank() not found"
      ROUNDTRIP.stage = "error"
      return
    end
  end

  if ROUNDTRIP.stage == "waiting_dump" then
    -- Wait until last_rx_voicebank is populated
    if _maybe_reassemble_bank_dump() then -- Phase 20: multipart assist
      
      ROUNDTRIP.stage = "compare"
      return
    end
    local timeout = tonumber(LIBRARY.roundtrip_timeout_s or 20) or 20
    if os.time() - (ROUNDTRIP.wait_started or os.time()) > timeout then
      ROUNDTRIP.error = "timeout waiting for bank dump"
      ROUNDTRIP.stage = "error"
    end
    return
  end

  if ROUNDTRIP.stage == "compare" then
    -- structured diff via Schema/VoiceMap if available
    local diffs = {}
    local maxv = tonumber(LIBRARY.roundtrip_max_voices or 8) or 8
    if LIBRARY.roundtrip_compare_all then maxv = 48 end
    ROUNDTRIP.progress = 0
    for vi=1,math.min(48, maxv) do
      ROUNDTRIP.progress = (vi / math.min(48, maxv))
      local a = ROUNDTRIP.expected_bank.voices[vi]
      local b = last_rx_voicebank.voices[vi]
      if a and b and #a == #b then
        local same = true
        for k=1,#a do if a[k] ~= b[k] then same=false; break end end
        if not same then
          if Schema and Schema.diff_structured and VoiceMap and VoiceMap.decode_voice_block then
            local av, aop = VoiceMap.decode_voice_block(a)
            local bv, bop = VoiceMap.decode_voice_block(b)
            local pd = Schema.diff_structured(av, bv, aop, bop, ("bank.voice%02d."):format(vi))
            for _,d in ipairs(pd or {}) do diffs[#diffs+1]=d end
          else
            diffs[#diffs+1] = { path=("bank.voice%02d.bytes"):format(vi), a="(bytes)", b="(bytes)" }
          end
        end
      end
    end
    ROUNDTRIP.diffs = diffs
    ROUNDTRIP.stage = "done"
    -- export report if requested
    if (LIBRARY.roundtrip_auto_export ~= false) and _export_param_diff_report and diffs and #diffs>0 then
      _export_param_diff_report("roundtrip_bank", diffs, { bank_no=ROUNDTRIP.bank_no, export_path=ROUNDTRIP.export_path, ts=os.time() })
    end
    return
  end
end
-- =========================
-- PHASE 18 BANK EXPORT: Export selected/current as Bank Bulk SYX + Index incremental build via cache
-- =========================
local function _bytes_to_bin(bytes)
  local s = {}
  for i=1,#bytes do s[i] = string.char(bytes[i] & 0xFF) end
  return table.concat(s)
end

local function _write_syx_file(path, msgs)
  local f = io.open(path, "wb")
  if not f then return false, "open failed" end
  if type(msgs) == "string" then
    f:write(msgs)
  else
    for _,m in ipairs(msgs or {}) do
      f:write(_bytes_to_bin(m))
    end
  end
  f:close()
  return true
end

local function _build_bank_voices_from_mode(mode)
  -- mode: "current" => current bank as-is
  -- mode: "pack_selected" => selected voices packed into 1..N, rest filled from current bank
  -- mode: "overlay_selected" => selected voices overwrite their indices, rest current bank
  if not (LIBRARY.bank and LIBRARY.bank.voices and #LIBRARY.bank.voices == 48) then
    return nil, "No active bank loaded (need 48 voices)"
  end
  local out = {}
  for i=1,48 do out[i] = LIBRARY.bank.voices[i] end
  if mode == "current" then
    return out
  end
  local sel = {}
  for k,_ in pairs(LIBRARY.selected_set or {}) do
    local _,_,vi = _lib_parse_selected_key(k)
    if vi and vi>=1 and vi<=48 then sel[#sel+1]=vi end
  end
  table.sort(sel)
  if #sel == 0 then return out end

  if mode == "overlay_selected" then
    for _,vi in ipairs(sel) do out[vi] = LIBRARY.bank.voices[vi] end
    return out
  end

  if mode == "pack_selected" then
    local pos = 1
    for _,vi in ipairs(sel) do
      out[pos] = LIBRARY.bank.voices[vi]
      pos = pos + 1
      if pos > 48 then break end
    end
    return out
  end

  return out
end

local function _export_bank_bulk_syx(mode)
  if not (BulkNative and BulkNative.build_bank_bulk) then
    return false, "BulkNative.build_bank_bulk not available"
  end
  local voices, err = _build_bank_voices_from_mode(mode)
  if not voices then return false, err end

  local sys_ch = (CAPTURE_CFG and CAPTURE_CFG.sys_ch) or 0
  local bank_no = tonumber(LIBRARY.export_bank_no or 1) or 1
  local chunk = tonumber(LIBRARY.export_bank_chunk or 48) or 48

  local opts = {
    strict_checksum = (LIBRARY.export_bank_strict_checksum == true),
    bytecount_two_bytes = (LIBRARY.export_bank_bytecount2 == true),
    checksum_from_body_index = (LIBRARY.export_bank_cs_from or 4),
  }

  local msgs, berr = BulkNative.build_bank_bulk(sys_ch, bank_no, voices, chunk, opts)
  if not msgs then return false, berr end

  local ts = os.date("%Y%m%d_%H%M%S")
  local dir = _lib_exports_dir() .. "/BankExport_" .. ts
  r.RecursiveCreateDirectory(dir, 0)
  local name = (mode == "current" and "bank_current") or (mode == "pack_selected" and "bank_pack_selected") or "bank_overlay_selected"
  local path = dir .. ("/FB01_%s_bank%02d.syx"):format(name, bank_no)
  local ok, werr = _write_syx_file(path, msgs)
  if not ok then return false, werr end
  return true, path
end

-- =========================
-- PHASE 27 CONFIG MULTI: Multi-instrument tabs + write safety + config randomizer + cfg_* canonical mapping
-- =========================
local function _cfg_defaults()
  return { cfg_midi_channel=1, cfg_key_low=0, cfg_key_high=127, cfg_bank_no=1, cfg_voice_no=1, cfg_level=100, cfg_pan=64, cfg_detune=0, cfg_octave=2 }
end

local function _cfg_randomize(decoded, mode)
  -- mode: "spread" creates a musically sensible multi with pan/levels, split/layer basic
  decoded = decoded or { instruments = {} }
  decoded.instruments = decoded.instruments or {}
  local base_ch = math.random(1,16)
  for inst=0,7 do
    local t = decoded.instruments[inst] or _cfg_defaults()
    if mode == "spread" then
      t.cfg_midi_channel = base_ch
      t.cfg_level = math.random(70, 110)
      t.cfg_pan = math.max(0, math.min(127, 64 + math.floor((inst-3.5)*14) + math.random(-6,6)))
      t.cfg_key_low = 0
      t.cfg_key_high = 127
      t.cfg_bank_no = math.random(1,2)
      t.cfg_voice_no = math.random(1,48)
      t.cfg_detune = math.random(0,6)
      t.cfg_octave = math.random(1,3)
      t.cfg_lfo_speed = math.random(0,90)
      t.cfg_amd = math.random(0,70)
      t.cfg_pmd = math.random(0,70)
      t.cfg_lfo_wave = math.random(0,3)
      t.cfg_lfo_load = math.random(0,1)
      t.cfg_lfo_sync = math.random(0,1)
      t.cfg_ams = math.random(0,3)
      t.cfg_pms = math.random(0,5)
    elseif mode == "split" then
      t.cfg_midi_channel = base_ch
      t.cfg_level = math.random(80, 110)
      t.cfg_pan = 64 + math.random(-20,20)
      local split = 60
      if inst < 4 then
        t.cfg_key_low = 0; t.cfg_key_high = split
      else
        t.cfg_key_low = split+1; t.cfg_key_high = 127
      end
      t.cfg_bank_no = math.random(1,2)
      t.cfg_voice_no = math.random(1,48)
    end
    decoded.instruments[inst] = t
  end
  return decoded
end
-- =========================
-- PHASE 24 ROUTING: Hardware MIDI Out auto-set (best-effort) + Schema-driven Config UI scaffold
-- =========================
local function _set_track_hw_midi_out(track, midi_out_idx)
  -- Phase 28: Use documented encoding for I_MIDIHWOUT: low 5 bits = channel (0=all, 1-16), next 5 bits = device index (0-31)
  -- Source: Ultraschall / ReaScript docs
  if not track then return false end
  midi_out_idx = tonumber(midi_out_idx)
  if not midi_out_idx or midi_out_idx < 0 then return false end
  local chan = 0 -- all
  local val = (midi_out_idx << 5) | (chan & 0x1F)
  r.SetMediaTrackInfo_Value(track, "I_MIDIHWOUT", val)
  return true
end

local function _ensure_capture_track_and_route()
  local tr = _lib_hw_route_setup()
  if CAPTURE_CFG and CAPTURE_CFG.preferred_midi_out and CAPTURE_CFG.preferred_midi_out >= 0 then
    _set_track_hw_midi_out(tr, CAPTURE_CFG.preferred_midi_out)
  end
  return tr
end

-- =========================
-- PHASE 30 TOOLTIP + AUDITION: Schema tooltips + A/B voice audition + algo debug
-- =========================
local function _maybe_tooltip(key)
  if not (Schema and Schema.DESC and Schema.DESC[key]) then return end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_Text(ctx, tostring(Schema.DESC[key]))
    r.ImGui_EndTooltip(ctx)
  end
end

local function _schema_draw_group(ctx, t, prefix, group)
  -- Draw sliders for keys in Schema.PARAMS that match group and exist in table t (or create)
  if not (Schema and Schema.PARAMS) then return end
  local keys = {}
  for k,p in pairs(Schema.PARAMS) do
    if p.group == group then keys[#keys+1] = k end
  end
  table.sort(keys)
  for _,k in ipairs(keys) do
    local p = Schema.PARAMS[k]
    local cur = tonumber(t[k] or (p.safe_min or p.min or 0)) or 0
    local changed
    changed, cur = r.ImGui_SliderInt(ctx, prefix .. k, cur, p.min or 0, p.max or 127)
    -- PHASE 30 tooltip hook
    -- Phase 35: log change baseline (optional)
    _maybe_tooltip(k)
    if changed then t[k] = cur end
  end
end
-- =========================
-- PHASE 23 USER META: Favorites/Rating/Recent + Hardware routing helper
-- =========================
local function _lib_user_meta_path() return _lib_db_dir() .. "/library_user_meta.json" end

local function _lib_load_user_meta()
  local f = io.open(_lib_user_meta_path(), "rb")
  if not f then return { fav={}, rating={}, recent={} } end
  local s = f:read("*all"); f:close()
  if not s or s=="" then return { fav={}, rating={}, recent={} } end
  local fav, rating, recent = {}, {}, {}
  for k,v in s:gmatch('"%s*fav%:%s*([^"]+)%s*"') do end -- noop
  for key in s:gmatch('"fav"%s*:%s*(%b{})') do
    for k in key:gmatch('"([^"]+)"') do fav[k]=true end
  end
  local rbody = s:match('"rating"%s*:%s*(%b{})')
  if rbody then
    for k,v in rbody:gmatch('"%s*([^"]+)%s*"%s*:%s*(%d+)') do rating[k]=tonumber(v) end
  end
  local rec = s:match('"recent"%s*:%s*(%b%[%])')
  if rec then
    for k in rec:gmatch('"([^"]-)"') do recent[#recent+1]=k end
  end
  return { fav=fav, rating=rating, recent=recent }
end

local function _lib_save_user_meta(meta)
  meta = meta or { fav={}, rating={}, recent={} }
  local f = io.open(_lib_user_meta_path(), "wb"); if not f then return false end
  f:write("{\n  \"fav\":{")
  local first = true
  for k,_ in pairs(meta.fav or {}) do
    if not first then f:write(",") end
    first = false
    local ks = tostring(k):gsub("\\","\\\\"):gsub('"','\\"')
    f:write(('"%s":1'):format(ks))
  end
  f:write("},\n  \"rating\":{")
  first = true
  for k,v in pairs(meta.rating or {}) do
    if not first then f:write(",") end
    first = false
    local ks = tostring(k):gsub("\\","\\\\"):gsub('"','\\"')
    f:write(('"%s":%d'):format(ks, tonumber(v) or 0))
  end
  f:write("},\n  \"recent\":[")
  first = true
  for _,k in ipairs(meta.recent or {}) do
    if not first then f:write(",") end
    first = false
    local ks = tostring(k):gsub("\\","\\\\"):gsub('"','\\"')
    f:write(('"%s"'):format(ks))
  end
  f:write("]\n}\n"); f:close()
  return true
end

local function _lib_recent_push(meta, key)
  meta.recent = meta.recent or {}
  -- remove existing
  local out = {}
  for _,k in ipairs(meta.recent) do if k ~= key then out[#out+1]=k end end
  out[#out+1] = key
  while #out > 30 do table.remove(out, 1) end
  meta.recent = out
end

local function _lib_hw_route_setup()
  -- Best-effort: ensure a track exists named "FB01 Capture" and has MIDI hardware output set.
  -- Note: REAPER's API for setting hardware MIDI output is limited; we store chosen output and show guidance.
  local tr = nil
  local n = r.CountTracks(0)
  for i=0,n-1 do
    local t = r.GetTrack(0,i)
    local _, name = r.GetTrackName(t, "")
    if name == "FB01 Capture" then tr = t break end
  end
  if not tr then
    r.InsertTrackAtIndex(n, true)
    tr = r.GetTrack(0,n)
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", "FB01 Capture", true)
  end
  -- Arm + monitor
  r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  r.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
  -- Input should be MIDI all channels on preferred input; REAPER encodes this in I_RECINPUT.
  if CAPTURE_CFG and CAPTURE_CFG.preferred_midi_in and tonumber(CAPTURE_CFG.preferred_midi_in) and CAPTURE_CFG.preferred_midi_in >= 0 then
    local dev = CAPTURE_CFG.preferred_midi_in
    -- MIDI input encoding: 4096 + dev*32 + 0 (all channels) [best-effort]
    local recinp = 4096 + (dev * 32)
    r.SetMediaTrackInfo_Value(tr, "I_RECINPUT", recinp)
  end
  -- Recording mode: MIDI output? Keep normal record
  return tr
end
-- =========================
-- PHASE 17 FULL LIBRARIAN: Global Index Search, Batch Verify Selected, Preset Pack Export
-- =========================
local function _lib_full_index_path() return _lib_db_dir() .. "/library_full_index.json" end
local function _lib_exports_dir()
  local d = _lib_db_dir() .. "/Exports"
  r.RecursiveCreateDirectory(d, 0)
  return d
end

local function _json_escape(s)
  return tostring(s):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")
end

local function _lib_save_full_index(idx)
  local f = io.open(_lib_full_index_path(), "wb"); if not f then return false end
  f:write("{\"version\":1,\"items\":[\n")
  local first = true
  for _,it in ipairs(idx.items or {}) do
    if not first then f:write(",\n") end
    first = false
    f:write(("{\"source\":\"%s\",\"file\":\"%s\",\"voice\":%d,\"name\":\"%s\",\"tags\":\"%s\"}"):format(
      _json_escape(it.source or ""), _json_escape(it.file or ""), tonumber(it.voice or 0),
      _json_escape(it.name or ""), _json_escape(it.tags or "")
    ))
  end
  f:write("\n]}\n"); f:close()
  return true
end

local function _lib_load_full_index()
  local f = io.open(_lib_full_index_path(), "rb"); if not f then return {items={}} end
  local s = f:read("*all"); f:close()
  if not s or s=="" then return {items={}} end
  local items = {}
  for src, file, voice, name, tags in s:gmatch('{"source":"([^"]*)","file":"([^"]*)","voice":(%d+),"name":"([^"]*)","tags":"([^"]*)"}') do
    items[#items+1] = { source=src, file=file, voice=tonumber(voice), name=name, tags=tags }
  end
  return { items = items }
end

local function _lib_build_full_index()
  local idx = { items = {} }
  local function add_item(source_name, file_path, voice_i, name, tags)
    idx.items[#idx.items+1] = {
      source = source_name,
      file = file_path,
      voice = voice_i,
      name = name or "",
      tags = tags or ""
    }
  end

  -- bundled archives
  local base = BUNDLED_ARCHIVES_DIR
  local i = 0
  while true do
    local sub = r.EnumerateSubdirectories(base, i)
    if not sub then break end
    local src_name = "Archive:" .. sub
    local src_dir = base .. "/" .. sub
    local j = 0
    while true do
      local fn = r.EnumerateFiles(src_dir, j)
      if not fn then break end
      local ext = (fn:match("^.+(%.[^%.]+)$") or ""):lower()
      if ext == ".syx" or ext == ".mid" or ext == ".midi" then
        local file_path = src_dir .. "/" .. fn
        -- Phase 18: index cache fast path (skip decode if names cached)
        local bytes_tmp = _file_read_all_bytes(file_path)
        local cached_names = bytes_tmp and _lib_cache_get_names(file_path, bytes_tmp) or nil
        if cached_names and #cached_names == 48 then
          for vi=1,48 do
            local vkey = _lib_entry_key(src_name, fn, vi)
            local t = (LIBRARY.tags and LIBRARY.tags[vkey]) or ""
            add_item(src_name, file_path, vi, cached_names[vi] or "", t)
          end
        else
          local res = _library_load_file_voices(file_path)

        if res and res.kind == "bank" and res.bank and res.bank.voices then
          for vi=1,#res.bank.voices do
            local vkey = _lib_entry_key(src_name, fn, vi)
            local t = (LIBRARY.tags and LIBRARY.tags[vkey]) or ""
            local nm = _voice_label_from_bytes64(res.bank.voices[vi], "")
            add_item(src_name, file_path, vi, nm, t)
          end
        elseif res and res.kind == "instvoice" and res.inst and res.inst.voice_bytes then
          local vkey = _lib_entry_key(src_name, fn, 1)
          local t = (LIBRARY.tags and LIBRARY.tags[vkey]) or ""
          local nm = _voice_label_from_bytes64(res.inst.voice_bytes, "")
          add_item(src_name, file_path, 1, nm, t)
        end
        end -- Phase 18: index cache fast path

      end
      j = j + 1
    end
    i = i + 1
  end

  -- optional external folder
  if LIBRARY.folder and LIBRARY.folder ~= "" then
    local src_name = "Folder:" .. LIBRARY.folder
    local j = 0
    while true do
      local fn = r.EnumerateFiles(LIBRARY.folder, j)
      if not fn then break end
      local ext = (fn:match("^.+(%.[^%.]+)$") or ""):lower()
      if ext == ".syx" or ext == ".mid" or ext == ".midi" then
        local file_path = LIBRARY.folder .. "/" .. fn
        local res = _library_load_file_voices(file_path)
        if res and res.kind == "bank" and res.bank and res.bank.voices then
          for vi=1,#res.bank.voices do
            local vkey = _lib_entry_key(src_name, fn, vi)
            local t = (LIBRARY.tags and LIBRARY.tags[vkey]) or ""
            local nm = _voice_label_from_bytes64(res.bank.voices[vi], "")
            add_item(src_name, file_path, vi, nm, t)
          end
        elseif res and res.kind == "instvoice" and res.inst and res.inst.voice_bytes then
          local vkey = _lib_entry_key(src_name, fn, 1)
          local t = (LIBRARY.tags and LIBRARY.tags[vkey]) or ""
          local nm = _voice_label_from_bytes64(res.inst.voice_bytes, "")
          add_item(src_name, file_path, 1, nm, t)
        end
      end
      j = j + 1
    end
  end

  return idx
end

local function _lib_index_match(it, q, tag)
  q = (q or ""):lower()
  tag = (tag or ""):lower()
  if q=="" and tag=="" then return true end
  local hay = (tostring(it.source).." "..tostring(it.file).." "..tostring(it.name).." "..tostring(it.tags)):lower()
  local okq = (q=="" or hay:find(q,1,true)~=nil)
  local okt = (tag=="" or hay:find(tag,1,true)~=nil)
  local meta = LIBRARY and LIBRARY.user_meta
  if meta then
    if LIBRARY.show_fav_only and not meta.fav[_lib_entry_key(it.source,it.file:match('([^/\\]+)$') or it.file,it.voice)] then return false end
    local rk = _lib_entry_key(it.source,it.file:match('([^/\\]+)$') or it.file,it.voice)
    local rv = tonumber(meta.rating[rk] or 0) or 0
    if (LIBRARY.min_rating or 0) > 0 and rv < (LIBRARY.min_rating or 0) then return false end
  end
  return okq and okt
end

local function _lib_export_preset_pack_from_selected()
  if not (LIBRARY.bank and LIBRARY.bank.voices) then return false, "No active bank loaded" end
  local sel = LIBRARY.selected_set or {}
  local list = {}
  for k,_ in pairs(sel) do
    local _,_,vi = _lib_parse_selected_key(k)
    if vi and vi>=1 and vi<=#LIBRARY.bank.voices then
      list[#list+1] = vi
    end
  end
  table.sort(list)
  if #list == 0 then return false, "No voices selected" end

  local ts = os.date("%Y%m%d_%H%M%S")
  local dir = _lib_exports_dir() .. "/PresetPack_" .. ts

  -- =========================
  -- Session Bundle (Phase 29): export/import meta + selected voice + config slot
  -- =========================
  r.ImGui_Separator(ctx)

  -- Auto Audition (Phase 31)
  r.ImGui_Text(ctx, "Auto Audition (Phase 31)")
  local c
  c, LIBRARY.auto_audition = r.ImGui_Checkbox(ctx, "Auto-send on selection (temp)", LIBRARY.auto_audition or false)
  r.ImGui_SameLine(ctx)
  c, LIBRARY.auto_audition_ms = r.ImGui_SliderInt(ctx, "Throttle (ms)", LIBRARY.auto_audition_ms or 350, 100, 2000)
  r.ImGui_Text(ctx, "Uses temp InstVoice send to edit buffer (no store).")

  r.ImGui_Separator(ctx)

  -- Phase 32: Favorites Scan quick-start
  if r.ImGui_Button(ctx, "Start Favorites Scan", 220, 0) then
  if r.ImGui_Button(ctx, "Build Queue from Current Results", 300, 0) then
  -- Queue Options (Phase 34)
  r.ImGui_Text(ctx, "Queue Options (Phase 34)")
  local c
  c, LIBRARY.queue_auto_rebuild = r.ImGui_Checkbox(ctx, "Auto-rebuild from current results", LIBRARY.queue_auto_rebuild ~= false)
  r.ImGui_SameLine(ctx)
  c, LIBRARY.queue_wrap = r.ImGui_Checkbox(ctx, "Wrap", LIBRARY.queue_wrap ~= false)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Rebuild Queue Now", 160, 0) then
    local n = _queue_build_from_current_results(true)
    LIBRARY.status = "Queue rebuilt: " .. tostring(n) .. " items"
  end
  if LIBRARY.queue_list and #LIBRARY.queue_list > 0 then
    r.ImGui_Text(ctx, ("Queue: %d items, pos %d"):format(#LIBRARY.queue_list, LIBRARY.queue_pos or 0))
  end

    local n = _queue_build_from_current_results(false)
    LIBRARY.status = "Queue built: " .. tostring(n) .. " items"
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Start Queue Scan", 160, 0) then
    if not LIBRARY.queue_list then _queue_build_from_current_results(false) end
    LIBRARY.scan_mode = "queue"
    LIBRARY.scan_enabled = true
    _log_add("scan", "Start Favorites Scan")
    LIBRARY.scan_last_t = 0
  end

    LIBRARY.scan_mode = "favorites"
    LIBRARY.scan_list = nil
    LIBRARY.scan_pos = 0
    LIBRARY.scan_enabled = true
    LIBRARY.scan_last_t = 0
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Stop Scan", 120, 0) then
    LIBRARY.scan_enabled = false
    _log_add("scan", "Stop Scan")
  end

  r.ImGui_Text(ctx, "Session Bundle (Phase 29)")
  if not BUNDLE then BUNDLE = { include_meta=true, include_tags=true, include_cache=false, include_config_slot=true, config_slot=0, include_voice=true } end
  local c
  c, BUNDLE.include_voice = r.ImGui_Checkbox(ctx, "Include current voice (.syx)", BUNDLE.include_voice); r.ImGui_SameLine(ctx)
  c, BUNDLE.include_config_slot = r.ImGui_Checkbox(ctx, "Include config slot (.syx)", BUNDLE.include_config_slot); r.ImGui_SameLine(ctx)
  c, BUNDLE.include_meta = r.ImGui_Checkbox(ctx, "Include favorites/ratings", BUNDLE.include_meta)
  c, BUNDLE.include_tags = r.ImGui_Checkbox(ctx, "Include tags", BUNDLE.include_tags); r.ImGui_SameLine(ctx)
  c, BUNDLE.include_cache = r.ImGui_Checkbox(ctx, "Include cache", BUNDLE.include_cache)
  c, BUNDLE.config_slot = r.ImGui_SliderInt(ctx, "Config slot", BUNDLE.config_slot or 0, 0, 20)

  if r.ImGui_Button(ctx, "Export Session Bundle", 220, 0) then
    local dir = _bundle_path()
    r.RecursiveCreateDirectory(dir, 0)
    -- meta files
    if BUNDLE.include_meta then _copy_file(_meta_path(), dir.."/library_user_meta.json") end
    if BUNDLE.include_tags then _copy_file(_tags_path(), dir.."/library_tags.json") end
    if BUNDLE.include_cache then _copy_file(_cache_path(), dir.."/library_cache.json") end
    -- voice
    if BUNDLE.include_voice and LIBRARY and LIBRARY.selected_voice_bytes then
      local syx_bytes = VoiceDump.build_inst_voice_sysex(LIBRARY.selected_voice_bytes, CAPTURE_CFG.sys_ch or 0, 0)
      _write_bytes_file(dir.."/voice_current.syx", syx_bytes)
    end
    -- config slot
    if BUNDLE.include_config_slot and CONFIG_LIB and CONFIG_LIB.store then
      local slot = tostring(BUNDLE.config_slot or 0)
      local obj = CONFIG_LIB.store[slot]
      local payload = (type(obj)=="table" and obj.payload) or obj
      local cmd = (type(obj)=="table" and obj.cmd_prefix) or nil
      if payload and ConfigDump and ConfigDump.build_config_sysex then
        local msg = ConfigDump.build_config_sysex(CAPTURE_CFG.sys_ch or 0, payload, cmd)
        _write_bytes_file(dir..("/config_slot%s.syx"):format(slot), msg)
      end
    end
    -- seed/state
    local f = io.open(dir.."/bundle_state.json","wb")
    if f then
      f:write(string.format("{\"sys_ch\":%d,\"seed\":%d,\"style\":\"%s\"}\n",
        tonumber(CAPTURE_CFG.sys_ch or 0) or 0,
        tonumber((RANDOM_EX and RANDOM_EX.seed) or 0) or 0,
        tostring((RANDOM_STYLE and RANDOM_STYLE.style) or "Pad")
      ))
      f:close()
    end
    LIBRARY.status = "Exported bundle: " .. dir
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Import Bundle (from folder path in search)", 360, 0) then
    -- User pastes a folder path into LIBRARY.index_search to import
    local dir = tostring(LIBRARY.index_search or "")
    if dir ~= "" then
      if BUNDLE.include_meta then _copy_file(dir.."/library_user_meta.json", _meta_path()) end
      if BUNDLE.include_tags then _copy_file(dir.."/library_tags.json", _tags_path()) end
      if BUNDLE.include_cache then _copy_file(dir.."/library_cache.json", _cache_path()) end
      -- import voice into current selection
      local vb = _read_bytes_file(dir.."/voice_current.syx")
      if vb and VoiceDump and VoiceDump.decode_inst_voice_from_any then
        local v = VoiceDump.decode_inst_voice_from_any(vb)
        if v and v.voice_block then
          LIBRARY.selected_voice_bytes = v.voice_block
        end
      end
      -- import config slot file if present (capture via Rx not possible; decode locally and store)
      local slot = tostring(BUNDLE.config_slot or 0)
      local cb = _read_bytes_file(dir..("/config_slot%s.syx"):format(slot))
      if cb and ConfigDump and ConfigDump.decode_config_from_sysex then
        local cobj = ConfigDump.decode_config_from_sysex(cb)
        if cobj and cobj.payload_bytes then
          CONFIG_LIB.store[slot] = { payload=cobj.payload_bytes, cmd_prefix=cobj.cmd_prefix }
          _config_save_store(CONFIG_LIB.store)
        end
      end
      LIBRARY.user_meta = _lib_load_user_meta()
      LIBRARY.tags = _lib_load_tags()
      LIBRARY.cache = _lib_load_cache()
      LIBRARY.status = "Imported bundle from: " .. dir
    end
  end
  r.ImGui_Text(ctx, "Import: paste bundle folder path into the Search field, then click Import.")

  r.RecursiveCreateDirectory(dir, 0)

  -- write index
  local f = io.open(dir .. "/index.json", "wb")
  if f then
    f:write("{\"created\":\"".._json_escape(ts).."\",\"count\":"..tostring(#list)..",\"items\":[\n")
    for i,vi in ipairs(list) do
      local nm = _voice_label_from_bytes64(LIBRARY.bank.voices[vi], "")
      if i>1 then f:write(",\n") end
      f:write(("{\"voice_index\":%d,\"name\":\"%s\"}"):format(vi,_json_escape(nm)))
    end
    f:write("\n]}\n"); f:close()
  end

  -- write .syx per voice (InstVoice format, stable)
  for _,vi in ipairs(list) do
    local nm = _voice_label_from_bytes64(LIBRARY.bank.voices[vi], "voice")
    local safe = nm:gsub("[^%w%-%_]+","_")
    if safe == "" then safe = ("voice_%02d"):format(vi) end
    local syx_path = dir .. ("/%02d_%s.syx"):format(vi, safe)
    local syx = VoiceDump.build_inst_voice_sysex(LIBRARY.bank.voices[vi], CAPTURE_CFG.sys_ch or 0, 0) -- inst 0 default
    local wf = io.open(syx_path, "wb")
    if wf then
      wf:write(syx)
      wf:close()
    end
  end
  return true, dir
end
-- =========================
-- PHASE 16.1: SMF SysEx reassembly + Cache fill/use + Batch actions on multi-select
-- =========================
local function _midi_reassemble_sysex_packets(msgs)
  -- Reassemble SMF SysEx packets:
  -- - First packet: 0xF0 + len + data (may or may not include terminal 0xF7)
  -- - Continuations: 0xF7 + len + data; if we're "in sysex", it's continuation
  -- We output messages normalized to start with 0xF0 and end with 0xF7 when possible.
  local out = {}
  local cur = nil
  local in_sysex = false
  for _,m in ipairs(msgs or {}) do
    local st = m[1]
    if st == 0xF0 then
      -- start new message
      cur = {0xF0}
      for i=2,#m do cur[#cur+1]=m[i] end
      in_sysex = true
      if cur[#cur] == 0xF7 then
        out[#out+1]=cur
        cur=nil; in_sysex=false
      end
    elseif st == 0xF7 then
      if in_sysex and cur then
        for i=2,#m do cur[#cur+1]=m[i] end
        if cur[#cur] == 0xF7 then
          out[#out+1]=cur
          cur=nil; in_sysex=false
        end
      else
        -- escape sequence or standalone; keep as-is wrapped to F0 for decoder friendliness
        local esc = {0xF0}
        for i=2,#m do esc[#esc+1]=m[i] end
        if esc[#esc] ~= 0xF7 then esc[#esc+1]=0xF7 end
        out[#out+1]=esc
      end
    else
      -- ignore
    end
  end
  if cur and #cur > 1 then
    if cur[#cur] ~= 0xF7 then cur[#cur+1]=0xF7 end
    out[#out+1]=cur
  end
  return out
end

local function _lib_cache_put_names(file_path, bytes, kind, names)
  if not LIBRARY or not LIBRARY.cache then return end
  local h = tostring(#bytes) .. ":" .. tostring(bytes[1] or 0) .. ":" .. tostring(bytes[2] or 0) .. ":" .. tostring(bytes[#bytes] or 0)
  LIBRARY.cache.files = LIBRARY.cache.files or {}
  LIBRARY.cache.files[file_path] = { hash=h, kind=kind, voices=(names and #names or 0), names=(names or {}) }
  _lib_save_cache(LIBRARY.cache)
end

local function _lib_cache_get_names(file_path, bytes)
  if not LIBRARY or not LIBRARY.cache or not LIBRARY.cache.files then return nil end
  local e = LIBRARY.cache.files[file_path]
  if not e then return nil end
  local h = tostring(#bytes) .. ":" .. tostring(bytes[1] or 0) .. ":" .. tostring(bytes[2] or 0) .. ":" .. tostring(bytes[#bytes] or 0)
  if e.hash == h and e.names and #e.names > 0 then return e.names end
  return nil
end

local function _lib_parse_selected_key(k)
  -- key: "source|file|voiceIndex"
  local a,b,c = k:match("^(.-)%|(.-)%|(.-)$")
  return tonumber(a or "0") or 0, tostring(b or ""), tonumber(c or "0") or 0
end
-- =========================
-- PHASE 16 LIBRARIAN: Real MIDI parser (SMF), Library cache, Multi-select tagging, Improved auto-tagging
-- =========================
local function _vlq_read(bytes, i)
  local value = 0
  local b
  repeat
    b = bytes[i]; i = i + 1
    value = (value << 7) | (b & 0x7F)
  until b < 0x80
  return value, i
end

local function _u32be(bytes, i)
  local v = (bytes[i] << 24) | (bytes[i+1] << 16) | (bytes[i+2] << 8) | (bytes[i+3])
  return v, i+4
end

local function _u16be(bytes, i)
  local v = (bytes[i] << 8) | (bytes[i+1])
  return v, i+2
end

local function _str4(bytes, i)
  local s = string.char(bytes[i],bytes[i+1],bytes[i+2],bytes[i+3])
  return s, i+4
end

local function _midi_parse_sysex_messages(bytes)
  -- Parse Standard MIDI File and return list of sysEx payloads (each includes F0..F7 or F7 continuation)
  local i = 1
  local sig; sig, i = _str4(bytes, i)
  if sig ~= "MThd" then return nil, "not a MIDI file" end
  local hlen; hlen, i = _u32be(bytes, i)
  local fmt; fmt, i = _u16be(bytes, i)
  local ntr; ntr, i = _u16be(bytes, i)
  local div; div, i = _u16be(bytes, i)
  i = 1 + 8 + hlen  -- skip to first track (safe)
  local msgs = {}
  local running = nil
  for tr=1,ntr do
    local tsig; tsig, i = _str4(bytes, i)
    if tsig ~= "MTrk" then return msgs, "missing MTrk" end
    local tlen; tlen, i = _u32be(bytes, i)
    local endi = i + tlen
    running = nil
    while i < endi do
      local delta; delta, i = _vlq_read(bytes, i)
      local status = bytes[i]
      if status < 0x80 then
        status = running
      else
        i = i + 1
        running = status
      end

      if status == 0xFF then
        local meta = bytes[i]; i=i+1
        local mlen; mlen, i = _vlq_read(bytes, i)
        i = i + mlen
      elseif status == 0xF0 or status == 0xF7 then
        local slen; slen, i = _vlq_read(bytes, i)
        local payload = {}
        payload[#payload+1] = status
        for k=0,slen-1 do
          payload[#payload+1] = bytes[i+k]
        end
        i = i + slen
        -- Many files omit terminal F7 in length; we keep as-is. If payload lacks F7, caller can assemble.
        msgs[#msgs+1] = payload
        running = nil
      else
        local hi = status & 0xF0
        local data_len = 0
        if hi == 0xC0 or hi == 0xD0 then data_len = 1
        else data_len = 2 end
        i = i + data_len
      end
    end
    i = endi
  end
  return msgs
end

local function _sysex_msgs_concat(msgs)
  local cat = {}
  for _,m in ipairs(msgs or {}) do
    for i=1,#m do cat[#cat+1]=m[i] end
  end
  return cat
end

local function _read_sysex_payloads_from_file(path)
  local bytes, err = _file_read_all_bytes(path)
  if not bytes then return nil, err end
  local ext = _file_ext(path)
  if ext == ".mid" or ext == ".midi" then
    local msgs, perr = _midi_parse_sysex_messages(bytes)
    if not msgs then
      -- fallback to naive scanner
      msgs = _extract_sysex_from_midi_file_bytes(bytes)
    end
    msgs = _midi_reassemble_sysex_packets(msgs)
    return { kind="midi", bytes=bytes, msgs=msgs }:gsub("return \{ kind=\"midi\", bytes=bytes, msgs=msgs \}", "")
  else
    local msgs = _split_sysex_messages(bytes)
    return { kind="raw", bytes=bytes, msgs=msgs }
  end
end

local function _sha1_bytes(bytes)
  -- minimal sha1 via ext: use project extstate hashing isn't available; so use crude hash string
  -- We'll use a stable small hash: first/last 64 bytes + len
  local n = #bytes
  local acc = tostring(n) .. "|"
  for i=1,math.min(n,64) do acc = acc .. string.char(bytes[i]) end
  for i=math.max(1,n-63),n do acc = acc .. string.char(bytes[i]) end
  return tostring(r.genGuid and r.genGuid(acc) or (acc:sub(1,64)))
end

local function _lib_cache_path() return _lib_db_dir() .. "/library_cache.json" end

local function _lib_load_cache()
  local f = io.open(_lib_cache_path(), "rb")
  if not f then return { files = {} } end
  local s = f:read("*all"); f:close()
  if not s or s == "" then return { files = {} } end
  local t = {}
  -- shallow JSON object decode for our needs
  for k,v in s:gmatch('"%s*([^"]+)%s*"%s*:%s*%{') do
    -- noop; we decode via regex below
    t.files = t.files or {}
  end
  -- very small decoder: entries are stored as lines '"path":{"hash":"...","kind":"bank","voices":48,"names":[...]}'
  local files = {}
  for pth, body in s:gmatch('"%s*([^"]+)%s*"%s*:%s*(%b{})') do
    local h = body:match('"%s*hash%s*"%s*:%s*"([^"]+)"') or ""
    local kind = body:match('"%s*kind%s*"%s*:%s*"([^"]+)"') or ""
    local voices = tonumber(body:match('"%s*voices%s*"%s*:%s*(%d+)') or "0") or 0
    local names = {}
    local names_blob = body:match('"%s*names%s*"%s*:%s*(%b%[%])')
    if names_blob then
      for n in names_blob:gmatch('"([^"]-)"') do names[#names+1]=n end
    end
    files[pth] = { hash=h, kind=kind, voices=voices, names=names }
  end
  return { files = files }
end

local function _lib_save_cache(cache)
  local f = io.open(_lib_cache_path(), "wb"); if not f then return false end
  f:write("{\n  \"files\": {\n")
  local first = true
  for pth, e in pairs(cache.files or {}) do
    if not first then f:write(",\n") end
    first = false
    local p = tostring(pth):gsub("\\","\\\\"):gsub('"','\\"')
    local h = tostring(e.hash or ""):gsub("\\","\\\\"):gsub('"','\\"')
    local k = tostring(e.kind or ""):gsub("\\","\\\\"):gsub('"','\\"')
    f:write(('    "%s": { "hash":"%s", "kind":"%s", "voices":%d, "names":['):format(p,h,k, tonumber(e.voices or 0)))
    local nf = true
    for _,nm in ipairs(e.names or {}) do
      if not nf then f:write(",") end
      nf = false
      local ns = tostring(nm):gsub("\\","\\\\"):gsub('"','\\"')
      f:write(('"%s"'):format(ns))
    end
    f:write("] }")
  end
  f:write("\n  }\n}\n"); f:close()
  return true
end

local function _lib_improved_autotag(vv, opv)
  -- heuristics: attempt style tags from common decoded fields
  local tags = {}
  local alg = vv and (vv.algorithm or vv.algo)
  local fb  = vv and (vv.feedback or vv.fb)
  if alg ~= nil then
    if alg == 0 or alg == 1 then tags[#tags+1]="bass"
    elseif alg == 2 or alg == 3 then tags[#tags+1]="pad"
    elseif alg == 6 or alg == 7 then tags[#tags+1]="fx" end
  end
  if fb ~= nil and fb >= 5 then tags[#tags+1]="bright" end
  -- percussive: very fast attack on at least one op
  if opv then
    for op=1,4 do
      local ar = opv["op"..op] and (opv["op"..op].attack_rate or opv["op"..op].ar)
      if ar and ar >= 24 then tags[#tags+1]="perc"; break end
    end
  end
  if #tags==0 then tags[#tags+1]="untagged" end
  -- de-dup
  local seen, out = {}, {}
  for _,t in ipairs(tags) do if not seen[t] then seen[t]=true; out[#out+1]=t end end
  return table.concat(out, ",")
end
-- =========================
-- PHASE 15 LIBRARIAN: Voice names, MIDI(.mid) SysEx extraction, Batch Verify, Tag chips
-- =========================
local function _extract_sysex_from_midi_file_bytes(file_bytes)
  -- Naive but practical: find raw F0..F7 sequences inside the MIDI file.
  -- Many SysEx MIDIs store literal F0 ... F7 in track data (especially exports from editors).
  local msgs = {}
  local cur = nil
  for i=1,#file_bytes do
    local b = file_bytes[i]
    if b == 0xF0 then cur = {b}
    elseif cur then
      cur[#cur+1] = b
      if b == 0xF7 then
        msgs[#msgs+1] = cur
        cur = nil
      end
    end
  end
  return msgs
end

local function _file_ext(path)
  return (path:match("^.+(%.[^%.]+)$") or ""):lower()
end

local function _read_sysex_payloads_from_file(path)
  local bytes, err = _file_read_all_bytes(path)
  if not bytes then return nil, err end
  local ext = _file_ext(path)
  if ext == ".mid" or ext == ".midi" then
    local msgs = _extract_sysex_from_midi_file_bytes(bytes)
    msgs = _midi_reassemble_sysex_packets(msgs)
    return { kind="midi", bytes=bytes, msgs=msgs }
  else
    local msgs = _split_sysex_messages(bytes)
    return { kind="raw", bytes=bytes, msgs=msgs }
  end
end

local function _voice_label_from_bytes64(bytes64, fallback)
  if VoiceMap and VoiceMap.decode_voice_block then
    local ok, vv, opv, meta = pcall(function()
      local a,b,c = VoiceMap.decode_voice_block(bytes64)
      return a,b,c
    end)
    if ok and meta and meta.name and meta.name ~= "" then
      return meta.name
    end
  end
  return fallback or "(voice)"
end

local function _collect_unique_tags(tags_db)
  local set, arr = {}, {}
  for _,v in pairs(tags_db or {}) do
    for t in tostring(v):gmatch("[^,%s]+") do
      if not set[t] then set[t]=true; arr[#arr+1]=t end
    end
  end
  table.sort(arr)
  return arr
end
-- =========================
-- PHASE 14 LIBRARY: Search/Tags/Batch + Type Detect + Multipart
-- =========================
local function _split_sysex_messages(bytes)
  local msgs, cur = {}, nil
  for i=1,#bytes do
    local b = bytes[i]
    if b == 0xF0 then cur = { b }
    elseif cur then
      cur[#cur+1] = b
      if b == 0xF7 then msgs[#msgs+1] = cur; cur = nil end
    end
  end
  return msgs
end

local function _file_read_all_bytes(path)
  local f = io.open(path, "rb"); if not f then return nil, "open failed" end
  local data = f:read("*all"); f:close()
  if not data then return nil, "read failed" end
  local bytes = {}
  for i=1,#data do bytes[i] = data:byte(i) end
  return bytes
end

local function _lib_db_dir()
  local p = r.GetProjectPath("") or ""
  if p == "" then p = r.GetResourcePath() end
  local d = p .. "/IFLS_FB01_Library"
  r.RecursiveCreateDirectory(d, 0)
  return d
end

local function _lib_tags_path() return _lib_db_dir() .. "/library_tags.json" end

local function _lib_load_tags()
  local f = io.open(_lib_tags_path(), "rb")
  if not f then return {} end
  local s = f:read("*all"); f:close()
  if not s or s == "" then return {} end
  local t = {}
  for k,v in s:gmatch('"%s*([^"]+)%s*"%s*:%s*"%s*([^"]-)%s*"') do t[k] = v end
  return t
end

local function _lib_save_tags(tags)
  local f = io.open(_lib_tags_path(), "wb"); if not f then return false end
  f:write("{\n")
  local first = true
  for k,v in pairs(tags) do
    if not first then f:write(",\n") end
    first = false
    local ks = tostring(k):gsub("\\","\\\\"):gsub('"','\\"')
    local vs = tostring(v):gsub("\\","\\\\"):gsub('"','\\"')
    f:write(('  "%s":"%s"'):format(ks, vs))
  end
  f:write("\n}\n"); f:close()
  return true
end

local function _lib_entry_key(source_id, file_rel, voice_index)
  return tostring(source_id) .. "|" .. tostring(file_rel) .. "|" .. tostring(voice_index or 0)
end

local function _lib_guess_tags_from_voice(voice_vals)
  local tags = {}
  local alg = voice_vals and (voice_vals.algorithm or voice_vals.algo)
  local fb  = voice_vals and (voice_vals.feedback or voice_vals.fb)
  if alg ~= nil then
    if alg == 0 or alg == 1 then tags[#tags+1] = "simple"
    elseif alg == 6 or alg == 7 then tags[#tags+1] = "complex" end
  end
  if fb ~= nil and fb >= 5 then tags[#tags+1] = "bright" end
  if #tags == 0 then tags[#tags+1] = "untagged" end
  return table.concat(tags, ",")
end

local function _decode_bank_any_from_bytes(bytes)
  if decode_bank_any then
    local ok, bank = pcall(decode_bank_any, bytes)
    if ok and bank and bank.voices and #bank.voices == 48 then return bank end
  end
  local msgs = _split_sysex_messages(bytes)
  if #msgs > 1 and decode_bank_any then
    local cat = {}
    for _,m in ipairs(msgs) do for i=1,#m do cat[#cat+1]=m[i] end end
    local ok, bank = pcall(decode_bank_any, cat)
    if ok and bank and bank.voices and #bank.voices == 48 then return bank end
  end
  return nil
end

local function _decode_instvoice_any_from_bytes(bytes)
  if VoiceDump and VoiceDump.decode_inst_voice_from_sysex then
    local ok, res = pcall(VoiceDump.decode_inst_voice_from_sysex, bytes)
    if ok and res and res.voice_bytes and #res.voice_bytes == 64 then return res end
  end
  local msgs = _split_sysex_messages(bytes)
  if #msgs > 1 and VoiceDump and VoiceDump.decode_inst_voice_from_sysex then
    for _,m in ipairs(msgs) do
      local ok, res = pcall(VoiceDump.decode_inst_voice_from_sysex, m)
      if ok and res and res.voice_bytes and #res.voice_bytes == 64 then return res end
    end
  end
  return nil
end
  sources = {},
  source_sel = 1,
  file_sel = 1,
  voice_sel = 1,
  files = {},
  voices = {},
  folder = _ext_get("library_folder", ""),
  index = nil,
  status = "",
  last_scan_ts = nil,
  selected_key = nil,
  selected_voice = nil, -- {bank_key, voice_index, voice64}
}

local function _library_index_path()
  local proj = r.GetProjectPath("") or ""
  if proj == "" then proj = r.GetResourcePath() end
  local dir = proj .. "/IFLS_FB01_Library"
  r.RecursiveCreateDirectory(dir, 0)
  return dir .. "/library_index.json"
end

local function _read_file_bytes(path)
  local f = io.open(path, "rb"); if not f then return nil, "open failed" end
  local data = f:read("*all"); f:close()
  local t = {}
  for i=1,#data do t[i] = string.byte(data, i) end
  return t
end

local function _is_syx(bytes)
  return bytes and #bytes>=2 and bytes[1]==0xF0 and bytes[#bytes]==0xF7
end

local function _decode_bank_any(bytes)
  -- Try both decoders if present
  local ok, bank = pcall(function() return Bank and Bank.decode_voice_bank_from_sysex and Bank.decode_voice_bank_from_sysex(bytes) end)
  if ok and bank and bank.voices and #bank.voices==48 then return bank, "bank.lua" end
  ok, bank = pcall(function() return VoiceBank and VoiceBank.decode_bank_from_sysex and VoiceBank.decode_bank_from_sysex(bytes) end)
  if ok and bank and bank.voices and #bank.voices==48 then return bank, "voicebank.lua" end
  return nil, "decode failed"
end

local function _library_refresh_sources()
  LIBRARY.sources = {}
  -- 1) bundled archives
  local i = 0
  while true do
    local dn = r.EnumerateSubdirectories(BUNDLED_ARCHIVES_DIR, i)
    if not dn then break end
    table.insert(LIBRARY.sources, {label="Archive: "..dn, path=BUNDLED_ARCHIVES_DIR.."/"..dn})
    i = i + 1
  end
  -- 2) user folder (if set)
  if LIBRARY.folder and LIBRARY.folder ~= "" then
    table.insert(LIBRARY.sources, 1, {label="Folder: "..LIBRARY.folder, path=LIBRARY.folder})
  end
  if #LIBRARY.sources == 0 then
    table.insert(LIBRARY.sources, {label="(no sources found)", path=""})
  end
  if LIBRARY.source_sel < 1 then LIBRARY.source_sel = 1 end
  if LIBRARY.source_sel > #LIBRARY.sources then LIBRARY.source_sel = #LIBRARY.sources end
end

local function _library_refresh_files()
  LIBRARY.files = {}
  LIBRARY.voices = {}
        -- Phase 16.1: use cache names
        local cached_names = _lib_cache_get_names(file_path, res.bytes or {})
  LIBRARY.file_sel = 1
  LIBRARY.voice_sel = 1
  local src = LIBRARY.sources[LIBRARY.source_sel]
  if not src or src.path == "" then return end
  local i = 0
  while true do
    local fn = r.EnumerateFiles(src.path, i)
    if not fn then break end
    local l = fn:lower()
    if l:match("%.syx$") or l:match("%.mid$") or l:match("%.midi$") then
      table.insert(LIBRARY.files, {name=fn, path=src.path.."/"..fn})
    end
    i = i + 1
  end
  table.sort(LIBRARY.files, function(a,b) return a.name:lower() < b.name:lower() end)
end

        -- Phase 16: cache fast path (names only)
        local cache_key = tostring(file_path)
        local bytes_tmp = nil
        local ioobj_tmp = nil
        if LIBRARY.cache and LIBRARY.cache.files and LIBRARY.cache.files[cache_key] then
          -- We still need bytes for audition; but we can skip name decode in list if unchanged
        end

local function _library_load_file_voices(file_path)
  -- Phase 15: autodetect bank/single/multipart + MIDI SysEx extraction
  local ioobj, err = _read_sysex_payloads_from_file(file_path)
  if not ioobj then return nil, err end
  local bytes = ioobj.bytes
  -- Try bank decode on full bytes first
  local bank = _decode_bank_any_from_bytes(bytes)
  if bank and bank.voices then return { kind="bank", bank=bank, bytes=bytes, msgs=ioobj.msgs } end
  -- Try on concatenated SysEx messages (MIDI file case)
  if ioobj.msgs and #ioobj.msgs > 0 then
    local cat = {}
    for _,m in ipairs(ioobj.msgs) do for i=1,#m do cat[#cat+1]=m[i] end end
    local bank2 = _decode_bank_any_from_bytes(cat)
    if bank2 and bank2.voices then return { kind="bank", bank=bank2, bytes=bytes, msgs=ioobj.msgs } end
    local inst2 = _decode_instvoice_any_from_bytes(cat)
    if inst2 and inst2.voice_bytes then return { kind="instvoice", inst=inst2, bytes=bytes, msgs=ioobj.msgs } end
  end
  local inst = _decode_instvoice_any_from_bytes(bytes)
  if inst and inst.voice_bytes then return { kind="instvoice", inst=inst, bytes=bytes, msgs=ioobj.msgs } end
  return { kind="unknown", bytes=bytes, msgs=ioobj.msgs }
end

local function _library_scan_folder(folder)
  if not folder or folder=="" then return nil, "No folder set" end
  local files = {}
  local i=0
  while true do
    local fn = r.EnumerateFiles(folder, i)
    if not fn then break end
    if fn:lower():match("%.syx$") then
      files[#files+1] = folder .. "/" .. fn
    end
    i=i+1
  end
  local idx = { version=1, folder=folder, scanned_at=os.time(), banks={}, files_scanned=#files }
  local bank_key_n=0
  for _,path in ipairs(files) do
    local bytes, err = _read_file_bytes(path)
    if bytes and _is_syx(bytes) then
      local bank, src = _decode_bank_any(bytes)
      if bank and bank.voices then
        bank_key_n = bank_key_n + 1
        local key = ("bank_%03d"):format(bank_key_n)
        local entry = { key=key, path=path, decoder=src, voices_count=#bank.voices, voices={} }
        for vi,v64 in ipairs(bank.voices) do
          -- best-effort name: decode via VoiceMap if it exposes name; else empty
          local nm = ""
          local ok2, vv, ops = pcall(function() return VoiceMap.decode_voice_block(v64) end)
          if ok2 and vv and vv.name then nm = vv.name end
          entry.voices[#entry.voices+1] = { index=vi, name=nm }
        end
        idx.banks[#idx.banks+1] = entry
      end
    end
  end
  return idx
end

local function _library_save_index(idx)
  local path = _library_index_path()
  local json = _json_encode and _json_encode(idx) or nil
  if not json then return nil, "json encoder missing" end
  local f = io.open(path, "wb"); if not f then return nil, "write failed" end
  f:write(json); f:close()
  return path
end

local function _library_load_index()
  local path = _library_index_path()
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*all"); f:close()
  if _json_decode_min then
    local ok, t = pcall(function() return _json_decode_min(s) end)
    if ok then return t end
  end
  return nil
end

local VERIFY = {
  pending = false,
  kind = nil,            -- "instvoice" | "config" | "bank"
  target = nil,          -- byte array payload to compare
  started = 0.0,
  deadline = 0.0,
  timeout = 2.5,
  sys_ch = 0,
  inst_no = 0,
  result = nil,          -- {ok=bool, diffs=int, err=str, backend=str}
}

-- Phase 10.2: Native Bulk Verify Harness (send native bulk -> auto capture dump -> compare -> export report)
NATIVE_HARNESS = {
  active = false,
  kind = nil,           -- "instvoice_native_bulk" | "bank_native_bulk"
  started = 0.0,
  step = "idle",        -- "sending" | "await_dump" | "done"
  settings = nil,       -- snapshot of relevant settings
  report = nil,         -- last report table
}

local function _proj_dir()
  local p = r.GetProjectPath and r.GetProjectPath("") or ""
  if not p or p == "" then return r.GetResourcePath() end
  return p
end

local function _ts_compact()
  return os.date("%Y%m%d_%H%M%S")
end

local function _write_file(path, s)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(s)
  f:close()
  return true
end

local function _to_json_safe(tbl)
  -- minimal JSON encoder (safe; no load())
  local function esc(s)
    s = tostring(s)
    s = s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
    return '"'..s..'"'
  end
  local function enc(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "string" then return esc(v)
    elseif t == "table" then
      local is_arr = true
      local n = 0
      for k,_ in pairs(v) do
        if type(k) ~= "number" then is_arr = false; break end
        if k > n then n = k end
      end
      if is_arr then
        local out = {}
        for i=1,n do out[#out+1] = enc(v[i]) end
        return "["..table.concat(out,",").."]"
      else
        local out = {}
        for k,val in pairs(v) do out[#out+1] = esc(k)..":"..enc(val) end
        return "{"..table.concat(out,",").."}"
      end
    end
    return esc(tostring(v))
  end
  return enc(tbl)
end

local function _export_native_verify_report(report)
  local dir = _proj_dir()
  local base = dir .. "/IFLS_FB01_NativeVerify_" .. (report.kind or "unknown") .. "_" .. _ts_compact()
  local ok1 = _write_file(base .. ".json", _to_json_safe(report))
  -- plain text summary
  local lines = {}
  lines[#lines+1] = "IFLS FB-01 Native Verify Report"
  lines[#lines+1] = "kind="..tostring(report.kind)
  lines[#lines+1] = "ok="..tostring(report.ok).." diffs="..tostring(report.diffs).." backend="..tostring(report.backend)
  lines[#lines+1] = "started="..tostring(report.started_wallclock).." finished="..tostring(report.finished_wallclock)
  lines[#lines+1] = "settings:"
  if report.settings then
    for k,v in pairs(report.settings) do
      lines[#lines+1] = "  "..k.."="..tostring(v)
    end
  end
  if report.voice_diffs and #report.voice_diffs > 0 then
    lines[#lines+1] = "voice_diffs:"
    for i=1,#report.voice_diffs do
      local vd = report.voice_diffs[i]
      lines[#lines+1] = ("  voice %02d: diffs=%d"):format(vd.voice_index, vd.diffs or 0)
    end
  end
  local ok2 = _write_file(base .. ".txt", table.concat(lines, "\n"))
  return ok1 and ok2, base
end

local function _snapshot_native_settings()
  return {
    allow_native = (CAPTURE_CFG and CAPTURE_CFG.allow_native_bulk) or false,
    strict_checksum = (CAPTURE_CFG and CAPTURE_CFG.native_strict_checksum) or false,
    bytecount_two_bytes = (CAPTURE_CFG and CAPTURE_CFG.native_bytecount_two) or false,
    chunk_source_bytes = (CAPTURE_CFG and CAPTURE_CFG.native_chunk_source_bytes) or 48,
    sysex_delay_ms = (CAPTURE_CFG and CAPTURE_CFG.sysex_delay_ms) or 0,
    bulk_delay_ms = (CAPTURE_CFG and CAPTURE_CFG.bulk_delay_ms) or 120,
    retry_instvoice = (CAPTURE_CFG and CAPTURE_CFG.retry_count_instvoice) or 1,
    retry_bank = (CAPTURE_CFG and CAPTURE_CFG.retry_count_bank) or 2,
  }
end

local function native_harness_on_verify_done()
  if not NATIVE_HARNESS.active then return end
  local res = VERIFY.result
  if not res then return end
  local report = {
    kind = NATIVE_HARNESS.kind,
    ok = res.ok and true or false,
    diffs = res.diffs,
    backend = res.backend,
    started_wallclock = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    finished_wallclock = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    settings = NATIVE_HARNESS.settings,
  }
  -- bank reports: if we have a detailed bank verify report, include voice_diffs
  if BANK_VERIFY_REPORT and BANK_VERIFY_REPORT.voice_diffs then
    report.voice_diffs = BANK_VERIFY_REPORT.voice_diffs
  end
  NATIVE_HARNESS.report = report
  NATIVE_HARNESS.active = false
  NATIVE_HARNESS.step = "done"
  local ok, base = _export_native_verify_report(report)
  if ok then
    r.ShowConsoleMsg(("Native verify report saved: %s[.json/.txt]\n"):format(base))
  else
    r.ShowConsoleMsg("Native verify report save failed\n")
  end
end

local 
-- =========================
-- Phase 4: Capture settings (timeouts, preferred MIDI input, cleanup)
-- Stored in ExtState namespace IFLS_FB01_EDITOR
-- =========================
local EXT_NS = "IFLS_FB01_EDITOR"

local function _ext_get(key, default)
  local v = r.GetExtState(EXT_NS, key)
  if v == nil or v == "" then return default end
  return v
end

local function _ext_set(key, val)
  r.SetExtState(EXT_NS, key, tostring(val), true)
end

local CAPTURE_CFG = {
  preferred_midi_out = tonumber(_ext_get("fb01_preferred_midi_out", "-1")) or -1,
  preferred_midi_out_name = _ext_get("fb01_preferred_midi_out_name", ""),
  send_mode = _ext_get("fb01_send_mode", "track"), -- "track" recommended

-- =========================
-- PHASE 21.1 AUTODETECT SYS CH: probe System Channel by sending InstVoice dump request and watching Rx.get_last_dump().ts
-- =========================
AUTOSYS = AUTOSYS or { active=false, ch=0, inst=0, prev_ts=nil, deadline=0, status="" }

local function _autosys_start()
  AUTOSYS.active = true
  AUTOSYS.ch = 0
  AUTOSYS.inst = 0
  AUTOSYS.prev_ts = CAPTURE and CAPTURE.last_rx_ts or nil
  AUTOSYS.deadline = 0
  AUTOSYS.status = "probing..."
end

local function _autosys_tick()
  if not AUTOSYS.active then return end
  local now = (r.time_precise and r.time_precise()) or os.clock()
  -- if we saw a new dump, stop
  if CAPTURE and AUTOSYS.prev_ts and CAPTURE.last_rx_ts and CAPTURE.last_rx_ts ~= AUTOSYS.prev_ts then
    CAPTURE_CFG.sys_ch = AUTOSYS.ch
    _ext_set("fb01_sys_ch", AUTOSYS.ch)
    AUTOSYS.status = "found system channel: " .. tostring(AUTOSYS.ch)
    AUTOSYS.active = false
    return
  end
  if now < (AUTOSYS.deadline or 0) then return end
  if AUTOSYS.ch > 15 then
    AUTOSYS.status = "not found (no response on sys ch 0..15)"
    AUTOSYS.active = false
    return
  end
  -- probe current channel
  local sysch = AUTOSYS.ch
  if Syx and Syx.dump_inst_voice and enqueue_sysex then
    enqueue_sysex(Syx.dump_inst_voice(sysch, AUTOSYS.inst))
  end
  AUTOSYS.prev_ts = CAPTURE and CAPTURE.last_rx_ts or AUTOSYS.prev_ts
  AUTOSYS.deadline = now + 0.7  -- 700ms per channel
  AUTOSYS.status = "probing sys ch " .. tostring(sysch)
  AUTOSYS.ch = AUTOSYS.ch + 1
end

  -- FB-01 System Channel (Device ID) for SysEx addressing (0-15)
  sys_ch = tonumber(_ext_get("fb01_sys_ch", "0")) or 0,
  -- timeouts in seconds
  t_instvoice = tonumber(_ext_get("capture_timeout_instvoice", "2.5")) or 2.5,
  t_config    = tonumber(_ext_get("capture_timeout_config",   "5.0")) or 5.0,
  t_bank      = tonumber(_ext_get("capture_timeout_bank",     "9.0")) or 9.0,

  -- preferred MIDI input device index (0..N-1), or -1 for all inputs
  pref_midi_in = tonumber(_ext_get("preferred_midi_input", "-2")) or -2,

  -- cleanup: 0 keep, 1 delete, 2 archive
  cleanup_mode = tonumber(_ext_get("capture_cleanup_mode", "0")) or 0,
  auto_export_paramdiff = tonumber(_ext_get("auto_export_paramdiff", "0")) or 0,
  cleanup_mode_instvoice = tonumber(_ext_get("capture_cleanup_mode_instvoice", "")) or nil,
  cleanup_mode_config    = tonumber(_ext_get("capture_cleanup_mode_config",    "")) or nil,
  cleanup_mode_bank      = tonumber(_ext_get("capture_cleanup_mode_bank",      "")) or nil,

  -- Phase 5: retry counts (SysEx throttling / flaky interfaces)
  retry_count_instvoice = tonumber(_ext_get("capture_retry_count_instvoice", "1")) or 1,
  retry_count_config    = tonumber(_ext_get("capture_retry_count_config",   "2")) or 2,
  retry_count_bank      = tonumber(_ext_get("capture_retry_count_bank",     "2")) or 2,

}

local function _capture_archive_track_name()
  return "IFLS FB01 CAPTURE ARCHIVE"
end

local function _list_midi_inputs()
  local n = r.GetNumMIDIInputs()
  local names = {"Auto (single MIDI input)", "All MIDI inputs"}
  for i=0,n-1 do
    local ok, name = r.GetMIDIInputName(i, "")
    if ok and name and name ~= "" then
      names[#names+1] = string.format("%d: %s", i+1, name)
    else
      names[#names+1] = string.format("%d: MIDI Input %d", i+1, i+1)
    end
  end
  return names
end

local function _midi_input_combo_items(names)
  -- ImGui Combo expects NUL-separated string list ending with double NUL.
  return table.concat(names, "\0") .. "\0\0"
end

local function resolve_pref_midi_in()
  -- pref_midi_in: -2=auto(single), -1=all, 0..N-1 specific
  local n = r.GetNumMIDIInputs() or 0
  if CAPTURE_CFG.pref_midi_in == -2 then
    if n == 1 then return 0 end
    return -1
  end
  if CAPTURE_CFG.pref_midi_in == -1 then return -1 end
  if CAPTURE_CFG.pref_midi_in >= 0 and CAPTURE_CFG.pref_midi_in < n then return CAPTURE_CFG.pref_midi_in end
  return -1
end

CAPTURE = {
  active = false,
  kind = nil,        -- "instvoice" | "config" | "bank"
  started = 0.0,
  deadline = 0.0,
  timeout = 4.0,
  track = nil,
  track_idx = -1,
  -- item tracking for cleanup
  pre_item_guids = nil,
  new_items = nil,   -- array of MediaItem handles captured in this session
  cleanup_done = false,
  -- Phase 5 retry state
  retries_left = 0,
  attempt = 0,
  last_backend = nil,
  last_rx_ts = nil,
  captured_sysex_msgs = nil,
  captured_sysex_assembled = nil,
  prev_arms = nil,   -- array of {tr, arm}
  seen_sysex = false,
  err = nil,
}

local function _now()
  return r.time_precise()
end

local function verify_start(kind, target_bytes, opts)
  opts = opts or {}
  VERIFY.pending = true
  VERIFY.kind = kind
  VERIFY.target = target_bytes or {}
  VERIFY.started = _now()
  VERIFY.timeout = tonumber(opts.timeout) or VERIFY.timeout
  VERIFY.deadline = VERIFY.started + VERIFY.timeout
  VERIFY.sys_ch = tonumber(opts.sys_ch) or 0
  VERIFY.inst_no = tonumber(opts.inst_no) or 0
  VERIFY.result = nil
  -- UI compatibility flags
  if kind == "bank" then
    local decoded = nil
    if decode_bank_any then decoded = select(1, decode_bank_any(target_bytes)) end
    VERIFY.target_decoded = decoded
  else
    VERIFY.target_decoded = nil
  end
  if kind == "instvoice" then
    sv_verify_pending = true
    sv_verify_result = nil
  else
    verify_stage = "await_dump"
    verify_result = nil
  end
end

local function verify_clear()
  VERIFY.pending = false
  VERIFY.kind = nil
  VERIFY.target = nil
  VERIFY.result = nil
end

local function _diff_voice64(a, b)
  local diffs = 0
  local idxs = {}
  for k=1,64 do
    local av = (a and a[k]) or 0
    local bv = (b and b[k]) or 0
    if av ~= bv then
      diffs = diffs + 1
      idxs[#idxs+1] = k
    end
  end
  return diffs, idxs
end

local BANK_VERIFY_REPORT
local bank_send_queue = nil
local bank_send_queue_pos = 0
local bank_drill_voice = 0
local bank_sel_map = nil
local map_verify = false
local map_timeout = 2.5
local map_retries = 1
 = nil -- {ok=bool,total_diffs=int,voices={ {i=1,diffs=n,idxs={...}},... }, backend=..., ts=..., bank_id=... }

local function _bank_report_to_text(rep)
  if not rep then return "" end
  local t = {}
  t[#t+1] = string.format("Bank Verify Report (bank_id=%s) ok=%s total_diffs=%d backend=%s time=%s",

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Phase 7: Export report / Drilldown / Selected mapping send")
  if reaper.ImGui_Button(ctx, "Export Bank Verify Report (CSV)", 260, 0) then
    local ok, path = _export_bank_verify_report_csv(BANK_VERIFY_REPORT)
    if ok then reaper.MB("Exported:\n"..tostring(path), "Export CSV", 0) else reaper.MB("Export failed:\n"..tostring(path), "Export CSV", 0) end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Export Bank Verify Report (JSON)", 260, 0) then
    local ok, path = _export_bank_verify_report_json(BANK_VERIFY_REPORT)
    if ok then reaper.MB("Exported:\n"..tostring(path), "Export JSON", 0) else reaper.MB("Export failed:\n"..tostring(path), "Export JSON", 0) end
  end

  local _chg
  _chg, bank_drill_voice = reaper.ImGui_SliderInt(ctx, "Drilldown voice (0..47)", bank_drill_voice or 0, 0, 47)
  if BANK_VERIFY_REPORT and BANK_VERIFY_REPORT.target_voices and BANK_VERIFY_REPORT.dump_voices then
    local a64 = BANK_VERIFY_REPORT.target_voices[bank_drill_voice+1]
    local b64 = BANK_VERIFY_REPORT.dump_voices[bank_drill_voice+1]
    if a64 and b64 then
      local diffs = _diff_structured_voice(a64, b64)
      if diffs and #diffs > 0 then
        reaper.ImGui_Text(ctx, ("Param diffs: %d"):format(#diffs))
        if reaper.ImGui_BeginChild(ctx, "##bank_drill", 0, 140, true) then
          for i=1,math.min(#diffs, 200) do
            local d = diffs[i]
            reaper.ImGui_Text(ctx, ("%s: %s -> %s"):format(d.path, tostring(d.a), tostring(d.b)))
          end
          reaper.ImGui_EndChild(ctx)
        end
      else
        reaper.ImGui_Text(ctx, "No structured diffs (or VoiceMap unavailable).")
      end
    end
  end

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Selected voices -> Instrument mapping send (InstVoice write, robust)")
  local _c3
  _c3, map_verify = reaper.ImGui_Checkbox(ctx, "Verify each voice after send", map_verify or false)
  _c3, map_timeout = reaper.ImGui_SliderDouble(ctx, "Per-voice timeout (s)", map_timeout or (CAPTURE_CFG.t_inst or 2.5), 1.0, 10.0, "%.1f")
  _c3, map_retries = reaper.ImGui_SliderInt(ctx, "Per-voice retries", map_retries or (CAPTURE_CFG.retry_count_instvoice or 1), 0, 5)

  if last_rx_voicebank and last_rx_voicebank.voices then
    if not bank_sel_map then bank_sel_map = {} end
    if not bank_selected then bank_selected = {} end

    local sel_count = 0
    for vi=1,48 do if bank_selected[vi] then sel_count = sel_count + 1 end end
    reaper.ImGui_Text(ctx, ("Selected: %d"):format(sel_count))

    if reaper.ImGui_Button(ctx, "Send Selected (Mapped)", 220, 0) then
      if sel_count == 0 then
        reaper.MB("No voices selected.", "Send Selected", 0)
      else
        CAPTURE_CFG.t_inst = map_timeout; _ext_set("capture_timeout_instvoice", map_timeout)
        CAPTURE_CFG.retry_count_instvoice = map_retries; _ext_set("capture_retry_count_instvoice", map_retries)
        bank_send_queue = {}
        for vi=1,48 do
          if bank_selected[vi] then
            local slot = bank_sel_map[vi]
            if slot ~= nil and slot >= 0 and slot <= 7 then
              bank_send_queue[#bank_send_queue+1] = { voice_index=(vi-1), inst_no=slot, bytes=last_rx_voicebank.voices[vi], verify=map_verify }
            end
          end
        end
        bank_send_queue_pos = 1
        reaper.MB(("Queued %d voices for send."):format(#bank_send_queue), "Send Selected", 0)
      end
    end

    if reaper.ImGui_BeginChild(ctx, "##mapgrid", 0, 160, true) then
      for vi=1,48 do
        local checked = bank_selected[vi] or false
        local chg, newc = reaper.ImGui_Checkbox(ctx, ("V%02d##sel"):format(vi-1), checked)
        if chg then bank_selected[vi] = newc end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "->")
        reaper.ImGui_SameLine(ctx)
        local cur = bank_sel_map[vi] or -1
        local items = "skip\0inst0\0inst1\0inst2\0inst3\0inst4\0inst5\0inst6\0inst7\0\0"
        local chg2, idx = reaper.ImGui_Combo(ctx, ("##slot"..vi), (cur>=0 and cur+1 or 0), items)
        if chg2 then
          if idx == 0 then bank_sel_map[vi] = -1 else bank_sel_map[vi] = idx-1 end
        end
      end
      reaper.ImGui_EndChild(ctx)
    end
  else
    reaper.ImGui_Text(ctx, "Tip: capture/decode a bank dump first to enable mapping send.")
  end

    tostring(rep.bank_id), tostring(rep.ok), tonumber(rep.total_diffs or -1), tostring(rep.backend or "?"), tostring(rep.time_str or "?"))
  t[#t+1] = "VoiceIndex\tDiffBytes\tBytePositions(1..64)"
  for _,v in ipairs(rep.voices or {}) do
    if (v.diffs or 0) > 0 then
      t[#t+1] = string.format("%02d\t%d\t%s", v.i-1, v.diffs, table.concat(v.idxs or {}, ","))
    end
  end
  return table.concat(t, "\n")
end
local function _count_diffs(a, b)
  local diffs = 0
  local n = math.max(#(a or {}), #(b or {}))
  for i=1,n do
    local av = (a or {})[i]
    local bv = (b or {})[i]
    if av ~= bv then diffs = diffs + 1 end
  end
  return diffs
end

local function verify_tick(last_dump_msg)
  if not VERIFY.pending then return end

  -- Phase 9: handshake-aware behaviour (FB-01 manual)
  if Rx and Rx.state and Rx.state.last_handshake then
    if Rx.state.last_handshake == "CANCEL" then
      VERIFY.pending = false
      VERIFY.result = { ok=false, diffs=-1, err="CANCEL from device (memory protect / invalid target)" }
      return
    elseif Rx.state.last_handshake == "NAK" then
      -- on NAK, bump bulk delay and allow retry path to handle
      CAPTURE_CFG.bulk_delay_ms = (CAPTURE_CFG.bulk_delay_ms or 120) + 30
      _ext_set("bulk_delay_ms", tostring(CAPTURE_CFG.bulk_delay_ms))
    end
  end

  if _now() > VERIFY.deadline then
    VERIFY.pending = false
    VERIFY.result = { ok=false, diffs=-1, err="timeout waiting for dump" }
  else
    local m = last_dump_msg
    if m and m.bytes and #m.bytes > 0 then
      local bytes = m.bytes
      if VERIFY.kind == "instvoice" then
        if VoiceDump and VoiceDump.decode_inst_voice_from_sysex then
          local v, err = VoiceDump.decode_inst_voice_from_sysex(bytes)
          if v and v.voice_bytes then
            -- If we know expected sys_ch/inst_no, enforce match
            if (v.sys_ch == (VERIFY.sys_ch & 0x0F)) and (v.inst_no == (VERIFY.inst_no & 0x07)) then
              local diffs = _count_diffs(VERIFY.target, v.voice_bytes)
              VERIFY.pending = false
              VERIFY.result = { ok=(diffs==0), diffs=diffs, backend=m.backend }
            
              -- Phase 11.2: structured parameter diffs (param-name)
              if diffs ~= 0 and VoiceMap and VoiceMap.decode_voice_block and Schema and Schema.diff_structured then
                local a_voice, a_ops = VoiceMap.decode_voice_block(VERIFY.target)
                local b_voice, b_ops = VoiceMap.decode_voice_block(v.voice_bytes)
                if a_voice and b_voice then
                  local sa = { voice = a_voice, op1 = a_ops and a_ops[1], op2 = a_ops and a_ops[2], op3 = a_ops and a_ops[3], op4 = a_ops and a_ops[4] }
                  local sb = { voice = b_voice, op1 = b_ops and b_ops[1], op2 = b_ops and b_ops[2], op3 = b_ops and b_ops[3], op4 = b_ops and b_ops[4] }
                  VERIFY.result.diffs_struct = Schema.diff_structured(sa, sb)
                end
              end
end
          elseif err then
            -- ignore non-matching dumps; they might be config/bank etc.
          end
        else
          VERIFY.pending = false
          VERIFY.result = { ok=false, diffs=-1, err="VoiceDump missing" }
        end

      elseif VERIFY.kind == "config" then
        if ConfigDump and ConfigDump.decode_config_from_sysex and ConfigDump.diff_bytes then
          local cfg, err = ConfigDump.decode_config_from_sysex(bytes)
          if cfg and cfg.payload_bytes then
            local diffs_struct = (ConfigDump.diff_params and ConfigDump.diff_params(VERIFY.target, cfg.payload_bytes)) or nil
            local diffs_tbl = ConfigDump.diff_bytes(VERIFY.target, cfg.payload_bytes, 24)
            local ok = (diffs_struct and #diffs_struct==0) or (#diffs_tbl==0)
            VERIFY.pending = false
            VERIFY.result = { ok=ok, diffs=(diffs_struct and #diffs_struct) or #diffs_tbl, preview=diffs_tbl, backend=m.backend, diffs_struct=diffs_struct, checksum_ok=cfg.checksum_ok }
            _log_add("verify", "Config verify "..(ok and "OK" or ("FAIL diffs="..tostring((diffs_struct and #diffs_struct) or #diffs_tbl))), { backend=m.backend, checksum_ok=cfg.checksum_ok })
            -- Phase 26: export structured config diffs
            if (not ok) and diffs_struct and _export_param_diff_report and (LIBRARY and (LIBRARY.roundtrip_auto_export ~= false)) then
              _export_param_diff_report("config", diffs_struct, { sys_ch=CAPTURE_CFG.sys_ch or 0, ts=os.time() })
            end
          end
        else
          VERIFY.pending = false
          VERIFY.result = { ok=false, diffs=-1, err="ConfigDump module missing" }
        end
      end
    end
  end

  -- Mirror results into existing UI vars
  if not VERIFY.pending and VERIFY.result then
    if VERIFY.kind == "instvoice" then
      sv_verify_pending = false
      sv_verify_result = VERIFY.result
    else
      verify_stage = "done"
      verify_result = VERIFY.result
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        
          -- Phase 11.2: structured parameter diffs for bank (first N voices with diffs)
          if diffs ~= 0 and VoiceMap and VoiceMap.decode_voice_block and Schema and Schema.diff_structured then
            local out = {}
            local max_voices = 8
            local max_params = 300
            local voices_done = 0
            for i=1,48 do
              if voices_done >= max_voices then break end
              local a64 = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
              local b64 = (decoded.voices[i] and decoded.voices[i].voice64) or nil
              if a64 and b64 then
                local localdiff = 0
                for k=1,64 do if (a64[k] or 0) ~= (b64[k] or 0) then localdiff = localdiff + 1 end end
                if localdiff > 0 then
                  local av, aops = VoiceMap.decode_voice_block(a64)
                  local bv, bops = VoiceMap.decode_voice_block(b64)
                  if av and bv then
                    local sa = { voice=av, op1=aops and aops[1], op2=aops and aops[2], op3=aops and aops[3], op4=aops and aops[4] }
                    local sb = { voice=bv, op1=bops and bops[1], op2=bops and bops[2], op3=bops and bops[3], op4=bops and bops[4] }
                    local difflist = Schema.diff_structured(sa, sb)
                    for _,d in ipairs(difflist) do
                      out[#out+1] = { path = ("bank.voice%02d.%s"):format(i-1, d.path), a=d.a, b=d.b }
                      if #out >= max_params then break end
                    end
                    voices_done = voices_done + 1
                  end
                end
              end
              if #out >= max_params then break end
            end
            VERIFY.result.diffs_struct = out
          end
end

  end
  if VERIFY.result and (not VERIFY.pending) then native_harness_on_verify_done() end

end

-- =========================
-- Phase 3: One-button Auto-Capture (record -> request -> stop -> verify)
-- =========================

local function _capture_track_name()
  return "IFLS FB01 CAPTURE"
end

local function _capture_stop_recording()
  -- Prefer "Stop recording, save all" to avoid leaving unsaved takes around.
  -- Note: user prefs may still prompt; see Preferences > Recording.
  r.Main_OnCommand(40667, 0) -- Transport: Stop recording, save all
end

local function _capture_restore_arms()
  if not CAPTURE.prev_arms then return end
  for _,it in ipairs(CAPTURE.prev_arms) do
    if it.tr then r.SetMediaTrackInfo_Value(it.tr, "I_RECARM", it.arm or 0) end
  end
  CAPTURE.prev_arms = nil
end

local function _capture_collect_new_items(tr)
  local new_items = {}
  local cnt = r.CountTrackMediaItems(tr)
  for ii=0,cnt-1 do
    local it = r.GetTrackMediaItem(tr, ii)
    local ok, guid = r.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok and guid and (not CAPTURE.pre_item_guids or not CAPTURE.pre_item_guids[guid]) then
      new_items[#new_items+1] = it
    end
  end
  return new_items
end

local function _capture_find_or_create_archive_track()
  local proj = 0
  local name = _capture_archive_track_name()
  local n = r.CountTracks(proj)
  for i=0,n-1 do
    local tr = r.GetTrack(proj, i)
    local ok, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if ok and tr_name == name then
      return tr
    end
  end
  r.InsertTrackAtIndex(n, true)
  local tr = r.GetTrack(proj, n)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local function _capture_cleanup_items(mode)
  mode = tonumber(mode) or 0
  if mode == 0 then return end
  if CAPTURE.cleanup_done then return end
  if not CAPTURE.track then return end
  CAPTURE.new_items = CAPTURE.new_items or _capture_collect_new_items(CAPTURE.track)
  if not CAPTURE.new_items or #CAPTURE.new_items == 0 then CAPTURE.cleanup_done = true; return end

  if mode == 1 then
    -- delete
    for _,it in ipairs(CAPTURE.new_items) do
      r.DeleteTrackMediaItem(CAPTURE.track, it)
    end
  elseif mode == 2 then
    -- archive (move to archive track)
    local trA = _capture_find_or_create_archive_track()
    for _,it in ipairs(CAPTURE.new_items) do
      r.MoveMediaItemToTrack(it, trA)
    end
  end
  CAPTURE.cleanup_done = true
end

local function _capture_find_or_create_track()
  local proj = 0
  local name = _capture_track_name()
  local n = r.CountTracks(proj)
  for i=0,n-1 do
    local tr = r.GetTrack(proj, i)
    local ok, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if ok and tr_name == name then
      return tr, i
    end
  end
  -- create new track at end
  r.InsertTrackAtIndex(n, true)
  local tr = r.GetTrack(proj, n)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr, n
end

local function _capture_configure_track(tr, pref_in)
  -- Arm + record MIDI input (all devices, all channels)
  -- I_RECINPUT: 4096 enables MIDI; next 6 bits physical input (63=all), low 5 bits channel (0=all)
  -- => 4096 + (63<<5) + 0 = 6112
  r.SetMediaTrackInfo_Value(tr, "I_RECMON", 0)
  r.SetMediaTrackInfo_Value(tr, "I_RECMODE", 0)   -- record input
  -- I_RECINPUT encoding for MIDI:
  -- 4096 enables MIDI recording.
  -- We use: 4096 + (device<<5) + channel, where device 0..63 (63=all), channel 0=all.
  local dev = 63
  local n = r.GetNumMIDIInputs() or 0
  if pref_in == -2 then
    if n == 1 then dev = 0 else dev = 63 end
  elseif pref_in == -1 or pref_in == nil then
    dev = 63
  elseif tonumber(pref_in) and tonumber(pref_in) >= 0 then
    dev = tonumber(pref_in)
  end
  local recinput = 4096 + (dev << 5) + 0
  r.SetMediaTrackInfo_Value(tr, "I_RECINPUT", recinput)
  r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
end

local function _capture_unarm_others_keep_capture(tr_capture)
  local proj = 0
  local n = r.CountTracks(proj)
  CAPTURE.prev_arms = {}
  for i=0,n-1 do
    local tr = r.GetTrack(proj, i)
    local arm = r.GetMediaTrackInfo_Value(tr, "I_RECARM")
    CAPTURE.prev_arms[#CAPTURE.prev_arms+1] = { tr=tr, arm=arm }
    if tr ~= tr_capture then
      r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
    end
  end
  r.SetMediaTrackInfo_Value(tr_capture, "I_RECARM", 1)
end

local function _capture_get_last_sysex_on_track(tr)
  -- Returns {msg=string_without_F0F7, ppqpos=number} of the newest sysex event found, or nil
  local item_cnt = r.CountTrackMediaItems(tr)
  if item_cnt == 0 then return nil end

  -- newest item by end position
  local newest_item = nil
  local newest_end = -1
  for i=0,item_cnt-1 do
    local it = r.GetTrackMediaItem(tr, i)
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    local it_end = pos + len
    if it_end > newest_end then newest_end = it_end; newest_item = it end
  end
  if not newest_item then return nil end
  local take = r.GetActiveTake(newest_item)
  if not take or not r.TakeIsMIDI(take) then return nil end

  local _, _, textsyx = r.MIDI_CountEvts(take)
  if (textsyx or 0) == 0 then return nil end

  -- Scan from end for speed
  for idx=(textsyx-1),0,-1 do
    local ok, selected, muted, ppqpos, typ, msg = r.MIDI_GetTextSysexEvt(take, idx, false, false, 0, 0, "")
    if ok and typ == -1 and msg and #msg > 8 then
      return { msg=msg, ppqpos=ppqpos }
    end
  end
  return nil
end

-- Phase 9: collect ALL SysEx events from newly created capture items (TAKE backend)
local function _collect_sysex_from_items(items)
  local out = {}
  if not items then return out end
  for _, it in ipairs(items) do
    local take = r.GetActiveTake(it)
    if take and r.TakeIsMIDI(take) then
      local _, _, _, nsyx = r.MIDI_CountEvts(take)
      for idx=0, nsyx-1 do
        local ok, _, _, _, typ, msg = r.MIDI_GetTextSysexEvt(take, idx, false, false, 0, 0, "")
        if ok and typ == -1 and msg and #msg > 0 then
          local bytes = {}
          for i=1,#msg do bytes[#bytes+1] = msg:byte(i) end
          -- filter for Yamaha FB-01 group if possible
          if bytes[1] == 0xF0 and bytes[2] == 0x43 and bytes[3] == 0x75 then
            out[#out+1] = bytes
          end
        end
      end
    end
  end
  return out
end

local function capture_start(kind, send_fn, opts)
  if CAPTURE.active then return end
  opts = opts or {}
  CAPTURE.kind = kind
  CAPTURE.send_fn = send_fn
  CAPTURE.send_opts = opts
  local k = tostring(kind or "")
  local default_t = CAPTURE_CFG.t_config
  if k == "instvoice" then default_t = CAPTURE_CFG.t_instvoice end
  if k == "bank" then default_t = CAPTURE_CFG.t_bank end
  CAPTURE.timeout = tonumber(opts.timeout) or default_t
  CAPTURE.started = _now()
  CAPTURE.deadline = CAPTURE.started + CAPTURE.timeout
  -- Phase 5: retries
  local defr = CAPTURE_CFG.retry_count_config
  if k == "instvoice" then defr = CAPTURE_CFG.retry_count_instvoice end
  if k == "bank" then defr = CAPTURE_CFG.retry_count_bank end
  CAPTURE.retries_left = tonumber(opts.retries) or defr or 0
  CAPTURE.attempt = 0
  , next_send_ts = 0
  CAPTURE.bank_verify_target = opts.bank_verify_target

  CAPTURE.seen_sysex = false
  CAPTURE.err = nil
  CAPTURE.cleanup_done = false
  CAPTURE.pre_item_guids = nil
  CAPTURE.new_items = nil
  CAPTURE.active = true

local tr, idx = _capture_find_or_create_track()
-- snapshot existing items for cleanup diff
CAPTURE.pre_item_guids = {}
local cnt_items = r.CountTrackMediaItems(tr)
for ii=0,cnt_items-1 do
  local it = r.GetTrackMediaItem(tr, ii)
  local ok, guid = r.GetSetMediaItemInfo_String(it, "GUID", "", false)
  if ok and guid then CAPTURE.pre_item_guids[guid] = true end
end
CAPTURE.track, CAPTURE.track_idx = tr, idx
  _capture_configure_track(tr, CAPTURE_CFG.pref_midi_in)
  _capture_unarm_others_keep_capture(tr)

  -- Start recording if not already
  local ps = r.GetPlayState()
  if (ps & 4) == 0 then
    r.Main_OnCommand(1013, 0) -- Transport: Record
  end

  if send_fn then send_fn() end
end

local function capture_tick()
  -- Phase 5: process bank send queue (selected voices)
  if bank_send_queue and not CAPTURE.active then
    if bank_send_queue.idx > #bank_send_queue.list then
      bank_send_queue = nil
    else
      local v64 = bank_send_queue.list[bank_send_queue.idx]
      local _sys = bank_send_queue.sys
      local _inst = bank_send_queue.inst
      local function _send_one()
        local msg = VoiceDump.build_inst_voice_sysex(_sys, _inst, v64)
        if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
        if bank_send_verify then
          verify_start("instvoice", v64, { sys_ch=_sys, inst_no=_inst, timeout=CAPTURE_CFG.t_instvoice })
          enqueue_sysex(Syx.dump_inst_voice(_sys, _inst))
        end
      end
      if bank_send_verify then
        capture_start("instvoice", _send_one, { timeout = CAPTURE_CFG.t_instvoice, retries = CAPTURE_CFG.retry_count_instvoice })
      else
        _send_one()
      end
      bank_send_queue.idx = bank_send_queue.idx + 1
      bank_send_queue.inst = (bank_send_queue.inst + 1) % 8
    end
  end
  if not CAPTURE.active then return end

  -- Bank capture: stop when a bank dump is present and decodable
  if CAPTURE.kind == "bank" then
    if _now() > CAPTURE.deadline then
      CAPTURE.err = "capture timeout"
      _capture_stop_recording()
      CAPTURE.active = false
      CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
      _capture_restore_arms()
      return
    end

    local syx = _capture_get_last_sysex_on_track(CAPTURE.track)
    if syx then
      -- refresh RX state from take backend and decode
      if Rx and Rx.poll_take_backend then Rx.poll_take_backend() end

  -- Phase 7: send queue tick (Selected -> Instrument mapping)
  if bank_send_queue and bank_send_queue_pos and bank_send_queue_pos >= 1 and bank_send_queue_pos <= #bank_send_queue then
    local item = bank_send_queue[bank_send_queue_pos]
    local syx = VoiceDump.build_inst_voice_sysex(sysch or 0, item.inst_no, item.bytes)
    send_sysex(bytes_to_string(syx))
    if item.verify then
      CAPTURE.retries_left = CAPTURE_CFG.retry_count_instvoice or 1
      verify_start("instvoice", item.bytes, { timeout = (CAPTURE_CFG.t_inst or 2.5), sys_ch = (sysch or 0), inst_no = item.inst_no })
      enqueue_sysex(Syx.dump_inst_voice(sysch or 0, item.inst_no))
    end
    bank_send_queue_pos = bank_send_queue_pos + 1
    if bank_send_queue_pos > #bank_send_queue then
      bank_send_queue = nil
      bank_send_queue_pos = 0
    end
  end
      local last = Rx and Rx.get_last_dump and Rx.get_last_dump() or nil
      local decoded, err = decode_bank_any(last and last.bytes or syx)
      if decoded then
        bank_import = decoded.res
        bank_import_layout = decoded.layout
        last_rx_voicebank = decoded.res
        last_rx_voicebank_raw = (last and last.bytes) or syx
        bank_import_err = nil
        bank_sel = {}
        for i=1,48 do bank_sel[i]=true end
        bank_capture_status = string.format("Captured bank dump OK (layout=%s, voices=%d).", tostring(decoded.layout), #(decoded.voices or {}))
      else
        bank_import_err = err
        bank_capture_status = "Captured dump but decode failed: " .. tostring(err)
      end

      _capture_stop_recording()
      CAPTURE.active = false
      CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
      _capture_restore_arms()

      -- cleanup after successful decode
      if decoded then _capture_cleanup_items(_cleanup_mode_for_kind(CAPTURE.kind)) end

-- Phase 8: minimal JSON encode/decode (safe; no load())
local function _json_escape(s)
  return s:gsub('\\','\\\\'):gsub('"','\\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
end

local function _json_encode(v)
  local t = type(v)
  if v == nil then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return tostring(v)
  end
  if t == "string" then return '"' .. _json_escape(v) .. '"' end
  if t == "table" then
    local is_arr = true
    local n = 0
    for k,_ in pairs(v) do
      if type(k) ~= "number" then is_arr=false break end
      if k>n then n=k end
    end
    if is_arr then
      local parts = {}
      for i=1,n do parts[#parts+1] = _json_encode(v[i]) end
      return "["..table.concat(parts,",").."]"
    else
      local parts={}
      for k,val in pairs(v) do
        parts[#parts+1] = _json_encode(tostring(k)) .. ":" .. _json_encode(val)
      end
      return "{"..table.concat(parts,",").."}"
    end
  end
  return "null"
end

local function _json_decode_min(s)
  local i=1
  local function skip()
    while true do
      local c=s:sub(i,i)
      if c=="" then return end
      if c:match("%s") then i=i+1 else return end
    end
  end
  local function parse_value()
    skip()
    local c=s:sub(i,i)
    if c=='"' then
      i=i+1
      local out=""
      while true do
        local ch=s:sub(i,i); if ch=="" then break end
        if ch=='"' then i=i+1; break end
        if ch=='\\' then
          local n=s:sub(i+1,i+1)
          if n=='n' then out=out.."\n"; i=i+2
          elseif n=='r' then out=out.."\r"; i=i+2
          elseif n=='t' then out=out.."\t"; i=i+2
          elseif n=='"' then out=out..'"'; i=i+2
          elseif n=='\\' then out=out.."\\"; i=i+2
          else out=out..n; i=i+2 end
        else
          out=out..ch; i=i+1
        end
      end
      return out
    elseif c=='{' then
      i=i+1
      local obj={}
      skip()
      if s:sub(i,i)=='}' then i=i+1; return obj end
      while true do
        local k=parse_value(); skip()
        if s:sub(i,i)~=':' then return nil end
        i=i+1
        local v=parse_value()
        obj[k]=v
        skip()
        local d=s:sub(i,i)
        if d==',' then i=i+1
        elseif d=='}' then i=i+1; break
        else break end
      end
      return obj
    elseif c=='[' then
      i=i+1
      local arr={}
      skip()
      if s:sub(i,i)==']' then i=i+1; return arr end
      local idx=1
      while true do
        local v=parse_value()
        arr[idx]=v; idx=idx+1
        skip()
        local d=s:sub(i,i)
        if d==',' then i=i+1
        elseif d==']' then i=i+1; break
        else break end
      end
      return arr
    else
      local lit=s:sub(i)
      if lit:sub(1,4)=="true" then i=i+4; return true end
      if lit:sub(1,5)=="false" then i=i+5; return false end
      if lit:sub(1,4)=="null" then i=i+4; return nil end
      local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
      if num and #num>0 then i=i+#num; return tonumber(num) end
      return nil
    end
  end
  return parse_value()
end
      return
    end

    return
  end

  -- InstVoice/Config capture: record until verify completes or timeout.
  if VERIFY and VERIFY.result and not VERIFY.pending then
    _capture_stop_recording()
    CAPTURE.active = false
    CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
    _capture_restore_arms()
    if VERIFY.result and VERIFY.result.ok then
      _capture_cleanup_items(_cleanup_mode_for_kind(CAPTURE.kind))
    end
    return
  end

  -- If not recording anymore, clean up
  local ps = r.GetPlayState()
  if (ps & 4) == 0 then
    CAPTURE.active = false
    CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
    _capture_restore_arms()
    return
  end

  if _now() > CAPTURE.deadline then
    CAPTURE.err = "capture timeout"
    _capture_stop_recording()
    CAPTURE.active = false
    CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
    _capture_restore_arms()
    return
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local bank_inst_target = 0
local bank_send_verify = false
local bank_send_queue = nil -- {list={voice64,...}, idx=1, inst=0, sys=0, retries=0}

-- B2.28: Single-Voice SYX import + optional send/verify
local sv_import_path = ""
local sv_import = nil -- {sys_ch, inst_no, voice_bytes(64)}
local sv_import_err = nil
local sv_send_inst = 0
local sv_auto_verify = true
local sv_verify_pending = false
local sv_verify_result = nil -- {ok=bool, diffs=int}

-- B2.23: Config dump state + export/verify
local last_rx_config = nil
local last_rx_config_raw = nil
local cfg_A = nil
local cfg_B = nil
local cfg_slot = 0
local pending_capture = nil
local cfg_export_dir = root .. "/../IFLS_FB01_Dumps"

-- B2.25: Voice/bank export state
local voice_export_dir = root .. "/../IFLS_FB01_Patches"

-- B2.27: Bank import + extract + single-voice SYX export
local bank_import_path = ""
local bank_import = nil
local bank_import_err = nil
local bank_import_layout = nil
local bank_sel = {}
local bank_request_id = 0
local bank_capture_status = ""

local bank_export_mode = 0 -- 0=payload bin, 1=json, 2=single-voice syx
local bank_inst_target = 0
local bank_send_verify = false
local bank_send_queue = nil -- {list={voice64,...}, idx=1, inst=0, sys=0, retries=0}

local last_rx_voice = nil
local last_rx_voice_raw = nil
local last_rx_voicebank = nil
local last_rx_voicebank_raw = nil
local req_voice_bank = 0
local req_inst_voice = 0

-- B2.24: TrueBulk Send + Verify (Config)
local bulk_syx_path = ""
local bulk_bytes = nil
local bulk_cfg = nil -- decoded config (if applicable)
local bulk_err = nil
local verify_stage = nil -- "await_ack" -> "await_dump" -> "done"
local verify_result = nil -- {ok=bool, diffs=int}
local verify_target = nil -- payload bytes to compare against

-- B2.22: Event List Builder state
local event_items = {} -- {type="cc"/"note"/..., fields...}
local ev_key = 60
local ev_frac = 0
local ev_vel = 100
local ev_cc = 1
local ev_ccval = 0
local ev_prog = 0
local ev_at = 0
local ev_py = 0
local ev_px = 0
local ev_pa = 0
local ev_dd = 0
local ev_y = 0
local ev_x = 0
local ev_yy = 0
local ev_xx = 0
-- ===== Schema-driven UI helpers (Voice + OP EG) =====
local function clamp(v, lo, hi)
  v = math.floor(tonumber(v) or 0)
  if v < lo then return lo end

local function encode_ui_value(it, ui_val)
  if it == nil then return ui_val end

local function decode_bank_any(bytes)
  if not bytes then return nil, "no bytes" end

  -- Layout A: ifls_fb01_bank.lua (nibble payload detection)
  if BankA and BankA.decode_voice_bank_from_sysex then
    local resA, errA = BankA.decode_voice_bank_from_sysex(bytes)
    if resA and resA.voices and #resA.voices == 48 then
      return {layout="bankA", res=resA, voices=resA.voices}, nil
    end
  end

  -- Layout B: ifls_fb01_voicebank.lua (block/marker style)
  if VoiceBank and VoiceBank.decode_voicebank_from_sysex then
    local resB, errB = VoiceBank.decode_voicebank_from_sysex(bytes)
    if resB and resB.voices and #resB.voices == 48 then
      return {layout="voicebank", res=resB, voices=resB.voices}, nil
    end
  end

  return nil, "could not decode bank (unknown layout or invalid sysex)"
end

local function read_file_bytes_bank(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open file" end
  local data = f:read("*all")
  f:close()
  local t={}
  for i=1,#data do t[#t+1]=string.byte(data,i) end
  return t
end

local function apply_bank_voice_to_ui(voice_index)
  if not bank_voice_bytes or not bank_voice_bytes[voice_index+1] then
    bank_apply_status = "No voice bytes cached (re-import bank)."
    return
  end
  local bytes = bank_voice_bytes[voice_index+1]
  local vvals, ovals = VoiceMap.decode_voice_block(bytes)

  for k,val in pairs(vvals) do
    voice_vals[k] = val
  end
  for op=1,4 do
    for k,val in pairs(ovals[op]) do
      op_vals[op][k] = val
    end
  end

  bank_apply_status = "Applied voice " .. tostring(voice_index) .. " to UI (decoded)."
end

-- B2.9: Configuration parameter mapping (subset)

local function _contains(hay, needle)
  if not hay or not needle then return false end
  hay = string.lower(tostring(hay))
  needle = string.lower(tostring(needle))
  return string.find(hay, needle, 1, true) ~= nil
end

local function build_param_catalog()
  local items = {}
  local V = VoiceMap.VOICE
  local voice_items = {
    {key="voice.algorithm", name="Algorithm", get=function() return voice_vals[V.algorithm] or 0 end, range="0..7", enc="bits"},
    {key="voice.feedback", name="Feedback", get=function() return voice_vals[V.feedback] or 0 end, range="0..6", enc="bits"},
    {key="voice.transpose", name="Transpose", get=function() return voice_vals[V.transpose] or 0 end, range="0..127", enc="u7"},
    {key="voice.poly_mode", name="Poly Mode", get=function() return voice_vals[V.poly_mode] or 0 end, range="0..1", enc="bit"},
    {key="voice.portamento_time", name="Portamento Time", get=function() return voice_vals[V.portamento_time] or 0 end, range="0..127", enc="u7"},
    {key="voice.pitchbend_range", name="Pitch Bend Range", get=function() return voice_vals[V.pitchbend_range] or 0 end, range="0..12", enc="bits"},
    {key="voice.controller_set", name="Controller Set", get=function() return voice_vals[V.controller_set] or 0 end, range="0..4", enc="bits"},
    {key="voice.lfo_speed", name="LFO Speed", get=function() return voice_vals[V.lfo_speed] or 0 end, range="0..127", enc="u7"},
    {key="voice.lfo_wave", name="LFO Wave", get=function() return voice_vals[V.lfo_wave] or 0 end, range="0..3", enc="bits"},
    {key="voice.lfo_load", name="LFO Load", get=function() return voice_vals[V.lfo_load] or 0 end, range="0..1", enc="bit"},
    {key="voice.lfo_key_sync", name="LFO Key Sync", get=function() return voice_vals[V.lfo_key_sync] or 0 end, range="0..1", enc="bit"},
    {key="voice.lfo_amd", name="LFO AMD", get=function() return voice_vals[V.lfo_amd] or 0 end, range="0..127", enc="u7"},
    {key="voice.lfo_ams", name="LFO AMS", get=function() return voice_vals[V.lfo_ams] or 0 end, range="0..3", enc="bits"},
    {key="voice.lfo_pmd", name="LFO PMD", get=function() return voice_vals[V.lfo_pmd] or 0 end, range="0..127", enc="u7"},
    {key="voice.lfo_pms", name="LFO PMS", get=function() return voice_vals[V.lfo_pms] or 0 end, range="0..7", enc="bits"},
    {key="voice.op1_enable", name="OP1 Enable", get=function() return voice_vals[V.op1_enable] or 0 end, range="0..1", enc="bit"},
    {key="voice.op2_enable", name="OP2 Enable", get=function() return voice_vals[V.op2_enable] or 0 end, range="0..1", enc="bit"},
    {key="voice.op3_enable", name="OP3 Enable", get=function() return voice_vals[V.op3_enable] or 0 end, range="0..1", enc="bit"},
    {key="voice.op4_enable", name="OP4 Enable", get=function() return voice_vals[V.op4_enable] or 0 end, range="0..1", enc="bit"},
  }
  for i=1,#voice_items do voice_items[i].scope="voice"; items[#items+1]=voice_items[i] end

  local O = VoiceMap.OP
  local op_fields = {
    {suffix="volume",          name="TL/Volume",        idx=O.volume,          range="0..127", enc="u7"},
    {suffix="level_curb",      name="Level Curb Type",  idx=O.level_curb,      range="0..3",   enc="bits"},
    {suffix="level_velocity",  name="Level Velocity",   idx=O.level_velocity,  range="0..7",   enc="bits"},
    {suffix="level_depth",     name="Level Depth",      idx=O.level_depth,     range="0..15",  enc="nib"},
    {suffix="adjust",          name="Adjust",           idx=O.adjust,          range="0..15",  enc="nib"},
    {suffix="fine",            name="Fine",             idx=O.fine,            range="0..7",   enc="bits"},
    {suffix="coarse",          name="Coarse",           idx=O.coarse,          range="0..15",  enc="nib"},
    {suffix="rate_depth",      name="Rate Depth",       idx=O.rate_depth,      range="0..3",   enc="bits"},
    {suffix="attack",          name="Attack (AR)",      idx=O.attack,          range="0..31",  enc="bits"},
    {suffix="modulator",       name="Modulator Flag",   idx=O.modulator,       range="0..1",   enc="bit"},
    {suffix="attack_velocity", name="Attack Velocity",  idx=O.attack_velocity, range="0..3",   enc="bits"},
    {suffix="decay1",          name="Decay1 (D1R)",     idx=O.decay1,          range="0..31",  enc="bits"},
    {suffix="multiple",        name="Multiple",         idx=O.multiple,        range="0..3",   enc="bits"},
    {suffix="decay2",          name="Decay2 (D2R)",     idx=O.decay2,          range="0..31",  enc="bits"},
    {suffix="sustain",         name="Sustain (SL)",     idx=O.sustain,         range="0..15",  enc="nib"},
    {suffix="release",         name="Release (RR)",     idx=O.release,         range="0..15",  enc="nib"},
  }
  for op=1,4 do
    for i=1,#op_fields do
      local f = op_fields[i]
      items[#items+1] = {scope="op", key=string.format("op%d.%s",op,f.suffix), name=string.format("OP%d %s",op,f.name),
                         range=f.range, enc=f.enc, get=function() return (op_vals[op] and op_vals[op][f.idx]) or 0 end}
    end
  end

  for i=1,#CONF_PARAMS do
    local p = CONF_PARAMS[i]
    items[#items+1] = {scope="conf", key="conf."..tostring(p.key), name="Conf "..tostring(p.name),
                       range=string.format("%d..%d",p.min,p.max), enc="u7", extra=string.format("pp=%d",p.no),
                       get=function() return conf_vals[p.key] or 0 end}
  end
  return items
end

local CONF_PARAMS = {
  {no=0,  key="notes",      name="Number of notes",       min=0,   max=8},
  {no=1,  key="midi_ch",    name="MIDI channel (0-15)",   min=0,   max=15},
  {no=2,  key="key_hi",     name="Key limit (high)",     min=0,   max=127},
  {no=3,  key="key_lo",     name="Key limit (low)",      min=0,   max=127},
  {no=4,  key="voice_bank", name="Voice bank",           min=0,   max=6},
  {no=5,  key="voice_no",   name="Voice number",         min=0,   max=47},
  {no=6,  key="detune",     name="Detune",               min=0,   max=127},
  {no=7,  key="octave2",    name="Octave +2",            min=0,   max=4},
  {no=8,  key="out_level",  name="Output level",         min=0,   max=127},
  {no=9,  key="pan",        name="Pan",                  min=0,   max=127},
  {no=10, key="lfo_enable", name="LFO enable",           min=0,   max=1},
  {no=11, key="porta_time", name="Portamento time",      min=0,   max=127},
  {no=12, key="pb_range",   name="Pitch bend range",     min=0,   max=12},
  {no=13, key="mono_poly",  name="Mono/Poly",            min=0,   max=1},
  {no=14, key="pmd_ctrl",   name="PMD controller",       min=0,   max=4},
  {no=16, key="lfo_speed",  name="LFO speed",            min=0,   max=127},
  {no=17, key="amd",        name="AMD",                  min=0,   max=127},
  {no=18, key="pmd",        name="PMD",                  min=0,   max=127},
  {no=19, key="lfo_wave",   name="LFO waveform",         min=0,   max=3},
  {no=20, key="lfo_load",   name="LFO load enable",      min=0,   max=1},
  {no=21, key="lfo_sync",   name="LFO sync",             min=0,   max=1},
  {no=22, key="ams",        name="AMS",                  min=0,   max=3},
  {no=23, key="pms",        name="PMS",                  min=0,   max=7},
}

local function build_conf_param_stream(only_diff)
  local msgs = {}
  local delay_ms = slow_chunk and 50 or nil
  if not last_sent_conf then last_sent_conf = {} end
  for i=1,#CONF_PARAMS do
    local p = CONF_PARAMS[i]
    local v = conf_vals[p.key] or 0
    v = math.max(p.min, math.min(p.max, v))
    local prev = last_sent_conf[p.key]
    if (not only_diff) or (prev == nil) or (prev ~= v) then
      msgs[#msgs+1] = {msg = Syx.conf_param_inst(sys_ch, inst_no, p.no, v), delay_ms = delay_ms}
      last_sent_conf[p.key] = v
    end
  end
  return msgs
end

local function build_eventlist_from_voice_bytes(bytes, only_diff)
  local events = {}
  if only_diff and last_sent_voice_bytes then
    for p=0,63 do
      local v = (bytes[p+1] or 0) & 0x7F
      local prev = (last_sent_voice_bytes[p+1] or -1)
      if v ~= prev then
        events[#events+1] = Syx.ev_inst_param2(sys_ch, (0x40 + p) & 0x7F, v)
      end
    end
  else
    for p=0,63 do
      local v = (bytes[p+1] or 0) & 0x7F
      events[#events+1] = Syx.ev_inst_param2(sys_ch, (0x40 + p) & 0x7F, v)
    end
  end
  return events
end

-- B2.7: Encode current UI state to 64-byte voice block and send diff/full via queue

local function refresh_ui_from_current_block()
  if not current_voice_block then return end
  local v, o, meta = VoiceMap.decode_voice_block(current_voice_block)
  voice_vals = v or voice_vals
  op_vals = o or op_vals
  if meta then
    voice_name = meta.name or voice_name
    voice_user_code = meta.user_code or voice_user_code
    voice_breath = meta.breath or voice_breath
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function encode_current_ui_voice_block()
  local op_list = {op_vals[1], op_vals[2], op_vals[3], op_vals[4]}
  return VoiceMap.encode_voice_block(voice_vals, op_list)
end

local function build_param_stream_from_bytes(bytes, only_diff)
  local msgs = {}
  local function make_msg(p, v)
    if addr_mode == 1 then
      return Syx.voice_param_inst(sys_ch, inst_no, p, v)
    else
      return Syx.voice_param(sys_ch, midi_ch, p, v)
    end
  end
  local delay_ms = slow_chunk and 50 or nil
  if only_diff and last_sent_voice_bytes then
    for p=0,63 do
      local v = (bytes[p+1] or 0) & 0x7F
      local prev = (last_sent_voice_bytes[p+1] or -1)
      if v ~= prev then
        msgs[#msgs+1] = {msg = make_msg(p, v), delay_ms = delay_ms}
      end
    end
  else
    for p=0,63 do
      local v = (bytes[p+1] or 0) & 0x7F
      msgs[#msgs+1] = {msg = make_msg(p, v), delay_ms = delay_ms}
    end
  end
  return msgs
end
    end
  else
    for p=0,63 do
      local v = (bytes[p+1] or 0) & 0x7F
      msgs[#msgs+1] = Syx.voice_param(sys_ch, midi_ch, p, v)
    end
  end
  return msgs
end

local function build_voice_param_stream(voice_index)
  if not bank_voice_bytes or not bank_voice_bytes[voice_index+1] then return nil end
  local bytes = bank_voice_bytes[voice_index+1]
  local msgs = {}
  for p=0,63 do
    local v = (bytes[p+1] or 0) & 0x7F
    -- use existing voice param sender (by current MIDI channel)
    -- apply_voice_param already exists in editor; it sends a sysex immediately.
    -- Here we build the raw message for queueing:
    msgs[#msgs+1] = Syx.voice_param(sys_ch, midi_ch, p, v)
  end
  return msgs
end

  local bytes, err = read_file_bytes_bank(file)
  if not bytes then
    dump_status = "Read failed: " .. tostring(err)
    return
  end
  local res, err2 = Bank.decode_voice_bank_from_filebytes(bytes)
              bank_source_file = file
  if not res then
    dump_status = "Decode failed: " .. tostring(err2)
    return
  end
  bank_name = res.bank_name
  bank_checksum_ok = res.checksum_ok
              bank_template = res.template
  bank_names = {}
              bank_voice_bytes = {}
              for i=1,#res.voices do
                bank_names[i] = res.voices[i].name
                -- cache 64 bytes of voice data (as delivered by bank decoder)
                bank_voice_bytes[i] = res.voices[i].bytes
              end
  dump_status = "Imported bank: " .. tostring(bank_name) .. " (checksum " .. tostring(bank_checksum_ok) .. ")"
end
  if it.encoding == "s7" then
    -- signed 7-bit two's complement: -64..63 -> 0..127
    local v = clamp(ui_val, it.ui_min or -64, it.ui_max or 63)
    if v < 0 then v = v + 128 end
    return v & 0x7F
  elseif it.encoding == "offset" then
    local off = it.offset or 0
    local v = clamp(ui_val, it.ui_min or (it.min or 0), it.ui_max or (it.max or 127))
    return clamp(v + off, it.min or 0, it.max or 127)
  end
  return clamp(ui_val, it.min or 0, it.max or 127)
end
  if v > hi then return hi end
  return v
end

local send_on_release_always_once = true
local snapshot_preview_while_dragging = false

local autosend_schema_full_on_exit = false
local schema_tab_active = false
local schema_tab_was_active = false
local autosend_last_t = 0.0
local function rate_limited_send(msg, interval_ms)
  local t = reaper.time_precise()
  if (t - autosend_last_t) * 1000.0 >= (interval_ms or 140) then
    autosend_last_t = t
    send_sysex(msg)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function hook_autosave_autosend(msg, is_deactivate)
  if autosave_slot then autosave_deb:request() end
  if not autosend then return end

  if autosend_mode == 0 then
    if snapshot_preview_while_dragging and not is_deactivate then
      rate_limited_send(msg, 140)
    end
    if is_deactivate then
      autosend_deb:request()
    end
    return
  end

  -- per-change
  if not is_deactivate then
    if not live_send_per_change then
      rate_limited_send(msg, 140)
    end
  else
    if send_on_release_always_once then
      send_sysex(msg)
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function fullspec_voice_slider(it)
  local p = tonumber(it.param) or 0
  local label = it.label or ("Param "..tostring(p))
  local v = voice_vals[p] or 0
  local changed, nv = r.ImGui_SliderInt(ctx, label .. "##fs_"..tostring(p), v, 0, 127)
  if changed then
    apply_voice_param(p, nv)
  end
  if it.bits then
    local b = voice_vals[p] or 0
    local first=true
    for k, rr in pairs(it.bits) do
      local hi, lo = rr[1], rr[2]
      local mask = ((1 << (hi-lo+1)) - 1) << lo
      local cur = (b & mask) >> lo
      if not first then r.ImGui_SameLine(ctx) end
      first=false
      local ch2, newv = r.ImGui_SliderInt(ctx, k.."##fsbf_"..tostring(p)..k, cur, 0, (1 << (hi-lo+1)) - 1)
      if ch2 then
        local bb = voice_vals[p] or 0
        bb = (bb & (~mask)) | ((newv << lo) & mask)
        apply_voice_param(p, bb)
      end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function schema_slider_voice(it)
  local lo = it.ui_min or it.min or 0
              local hi = it.ui_max or it.max or 127
  local v  = clamp(voice_vals[it.param] or 0, lo, hi)

  local changed, newv = r.ImGui_SliderInt(ctx, it.name, v, lo, hi)
  local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)

  if changed then
    newv = clamp(newv, lo, hi)
    voice_vals[it.param] = newv
    local msg = Syx.voice_param(sysch, inst, it.param, newv)
    if live_send_per_change then send_sysex(msg) end
    hook_autosave_autosend(msg, deact)
  elseif deact then
    local msg = Syx.voice_param(sysch, inst, it.param, v)
    hook_autosave_autosend(msg, true)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function schema_slider_op(op_id, it)
  local lo = it.ui_min or it.min or 0
              local hi = it.ui_max or it.max or 127
  local v  = clamp(op_vals[op_id+1][it.param] or 0, lo, hi)

  local label = string.format("OP%d %s", op_id+1, it.name)
  local changed, newv = r.ImGui_SliderInt(ctx, label, v, lo, hi)
  local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)

  if changed then
    newv = clamp(newv, lo, hi)
    op_vals[op_id+1][it.param] = newv
    local msg = Syx.operator_param(sysch, inst, op_id, it.param, newv)
    if live_send_per_change then send_sysex(msg) end
    hook_autosave_autosend(msg, deact)
  elseif deact then
    local msg = Syx.operator_param(sysch, inst, op_id, it.param, v)
    hook_autosave_autosend(msg, true)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

-- @description IFLS FB-01 Sound Editor (MVP)
-- @version 0.90.0
-- @author IFLS
-- @about
--   Native FB-01 editor for REAPER using ReaImGui + SWS SysEx send.
--   MVP: live parameter change for Voice + Operators + Instruments, plus dump-request buttons.
--
-- Requirements:
--   - ReaImGui
--   - SWS (SNM_SendSysEx)
--
-- Data:
--   - Workbench/FB01/Data/fb01_params_mvp.json

-- deps
if not r.ImGui_CreateContext then
  r.MB("ReaImGui not found. Install ReaImGui first.", "FB-01 Sound Editor", 0)
  return
end
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "FB-01 Sound Editor", 0)
  return
end
Syx = dofile(root .. "/Core/ifls_fb01_sysex.lua")
local ParamSchema = dofile(root .. "/Core/fb01_parameter_schema.lua")
local BulkNative = dofile(root .. "/Core/ifls_fb01_bulk_native.lua")
Rx = dofile(root .. "/Core/ifls_fb01_rx.lua")
VoiceDump = dofile(root .. "/Lib/ifls_fb01_voice_dump.lua")
BankA = dofile(root .. "/Lib/ifls_fb01_bank.lua")
VoiceBank = dofile(root .. "/Lib/ifls_fb01_voicebank.lua")
local ConfigDump = dofile(root .. "/Lib/ifls_fb01_config_dump.lua")
ParamSchema = dofile(root .. "/Core/ifls_fb01_paramschema.lua")
VoiceSpec = dofile(root .. "/Lib/ifls_fb01_voiceblock_spec.lua")
VoiceMap = dofile(root .. "/Lib/ifls_fb01_voice_map.lua")
SlotCore = dofile(root .. "/Workbench/_Shared/IFLS_SlotCore.lua")

local function read_json(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local s=f:read("*all"); f:close()
  return r.JSON_Parse and r.JSON_Parse(s) or nil
end

-- fallback JSON parser if REAPER lacks JSON_Parse: tiny decoder for our file
local function json_decode_min(s)
  -- minimal: rely on Lua load trick for trusted repo file
  local t = s:gsub('"%s*:%s*', '"='):gsub("null","nil")
  t = "return " .. t
  local ok, res = pcall(load(t))
  if ok then return res end
  return nil
end

local params_path = root .. "/Data/fb01_params_mvp.json"
local raw = io.open(params_path,"rb"); local js = raw and raw:read("*all"); if raw then raw:close() end
local P = js and json_decode_min(js) or nil

-- B2.19: load FullSpec voice params (64 bytes) generated from Service Manual
local fullspec_path = root .. "/Data/fb01_params_fullspec.json"
local raw2 = io.open(fullspec_path, "rb")
local js2 = raw2 and raw2:read("*all"); if raw2 then raw2:close() end
local P_FULL = js2 and json_decode_min(js2) or nil
if not P_FULL or not P_FULL.voice_params_fullspec then
  P_FULL = { voice_params_fullspec = {} }
end

if not P then
  r.MB("Failed to load params JSON:\n"..params_path, "FB-01 Sound Editor", 0)
  return
end

local function bin_to_hex

local function build_event_list_sysex(sys_ch)
  local msg = Syx.event_list_begin()
  for _,ev in ipairs(event_items) do
    if ev.t == "note_off_frac" then
      Syx.ev_note_off_frac(msg, sys_ch, ev.key, ev.frac)
    elseif ev.t == "note_onoff_frac" then
      Syx.ev_note_onoff_frac(msg, sys_ch, ev.key, ev.frac, ev.vel)
    elseif ev.t == "note_dur" then
      Syx.ev_note_dur(msg, sys_ch, ev.key, ev.frac, ev.vel, ev.yy, ev.xx)
    elseif ev.t == "cc" then
      Syx.ev_cc(msg, sys_ch, ev.cc, ev.val)
    elseif ev.t == "program" then
      Syx.ev_program(msg, sys_ch, ev.prog)
    elseif ev.t == "aftertouch" then
      Syx.ev_aftertouch(msg, sys_ch, ev.val)
    elseif ev.t == "pitchbend" then
      Syx.ev_pitchbend(msg, sys_ch, ev.py, ev.px)
    elseif ev.t == "inst_param_1" then
      Syx.ev_inst_param_1(msg, sys_ch, ev.pa, ev.dd)
    elseif ev.t == "inst_param_2" then
      Syx.ev_inst_param_2(msg, sys_ch, ev.pa, ev.y, ev.x)
    end
  end
  Syx.event_list_end(msg)
  return msg
end

-- B2.23: file export helpers
local function write_bytes_to_file(path, bytes)
  local f = io.open(path, "wb")
  if not f then return false end
  for i=1,#bytes do f:write(string.char(bytes[i] & 0xFF)) end
  f:close()
  return true
end

local function now_stamp

-- Minimal JSON encoder (strings/numbers/booleans/nil, arrays, maps)
local function json_escape(s)
  s = tostring(s)
  s = s:gsub('\\', '\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
  return '"'..s..'"'
end

local function json_is_array(t)
  local n=0
  for k,_ in pairs(t) do
    if type(k)~="number" then return false end
    if k>n then n=k end
  end
  return true, n
end

local function json_encode_min(v)
  local tv=type(v)
  if tv=="nil" then return "null"
  elseif tv=="number" then return tostring(v)
  elseif tv=="boolean" then return v and "true" or "false"
  elseif tv=="string" then return json_escape(v)
  elseif tv=="table" then
    local isarr,n = json_is_array(v)
    if isarr then
      local parts={}
      for i=1,n do parts[#parts+1]=json_encode_min(v[i]) end
      return "["..table.concat(parts,",").."]"
    else
      local parts={}
      for k,val in pairs(v) do
        parts[#parts+1]=json_escape(k)..":"..json_encode_min(val)
      end
      return "{"..table.concat(parts,",").."}"
    end
  else
    return json_escape(tostring(v))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

()
  return os.date("%Y%m%d_%H%M%S")
end

(bin)
  local out={}
  for i=1,#bin do out[#out+1]=string.format("%02X", bin:byte(i)) end
  return table.concat(out)
end

local function send_sysex(bin)
  -- store hex in ExtState and call helper (keeps binary-safe across Lua layers)
  r.SetExtState("IFLS_FB01", "SYSEX_PAYLOAD", bin_to_hex(bin), false)
  dofile(root .. "/Pack_v8/Scripts/IFLS_FB01_Send_SysEx_FromExtState.lua")
end

-- Preset / Random / Save-Load helpers (V93)

local function now_seed()
  local t = r.time_precise()
  return math.floor((t - math.floor(t)) * 1000000) + math.floor(t)
end

local function _now_precise()
  return r.time_precise()
end

local function send

-- Phase 9: replay a list of SysEx messages (each as byte table) with bulk spacing
local function _replay_sysex_msgs(msg_list, delay_ms)
  if not msg_list or #msg_list == 0 then return end
  local d = delay_ms ~= nil and delay_ms or (CAPTURE_CFG.bulk_delay_ms or 120)
  for i=1,#msg_list do
    local bts = msg_list[i]
    if bts and #bts > 0 then
      send_sysex_throttled(string.char(table.unpack(bts)), d)
    end
  end
end

-- Phase 9: assemble multi-part bulk dumps into a single byte stream for decoding/comparison
local function _assemble_bulk_msgs(msg_list)
  if not msg_list or #msg_list == 0 then return nil end
  local out = {0xF0}
  for i=1,#msg_list do
    local m = msg_list[i]
    if m and #m >= 2 then
      -- append everything except leading F0 and trailing F7
      for j=2,#m-1 do out[#out+1] = m[j] end
    end
  end
  out[#out+1] = 0xF7
  return out
end
_sysex_throttled(payload_str, delay_ms)
  local delay = (CAPTURE_CFG.sysex_delay_ms or 0) / 1000.0
  local now = _now_precise()
  if CAPTURE.next_send_ts and now < CAPTURE.next_send_ts then
    return false
  end
  send_sysex(payload_str)
  CAPTURE.next_send_ts = now + delay
  return true
end

local function rand_int(lo, hi)
  if hi < lo then lo,hi=hi,lo end
  return lo + math.random(0, hi-lo)
end

local function sleep_ms(ms) r.Sleep(ms) end

local function apply_voice_param(param, val)
  voice_vals[param] = val
  local msg = Syx.voice_param(sysch, inst, param, val)
  if live_send_per_change then send_sysex(msg) end
      if autosave_slot then autosave_deb:request() end
      if autosend and autosend_mode==0 then autosend_deb:request() end
  sleep_ms(5)
end

-- B2.20: apply configuration parameter change (instrument-specific)
local function apply_conf_param(pp, value7)
  pp = tonumber(pp) or 0
  value7 = tonumber(value7) or 0
  local msg = Syx.conf_param_inst(sys_ch, inst_id, pp, value7)
  if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
end

local function apply_op_param(op_id, param, val)
  op_vals[op_id+1][param] = val
  local msg = Syx.operator_param(sysch, inst, op_id, param, val)
  if live_send_per_change then send_sysex(msg) end
      if autosave_slot then autosave_deb:request() end
      if autosend and autosend_mode==0 then autosend_deb:request() end
  sleep_ms(5)
end

local function apply_inst_param(param, val)
  inst_vals[param] = val
  local msg = Syx.instrument_param(sysch, inst, param, val)
  if live_send_per_change then send_sysex(msg) end

local function apply_cfg_param(param_no, value)
  local msg = Syx.config_param(sys_ch, param_no, clamp(value, 0, 127))
  send_sysex(msg)
end
      if autosave_slot then autosave_deb:request() end
      if autosend and autosend_mode==0 then autosend_deb:request() end
  sleep_ms(5)
end

local function apply_template(tpl)
  if tpl.voice then
    for k,v in pairs(tpl.voice) do apply_voice_param(k, v) end
  end
  if tpl.ops then
    for op_id, params in pairs(tpl.ops) do
      for k,v in pairs(params) do apply_op_param(op_id, k, v) end
    end
  end
  if tpl.instrument then
    for k,v in pairs(tpl.instrument) do apply_inst_param(k, v) end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function randomize(scope)
  math.randomseed(now_seed())
  if scope=="voice" or scope=="all" then
    for _,it in ipairs(P.voice_params) do
      apply_voice_param(it.param, rand_int(0,127))
    end
  end
  if scope=="ops" or scope=="all" then
    for op_id=0,3 do
      for _,it in ipairs(P.operator_params) do
        apply_op_param(op_id, it.param, rand_int(0,127))
      end
    end
  end
  if scope=="instrument" or scope=="all" then
    for _,it in ipairs(P.instrument_params) do
      apply_inst_param(it.param, rand_int(0,127))
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

-- Simple "genre templates" (starting points; adjust by ear)
local TEMPLATES = {
  ["Organ (bright)"] = {
    voice = { [0]=2, [1]=16, [3]=1, [7]=40, [8]=2, [11]=0, [13]=20, [14]=10, [15]=127, [16]=127, [17]=127, [18]=127 },
    ops = {
      [0] = { [0]=110, [6]=64, [12]=60, [8]=5, [11]=25, [14]=90, [15]=20 },
      [1] = { [0]=95,  [6]=64, [12]=60, [8]=5, [11]=25, [14]=90, [15]=20 },
      [2] = { [0]=0 },
      [3] = { [0]=0 },
    }
  },
  ["Synth (pad soft)"] = {
    voice = { [0]=6, [1]=10, [3]=1, [7]=30, [8]=1, [11]=10, [13]=25, [14]=15, [15]=127, [16]=127, [17]=127, [18]=127 },
    ops = {
      [0] = { [0]=95, [6]=48, [12]=40, [8]=40, [11]=60, [13]=80, [14]=80, [15]=60 },
      [1] = { [0]=85, [6]=48, [12]=40, [8]=40, [11]=60, [13]=80, [14]=80, [15]=60 },
      [2] = { [0]=70, [6]=32, [12]=40, [8]=50, [11]=70, [13]=90, [14]=70, [15]=70 },
      [3] = { [0]=0 },
    }
  },
  ["BD (kick-ish)"] = {
    voice = { [0]=0, [1]=0, [2]=0, [3]=0, [7]=0, [15]=127, [16]=0, [17]=0, [18]=0 },
    ops = {
      [0] = { [0]=127, [6]=10, [12]=20, [8]=0, [11]=10, [13]=20, [14]=0, [15]=5 },
      [1] = { [0]=90,  [6]=5,  [12]=10, [8]=0, [11]=15, [13]=30, [14]=0, [15]=10 },
    }
  },
  ["SD (snare-ish)"] = {
    voice = { [0]=4, [1]=8, [3]=0, [15]=127, [16]=127, [17]=0, [18]=0 },
    ops = {
      [0] = { [0]=110, [6]=30, [12]=50, [8]=0, [11]=20, [13]=50, [14]=0, [15]=25 },
      [1] = { [0]=90,  [6]=50, [12]=70, [8]=0, [11]=30, [13]=70, [14]=0, [15]=40 },
    }
  },
  ["HH (hat-ish)"] = {
    voice = { [0]=7, [1]=0, [3]=0, [15]=127, [16]=127, [17]=127, [18]=0 },
    ops = {
      [0] = { [0]=80, [6]=90, [12]=90, [8]=0, [11]=5, [13]=20, [14]=0, [15]=10 },
      [1] = { [0]=80, [6]=110,[12]=110,[8]=0, [11]=5, [13]=20, [14]=0, [15]=10 },
      [2] = { [0]=70, [6]=120,[12]=120,[8]=0, [11]=5, [13]=20, [14]=0, [15]=10 },
    }
  },
}

local function table_to_json(t)
  -- minimal JSON serializer for our state (numbers/tables/strings)
  local function esc(s) return s:gsub('\\','\\\\'):gsub('"','\\"') end
  local function ser(v)
    local tv=type(v)
    if tv=="number" then return tostring(math.floor(v))
    elseif tv=="boolean" then return v and "true" or "false"
    elseif tv=="string" then return '"'..esc(v)..'"'
    elseif tv=="table" then
      -- decide array vs object
      local is_arr=true
      local n=0
      for k,_ in pairs(v) do
        if type(k)~="number" then is_arr=false; break end
        n = math.max(n, k)
      end
      local out={}
      if is_arr then
        for i=1,n do out[#out+1]=ser(v[i]) end
        return "["..table.concat(out,",").."]"
      else
        for k,val in pairs(v) do
          out[#out+1]=ser(tostring(k))..":"..ser(val)
        end
        return "{"..table.concat(out,",").."}"
      end
    end
    return "null"
  end
  return ser(t)
end

local function save_state_json()
  local ok, path = r.GetUserFileNameForWrite("", "Save FB-01 state as JSON", ".json")
  if not ok or not path or path=="" then return end
  local state = { meta={version="0.93.0", sysch=sysch, inst=inst}, voice=voice_vals, ops=op_vals, instrument=inst_vals }
  local f=io.open(path,"wb"); if not f then r.MB("Cannot write:\n"..path, "FB-01", 0); return end
  f:write(table_to_json(state)); f:close()
  r.MB("Saved JSON:\n"..path, "FB-01", 0)
end

local function load_state_json()
  local ok, path = r.GetUserFileNameForRead("", "Load FB-01 state JSON", ".json")
  if not ok or not path or path=="" then return end
  local f=io.open(path,"rb"); if not f then r.MB("Cannot read:\n"..path, "FB-01", 0); return end
  local s=f:read("*all"); f:close()
  -- trusted local file: convert JSON-ish to Lua table (same trick)
  local t = s:gsub('"%s*:%s*', '"='):gsub("%[","{"):gsub("%]","}"):gsub("null","nil")
  local ok2, obj = pcall(load("return "..t))
  if not ok2 or type(obj)~="table" then r.MB("Invalid JSON file.", "FB-01", 0); return end

  if obj.voice then
    for k,v in pairs(obj.voice) do apply_voice_param(tonumber(k) or k, tonumber(v) or 0) end
  end
  if obj.ops then
    for op_id=0,3 do
      local op_t = obj.ops[op_id+1]
      if type(op_t)=="table" then
        for k,v in pairs(op_t) do apply_op_param(op_id, tonumber(k) or k, tonumber(v) or 0) end
      end
    end
  end
  if obj.instrument then
    for k,v in pairs(obj.instrument) do apply_inst_param(tonumber(k) or k, tonumber(v) or 0) end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

-- V94 additions: constrained random + user templates

local USER_TEMPLATES_PATH = root .. "/Templates/user_templates.json"

local function read_file(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local s=f:read("*all"); f:close(); return s
end
local function write_file(path, data)
  local f=io.open(path,"wb"); if not f then return false end
  f:write(data); f:close(); return true
end

local function load_user_templates()
  local s = read_file(USER_TEMPLATES_PATH)
  if not s or s=="" then return {meta={version="0.1.0"}, templates={}} end
  local t = s:gsub('"%s*:%s*', '"='):gsub("%[","{"):gsub("%]","}"):gsub("null","nil")
  local ok, obj = pcall(load("return "..t))
  if ok and type(obj)=="table" then
    obj.templates = obj.templates or {}
    return obj
  end
  return {meta={version="0.1.0"}, templates={}}
end

local function save_user_templates(db)
  db = db or {meta={version="0.1.0"}, templates={}}
  local ok = write_file(USER_TEMPLATES_PATH, table_to_json(db))
  return ok
end

local function capture_current_as_template(name)
  local tpl = {
    name = name,
    created_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    meta = {sysch=sysch, inst=inst},
    voice = voice_vals,
    ops = op_vals,
    instrument = inst_vals
  }
  return tpl
end

-- Parameter groups for constrained random
local OP_ENV = {8,11,13,14,15} -- Attack, Decay1, Decay2, Sustain, Release
local OP_PITCH = {5,6,12}      -- Fine, Multiple, Coarse (MVP IDs)
local OP_LEVEL = {0,1,2,3}     -- Volume + level mods
local VOICE_LFO = {7,8,9,10,11,12,13,14}

local function randomize_groups(opts)
  math.randomseed(now_seed())
  opts = opts or {}
  if opts.voice_lfo then
    for _,p in ipairs(VOICE_LFO) do apply_voice_param(p, rand_int(0,127)) end
  end
  if opts.voice_all then
    for _,it in ipairs(P.voice_params) do apply_voice_param(it.param, rand_int(0,127)) end
  end
  if opts.ops_env or opts.ops_pitch or opts.ops_level or opts.ops_all then
    for op_id=0,3 do
      if opts.ops_all then
        for _,it in ipairs(P.operator_params) do apply_op_param(op_id, it.param, rand_int(0,127)) end
      else
        if opts.ops_env then
          for _,p in ipairs(OP_ENV) do apply_op_param(op_id, p, rand_int(0,127)) end
        end
        if opts.ops_pitch then
          for _,p in ipairs(OP_PITCH) do apply_op_param(op_id, p, rand_int(0,127)) end
        end
        if opts.ops_level then
          for _,p in ipairs(OP_LEVEL) do apply_op_param(op_id, p, rand_int(0,127)) end
        end
      end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

-- V95 additions: locks + intensity + export .syx as param-stream

local locks = {
  voice = {},         -- [param]=true
  ops = { {},{},{},{} }, -- [op+1][param]=true
  instrument = {},    -- [param]=true
}

local function is_locked(scope, a, b)
  if scope=="voice" then return locks.voice[a] == true end
  if scope=="instrument" then return locks.instrument[a] == true end
  if scope=="op" then return locks.ops[a+1][b] == true end
  return false
end

local function set_locked(scope, a, b, v)
  v = v and true or false
  if scope=="voice" then locks.voice[a] = v; return end
  if scope=="instrument" then locks.instrument[a] = v; return end
  if scope=="op" then locks.ops[a+1][b] = v; return end
end

local function export_param_stream_syx()
  local ok, path = r.GetUserFileNameForWrite("", "Export FB-01 state as .syx (param stream)", ".syx")
  if not ok or not path or path=="" then return end

  local out = {}
  -- voice
  for _,it in ipairs(P.voice_params) do
    local v = voice_vals[it.param] or 0
    out[#out+1] = Syx.voice_param(sysch, inst, it.param, v)
  end
  -- operators
  for op_id=0,3 do
    local t = op_vals[op_id+1]
    for _,it in ipairs(P.operator_params) do
      local v = (t and t[it.param]) or 0
      out[#out+1] = Syx.operator_param(sysch, inst, op_id, it.param, v)
    end
  end
  -- instrument
  for _,it in ipairs(P.instrument_params) do
    local v = inst_vals[it.param] or 0
    out[#out+1] = Syx.instrument_param(sysch, inst, it.param, v)
  end

  local f = io.open(path, "wb")
  if not f then r.MB("Cannot write:\n"..path, "FB-01", 0); return end
  for _,msg in ipairs(out) do f:write(msg) end
  f:close()
  r.MB("Exported .syx param stream:\n"..path, "FB-01", 0)
end

local function randomize_groups_intensity(opts, intensity)
  intensity = tonumber(intensity) or 1.0
  if intensity < 0 then intensity = 0 elseif intensity > 1 then intensity = 1 end
  math.randomseed(now_seed())
  opts = opts or {}

  local function mix(old, rnd)
    -- intensity=0 keeps old; intensity=1 uses rnd
    return clamp(math.floor(old*(1-intensity) + rnd*intensity + 0.5), 0, 127)
  end

  if opts.voice_lfo then
    for _,p in ipairs(VOICE_LFO) do
      if not is_locked("voice", p) then
        local old = voice_vals[p] or 0
        apply_voice_param(p, mix(old, rand_int(0,127)))
      end
    end
  end

  if opts.voice_all then
    for _,it in ipairs(P.voice_params) do
      local p = it.param
      if not is_locked("voice", p) then
        local old = voice_vals[p] or 0
        apply_voice_param(p, mix(old, rand_int(0,127)))
      end
    end
  end

  local function op_apply(op_id, p)
    if not is_locked("op", op_id, p) then
      local old = op_vals[op_id+1][p] or 0
      apply_op_param(op_id, p, mix(old, rand_int(0,127)))
    end
  end

  if opts.ops_all or opts.ops_env or opts.ops_pitch or opts.ops_level then
    for op_id=0,3 do
      if opts.ops_all then
        for _,it in ipairs(P.operator_params) do op_apply(op_id, it.param) end
      else
        if opts.ops_env then for _,p in ipairs(OP_ENV) do op_apply(op_id, p) end end
        if opts.ops_pitch then for _,p in ipairs(OP_PITCH) do op_apply(op_id, p) end end
        if opts.ops_level then for _,p in ipairs(OP_LEVEL) do op_apply(op_id, p) end end
      end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
-- UI state
local ctx = r.ImGui_CreateContext("IFLS FB-01 Sound Editor (MVP)")

local _IFLS_UI_START_TAB = r.GetExtState("IFLS_FB01", "UI_START_TAB")
r.DeleteExtState("IFLS_FB01","UI_START_TAB",false)
local autosave_slot=false
local autosave_ms=350
local autosend=false
local autosend_ms=150
local autosend_mode=0 -- 0=snapshot(debounced) 1=per-change
local autosend_last_send = 0.0
local autosend_final_on_release = true
local snapshot_preview_while_dragging = false
local live_send_per_change=true
local last_autosave_at=0.0
local last_autosend_at=0.0

local inst = 0
local op = 0
local sysch = 0
local voice_vals = {}
local op_vals = {{},{},{},{}}
local inst_vals = {}
local cfg_vals = {}
local user_db = load_user_templates()
local user_tpl_idx = 0
local template_names = {}
for k,_ in pairs(TEMPLATES) do template_names[#template_names+1]=k end
table.sort(template_names)
local template_idx = 0
local rand_intensity = 1.0

local function clamp(v, lo, hi)
  v = math.floor(tonumber(v) or 0)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function voice_panel()
  r.ImGui_Text(ctx, "Voice params (8-bit nibble-split)")
  for _,it in ipairs(P.voice_params) do
    local key = it.param
    local v = voice_vals[key] or 0
    local lock = is_locked("voice", key)
    local chkl, nlock = r.ImGui_Checkbox(ctx, "L##vlock"..key, lock)
    if chkl then set_locked("voice", key, nil, nlock) end
    r.ImGui_SameLine(ctx)
    local changed, nv = r.ImGui_SliderInt(ctx, it.name .. "##v"..key, v, 0, 127)
    if changed then
      nv = clamp(nv, 0, 127)
      voice_vals[key] = nv
      local msg = Syx.voice_param(sysch, inst, key, nv)
      if live_send_per_change then send_sysex(msg) end
      if autosend and autosend_mode==1 then
        local now = reaper.time_precise()
        if (now - autosend_last_send) * 1000.0 >= autosend_ms then
          autosend_last_send = now
          send_sysex(msg)
        end
      end
            if autosend and autosend_mode==0 and snapshot_preview_while_dragging then
        local now = reaper.time_precise()
        if (now - autosend_last_send) * 1000.0 >= autosend_ms then
          autosend_last_send = now
          send_sysex(msg)
        end
      end
if autosave_slot then autosave_deb:request() end
      local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)
      if deact and autosend and autosend_mode==1 and autosend_final_on_release then
        send_sysex(msg)
      end
      if deact and autosend and autosend_mode==0 then autosend_deb:request() end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  -- =========================
  -- Auto Calibration (Phase 36): guided listening + toolbar entry target
  -- =========================
  local algo = tonumber(voice_vals and voice_vals["algorithm"]) or 0
  local want_autocal = (_IFLS_UI_START_TAB == "autocal")
  if r.ImGui_CollapsingHeader(ctx, "Auto Calibration (Phase 36)", want_autocal and r.ImGui_TreeNodeFlags_DefaultOpen() or 0) then
    if want_autocal and r.ImGui_SetScrollHereY then
      r.ImGui_SetScrollHereY(ctx, 0.0)
      _IFLS_UI_START_TAB = nil
    end
    r.ImGui_Text(ctx, "Algorithm: " .. tostring(algo))
    r.ImGui_Text(ctx, "Press Test OP1..4, play a note, tick audible ops, then Apply.")

    -- Meter-based AutoCal (Phase 36.2)
    local names = _list_track_names()
    local cur = AUTOCAL.track_name or "FB-01 Audio Return"
    local idx = 0
    for i,nm in ipairs(names) do if nm == cur then idx = i-1 break end end
    if r.ImGui_BeginCombo(ctx, "Audio return track", cur) then

    -- Phase 36.4: MIDI out auto-detect/select (StuffMIDIMessage hardware mode)
    local outs = _list_midi_outputs()
    local cur_idx = AUTOCAL.midi_out_idx
    if cur_idx == nil then
      local saved = r.GetExtState("IFLS_FB01","MIDI_OUT_IDX")
      if saved ~= "" then cur_idx = tonumber(saved) end
    end
    local cur_name = "(VKB/Track routing)"
    if cur_idx ~= nil and outs then
      for _,o in ipairs(outs) do if o.idx == cur_idx then cur_name = o.name break end end
    end

    local c3
    c3, AUTOCAL.midi_use_hw = r.ImGui_Checkbox(ctx, "Send test note direct to MIDI HW out", AUTOCAL.midi_use_hw)

    if AUTOCAL.midi_use_hw then
      local api = (r.APIExists and r.APIExists("SendMIDIMessageToHardware")) and "available" or "not available"
      local c5
      c5, AUTOCAL.midi_use_send_to_hw = r.ImGui_Checkbox(ctx, "Prefer SendMIDIMessageToHardware() ("..api..")", AUTOCAL.midi_use_send_to_hw)

      local c6
      c6, AUTOCAL.sysex_use_send_to_hw = r.ImGui_Checkbox(ctx, "SysEx via SendMIDIMessageToHardware() (test patch)", AUTOCAL.sysex_use_send_to_hw)
      c6, AUTOCAL.device_lock = r.ImGui_Checkbox(ctx, "Device lock (remap by port name)", AUTOCAL.device_lock)
      c6, AUTOCAL.tonefix_fx = r.ImGui_Checkbox(ctx, "Auto-insert ToneFix EQ on Audio Return track", AUTOCAL.tonefix_fx)

      if AUTOCAL.tonefix_fx then
        local curm = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
        if r.ImGui_BeginCombo(ctx, "ToneFix mode", curm) then
          if r.ImGui_Selectable(ctx, "always", curm=="always") then
            AUTOCAL.tonefix_mode="always"
            r.SetExtState("IFLS_FB01","TONEFIX_MODE","always", true)
          end
          if r.ImGui_Selectable(ctx, "autocal", curm=="autocal") then
            AUTOCAL.tonefix_mode="autocal"
            r.SetExtState("IFLS_FB01","TONEFIX_MODE","autocal", true)
          end
          r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_Button(ctx, "Install ToneFix FX Chain (.RfxChain)", 280, 0) then
          local p = _install_tonefix_rfxchain()
          if p then AUTOCAL.status = "Installed FX Chain: " .. p else AUTOCAL.status = "ERROR: could not write FX Chain" end
        end
        r.ImGui_Text(ctx, "Noise-aware treble: high shelf auto-set from baseline stats.")
      end

      r.ImGui_Text(ctx, "Note: 'enabled in prefs' filtering is best-effort; REAPER may only enumerate enabled devices.")
    end

    if AUTOCAL.midi_use_hw then
      if r.ImGui_BeginCombo(ctx, "MIDI output device", cur_name) then
        if r.ImGui_Selectable(ctx, "(VKB/Track routing)", cur_idx == nil) then
          AUTOCAL.midi_out_idx = nil
          r.SetExtState("IFLS_FB01","MIDI_OUT_IDX","", true)
        end
        for _,o in ipairs(outs) do
          local sel = (cur_idx == o.idx)
          if r.ImGui_Selectable(ctx, o.name, sel) then
            AUTOCAL.midi_out_idx = o.idx
            AUTOCAL.midi_out_name = o.name
            r.SetExtState("IFLS_FB01","MIDI_OUT_IDX", tostring(o.idx), true)
            r.SetExtState("IFLS_FB01","MIDI_OUT_NAME", o.name, true)
          end
        end
        r.ImGui_EndCombo(ctx)
      end
      c3, AUTOCAL.midi_set_track_hwout = r.ImGui_Checkbox(ctx, "Also set MIDI HW out on 'FB-01 MIDI OUT' track", AUTOCAL.midi_set_track_hwout)
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Auto-detect MIDI out", 160, 0) then
        local pref = AUTOCAL.midi_pref_substr or r.GetExtState("IFLS_FB01","MIDI_OUT_PREF") or ""
        local idx = _autodetect_midi_output(pref)
        if idx ~= nil then
          AUTOCAL.midi_out_idx = idx
          r.SetExtState("IFLS_FB01","MIDI_OUT_IDX", tostring(idx), true)
    local outs=_list_midi_outputs(); for _,o in ipairs(outs) do if o.idx==idx then AUTOCAL.midi_out_name=o.name; r.SetExtState("IFLS_FB01","MIDI_OUT_NAME",o.name,true) break end end
        end
      end
    end

    -- Phase 36.4: Audio input auto-detect
    if r.ImGui_Button(ctx, "Auto-detect Audio Input Pair", 240, 0) then
      local inL = _autodetect_audio_in_l()
      r.SetExtState("IFLS_FB01","AUDIO_IN_L", tostring(inL), true)
      AUTOCAL.status = "Audio input set to " .. tostring(inL) .. "/" .. tostring(inL+1)
      if AUTOCAL.auto_ensure_tracks then _autocal_ensure_tracks()
    local aud=_find_track_by_name(AUTOCAL.track_name or "FB-01 Audio Return")
    if aud and AUTOCAL.tonefix_fx then
      local mode = AUTOCAL.tonefix_mode or (r.GetExtState("IFLS_FB01","TONEFIX_MODE") ~= "" and r.GetExtState("IFLS_FB01","TONEFIX_MODE") or "always")
      if mode == "autocal" then _tonefix_set_enabled(aud, true) end
    end end
    end

      for i,nm in ipairs(names) do
        local sel = (nm == cur)
        if r.ImGui_Selectable(ctx, nm, sel) then
          AUTOCAL.track_name = nm
          r.SetExtState("IFLS_FB01", "AUTOCAL_TRACK", nm, true)
        end
      end
      r.ImGui_EndCombo(ctx)
    end

    local ch = tonumber(r.GetExtState("IFLS_FB01", "AUTOCAL_CH") or "") or AUTOCAL.chan or 0
    local changed, v = r.ImGui_InputInt(ctx, "MIDI channel (0=1)", ch, 1, 4)
    if changed then
      if v < 0 then v = 0 end
      if v > 15 then v = 15 end
      AUTOCAL.chan = v
      r.SetExtState("IFLS_FB01", "AUTOCAL_CH", tostring(v), true)
    end
    r.ImGui_SameLine(ctx)
    changed, v = r.ImGui_InputInt(ctx, "Note", AUTOCAL.note or 60, 1, 12)
    if changed then AUTOCAL.note = math.max(0, math.min(127, v)) end
    r.ImGui_SameLine(ctx)
    changed, v = r.ImGui_InputInt(ctx, "Vel", AUTOCAL.vel or 100, 1, 10)
    if changed then AUTOCAL.vel = math.max(1, math.min(127, v)) end

    changed, v = r.ImGui_InputDouble(ctx, "Threshold dB", AUTOCAL.thresh_db or -45.0, 1.0, 5.0, "%.1f")
    if changed then AUTOCAL.thresh_db = v end
    r.ImGui_SameLine(ctx)
    changed, v = r.ImGui_InputDouble(ctx, "Note len (s)", AUTOCAL.note_len or 0.8, 0.05, 0.2, "%.2f")
    if changed then AUTOCAL.note_len = math.max(0.1, v) end
    r.ImGui_SameLine(ctx)
    changed, v = r.ImGui_InputDouble(ctx, "Pause (s)", AUTOCAL.pause or 0.35, 0.05, 0.2, "%.2f")
    if changed then AUTOCAL.pause = math.max(0.05, v) end

    if not AUTOCAL.running then
      if r.ImGui_Button(ctx, "Auto-Calibrate All (Meter)", 240, 0) then
        AUTOCAL.track_name = r.GetExtState("IFLS_FB01", "AUTOCAL_TRACK") ~= "" and r.GetExtState("IFLS_FB01", "AUTOCAL_TRACK") or (AUTOCAL.track_name or "FB-01 Audio Return")
        _autocal_init()
      end
    else
      if r.ImGui_Button(ctx, "Stop AutoCal", 140, 0) then
        _autocal_reset()
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_Text(ctx, AUTOCAL.status or "")
      if AUTOCAL.last_db then
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, string.format("(last %.1f dB)", AUTOCAL.last_db))
      end
    end

    CAL = CAL or { audible = { [1]=false,[2]=false,[3]=false,[4]=false } }

    if r.ImGui_Button(ctx, "Test OP1", 90, 0) then
      local v, ops = _voice_clone_defaults(); v.algorithm = algo; _voice_set_solo_op(v, ops, 1)
      local bytes64 = VoiceMap.encode_voice_block(v, ops); send_inst_voice_temp(bytes64, 0)
      _log_add("algo", "Test OP1 for algo "..tostring(algo))
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Test OP2", 90, 0) then
      local v, ops = _voice_clone_defaults(); v.algorithm = algo; _voice_set_solo_op(v, ops, 2)
      local bytes64 = VoiceMap.encode_voice_block(v, ops); send_inst_voice_temp(bytes64, 0)
      _log_add("algo", "Test OP2 for algo "..tostring(algo))
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Test OP3", 90, 0) then
      local v, ops = _voice_clone_defaults(); v.algorithm = algo; _voice_set_solo_op(v, ops, 3)
      local bytes64 = VoiceMap.encode_voice_block(v, ops); send_inst_voice_temp(bytes64, 0)
      _log_add("algo", "Test OP3 for algo "..tostring(algo))
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Test OP4", 90, 0) then
      local v, ops = _voice_clone_defaults(); v.algorithm = algo; _voice_set_solo_op(v, ops, 4)
      local bytes64 = VoiceMap.encode_voice_block(v, ops); send_inst_voice_temp(bytes64, 0)
      _log_add("algo", "Test OP4 for algo "..tostring(algo))
    end

    local c
    c, CAL.audible[1] = r.ImGui_Checkbox(ctx, "OP1 audible", CAL.audible[1]); r.ImGui_SameLine(ctx)
    c, CAL.audible[2] = r.ImGui_Checkbox(ctx, "OP2 audible", CAL.audible[2]); r.ImGui_SameLine(ctx)
    c, CAL.audible[3] = r.ImGui_Checkbox(ctx, "OP3 audible", CAL.audible[3]); r.ImGui_SameLine(ctx)
    c, CAL.audible[4] = r.ImGui_Checkbox(ctx, "OP4 audible", CAL.audible[4])

    if r.ImGui_Button(ctx, "Apply carriers from checks", 220, 0) then
      _algo_apply_carriers_from_checks(algo, CAL.audible)
      CAL.audible[1],CAL.audible[2],CAL.audible[3],CAL.audible[4] = false,false,false,false
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export calibration report", 220, 0) then
      local p = _algo_export_calibration_report()
      if p and LIBRARY then LIBRARY.status = "Exported algo calibration: " .. p end
    end
  end

  end
end

local function operator_panel()
  r.ImGui_Text(ctx, "Operator params")
  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local wide = avail_w >= 860 -- responsive breakpoint for matrix view

  local function send_op_param(op_idx, param_no, value)
    local msg = Syx.operator_param(sysch, inst, op_idx, param_no, value)
    if live_send_per_change then send_sysex(msg) end
    if autosend and autosend_mode==1 then
      local now = reaper.time_precise()
      if (now - autosend_last_send) * 1000.0 >= autosend_ms then
        autosend_last_send = now
        send_sysex(msg)
      end
    end
    if autosend and autosend_mode==0 and snapshot_preview_while_dragging then
      local now = reaper.time_precise()
      if (now - autosend_last_send) * 1000.0 >= autosend_ms then
        autosend_last_send = now
        send_sysex(msg)
      end
    end
    if autosave_slot then autosave_deb:request() end
    local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)
    if deact and autosend and autosend_mode==1 and autosend_final_on_release then
      send_sysex(msg)
    end
    if deact and autosend and autosend_mode==0 then autosend_deb:request() end
  end

  -- Common drawing helper for matrix cells
  local function op_cell(op_idx, param_no, v, vmin, vmax, id_suffix)
    local lock = is_locked("op", op_idx, param_no)
    local chkl, nlock = r.ImGui_Checkbox(ctx, "L##m_oplock"..op_idx.."_"..param_no..id_suffix, lock)
    if chkl then set_locked("op", op_idx, param_no, nlock) end
    r.ImGui_SameLine(ctx)
    local ch, nv = r.ImGui_SliderInt(ctx, "##m_op"..op_idx.."_"..param_no..id_suffix, v, vmin, vmax)
    if ch then
      nv = clamp(nv, vmin, vmax)
      op_vals[op_idx+1][param_no] = nv
      send_op_param(op_idx, param_no, nv)
    end
  end

  if wide then
    r.ImGui_Text(ctx, "All Ops (Matrix) â€“ EG + TL/MUL")
    r.ImGui_Separator(ctx)

  -- Schema-driven Config UI (Phase 24): edits a local config shadow table; send/apply uses existing config send pipeline.
  r.ImGui_Text(ctx, "Schema-driven Config UI (Phase 24)")
  if not CFG_SHADOW then CFG_SHADOW = {} end
  local _c
  _c, CFG_SHADOW.inst = r.ImGui_SliderInt(ctx, "Config Instrument Slot", CFG_SHADOW.inst or 0, 0, 7)
  CFG_SHADOW.data = CFG_SHADOW.data or {}
  CFG_SHADOW.data[CFG_SHADOW.inst] = CFG_SHADOW.data[CFG_SHADOW.inst] or {}
  local ct = CFG_SHADOW.data[CFG_SHADOW.inst]
  _schema_draw_group(ctx, ct, "cfg.", "config.instrument")

  if r.ImGui_Button(ctx, "Copy Shadow -> Current Config Table", 260, 0) then
    -- Best-effort: if your existing code stores config for instruments in a table, map keys over.
    if CONFIG and CONFIG.instruments then
      CONFIG.instruments[CFG_SHADOW.inst] = CONFIG.instruments[CFG_SHADOW.inst] or {}
      for k,v in pairs(ct) do CONFIG.instruments[CFG_SHADOW.inst][k] = v end
    end
  end
  r.ImGui_Text(ctx, "Note: This panel is schema-driven and will expand as Schema.PARAMS gains more cfg_* keys.")
  r.ImGui_Separator(ctx)

    -- Table 1: EG
    if r.ImGui_BeginTable(ctx, "op_matrix_eg", 5,
      r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
      r.ImGui_TableSetupColumn(ctx, "EG")
      r.ImGui_TableSetupColumn(ctx, "OP1")
      r.ImGui_TableSetupColumn(ctx, "OP2")
      r.ImGui_TableSetupColumn(ctx, "OP3")
      r.ImGui_TableSetupColumn(ctx, "OP4")
      r.ImGui_TableHeadersRow(ctx)

      local rows = {
        {name="Attack (AR)",  p=8,  min=0, max=31},
        {name="Decay1 (D1R)", p=11, min=0, max=31},
        {name="Decay2 (D2R)", p=13, min=0, max=31},
        {name="Sustain (SL)", p=14, min=0, max=15},
        {name="Release (RR)", p=15, min=0, max=15},
      }

      for _,row in ipairs(rows) do
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, row.name)
        for op_idx=0,3 do
          r.ImGui_TableSetColumnIndex(ctx, 1+op_idx)
          local v = op_vals[op_idx+1][row.p] or 0
          op_cell(op_idx, row.p, v, row.min, row.max, "_eg")
        end
      end
      r.ImGui_EndTable(ctx)
    end

    r.ImGui_Separator(ctx)

    -- Table 2: TL/MUL (compact)
    if r.ImGui_BeginTable(ctx, "op_matrix_tlmul", 5,
      r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
      r.ImGui_TableSetupColumn(ctx, "Level/Freq")
      r.ImGui_TableSetupColumn(ctx, "OP1")
      r.ImGui_TableSetupColumn(ctx, "OP2")
      r.ImGui_TableSetupColumn(ctx, "OP3")
      r.ImGui_TableSetupColumn(ctx, "OP4")
      r.ImGui_TableHeadersRow(ctx)

      local rows2 = {
        {name="TL/Volume", p=0, min=0, max=127},
        {name="MUL",       p=6, min=0, max=15},
      }
      for _,row in ipairs(rows2) do
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, row.name)
        for op_idx=0,3 do
          r.ImGui_TableSetColumnIndex(ctx, 1+op_idx)
          local v = op_vals[op_idx+1][row.p] or 0
          op_cell(op_idx, row.p, v, row.min, row.max, "_tlmul")
        end
      end
      r.ImGui_EndTable(ctx)
    end

    -- Optional: access full operator params when in matrix view
    r.ImGui_Separator(ctx)
    if r.ImGui_CollapsingHeader(ctx, "Advanced: Full Operator Params (Tabs)", 0) then
      if r.ImGui_BeginTabBar(ctx, "op_tabs_adv") then
        for op_idx=0,3 do
          if r.ImGui_BeginTabItem(ctx, "OP"..tostring(op_idx+1), true) then
            local t = op_vals[op_idx+1]
            for _,it in ipairs(P.operator_params) do
              local key = it.param
              local v = t[key] or 0
              local lock = is_locked("op", op_idx, key)
              local chkl, nlock = r.ImGui_Checkbox(ctx, "L##oplock"..op_idx.."_"..key, lock)
              if chkl then set_locked("op", op_idx, key, nlock) end
              r.ImGui_SameLine(ctx)
              local ch, nv = r.ImGui_SliderInt(ctx, it.name .. "##op"..op_idx.."_"..key, v, it.min or 0, it.max or 127)
              if ch then
                nv = clamp(nv, it.min or 0, it.max or 127)
                t[key] = nv
                send_op_param(op_idx, key, nv)
              end
            end
            r.ImGui_EndTabItem(ctx)
          end
        end
        r.
    -- Phase 12: Library tab
    if r.ImGui_BeginTabItem(ctx, "Library") then

    if not LIBRARY.sources or #LIBRARY.sources == 0 then
      _library_refresh_sources()
      _library_refresh_files()
    end

    -- Sidebar layout
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local sidebar_w = math.max(220, math.floor(avail_w * 0.30))
    r.ImGui_BeginChild(ctx, "##lib_sidebar", sidebar_w, 0, true)

    r.ImGui_Text(ctx, "Sources")
    if r.ImGui_Button(ctx, "Refresh Sources", -1, 0) then
      _library_refresh_sources()
      _library_refresh_files()
    end

    local src_labels = {}
    for i,s in ipairs(LIBRARY.sources) do src_labels[i]=s.label end
    local changed
    changed, LIBRARY.source_sel = r.ImGui_ListBox(ctx, "##lib_sources", LIBRARY.source_sel, src_labels, math.min(#src_labels, 12))
    if changed then
      _library_refresh_files()
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Files")
    local file_labels = {}
    for i,f in ipairs(LIBRARY.files) do file_labels[i]=f.name end
    local fchanged
    fchanged, LIBRARY.file_sel = r.ImGui_ListBox(ctx, "##lib_files", LIBRARY.file_sel, file_labels, math.min(#file_labels, 12))
    if fchanged then
      _library_load_file_voices(LIBRARY.files[LIBRARY.file_sel])
    end

    r.ImGui_EndChild(ctx)
    r.ImGui_SameLine(ctx)

    -- Main panel
    r.ImGui_BeginChild(ctx, "##lib_main", 0, 0, false)

    r.ImGui_Text(ctx, "Selected sound")
    if #LIBRARY.voices == 0 and LIBRARY.files and #LIBRARY.files > 0 then
      -- lazy load first file
      _library_load_file_voices(LIBRARY.files[LIBRARY.file_sel])
    end

    local voice_labels = {}
    for i,v in ipairs(LIBRARY.voices) do voice_labels[i]=v.name end
    local vchanged
    vchanged, LIBRARY.voice_sel = r.ImGui_ListBox(ctx, "##lib_voices", LIBRARY.voice_sel, voice_labels, math.min(#voice_labels, 18))

    local _c
    _c, LIBRARY.target_inst = r.ImGui_SliderInt(ctx, "Target Instrument (0..7)", LIBRARY.target_inst or 0, 0, 7)
    _c, LIBRARY.verify_after = r.ImGui_Checkbox(ctx, "Verify after send", LIBRARY.verify_after or false)

    if r.ImGui_Button(ctx, "Audition to Instrument", 240, 0) then
      local v = LIBRARY.voices[LIBRARY.voice_sel]
      if v and v.bytes and #v.bytes == 64 then
        -- send as instvoice to target instrument slot
        local sysch2 = sys_ch or sysch or 0
        local instno = LIBRARY.target_inst or 0
        -- optional: rate-limited send
        if VoiceDump and VoiceDump.build_inst_voice_sysex then
          local msg = VoiceDump.build_inst_voice_sysex(sysch2, instno, v.bytes)
          send_sysex_throttled(msg, CAPTURE_CFG.sysex_delay_ms)
        else
          r.MB("InstVoice builder not available.", "Library", 0)
        end
        if LIBRARY.verify_after then
          CAPTURE.retries_left = CAPTURE_CFG.retry_count_instvoice or 1
          verify_start("instvoice", v.bytes, {timeout=CAPTURE_CFG.t_instvoice or 2.5, sys_ch=sysch2, inst_no=instno})
          enqueue_sysex(Syx.dump_inst_voice(sysch2, instno))
        end
      else
        r.MB("No selectable voice loaded (expected 64-byte voice).", "Library", 0)
      end
    end

      r.ImGui_Text(ctx, "Patch Library Index (folder of .syx bank dumps)")
      local changed
      changed, LIBRARY.folder = r.ImGui_InputText(ctx, "Library folder", LIBRARY.folder or "")
      if changed then _ext_set("library_folder", LIBRARY.folder or "") end
      if r.ImGui_Button(ctx, "Scan Folder â†’ Build Index", 220, 0) then
        local idx, err = _library_scan_folder(LIBRARY.folder)
        if idx then
          LIBRARY.index = idx
          LIBRARY.last_scan_ts = os.time()
          local p, e2 = _library_save_index(idx)
          LIBRARY.status = p and ("Saved index: " .. p) or ("Save failed: " .. tostring(e2))
        else
          LIBRARY.status = "Scan failed: " .. tostring(err)
        end
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Load Index", 120, 0) then
        local idx = _library_load_index()
        if idx then
          LIBRARY.index = idx
          LIBRARY.status = "Loaded index from project folder."
        else
          LIBRARY.status = "No index found."
        end
      end
      if LIBRARY.status and LIBRARY.status ~= "" then
        r.ImGui_Text(ctx, LIBRARY.status)
      end

      if LIBRARY.index and LIBRARY.index.banks then
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, ("Banks indexed: %d    Files scanned: %d"):format(#LIBRARY.index.banks, LIBRARY.index.files_scanned or 0))
        -- list banks
        for bi, b in ipairs(LIBRARY.index.banks) do
          local label = ("%s (%d voices)"):format(b.path:match("[^/\\]+$") or b.key, b.voices_count or 0)
          local sel = (LIBRARY.selected_key == b.key)
          if r.ImGui_Selectable(ctx, label, sel) then
            LIBRARY.selected_key = b.key
          end
        end

        -- audition selected bank voice -> inst slot
        if LIBRARY.selected_key then
          local bank_entry = nil
          for _,b in ipairs(LIBRARY.index.banks) do if b.key==LIBRARY.selected_key then bank_entry=b break end end
          if bank_entry then
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Selected: " .. (bank_entry.path or bank_entry.key))
            local ch
            ch, lib_voice_idx = r.ImGui_SliderInt(ctx, "Voice index (1..48)", lib_voice_idx or 1, 1, 48)
            ch, lib_inst_no = r.ImGui_SliderInt(ctx, "Target instrument (0..7)", lib_inst_no or 0, 0, 7)
            ch, lib_verify = r.ImGui_Checkbox(ctx, "Verify after send", lib_verify or false)

  -- Phase 14: Tagging for selected voice
  if LIBRARY.voice_sel and LIBRARY.file_sel_name then
    local vkey = _lib_entry_key(LIBRARY.source_sel or 0, LIBRARY.file_sel_name, LIBRARY.voice_sel)

    -- Phase 23: Favorite + rating meta
    local meta = LIBRARY.user_meta
    if meta then
      local fav = meta.fav[vkey] and true or false
      local _c
      _c, fav = r.ImGui_Checkbox(ctx, "Favorite", fav)
      if _c then
        if fav then meta.fav[vkey]=true else meta.fav[vkey]=nil end
        _lib_save_user_meta(meta)
      end
      local rat = tonumber(meta.rating[vkey] or 0) or 0
      _c, rat = r.ImGui_SliderInt(ctx, "Rating", rat, 0, 5)
      if _c then meta.rating[vkey]=rat; _lib_save_user_meta(meta) end
    end

    local curtags = (LIBRARY.tags and LIBRARY.tags[vkey]) or ""
    r.ImGui_Text(ctx, "Tags: " .. (curtags ~= "" and curtags or "(none)"))
    local _c
    _c, LIBRARY.tag_edit = r.ImGui_InputText(ctx, "Edit tags (comma-separated)", LIBRARY.tag_edit or curtags)
    if r.ImGui_Button(ctx, "Save Tags", 120, 0) then
      LIBRARY.tags[vkey] = tostring(LIBRARY.tag_edit or "")
      _lib_save_tags(LIBRARY.tags)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Auto-tag (heuristic)", 160, 0) then
      if LIBRARY.selected_voice_bytes and VoiceMap and VoiceMap.decode_voice_block then
        local vv = VoiceMap.decode_voice_block(LIBRARY.selected_voice_bytes)
        local t = _lib_guess_tags_from_voice(vv)
        LIBRARY.tag_edit = t
        LIBRARY.tags[vkey] = t
        _lib_save_tags(LIBRARY.tags)
      end
    end
  end

  
    r.ImGui_Separator(ctx)

    -- =========================
    -- Audition A/B (Phase 30)
    -- =========================
    r.ImGui_Text(ctx, "Audition A/B (Phase 30)")
    if r.ImGui_Button(ctx, "Set A = current", 170, 0) then
      LIBRARY.auditionA = LIBRARY.selected_voice_bytes
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Set B = current", 170, 0) then
      LIBRARY.auditionB = LIBRARY.selected_voice_bytes
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Swap A/B", 120, 0) then
      local tmp = LIBRARY.auditionA; LIBRARY.auditionA = LIBRARY.auditionB; LIBRARY.auditionB = tmp
    end

    if r.ImGui_Button(ctx, "Send A (temp)", 170, 0) then
      send_inst_voice_temp(LIBRARY.auditionA, 0)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send B (temp)", 170, 0) then
      send_inst_voice_temp(LIBRARY.auditionB, 0)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send Current (temp)", 210, 0) then

    -- Send+Verify (Phase 33): temp send then dump+compare with retries (edit buffer, no store)
    if r.ImGui_Button(ctx, "Send+Verify Current (temp)", 260, 0) then
      local target = LIBRARY.selected_voice_bytes
      if target then
        send_inst_voice_temp(target, 0)
        VERIFY.pending = true
        VERIFY.kind = "instvoice"
        VERIFY.target = target
        VERIFY.started = r.time_precise()
        VERIFY.timeout = 4.0
        VERIFY.retries = 2
        VERIFY.req_fn = function()
          enqueue_sysex(Syx.dump_inst_voice(CAPTURE_CFG.sys_ch or 0, 0))
        end
        VERIFY.req_fn()
      end
    end

      send_inst_voice_temp(LIBRARY.selected_voice_bytes, 0)
    end
    if LIBRARY.last_send_ts and LIBRARY.last_send_ts ~= "" then
    -- =========================
    -- Phase 32: Next/Prev + Scan (results/favorites)
    -- =========================
    -- Commit Workflow (Phase 35): audition -> verify -> tag/meta -> export
    -- =========================
    if not COMMIT then COMMIT = { auto_verify=true, auto_fav=false, rating=0, name="Committed", export_bundle=true } end
    r.ImGui_Text(ctx, "Commit Workflow (Phase 35)")
    local c
    c, COMMIT.name = r.ImGui_InputText(ctx, "Name", COMMIT.name)
    c, COMMIT.auto_verify = r.ImGui_Checkbox(ctx, "Auto Verify (Send+Verify)", COMMIT.auto_verify); r.ImGui_SameLine(ctx)
    c, COMMIT.export_bundle = r.ImGui_Checkbox(ctx, "Export commit folder", COMMIT.export_bundle)
    c, COMMIT.auto_fav = r.ImGui_Checkbox(ctx, "Mark Favorite", COMMIT.auto_fav); r.ImGui_SameLine(ctx)
    c, COMMIT.rating = r.ImGui_SliderInt(ctx, "Rating", COMMIT.rating or 0, 0, 5)

    if r.ImGui_Button(ctx, "COMMIT Current Voice", 220, 0) then
      local vb = LIBRARY.selected_voice_bytes
      if vb then
        -- optional verify
        if COMMIT.auto_verify then
          send_inst_voice_temp(vb, 0)
          VERIFY.pending = true
          VERIFY.kind = "instvoice"
          VERIFY.target = vb
          VERIFY.started = r.time_precise()
          VERIFY.timeout = 4.0
          VERIFY.retries = 2
          VERIFY.req_fn = function() enqueue_sysex(Syx.dump_inst_voice(CAPTURE_CFG.sys_ch or 0, 0)) end
          VERIFY.req_fn()
        end

        -- meta updates (favorite/rating) for current selected voice key
        if LIBRARY.user_meta and LIBRARY.file_sel_name and LIBRARY.selected_voice then
          local vkey = _lib_entry_key(LIBRARY.file_sel_meta and LIBRARY.file_sel_meta.source or "unknown", LIBRARY.file_sel_name, LIBRARY.selected_voice)
          if COMMIT.auto_fav then LIBRARY.user_meta.fav[vkey]=true end
          if (COMMIT.rating or 0) > 0 then LIBRARY.user_meta.rating[vkey]=COMMIT.rating end
          _lib_save_user_meta(LIBRARY.user_meta)
        end

        -- export
        if COMMIT.export_bundle then
          local dir = _lib_exports_dir() .. "/Committed_" .. os.date("%Y%m%d_%H%M%S")
          r.RecursiveCreateDirectory(dir, 0)
          local syx_bytes = VoiceDump.build_inst_voice_sysex(vb, CAPTURE_CFG.sys_ch or 0, 0)
          local fname = (COMMIT.name and COMMIT.name ~= "" and COMMIT.name or "voice") .. ".syx"
          fname = fname:gsub("[^%w%-%_%. ]","_")
          _write_bytes_file(dir.."/"..fname, syx_bytes)
          -- also dump meta snapshot
          _copy_file(_meta_path(), dir.."/library_user_meta.json")
          _copy_file(_tags_path(), dir.."/library_tags.json")
          _log_add("commit", "Committed voice export: "..dir.."/"..fname)
          LIBRARY.status = "Committed -> " .. dir
        else
          _log_add("commit", "Committed voice (no export)")
        end
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export Log", 120, 0) then
      local p = _log_export()
      if p then LIBRARY.status = "Log exported: " .. p end
    end

    if r.ImGui_Button(ctx, "Show Log (last 30)", 180, 0) then
      COMMIT.show_log = not COMMIT.show_log
    end
    if COMMIT.show_log then
      r.ImGui_BeginChild(ctx, "##log", 0, 120, true)
      local start = math.max(1, #LOG.items - 29)
      for i=start,#LOG.items do
        local it = LOG.items[i]
        r.ImGui_Text(ctx, ("[%s] %s: %s"):format(it.ts, it.kind, it.msg))
      end
      r.ImGui_EndChild(ctx)
    end

    r.ImGui_Separator(ctx)

    -- =========================
    r.ImGui_Text(ctx, "Next/Prev + Scan (Phase 32)")
    if r.ImGui_Button(ctx, "Prev", 70, 0) then _scan_prev() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Next", 70, 0) then _scan_next() end
    r.ImGui_SameLine(ctx)
    local c
    c, LIBRARY.scan_enabled = r.ImGui_Checkbox(ctx, "Scan", LIBRARY.scan_enabled or false)
    r.ImGui_SameLine(ctx)
    c, LIBRARY.scan_interval_ms = r.ImGui_SliderInt(ctx, "Interval (ms)", LIBRARY.scan_interval_ms or 900, 200, 5000)

    local modes = "results\0favorites\0\0"
    local mi = 1
    if LIBRARY.scan_mode == "queue" then
      r.ImGui_Text(ctx, "Queue scan uses current search_results order. With Auto-rebuild enabled, it tracks filter/sort changes.")
    elseif LIBRARY.scan_mode == "favorites" then mi = 2 elseif LIBRARY.scan_mode == "queue" then mi = 3 end
    c, mi = r.ImGui_Combo(ctx, "Scan Mode", mi, modes)
    if c then
      if mi==2 then LIBRARY.scan_mode="favorites" elseif mi==3 then LIBRARY.scan_mode="queue" else LIBRARY.scan_mode="results" end
      LIBRARY.scan_list = nil
      LIBRARY.scan_pos = 0
    end
    if LIBRARY.scan_mode == "queue" then
    _queue_next()
    return
  end
  if LIBRARY.scan_mode == "queue" then
    _queue_prev()
    return
  end
  if LIBRARY.scan_mode == "favorites" then
      r.ImGui_Text(ctx, "Favorites scan uses your Favorite list (Phase 23).")
    else
      r.ImGui_Text(ctx, "Results scan uses the order you click results (builds a list).")
    end

      r.ImGui_Text(ctx, "Last sent: " .. tostring(LIBRARY.last_send_ts))
    end
    r.ImGui_Text(ctx, "Note: This sends InstVoice to the instrument edit buffer; store/write is not performed.")

    r.ImGui_Separator(ctx)

    -- Phase 31: A/B Diff + Apply
    if r.ImGui_Button(ctx, "Show A/B Diff", 170, 0) then
      local va, oa = _ab_decode(LIBRARY.auditionA)
      local vb, ob = _ab_decode(LIBRARY.auditionB)
      if va and vb then
        LIBRARY.ab_diff = _ab_collect_diffs(va, oa, vb, ob)
      else
        LIBRARY.ab_diff = nil
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Apply A->Current (diff only)", 240, 0) then
      local vc, oc = _ab_decode(LIBRARY.selected_voice_bytes)
      local va, oa = _ab_decode(LIBRARY.auditionA)
      local vb, ob = _ab_decode(LIBRARY.auditionB)
      if vc and oc and va and vb then
        local diffs = LIBRARY.ab_diff or _ab_collect_diffs(va, oa, vb, ob)
        _ab_apply_diffs_to_current(diffs, vc, oc, true)
        local bytes64 = VoiceMap.encode_voice_block(vc, oc)
        LIBRARY.selected_voice_bytes = bytes64
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Apply B->Current (diff only)", 240, 0) then
      local vc, oc = _ab_decode(LIBRARY.selected_voice_bytes)
      local va, oa = _ab_decode(LIBRARY.auditionA)
      local vb, ob = _ab_decode(LIBRARY.auditionB)
      if vc and oc and va and vb then
        local diffs = LIBRARY.ab_diff or _ab_collect_diffs(va, oa, vb, ob)
        _ab_apply_diffs_to_current(diffs, vc, oc, false)
        local bytes64 = VoiceMap.encode_voice_block(vc, oc)
        LIBRARY.selected_voice_bytes = bytes64
      end
    end

    if LIBRARY.ab_diff and #LIBRARY.ab_diff > 0 then
      r.ImGui_Text(ctx, ("A/B diffs: %d"):format(#LIBRARY.ab_diff))
      r.ImGui_BeginChild(ctx, "##abdiff", 0, 120, true)
      local maxshow = math.min(#LIBRARY.ab_diff, 80)
      for i=1,maxshow do
        local d = LIBRARY.ab_diff[i]
        r.ImGui_Text(ctx, ("%s  A=%s  B=%s"):format(d.path, tostring(d.a), tostring(d.b)))
      end
      if #LIBRARY.ab_diff > maxshow then r.ImGui_Text(ctx, "...") end
      r.ImGui_EndChild(ctx)
    end

    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, "Multi-select tagging")
    local _c
    _c, LIBRARY.bulk_tag_edit = r.ImGui_InputText(ctx, "Tags for selected", LIBRARY.bulk_tag_edit or "")
    if r.ImGui_Button(ctx, "Apply to Selected", 160, 0) then
      if not LIBRARY.tags then LIBRARY.tags = {} end
      for k,_ in pairs(LIBRARY.selected_set or {}) do
        LIBRARY.tags[k] = tostring(LIBRARY.bulk_tag_edit or "")
      end
      _lib_save_tags(LIBRARY.tags)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Clear Selected", 140, 0) then
      LIBRARY.selected_set = {}
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Batch actions (selected voices)")

    if r.ImGui_Button(ctx, "Batch Verify Selected", 200, 0) then
      -- Send each selected to target instrument and verify (serial queue)
      if LIBRARY.bank and LIBRARY.bank.voices then
        bank_send_queue = bank_send_queue or {}
        for k,_ in pairs(LIBRARY.selected_set or {}) do
          local _,_,vi = _lib_parse_selected_key(k)
          if vi and vi>=1 and vi<=#LIBRARY.bank.voices then
            bank_send_queue[#bank_send_queue+1] = { inst_no=LIBRARY.batch_target_inst or 0, voice_bytes=LIBRARY.bank.voices[vi], verify=true }
          end
        end
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export Preset Pack", 180, 0) then
      local ok, msg = _lib_export_preset_pack_from_selected()
      if ok then
        LIBRARY.status = "Exported preset pack: " .. tostring(msg)
      else
        LIBRARY.status = "Export failed: " .. tostring(msg)
      end
    end
    local _c
    _c, LIBRARY.batch_target_inst = r.ImGui_SliderInt(ctx, "Target instrument for selected", LIBRARY.batch_target_inst or 0, 0, 7)
    if r.ImGui_Button(ctx, "Send Selected Sequentially", 220, 0) then
      if LIBRARY.bank and LIBRARY.bank.voices then
        bank_send_queue = bank_send_queue or {}
        for k,_ in pairs(LIBRARY.selected_set or {}) do
          local _,_,vi = _lib_parse_selected_key(k)
          if vi and vi >= 1 and vi <= #LIBRARY.bank.voices then
            bank_send_queue[#bank_send_queue+1] = { inst_no=LIBRARY.batch_target_inst or 0, voice_bytes=LIBRARY.bank.voices[vi], verify=false }
          end
        end
      end
    end
r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Batch audition/navigation")
  if r.ImGui_Button(ctx, "Prev Voice", 110, 0) then
    if LIBRARY.voice_sel and LIBRARY.voice_sel > 1 then LIBRARY.voice_sel = LIBRARY.voice_sel - 1 end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Next Voice", 110, 0) then
    if LIBRARY.voice_sel and LIBRARY.voices and LIBRARY.voice_sel < #LIBRARY.voices then LIBRARY.voice_sel = LIBRARY.voice_sel + 1 end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Random Voice", 120, 0) then
    if LIBRARY.voices and #LIBRARY.voices > 0 then LIBRARY.voice_sel = math.random(1, #LIBRARY.voices) end
  end

  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Send 8 selected voices to Inst 0..7 (mapping)")
  if not LIBRARY.batch_map then
    LIBRARY.batch_map = {}
    for i=0,7 do LIBRARY.batch_map[i] = 0 end
  end
  for inst=0,7 do
    local label = "Inst " .. inst .. " <- voice index"
    local cur = LIBRARY.batch_map[inst] or 0
    local _c
    _c, cur = r.ImGui_SliderInt(ctx, label, cur, 0, (LIBRARY.voices and #LIBRARY.voices or 0))
    LIBRARY.batch_map[inst] = cur
  end
  if r.ImGui_Button(ctx, "Send Mapped (0..7)", 180, 0) then
    if LIBRARY.bank and LIBRARY.bank.voices then
      bank_send_queue = bank_send_queue or {}
      for inst=0,7 do
        local vi = LIBRARY.batch_map[inst]
        if vi and vi >= 1 and vi <= #LIBRARY.bank.voices then
          bank_send_queue[#bank_send_queue+1] = { inst_no=inst, voice_bytes=LIBRARY.bank.voices[vi], verify=false }
        end
      end
    end
  end

  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Verify Mapped (0..7)", 200, 0) then
    -- Send each mapped voice to its instrument, then request dump and compare (param diffs exported).
    if LIBRARY.bank and LIBRARY.bank.voices then
      bank_send_queue = bank_send_queue or {}
      for inst=0,7 do
        local vi = LIBRARY.batch_map[inst]
        if vi and vi >= 1 and vi <= #LIBRARY.bank.voices then
          bank_send_queue[#bank_send_queue+1] = { inst_no=inst, voice_bytes=LIBRARY.bank.voices[vi], verify=true }
        end
      end
      -- enable one-shot auto export of diffs if user enabled it
      if LIBRARY.auto_export_reports then
        -- already handled by Phase 14 hook; keep flag
      end
    end
  end

            if r.ImGui_Button(ctx, "Audition Voice to Instrument", 260, 0) then
              local bytes, err = _read_file_bytes(bank_entry.path)
              if bytes and _is_syx(bytes) then
                local bank = select(1, _decode_bank_any(bytes))
                if bank and bank.voices and bank.voices[lib_voice_idx] then
                  local v64 = bank.voices[lib_voice_idx]
                  -- send as inst voice sysex (existing builder)
                  local msg = VoiceDump.build_inst_voice_sysex(sys_ch or sysch or 0, lib_inst_no, v64)
                  send_sysex(string.char(table.unpack(msg)))
                  if lib_verify then
                    CAPTURE.retries_left = CAPTURE_CFG.retry_count_instvoice or 1
                    verify_start("instvoice", v64, {timeout=CAPTURE_CFG.t_instvoice or 2.5, sys_ch=(sys_ch or sysch or 0), inst_no=lib_inst_no})
                    enqueue_sysex(Syx.dump_inst_voice(sys_ch or sysch or 0, lib_inst_no))
                    capture_start("instvoice", CAPTURE_CFG.t_instvoice or 2.5)
                  end
                else
                  r.MB("Bank decode failed or missing voice.", "Library", 0)
                end
              else
                r.MB("Could not read .syx file.", "Library", 0)
              end
            end
          end
        end
      end
      
    r.ImGui_EndChild(ctx)
r.ImGui_EndTabItem(ctx)
    end

ImGui_EndTabBar(ctx)
      end
    end

  else
    -- Default: OP Tabs (OP1..OP4)
    if r.ImGui_BeginTabBar(ctx, "op_tabs") then
      for op_idx=0,3 do
        if r.ImGui_BeginTabItem(ctx, "OP"..tostring(op_idx+1), true) then
          local t = op_vals[op_idx+1]
          for _,it in ipairs(P.operator_params) do
            local key = it.param
            local v = t[key] or 0
            local lock = is_locked("op", op_idx, key)
            local chkl, nlock = r.ImGui_Checkbox(ctx, "L##oplock"..op_idx.."_"..key, lock)
            if chkl then set_locked("op", op_idx, key, nlock) end
            r.ImGui_SameLine(ctx)
            local ch, nv = r.ImGui_SliderInt(ctx, it.name .. "##op"..op_idx.."_"..key, v, it.min or 0, it.max or 127)
            if ch then
              nv = clamp(nv, it.min or 0, it.max or 127)
              t[key] = nv
              send_op_param(op_idx, key, nv)
            end
          end
          r.ImGui_EndTabItem(ctx)
        end
      end
      r.ImGui_EndTabBar(ctx)
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function instrument_panel()
  r.ImGui_Text(ctx, "Instrument params (7-bit)")
  for _,it in ipairs(P.instrument_params) do
    local key = it.param
    local v = inst_vals[key] or 0
    local lock = is_locked("instrument", key)
    local chkl, nlock = r.ImGui_Checkbox(ctx, "L##ilock"..key, lock)
    if chkl then set_locked("instrument", key, nil, nlock) end
    r.ImGui_SameLine(ctx)
    local ch, nv = r.ImGui_SliderInt(ctx, it.name .. "##i"..key, v, 0, 127)
    if ch then
      nv = clamp(nv, 0, 127)
      inst_vals[key] = nv
      local msg = Syx.instrument_param(sysch, inst, key, nv)
      if live_send_per_change then send_sysex(msg) end
      if autosend and autosend_mode==1 then
        local now = reaper.time_precise()
        if (now - autosend_last_send) * 1000.0 >= autosend_ms then
          autosend_last_send = now
          send_sysex(msg)
        end
      end
            if autosend and autosend_mode==0 and snapshot_preview_while_dragging then
        local now = reaper.time_precise()
        if (now - autosend_last_send) * 1000.0 >= autosend_ms then
          autosend_last_send = now
          send_sysex(msg)
        end
      end
if autosave_slot then autosave_deb:request() end
      local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)
      if deact and autosend and autosend_mode==1 and autosend_final_on_release then
        send_sysex(msg)
      end
      if deact and autosend and autosend_mode==0 then autosend_deb:request() end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

local function requests_panel()
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Randomize: Voice", 160, 0) then randomize("voice") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Randomize: All Ops", 160, 0) then randomize("ops") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Randomize: All", 160, 0) then randomize("all") end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Constrained random")
    local chg_i, ni = r.ImGui_SliderDouble(ctx, "Random intensity", rand_intensity, 0.0, 1.0)
    if chg_i then rand_intensity = ni end
    if r.ImGui_Button(ctx, "Rand: OP Env", 120, 0) then randomize_groups_intensity({ops_env=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: OP Pitch", 120, 0) then randomize_groups_intensity({ops_pitch=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: OP Level", 120, 0) then randomize_groups_intensity({ops_level=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: Voice LFO", 140, 0) then randomize_groups_intensity({voice_lfo=true}, rand_intensity) end

    if r.ImGui_Button(ctx, "Save patch state (JSON)", 200, 0) then save_state_json() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Load patch state (JSON)", 200, 0) then load_state_json() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export .syx (param stream)", 200, 0) then export_param_stream_syx() end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "User templates")
    local names = ""
    for i=1,#(user_db.templates or {}) do names = names .. (user_db.templates[i].name or ("Template "..i)) .. "\0" end
    if names == "" then names = " (none)\0" end
    local chg_u, new_u = r.ImGui_Combo(ctx, "Saved", user_tpl_idx, names)
    if chg_u then user_tpl_idx = new_u end
    if r.ImGui_Button(ctx, "Apply Saved Template", 180, 0) then
      local t = (user_db.templates or {})[user_tpl_idx+1]
      if t then apply_template(t) end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save Current as Template", 200, 0) then
      local okN, nm = r.GetUserInputs("Save Template", 1, "Name", "My Template")
      if okN and nm ~= "" then
        user_db = load_user_templates()
        user_db.templates = user_db.templates or {}
        user_db.templates[#user_db.templates+1] = capture_current_as_template(nm)
        save_user_templates(user_db)
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Reload Templates", 140, 0) then
      user_db = load_user_templates()
      user_tpl_idx = 0
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Templates (starting points)")
    local combo_str = ""
    for i=1,#template_names do combo_str = combo_str .. template_names[i] .. "\0" end
    local chg_t, new_idx = r.ImGui_Combo(ctx, "Template", template_idx, combo_str)
    if chg_t then template_idx = new_idx end
    if r.ImGui_Button(ctx, "Apply Template", 160, 0) then
      local name = template_names[template_idx+1]
      if name and TEMPLATES[name] then apply_template(TEMPLATES[name]) end
    end

    
  if r.ImGui_Button(ctx, "Request Voice Dump (current instrument)", -1, 0) then
    send_sysex(Syx.request_voice(sysch, inst))
  end
  if r.ImGui_Button(ctx, "Request Set Dump", -1, 0) then
    send_sysex(Syx.request_set(sysch))
  end
  if r.ImGui_Button(ctx, "Request Bank Dump (0)", -1, 0) then
    send_sysex(Syx.request_bank(sysch, 0))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

-- Build a full param-stream snapshot (voice + ops + instrument) as SysEx message list.
local function build_param_stream_msgs()
  local msgs = {}
  -- voice params
  for key,val in pairs(voice_vals or {}) do
    msgs[#msgs+1] = Syx.voice_param(sysch, inst, key, val)
  end
  -- operator params (assumes op_vals[op][key])
  if type(op_vals) == "table" then
    for op=1,4 do
      if type(op_vals[op]) == "table" then
        for key,val in pairs(op_vals[op]) do
          msgs[#msgs+1] = Syx.operator_param(sysch, inst, op, key, val)
        end
      end
    end
  end
  -- instrument params
  for key,val in pairs(inst_vals or {}) do
    msgs[#msgs+1] = Syx.instrument_param(sysch, inst, key, val)
  end
  return msgs
end

local function commit_bound_snapshot(mark_saved)
  local scope, slot = SlotCore.get_bound_slot()
  if scope ~= "fb01" or not slot then return end
  local msgs = build_param_stream_msgs()
  local state = SlotCore.load_state("fb01", 8)
  local slots = state.slots
  local name = (current_preset_name and current_preset_name ~= "" and current_preset_name) or ("FB01 Slot %d"):format(slot)
  SlotCore.slot_commit_multi(slots, slot, name, msgs, "")
  if mark_saved then SlotCore.slot_mark_saved(slots, slot) end
  SlotCore.save_state("fb01", { meta = state.meta, slots = slots })
  last_autosave_at = r.time_precise()
end

local autosave_deb = SlotCore.make_debouncer(autosave_ms, function() commit_bound_snapshot(false) end)
local autosend_deb = SlotCore.make_debouncer(autosend_ms, function()
  local msgs = build_param_stream_msgs()
  for i=1,#msgs do r.SNM_SendSysEx(msgs[i]); r.Sleep(8) end
  last_autosend_at = r.time_precise()
end)
local function loop()
  Rx.poll(64)
  if Rx.poll_take_backend then Rx.poll_take_backend() end
  if capture_tick_v2 then capture_tick_v2() else if capture_tick then capture_tick() end end
  pump_send_queue()

if auto_decode then
  local last = Rx.get_last_dump()
  if last and last.ts and last.ts ~= last_seen_dump_ts then
    last_seen_dump_ts = last.ts
    local res = DumpDec.decode_sysex(last.bytes)

-- B2.23: also decode configuration dumps (raw7 or nibble-packed) for roundtrip verification
local cfg, cfgerr = nil, "Config dump module missing"
if ConfigDump and ConfigDump.decode_config_from_sysex then
  cfg, cfgerr = ConfigDump.decode_config_from_sysex(last.bytes)
end
if cfg then
  last_rx_config = cfg
  last_rx_config_raw = last.bytes
  if pending_capture == "A" then cfg_A = cfg; pending_capture = nil end
  if pending_capture == "B" then cfg_B = cfg; pending_capture = nil end
end

if verify_stage == "await_dump" and last_rx_config and verify_target then
  if not (ConfigDump and ConfigDump.diff_bytes) then
    verify_result = { ok=false, diffs=-1, err="ConfigDump module missing" }
    verify_stage = "done"
  else
    local diffs = ConfigDump.diff_bytes(verify_target, last_rx_config.payload_bytes or {})
    verify_result = { ok=(#diffs==0), diffs=#diffs, preview=diffs }
    verify_stage = "done"
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

    if res and res.ok then
      last_decoded = res.decoded
      last_names = res.names
      last_decode_info = res.info
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
  local visible, open = r.ImGui_Begin(ctx, "IFLS FB-01 Sound Editor (MVP)", true, r.ImGui_WindowFlags_MenuBar())
  if visible then
  -- Phase 5: show last RX backend + last dump timestamp
  local _last = (Rx and Rx.get_last_dump) and Rx.get_last_dump() or nil
  if _last then
    CAPTURE.last_backend = _last.backend or CAPTURE.last_backend
    CAPTURE.last_rx_ts = _last.ts or CAPTURE.last_rx_ts
  end
  r.ImGui_Text(ctx, ("Last backend: %s   Last dump seen: %s"):format(
    tostring(CAPTURE.last_backend or "(none)"),
    (CAPTURE.last_rx_ts and os.date("%Y-%m-%d %H:%M:%S") or "(none)")
  ))
  r.ImGui_Separator(ctx)

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Slot Bind + Autosave/Auto-send")
    local bs, bn = SlotCore.get_bound_slot()
    local btxt = (bs and bn) and (bs .. ":" .. tostring(bn)) or "(none)"
    r.ImGui_Text(ctx, "Bound slot: " .. btxt)

    local chls, lspc = r.ImGui_Checkbox(ctx, "Live send per-change", live_send_per_change)
    if chls then live_send_per_change = lspc end

    local chas, av = r.ImGui_Checkbox(ctx, "Autosave Slot (debounced)", autosave_slot)
    if chas then autosave_slot = av end
    r.ImGui_SameLine(ctx)
    local chms, ms = r.ImGui_SliderInt(ctx, "Autosave ms", autosave_ms, 200, 800)
    if chms then autosave_ms = ms; autosave_deb:set_delay(autosave_ms) end

    local chsnd, asv = r.ImGui_Checkbox(ctx, "Auto Send", autosend)
    if chsnd then autosend = asv end
    if autosend then
      r.ImGui_SameLine(ctx)
      local chm, nm = r.ImGui_Combo(ctx, "AutoSend Mode", autosend_mode, "Snapshot (debounced)\0Per-change\0")
      if chm then autosend_mode = nm end
if autosend then
  if autosend_mode == 1 then
    local cf, nv = r.ImGui_Checkbox(ctx, "Send final on release", autosend_final_on_release)
    if cf then autosend_final_on_release = nv end
  else
    local cp, pv = r.ImGui_Checkbox(ctx, "Preview while dragging", snapshot_preview_while_dragging)
    if cp then snapshot_preview_while_dragging = pv end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
    end
    r.ImGui_SameLine(ctx)
    local chs2, ms2 = r.ImGui_SliderInt(ctx, "AutoSend ms", autosend_ms, 80, 400)
    if chs2 then autosend_ms = ms2; autosend_deb:set_delay(autosend_ms) end

    if r.ImGui_Button(ctx, "Commit snapshot to bound slot now", 220, 0) then commit_bound_snapshot(false) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Mark saved", 120, 0) then commit_bound_snapshot(true) end
    r.ImGui_Separator(ctx)

if r.ImGui_CollapsingHeader(ctx, "Config Dump + Verify", 0) then
  r.ImGui_Text(ctx, "Request FB-01 config dumps, capture A/B and diff payload bytes. Export last dump to disk.")
  r.ImGui_Separator(ctx)

  if r.ImGui_Button(ctx, "Request: Current Config") then
    enqueue_sysex(Syx.dump_current_config(sys_ch or sysch or 0))
  end
  r.ImGui_SameLine(ctx)
  local _c
  _c, cfg_slot = r.ImGui_SliderInt(ctx, "Slot (0..20)", cfg_slot, 0, 20)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Request: Slot") then
    enqueue_sysex(Syx.dump_config_slot(sys_ch or sysch or 0, cfg_slot))
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Request: All Config") then
    enqueue_sysex(Syx.dump_all_config(sys_ch or sysch or 0))
  end

-- =========================
-- Config Librarian (Phase 25): Capture/Store/Send/Verify config slots
-- =========================
if not CONFIG_LIB then
  CONFIG_LIB = {
    slot = 0,
    store = {}, -- slot -> payload_bytes
    status = "",
    verify_slot = 0,
    allow_write = false,
  }
end

local function _config_store_path() return _lib_db_dir() .. "/config_presets.json" end
local function _config_load_store()
  local f = io.open(_config_store_path(), "rb"); if not f then return {} end
  local s = f:read("*all"); f:close()
  local t = (r.JSON_Parse and r.JSON_Parse(s)) or nil
  return t and t.store or {}
end
local function _config_save_store(store)
  local f = io.open(_config_store_path(), "wb"); if not f then return false end
  f:write("{\"store\":{")
  local first=true
  for k,v in pairs(store or {}) do
    if not first then f:write(",") end; first=false
    f:write(("\"%s\":["):format(tostring(k)))
    for i=1,#v do if i>1 then f:write(",") end; f:write(tostring(v[i] & 0x7F)) end
    f:write("]")
  end
  f:write("}}\n"); f:close()
  return true
end

if not CONFIG_LIB.store_loaded then
  CONFIG_LIB.store = _config_load_store()
  CONFIG_LIB.store_loaded = true
end

r.ImGui_Text(ctx, "Config Librarian (Phase 25)")
local _c
_c, CONFIG_LIB.slot = r.ImGui_SliderInt(ctx, "Preset Slot", CONFIG_LIB.slot or 0, 0, 20)

if r.ImGui_Button(ctx, "Capture last config dump -> Slot", 280, 0) then
  local last = Rx and Rx.get_last_dump and Rx.get_last_dump()
  if last and last.bytes and ConfigDump and ConfigDump.decode_config_from_sysex then
    local cfg, err = ConfigDump.decode_config_from_sysex(last.bytes)
    if cfg and cfg.payload_bytes then
      CONFIG_LIB.store[tostring(CONFIG_LIB.slot)] = { payload = cfg.payload_bytes, cmd_prefix = cfg.cmd_prefix }
      _config_save_store(CONFIG_LIB.store)
      CONFIG_LIB.status = "Captured into slot " .. tostring(CONFIG_LIB.slot) .. (cfg.checksum_ok and " (cs ok)" or " (cs mismatch)")
    else
      CONFIG_LIB.status = "Decode failed: " .. tostring(err)
    end
  else
    CONFIG_LIB.status = "No last dump or Rx missing"
  end
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Request Slot (dump)", 180, 0) then
  enqueue_sysex(Syx.dump_config_slot(CAPTURE_CFG.sys_ch or 0, CONFIG_LIB.slot or 0))
end

r.ImGui_SameLine(ctx)
_c, CONFIG_LIB.allow_write = r.ImGui_Checkbox(ctx, "Allow write", CONFIG_LIB.allow_write or false)

if r.ImGui_Button(ctx, "Send Slot -> Instrument (SysCh)", 280, 0) then
  local _slot = CONFIG_LIB.store[tostring(CONFIG_LIB.slot)]
  local payload = (_slot and _slot.payload) or _slot
  local cmd_prefix = (_slot and _slot.cmd_prefix) or nil
  if payload and CONFIG_LIB.allow_write then
    local msg = ConfigDump.build_config_sysex(CAPTURE_CFG.sys_ch or 0, payload, cmd_prefix)
    if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
    CONFIG_LIB.status = "Sent config slot payload (write enabled)"
  else
    CONFIG_LIB.status = payload and "Enable 'Allow write' to send" or "No data in slot"
  end
end

r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Verify Slot (request->compare)", 280, 0) then
  local _slot = CONFIG_LIB.store[tostring(CONFIG_LIB.slot)]
  local payload = (_slot and _slot.payload) or _slot
  local cmd_prefix = (_slot and _slot.cmd_prefix) or nil
  if payload then
    VERIFY.pending = true
    VERIFY.kind = "config"
    VERIFY.target = payload
    VERIFY.started = r.time_precise()
    VERIFY.timeout = 8.0
    enqueue_sysex(Syx.dump_config_slot(CAPTURE_CFG.sys_ch or 0, CONFIG_LIB.slot or 0))
    CONFIG_LIB.status = "Verify pending..."
  else
    CONFIG_LIB.status = "No data in slot"
  end
end

-- Phase 26: Show decoded slot summary (instrument 0 preview)
if ConfigDump and ConfigDump.decode_payload_to_params and CONFIG_LIB.store then
  local _slot = CONFIG_LIB.store[tostring(CONFIG_LIB.slot)]
  local payload = (_slot and _slot.payload) or _slot
  local cmd_prefix = (_slot and _slot.cmd_prefix) or nil
  if payload then
    local dec = ConfigDump.decode_payload_to_params(payload)
    if dec and dec.instruments and dec.instruments[0] then
      local t = dec.instruments[0]
      r.ImGui_Text(ctx, ("Slot %d preview inst0: ch=%s bank=%s voice=%s level=%s pan=%s"):format(
        CONFIG_LIB.slot or 0,
        tostring(t.midi_ch or "?"),
        tostring(t.voice_bank or "?"),
        tostring(t.voice_no or "?"),
        tostring(t.out_level or "?"),
        tostring(t.pan or "?")
      ))
    end
  end
end

if CONFIG_LIB.status and CONFIG_LIB.status ~= "" then r.ImGui_Text(ctx, "Status: " .. tostring(CONFIG_LIB.status)) end

-- =========================
-- Phase 27: Multi-instrument Config Editor (cfg_* canonical) + Safety
-- =========================
if not CFG_MULTI then
  CFG_MULTI = { tab=0, decoded=nil, status="", memprotect_checked=false, confirm_write=false, mode="spread" }
end

-- load decoded from selected preset slot if available
local payload = CONFIG_LIB and CONFIG_LIB.store and CONFIG_LIB.store[tostring(CONFIG_LIB.slot)]
if payload and ConfigDump and ConfigDump.decode_payload_to_params then
  CFG_MULTI.decoded = ConfigDump.decode_payload_to_params(payload)
end
if not CFG_MULTI.decoded then CFG_MULTI.decoded = { instruments = {} } end
CFG_MULTI.decoded.instruments = CFG_MULTI.decoded.instruments or {}

-- Mode selector + randomize performance
do
  local modes = "spread (layer)\0split\0\0"
  local mi = (CFG_MULTI.mode=="split") and 2 or 1
  local c
  c, mi = r.ImGui_Combo(ctx, "Config Randomize Mode", mi, modes)
  if c then CFG_MULTI.mode = (mi==2) and "split" or "spread" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Randomize Config (Phase 27)", 240, 0) then
    CFG_MULTI.decoded = _cfg_randomize(CFG_MULTI.decoded, CFG_MULTI.mode)
    CFG_MULTI.status = "Randomized config: " .. tostring(CFG_MULTI.mode)
  end
end

-- Tabs Inst0..7
if r.ImGui_BeginTabBar(ctx, "##cfg_tabs") then
  for inst=0,7 do
    if r.ImGui_BeginTabItem(ctx, "Inst "..tostring(inst)) then
      local t = CFG_MULTI.decoded.instruments[inst] or _cfg_defaults()
      CFG_MULTI.decoded.instruments[inst] = t
      _schema_draw_group(ctx, t, ("i%d."):format(inst), "config.instrument")
      -- Phase 28: Copy/Paste instrument
      CFG_MULTI.clip = CFG_MULTI.clip or nil
      if r.ImGui_Button(ctx, "Copy Inst -> Clipboard", 220, 0) then
        local cpy = {}
        for k,v in pairs(t) do cpy[k]=v end
        CFG_MULTI.clip = cpy
        CFG_MULTI.status = "Copied inst " .. tostring(inst)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Paste Clipboard -> Inst", 220, 0) then
        if CFG_MULTI.clip then for k,v in pairs(CFG_MULTI.clip) do t[k]=v end end
        CFG_MULTI.status = "Pasted into inst " .. tostring(inst)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Apply Inst to ALL", 180, 0) then
        for ii=0,7 do
          if ii ~= inst then
            local tt = CFG_MULTI.decoded.instruments[ii] or _cfg_defaults(); CFG_MULTI.decoded.instruments[ii]=tt
            for k,v in pairs(t) do tt[k]=v end
          end
        end
        CFG_MULTI.status = "Applied inst " .. tostring(inst) .. " to all"
      end
      r.ImGui_EndTabItem(ctx)
    end
  end
  r.ImGui_EndTabBar(ctx)
end

-- Apply edited decoded -> payload in slot store
if r.ImGui_Button(ctx, "Apply Editor -> Slot Payload", 240, 0) then
  if ConfigDump and ConfigDump.encode_params_to_payload then
    local current = CONFIG_LIB.store[tostring(CONFIG_LIB.slot)] or {}
    local newp = ConfigDump.encode_params_to_payload(CFG_MULTI.decoded, current)
    CONFIG_LIB.store[tostring(CONFIG_LIB.slot)] = newp
    _config_save_store(CONFIG_LIB.store)
    CFG_MULTI.status = "Applied to slot " .. tostring(CONFIG_LIB.slot)
  end
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Export Config Slot Bundle", 240, 0) then
  local _slotE = CONFIG_LIB.store[tostring(CONFIG_LIB.slot)]
  local payloadE = (_slotE and _slotE.payload) or _slotE
  local cmdE = (_slotE and _slotE.cmd_prefix) or nil
  if payloadE then
    local ts = os.date("%Y%m%d_%H%M%S")
    local dir = _lib_exports_dir() .. "/ConfigBundle_" .. ts
    r.RecursiveCreateDirectory(dir, 0)
    local msg = ConfigDump.build_config_sysex(CAPTURE_CFG.sys_ch or 0, payloadE, cmdE)
    local f = io.open(dir .. "/config_slot"..tostring(CONFIG_LIB.slot)..".syx", "wb")
    if f then for i=1,#msg do f:write(string.char(msg[i] & 0xFF)) end; f:close() end
    CFG_MULTI.status = "Exported bundle: " .. tostring(dir)
  end
end

-- Safety: memory protect checklist + confirm write
local c
c, CFG_MULTI.memprotect_checked = r.ImGui_Checkbox(ctx, "Memory Protect OFF (I checked)", CFG_MULTI.memprotect_checked)
r.ImGui_SameLine(ctx)
c, CFG_MULTI.confirm_write = r.ImGui_Checkbox(ctx, "Confirm WRITE", CFG_MULTI.confirm_write)

if r.ImGui_Button(ctx, "Write + Verify (Safe)", 220, 0) then
  local payload2 = CONFIG_LIB.store[tostring(CONFIG_LIB.slot)]
  if payload2 and CFG_MULTI.memprotect_checked and CFG_MULTI.confirm_write then
    local msg = ConfigDump.build_config_sysex(CAPTURE_CFG.sys_ch or 0, payload2)
    if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
    -- queue verify after short delay by setting VERIFY with longer timeout and request
    VERIFY.pending = true
    VERIFY.kind = "config"
    VERIFY.target = payload2
    VERIFY.started = r.time_precise()
    VERIFY.timeout = 10.0
    VERIFY.retries = 2
    VERIFY.req_fn = function()
      enqueue_sysex(Syx.dump_config_slot(CAPTURE_CFG.sys_ch or 0, CONFIG_LIB.slot or 0))
    end
    -- request once immediately
    VERIFY.req_fn()
    CFG_MULTI.status = "Write sent; verify pending..."
  else
    CFG_MULTI.status = "Blocked: need slot payload + both safety checkboxes"
  end
end

if CFG_MULTI.status and CFG_MULTI.status ~= "" then r.ImGui_Text(ctx, "Config Editor: " .. tostring(CFG_MULTI.status)) end
r.ImGui_Separator(ctx)

r.ImGui_Separator(ctx)

r.ImGui_Separator(ctx)
r.ImGui_Text(ctx, "TrueBulk Send + Verify:")
local _c2
_c2, bulk_syx_path = r.ImGui_InputText(ctx, "SYX path", bulk_syx_path, 4096)
if r.ImGui_Button(ctx, "Load .syx") then
  bulk_bytes = read_file_bytes(bulk_syx_path)
  if bulk_bytes then
    if ConfigDump and ConfigDump.decode_config_from_sysex then
      bulk_cfg, bulk_err = ConfigDump.decode_config_from_sysex(bulk_bytes)
    else
      bulk_cfg, bulk_err = nil, "ConfigDump module missing"
    end
    if bulk_cfg then
      verify_target = bulk_cfg.payload_bytes
    end
  else
    bulk_err = "could not read file"
    bulk_cfg = nil
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "TrueBulk Send (.syx)") then
  if bulk_bytes then
    enqueue_sysex(bulk_bytes)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send + Verify") then
  if bulk_bytes and verify_target then
    verify_result = nil
    verify_stage = "await_ack"
    enqueue_sysex(bulk_bytes)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Auto Capture + Send+Verify") then
  if bulk_bytes and verify_target then
    verify_result = nil
    verify_stage = "await_ack"
    -- Start capture BEFORE sending bulk so we don't miss the response dump
    local function _send()
      enqueue_sysex(bulk_bytes)
    end
    capture_start("config", _send, { timeout = 6.0 })
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

if bulk_cfg then
  r.ImGui_Text(ctx, string.format("Loaded: typ=%d arg=%d enc=%s payloadBytes=%d",
    bulk_cfg.typ or -1, bulk_cfg.arg or -1, bulk_cfg.encoding or "?", #(bulk_cfg.payload_bytes or {})))
elseif bulk_err then
  r.ImGui_Text(ctx, "Load error: " .. tostring(bulk_err))
end

if verify_stage then
  r.ImGui_Text(ctx, "Verify stage: " .. tostring(verify_stage))
end
if verify_result then
  if verify_result.ok then
    r.ImGui_Text(ctx, "VERIFY: PASS (0 diffs)")
  else
    r.ImGui_Text(ctx, "VERIFY: FAIL diffs=" .. tostring(verify_result.diffs) .. " err=" .. tostring(verify_result.err))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

  if last_rx_config then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, string.format("Last RX Config: typ=%d arg=%d enc=%s bytes=%d",
      last_rx_config.typ or -1, last_rx_config.arg or -1,
      last_rx_config.encoding or "?", #(last_rx_config.payload_bytes or {})))

    if r.ImGui_Button(ctx, "Capture A") then cfg_A = last_rx_config end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Capture B") then cfg_B = last_rx_config end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Auto Capture A (Request Current)") then
      pending_capture = "A"; cfg_A = nil
      enqueue_sysex(Syx.dump_current_config(sys_ch or sysch or 0))
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Auto Capture B (Request Current)") then
      pending_capture = "B"; cfg_B = nil
      enqueue_sysex(Syx.dump_current_config(sys_ch or sysch or 0))
    end

    if r.ImGui_Button(ctx, "Export last dump (.syx)") then
      r.RecursiveCreateDirectory(cfg_export_dir, 0)
      local fname = cfg_export_dir .. "/fb01_config_" .. now_stamp() .. ".syx"
      write_bytes_to_file(fname, last_rx_config_raw or {})
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export payload (.bin)") then
      r.RecursiveCreateDirectory(cfg_export_dir, 0)
      local fname = cfg_export_dir .. "/fb01_config_payload_" .. now_stamp() .. ".bin"
      write_bytes_to_file(fname, last_rx_config.payload_bytes or {})
    end

    if cfg_A and cfg_B then
      local diffs = {}
      if ConfigDump and ConfigDump.diff_bytes then
        diffs = ConfigDump.diff_bytes(cfg_A.payload_bytes, cfg_B.payload_bytes)
      end
      r.ImGui_Separator(ctx)
      r.ImGui_Text(ctx, string.format("Diff: %d byte(s) differ", #diffs))
      if r.ImGui_BeginChild(ctx, "cfgdiff", -1, 160, 0) then
        for i=1,math.min(#diffs, 200) do
          local d = diffs[i]
          r.ImGui_Text(ctx, string.format("Byte %d: %02X -> %02X", (d.i-1), d.a & 0xFF, d.b & 0xFF))
        end
        if #diffs > 200 then r.ImGui_Text(ctx, "... (truncated)") end
        r.ImGui_EndChild(ctx)
      end
    end
  else
    r.ImGui_Text(ctx, "No config dump received yet (enable Auto Decode and request a dump).")

if r.ImGui_CollapsingHeader(ctx, "Single Voice Import / Apply", 0) then
  r.ImGui_Text(ctx, "Load a single-voice .syx (InstVoice header), apply to UI, optionally send to an instrument and verify by re-dumping.")
  r.ImGui_Separator(ctx)
  local _c
  _c, sv_import_path = r.ImGui_InputText(ctx, "Voice .syx path", sv_import_path, 4096)
  if r.ImGui_Button(ctx, "Load Voice .syx") then
    sv_import = nil
    sv_import_err = nil
    sv_verify_result = nil
    local bytes = read_file_bytes(sv_import_path)
    if bytes then
      local res, err = VoiceDump.decode_inst_voice_from_sysex(bytes)
      if res then
        sv_import = res
        sv_send_inst = res.inst_no or 0
      else
        sv_import_err = err
      end
    else
      sv_import_err = "could not read file"
    end
  end
  if sv_import_err then
    r.ImGui_Text(ctx, "Load error: " .. tostring(sv_import_err))
  end
  if sv_import then
    r.ImGui_Text(ctx, string.format("Loaded: sys_ch=%d inst=%d voiceBytes=%d", sv_import.sys_ch or -1, sv_import.inst_no or -1, #(sv_import.voice_bytes or {})))
    _c, sv_send_inst = r.ImGui_SliderInt(ctx, "Send to Inst (0..7)", sv_send_inst, 0, 7)
    r.ImGui_SameLine(ctx)
    _c, sv_auto_verify = r.ImGui_Checkbox(ctx, "Auto verify (re-dump inst voice)", sv_auto_verify == true)

    if r.ImGui_Button(ctx, "Apply to UI (decode)") then
      -- Decode to voice_vals/op_vals via VoiceMap, like bank apply
      local bytes = sv_import.voice_bytes
      local vvals, ovals = VoiceMap.decode_voice_block(bytes)
      for k,val in pairs(vvals) do voice_vals[k] = val end
      for op=1,4 do for k,val in pairs(ovals[op]) do op_vals[op][k] = val end end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Generate & Send ONE-VOICE BULK (native)", 340, 0) then

  if r.ImGui_Button(ctx, "Run Native One-Voice Bulk Verify Harness", 330, 0) then
    if not (CAPTURE_CFG and CAPTURE_CFG.allow_native_bulk) then
      r.MB("Enable native bulk builders (Phase 10/10.1) first.", "Native Verify Harness", 0)
    elseif not (sv_import and sv_import.voice_bytes and #sv_import.voice_bytes==64) then
      r.MB("Import a single voice (64 bytes) first.", "Native Verify Harness", 0)
    else
      NATIVE_HARNESS.active = true
      NATIVE_HARNESS.kind = "instvoice_native_bulk"
      NATIVE_HARNESS.step = "sending"
      NATIVE_HARNESS.settings = _snapshot_native_settings()
      CAPTURE.retries_left = (CAPTURE_CFG.retry_count_instvoice or 1)
      CAPTURE.attempt = 0
      capture_start("instvoice", CAPTURE_CFG.t_instvoice or 2.5)
      local opts = {
        strict_checksum = CAPTURE_CFG.native_strict_checksum,
        bytecount_two_bytes = CAPTURE_CFG.native_bytecount_two,
        chunk_source_bytes = CAPTURE_CFG.native_chunk_source_bytes or 48,
      }
      local msg, err = BulkNative.build_one_voice_bulk(sysch or 0, inst_no or 0, sv_import.voice_bytes, opts)
      if not msg then
        r.MB("Native one-voice bulk build failed: " .. tostring(err), "Native Verify Harness", 0)
        NATIVE_HARNESS.active = false
      else
        send_sysex_throttled(msg, CAPTURE_CFG.bulk_delay_ms or 120)
        enqueue_sysex(Syx.dump_inst_voice(sysch or 0, inst_no or 0))
        verify_start("instvoice", sv_import.voice_bytes, {timeout=CAPTURE_CFG.t_instvoice or 2.5, sys_ch=(sysch or 0), inst_no=(inst_no or 0)})
      end
    end
  end
    if CAPTURE_CFG.allow_native_bulk_builders ~= 1 then
      r.MB("Enable 'native bulk builders' in settings first (experimental).", "Native Bulk", 0)
    else
      if sv_import and sv_import.voice_bytes and #sv_import.voice_bytes >= 64 then
        local msg, err = BulkNative.build_one_voice_bulk(sysch, inst_no or 0, sv_import.voice_bytes, { strict_checksum = (CAPTURE_CFG.allow_native_bulk_strict==1), bytecount_two_bytes = (CAPTURE_CFG.native_bytecount_two==1), checksum_from_body_index = 4 })
        if not msg then
          r.MB("Native bulk build failed: " .. tostring(err), "Native Bulk", 0)
        else
          send_sysex_throttled(string.char(table.unpack(msg)), CAPTURE_CFG.bulk_delay_ms or 120)
        end
      else
        r.MB("No 64-byte voice loaded. Import a voice first.", "Native Bulk", 0)
      end
    end
  end
 (InstVoice)") then
      local msg = VoiceDump.build_inst_voice_sysex(sys_ch or sysch or 0, sv_send_inst, sv_import.voice_bytes)
      if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
      if sv_auto_verify then
        verify_start("instvoice", sv_import.voice_bytes, { sys_ch = (sys_ch or sysch or 0), inst_no = sv_send_inst, timeout = 2.5 })
        enqueue_sysex(Syx.dump_inst_voice(sys_ch or sysch or 0, sv_send_inst))
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Auto Capture + Send+Verify") then
      -- Record a short MIDI capture so large SysEx dumps can be read back reliably
      local _sys = (sys_ch or sysch or 0)
      local _inst = sv_send_inst
      local function _send()
        local msg = VoiceDump.build_inst_voice_sysex(_sys, _inst, sv_import.voice_bytes)
        if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
        verify_start("instvoice", sv_import.voice_bytes, { sys_ch=_sys, inst_no=_inst, timeout=2.5 })
        enqueue_sysex(Syx.dump_inst_voice(_sys, _inst))
      end
      capture_start("instvoice", _send, { timeout = 4.0 })
    end

    if sv_verify_pending then
      r.ImGui_Text(ctx, "Verify: waiting for inst voice dumpâ€¦")
    end
    if sv_verify_result then
      if sv_verify_result.ok then
        r.ImGui_Text(ctx, "VERIFY: PASS (0 diffs)")
      else
        r.ImGui_Text(ctx, "VERIFY: FAIL diffs=" .. tostring(sv_verify_result.diffs))
      end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

if r.ImGui_CollapsingHeader(ctx, "Bank Import / Extract", 0) then
  r.ImGui_Text(ctx, "Load a 48-voice bank .syx, list patch names, export selected (bin/json/syx) and optionally send to an instrument.")
r.ImGui_Separator(ctx)

-- Phase 4: Auto capture bank dump (robust for large SysEx)
local names = _list_midi_inputs()
local items = _midi_input_combo_items(names)
local pref_idx = (CAPTURE_CFG.pref_midi_in == -2) and 0 or ((CAPTURE_CFG.pref_midi_in == -1) and 1 or (CAPTURE_CFG.pref_midi_in + 2)) -- 0=auto,1=all,2..=device0..
local changed
changed, pref_idx = r.ImGui_Combo(ctx, "Preferred MIDI Input", pref_idx, items)
if changed then
  if pref_idx == 0 then CAPTURE_CFG.pref_midi_in = -2
  elseif pref_idx == 1 then CAPTURE_CFG.pref_midi_in = -1
  else CAPTURE_CFG.pref_midi_in = pref_idx - 2 end
  _ext_set("preferred_midi_input", CAPTURE_CFG.pref_midi_in)
end

-- Phase 22: Preferred MIDI Output (for track routing setups / documentation)
do
  local out_items = {"All (track routing)"}
  local out_map = {-1}
  local nouts = (r.GetNumMIDIOutputs and r.GetNumMIDIOutputs()) or 0
  for i=0,nouts-1 do
    local rv, name = r.GetMIDIOutputName(i, "")
    out_items[#out_items+1] = (rv and name) or ("MIDI Out " .. tostring(i))
    out_map[#out_map+1] = i
  end
  local cur = 1
  for ii=1,#out_map do
    if out_map[ii] == (CAPTURE_CFG.preferred_midi_out or -1) then cur = ii break end
  end
  local changed
  changed, cur = r.ImGui_Combo(ctx, "Preferred MIDI Output", cur, table.concat(out_items, "\0") .. "\0")
  if changed then
    CAPTURE_CFG.preferred_midi_out = out_map[cur] or -1
    CAPTURE_CFG.preferred_midi_out_name = out_items[cur] or ""
    _ext_set("fb01_preferred_midi_out", CAPTURE_CFG.preferred_midi_out)
    _ext_set("fb01_preferred_midi_out_name", CAPTURE_CFG.preferred_midi_out_name)
  end
  local sm = CAPTURE_CFG.send_mode or "track"
  local modes = "track (recommended)\0direct (unsupported)\0\0"
  local mi = (sm == "direct") and 2 or 1
  local c2
  c2, mi = r.ImGui_Combo(ctx, "SysEx Send Mode", mi, modes)
  if c2 then
    CAPTURE_CFG.send_mode = (mi == 2) and "direct" or "track"
    _ext_set("fb01_send_mode", CAPTURE_CFG.send_mode)
  end
  if CAPTURE_CFG.send_mode ~= "track" then
    r.ImGui_Text(ctx, "Warning: Direct SysEx send is not supported in this build; use track routing.")
  end
end

if r.ImGui_Button(ctx, "Setup Capture Track (FB01 Capture)", 280, 0) then
  _lib_hw_route_setup()
end
r.ImGui_Text(ctx, "This will create/arm a track named 'FB01 Capture' and set MIDI input best-effort. Set hardware MIDI output manually to your preferred MIDI out if needed.")

-- Phase 21: System Channel (Device ID) UI + persistence
local sysch = tonumber(CAPTURE_CFG.sys_ch or 0) or 0
changed, sysch = r.ImGui_SliderInt(ctx, "FB-01 System Channel (SysEx Device ID)", sysch, 0, 15)
if changed then
  CAPTURE_CFG.sys_ch = sysch
  _ext_set("fb01_sys_ch", sysch)
end
r.ImGui_Text(ctx, "Note: System Channel is NOT the MIDI channel. It selects which FB-01 responds to SysEx.")

r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Autodetect System Channel", 210, 0) then
  _autosys_start()
end
if AUTOSYS and AUTOSYS.status and AUTOSYS.status ~= "" then
  r.ImGui_Text(ctx, "Auto-detect: " .. tostring(AUTOSYS.status))
end

changed, CAPTURE_CFG.cleanup_mode = r.ImGui_Combo(ctx, "Capture cleanup", CAPTURE_CFG.cleanup_mode, "Keep items\0Delete items\0Archive items\0\0")
if changed then _ext_set("capture_cleanup_mode", CAPTURE_CFG.cleanup_mode) end

local tinst = CAPTURE_CFG.t_instvoice
changed, tinst = r.ImGui_DragDouble(ctx, "Timeout InstVoice (s)", tinst, 0.1, 0.5, 10.0, "%.1f")
if changed then CAPTURE_CFG.t_instvoice = tinst; _ext_set("capture_timeout_instvoice", tinst) end
local tcfg = CAPTURE_CFG.t_config
changed, tcfg = r.ImGui_DragDouble(ctx, "Timeout Config (s)", tcfg, 0.1, 1.0, 20.0, "%.1f")
if changed then CAPTURE_CFG.t_config = tcfg; _ext_set("capture_timeout_config", tcfg) end
local tbank = CAPTURE_CFG.t_bank
changed, tbank = r.ImGui_DragDouble(ctx, "Timeout Bank (s)", tbank, 0.1, 2.0, 30.0, "%.1f")
if changed then CAPTURE_CFG.t_bank = tbank; _ext_set("capture_timeout_bank", tbank) end

local rchg
local rinst = CAPTURE_CFG.retry_count_instvoice
rchg, rinst = r.ImGui_SliderInt(ctx, "Retry InstVoice", rinst, 0, 5)
if rchg then CAPTURE_CFG.retry_count_instvoice = rinst; _ext_set("capture_retry_count_instvoice", rinst) end
local rcfg = CAPTURE_CFG.retry_count_config
rchg, rcfg = r.ImGui_SliderInt(ctx, "Retry Config", rcfg, 0, 5)
if rchg then CAPTURE_CFG.retry_count_config = rcfg; _ext_set("capture_retry_count_config", rcfg) end
local rbank = CAPTURE_CFG.retry_count_bank
rchg, rbank = r.ImGui_SliderInt(ctx, "Retry Bank", rbank, 0, 5)
if rchg then CAPTURE_CFG.retry_count_bank = rbank; _ext_set("capture_retry_count_bank", rbank) end

-- Phase 6: friendly bank selector (FB-01 voice banks 0..6)
local bank_names = {
  "Bank 1 (RAM1) [id=0]",
  "Bank 2 (RAM2) [id=1]",
  "Bank 3 (ROM1) [id=2]",
  "Bank 4 (ROM2) [id=3]",
  "Bank 5 (ROM3) [id=4]",
  "Bank 6 (ROM4) [id=5]",
  "Bank 7 (ROM5) [id=6]",
  "Bank 8 (reserved?) [id=7]"
}
local bidx = (bank_request_id or 0) + 1
local bchg
bchg, bidx = r.ImGui_Combo(ctx, "Voice Bank", bidx, table.concat(bank_names, "\0") .. "\0\0")
if bchg then bank_request_id = bidx - 1 end

changed, bank_request_id = r.ImGui_SliderInt(ctx, "Request Bank ID", bank_request_id, 0, 7)

if r.ImGui_Button(ctx, "Auto Capture + Request Bank Dump") then
  bank_capture_status = ""
  capture_start("bank", function()
    local bin = Syx.request_bank(sys_ch, bank_request_id)
    send_sysex(bin)
    -- For some devices, a set request first can help; keep minimal here.
  end, {timeout=CAPTURE_CFG.t_bank})
end
if r.ImGui_Button(ctx, "Auto Capture + Send Bank Dump + Verify") then
  if last_rx_voicebank_raw and #last_rx_voicebank_raw > 0 then
    bank_capture_status = ""
    local _sys = sys_ch
    capture_start("bank", function()
      -- send bank dump as-is (most compatible)
      send_sysex(bytes_to_string(last_rx_voicebank_raw))
      -- request bank dump back for verify
      enqueue_sysex(Syx.request_bank(_sys, bank_request_id))
      verify_start("bank", last_rx_voicebank_raw, { sys_ch=_sys, timeout=CAPTURE_CFG.t_bank })
    end, {timeout=CAPTURE_CFG.t_bank, retries=CAPTURE_CFG.retry_count_bank})
  else
    r.MB("No bank dump in memory (last captured bank). First request/capture a bank dump.", "Bank Verify", 0)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Generate & Send Bank (native bulk)", 280, 0) then
    if CAPTURE_CFG.allow_native_bulk_builders ~= 1 then
      r.MB("Enable 'native bulk builders' in settings first (experimental).", "Native Bulk", 0)
    else
      if last_rx_voicebank and last_rx_voicebank.voices and #last_rx_voicebank.voices > 0 then
        local msgs, err = BulkNative.build_bank_bulk(sysch, req_voice_bank or 0, last_rx_voicebank.voices, 48, CAPTURE_CFG.native_chunk_source_bytes or 48, { strict_checksum = (CAPTURE_CFG.allow_native_bulk_strict==1), bytecount_two_bytes = (CAPTURE_CFG.native_bytecount_two==1), checksum_from_body_index = 4 })
        if not msgs then
          r.MB("Native bulk build failed: " .. tostring(err), "Native Bulk", 0)
        else
          send_sysex_msgs_throttled(msgs, CAPTURE_CFG.bulk_delay_ms or 120)
        end
      else
        r.MB("No decoded bank in memory. First capture/decode a bank dump (Phase 4+).", "Native Bulk", 0)
      end
    end
  end

end
if bank_capture_status and bank_capture_status ~= "" then
  r.ImGui_Text(ctx, bank_capture_status)
end

if BANK_VERIFY_REPORT then
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Last bank verify: ok="..tostring(BANK_VERIFY_REPORT.ok).." diffs="..tostring(BANK_VERIFY_REPORT.total_diffs).." backend="..tostring(BANK_VERIFY_REPORT.backend).." time="..tostring(BANK_VERIFY_REPORT.time_str))
  if r.ImGui_Button(ctx, "Copy last bank verify report") then
  if BANK_VERIFY_REPORT then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Bank diff report export")
    if r.ImGui_Button(ctx, "Export parameter diff report (JSON)", 260, 0) then
      local dir = r.GetProjectPath("") or (root or r.GetResourcePath())
      local fn = dir .. "/IFLS_FB01_ParamDiffReport_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
      _write_file(fn, _json_encode(BANK_VERIFY_REPORT))
      r.ShowConsoleMsg("Wrote: "..fn.."\n")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export parameter diff report (TXT)", 250, 0) then
      local dir = r.GetProjectPath("") or (root or r.GetResourcePath())
      local fn = dir .. "/IFLS_FB01_ParamDiffReport_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
      local out = {}
      out[#out+1] = "FB01 Param Diff Report " .. os.date("%Y-%m-%d %H:%M:%S")
      if BANK_VERIFY_REPORT.summary then
        out[#out+1] = ("OK=%s diffs=%s backend=%s"):format(tostring(BANK_VERIFY_REPORT.summary.ok), tostring(BANK_VERIFY_REPORT.summary.total_diffs), tostring(BANK_VERIFY_REPORT.summary.backend))
      end
      if BANK_VERIFY_REPORT.voices then
        for _,v in ipairs(BANK_VERIFY_REPORT.voices) do
          if v and v.param_diffs and #v.param_diffs>0 then
            out[#out+1] = ("Voice %d: %d diffs"):format(v.index or -1, #v.param_diffs)
            for _,d in ipairs(v.param_diffs) do out[#out+1] = "  "..d end
          end
        end
      end
      _write_file(fn, table.concat(out, "\n"))
      r.ShowConsoleMsg("Wrote: "..fn.."\n")
    end
  end

    local rep = _bank_report_to_text(BANK_VERIFY_REPORT)
    r.ImGui_SetClipboardText(ctx, rep)
  end
end

local _c
  _c, bank_import_path = r.ImGui_InputText(ctx, "Bank .syx path", bank_import_path, 4096)
  if r.ImGui_Button(ctx, "Load Bank .syx") then
    bank_import_err = nil
    bank_import = nil
    bank_sel = {}
    local bytes = read_file_bytes(bank_import_path)
    if bytes then
      local decoded, err = decode_bank_any(bytes)
      if decoded then
        bank_import = decoded.res
        bank_import_layout = decoded.layout
        last_rx_voicebank = decoded.res
        last_rx_voicebank_raw = (last and last.bytes) or syx
        for i=1,48 do bank_sel[i] = true end
      else
        bank_import_err = err
      end
    else
      bank_import_err = "could not read file"
    end
  end

  if bank_import_err then
    r.ImGui_Text(ctx, "Load error: " .. tostring(bank_import_err))
  end

  if bank_import then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, string.format("Loaded bank_no=%d voices=%d size=%d bytes",
      bank_import.bank_no or -1, #(bank_import.voices or {}), bank_import.size or 0))

    if r.ImGui_Button(ctx, "Select All") then
      for i=1,48 do bank_sel[i]=true end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Select None") then
      for i=1,48 do bank_sel[i]=false end
    end

    r.ImGui_SameLine(ctx)
    _c, bank_export_mode = r.ImGui_Combo(ctx, "Export Mode", bank_export_mode, "Payload .bin\0Bank JSON\0Single-Voice .syx (Inst)\0\0")
    r.ImGui_SameLine(ctx)
    _c, bank_inst_target = r.ImGui_SliderInt(ctx, "Inst", bank_inst_target, 0, 7)

    if r.ImGui_Button(ctx, "Export Selected") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      if bank_export_mode == 0 then
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            local safe = (v.name or "VOICE"):gsub("[^%w%-%_ ]","_")
            local fname = voice_export_dir .. string.format("/bank%d_voice%02d_%s.bin", bank_import.bank_no or 0, v.index or (i-1), safe)
            write_bytes_to_file(fname, v.payload_bytes or {})
          end
        end
      elseif bank_export_mode == 1 then
        local export = { bank_no=bank_import.bank_no, voices={} }
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            export.voices[#export.voices+1] = { index=v.index, name=v.name, payload_bytes=v.payload_bytes }
          end
        end
        local js = json_encode_min(export)
        local bytes={}
        for i=1,#js do bytes[i]=string.byte(js,i) end
        local fname = voice_export_dir .. string.format("/bank%d_%s.json", bank_import.bank_no or 0, now_stamp())
        write_bytes_to_file(fname, bytes)
      else
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            local pb = v.payload_bytes or {}
            local off = math.max(1, (#pb - 64) + 1)
            local voice64={}
            for k=1,64 do voice64[k] = pb[off + (k-1)] or 0 end
            local msg = VoiceDump.build_inst_voice_sysex(sys_ch or sysch or 0, bank_inst_target, voice64)
            local safe = (v.name or "VOICE"):gsub("[^%w%-%_ ]","_")
            local fname = voice_export_dir .. string.format("/bank%d_voice%02d_inst%d_%s.syx", bank_import.bank_no or 0, v.index or (i-1), bank_inst_target, safe)
            write_bytes_to_file(fname, msg)
          end
        end
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send Selected to Inst (live)") then
      for i=1,48 do
        if bank_sel[i] then
          local v = bank_import.voices[i]
          local pb = v.payload_bytes or {}
          local off = math.max(1, (#pb - 64) + 1)
          local voice64={}
          for k=1,64 do voice64[k] = pb[off + (k-1)] or 0 end
          local msg = VoiceDump.build_inst_voice_sysex(sys_ch or sysch or 0, bank_inst_target, voice64)
          if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
        end
      end
    end
    r.ImGui_SameLine(ctx)
    local chg
    chg, bank_send_verify = r.ImGui_Checkbox(ctx, "Verify each voice", bank_send_verify)
    if r.ImGui_Button(ctx, "Send Selected to Inst (auto capture)") then
      if not bank_import or not bank_import.voices then
        r.MB("No bank loaded.", "Bank Send", 0)
      else
        local list = {}
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            local voice64 = v.voice64
            if not voice64 then
              -- derive from payload_bytes
              local pb = v.payload_bytes or {}
              local off = math.max(1, (#pb - 64) + 1)
              voice64 = {}
              for k=1,64 do voice64[k] = pb[off + (k-1)] or 0 end
            end
            list[#list+1] = voice64
          end
        end
        if #list == 0 then
          r.MB("No voices selected.", "Bank Send", 0)
        else
          bank_send_queue = { list=list, idx=1, inst=bank_inst_target, sys=(sys_ch or 0), retries=CAPTURE_CFG.retry_count_instvoice }
        end
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Auto Capture + Send+Verify") then
      -- Record a short MIDI capture so large SysEx dumps can be read back reliably
      local _sys = (sys_ch or sysch or 0)
      local _inst = sv_send_inst
      local function _send()
        local msg = VoiceDump.build_inst_voice_sysex(_sys, _inst, sv_import.voice_bytes)
        if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
        verify_start("instvoice", sv_import.voice_bytes, { sys_ch=_sys, inst_no=_inst, timeout=2.5 })
        enqueue_sysex(Syx.dump_inst_voice(_sys, _inst))
      end
      capture_start("instvoice", _send, { timeout = 4.0 })
    end

    if r.ImGui_BeginTable(ctx, "banktbl", 3, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
      r.ImGui_TableSetupColumn(ctx, "Sel")
      r.ImGui_TableSetupColumn(ctx, "Idx")
      r.ImGui_TableSetupColumn(ctx, "Name")
      r.ImGui_TableHeadersRow(ctx)
      for i=1,48 do
        local v = bank_import.voices[i]
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0)
        local changed
        changed, bank_sel[i] = r.ImGui_Checkbox(ctx, "##banksel"..tostring(i), bank_sel[i] == true)
        r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, string.format("%02d", v.index or (i-1)))
        r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_Text(ctx, v.name or "???????")
      end
      r.ImGui_EndTable(ctx)
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

if r.ImGui_CollapsingHeader(ctx, "Patch Export / Import", 0) then
  r.ImGui_Text(ctx, "Export voices/banks from FB-01 to the computer (requests + save .syx).")
  r.ImGui_Separator(ctx)

  local _c
  _c, req_voice_bank = r.ImGui_SliderInt(ctx, "Request Voice Bank (0..6)", req_voice_bank, 0, 6)
  if r.ImGui_Button(ctx, "Request: Voice Bank") then
    enqueue_sysex(Syx.dump_voice_bank(sys_ch or sysch or 0, req_voice_bank))
  end
  r.ImGui_SameLine(ctx)
  _c, req_inst_voice = r.ImGui_SliderInt(ctx, "Request Inst Voice (0..7)", req_inst_voice, 0, 7)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Request: Inst Voice") then
    enqueue_sysex(Syx.dump_inst_voice(sys_ch or sysch or 0, req_inst_voice))
  end

  r.ImGui_Separator(ctx)

  if last_rx_voicebank_raw then
    r.ImGui_Text(ctx, "Last RX: VoiceBank dump available.")
    if r.ImGui_Button(ctx, "Export last VoiceBank (.syx)") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      local fname = voice_export_dir .. "/fb01_voicebank_" .. tostring(req_voice_bank) .. "_" .. now_stamp() .. ".syx"
      write_bytes_to_file(fname, last_rx_voicebank_raw)
    end
  else
    r.ImGui_Text(ctx, "No voice bank dump received yet.")
  end

  if last_rx_voice_raw then
    r.ImGui_Text(ctx, "Last RX: Single Voice dump available.")
    if r.ImGui_Button(ctx, "Export last Voice (.syx)") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      local fname = voice_export_dir .. "/fb01_voice_" .. now_stamp() .. ".syx"
      write_bytes_to_file(fname, last_rx_voice_raw)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export voice payload (.bin)") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      local fname = voice_export_dir .. "/fb01_voice_payload_" .. now_stamp() .. ".bin"
      write_bytes_to_file(fname, last_rx_voice.payload_bytes or {})
    end
  else
    r.ImGui_Text(ctx, "No single voice dump received yet.")
  end

  r.ImGui_Text(ctx, "Tip: enable Auto Decode, then request bank/inst voice and export once received.")
  r.ImGui_EndChild(ctx)
end

      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

    if r.ImGui_BeginMenuBar(ctx) then
      if r.ImGui_BeginMenu(ctx, "Help", true) then
        r.ImGui_Text(ctx, "Requires: ReaImGui + SWS SysEx")
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Tip: Use your existing FB-01 dump record/replay tools for librarian/recall.")
        r.ImGui_EndMenu(ctx)
      end
      r.ImGui_EndMenuBar(ctx)
    end

    r.ImGui_Separator(ctx)
    local chg, nsys = r.ImGui_SliderInt(ctx, "FB-01 SysEx Channel (SysCh)", sysch, 0, 15)
    if chg then sysch = clamp(nsys,0,15) end
    local ch2, ninst = r.ImGui_SliderInt(ctx, "Instrument (0..7)", inst, 0, 7)
    if ch2 then inst = clamp(ninst,0,7) end

    r.ImGui_Separator(ctx)
    requests_panel()
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Randomize: Voice", 160, 0) then randomize("voice") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Randomize: All Ops", 160, 0) then randomize("ops") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Randomize: All", 160, 0) then randomize("all") end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Constrained random")
    local chg_i, ni = r.ImGui_SliderDouble(ctx, "Random intensity", rand_intensity, 0.0, 1.0)
    if chg_i then rand_intensity = ni end
    if r.ImGui_Button(ctx, "Rand: OP Env", 120, 0) then randomize_groups_intensity({ops_env=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: OP Pitch", 120, 0) then randomize_groups_intensity({ops_pitch=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: OP Level", 120, 0) then randomize_groups_intensity({ops_level=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: Voice LFO", 140, 0) then randomize_groups_intensity({voice_lfo=true}, rand_intensity) end

    if r.ImGui_Button(ctx, "Save patch state (JSON)", 200, 0) then save_state_json() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Load patch state (JSON)", 200, 0) then load_state_json() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export .syx (param stream)", 200, 0) then export_param_stream_syx() end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "User templates")
    local names = ""
    for i=1,#(user_db.templates or {}) do names = names .. (user_db.templates[i].name or ("Template "..i)) .. "\0" end
    if names == "" then names = " (none)\0" end
    local chg_u, new_u = r.ImGui_Combo(ctx, "Saved", user_tpl_idx, names)
    if chg_u then user_tpl_idx = new_u end
    if r.ImGui_Button(ctx, "Apply Saved Template", 180, 0) then
      local t = (user_db.templates or {})[user_tpl_idx+1]
      if t then apply_template(t) end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save Current as Template", 200, 0) then
      local okN, nm = r.GetUserInputs("Save Template", 1, "Name", "My Template")
      if okN and nm ~= "" then
        user_db = load_user_templates()
        user_db.templates = user_db.templates or {}
        user_db.templates[#user_db.templates+1] = capture_current_as_template(nm)
        save_user_templates(user_db)
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Reload Templates", 140, 0) then
      user_db = load_user_templates()
      user_tpl_idx = 0
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Templates (starting points)")
    local combo_str = ""
    for i=1,#template_names do combo_str = combo_str .. template_names[i] .. "\0" end
    local chg_t, new_idx = r.ImGui_Combo(ctx, "Template", template_idx, combo_str)
    if chg_t then template_idx = new_idx end
    if r.ImGui_Button(ctx, "Apply Template", 160, 0) then
      local name = template_names[template_idx+1]
      if name and TEMPLATES[name] then apply_template(TEMPLATES[name]) end
    end

    
    r.ImGui_Separator(ctx)

    schema_tab_was_active = schema_tab_active
schema_tab_active = false
if r.ImGui_BeginTabBar(ctx, "tabs") then
      if r.ImGui_BeginTabItem(ctx, "Voice", true) then
        voice_panel()
        r.ImGui_EndTabItem(ctx)
      end
      if r.ImGui_BeginTabItem(ctx, "Operators", true) then
        operator_panel()
        r.ImGui_EndTabItem(ctx)
      end
      if r.ImGui_BeginTabItem(ctx, "Instrument", true) then
        instrument_panel()
        r.ImGui_EndTabItem(ctx)

if r.ImGui_BeginTabItem(ctx, "Config/MIDI") then
  if P.config_params then
    r.ImGui_Text(ctx, "System/Config (SysEx ch " .. tostring(sys_ch) .. ")")
    r.ImGui_Separator(ctx)

-- B2.2: Live dump requests / receiver
r.ImGui_Text(ctx, "B2.2 Live Dumps")

local chg_ad, ad = r.ImGui_Checkbox(ctx, "Auto-decode on receive (B2.3)", auto_decode)
if chg_ad then auto_decode = ad end
local changed_bank, bank_no = r.ImGui_SliderInt(ctx, "Voice Bank (0-6)", dump_bank_no or 0, 0, 6)
if changed_bank then dump_bank_no = bank_no end
if r.ImGui_Button(ctx, "Request Voice Bank") then
  send_sysex(Syx.request_bank(sys_ch, dump_bank_no or 0))
end
if r.ImGui_Button(ctx, "Request Current Config") then
  send_sysex(Syx.request_current_config(sys_ch))
end
local changed_inst, inst_no = r.ImGui_SliderInt(ctx, "Instrument (1-8)", dump_inst_no or 1, 1, 8)
if changed_inst then dump_inst_no = inst_no end
if r.ImGui_Button(ctx, "Request Instrument Voice") then
  send_sysex(Syx.request_instrument_voice(sys_ch, dump_inst_no or 1))
end

local hs = Rx.state.last_handshake
if hs then r.ImGui_Text(ctx, "Handshake: " .. hs) end

-- Phase 2.5: advance Send+Verify state on ACK
if verify_stage == "await_ack" and hs == "ACK" and verify_target then
  verify_stage = "await_dump"
  -- request config dump for the current slot
  enqueue_sysex(Syx.dump_config_slot(sysch or 0, cfg_slot or 0))
  verify_start("config", verify_target, { timeout = 3.5 })
end

local last = Rx.get_last_dump()
-- Phase 2.5: tick verify engine (works with LIVE or TAKE backend)
verify_tick(last)
if last and last.preview then
  r.ImGui_TextWrapped(ctx, "Last dump: " .. last.preview)
  if r.ImGui_Button(ctx, "Save last dump to project folder") then
    local proj = r.GetProjectPath("")
    local fname = string.format("FB01_dump_%s.syx", os.date("%Y%m%d_%H%M%S"))
    local path = proj .. "/" .. fname
    local ok, err = Rx.save_last_dump_to_file(path)
    if ok then
      dump_status = "Saved: " .. path
    else
      dump_status = "Save failed: " .. tostring(err)
    end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear") then
    Rx.clear_last_dump()
    dump_status = nil
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if dump_status then r.ImGui_TextWrapped(ctx, dump_status) end

-- B2.3: Decode last dump (nibble bulk) + show patch names (heuristic)
if r.ImGui_Button(ctx, "Decode last dump") then
  local last = Rx.get_last_dump()
  if last and last.bytes then
    local res = DumpDec.decode_sysex(last.bytes)
    if res and res.ok then
      last_decoded = res.decoded
      last_names = res.names
      last_decode_info = res.info
      dump_status = (res.checksum_ok and "Decode OK (checksum OK)" or "Decode OK (checksum FAIL)")
    else
      last_decoded = nil
      last_names = nil
      last_decode_info = res and res.info or nil
      dump_status = "Decode failed: " .. tostring(res and res.error or "unknown")
    end
  else
    dump_status = "No dump in buffer."
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if last_decode_info then
  r.ImGui_TextWrapped(ctx, "Decoded len: " .. tostring(last_decode_info.decoded_len or "?") ..
                          " | Names found: " .. tostring(last_decode_info.names_found or 0) ..
                          " | Checksum: " .. tostring(last_decode_info.checksum_ok))
end

if last_decoded and r.ImGui_Button(ctx, "Export decoded payload (.bin) to project folder") then
  local proj = r.GetProjectPath("")
  local fname = string.format("FB01_decoded_%s.bin", os.date("%Y%m%d_%H%M%S"))
  local path = proj .. "/" .. fname
  local f = io.open(path, "wb")
  if f then
    for i=1,#last_decoded do f:write(string.char(last_decoded[i] & 0xFF)) end
    f:close()
    export_status = "Exported: " .. path
  else
    export_status = "Export failed: cannot open file"
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if export_status then r.ImGui_TextWrapped(ctx, export_status) end
if last_names and #last_names > 0 then
  

-- B2.4: Import .syx voice bank (48) and display names
if r.ImGui_Button(ctx, "Import Voice Bank (.syx)") then
  import_bank_dialog()
end
if bank_names then
  r.ImGui_TextWrapped(ctx, "Bank: " .. tostring(bank_name) .. " | Checksum: " .. tostring(bank_checksum_ok))
  
local chg_sel, nv = r.ImGui_SliderInt(ctx, "Selected Voice (0-47)", selected_bank_voice, 0, 47)
if chg_sel then selected_bank_voice = nv end
if r.ImGui_Button(ctx, "Apply selected voice to UI (no send)") then
  apply_bank_voice_to_ui(selected_bank_voice)
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send selected voice (queued)") then
  local msgs = build_voice_param_stream(selected_bank_voice)
  if msgs then
    enqueue_sysex_many(msgs)
    bank_apply_status = "Queued 64 param messages for voice " .. tostring(selected_bank_voice)
  else
    bank_apply_status = "No voice bytes cached."
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if bank_apply_status then r.ImGui_TextWrapped(ctx, bank_apply_status) end

if r.ImGui_Button(ctx, "Send CURRENT UI voice (diff queued)") then
  local bytes = encode_current_ui_voice_block()
  local msgs = build_param_stream_from_bytes(bytes, true)
  enqueue_sysex_many(msgs)
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued " .. tostring(#msgs) .. " changed params (diff)."
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send CURRENT UI voice (full queued)") then
  local bytes = encode_current_ui_voice_block()
  local msgs = build_param_stream_from_bytes(bytes, false)
  enqueue_sysex_many(msgs)
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued 64 params (full)."

if r.ImGui_Button(ctx, "Send CURRENT UI voice as EventList (diff)") then
  local bytes = encode_current_ui_voice_block()
  local events = build_eventlist_from_voice_bytes(bytes, true)
  local msg = Syx.event_list(events)
  enqueue_sysex_many({{msg=msg, delay_ms = slow_chunk and 50 or nil}})
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued EventList (" .. tostring(#events) .. " events, diff)."
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send CURRENT UI voice as EventList (full)") then
  local bytes = encode_current_ui_voice_block()
  local events = build_eventlist_from_voice_bytes(bytes, false)
  local msg = Syx.event_list(events)
  enqueue_sysex_many({{msg=msg, delay_ms = slow_chunk and 50 or nil}})
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued EventList (" .. tostring(#events) .. " events, full)."
end

end

if r.ImGui_Button(ctx, "

if r.ImGui_CollapsingHeader(ctx, "Parameter List", r.ImGui_TreeNodeFlags_DefaultOpen()) then
  r.ImGui_Text(ctx, "Searchable list of parameters (deterministic keys).")
  local chg
  chg, paramlist_filter = r.ImGui_InputText(ctx, "Search", paramlist_filter)
  r.ImGui_SameLine(ctx)
  chg, paramlist_show_raw = r.ImGui_Checkbox(ctx, "Show Raw VoiceBlock (0..63)", paramlist_show_raw)
  chg, paramlist_show_voice = r.ImGui_Checkbox(ctx, "Show Voice", paramlist_show_voice)
  r.ImGui_SameLine(ctx)
  chg, paramlist_show_ops = r.ImGui_Checkbox(ctx, "Show OPs", paramlist_show_ops)
  r.ImGui_SameLine(ctx)
  chg, paramlist_show_conf = r.ImGui_Checkbox(ctx, "Show Config", paramlist_show_conf)

  local items = build_param_catalog()
  if r.ImGui_BeginTable(ctx, "paramlist_table", 6, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingStretchProp()) then
    r.ImGui_TableSetupColumn(ctx, "Scope")
    r.ImGui_TableSetupColumn(ctx, "schema_key")
    r.ImGui_TableSetupColumn(ctx, "Label")
    r.ImGui_TableSetupColumn(ctx, "Value")
    r.ImGui_TableSetupColumn(ctx, "Range")
    r.ImGui_TableSetupColumn(ctx, "Encoding/Note")
    r.ImGui_TableHeadersRow(ctx)
    for i=1,#items do
      local it = items[i]
      local ok_scope = (it.scope=="voice" and paramlist_show_voice) or (it.scope=="op" and paramlist_show_ops) or (it.scope=="conf" and paramlist_show_conf)
      local ok_search = (paramlist_filter == "" or _contains(it.key, paramlist_filter) or _contains(it.name, paramlist_filter))
      if ok_scope and ok_search then
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, it.scope)
        r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, tostring(it.key))
        r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_Text(ctx, tostring(it.name))
        r.ImGui_TableSetColumnIndex(ctx, 3); r.ImGui_Text(ctx, tostring(it.get()))
        r.ImGui_TableSetColumnIndex(ctx, 4); r.ImGui_Text(ctx, tostring(it.range or ""))
        r.ImGui_TableSetColumnIndex(ctx, 5); r.ImGui_Text(ctx, tostring(it.enc or "") .. (it.extra and (" "..it.extra) or ""))
      end
    end
    r.ImGui_EndTable(ctx)
  end

  if paramlist_show_raw then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Raw VoiceBlock bytes (64 params -> pp=0x40+index).")
    local bytes = encode_current_ui_voice_block()
    if r.ImGui_BeginTable(ctx, "rawblock_table", 5, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
      r.ImGui_TableSetupColumn(ctx, "Index")
      r.ImGui_TableSetupColumn(ctx, "pp (hex)")
      r.ImGui_TableSetupColumn(ctx, "Value (dec)")
      r.ImGui_TableSetupColumn(ctx, "Value (hex)")
      r.ImGui_TableSetupColumn(ctx, "Diff?")
      r.ImGui_TableHeadersRow(ctx)
      for p=0,63 do
        local v = (bytes[p+1] or 0) & 0xFF
        local diff = ""
        if last_sent_voice_bytes then
          local prev = (last_sent_voice_bytes[p+1] or -1) & 0xFF
          if prev ~= v then diff = "*" end
        end
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, tostring(p))
        r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, string.format("0x%02X", 0x40 + p))
        r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_Text(ctx, tostring(v))
        r.ImGui_TableSetColumnIndex(ctx, 3); r.ImGui_Text(ctx, string.format("%02X", v))
        r.ImGui_TableSetColumnIndex(ctx, 4); r.ImGui_Text(ctx, diff)
      end
      r.ImGui_EndTable(ctx)
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

if r.ImGui_CollapsingHeader(ctx, "TrueBulk VoiceWrite", r.ImGui_TreeNodeFlags_DefaultOpen()) then
  r.ImGui_Text(ctx, "Template-based single-message voice write (capture real dump prefix+layout).")
  if r.ImGui_Button(ctx, "Request single-voice dump (capture template)") then
    local req = Syx.request_instrument_voice(sys_ch, inst_no)
    enqueue_sysex_many({{msg=req, delay_ms = slow_chunk and 100 or nil}})
    voice_dump_status = "Requested dump. After it arrives, click 'Use last received voice dump'."
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Use last received voice dump") then
    if last_rx_sysex and type(last_rx_sysex)=="table" and #last_rx_sysex>0 then
      local res, err = VoiceDump.decode_voice_from_sysex(last_rx_sysex)
      if not res then
        voice_dump_status = "Decode failed: " .. tostring(err)
      else
        voice_dump_template = res.template
                      current_voice_block = res.voice_bytes
                      voice_name = (res.meta and res.meta.name) or voice_name
                      voice_user_code = (res.meta and res.meta.user_code) or voice_user_code
                      voice_breath = (res.meta and res.meta.breath) or voice_breath
        voice_dump_payload = res.payload_bytes
        voice_dump_offset = res.voice_offset
        voice_dump_status = "Captured template. Payload bytes=" .. tostring(#res.payload_bytes)
      end
    else
      voice_dump_status = "No received SysEx captured yet."
    end
  end
  if r.ImGui_Button(ctx, "Apply CURRENT UI voice (TrueBulk)") then
    if not voice_dump_template or not voice_dump_payload or not voice_dump_offset then
      voice_dump_status = "No template yet. Capture a voice dump first."
    else
      local vbytes = encode_current_ui_voice_block()
      local new_payload = VoiceDump.replace_voice_bytes(voice_dump_payload, voice_dump_offset, vbytes)
      local msg, err = VoiceDump.build_voice_sysex_from_template(voice_dump_template, new_payload)
      if not msg then
        voice_dump_status = "Build failed: " .. tostring(err)
      else
        enqueue_sysex_many({{msg=msg, delay_ms = slow_chunk and 100 or nil}})
        last_sent_voice_bytes = vbytes
        voice_dump_status = "Queued TrueBulk voice write (single message)."
      end
    end
  end
  r.ImGui_Text(ctx, voice_dump_status or "")
end

Export Bank as .syx (template)") then
  if not bank_template or not bank_voice_bytes then
    bank_apply_status = "No bank template cached. Re-import a .syx first."
  else
    local payload = Bank.payload_from_voice_blocks(bank_name or "FB01BANK", bank_voice_bytes)
    local msg, err = Bank.build_sysex_from_template(bank_template, payload)
    if not msg then
      bank_apply_status = "Export build failed: " .. tostring(err)
    else
      local proj = r.GetProjectPath("")
      local fname = string.format("FB01_bank_export_%s.syx", os.date("%Y%m%d_%H%M%S"))
      local path = proj .. "/" .. fname
      local f = io.open(path, "wb")
      if f then
        for i=1,#msg do f:write(string.char(msg[i] & 0xFF)) end
        f:close()
        bank_apply_status = "Exported: " .. path
      else
        bank_apply_status = "Export failed: cannot open file"
      end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.ImGui_Separator(ctx)
  for i=1,math.min(#bank_names,48) do
    r.ImGui_Text(ctx, string.format("%02d: %s", i-1, bank_names[i]))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Patch/Tone names (heuristic):")
  for i=1,math.min(#last_names,48) do
    r.ImGui_Text(ctx, string.format("%02d: %s", i-1, last_names[i]))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.ImGui_Separator(ctx)

    for _,it in ipairs(P.config_params) do
      local v = cfg_vals[it.param] or it.default or 0
      local lo = it.ui_min or it.min or 0
              local hi = it.ui_max or it.max or 127
      if it.ui == "checkbox" then
        local b = (v ~= 0)
        local changed, nb = r.ImGui_Checkbox(ctx, it.name, b)
        if changed then
          cfg_vals[it.param] = nb and 1 or 0
          apply_cfg_param(it.param, cfg_vals[it.param])
        end
      else
        local changed, nv = r.ImGui_SliderInt(ctx, it.name, v, lo, hi)
        if changed then
          cfg_vals[it.param] = nv
          apply_cfg_param(it.param, nv)
        end
      end
    end
  else
    r.ImGui_Text(ctx, "No config params in schema.")
  end
  r.ImGui_EndTabItem(ctx)
end

      end
      if r.ImGui_BeginTabItem(ctx, "Library", true) then
        r.ImGui_Text(ctx, "Library + Project Recall")
        if r.ImGui_Button(ctx, "Open FB-01 Library Browser (v2)", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Library_Browser_v2.lua")
        end
        if r.ImGui_Button(ctx, "Project Recall: Save voice (.syx)", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Project_Save_Recall.lua")
        end
        if r.ImGui_Button(ctx, "Project Recall: Apply stored voice", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Project_Apply_Recall.lua")
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Fix/Normalize SysEx (offline)")
        if r.ImGui_Button(ctx, "Normalize DeviceID/SysExCh", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Normalize_DeviceID.lua")
        end
        if r.ImGui_Button(ctx, "Retarget Bank1<->Bank2", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Retarget_Bank1_Bank2.lua")
        end
        r.ImGui_EndTabItem(ctx)
      end
      if r.ImGui_BeginTabItem(ctx, "Schema (beta)") then
  local sch, err = ParamSchema.load()
  if not sch then
    r.ImGui_Text(ctx, err)
  else
    r.ImGui_Text(ctx, "Schema loaded: " .. tostring(sch.device or "FB-01"))
    r.ImGui_Separator(ctx)
    for _,grp in ipairs(sch.groups or {}) do
      if r.ImGui_CollapsingHeader(ctx, grp.label or grp.id) then
        r.ImGui_Text(ctx, "This tab is the foundation for full coverage. Extend schema to add params.")
      end
    end
  end
  r.ImGui_EndTabItem(ctx)
end
if r.ImGui_BeginTabItem(ctx, "Schema: Voice + OP EG") then
  schema_tab_active = true

  r.ImGui_SeparatorText(ctx, "Schema-driven send")
  local ch
  ch, autosend_schema_full_on_exit = r.ImGui_Checkbox(ctx, "Send full snapshot on tab exit (snapshot mode)", autosend_schema_full_on_exit)

  r.ImGui_SeparatorText(ctx, "AutoSend extras")
  ch, send_on_release_always_once = r.ImGui_Checkbox(ctx, "Per-change: send on release always once", send_on_release_always_once)
  ch, snapshot_preview_while_dragging = r.ImGui_Checkbox(ctx, "Snapshot: preview while dragging (rate-limited)", snapshot_preview_while_dragging)

  r.ImGui_SeparatorText(ctx, "Voice")
  for _,it in ipairs(P.voice_params) do
    schema_slider_voice(it)
  end

  r.ImGui_SeparatorText(ctx, "Operators: EG (4-column)")
  local function is_eg(it)
    local g = (it.group or ""):lower()
    if g == "eg" then return true end
    local n = (it.name or ""):lower()
    return n:find("attack") or n:find("decay") or n:find("sustain") or n:find("release")
  end

  -- build EG param list once
  local eg = {}
  for _,it in ipairs(P.operator_params) do
    if is_eg(it) then eg[#eg+1] = it end
  end

  if r.ImGui_BeginTable(ctx, "eg_table", 5, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
    r.ImGui_TableSetupColumn(ctx, "Param", r.ImGui_TableColumnFlags_WidthFixed(), 150)
    r.ImGui_TableSetupColumn(ctx, "OP1")
    r.ImGui_TableSetupColumn(ctx, "OP2")
    r.ImGui_TableSetupColumn(ctx, "OP3")
    r.ImGui_TableSetupColumn(ctx, "OP4")
    r.ImGui_TableHeadersRow(ctx)

    for _,it in ipairs(eg) do
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableSetColumnIndex(ctx, 0)
      r.ImGui_Text(ctx, it.name)

      for op_id=0,3 do
        r.ImGui_TableSetColumnIndex(ctx, op_id+1)
        local lo = it.ui_min or it.min or 0
              local hi = it.ui_max or it.max or 127
        local v  = clamp(op_vals[op_id+1][it.param] or 0, lo, hi)
        local label = string.format("##eg_op%d_%d", op_id+1, it.param)
        local changed, newv = r.ImGui_SliderInt(ctx, label, v, lo, hi)
        local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)

        if changed then
          newv = clamp(newv, lo, hi)
          op_vals[op_id+1][it.param] = newv
          local msg = Syx.operator_param(sysch, inst, op_id, it.param, newv)
          if live_send_per_change then send_sysex(msg) end
          hook_autosave_autosend(msg, deact)
        elseif deact then
          local msg = Syx.operator_param(sysch, inst, op_id, it.param, v)
          hook_autosave_autosend(msg, true)
        end
      end
    end

    r.ImGui_EndTable(ctx)
  end

  r.ImGui_SeparatorText(ctx, "Operators: Level / Ratio / Scaling")
  local function in_group(it, want)
    return ((it.group or ""):upper() == want)
  end

  local groups = {{"LEVEL","LEVEL"}, {"FREQ","FREQ"}, {"SCALE","SCALE"}, {"MOD","MOD"}}
  for _,g in ipairs(groups) do
    local gid, glabel = g[1], g[2]
    if r.ImGui_CollapsingHeader(ctx, glabel) then
      for op_id=0,3 do
        r.ImGui_SeparatorText(ctx, string.format("OP%d", op_id+1))
        for _,it in ipairs(P.operator_params) do
          if in_group(it, gid) then
            schema_slider_op(op_id, it)
          end
        end
      end
    end
  end

  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "Voice FullSpec (64)") then
  r.ImGui_Text(ctx, "Auto-generated from Service Manual voice parameter list. Sends Voice Parameter Change (pp=0x40+param).")
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginChild(ctx, "fullspec_voice_scroller", -1, -1, 0) then
    for _,it in ipairs(P_FULL.voice_params_fullspec or {}) do
      fullspec_voice_slider(it)
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "Inst Config FullSpec") then
  r.ImGui_Text(ctx, "Instrument configuration parameters (pp=0x00..0x17).")
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginChild(ctx, "conf_fullspec_scroller", -1, -1, 0) then
    for _,it in ipairs(P_CONF.conf_params_fullspec or {}) do
      local pp = tonumber(it.pp) or 0
      local label = it.label or ("Conf "..tostring(pp))
      -- conf_vals is optional; fall back to local cache
      conf_vals = conf_vals or {}
      local cur = conf_vals[pp] or 0
      local changed, nv = r.ImGui_SliderInt(ctx, label .. "##conf_"..tostring(pp), cur, 0, 127)
      if changed then
        conf_vals[pp] = nv
        apply_conf_param(pp, nv)
      end
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "System Params (Raw)") then
  r.ImGui_Text(ctx, "Raw System Parameter Change: F0 43 75 0s 10 pp dd F7")
  r.ImGui_Separator(ctx)
  local ch
  ch, sys_pp = r.ImGui_SliderInt(ctx, "System Param (pp)", sys_pp, 0, 127)
  ch, sys_dd = r.ImGui_SliderInt(ctx, "Value (dd)", sys_dd, 0, 127)
  if r.ImGui_Button(ctx, "Send System Param") then
    local msg = Syx.sys_param(sys_ch, sys_pp, sys_dd)
    if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
  end
  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "Event List") then
  r.ImGui_Text(ctx, "FB-01 SysEx Event List builder (F0 43 75 70 ... F7).")
  r.ImGui_Text(ctx, "Builds a single SysEx message to avoid MIDI flood. 'sys_ch' is encoded in each event nibble.")
  r.ImGui_Separator(ctx)

  if r.ImGui_Button(ctx, "Add: NoteOff+Frac") then
    event_items[#event_items+1] = {t="note_off_frac", key=ev_key, frac=ev_frac}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: NoteOn/Off+Frac") then
    event_items[#event_items+1] = {t="note_onoff_frac", key=ev_key, frac=ev_frac, vel=ev_vel}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: Note+Dur") then
    event_items[#event_items+1] = {t="note_dur", key=ev_key, frac=ev_frac, vel=ev_vel, yy=ev_yy, xx=ev_xx}
  end

  if r.ImGui_Button(ctx, "Add: CC") then
    event_items[#event_items+1] = {t="cc", cc=ev_cc, val=ev_ccval}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: Program") then
    event_items[#event_items+1] = {t="program", prog=ev_prog}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: AfterTouch") then
    event_items[#event_items+1] = {t="aftertouch", val=ev_at}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: PitchBend") then
    event_items[#event_items+1] = {t="pitchbend", py=ev_py, px=ev_px}
  end

  if r.ImGui_Button(ctx, "Add: InstParam (1B)") then
    event_items[#event_items+1] = {t="inst_param_1", pa=ev_pa, dd=ev_dd}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: InstParam (2B)") then
    event_items[#event_items+1] = {t="inst_param_2", pa=ev_pa, y=ev_y, x=ev_x}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear List") then
    event_items = {}
  end

  r.ImGui_Separator(ctx)

  r.ImGui_Text(ctx, "Defaults / inputs:")
  local _c
  _c, ev_key = r.ImGui_SliderInt(ctx, "Key", ev_key, 0, 127)
  _c, ev_frac = r.ImGui_SliderInt(ctx, "Frac (cents 0..100)", ev_frac, 0, 100)
  _c, ev_vel  = r.ImGui_SliderInt(ctx, "Vel", ev_vel, 0, 127)
  _c, ev_yy   = r.ImGui_SliderInt(ctx, "Dur YY", ev_yy, 0, 127)
  _c, ev_xx   = r.ImGui_SliderInt(ctx, "Dur XX", ev_xx, 0, 127)
  _c, ev_cc   = r.ImGui_SliderInt(ctx, "CC#", ev_cc, 0, 127)
  _c, ev_ccval= r.ImGui_SliderInt(ctx, "CC Val", ev_ccval, 0, 127)
  _c, ev_prog = r.ImGui_SliderInt(ctx, "Program", ev_prog, 0, 127)
  _c, ev_at   = r.ImGui_SliderInt(ctx, "AfterTouch", ev_at, 0, 127)
  _c, ev_py   = r.ImGui_SliderInt(ctx, "PB Y", ev_py, 0, 127)
  _c, ev_px   = r.ImGui_SliderInt(ctx, "PB X", ev_px, 0, 127)
  _c, ev_pa   = r.ImGui_SliderInt(ctx, "Inst Param#", ev_pa, 0, 127)
  _c, ev_dd   = r.ImGui_SliderInt(ctx, "Inst Param DD", ev_dd, 0, 127)
  _c, ev_y    = r.ImGui_SliderInt(ctx, "Inst Param Y (0..15)", ev_y, 0, 15)
  _c, ev_x    = r.ImGui_SliderInt(ctx, "Inst Param X (0..15)", ev_x, 0, 15)

  r.ImGui_Separator(ctx)

  if r.ImGui_BeginTable(ctx, "ev_tbl", 4, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
    r.ImGui_TableSetupColumn(ctx, "#")
    r.ImGui_TableSetupColumn(ctx, "Type")
    r.ImGui_TableSetupColumn(ctx, "Data")
    r.ImGui_TableSetupColumn(ctx, "Del")
    r.ImGui_TableHeadersRow(ctx)
    for i=1,#event_items do
      local ev = event_items[i]
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, tostring(i))
      r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, ev.t or "")
      r.ImGui_TableSetColumnIndex(ctx, 2)
      r.ImGui_Text(ctx, table.concat((function()
        local parts={}
        for k,v in pairs(ev) do if k~="t" then parts[#parts+1]=k.."="..tostring(v) end end
        return parts
      end)(), " "))
      r.ImGui_TableSetColumnIndex(ctx, 3)
      if r.ImGui_Button(ctx, "X##evdel"..tostring(i)) then
        table.remove(event_items, i)
        break
      end
    end
    r.ImGui_EndTable(ctx)
  end

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Send Event List SysEx") then
    local msg = build_event_list_sysex(sys_ch)
    if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Show Hex") then
    local msg = build_event_list_sysex(sys_ch)
    last_hex_preview = bin_to_hex(msg)
  end
  if last_hex_preview then
    r.ImGui_TextWrapped(ctx, last_hex_preview)
  end

  r.ImGui_EndTabItem(ctx)
end

r.ImGui_EndTabBar(ctx)
    
      -- schema tab exit snapshot send
      if autosend and autosend_mode==0 and autosend_schema_full_on_exit and schema_tab_was_active and (not schema_tab_active) then
        autosend_deb:request()
      end
end

    autosave_deb:update(); autosend_deb:update();
    
r.ImGui_Separator(ctx)
if r.ImGui_CollapsingHeader(ctx, "Debug: Snapshot/Hash", r.ImGui_TreeNodeFlags_DefaultOpen()) then
  local msgs = build_param_stream_msgs()
  local blob = table.concat(msgs or {}, "")
  local cur_hash = SlotCore.hash_bytes(blob)
  r.ImGui_Text(ctx, "Snapshot hash: " .. SlotCore.hex_hash(cur_hash))

  local bs, bn = SlotCore.get_bound_slot()
  if bs == "fb01" and bn and bn >= 1 then
    local state = SlotCore.load_slots("fb01", 8)
    local slots = (state and state.slots) or nil
    local slot = slots and slots[bn] or nil
    if slot and slot.msgs then
      local slot_blob = table.concat(slot.msgs or {}, "")
      local slot_hash = SlotCore.hash_bytes(slot_blob)
      local saved_hash = slot.saved_hash or slot_hash
      local dirty = (slot_hash ~= saved_hash)
      r.ImGui_Text(ctx, ("Bound slot %d: slot_hash=%s saved_hash=%s dirty=%s"):format(
        bn, SlotCore.hex_hash(slot_hash), SlotCore.hex_hash(saved_hash), tostring(dirty)
      ))
      r.ImGui_Text(ctx, "Reason: " .. (dirty and "hash differs from saved/export baseline" or "matches baseline"))
    else
      r.ImGui_Text(ctx, ("Bound slot %d: (empty)"):format(bn))
    end
  else
    r.ImGui_Text(ctx, "Bound slot: (none)  (open Librarian and select a slot)")
  end

  if r.ImGui_Button(ctx, "Copy snapshot hex", 180, 0) then
    r.ImGui_SetClipboardText(ctx, SlotCore.hexdump_bytes(blob, 16))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
r.ImGui_End(ctx)
  end

  if open then
    r.defer(loop)
  else
    r.ImGui_DestroyContext(ctx)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.defer(loop)
local function _cleanup_mode_for_kind(kind)
  local k = tostring(kind or "")
  if k == "instvoice" and CAPTURE_CFG.cleanup_mode_instvoice ~= nil then return CAPTURE_CFG.cleanup_mode_instvoice end
  if k == "config"    and CAPTURE_CFG.cleanup_mode_config    ~= nil then return CAPTURE_CFG.cleanup_mode_config end
  if k == "bank"      and CAPTURE_CFG.cleanup_mode_bank      ~= nil then return CAPTURE_CFG.cleanup_mode_bank end
  return CAPTURE_CFG.cleanup_mode or 0
end

-- Phase 8: mapping preset storage
local function _get_preset_dir()
  local proj = r.GetProjectPath("") or ""
  if proj ~= "" then
    return proj .. "/IFLS_FB01_Presets"
  end
  return (root or r.GetResourcePath()) .. "/IFLS_FB01_Presets"
end

local function _ensure_dir(path)
  r.RecursiveCreateDirectory(path, 0)
end

local function _write_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false, "cannot open file for write" end
  f:write(data)
  f:close()
  return true
end

local function _read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function _save_mapping_preset(name, preset_tbl)
  local dir = _get_preset_dir()
  _ensure_dir(dir)
  local path = dir .. "/" .. name .. ".json"
  local ok, err = _write_file(path, _json_encode(preset_tbl))
  return ok, err, path
end

local function _load_mapping_preset(name)
  local dir = _get_preset_dir()
  local path = dir .. "/" .. name .. ".json"
  local d = _read_file(path)
  if not d then return nil, "preset not found", path end
  local t = _json_decode_min(d)
  if type(t) ~= "table" then return nil, "invalid json", path end
  return t, nil, path
end

-- Phase 9: rewritten capture tick (multipart bulk aware, service-manual spacing)
local function capture_tick_v2()
  -- process mapping send queue when no capture is active
  if bank_send_queue and not CAPTURE.active and bank_send_queue.list and bank_send_queue.idx and bank_send_queue.idx <= #bank_send_queue.list then
    local v64 = bank_send_queue.list[bank_send_queue.idx]
    local _sys = bank_send_queue.sys
    local _inst = bank_send_queue.inst
    local function _send_one()
      local msg_tbl = VoiceDump.build_inst_voice_sysex(_sys, _inst, v64)
      -- InstVoice is small: use normal delay
      send_sysex_throttled(string.char(table.unpack(msg_tbl)), CAPTURE_CFG.sysex_delay_ms or 10)
      if bank_send_verify then
        CAPTURE.retries_left = CAPTURE_CFG.retry_count_instvoice or 1
        verify_start("instvoice", v64, { sys_ch=_sys, inst_no=_inst, timeout=CAPTURE_CFG.t_instvoice })
        enqueue_sysex(Syx.dump_inst_voice(_sys, _inst))
      end
    end

    if bank_send_verify then
      capture_start("instvoice", _send_one, { timeout = CAPTURE_CFG.t_instvoice, retries = CAPTURE_CFG.retry_count_instvoice })
    else
      _send_one()
    end

    bank_send_queue.idx = bank_send_queue.idx + 1
    bank_send_queue.inst = (_inst + 1) % 8
    if bank_send_queue.idx > #bank_send_queue.list then
      bank_send_queue = nil
    end
  end

  if not CAPTURE.active then return end

  -- timeout
  if _now() > (CAPTURE.deadline or 0) then
    CAPTURE.err = "capture timeout"
    _capture_stop_recording()
    CAPTURE.active = false
    CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
    _capture_restore_arms()
    return
  end

  -- collect all FB01 SysEx from newly created items
  local new_items = _capture_collect_new_items(CAPTURE.track)
  local msgs = _collect_sysex_from_items(new_items)
  if msgs and #msgs > 0 then
    CAPTURE.captured_sysex_msgs = msgs
    CAPTURE.captured_sysex_assembled = _assemble_bulk_msgs(msgs)
    CAPTURE.last_backend = "TAKE"
    CAPTURE.last_rx_ts = _now()
  end

  -- completion criteria per kind
  local complete = false
  if CAPTURE.kind == "instvoice" then
    complete = (CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1)
  elseif CAPTURE.kind == "config" then
    if CAPTURE.captured_sysex_assembled and ConfigDump and ConfigDump.decode_config_from_sysex then
      local ok = pcall(function()
        local buf = string.char(table.unpack(CAPTURE.captured_sysex_assembled))
        local bytes = {}
        for i=1,#buf do bytes[i]=buf:byte(i) end
        local _ = ConfigDump.decode_config_from_sysex(bytes)
      end)
      complete = ok
    else
      -- no ConfigDump: accept first dump
      complete = (CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1)
    end
  elseif CAPTURE.kind == "bank" then
    if CAPTURE.captured_sysex_assembled then
      local decoded = nil
      if decode_bank_any then
        decoded = select(1, decode_bank_any(CAPTURE.captured_sysex_assembled))
      end
      complete = (decoded and decoded.voices and #decoded.voices == 48) and true or false
      if complete then
        last_rx_voicebank = decoded
        last_rx_voicebank_raw = CAPTURE.captured_sysex_assembled
      end
    end
    -- fallback: stop after seeing at least one msg (some variants are single msg)
    if not complete and CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1 and (_now() - (CAPTURE.first_seen_ts or _now()) > 0.4) then
      complete = true
    end
    if CAPTURE.captured_sysex_msgs and not CAPTURE.first_seen_ts then CAPTURE.first_seen_ts = _now() end
  else
    complete = (CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1)
  end

  if complete then
    _capture_stop_recording()
    CAPTURE.active = false
    CAPTURE.new_items = new_items
    _capture_restore_arms()
    -- refresh RX state
    if Rx and Rx.poll_take_backend then Rx.poll_take_backend() end
  end
end
local function _native_bulk_supported(kind)
  -- "instvoice" is safe because we already have a proven builder (VoiceDump.build_inst_voice_sysex).
  -- Bank/Config bulk builders require exact manual framing (byte count fields etc.) and are not enabled by default.
  return kind == "instvoice"
end
if r.ImGui_Button(ctx, "Setup Capture Track + Route HW Out", 320, 0) then
  _ensure_capture_track_and_route()
end
r.ImGui_Text(ctx, "Creates/arms 'FB01 Capture', sets MIDI input best-effort, and attempts to set track hardware MIDI output to Preferred MIDI Output.")

-- Phase 21: System Channel (Device ID) UI + persistence
local sysch = tonumber(CAPTURE_CFG.sys_ch or 0) or 0
changed, sysch = r.ImGui_SliderInt(ctx, "FB-01 System Channel (SysEx Device ID)", sysch, 0, 15)
if changed then
  CAPTURE_CFG.sys_ch = sysch
  _ext_set("fb01_sys_ch", sysch)
end
r.ImGui_Text(ctx, "Note: System Channel is NOT the MIDI channel. It selects which FB-01 responds to SysEx.")

r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Autodetect System Channel", 210, 0) then
  _autosys_start()
end
if AUTOSYS and AUTOSYS.status and AUTOSYS.status ~= "" then
  r.ImGui_Text(ctx, "Auto-detect: " .. tostring(AUTOSYS.status))
end

changed, CAPTURE_CFG.cleanup_mode = r.ImGui_Combo(ctx, "Capture cleanup", CAPTURE_CFG.cleanup_mode, "Keep items\0Delete items\0Archive items\0\0")
if changed then _ext_set("capture_cleanup_mode", CAPTURE_CFG.cleanup_mode) end

local tinst = CAPTURE_CFG.t_instvoice
changed, tinst = r.ImGui_DragDouble(ctx, "Timeout InstVoice (s)", tinst, 0.1, 0.5, 10.0, "%.1f")
if changed then CAPTURE_CFG.t_instvoice = tinst; _ext_set("capture_timeout_instvoice", tinst) end
local tcfg = CAPTURE_CFG.t_config
changed, tcfg = r.ImGui_DragDouble(ctx, "Timeout Config (s)", tcfg, 0.1, 1.0, 20.0, "%.1f")
if changed then CAPTURE_CFG.t_config = tcfg; _ext_set("capture_timeout_config", tcfg) end
local tbank = CAPTURE_CFG.t_bank
changed, tbank = r.ImGui_DragDouble(ctx, "Timeout Bank (s)", tbank, 0.1, 2.0, 30.0, "%.1f")
if changed then CAPTURE_CFG.t_bank = tbank; _ext_set("capture_timeout_bank", tbank) end

local rchg
local rinst = CAPTURE_CFG.retry_count_instvoice
rchg, rinst = r.ImGui_SliderInt(ctx, "Retry InstVoice", rinst, 0, 5)
if rchg then CAPTURE_CFG.retry_count_instvoice = rinst; _ext_set("capture_retry_count_instvoice", rinst) end
local rcfg = CAPTURE_CFG.retry_count_config
rchg, rcfg = r.ImGui_SliderInt(ctx, "Retry Config", rcfg, 0, 5)
if rchg then CAPTURE_CFG.retry_count_config = rcfg; _ext_set("capture_retry_count_config", rcfg) end
local rbank = CAPTURE_CFG.retry_count_bank
rchg, rbank = r.ImGui_SliderInt(ctx, "Retry Bank", rbank, 0, 5)
if rchg then CAPTURE_CFG.retry_count_bank = rbank; _ext_set("capture_retry_count_bank", rbank) end

-- Phase 6: friendly bank selector (FB-01 voice banks 0..6)
local bank_names = {
  "Bank 1 (RAM1) [id=0]",
  "Bank 2 (RAM2) [id=1]",
  "Bank 3 (ROM1) [id=2]",
  "Bank 4 (ROM2) [id=3]",
  "Bank 5 (ROM3) [id=4]",
  "Bank 6 (ROM4) [id=5]",
  "Bank 7 (ROM5) [id=6]",
  "Bank 8 (reserved?) [id=7]"
}
local bidx = (bank_request_id or 0) + 1
local bchg
bchg, bidx = r.ImGui_Combo(ctx, "Voice Bank", bidx, table.concat(bank_names, "\0") .. "\0\0")
if bchg then bank_request_id = bidx - 1 end

changed, bank_request_id = r.ImGui_SliderInt(ctx, "Request Bank ID", bank_request_id, 0, 7)

if r.ImGui_Button(ctx, "Auto Capture + Request Bank Dump") then
  bank_capture_status = ""
  capture_start("bank", function()
    local bin = Syx.request_bank(sys_ch, bank_request_id)
    send_sysex(bin)
    -- For some devices, a set request first can help; keep minimal here.
  end, {timeout=CAPTURE_CFG.t_bank})
end
if r.ImGui_Button(ctx, "Auto Capture + Send Bank Dump + Verify") then
  if last_rx_voicebank_raw and #last_rx_voicebank_raw > 0 then
    bank_capture_status = ""
    local _sys = sys_ch
    capture_start("bank", function()
      -- send bank dump as-is (most compatible)
      send_sysex(bytes_to_string(last_rx_voicebank_raw))
      -- request bank dump back for verify
      enqueue_sysex(Syx.request_bank(_sys, bank_request_id))
      verify_start("bank", last_rx_voicebank_raw, { sys_ch=_sys, timeout=CAPTURE_CFG.t_bank })
    end, {timeout=CAPTURE_CFG.t_bank, retries=CAPTURE_CFG.retry_count_bank})
  else
    r.MB("No bank dump in memory (last captured bank). First request/capture a bank dump.", "Bank Verify", 0)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Generate & Send Bank (native bulk)", 280, 0) then
    if CAPTURE_CFG.allow_native_bulk_builders ~= 1 then
      r.MB("Enable 'native bulk builders' in settings first (experimental).", "Native Bulk", 0)
    else
      if last_rx_voicebank and last_rx_voicebank.voices and #last_rx_voicebank.voices > 0 then
        local msgs, err = BulkNative.build_bank_bulk(sysch, req_voice_bank or 0, last_rx_voicebank.voices, 48, CAPTURE_CFG.native_chunk_source_bytes or 48, { strict_checksum = (CAPTURE_CFG.allow_native_bulk_strict==1), bytecount_two_bytes = (CAPTURE_CFG.native_bytecount_two==1), checksum_from_body_index = 4 })
        if not msgs then
          r.MB("Native bulk build failed: " .. tostring(err), "Native Bulk", 0)
        else
          send_sysex_msgs_throttled(msgs, CAPTURE_CFG.bulk_delay_ms or 120)
        end
      else
        r.MB("No decoded bank in memory. First capture/decode a bank dump (Phase 4+).", "Native Bulk", 0)
      end
    end
  end

end
if bank_capture_status and bank_capture_status ~= "" then
  r.ImGui_Text(ctx, bank_capture_status)
end

if BANK_VERIFY_REPORT then
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Last bank verify: ok="..tostring(BANK_VERIFY_REPORT.ok).." diffs="..tostring(BANK_VERIFY_REPORT.total_diffs).." backend="..tostring(BANK_VERIFY_REPORT.backend).." time="..tostring(BANK_VERIFY_REPORT.time_str))
  if r.ImGui_Button(ctx, "Copy last bank verify report") then
  if BANK_VERIFY_REPORT then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Bank diff report export")
    if r.ImGui_Button(ctx, "Export parameter diff report (JSON)", 260, 0) then
      local dir = r.GetProjectPath("") or (root or r.GetResourcePath())
      local fn = dir .. "/IFLS_FB01_ParamDiffReport_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
      _write_file(fn, _json_encode(BANK_VERIFY_REPORT))
      r.ShowConsoleMsg("Wrote: "..fn.."\n")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export parameter diff report (TXT)", 250, 0) then
      local dir = r.GetProjectPath("") or (root or r.GetResourcePath())
      local fn = dir .. "/IFLS_FB01_ParamDiffReport_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
      local out = {}
      out[#out+1] = "FB01 Param Diff Report " .. os.date("%Y-%m-%d %H:%M:%S")
      if BANK_VERIFY_REPORT.summary then
        out[#out+1] = ("OK=%s diffs=%s backend=%s"):format(tostring(BANK_VERIFY_REPORT.summary.ok), tostring(BANK_VERIFY_REPORT.summary.total_diffs), tostring(BANK_VERIFY_REPORT.summary.backend))
      end
      if BANK_VERIFY_REPORT.voices then
        for _,v in ipairs(BANK_VERIFY_REPORT.voices) do
          if v and v.param_diffs and #v.param_diffs>0 then
            out[#out+1] = ("Voice %d: %d diffs"):format(v.index or -1, #v.param_diffs)
            for _,d in ipairs(v.param_diffs) do out[#out+1] = "  "..d end
          end
        end
      end
      _write_file(fn, table.concat(out, "\n"))
      r.ShowConsoleMsg("Wrote: "..fn.."\n")
    end
  end

    local rep = _bank_report_to_text(BANK_VERIFY_REPORT)
    r.ImGui_SetClipboardText(ctx, rep)
  end
end

local _c
  _c, bank_import_path = r.ImGui_InputText(ctx, "Bank .syx path", bank_import_path, 4096)
  if r.ImGui_Button(ctx, "Load Bank .syx") then
    bank_import_err = nil
    bank_import = nil
    bank_sel = {}
    local bytes = read_file_bytes(bank_import_path)
    if bytes then
      local decoded, err = decode_bank_any(bytes)
      if decoded then
        bank_import = decoded.res
        bank_import_layout = decoded.layout
        last_rx_voicebank = decoded.res
        last_rx_voicebank_raw = (last and last.bytes) or syx
        for i=1,48 do bank_sel[i] = true end
      else
        bank_import_err = err
      end
    else
      bank_import_err = "could not read file"
    end
  end

  if bank_import_err then
    r.ImGui_Text(ctx, "Load error: " .. tostring(bank_import_err))
  end

  if bank_import then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, string.format("Loaded bank_no=%d voices=%d size=%d bytes",
      bank_import.bank_no or -1, #(bank_import.voices or {}), bank_import.size or 0))

    if r.ImGui_Button(ctx, "Select All") then
      for i=1,48 do bank_sel[i]=true end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Select None") then
      for i=1,48 do bank_sel[i]=false end
    end

    r.ImGui_SameLine(ctx)
    _c, bank_export_mode = r.ImGui_Combo(ctx, "Export Mode", bank_export_mode, "Payload .bin\0Bank JSON\0Single-Voice .syx (Inst)\0\0")
    r.ImGui_SameLine(ctx)
    _c, bank_inst_target = r.ImGui_SliderInt(ctx, "Inst", bank_inst_target, 0, 7)

    if r.ImGui_Button(ctx, "Export Selected") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      if bank_export_mode == 0 then
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            local safe = (v.name or "VOICE"):gsub("[^%w%-%_ ]","_")
            local fname = voice_export_dir .. string.format("/bank%d_voice%02d_%s.bin", bank_import.bank_no or 0, v.index or (i-1), safe)
            write_bytes_to_file(fname, v.payload_bytes or {})
          end
        end
      elseif bank_export_mode == 1 then
        local export = { bank_no=bank_import.bank_no, voices={} }
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            export.voices[#export.voices+1] = { index=v.index, name=v.name, payload_bytes=v.payload_bytes }
          end
        end
        local js = json_encode_min(export)
        local bytes={}
        for i=1,#js do bytes[i]=string.byte(js,i) end
        local fname = voice_export_dir .. string.format("/bank%d_%s.json", bank_import.bank_no or 0, now_stamp())
        write_bytes_to_file(fname, bytes)
      else
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            local pb = v.payload_bytes or {}
            local off = math.max(1, (#pb - 64) + 1)
            local voice64={}
            for k=1,64 do voice64[k] = pb[off + (k-1)] or 0 end
            local msg = VoiceDump.build_inst_voice_sysex(sys_ch or sysch or 0, bank_inst_target, voice64)
            local safe = (v.name or "VOICE"):gsub("[^%w%-%_ ]","_")
            local fname = voice_export_dir .. string.format("/bank%d_voice%02d_inst%d_%s.syx", bank_import.bank_no or 0, v.index or (i-1), bank_inst_target, safe)
            write_bytes_to_file(fname, msg)
          end
        end
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Send Selected to Inst (live)") then
      for i=1,48 do
        if bank_sel[i] then
          local v = bank_import.voices[i]
          local pb = v.payload_bytes or {}
          local off = math.max(1, (#pb - 64) + 1)
          local voice64={}
          for k=1,64 do voice64[k] = pb[off + (k-1)] or 0 end
          local msg = VoiceDump.build_inst_voice_sysex(sys_ch or sysch or 0, bank_inst_target, voice64)
          if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
        end
      end
    end
    r.ImGui_SameLine(ctx)
    local chg
    chg, bank_send_verify = r.ImGui_Checkbox(ctx, "Verify each voice", bank_send_verify)
    if r.ImGui_Button(ctx, "Send Selected to Inst (auto capture)") then
      if not bank_import or not bank_import.voices then
        r.MB("No bank loaded.", "Bank Send", 0)
      else
        local list = {}
        for i=1,48 do
          if bank_sel[i] then
            local v = bank_import.voices[i]
            local voice64 = v.voice64
            if not voice64 then
              -- derive from payload_bytes
              local pb = v.payload_bytes or {}
              local off = math.max(1, (#pb - 64) + 1)
              voice64 = {}
              for k=1,64 do voice64[k] = pb[off + (k-1)] or 0 end
            end
            list[#list+1] = voice64
          end
        end
        if #list == 0 then
          r.MB("No voices selected.", "Bank Send", 0)
        else
          bank_send_queue = { list=list, idx=1, inst=bank_inst_target, sys=(sys_ch or 0), retries=CAPTURE_CFG.retry_count_instvoice }
        end
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Auto Capture + Send+Verify") then
      -- Record a short MIDI capture so large SysEx dumps can be read back reliably
      local _sys = (sys_ch or sysch or 0)
      local _inst = sv_send_inst
      local function _send()
        local msg = VoiceDump.build_inst_voice_sysex(_sys, _inst, sv_import.voice_bytes)
        if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
        verify_start("instvoice", sv_import.voice_bytes, { sys_ch=_sys, inst_no=_inst, timeout=2.5 })
        enqueue_sysex(Syx.dump_inst_voice(_sys, _inst))
      end
      capture_start("instvoice", _send, { timeout = 4.0 })
    end

    if r.ImGui_BeginTable(ctx, "banktbl", 3, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
      r.ImGui_TableSetupColumn(ctx, "Sel")
      r.ImGui_TableSetupColumn(ctx, "Idx")
      r.ImGui_TableSetupColumn(ctx, "Name")
      r.ImGui_TableHeadersRow(ctx)
      for i=1,48 do
        local v = bank_import.voices[i]
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0)
        local changed
        changed, bank_sel[i] = r.ImGui_Checkbox(ctx, "##banksel"..tostring(i), bank_sel[i] == true)
        r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, string.format("%02d", v.index or (i-1)))
        r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_Text(ctx, v.name or "???????")
      end
      r.ImGui_EndTable(ctx)
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

if r.ImGui_CollapsingHeader(ctx, "Patch Export / Import", 0) then
  r.ImGui_Text(ctx, "Export voices/banks from FB-01 to the computer (requests + save .syx).")
  r.ImGui_Separator(ctx)

  local _c
  _c, req_voice_bank = r.ImGui_SliderInt(ctx, "Request Voice Bank (0..6)", req_voice_bank, 0, 6)
  if r.ImGui_Button(ctx, "Request: Voice Bank") then
    enqueue_sysex(Syx.dump_voice_bank(sys_ch or sysch or 0, req_voice_bank))
  end
  r.ImGui_SameLine(ctx)
  _c, req_inst_voice = r.ImGui_SliderInt(ctx, "Request Inst Voice (0..7)", req_inst_voice, 0, 7)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Request: Inst Voice") then
    enqueue_sysex(Syx.dump_inst_voice(sys_ch or sysch or 0, req_inst_voice))
  end

  r.ImGui_Separator(ctx)

  if last_rx_voicebank_raw then
    r.ImGui_Text(ctx, "Last RX: VoiceBank dump available.")
    if r.ImGui_Button(ctx, "Export last VoiceBank (.syx)") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      local fname = voice_export_dir .. "/fb01_voicebank_" .. tostring(req_voice_bank) .. "_" .. now_stamp() .. ".syx"
      write_bytes_to_file(fname, last_rx_voicebank_raw)
    end
  else
    r.ImGui_Text(ctx, "No voice bank dump received yet.")
  end

  if last_rx_voice_raw then
    r.ImGui_Text(ctx, "Last RX: Single Voice dump available.")
    if r.ImGui_Button(ctx, "Export last Voice (.syx)") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      local fname = voice_export_dir .. "/fb01_voice_" .. now_stamp() .. ".syx"
      write_bytes_to_file(fname, last_rx_voice_raw)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export voice payload (.bin)") then
      r.RecursiveCreateDirectory(voice_export_dir, 0)
      local fname = voice_export_dir .. "/fb01_voice_payload_" .. now_stamp() .. ".bin"
      write_bytes_to_file(fname, last_rx_voice.payload_bytes or {})
    end
  else
    r.ImGui_Text(ctx, "No single voice dump received yet.")
  end

  r.ImGui_Text(ctx, "Tip: enable Auto Decode, then request bank/inst voice and export once received.")
  r.ImGui_EndChild(ctx)
end

      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

    if r.ImGui_BeginMenuBar(ctx) then
      if r.ImGui_BeginMenu(ctx, "Help", true) then
        r.ImGui_Text(ctx, "Requires: ReaImGui + SWS SysEx")
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Tip: Use your existing FB-01 dump record/replay tools for librarian/recall.")
        r.ImGui_EndMenu(ctx)
      end
      r.ImGui_EndMenuBar(ctx)
    end

    r.ImGui_Separator(ctx)
    local chg, nsys = r.ImGui_SliderInt(ctx, "FB-01 SysEx Channel (SysCh)", sysch, 0, 15)
    if chg then sysch = clamp(nsys,0,15) end
    local ch2, ninst = r.ImGui_SliderInt(ctx, "Instrument (0..7)", inst, 0, 7)
    if ch2 then inst = clamp(ninst,0,7) end

    r.ImGui_Separator(ctx)
    requests_panel()
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Randomize: Voice", 160, 0) then randomize("voice") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Randomize: All Ops", 160, 0) then randomize("ops") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Randomize: All", 160, 0) then randomize("all") end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Constrained random")
    local chg_i, ni = r.ImGui_SliderDouble(ctx, "Random intensity", rand_intensity, 0.0, 1.0)
    if chg_i then rand_intensity = ni end
    if r.ImGui_Button(ctx, "Rand: OP Env", 120, 0) then randomize_groups_intensity({ops_env=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: OP Pitch", 120, 0) then randomize_groups_intensity({ops_pitch=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: OP Level", 120, 0) then randomize_groups_intensity({ops_level=true}, rand_intensity) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Rand: Voice LFO", 140, 0) then randomize_groups_intensity({voice_lfo=true}, rand_intensity) end

    if r.ImGui_Button(ctx, "Save patch state (JSON)", 200, 0) then save_state_json() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Load patch state (JSON)", 200, 0) then load_state_json() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Export .syx (param stream)", 200, 0) then export_param_stream_syx() end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "User templates")
    local names = ""
    for i=1,#(user_db.templates or {}) do names = names .. (user_db.templates[i].name or ("Template "..i)) .. "\0" end
    if names == "" then names = " (none)\0" end
    local chg_u, new_u = r.ImGui_Combo(ctx, "Saved", user_tpl_idx, names)
    if chg_u then user_tpl_idx = new_u end
    if r.ImGui_Button(ctx, "Apply Saved Template", 180, 0) then
      local t = (user_db.templates or {})[user_tpl_idx+1]
      if t then apply_template(t) end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save Current as Template", 200, 0) then
      local okN, nm = r.GetUserInputs("Save Template", 1, "Name", "My Template")
      if okN and nm ~= "" then
        user_db = load_user_templates()
        user_db.templates = user_db.templates or {}
        user_db.templates[#user_db.templates+1] = capture_current_as_template(nm)
        save_user_templates(user_db)
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Reload Templates", 140, 0) then
      user_db = load_user_templates()
      user_tpl_idx = 0
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Templates (starting points)")
    local combo_str = ""
    for i=1,#template_names do combo_str = combo_str .. template_names[i] .. "\0" end
    local chg_t, new_idx = r.ImGui_Combo(ctx, "Template", template_idx, combo_str)
    if chg_t then template_idx = new_idx end
    if r.ImGui_Button(ctx, "Apply Template", 160, 0) then
      local name = template_names[template_idx+1]
      if name and TEMPLATES[name] then apply_template(TEMPLATES[name]) end
    end

    
    r.ImGui_Separator(ctx)

    schema_tab_was_active = schema_tab_active
schema_tab_active = false
if r.ImGui_BeginTabBar(ctx, "tabs") then
      if r.ImGui_BeginTabItem(ctx, "Voice", true) then
        voice_panel()
        r.ImGui_EndTabItem(ctx)
      end
      if r.ImGui_BeginTabItem(ctx, "Operators", true) then
        operator_panel()
        r.ImGui_EndTabItem(ctx)
      end
      if r.ImGui_BeginTabItem(ctx, "Instrument", true) then
        instrument_panel()
        r.ImGui_EndTabItem(ctx)

if r.ImGui_BeginTabItem(ctx, "Config/MIDI") then
  if P.config_params then
    r.ImGui_Text(ctx, "System/Config (SysEx ch " .. tostring(sys_ch) .. ")")
    r.ImGui_Separator(ctx)

-- B2.2: Live dump requests / receiver
r.ImGui_Text(ctx, "B2.2 Live Dumps")

local chg_ad, ad = r.ImGui_Checkbox(ctx, "Auto-decode on receive (B2.3)", auto_decode)
if chg_ad then auto_decode = ad end
local changed_bank, bank_no = r.ImGui_SliderInt(ctx, "Voice Bank (0-6)", dump_bank_no or 0, 0, 6)
if changed_bank then dump_bank_no = bank_no end
if r.ImGui_Button(ctx, "Request Voice Bank") then
  send_sysex(Syx.request_bank(sys_ch, dump_bank_no or 0))
end
if r.ImGui_Button(ctx, "Request Current Config") then
  send_sysex(Syx.request_current_config(sys_ch))
end
local changed_inst, inst_no = r.ImGui_SliderInt(ctx, "Instrument (1-8)", dump_inst_no or 1, 1, 8)
if changed_inst then dump_inst_no = inst_no end
if r.ImGui_Button(ctx, "Request Instrument Voice") then
  send_sysex(Syx.request_instrument_voice(sys_ch, dump_inst_no or 1))
end

local hs = Rx.state.last_handshake
if hs then r.ImGui_Text(ctx, "Handshake: " .. hs) end

-- Phase 2.5: advance Send+Verify state on ACK
if verify_stage == "await_ack" and hs == "ACK" and verify_target then
  verify_stage = "await_dump"
  -- request config dump for the current slot
  enqueue_sysex(Syx.dump_config_slot(sysch or 0, cfg_slot or 0))
  verify_start("config", verify_target, { timeout = 3.5 })
end

local last = Rx.get_last_dump()
-- Phase 2.5: tick verify engine (works with LIVE or TAKE backend)
verify_tick(last)
if last and last.preview then
  r.ImGui_TextWrapped(ctx, "Last dump: " .. last.preview)
  if r.ImGui_Button(ctx, "Save last dump to project folder") then
    local proj = r.GetProjectPath("")
    local fname = string.format("FB01_dump_%s.syx", os.date("%Y%m%d_%H%M%S"))
    local path = proj .. "/" .. fname
    local ok, err = Rx.save_last_dump_to_file(path)
    if ok then
      dump_status = "Saved: " .. path
    else
      dump_status = "Save failed: " .. tostring(err)
    end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear") then
    Rx.clear_last_dump()
    dump_status = nil
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if dump_status then r.ImGui_TextWrapped(ctx, dump_status) end

-- B2.3: Decode last dump (nibble bulk) + show patch names (heuristic)
if r.ImGui_Button(ctx, "Decode last dump") then
  local last = Rx.get_last_dump()
  if last and last.bytes then
    local res = DumpDec.decode_sysex(last.bytes)
    if res and res.ok then
      last_decoded = res.decoded
      last_names = res.names
      last_decode_info = res.info
      dump_status = (res.checksum_ok and "Decode OK (checksum OK)" or "Decode OK (checksum FAIL)")
    else
      last_decoded = nil
      last_names = nil
      last_decode_info = res and res.info or nil
      dump_status = "Decode failed: " .. tostring(res and res.error or "unknown")
    end
  else
    dump_status = "No dump in buffer."
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if last_decode_info then
  r.ImGui_TextWrapped(ctx, "Decoded len: " .. tostring(last_decode_info.decoded_len or "?") ..
                          " | Names found: " .. tostring(last_decode_info.names_found or 0) ..
                          " | Checksum: " .. tostring(last_decode_info.checksum_ok))
end

if last_decoded and r.ImGui_Button(ctx, "Export decoded payload (.bin) to project folder") then
  local proj = r.GetProjectPath("")
  local fname = string.format("FB01_decoded_%s.bin", os.date("%Y%m%d_%H%M%S"))
  local path = proj .. "/" .. fname
  local f = io.open(path, "wb")
  if f then
    for i=1,#last_decoded do f:write(string.char(last_decoded[i] & 0xFF)) end
    f:close()
    export_status = "Exported: " .. path
  else
    export_status = "Export failed: cannot open file"
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if export_status then r.ImGui_TextWrapped(ctx, export_status) end
if last_names and #last_names > 0 then
  

-- B2.4: Import .syx voice bank (48) and display names
if r.ImGui_Button(ctx, "Import Voice Bank (.syx)") then
  import_bank_dialog()
end
if bank_names then
  r.ImGui_TextWrapped(ctx, "Bank: " .. tostring(bank_name) .. " | Checksum: " .. tostring(bank_checksum_ok))
  
local chg_sel, nv = r.ImGui_SliderInt(ctx, "Selected Voice (0-47)", selected_bank_voice, 0, 47)
if chg_sel then selected_bank_voice = nv end
if r.ImGui_Button(ctx, "Apply selected voice to UI (no send)") then
  apply_bank_voice_to_ui(selected_bank_voice)
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send selected voice (queued)") then
  local msgs = build_voice_param_stream(selected_bank_voice)
  if msgs then
    enqueue_sysex_many(msgs)
    bank_apply_status = "Queued 64 param messages for voice " .. tostring(selected_bank_voice)
  else
    bank_apply_status = "No voice bytes cached."
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
if bank_apply_status then r.ImGui_TextWrapped(ctx, bank_apply_status) end

if r.ImGui_Button(ctx, "Send CURRENT UI voice (diff queued)") then
  local bytes = encode_current_ui_voice_block()
  local msgs = build_param_stream_from_bytes(bytes, true)
  enqueue_sysex_many(msgs)
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued " .. tostring(#msgs) .. " changed params (diff)."
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send CURRENT UI voice (full queued)") then
  local bytes = encode_current_ui_voice_block()
  local msgs = build_param_stream_from_bytes(bytes, false)
  enqueue_sysex_many(msgs)
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued 64 params (full)."

if r.ImGui_Button(ctx, "Send CURRENT UI voice as EventList (diff)") then
  local bytes = encode_current_ui_voice_block()
  local events = build_eventlist_from_voice_bytes(bytes, true)
  local msg = Syx.event_list(events)
  enqueue_sysex_many({{msg=msg, delay_ms = slow_chunk and 50 or nil}})
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued EventList (" .. tostring(#events) .. " events, diff)."
end
r.ImGui_SameLine(ctx)
if r.ImGui_Button(ctx, "Send CURRENT UI voice as EventList (full)") then
  local bytes = encode_current_ui_voice_block()
  local events = build_eventlist_from_voice_bytes(bytes, false)
  local msg = Syx.event_list(events)
  enqueue_sysex_many({{msg=msg, delay_ms = slow_chunk and 50 or nil}})
  last_sent_voice_bytes = bytes
  bank_apply_status = "Queued EventList (" .. tostring(#events) .. " events, full)."
end

end

if r.ImGui_Button(ctx, "

if r.ImGui_CollapsingHeader(ctx, "Parameter List", r.ImGui_TreeNodeFlags_DefaultOpen()) then
  r.ImGui_Text(ctx, "Searchable list of parameters (deterministic keys).")
  local chg
  chg, paramlist_filter = r.ImGui_InputText(ctx, "Search", paramlist_filter)
  r.ImGui_SameLine(ctx)
  chg, paramlist_show_raw = r.ImGui_Checkbox(ctx, "Show Raw VoiceBlock (0..63)", paramlist_show_raw)
  chg, paramlist_show_voice = r.ImGui_Checkbox(ctx, "Show Voice", paramlist_show_voice)
  r.ImGui_SameLine(ctx)
  chg, paramlist_show_ops = r.ImGui_Checkbox(ctx, "Show OPs", paramlist_show_ops)
  r.ImGui_SameLine(ctx)
  chg, paramlist_show_conf = r.ImGui_Checkbox(ctx, "Show Config", paramlist_show_conf)

  local items = build_param_catalog()
  if r.ImGui_BeginTable(ctx, "paramlist_table", 6, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingStretchProp()) then
    r.ImGui_TableSetupColumn(ctx, "Scope")
    r.ImGui_TableSetupColumn(ctx, "schema_key")
    r.ImGui_TableSetupColumn(ctx, "Label")
    r.ImGui_TableSetupColumn(ctx, "Value")
    r.ImGui_TableSetupColumn(ctx, "Range")
    r.ImGui_TableSetupColumn(ctx, "Encoding/Note")
    r.ImGui_TableHeadersRow(ctx)
    for i=1,#items do
      local it = items[i]
      local ok_scope = (it.scope=="voice" and paramlist_show_voice) or (it.scope=="op" and paramlist_show_ops) or (it.scope=="conf" and paramlist_show_conf)
      local ok_search = (paramlist_filter == "" or _contains(it.key, paramlist_filter) or _contains(it.name, paramlist_filter))
      if ok_scope and ok_search then
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, it.scope)
        r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, tostring(it.key))
        r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_Text(ctx, tostring(it.name))
        r.ImGui_TableSetColumnIndex(ctx, 3); r.ImGui_Text(ctx, tostring(it.get()))
        r.ImGui_TableSetColumnIndex(ctx, 4); r.ImGui_Text(ctx, tostring(it.range or ""))
        r.ImGui_TableSetColumnIndex(ctx, 5); r.ImGui_Text(ctx, tostring(it.enc or "") .. (it.extra and (" "..it.extra) or ""))
      end
    end
    r.ImGui_EndTable(ctx)
  end

  if paramlist_show_raw then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Raw VoiceBlock bytes (64 params -> pp=0x40+index).")
    local bytes = encode_current_ui_voice_block()
    if r.ImGui_BeginTable(ctx, "rawblock_table", 5, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
      r.ImGui_TableSetupColumn(ctx, "Index")
      r.ImGui_TableSetupColumn(ctx, "pp (hex)")
      r.ImGui_TableSetupColumn(ctx, "Value (dec)")
      r.ImGui_TableSetupColumn(ctx, "Value (hex)")
      r.ImGui_TableSetupColumn(ctx, "Diff?")
      r.ImGui_TableHeadersRow(ctx)
      for p=0,63 do
        local v = (bytes[p+1] or 0) & 0xFF
        local diff = ""
        if last_sent_voice_bytes then
          local prev = (last_sent_voice_bytes[p+1] or -1) & 0xFF
          if prev ~= v then diff = "*" end
        end
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, tostring(p))
        r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, string.format("0x%02X", 0x40 + p))
        r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_Text(ctx, tostring(v))
        r.ImGui_TableSetColumnIndex(ctx, 3); r.ImGui_Text(ctx, string.format("%02X", v))
        r.ImGui_TableSetColumnIndex(ctx, 4); r.ImGui_Text(ctx, diff)
      end
      r.ImGui_EndTable(ctx)
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

if r.ImGui_CollapsingHeader(ctx, "TrueBulk VoiceWrite", r.ImGui_TreeNodeFlags_DefaultOpen()) then
  r.ImGui_Text(ctx, "Template-based single-message voice write (capture real dump prefix+layout).")
  if r.ImGui_Button(ctx, "Request single-voice dump (capture template)") then
    local req = Syx.request_instrument_voice(sys_ch, inst_no)
    enqueue_sysex_many({{msg=req, delay_ms = slow_chunk and 100 or nil}})
    voice_dump_status = "Requested dump. After it arrives, click 'Use last received voice dump'."
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Use last received voice dump") then
    if last_rx_sysex and type(last_rx_sysex)=="table" and #last_rx_sysex>0 then
      local res, err = VoiceDump.decode_voice_from_sysex(last_rx_sysex)
      if not res then
        voice_dump_status = "Decode failed: " .. tostring(err)
      else
        voice_dump_template = res.template
                      current_voice_block = res.voice_bytes
                      voice_name = (res.meta and res.meta.name) or voice_name
                      voice_user_code = (res.meta and res.meta.user_code) or voice_user_code
                      voice_breath = (res.meta and res.meta.breath) or voice_breath
        voice_dump_payload = res.payload_bytes
        voice_dump_offset = res.voice_offset
        voice_dump_status = "Captured template. Payload bytes=" .. tostring(#res.payload_bytes)
      end
    else
      voice_dump_status = "No received SysEx captured yet."
    end
  end
  if r.ImGui_Button(ctx, "Apply CURRENT UI voice (TrueBulk)") then
    if not voice_dump_template or not voice_dump_payload or not voice_dump_offset then
      voice_dump_status = "No template yet. Capture a voice dump first."
    else
      local vbytes = encode_current_ui_voice_block()
      local new_payload = VoiceDump.replace_voice_bytes(voice_dump_payload, voice_dump_offset, vbytes)
      local msg, err = VoiceDump.build_voice_sysex_from_template(voice_dump_template, new_payload)
      if not msg then
        voice_dump_status = "Build failed: " .. tostring(err)
      else
        enqueue_sysex_many({{msg=msg, delay_ms = slow_chunk and 100 or nil}})
        last_sent_voice_bytes = vbytes
        voice_dump_status = "Queued TrueBulk voice write (single message)."
      end
    end
  end
  r.ImGui_Text(ctx, voice_dump_status or "")
end

Export Bank as .syx (template)") then
  if not bank_template or not bank_voice_bytes then
    bank_apply_status = "No bank template cached. Re-import a .syx first."
  else
    local payload = Bank.payload_from_voice_blocks(bank_name or "FB01BANK", bank_voice_bytes)
    local msg, err = Bank.build_sysex_from_template(bank_template, payload)
    if not msg then
      bank_apply_status = "Export build failed: " .. tostring(err)
    else
      local proj = r.GetProjectPath("")
      local fname = string.format("FB01_bank_export_%s.syx", os.date("%Y%m%d_%H%M%S"))
      local path = proj .. "/" .. fname
      local f = io.open(path, "wb")
      if f then
        for i=1,#msg do f:write(string.char(msg[i] & 0xFF)) end
        f:close()
        bank_apply_status = "Exported: " .. path
      else
        bank_apply_status = "Export failed: cannot open file"
      end
    end
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.ImGui_Separator(ctx)
  for i=1,math.min(#bank_names,48) do
    r.ImGui_Text(ctx, string.format("%02d: %s", i-1, bank_names[i]))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Patch/Tone names (heuristic):")
  for i=1,math.min(#last_names,48) do
    r.ImGui_Text(ctx, string.format("%02d: %s", i-1, last_names[i]))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.ImGui_Separator(ctx)

    for _,it in ipairs(P.config_params) do
      local v = cfg_vals[it.param] or it.default or 0
      local lo = it.ui_min or it.min or 0
              local hi = it.ui_max or it.max or 127
      if it.ui == "checkbox" then
        local b = (v ~= 0)
        local changed, nb = r.ImGui_Checkbox(ctx, it.name, b)
        if changed then
          cfg_vals[it.param] = nb and 1 or 0
          apply_cfg_param(it.param, cfg_vals[it.param])
        end
      else
        local changed, nv = r.ImGui_SliderInt(ctx, it.name, v, lo, hi)
        if changed then
          cfg_vals[it.param] = nv
          apply_cfg_param(it.param, nv)
        end
      end
    end
  else
    r.ImGui_Text(ctx, "No config params in schema.")
  end
  r.ImGui_EndTabItem(ctx)
end

      end
      if r.ImGui_BeginTabItem(ctx, "Library", true) then
        r.ImGui_Text(ctx, "Library + Project Recall")
        if r.ImGui_Button(ctx, "Open FB-01 Library Browser (v2)", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Library_Browser_v2.lua")
        end
        if r.ImGui_Button(ctx, "Project Recall: Save voice (.syx)", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Project_Save_Recall.lua")
        end
        if r.ImGui_Button(ctx, "Project Recall: Apply stored voice", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Project_Apply_Recall.lua")
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Fix/Normalize SysEx (offline)")
        if r.ImGui_Button(ctx, "Normalize DeviceID/SysExCh", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Normalize_DeviceID.lua")
        end
        if r.ImGui_Button(ctx, "Retarget Bank1<->Bank2", -1, 0) then
          dofile(root .. "/Tools/IFLS_FB01_Retarget_Bank1_Bank2.lua")
        end
        r.ImGui_EndTabItem(ctx)
      end
      if r.ImGui_BeginTabItem(ctx, "Schema (beta)") then
  local sch, err = ParamSchema.load()
  if not sch then
    r.ImGui_Text(ctx, err)
  else
    r.ImGui_Text(ctx, "Schema loaded: " .. tostring(sch.device or "FB-01"))
    r.ImGui_Separator(ctx)
    for _,grp in ipairs(sch.groups or {}) do
      if r.ImGui_CollapsingHeader(ctx, grp.label or grp.id) then
        r.ImGui_Text(ctx, "This tab is the foundation for full coverage. Extend schema to add params.")
      end
    end
  end
  r.ImGui_EndTabItem(ctx)
end
if r.ImGui_BeginTabItem(ctx, "Schema: Voice + OP EG") then
  schema_tab_active = true

  r.ImGui_SeparatorText(ctx, "Schema-driven send")
  local ch
  ch, autosend_schema_full_on_exit = r.ImGui_Checkbox(ctx, "Send full snapshot on tab exit (snapshot mode)", autosend_schema_full_on_exit)

  r.ImGui_SeparatorText(ctx, "AutoSend extras")
  ch, send_on_release_always_once = r.ImGui_Checkbox(ctx, "Per-change: send on release always once", send_on_release_always_once)
  ch, snapshot_preview_while_dragging = r.ImGui_Checkbox(ctx, "Snapshot: preview while dragging (rate-limited)", snapshot_preview_while_dragging)

  r.ImGui_SeparatorText(ctx, "Voice")
  for _,it in ipairs(P.voice_params) do
    schema_slider_voice(it)
  end

  r.ImGui_SeparatorText(ctx, "Operators: EG (4-column)")
  local function is_eg(it)
    local g = (it.group or ""):lower()
    if g == "eg" then return true end
    local n = (it.name or ""):lower()
    return n:find("attack") or n:find("decay") or n:find("sustain") or n:find("release")
  end

  -- build EG param list once
  local eg = {}
  for _,it in ipairs(P.operator_params) do
    if is_eg(it) then eg[#eg+1] = it end
  end

  if r.ImGui_BeginTable(ctx, "eg_table", 5, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
    r.ImGui_TableSetupColumn(ctx, "Param", r.ImGui_TableColumnFlags_WidthFixed(), 150)
    r.ImGui_TableSetupColumn(ctx, "OP1")
    r.ImGui_TableSetupColumn(ctx, "OP2")
    r.ImGui_TableSetupColumn(ctx, "OP3")
    r.ImGui_TableSetupColumn(ctx, "OP4")
    r.ImGui_TableHeadersRow(ctx)

    for _,it in ipairs(eg) do
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableSetColumnIndex(ctx, 0)
      r.ImGui_Text(ctx, it.name)

      for op_id=0,3 do
        r.ImGui_TableSetColumnIndex(ctx, op_id+1)
        local lo = it.ui_min or it.min or 0
              local hi = it.ui_max or it.max or 127
        local v  = clamp(op_vals[op_id+1][it.param] or 0, lo, hi)
        local label = string.format("##eg_op%d_%d", op_id+1, it.param)
        local changed, newv = r.ImGui_SliderInt(ctx, label, v, lo, hi)
        local deact = r.ImGui_IsItemDeactivatedAfterEdit(ctx)

        if changed then
          newv = clamp(newv, lo, hi)
          op_vals[op_id+1][it.param] = newv
          local msg = Syx.operator_param(sysch, inst, op_id, it.param, newv)
          if live_send_per_change then send_sysex(msg) end
          hook_autosave_autosend(msg, deact)
        elseif deact then
          local msg = Syx.operator_param(sysch, inst, op_id, it.param, v)
          hook_autosave_autosend(msg, true)
        end
      end
    end

    r.ImGui_EndTable(ctx)
  end

  r.ImGui_SeparatorText(ctx, "Operators: Level / Ratio / Scaling")
  local function in_group(it, want)
    return ((it.group or ""):upper() == want)
  end

  local groups = {{"LEVEL","LEVEL"}, {"FREQ","FREQ"}, {"SCALE","SCALE"}, {"MOD","MOD"}}
  for _,g in ipairs(groups) do
    local gid, glabel = g[1], g[2]
    if r.ImGui_CollapsingHeader(ctx, glabel) then
      for op_id=0,3 do
        r.ImGui_SeparatorText(ctx, string.format("OP%d", op_id+1))
        for _,it in ipairs(P.operator_params) do
          if in_group(it, gid) then
            schema_slider_op(op_id, it)
          end
        end
      end
    end
  end

  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "Voice FullSpec (64)") then
  r.ImGui_Text(ctx, "Auto-generated from Service Manual voice parameter list. Sends Voice Parameter Change (pp=0x40+param).")
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginChild(ctx, "fullspec_voice_scroller", -1, -1, 0) then
    for _,it in ipairs(P_FULL.voice_params_fullspec or {}) do
      fullspec_voice_slider(it)
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "Inst Config FullSpec") then
  r.ImGui_Text(ctx, "Instrument configuration parameters (pp=0x00..0x17).")
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginChild(ctx, "conf_fullspec_scroller", -1, -1, 0) then
    for _,it in ipairs(P_CONF.conf_params_fullspec or {}) do
      local pp = tonumber(it.pp) or 0
      local label = it.label or ("Conf "..tostring(pp))
      -- conf_vals is optional; fall back to local cache
      conf_vals = conf_vals or {}
      local cur = conf_vals[pp] or 0
      local changed, nv = r.ImGui_SliderInt(ctx, label .. "##conf_"..tostring(pp), cur, 0, 127)
      if changed then
        conf_vals[pp] = nv
        apply_conf_param(pp, nv)
      end
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "System Params (Raw)") then
  r.ImGui_Text(ctx, "Raw System Parameter Change: F0 43 75 0s 10 pp dd F7")
  r.ImGui_Separator(ctx)
  local ch
  ch, sys_pp = r.ImGui_SliderInt(ctx, "System Param (pp)", sys_pp, 0, 127)
  ch, sys_dd = r.ImGui_SliderInt(ctx, "Value (dd)", sys_dd, 0, 127)
  if r.ImGui_Button(ctx, "Send System Param") then
    local msg = Syx.sys_param(sys_ch, sys_pp, sys_dd)
    if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
  end
  r.ImGui_EndTabItem(ctx)
end

if r.ImGui_BeginTabItem(ctx, "Event List") then
  r.ImGui_Text(ctx, "FB-01 SysEx Event List builder (F0 43 75 70 ... F7).")
  r.ImGui_Text(ctx, "Builds a single SysEx message to avoid MIDI flood. 'sys_ch' is encoded in each event nibble.")
  r.ImGui_Separator(ctx)

  if r.ImGui_Button(ctx, "Add: NoteOff+Frac") then
    event_items[#event_items+1] = {t="note_off_frac", key=ev_key, frac=ev_frac}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: NoteOn/Off+Frac") then
    event_items[#event_items+1] = {t="note_onoff_frac", key=ev_key, frac=ev_frac, vel=ev_vel}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: Note+Dur") then
    event_items[#event_items+1] = {t="note_dur", key=ev_key, frac=ev_frac, vel=ev_vel, yy=ev_yy, xx=ev_xx}
  end

  if r.ImGui_Button(ctx, "Add: CC") then
    event_items[#event_items+1] = {t="cc", cc=ev_cc, val=ev_ccval}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: Program") then
    event_items[#event_items+1] = {t="program", prog=ev_prog}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: AfterTouch") then
    event_items[#event_items+1] = {t="aftertouch", val=ev_at}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: PitchBend") then
    event_items[#event_items+1] = {t="pitchbend", py=ev_py, px=ev_px}
  end

  if r.ImGui_Button(ctx, "Add: InstParam (1B)") then
    event_items[#event_items+1] = {t="inst_param_1", pa=ev_pa, dd=ev_dd}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add: InstParam (2B)") then
    event_items[#event_items+1] = {t="inst_param_2", pa=ev_pa, y=ev_y, x=ev_x}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear List") then
    event_items = {}
  end

  r.ImGui_Separator(ctx)

  r.ImGui_Text(ctx, "Defaults / inputs:")
  local _c
  _c, ev_key = r.ImGui_SliderInt(ctx, "Key", ev_key, 0, 127)
  _c, ev_frac = r.ImGui_SliderInt(ctx, "Frac (cents 0..100)", ev_frac, 0, 100)
  _c, ev_vel  = r.ImGui_SliderInt(ctx, "Vel", ev_vel, 0, 127)
  _c, ev_yy   = r.ImGui_SliderInt(ctx, "Dur YY", ev_yy, 0, 127)
  _c, ev_xx   = r.ImGui_SliderInt(ctx, "Dur XX", ev_xx, 0, 127)
  _c, ev_cc   = r.ImGui_SliderInt(ctx, "CC#", ev_cc, 0, 127)
  _c, ev_ccval= r.ImGui_SliderInt(ctx, "CC Val", ev_ccval, 0, 127)
  _c, ev_prog = r.ImGui_SliderInt(ctx, "Program", ev_prog, 0, 127)
  _c, ev_at   = r.ImGui_SliderInt(ctx, "AfterTouch", ev_at, 0, 127)
  _c, ev_py   = r.ImGui_SliderInt(ctx, "PB Y", ev_py, 0, 127)
  _c, ev_px   = r.ImGui_SliderInt(ctx, "PB X", ev_px, 0, 127)
  _c, ev_pa   = r.ImGui_SliderInt(ctx, "Inst Param#", ev_pa, 0, 127)
  _c, ev_dd   = r.ImGui_SliderInt(ctx, "Inst Param DD", ev_dd, 0, 127)
  _c, ev_y    = r.ImGui_SliderInt(ctx, "Inst Param Y (0..15)", ev_y, 0, 15)
  _c, ev_x    = r.ImGui_SliderInt(ctx, "Inst Param X (0..15)", ev_x, 0, 15)

  r.ImGui_Separator(ctx)

  if r.ImGui_BeginTable(ctx, "ev_tbl", 4, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingFixedFit()) then
    r.ImGui_TableSetupColumn(ctx, "#")
    r.ImGui_TableSetupColumn(ctx, "Type")
    r.ImGui_TableSetupColumn(ctx, "Data")
    r.ImGui_TableSetupColumn(ctx, "Del")
    r.ImGui_TableHeadersRow(ctx)
    for i=1,#event_items do
      local ev = event_items[i]
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_Text(ctx, tostring(i))
      r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_Text(ctx, ev.t or "")
      r.ImGui_TableSetColumnIndex(ctx, 2)
      r.ImGui_Text(ctx, table.concat((function()
        local parts={}
        for k,v in pairs(ev) do if k~="t" then parts[#parts+1]=k.."="..tostring(v) end end
        return parts
      end)(), " "))
      r.ImGui_TableSetColumnIndex(ctx, 3)
      if r.ImGui_Button(ctx, "X##evdel"..tostring(i)) then
        table.remove(event_items, i)
        break
      end
    end
    r.ImGui_EndTable(ctx)
  end

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Send Event List SysEx") then
    local msg = build_event_list_sysex(sys_ch)
    if AUTOCAL and AUTOCAL.sysex_use_send_to_hw and AUTOCAL.midi_out_idx ~= nil and r.APIExists and r.APIExists("SendMIDIMessageToHardware") and r.SendMIDIMessageToHardware then
    -- msg is a raw sysex string built by VoiceDump
    r.SendMIDIMessageToHardware(tonumber(AUTOCAL.midi_out_idx), msg)
  else
    enqueue_sysex(msg)
  end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Show Hex") then
    local msg = build_event_list_sysex(sys_ch)
    last_hex_preview = bin_to_hex(msg)
  end
  if last_hex_preview then
    r.ImGui_TextWrapped(ctx, last_hex_preview)
  end

  r.ImGui_EndTabItem(ctx)
end

r.ImGui_EndTabBar(ctx)
    
      -- schema tab exit snapshot send
      if autosend and autosend_mode==0 and autosend_schema_full_on_exit and schema_tab_was_active and (not schema_tab_active) then
        autosend_deb:request()
      end
end

    autosave_deb:update(); autosend_deb:update();
    
r.ImGui_Separator(ctx)
if r.ImGui_CollapsingHeader(ctx, "Debug: Snapshot/Hash", r.ImGui_TreeNodeFlags_DefaultOpen()) then
  local msgs = build_param_stream_msgs()
  local blob = table.concat(msgs or {}, "")
  local cur_hash = SlotCore.hash_bytes(blob)
  r.ImGui_Text(ctx, "Snapshot hash: " .. SlotCore.hex_hash(cur_hash))

  local bs, bn = SlotCore.get_bound_slot()
  if bs == "fb01" and bn and bn >= 1 then
    local state = SlotCore.load_slots("fb01", 8)
    local slots = (state and state.slots) or nil
    local slot = slots and slots[bn] or nil
    if slot and slot.msgs then
      local slot_blob = table.concat(slot.msgs or {}, "")
      local slot_hash = SlotCore.hash_bytes(slot_blob)
      local saved_hash = slot.saved_hash or slot_hash
      local dirty = (slot_hash ~= saved_hash)
      r.ImGui_Text(ctx, ("Bound slot %d: slot_hash=%s saved_hash=%s dirty=%s"):format(
        bn, SlotCore.hex_hash(slot_hash), SlotCore.hex_hash(saved_hash), tostring(dirty)
      ))
      r.ImGui_Text(ctx, "Reason: " .. (dirty and "hash differs from saved/export baseline" or "matches baseline"))
    else
      r.ImGui_Text(ctx, ("Bound slot %d: (empty)"):format(bn))
    end
  else
    r.ImGui_Text(ctx, "Bound slot: (none)  (open Librarian and select a slot)")
  end

  if r.ImGui_Button(ctx, "Copy snapshot hex", 180, 0) then
    r.ImGui_SetClipboardText(ctx, SlotCore.hexdump_bytes(blob, 16))
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end
r.ImGui_End(ctx)
  end

  if open then
    r.defer(loop)
  else
    r.ImGui_DestroyContext(ctx)
      elseif VERIFY.kind == "bank" then
        -- Compare decoded bank voices (48x64) to tolerate container/header variations.
        local decoded, err = decode_bank_any(bytes)
        if decoded and decoded.voices and VERIFY.target_decoded and VERIFY.target_decoded.voices then
          local diffs = 0
          for i=1,48 do
            local a = (VERIFY.target_decoded.voices[i] and VERIFY.target_decoded.voices[i].voice64) or nil
            local b = (decoded.voices[i] and decoded.voices[i].voice64) or nil
            if a and b then
              for k=1,64 do if (a[k] or 0) ~= (b[k] or 0) then diffs = diffs + 1 end end
            else
              diffs = diffs + 64
            end
          end
          VERIFY.pending = false
          VERIFY.result = { ok = (diffs == 0), diffs = diffs, backend = m.backend }
        end

  end
end

r.defer(loop)
local function _cleanup_mode_for_kind(kind)
  local k = tostring(kind or "")
  if k == "instvoice" and CAPTURE_CFG.cleanup_mode_instvoice ~= nil then return CAPTURE_CFG.cleanup_mode_instvoice end
  if k == "config"    and CAPTURE_CFG.cleanup_mode_config    ~= nil then return CAPTURE_CFG.cleanup_mode_config end
  if k == "bank"      and CAPTURE_CFG.cleanup_mode_bank      ~= nil then return CAPTURE_CFG.cleanup_mode_bank end
  return CAPTURE_CFG.cleanup_mode or 0
end

-- Phase 8: mapping preset storage
local function _get_preset_dir()
  local proj = r.GetProjectPath("") or ""
  if proj ~= "" then
    return proj .. "/IFLS_FB01_Presets"
  end
  return (root or r.GetResourcePath()) .. "/IFLS_FB01_Presets"
end

local function _ensure_dir(path)
  r.RecursiveCreateDirectory(path, 0)
end

local function _write_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false, "cannot open file for write" end
  f:write(data)
  f:close()
  return true
end

local function _read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function _save_mapping_preset(name, preset_tbl)
  local dir = _get_preset_dir()
  _ensure_dir(dir)
  local path = dir .. "/" .. name .. ".json"
  local ok, err = _write_file(path, _json_encode(preset_tbl))
  return ok, err, path
end

local function _load_mapping_preset(name)
  local dir = _get_preset_dir()
  local path = dir .. "/" .. name .. ".json"
  local d = _read_file(path)
  if not d then return nil, "preset not found", path end
  local t = _json_decode_min(d)
  if type(t) ~= "table" then return nil, "invalid json", path end
  return t, nil, path
end

-- Phase 9: rewritten capture tick (multipart bulk aware, service-manual spacing)
local function capture_tick_v2()
  -- process mapping send queue when no capture is active
  if bank_send_queue and not CAPTURE.active and bank_send_queue.list and bank_send_queue.idx and bank_send_queue.idx <= #bank_send_queue.list then
    local v64 = bank_send_queue.list[bank_send_queue.idx]
    local _sys = bank_send_queue.sys
    local _inst = bank_send_queue.inst
    local function _send_one()
      local msg_tbl = VoiceDump.build_inst_voice_sysex(_sys, _inst, v64)
      -- InstVoice is small: use normal delay
      send_sysex_throttled(string.char(table.unpack(msg_tbl)), CAPTURE_CFG.sysex_delay_ms or 10)
      if bank_send_verify then
        CAPTURE.retries_left = CAPTURE_CFG.retry_count_instvoice or 1
        verify_start("instvoice", v64, { sys_ch=_sys, inst_no=_inst, timeout=CAPTURE_CFG.t_instvoice })
        enqueue_sysex(Syx.dump_inst_voice(_sys, _inst))
      end
    end

    if bank_send_verify then
      capture_start("instvoice", _send_one, { timeout = CAPTURE_CFG.t_instvoice, retries = CAPTURE_CFG.retry_count_instvoice })
    else
      _send_one()
    end

    bank_send_queue.idx = bank_send_queue.idx + 1
    bank_send_queue.inst = (_inst + 1) % 8
    if bank_send_queue.idx > #bank_send_queue.list then
      bank_send_queue = nil
    end
  end

  if not CAPTURE.active then return end

  -- timeout
  if _now() > (CAPTURE.deadline or 0) then
    CAPTURE.err = "capture timeout"
    _capture_stop_recording()
    CAPTURE.active = false
    CAPTURE.new_items = _capture_collect_new_items(CAPTURE.track)
    _capture_restore_arms()
    return
  end

  -- collect all FB01 SysEx from newly created items
  local new_items = _capture_collect_new_items(CAPTURE.track)
  local msgs = _collect_sysex_from_items(new_items)
  if msgs and #msgs > 0 then
    CAPTURE.captured_sysex_msgs = msgs
    CAPTURE.captured_sysex_assembled = _assemble_bulk_msgs(msgs)
    CAPTURE.last_backend = "TAKE"
    CAPTURE.last_rx_ts = _now()
  end

  -- completion criteria per kind
  local complete = false
  if CAPTURE.kind == "instvoice" then
    complete = (CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1)
  elseif CAPTURE.kind == "config" then
    if CAPTURE.captured_sysex_assembled and ConfigDump and ConfigDump.decode_config_from_sysex then
      local ok = pcall(function()
        local buf = string.char(table.unpack(CAPTURE.captured_sysex_assembled))
        local bytes = {}
        for i=1,#buf do bytes[i]=buf:byte(i) end
        local _ = ConfigDump.decode_config_from_sysex(bytes)
      end)
      complete = ok
    else
      -- no ConfigDump: accept first dump
      complete = (CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1)
    end
  elseif CAPTURE.kind == "bank" then
    if CAPTURE.captured_sysex_assembled then
      local decoded = nil
      if decode_bank_any then
        decoded = select(1, decode_bank_any(CAPTURE.captured_sysex_assembled))
      end
      complete = (decoded and decoded.voices and #decoded.voices == 48) and true or false
      if complete then
        last_rx_voicebank = decoded
        last_rx_voicebank_raw = CAPTURE.captured_sysex_assembled
      end
    end
    -- fallback: stop after seeing at least one msg (some variants are single msg)
    if not complete and CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1 and (_now() - (CAPTURE.first_seen_ts or _now()) > 0.4) then
      complete = true
    end
    if CAPTURE.captured_sysex_msgs and not CAPTURE.first_seen_ts then CAPTURE.first_seen_ts = _now() end
  else
    complete = (CAPTURE.captured_sysex_msgs and #CAPTURE.captured_sysex_msgs >= 1)
  end

  if complete then
    _capture_stop_recording()
    CAPTURE.active = false
    CAPTURE.new_items = new_items
    _capture_restore_arms()
    -- refresh RX state
    if Rx and Rx.poll_take_backend then Rx.poll_take_backend() end
  end
end
local function _native_bulk_supported(kind)
  -- "instvoice" is safe because we already have a proven builder (VoiceDump.build_inst_voice_sysex).
  -- Bank/Config bulk builders require exact manual framing (byte count fields etc.) and are not enabled by default.
  return kind == "instvoice"
end
