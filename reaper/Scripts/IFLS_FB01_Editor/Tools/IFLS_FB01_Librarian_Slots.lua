-- @description IFLS FB-01 - Librarian (Slots + Batch Send)
-- @version 0.10.0
-- @author IFLS
-- @about
--   Slot-based librarian for FB-01 SysEx. Uses shared IFLS SlotCore:
--   - Library scan
--   - Slot persistence (slots_fb01.json)
--   - Non-blocking batch sender
--
--   Slot payload is "multi": a list of SysEx messages from a .syx file.
--   This works for param-stream files and for dumps (they'll just be 1 message).

local r = reaper
if not r.ImGui_CreateContext then r.MB("ReaImGui required.", "FB-01 Librarian", 0) return end
if not r.SNM_SendSysEx then r.MB("SWS required (SNM_SendSysEx).", "FB-01 Librarian", 0) return end

local root = r.GetResourcePath() .. "/Scripts/IFLS FB-01 Editor"
local SlotCore = dofile(root .. "/Workbench/_Shared/IFLS_SlotCore.lua")

local ctx = r.ImGui_CreateContext("IFLS FB-01 Librarian")
r.ImGui_SetNextWindowSize(ctx, 1200, 720, r.ImGui_Cond_FirstUseEver())

local SCOPE = "fb01"
local SLOT_COUNT = 8
local state = SlotCore.load_state(SCOPE, SLOT_COUNT)
local slots = state.slots
local lib_dir = (state.meta and state.meta.lib_dir) or ""
local active = 1

local lib_files = {}
local filter = ""

local sender = SlotCore.BatchSender.new(function(msg) r.SNM_SendSysEx(msg) end)
sender:set_delay_ms(40)

local function rescan()
  lib_files = SlotCore.scan_dir(lib_dir, ".syx")
end

local function slot_load_from_file(i, path)
  local blob = SlotCore.read_all(path)
  if not blob then return false, "read failed" end
  local msgs = SlotCore.split_sysex(blob)
  if #msgs == 0 then return false, "no sysex messages found" end
  local name = (path:match("([^/\\]+)%.syx$") or ("Slot %d"):format(i))
  SlotCore.slot_set_multi(slots, i, name, path, msgs)
  state.slots = slots
  SlotCore.save_state(SCOPE, state)
  return true
end

local function slot_save_to_file(i, outp)
  local msgs = SlotCore.slot_get_multi(slots, i)
  if not msgs or #msgs == 0 then return false, "slot empty" end
  local ok = true
  local f = io.open(outp, "wb")
  if not f then return false, "write failed" end
  for _,m in ipairs(msgs) do f:write(m) end
  f:close()
  slots[i].path = outp
  state.slots = slots
  SlotCore.save_state(SCOPE, state)
  return ok
end

local function ui_library()
  r.ImGui_Text(ctx, "Library (.syx)")
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Set folder...", 120, 0) then
    local dir = SlotCore.choose_folder("FB-01 Library Folder", lib_dir)
    if dir then
      lib_dir = dir
      if state.meta then state.meta.lib_dir = lib_dir end
      SlotCore.save_state(SCOPE, state)
      rescan()
    end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Rescan", 80, 0) then rescan() end

  local ch, nv = r.ImGui_InputText(ctx, "Filter", filter)
  r.ImGui_SameLine(ctx)
  local cap, apv = r.ImGui_Checkbox(ctx, "Auto preview while browsing", auto_preview)
  if cap then auto_preview = apv end
  local cfav, fv = r.ImGui_Checkbox(ctx, "Favorites only", favorites_only)
  if cfav then favorites_only = fv end
  local cdup, dv = r.ImGui_Checkbox(ctx, "Show duplicates", show_duplicates)
  if cdup then show_duplicates = dv end

  if ch then filter = nv end

  r.ImGui_Separator(ctx)
  r.ImGui_BeginChild(ctx, "lib_list", -1, -1, true)
  for _,it in ipairs(lib_files) do
    local is_dupe = false
    if show_duplicates and it.hash and dupes[it.hash] and #dupes[it.hash] > 1 then is_dupe = true end
    local disp = it.name .. (is_dupe and "  [DUP]" or "")
    if filter == "" or it.name:lower():find(filter:lower(), 1, true) then
      if r.ImGui_Selectable(ctx, disp, false) then
        local ok, err = slot_load_from_file(active, it.path)
        if not ok then r.MB(err, "Load failed", 0) end
      end
      if r.ImGui_BeginDragDropSource(ctx) then
        r.ImGui_SetDragDropPayload(ctx, "IFLS_SYX_PATH", it.path)
        r.ImGui_Text(ctx, it.name)
        r.ImGui_EndDragDropSource(ctx)
      end
    end
  end
  r.ImGui_EndChild(ctx)
end

local function ui_slots()
  r.ImGui_Text(ctx, "Slots (FB-01 SysEx message lists)")
  local d = sender.delay_ms
  local changed, newd = r.ImGui_SliderInt(ctx, "Delay ms", d, 0, 200)
  if changed then sender:set_delay_ms(newd) end
  r.ImGui_Separator(ctx)

  for i=1,SLOT_COUNT do
    local s = slots[i]
    local label = (s.name or ("Slot %d"):format(i))
    if r.ImGui_Selectable(ctx, label, i==active) then active = i end
    if r.ImGui_BeginDragDropTarget(ctx) then
      local rv, payload = r.ImGui_AcceptDragDropPayload(ctx, "IFLS_SYX_PATH")
      if rv and payload and payload ~= "" then
        local ok2, err = slot_load_from_file(i, payload)
        if not ok2 then r.MB(err, "Load failed", 0) end
      end
      r.ImGui_EndDragDropTarget(ctx)
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, ("Load##%d"):format(i), 60, 0) then
      local ok, p = r.GetUserFileNameForRead("", "Load FB-01 .syx", ".syx")
      if ok and p ~= "" then
        local ok2, err = slot_load_from_file(i, p)
        if not ok2 then r.MB(err, "Load failed", 0) end
      end
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, ("Send##%d"):format(i), 60, 0) then
      local msgs = SlotCore.slot_get_multi(slots, i)
      if msgs then
        sender:clear()
        sender:enqueue_many(msgs)
        sender:start()
      end
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, ("Save##%d"):format(i), 60, 0) then
      local ok, outp = r.GetUserFileNameForWrite("", "Save FB-01 slot .syx", ".syx")
      if ok and outp ~= "" then
        local ok2, err = slot_save_to_file(i, outp)
        if not ok2 then r.MB(err, "Save failed", 0) end
      end
    end
  end

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Batch Send 1-4", 140, 0) then
    sender:clear()
    for i=1,math.min(4,SLOT_COUNT) do
      local msgs = SlotCore.slot_get_multi(slots, i)
      if msgs then sender:enqueue_many(msgs) end
    end
    sender:start()
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Batch Send 1-8", 140, 0) then
    sender:clear()
    for i=1,SLOT_COUNT do
      local msgs = SlotCore.slot_get_multi(slots, i)
      if msgs then sender:enqueue_many(msgs) end
    end
    sender:start()
  end

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Open slots JSON", 140, 0) then
    local p = SlotCore.slots_path(SCOPE)
    if package.config:sub(1,1) == "\\" then
      os.execute(('start "" "%s"'):format(p))
    else
      os.execute(('xdg-open "%s" >/dev/null 2>&1 &'):format(p))
    end
  end
end

local function loop()
  local visible, open = r.ImGui_Begin(ctx, "IFLS FB-01 Librarian (Slots + Batch Send)", true)
  if visible then
    r.ImGui_Columns(ctx, 2, "cols")
    ui_library()
    r.ImGui_NextColumn(ctx)
    ui_slots()
    r.ImGui_Columns(ctx, 1)
    r.ImGui_End(ctx)
  end
  if open then r.defer(loop) else r.ImGui_DestroyContext(ctx) end
end

r.defer(loop)
