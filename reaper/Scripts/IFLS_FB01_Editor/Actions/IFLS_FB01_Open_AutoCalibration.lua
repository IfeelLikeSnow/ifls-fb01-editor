-- @description IFLS FB-01: Open Auto-Calibration
-- @version 0.1.2
-- @author IFLS
-- @about
--   Opens the editor and jumps to Auto-Calibration (via ExtState hint).
local r = reaper
r.SetExtState("IFLS_FB01", "UI_START_TAB", "autocal", false)
local script = r.GetResourcePath() .. "/Scripts/IFLS FB-01 Editor/Editor/IFLS_FB01_SoundEditor.lua"
dofile(script)
