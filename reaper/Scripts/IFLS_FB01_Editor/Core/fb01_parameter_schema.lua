-- fb01_parameter_schema.lua
-- Phase 11: Parameter Authority Layer (single source of truth)
-- Provides: parameter inventory, ranges, enums, safe-random rules, and helpers.
--
-- Designed to be consumed by IFLS_FB01_SoundEditor.lua and tools (randomizer, reports, presets).
--
-- Notes:
-- - Ranges are based on common FB-01 editor practice and cross-checked against reference editors (Edisyn, FB01 Sound Editor).
-- - Some parameters are device/firmware dependent; keep safe_random conservative.
--
-- Public API:
--   Schema.voice, Schema.op, Schema.config, Schema.enums
--   Schema.get(def_table, key) -> def or nil
--   Schema.safe_randomize_voice(voice_vals, op_vals, opts) -> new_voice_vals, new_op_vals, meta
--   Schema.diff_structured(a, b) -> list of {path, a, b, label, group}
--
local Schema = {}

-- Phase 21: Canonical keys match VoiceMap.decode_voice_block() output.
-- Aliases keep backward-compatibility with older UI keys.
Schema.ALIASES = {
  ["portamento"] = "portamento_time",
  ["pb_range"] = "pitchbend_range",
  ["controller"] = "controller_set",
  ["lfo_speed"] = "lfo_speed",
  ["amd"] = "lfo_amd",
  ["pmd"] = "lfo_pmd",
  ["pms"] = "lfo_pms",
  ["lfo_waveform"] = "lfo_wave",
}

local function _canon(path)
  if not path then return path end
  return Schema.ALIASES[path] or path
end


Schema.enums = {
  lfo_wave = {
    {0, "Saw"},
    {1, "Square"},
    {2, "Triangle"},
    {3, "S&H"},
  },
  pitch_mod_control = {
    {0, "Off"},
    {1, "Aftertouch"},
    {2, "Pitch Wheel"},
    {3, "Breath"},
    {4, "Foot"},
    -- 5..7 exist in some implementations; default to safe range 0..4 unless advanced.
    {5, "Control 5"},
    {6, "Control 6"},
    {7, "Control 7"},
  },
}

-- Voice-common parameter definitions
Schema.voice = {
  name      = {label="Name", type="string", safe_random=false, group="common"},
  algorithm = {label="Algorithm", type="int", min=0, max=7, safe_random=true, group="common"},
  feedback  = {label="Feedback",  type="int", min=0, max=7, safe_random=true, group="common", safe_max=4},
  transpose = {label="Transpose", type="int", min=0, max=127, safe_random=false, group="common"},
  portamento= {label="Portamento",type="int", min=0, max=127, safe_random=false, group="common"},
  pb_range  = {label="Pitch Bend Range", type="int", min=0, max=15, safe_random=false, group="common"},
  poly      = {label="Poly", type="bool", safe_random=false, group="common"},
  controller= {label="Pitch Mod Control", type="enum", enum="pitch_mod_control", min=0, max=7, safe_random=true, group="lfo", safe_max=4},

  lfo_speed = {label="LFO Speed", type="int", min=0, max=127, safe_random=true, group="lfo", safe_min=10, safe_max=100},
  lfo_wave  = {label="LFO Wave",  type="enum", enum="lfo_wave", min=0, max=3, safe_random=true, group="lfo"},
  lfo_sync  = {label="LFO Sync",  type="bool", safe_random=true, group="lfo"},
  lfo_load  = {label="LFO Load",  type="bool", safe_random=true, group="lfo"},
  amd       = {label="AMD", type="int", min=0, max=127, safe_random=true, group="lfo", safe_max=90},
  ams       = {label="AMS", type="int", min=0, max=3, safe_random=true, group="lfo"},
  pmd       = {label="PMD", type="int", min=0, max=127, safe_random=true, group="lfo", safe_max=90},
  pms       = {label="PMS", type="int", min=0, max=7, safe_random=true, group="lfo", safe_max=5},

  out_l     = {label="Out L", type="bool", safe_random=false, group="routing"},
  out_r     = {label="Out R", type="bool", safe_random=false, group="routing"},
  op_on     = {label="OP Enable", type="bitset4", safe_random=false, group="routing"},
}

