
-- IFLS_FB01_Bank_Import_Syx_File.lua
-- B2.4 Tool: Import FB-01 voice bank .syx and export names CSV.

local r = reaper
local Bank = require("ifls_fb01_bank")

local function read_file_bytes(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open file" end
  local data = f:read("*all")
  f:close()
  local t={}
  for i=1,#data do t[#t+1]=string.byte(data,i) end
  return t
end

local function write_csv(path, rows)
  local f = io.open(path, "w")
  if not f then return false, "cannot write csv" end
  f:write("index,name\n")
  for _,row in ipairs(rows) do
    f:write(string.format("%d,%q\n", row.index, row.name))
  end
  f:close()
  return true
end

local function main()
  local ok, file = r.GetUserFileNameForRead("", "Select FB-01 Voice Bank (.syx)", ".syx")
  if not ok then return end

  local bytes, err = read_file_bytes(file)
  if not bytes then
    r.ShowMessageBox("Read failed: "..tostring(err), "FB-01 Import", 0)
    return
  end

  local res, err2 = Bank.decode_voice_bank_from_filebytes(bytes)
  if not res then
    r.ShowMessageBox("Decode failed: "..tostring(err2), "FB-01 Import", 0)
    return
  end

  local dir = file:match("^(.*)[/\\].-$") or "."
  local base = file:match("([^/\\]+)$") or "bank.syx"
  local csv = dir .. "/" .. (base:gsub("%.syx$","") .. "_names.csv")
  local ok2, err3 = write_csv(csv, res.voices)
  if not ok2 then
    r.ShowMessageBox("CSV write failed: "..tostring(err3), "FB-01 Import", 0)
    return
  end

  r.ShowMessageBox(
    "Imported bank: "..tostring(res.bank_name).."\nChecksum OK: "..tostring(res.checksum_ok).."\nExported: "..csv,
    "FB-01 Import", 0
  )
end

main()
