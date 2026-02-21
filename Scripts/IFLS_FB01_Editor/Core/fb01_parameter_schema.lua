-- fb01_parameter_schema.lua
-- Parameter Authority Layer (repaired, syntax-safe)
-- Provides:
--   Schema.get(path) -> param def (min/max/enum_items/label/group)
--   Schema.diff_structured(a, b) -> list of {path, a, b, label, group}
--
-- This file was previously corrupted by duplicated blocks / early "return".
-- This version restores a minimal, correct API used by IFLS_FB01_SoundEditor.lua.

local Schema = {}

-- Backward-compatible aliases for older UI keys
Schema.ALIASES = {
  ["portamento"]    = "portamento_time",
  ["pb_range"]      = "pitchbend_range",
  ["controller"]    = "controller_set",
  ["amd"]           = "lfo_amd",
  ["pmd"]           = "lfo_pmd",
  ["pms"]           = "lfo_pms",
  ["lfo_waveform"]  = "lfo_wave",
  -- operator aliases (short -> long)
  ["ar"]  = "attack_rate",
  ["d1r"] = "decay1_rate",
  ["d2r"] = "decay2_rate",
  ["rr"]  = "release_rate",
  ["sl"]  = "sustain_level",
  ["level"] = "output_level",
}

local function _canon_key(k)
  if not k then return k end
  return Schema.ALIASES[k] or k
end

-- Enumerations
Schema.enums = {
  lfo_wave = { "Saw", "Square", "Triangle", "S&H" }, -- values 0..3
  pitch_mod_control = { "Off", "Aftertouch", "Pitch Wheel", "Breath", "Foot", "Control 5", "Control 6", "Control 7" }, -- 0..7
  mono_poly = { "Mono", "Poly" }, -- 0..1
}

-- Voice parameter definitions (subset used by UI + verify)
Schema.voice = {
  algorithm       = {label="Algorithm", type="int", min=0, max=7, group="voice.common"},
  feedback        = {label="Feedback", type="int", min=0, max=7, group="voice.common"},
  transpose       = {label="Transpose", type="int", min=0, max=127, group="voice.common"},
  portamento_time = {label="Portamento time", type="int", min=0, max=127, group="voice.common"},
  pitchbend_range = {label="Pitch bend range", type="int", min=0, max=15, group="voice.ctrl"},
  controller_set  = {label="Pitch mod control", type="enum", enum="pitch_mod_control", min=0, max=7, group="voice.ctrl"},
  lfo_speed       = {label="LFO speed", type="int", min=0, max=127, group="voice.lfo"},
  lfo_amd         = {label="AMD", type="int", min=0, max=127, group="voice.lfo"},
  lfo_pmd         = {label="PMD", type="int", min=0, max=127, group="voice.lfo"},
  lfo_wave        = {label="LFO wave", type="enum", enum="lfo_wave", min=0, max=3, group="voice.lfo"},
  lfo_load        = {label="LFO load", type="int", min=0, max=1, group="voice.lfo"},
  lfo_sync        = {label="LFO sync", type="int", min=0, max=1, group="voice.lfo"},
  ams             = {label="AMS", type="int", min=0, max=3, group="voice.lfo"},
  lfo_pms         = {label="PMS", type="int", min=0, max=7, group="voice.lfo"},
}

-- Operator definitions (keys used by editor: attack_rate/decay*/release/sustain, output_level, multiple, detune)
Schema.op = {
  output_level = {label="Output level", type="int", min=0, max=127, group="op.level"},
  multiple     = {label="Multiple", type="int", min=0, max=15, group="op.freq"},
  detune       = {label="Detune", type="int", min=0, max=15, group="op.freq"},
  fine         = {label="Fine", type="int", min=0, max=7, group="op.freq"},
  coarse       = {label="Coarse", type="int", min=0, max=3, group="op.freq"},
  adjust       = {label="Adjust", type="int", min=0, max=15, group="op.freq"},
  attack_rate  = {label="Attack rate", type="int", min=0, max=31, group="op.env"},
  decay1_rate  = {label="Decay 1 rate", type="int", min=0, max=31, group="op.env"},
  decay2_rate  = {label="Decay 2 rate", type="int", min=0, max=31, group="op.env"},
  release_rate = {label="Release rate", type="int", min=0, max=15, group="op.env"},
  sustain_level= {label="Sustain level", type="int", min=0, max=15, group="op.env"},
  am_sens      = {label="AM sens", type="int", min=0, max=3, group="op.mod"},
}

