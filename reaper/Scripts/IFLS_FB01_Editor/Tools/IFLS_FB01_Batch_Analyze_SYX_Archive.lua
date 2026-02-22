-- @description IFLS FB-01 - Batch analyze SYX archive (zip/folder)
-- @version 0.97.0
-- @author IFLS
-- @about
--   Choose a .zip file containing .syx files OR a folder.
--   Writes CSV + Markdown report into Scripts/IFLS_Workbench/Docs/Reports/

local r = reaper

local function split_sysex(data)
  local msgs = {}
  local i=1
  while true do
    local s = data:find(string.char(0xF0), i, true)
    if not s then break end
    local e = data:find(string.char(0xF7), s+1, true)
    if not e then break end
    msgs[#msgs+1] = data:sub(s, e)
    i = e + 1
  end
  return msgs
end

local function classify(msg)
  if #msg < 6 then return "unknown", nil end
  local b1,b2,b3,b4,b5 = msg:byte(1,5)
  if b1 ~= 0xF0 then return "unknown", nil end
  if b2==0x43 and b3==0x75 then
    local cmd = b5
    if #msg >= 6300 then
      local bankId = msg:byte(7)
      return "bank_dump", bankId
    end
    if cmd >= 0x18 and cmd <= 0x1F then return "param_change", nil end
    if cmd == 0x20 then return "dump_request", nil end
    return "fb01_sysex", nil
  end
  return "other_sysex", nil
end

local function read_all(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local d=f:read("*all"); f:close(); return d
end

local function list_syx_in_dir(dir)
  local out={}
  local cmd
  if r.GetOS():match("Win") then
    cmd = 'dir /s /b "'..dir..'\\*.syx" 2>nul'
  else
    cmd = 'find "'..dir..'" -type f \\( -iname "*.syx" -o -iname "*.SYX" \\ ) 2>/dev/null'
  end
  local p=io.popen(cmd)
  if not p then return out end
  local s=p:read("*all") or ""; p:close()
  for line in s:gmatch("[^\r\n]+") do out[#out+1]=line end
  return out
end

local function ensure_dir(path)
  if r.GetOS():match("Win") then
    os.execute('mkdir "'..path..'" 2>nul')
  else
    os.execute('mkdir -p "'..path..'"')
  end
end

local res = r.GetResourcePath()
local reports = res.."/Scripts/IFLS FB-01 Editor/Docs/Reports"
ensure_dir(reports)

local ok, target = r.GetUserFileNameForRead("", "Select .zip (or any file inside folder) to analyze", "")
if not ok or not target or target=="" then return end

-- If user picks a .zip, extract to temp folder using OS tools (best-effort)
local temp = res.."/Scripts/IFLS FB-01 Editor/Docs/Reports/_tmp_syx_extract"
ensure_dir(temp)

local is_zip = target:lower():match("%.zip$")
if is_zip then
  -- try: powershell Expand-Archive, or unzip
  if r.GetOS():match("Win") then
    os.execute('powershell -NoProfile -Command "Try {Expand-Archive -Force \''..target..'\' \''..temp..'\' } Catch { }"')
  else
    os.execute('unzip -o "'..target..'" -d "'..temp..'" >/dev/null 2>&1')
  end
  target = temp
else
  -- treat as folder
  local dir = target:match("^(.*)[/\\][^/\\]+$")
  if dir then target = dir end
end

local files = list_syx_in_dir(target)
if #files==0 then
  r.MB("No .syx files found in:\n"..target, "Batch SYX Analyze", 0)
  return
end

local ts = os.date("!%Y%m%d_%H%M%S")
local csv_path = reports.."/FB01_SYX_Report_"..ts..".csv"
local md_path  = reports.."/FB01_SYX_Report_"..ts..".md"

-- write CSV
local fcsv = io.open(csv_path, "wb")
fcsv:write("file,bytes,sysex_messages,type,bankId\n")

local counts={}
local rows={}
for _,p in ipairs(files) do
  local d = read_all(p)
  if d then
    local msgs = split_sysex(d)
    local typ="unknown"; local bid=""
    if #msgs==1 then
      local t,b = classify(msgs[1]); typ=t; if b~=nil then bid=tostring(b) end
    elseif #msgs>1 then
      typ="param_stream"
    end
    counts[typ] = (counts[typ] or 0) + 1
    rows[#rows+1] = {p, #d, #msgs, typ, bid}
    fcsv:write(string.format("%q,%d,%d,%q,%q\n", p, #d, #msgs, typ, bid))
  end
end
fcsv:close()

-- write Markdown summary
local fmd=io.open(md_path, "wb")
fmd:write("# FB-01 SYX Batch Report\n\n")
fmd:write("Generated (UTC): "..os.date("!%Y-%m-%dT%H:%M:%SZ").."\n\n")
fmd:write("Files: "..tostring(#rows).."\n\n")
fmd:write("## Type counts\n")
for k,v in pairs(counts) do fmd:write(string.format("- %s: %d\n", k, v)) end
fmd:write("\n## Sample (first 20)\n\n")
fmd:write("| file | bytes | msgs | type | bankId |\n|---|---:|---:|---|---|\n")
for i=1, math.min(#rows, 20) do
  local r0=rows[i]
  fmd:write(string.format("| %s | %d | %d | %s | %s |\n", r0[1]:gsub("|","\\\\|"), r0[2], r0[3], r0[4], r0[5]))
end
fmd:close()

r.MB("Report written:\n"..csv_path.."\n"..md_path, "Batch SYX Analyze", 0)