-- Operator parameter definitions (OP1..OP4)
Schema.op = {
  level          = {label="Output Level", type="int", min=0, max=127, safe_random=true, group="level", safe_min=30, safe_max=110},
  multiple       = {label="Multiple", type="int", min=0, max=15, safe_random=true, group="freq", safe_max=8},
  detune         = {label="Detune", type="int", min=0, max=15, safe_random=true, group="freq", safe_max=10}, -- device uses nibble; treat 0..15
  fine           = {label="Fine", type="int", min=0, max=7, safe_random=true, group="freq"},
  coarse         = {label="Coarse", type="int", min=0, max=3, safe_random=true, group="freq"},
  adjust         = {label="Adjust", type="int", min=0, max=15, safe_random=true, group="freq"},

  ar             = {label="Attack Rate", type="int", min=0, max=31, safe_random=true, group="env", safe_max=28},
  d1r            = {label="Decay 1 Rate", type="int", min=0, max=31, safe_random=true, group="env", safe_max=28},
  d2r            = {label="Decay 2 Rate", type="int", min=0, max=31, safe_random=true, group="env", safe_max=28},
  rr             = {label="Release Rate", type="int", min=0, max=15, safe_random=true, group="env", safe_max=14},
  sl             = {label="Sustain Level", type="int", min=0, max=15, safe_random=true, group="env"},

  ams            = {label="AM Sens", type="int", min=0, max=3, safe_random=true, group="mod"},
  lvl_vel        = {label="Level Vel", type="int", min=0, max=7, safe_random=true, group="mod"},
  ar_vel         = {label="AR Vel", type="int", min=0, max=3, safe_random=true, group="mod"},
  key_depth      = {label="Key Depth", type="int", min=0, max=15, safe_random=true, group="scale"},
  key_curve      = {label="Key Curve", type="int", min=0, max=3, safe_random=true, group="scale"},
  rate_depth     = {label="Rate Depth", type="int", min=0, max=3, safe_random=true, group="scale"},
  mod_flag       = {label="Car/Mod", type="bool", safe_random=true, group="mod"},
}

-- Config / Multi (Instrument slot) definitions (conservative)
Schema.config = {
  midi_ch   = {label="MIDI Channel", type="int", min=0, max=15, safe_random=false, group="config"},
  notes     = {label="Notes (Poly)", type="int", min=1, max=16, safe_random=false, group="config"},
  key_lo    = {label="Key Low", type="int", min=0, max=127, safe_random=false, group="config"},
  key_hi    = {label="Key High", type="int", min=0, max=127, safe_random=false, group="config"},
  bank      = {label="Bank", type="int", min=0, max=7, safe_random=false, group="config"},
  voice_no  = {label="Voice No", type="int", min=0, max=127, safe_random=false, group="config"},
  octave    = {label="Octave", type="int", min=0, max=7, safe_random=false, group="config"},
  level     = {label="Level", type="int", min=0, max=127, safe_random=false, group="config"},
  pan       = {label="Pan", type="int", min=0, max=127, safe_random=false, group="config"},
  lfo_on    = {label="LFO Enable", type="bool", safe_random=false, group="config"},
}

local function _clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function _rand_int(lo, hi)
  -- inclusive
  return math.random(lo, hi)
end

function Schema.get(tbl, key)
  path = _canon(path)
  return tbl and tbl[key] or nil
end

local function _safe_bounds(def)
  local lo = def.safe_min or def.min
  local hi = def.safe_max or def.max
  return lo, hi
end