-- Config (instrument slot) parameters (subset)
Schema.config = {
  cfg_midi_channel = {label="MIDI channel", type="int", min=0, max=15, group="config"},
  cfg_key_low      = {label="Key low", type="int", min=0, max=127, group="config"},
  cfg_key_high     = {label="Key high", type="int", min=0, max=127, group="config"},
  cfg_bank_no      = {label="Bank", type="int", min=0, max=7, group="config"},
  cfg_voice_no     = {label="Voice no", type="int", min=0, max=127, group="config"},
  cfg_level        = {label="Level", type="int", min=0, max=127, group="config"},
  cfg_pan          = {label="Pan", type="int", min=0, max=127, group="config"},
  cfg_porta_time   = {label="Portamento time", type="int", min=0, max=127, group="config"},
  cfg_pb_range     = {label="Pitch bend range", type="int", min=0, max=12, group="config"},
  cfg_mono_poly    = {label="Mono/Poly", type="enum", enum="mono_poly", min=0, max=1, group="config"},
}

local function _attach_enum_items(def)
  if not def or def.enum_items then return def end
  if def.enum and Schema.enums[def.enum] then
    def.enum_items = Schema.enums[def.enum]
  end
  return def
end

-- Public lookup:
--   Schema.get("voice.lfo_speed"), Schema.get("op1.attack_rate"), Schema.get("config.cfg_midi_channel")
-- Also supports legacy Schema.get(tbl,key) calls if first arg is a table.
function Schema.get(a, b)
  -- legacy form
  if type(a) == "table" then
    local tbl, key = a, b
    key = _canon_key(key)
    return _attach_enum_items(tbl and tbl[key] or nil)
  end

  local path = a
  if type(path) ~= "string" then return nil end
  path = path:gsub("^%s+",""):gsub("%s+$","")
  if path == "" then return nil end

  -- Split "section.key"
  local section, key = path:match("^([%w_]+)%.(.+)$")
  if not section then
    -- no section: try voice/op/config by key
    key = _canon_key(path)
    return _attach_enum_items(Schema.voice[key] or Schema.op[key] or Schema.config[key])
  end

  -- Normalize operator sections: op, op1..op4
  if section:match("^op%d$") or section == "op" then
    key = _canon_key(key)
    return _attach_enum_items(Schema.op[key])
  elseif section == "voice" then
    key = _canon_key(key)
    return _attach_enum_items(Schema.voice[key])
  elseif section == "config" then
    key = _canon_key(key)
    return _attach_enum_items(Schema.config[key])
  end

  -- Unknown section: try global key
  key = _canon_key(key)
  return _attach_enum_items(Schema.voice[key] or Schema.op[key] or Schema.config[key])
end

-- Structured diff (used by Verify). Accepts either:
--   Schema.diff_structured(a, b)
-- where a/b are tables like { voice = {...}, op1={...}, op2={...} } OR plain voice tables
function Schema.diff_structured(a, b)
  local out = {}
  local function push(p, av, bv, def)
    out[#out+1] = { path=p, a=av, b=bv, label=(def and def.label) or p, group=(def and def.group) or nil }
  end
  local function diff_tbl(prefix, ta, tb, defs)
    for k,def in pairs(defs) do
      local av = ta and ta[k]
      local bv = tb and tb[k]
      if av ~= nil and bv ~= nil and av ~= bv then
        push(prefix..k, av, bv, def)
      end
    end
  end

  -- voice layer
  local va = (a and (a.voice or a)) or nil
  local vb = (b and (b.voice or b)) or nil
  diff_tbl("voice.", va, vb, Schema.voice)

  -- op layers (supports op1/op2/op3/op4 or ops array)
  for op=1,4 do
    local oa = (a and (a["op"..op] or (a.ops and a.ops[op]))) or nil
    local ob = (b and (b["op"..op] or (b.ops and b.ops[op]))) or nil
    if oa and ob then
      diff_tbl(("op%d."):format(op), oa, ob, Schema.op)
    end
  end

  table.sort(out, function(x,y) return tostring(x.path) < tostring(y.path) end)
  return out
end

return Schema
