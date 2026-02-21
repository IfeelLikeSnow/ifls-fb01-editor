-- @description IFLS FB-01 Library Browser (v2)
-- @version 0.92.0
-- @author IFLS
-- @about
--   Unified browser for FB-01 patches across:
--    1) Workbench curated library (internal)
--    2) External IFLS_FB01_PatchLibrary repo (optional)
--
--   Requires: ReaImGui
--   Sending .syx requires: SWS (SNM_SendSysEx)
--
--   External library path:
--     Default: REAPER/ResourcePath/Scripts/IFLS_FB01_PatchLibrary
--     Override: ExtState IFLS_FB01 / LIBRARY_PATH

local r = reaper
if not r.ImGui_CreateContext then
  r.MB("ReaImGui not found. Install ReaImGui first.", "FB-01 Library Browser", 0)
  return
end
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing). Install SWS first.", "FB-01 Library Browser", 0)
  return
end

local wb_root = r.GetResourcePath() .. "/Scripts/IFLS FB-01 Editor"
local LibPath = dofile(wb_root .. "/Lib/ifls_fb01_library_path.lua")

local function file_exists(p)
  local f = io.open(p, "rb"); if f then f:close(); return true end


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

local function classify_sysex(msg)
  if #msg < 6 then return "unknown", nil end
  local b1,b2,b3,b4,b5 = msg:byte(1,5)
  if b1 ~= 0xF0 then return "unknown", nil end
  -- Yamaha FB-01 typically: F0 43 75 <sysch> <cmd> ...
  if b2==0x43 and b3==0x75 then
    local cmd = b5
    -- bulk dumps are usually single long messages (e.g. 6363 bytes bank)
    if #msg >= 6300 then
      -- bank id often at byte 7 in simple request/command forms, but dumps vary; we attempt heuristics:
      local bankId = msg:byte(7) -- best-effort
      return "bank_dump", bankId
    end
    if cmd >= 0x18 and cmd <= 0x1F then
      return "param_change", nil
    end
    if cmd == 0x20 then
      return "dump_request", nil
    end
    return "fb01_sysex", nil
  end
  return "other_sysex", nil
end

  return false
end

-- JSON parsing: prefer REAPER JSON_Parse if available, else minimal trusted loader.
local function json_decode_trusted(s)
  if r.JSON_Parse then
    local ok, res = pcall(r.JSON_Parse, s)
    if ok and res then return res end
  end
  -- Trusted repo files only: convert JSON to Lua table using load()
  local t = s
  t = t:gsub('"%s*:%s*', '"=')          -- "k": -> "k"=
  t = t:gsub("%[", "{"):gsub("%]", "}") -- arrays to tables (rough)
  t = t:gsub("null", "nil")
  t = "return " .. t
  local ok, res = pcall(load(t))
  if ok then return res end
  return nil
end

