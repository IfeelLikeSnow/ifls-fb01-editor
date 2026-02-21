-- @description IFLS FB-01 - Project Recall: Save current voice file selection
-- @version 0.99.0
-- @author IFLS
-- Saves a selected voice .syx path into ProjectExtState so it can be recalled on load.
local r=reaper
local ok, path = r.GetUserFileNameForRead("", "Select FB-01 Voice .syx to store in project", ".syx")
if not ok or path=="" then return end

-- compute hash for safety
local f=io.open(path,"rb"); if not f then r.MB("Cannot read.", "FB-01 Recall", 0); return end
local data=f:read("*all"); f:close()
local h = r.md5(data)

r.SetProjExtState(0, "IFLS_FB01", "RECALL_VOICE_PATH", path)
r.SetProjExtState(0, "IFLS_FB01", "RECALL_VOICE_MD5", h)
r.MB("Stored FB-01 recall voice in project:\n"..path.."\nmd5="..h, "FB-01 Recall", 0)
