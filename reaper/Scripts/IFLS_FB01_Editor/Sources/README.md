# FB-01 Patch Sources moved to external repository

The full FB-01 patch archive has been moved out of the main IFLS Workbench repo to keep updates lightweight.

Install the separate patch library repo into:
`REAPER/ResourcePath/Scripts/IFLS_FB01_PatchLibrary`

Workbench will auto-detect it, or you can set:
ExtState namespace `IFLS_FB01` key `LIBRARY_PATH` to an absolute path.

Curated patches may still exist under `Workbench/FB01/PatchLibrary/Patches/`.