local function read_json(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*all"); f:close()
  return json_decode_trusted(s)
end

local function scan_manifest(manifest_path, root_prefix, source_name)
  local m = read_json(manifest_path)
  if not m then return {} end
  local items = {}
  local entries = m.entries or m.patches or m.items or {}
  for i, e in ipairs(entries) do
    local name = e.name or e.title or e.patch_name or ("Patch "..i)
    local rel  = e.path or e.file or e.relpath or e.filename
    local tags = e.tags or e.categories or {}
    if type(tags) == "string" then tags = {tags} end
    if rel and type(rel)=="string" then
      local full = root_prefix .. "/" .. rel
      items[#items+1] = {
        name=name,
        rel=rel,
        full=full,
        source=source_name,
        tags=tags,
        bank=e.bank, program=e.program, voice=e.voice,
        meta=e
      }
    end
  end
  return items
end

local function discover()
  local out = {}
  -- Internal curated manifest (if exists)
  local internal_manifest = wb_root .. "/PatchLibrary/Patches/manifest.json"
  if file_exists(internal_manifest) then
    local internal_root = wb_root .. "/PatchLibrary/Patches"
    local it = scan_manifest(internal_manifest, internal_root, "Workbench (Curated)")
    for _,x in ipairs(it) do out[#out+1]=x end
  end

  -- External repo manifests
  local ext_root = LibPath.get()
  local ext_manifest_dir = ext_root .. "/FB01/Manifests"
  local function glob_json(dir)
    local t = {}
    local cmd
    if r.GetOS():match("Win") then
      cmd = 'dir /b "'..dir..'\\*.json" 2>nul'
    else
      cmd = 'ls "'..dir..'"/*.json 2>/dev/null'
    end
    local p = io.popen(cmd)
    if p then
      local s = p:read("*all") or ""
      p:close()
      for line in s:gmatch("[^\r\n]+") do
        if r.GetOS():match("Win") then
          t[#t+1] = dir.."/"..line
        else
          t[#t+1] = line
        end
      end
    end
    return t
  end

  local jsons = glob_json(ext_manifest_dir)
  for _,mp in ipairs(jsons) do
    local base = mp:match("([^/\\]+)$") or mp
    local source = "PatchRepo ("..base..")"
    -- try to guess root for rel paths:
    local root_prefix = ext_root .. "/FB01"
    local it = scan_manifest(mp, root_prefix, source)
    for _,x in ipairs(it) do out[#out+1]=x end
  end


-- classify each item by reading the file (best-effort)
for _,it in ipairs(out) do
  it.kind = it.kind or "unknown"
  if it.full and file_exists(it.full) then
    local f = io.open(it.full, "rb")
    if f then
      local data = f:read("*all")
      f:close()
      local msgs = split_sysex(data)
      if #msgs == 1 then
        local k, bid = classify_sysex(msgs[1])
        it.kind = k
        it.bankId = bid
      elseif #msgs > 1 then
        it.kind = "param_stream"
      end
    end
  end
end

  return out
end

local function send_syx_file(path)
  r.SetExtState("IFLS_FB01", "SYX_PATH", path, false)
  dofile(wb_root .. "/Pack_v8/Scripts/IFLS_FB01_Replay_SYX_File_FromPath.lua")
end


local function md5_file(path)
  local f=io.open(path,"rb"); if not f then return "" end
  local d=f:read("*all"); f:close()
  if r.md5 then return r.md5(d) end
  return ""
end


-- UI
local ctx = r.ImGui_CreateContext("IFLS FB-01 Library Browser v2")
local filter = ""
local items = discover()
local last_refresh = r.time_precise()
local selected = 0
local audition_last = ""
local audition_last_md5 = ""
local audition_enabled = true


local function tags_to_str(tags)
  if type(tags)~="table" then return "" end
  local out={}
  for i=1, math.min(#tags, 6) do out[#out+1]=tostring(tags[i]) end
  return table.concat(out, ", ")
end

local function match(it, f)
  if f=="" then return true end
  f = f:lower()
  if (it.name or ""):lower():find(f, 1, true) then return true end
  if (it.source or ""):lower():find(f, 1, true) then return true end
  local ts = tags_to_str(it.tags):lower()
  if ts:find(f, 1, true) then return true end
  return false
end

local function loop()
  local visible, open = r.ImGui_Begin(ctx, "FB-01 Library Browser (v2)", true)
  if visible then
    local chg, nf = r.ImGui_InputText(ctx, "Search", filter)
    if chg then filter = nf end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Refresh", 100, 0) then
      items = discover()
      selected = 0
      last_refresh = r.time_precise()
    end
    r.ImGui_Text(ctx, ("Items: %d  |  Last refresh: %.1fs ago"):format(#items, r.time_precise()-last_refresh))
    r.ImGui_Separator(ctx)

    -- list
    if r.ImGui_BeginChild(ctx, "list", -1, 260, true) then
      local shown = 0
      for i,it in ipairs(items) do
        if match(it, filter) then
          shown = shown + 1
          local label = ("%s  [%s]  [Type:%s]"):format(it.name, it.source, (it.kind or "n/a"))
          local sel = (selected==i)
          if r.ImGui_Selectable(ctx, label, sel) then selected=i end
        end
      end
      if shown==0 then r.ImGui_Text(ctx, "No matches.") end
      r.ImGui_EndChild(ctx)
    end

    r.ImGui_Separator(ctx)
    if selected>0 and items[selected] then
      local it = items[selected]
      r.ImGui_Text(ctx, "Selected:")
      r.ImGui_Text(ctx, it.name)
      r.ImGui_Text(ctx, "Source: "..(it.source or ""))
      r.ImGui_Text(ctx, "Rel: "..(it.rel or ""))
      r.ImGui_Text(ctx, "Type: "..(it.kind or ""))
      if it.bankId ~= nil then r.ImGui_Text(ctx, "BankId: "..tostring(it.bankId)) end
      r.ImGui_Text(ctx, "Tags: "..tags_to_str(it.tags))
      r.ImGui_Text(ctx, "Path: "..(it.full or ""))

      if not file_exists(it.full) then
        r.ImGui_Text(ctx, "⚠ File missing on disk.")
      end

      if r.ImGui_Button(ctx, "Send to FB-01 (SysEx)", -1, 0) then
        if file_exists(it.full) then send_syx_file(it.full) end
      end
      if r.ImGui_Button(ctx, "Safe Audition (backup->audition->revert)", -1, 0) then
        dofile(root .. "/Tools/IFLS_FB01_Safe_Audition_Backup.lua")
      end
      if r.ImGui_Button(ctx, "Audition (send + remember for revert)", -1, 0) then
        if file_exists(it.full) then
          audition_last = it.full
          audition_last_md5 = md5_file(it.full)
          send_syx_file(it.full)
        end
      end
      if r.ImGui_Button(ctx, "Revert (re-send last auditioned)", -1, 0) then
        if audition_last ~= "" and file_exists(audition_last) then
          send_syx_file(audition_last)
        else
          r.MB("No audition file stored.", "FB-01 Browser", 0)
        end
      end
    else
      r.ImGui_Text(ctx, "Select a patch to view details.")
    end

    r.ImGui_End(ctx)
  end
  if open then r.defer(loop) else r.ImGui_DestroyContext(ctx) end
end

r.defer(loop)
