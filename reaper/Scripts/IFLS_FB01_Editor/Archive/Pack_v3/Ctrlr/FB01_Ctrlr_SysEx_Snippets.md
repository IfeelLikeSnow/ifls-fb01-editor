# CTRLR: FB-01 SysEx snippets (V3)

CTRLR panels can use **Global Variables** inside SysEx strings (k0, k1, …) and set them from Lua:
- `panel:setGlobalVariable(n, value)`
- `panel:getGlobalVariable(n)`

Example discussion with `k0` usage: citeturn0search6

## Recommended globals
- k0 = System Channel-1 (0..15)
- k1 = Instrument (0..7)

## Config Change SysEx template (SysCh+Inst)
`F0 43 75 k0 zZ pP 0y 0x F7`

In CTRLR you can’t easily compute `zz=0x18+inst` purely in the template, so do it in Lua and build the sysex.

### Lua helper (paste into panel Lua)
```lua
function fb01_nibbles(v)
  local high = math.floor(v / 16)
  local low  = v - 16*high
  return low, high
end

function fb01_send_cfg(pp, value)
  local sys = panel:getGlobalVariable(0) -- 0..15
  local inst = panel:getGlobalVariable(1) -- 0..7
  local zz = 0x18 + inst
  local low, high = fb01_nibbles(value)
  local msg = string.format("F0 43 75 %02X %02X %02X 0%X 0%X F7", sys, zz, pp, low, high)
  panel:sendMidiMessageNow(CtrlrMidiMessage(msg))
end
```

## Transpose helper
Parameter `pp=0x4F` (transpose) and value is two's complement (e.g. -12 => 0xF4) with nibbles low/high reversed in message. citeturn2view1
