-- @description IFLS FB-01 Config Dump helper (Phase 26)
-- Goals:
-- 1) Layout-detection: tolerate variations in container/header/cmd bytes
-- 2) Payload slicing: extract the actual config data region robustly
-- 3) Mapping: decode/encode the common per-instrument config params (8 instruments x 24 bytes)
-- 4) Human readable diffs for Verify

local M = {}

-- Per-instrument configuration parameter layout (24 bytes, indices 0..23).
-- Derived from the editor's CONF_PARAMS list (param numbers pp 0x00..0x17).
local PARAMS = {
  [0]  = { key="notes",      name="Number of notes" },
  [1]  = { key="midi_ch",    name="MIDI channel" },
  [2]  = { key="key_hi",     name="Key limit high" },
  [3]  = { key="key_lo",     name="Key limit low" },
  [4]  = { key="voice_bank", name="Voice bank" },
  [5]  = { key="voice_no",   name="Voice number" },
  [6]  = { key="detune",     name="Detune" },
  [7]  = { key="octave2",    name="Octave +2" },
  [8]  = { key="out_level",  name="Output level" },
  [9]  = { key="pan",        name="Pan" },
  [10] = { key="lfo_enable", name="LFO enable" },
  [11] = { key="porta_time", name="Portamento time" },
  [12] = { key="pb_range",   name="Pitch bend range" },
  [13] = { key="mono_poly",  name="Mono/Poly" },
  [14] = { key="pmd_ctrl",   name="PMD controller" },
  [15] = { key="_unused15",  name="(unused 15)" },
  [16] = { key="lfo_speed",  name="LFO speed" },
  [17] = { key="amd",        name="AMD" },
  [18] = { key="pmd",        name="PMD" },
  [19] = { key="lfo_wave",   name="LFO waveform" },
  [20] = { key="lfo_load",   name="LFO load enable" },
  [21] = { key="lfo_sync",   name="LFO sync" },
  [22] = { key="ams",        name="AMS" },
  [23] = { key="pms",        name="PMS" },

local CANON = {
  midi_ch="cfg_midi_channel",
  key_hi="cfg_key_high",
  key_lo="cfg_key_low",
  voice_bank="cfg_bank_no",
  voice_no="cfg_voice_no",
  detune="cfg_detune",
  octave2="cfg_octave",
  out_level="cfg_level",
  pan="cfg_pan",
  porta_time="cfg_porta_time",
  pb_range="cfg_pb_range",
  mono_poly="cfg_mono_poly",
  lfo_speed="cfg_lfo_speed",
  amd="cfg_amd",
  pmd="cfg_pmd",
  lfo_wave="cfg_lfo_wave",
  lfo_load="cfg_lfo_load",
  lfo_sync="cfg_lfo_sync",
  ams="cfg_ams",
  pms="cfg_pms",
}
}

local function sum7(bytes, a, b)
  local s = 0
  for i=a,b do s = (s + (bytes[i] or 0)) end
  return s
end

local function checksum_yamaha(bytes, a, b)
  -- Yamaha bulk checksum: (-sum(data)) & 0x7F
  local s = sum7(bytes, a, b)
  return ((-s) & 0x7F)
end

local function _find_f0_f7(bytes)
  local s=nil
  for i=1,#bytes do if bytes[i]==0xF0 then s=i; break end end
  if not s then return nil end
  local e=nil
  for i=s+1,#bytes do if bytes[i]==0xF7 then e=i; break end end
  if not e then return nil end
  return s,e
end

local function _payload_slice(bytes, s, e)
  -- Returns payload_start, payload_end, stored_checksum_idx, cmd_header_len
  -- Strategy:
  -- - Expect Yamaha header: F0 43 75 0s
  -- - Many replies include command bytes (e.g. 0x20 sub cfgno) before actual data.
  -- - Use length heuristics: config data block is 8*24 = 192 bytes. We locate that at the tail before checksum.
  local header_end = s + 3 -- 0s at s+3
  local checksum_idx = e - 1
  local data_end = checksum_idx - 1
  if data_end <= header_end then
    return header_end+1, data_end, checksum_idx, 0
  end

  -- candidate region between header_end+1 and data_end
  local region_start = header_end + 1
  local region_len = (data_end - region_start + 1)

  -- detect command prefix "0x20 ?? ??"
  local cmd_len = 0
  if region_len >= 3 and bytes[region_start] == 0x20 then
    cmd_len = 3
  end

  -- try to locate the 192-byte instrument config block near the end
  local want = 192
  if region_len >= want then
    local payload_start = data_end - want + 1
    -- if there is a cmd prefix and block overlaps it, prefer skip cmd
    if cmd_len > 0 and payload_start < (region_start + cmd_len) then
      payload_start = region_start + cmd_len
    end
    return payload_start, data_end, checksum_idx, cmd_len
  end

  -- fallback: take entire region (minus cmd prefix if present)
  local payload_start = region_start + cmd_len
  return payload_start, data_end, checksum_idx, cmd_len
