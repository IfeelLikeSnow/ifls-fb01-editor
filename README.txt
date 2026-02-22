IFLS FB-01 Syntax Fix v4

Fixes reported by IFLS FB-01 Lua syntax scan:
- SoundEditor: <eof> expected near 'end' (stray AutoCal peak block)
- Batch Analyze tool: invalid escape sequence near '"\|' (Lua string escapes)

Why the batch tool fails:
Lua strings treat backslash as an escape introducer, so "\|" is invalid.
Use "\\|" to represent \| in the resulting string. (Lua manual / common Lua behavior)

Local apply:
  powershell -ExecutionPolicy Bypass -File IFLS_FB01_Apply_SyntaxFix_v4.ps1

Repo apply:
  Copy tools/IFLS_FB01_Repo_Apply_SyntaxFix_v4.ps1 into your repo (or run from this zip if you unzip into repo root)
  powershell -ExecutionPolicy Bypass -File .\tools\IFLS_FB01_Repo_Apply_SyntaxFix_v4.ps1
  git add -A
  git commit -m "Fix Lua syntax (SoundEditor peak block + batch syx escape)"
  git push

After patch:
- Restart REAPER
- Run the IFLS FB-01 Lua syntax scan again. If new errors show up, send the output.
