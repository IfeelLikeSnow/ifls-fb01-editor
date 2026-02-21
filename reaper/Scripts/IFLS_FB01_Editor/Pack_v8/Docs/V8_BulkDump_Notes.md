# V8 Bulk Dump Tools – Notes

## Dump requests
SysexDB lists FB-01 dump request heads for voice banks and configs. citeturn1view0  
V8 uses the commonly cited short forms:
- Voice bank 00: `F0 43 75 00 20 00 00 F7`
- Voice bank 01: `F0 43 75 00 20 00 01 F7`
- All configs:   `F0 43 75 00 20 03 00 F7`

## Why bank dumps are large
Service manual summaries note voice data includes 48 voices, each 64 bytes. citeturn0search2  
So voice banks can be thousands of bytes, often split across multiple SysEx messages.

## Best practice
- Always **export to .syx** for archiving.
- ExtState storage is handy for smaller config dumps or quick recall but may hit size limits for full banks.