end

function M.decode_config_from_sysex(bytes)
  if type(bytes) ~= "table" then return nil, "bytes not table" end
  local s,e = _find_f0_f7(bytes)
  if not s then return nil, "no sysex frame" end

  -- Yamaha FB-01 header check
  if bytes[s+1] ~= 0x43 or bytes[s+2] ~= 0x75 then return nil, "not yamaha fb01" end
  local sys = bytes[s+3] & 0x0F

  local payload_start, payload_end, checksum_idx, cmd_len = _payload_slice(bytes, s, e)
  local payload = {}
  for i=payload_start,payload_end do payload[#payload+1] = bytes[i] & 0x7F end

  local stored_cs = (bytes[checksum_idx] or 0) & 0x7F
  local calc_cs = checksum_yamaha(bytes, payload_start, payload_end)

  -- decode instruments if payload length matches 192
  local decoded = nil
  if #payload >= 192 then
    decoded = M.decode_payload_to_params(payload)
  end

  return {
    sys_ch = sys,
    raw_start = s, raw_end = e,
    payload_start = payload_start, payload_end = payload_end,
    payload_bytes = payload,
    checksum_ok = (stored_cs == calc_cs),
    checksum = stored_cs, checksum_calc = calc_cs,
    cmd_len = cmd_len,
    decoded = decoded,
  }
end

function M.decode_payload_to_params(payload)
  if type(payload) ~= "table" then return nil end
  if #payload < 192 then return nil end
  -- use last 192 bytes if extra
  local base = #payload - 192
  local instruments = {}
  for inst=0,7 do
    local t = {}
    local off = base + (inst * 24)
    for pi=0,23 do
      local v = payload[off + pi + 1] or 0
      local p = PARAMS[pi]
      if p and p.key and p.key:sub(1,1) ~= "_" then
        t[p.key] = v
        local ck = CANON[p.key]
        if ck then t[ck] = v end
      end
    end
    instruments[inst] = t
  end
  return { instruments = instruments }
end

function M.encode_params_to_payload(decoded, payload_template)
  -- Build a 192-byte payload from decoded.instruments; if payload_template provided, copy tail/extra.
  local out = {}
  -- start from template
  if type(payload_template) == "table" then
    for i=1,#payload_template do out[i] = payload_template[i] & 0x7F end
  end
  -- ensure at least 192 bytes
  if #out < 192 then
    for i=#out+1,192 do out[i]=0 end
  end
  local base = #out - 192
  for inst=0,7 do
    local t = decoded and decoded.instruments and decoded.instruments[inst] or nil
    if t then
      local off = base + inst*24
      for pi=0,23 do
        local p = PARAMS[pi]
        if p and p.key and p.key:sub(1,1) ~= "_" then
          local ck = CANON[p.key]
        local v = (ck and t[ck] ~= nil) and t[ck] or t[p.key]
          if v ~= nil then out[off+pi+1] = (tonumber(v) or 0) & 0x7F end
        end
      end
    end
  end
  return out
end

function M.diff_bytes(a, b, limit)
  local diffs = {}
  if not a or not b then return {{idx=-1,a="nil",b="nil"}} end
  local n = math.max(#a, #b)
  local lim = limit or 64
  for i=1,n do
    local av = a[i]
    local bv = b[i]
    if av ~= bv then
      diffs[#diffs+1] = { idx=i, a=av, b=bv }
      if #diffs >= lim then break end
    end
  end
  return diffs
end

function M.diff_params(payload_a, payload_b)
  local da = M.decode_payload_to_params(payload_a)
  local db = M.decode_payload_to_params(payload_b)
  if not da or not db then return nil end
  local diffs = {}
  for inst=0,7 do
    local a = da.instruments[inst] or {}
    local b = db.instruments[inst] or {}
    for pi=0,23 do
      local p = PARAMS[pi]
      if p and p.key and p.key:sub(1,1) ~= "_" then
        local av = a[p.key]
        local bv = b[p.key]
        if av ~= bv then
          diffs[#diffs+1] = {
            path = ("config.inst%d.%s"):format(inst, p.key),
            name = p.name,
            a = av, b = bv
          }
        end
      end
    end
  end
  return diffs
end

function M.build_config_sysex(sys_ch, payload_bytes, cmd_prefix)
  -- Build a single FB-01 config dump-like message with checksum. cmd_prefix optional table e.g. {0x20,0x12,cfgno}.
  sys_ch = sys_ch or 0
  local msg = {0xF0, 0x43, 0x75, (sys_ch & 0x0F)}
  if type(cmd_prefix) == "table" then
    for i=1,#cmd_prefix do msg[#msg+1] = cmd_prefix[i] & 0x7F end
  end
  for i=1,#payload_bytes do msg[#msg+1] = payload_bytes[i] & 0x7F end
  local cs = checksum_yamaha(msg, 5, #msg) -- after header
  msg[#msg+1] = cs
  msg[#msg+1] = 0xF7
  return msg
end

return M
