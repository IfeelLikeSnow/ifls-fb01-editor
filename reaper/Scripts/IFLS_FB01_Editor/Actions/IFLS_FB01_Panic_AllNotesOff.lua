-- @description IFLS FB-01: Panic (All Notes Off)
-- @version 0.1.2
-- @author IFLS
-- @about
--   Calls REAPER action 'Send all notes off to all MIDI outputs/plug-ins' (cmd 40345).
local r = reaper
r.Main_OnCommand(40345, 0)