-- Create a stable list of diff entries between two structured tables.
-- 'a' and 'b' are tables like returned by VoiceMap.decode_voice_block or your own normalized structures.
function Schema.diff_structured(a, b)
  local out = {}
  local function walk(prefix, ta, tb, defs)
    for k,v in pairs(defs) do
      if v.type == "bitset4" then
        -- handled elsewhere
      else
        local pa = ta and ta[k]
        local pb = tb and tb[k]
        if pa ~= nil and pb ~= nil and pa ~= pb then
          out[#out+1] = {path=prefix..k, a=pa, b=pb, label=v.label, group=v.group}
        end
      end
    end
  end
  if a and b then
    walk("voice.", a.voice or a, b.voice or b, Schema.voice)
    for op=1,4 do
      local oa = (a["op"..op] or (a.ops and a.ops[op])) or nil
      local ob = (b["op"..op] or (b.ops and b.ops[op])) or nil
      if oa and ob then
        for k,v in pairs(Schema.op) do
          local pa = oa[k]; local pb = ob[k]
          if pa ~= nil and pb ~= nil and pa ~= pb then
            out[#out+1] = {path=("op%d.%s"):format(op,k), a=pa, b=pb, label=v.label, group=v.group}
          end
        end
      end
    end
  end
  table.sort(out, function(x,y) return x.path < y.path end)
  return out
end

-- Safe randomization for the currently loaded voice values.
-- voice_vals/op_vals are expected to be simple tables of numeric fields.
-- opts:
--   advanced_controller (bool): allow controller 0..7, else clamp to 0..4
--   keep_algo (bool)
--   seed (int)
function Schema.safe_randomize_voice(voice_vals, op_vals, opts)
  opts = opts or {}
  if opts.seed then math.randomseed(opts.seed) end

  local nv = {}
  for k,v in pairs(voice_vals or {}) do nv[k]=v end

  -- voice common
  for key,def in pairs(Schema.voice) do
    if def.safe_random and nv[key] ~= nil then
      if opts.keep_algo and key == "algorithm" then
        -- keep
      else
        local lo,hi = _safe_bounds(def)
        if def.enum == "pitch_mod_control" and not opts.advanced_controller then
          hi = math.min(hi, 4)
        end
        if def.type == "bool" then
          nv[key] = _rand_int(0,1)
        else
          nv[key] = _rand_int(lo, hi)
        end
      end
    end
  end

  -- operators
  local nop = {}
  for op=1,4 do
    local src = op_vals and op_vals[op] or nil
    nop[op] = {}
    if src then
      for k,v in pairs(src) do nop[op][k]=v end
      for key,def in pairs(Schema.op) do
        if def.safe_random and nop[op][key] ~= nil then
          local lo,hi = _safe_bounds(def)
          if def.type == "bool" then
            nop[op][key] = _rand_int(0,1)
          else
            nop[op][key] = _rand_int(lo, hi)
          end
        end
      end
      -- guardrails: keep at least one operator audible
      nop[op].level = _clamp(nop[op].level or 0, 0, 127)
    end
  end

  local meta = {seed=opts.seed, advanced_controller=opts.advanced_controller and true or false}
  return nv, nop, meta
end


-- Phase 12: style profiles (weights/constraints for randomize)
Schema.STYLE_PROFILES = {
  Bass = { focus = { "op.multiple", "op.output_level", "voice.feedback" }, algo_whitelist = {0,1,2,3}, feedback_max=5 },
  Pad  = { focus = { "voice.lfo_speed", "voice.lfo_amd", "op.release_rate", "op.sustain_level" }, algo_whitelist = {4,5,6,7}, feedback_max=3 },
  Bell = { focus = { "op.multiple", "op.detune", "op.attack_rate" }, algo_whitelist = {2,3,4,5}, feedback_max=4 },
  Perc = { focus = { "op.attack_rate", "op.decay1_rate", "op.decay2_rate" }, algo_whitelist = {0,1,2}, feedback_max=2 },
  FX   = { focus = { "voice.lfo_pmd", "voice.lfo_amd", "voice.controller" }, algo_whitelist = {0,1,2,3,4,5,6,7}, feedback_max=7, allow_ctrl_advanced=true },
}

function Schema.safe_randomize_voice_style(voice_vals, op_vals, style_name, opts)
  opts = opts or {}
  local prof = Schema.STYLE_PROFILES[style_name]
  if not prof then return Schema.safe_randomize_voice(voice_vals, op_vals, opts) end
  local o2 = {}
  for k,v in pairs(opts) do o2[k]=v end
  if prof.allow_ctrl_advanced then o2.allow_controller_advanced = true end
  local vv, oo = Schema.safe_randomize_voice(voice_vals, op_vals, o2)
  if prof.algo_whitelist and vv.algorithm ~= nil then
    local wl = prof.algo_whitelist
    vv.algorithm = wl[ (math.random(1,#wl)) ]
  end
  if prof.feedback_max and vv.feedback ~= nil then
    vv.feedback = math.min(vv.feedback, prof.feedback_max)
  end
  return vv, oo
end

-- FIX: Schema.get() + Schema.PARAMS builder (repair corrupted release)
function Schema.get(a, b)
  -- Backwards compatible: Schema.get(tbl, key) or Schema.get('voice.param')
  if type(a) == 'table' then
    local key = _canon(b)
    return a[key] or a[b]
  end
  local path = _canon(a)
  if not path then return nil end
  local head, rest = path:match('^([^.]+)%.(.+)$')
  if head == 'voice' then return Schema.voice and Schema.voice[_canon(rest)] or nil end
  if head == 'op' then return Schema.op and Schema.op[_canon(rest)] or nil end
  if head == 'config' then return Schema.config and Schema.config[_canon(rest)] or nil end
  -- fallback: try direct keys
  return (Schema.voice and Schema.voice[path]) or (Schema.op and Schema.op[path]) or (Schema.config and Schema.config[path])
end

Schema.PARAMS = Schema.PARAMS or {}
local function _add_params(prefix, t)
  if not t then return end
  for k,def in pairs(t) do
    if type(def) == 'table' then
      local key = _canon(k)
      local p = {}
      for kk,vv in pairs(def) do p[kk]=vv end
      p.key = prefix .. key
      Schema.PARAMS[p.key] = p
    end
  end
end
_add_params('', Schema.voice)
_add_params('', Schema.op)
_add_params('cfg_', Schema.config)

-- Ensure tooltip table exists (optional)
Schema.DESC = Schema.DESC or {}

-- Tooltips (kept from original)
Schema.DESC = Schema.DESC or {}
Schema.DESC["algorithm"] = "FM algorithm (operator routing)."
Schema.DESC["feedback"] = "Feedback amount (algorithm dependent)."
Schema.DESC["transpose"] = "Voice transpose."
Schema.DESC["cfg_midi_channel"] = "Instrument MIDI channel (performance)."
Schema.DESC["cfg_bank_no"] = "Voice bank number for instrument."
Schema.DESC["cfg_voice_no"] = "Voice number (1-48) for instrument."



-- Phase 30: more tooltips (expand over time)
Schema.DESC = Schema.DESC or {}
Schema.DESC["lfo_speed"] = "LFO speed (0-127)."
Schema.DESC["lfo_wave"] = "LFO waveform (Triangle/Saw/Square/S&H)."
Schema.DESC["lfo_amd"] = "Amplitude modulation depth."
Schema.DESC["lfo_pmd"] = "Pitch modulation depth."
Schema.DESC["lfo_pms"] = "Pitch modulation sensitivity."
Schema.DESC["portamento_time"] = "Portamento time."
Schema.DESC["pitchbend_range"] = "Pitch bend range in semitones."
Schema.DESC["volume"] = "Operator output level."
Schema.DESC["multiple"] = "Operator frequency multiple."
Schema.DESC["detune"] = "Operator detune."
Schema.DESC["attack_rate"] = "Operator attack rate."
Schema.DESC["decay1_rate"] = "Operator decay 1 rate."
Schema.DESC["decay2_rate"] = "Operator decay 2 rate."
Schema.DESC["release_rate"] = "Operator release rate."
Schema.DESC["sustain_level"] = "Operator sustain level."



return Schema

