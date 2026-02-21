-- @description IFLS FB-01 - Project Recall: Apply stored voice to FB-01
-- @version 0.99.0
-- @author IFLS
-- Requires SWS for SNM_SendSysEx, uses existing FromPath replayer.
local r=reaper
if not r.SNM_SendSysEx then
  r.MB("SWS not found (SNM_SendSysEx missing).", "FB-01 Recall Apply", 0)
  return
end
local rv, path = r.GetProjExtState(0, "IFLS_FB01", "RECALL_VOICE_PATH")
if rv==0 or not path or path=="" then
  r.MB("No recall voice stored in this project.", "FB-01 Recall Apply", 0)
  return
end
local rv2, md5 = r.GetProjExtState(0, "IFLS_FB01", "RECALL_VOICE_MD5")

local f=io.open(path,"rb")
if not f then r.MB("File missing:\n"..path, "FB-01 Recall Apply", 0); return end
local data=f:read("*all"); f:close()
local h = r.md5(data)
if md5 and md5~="" and h~=md5 then
  local ret = r.MB("Stored file hash differs. Continue sending anyway?\n\nPath:\n"..path, "FB-01 Recall Apply", 4)
  if ret ~= 6 then return end
end

local root = r.GetResourcePath().."/Scripts/IFLS FB-01 Editor"
r.SetExtState("IFLS_FB01","SYX_PATH", path, false)
dofile(root.."/Pack_v8/Scripts/IFLS_FB01_Replay_SYX_File_FromPath.lua")
