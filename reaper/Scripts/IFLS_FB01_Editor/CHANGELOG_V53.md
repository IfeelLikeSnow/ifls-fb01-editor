# V53 Additions (Bootstrap + SelfTest + SafeApply)

Generated: 2026-02-05T17:06:56.036344Z

## New: Bootstrap module
`Scripts/IFLS_Workbench/_bootstrap.lua`
- Central package.path setup
- Dependency detection helpers
- Data path resolver with ExtState override

## New: Safe Apply wrapper
`Scripts/IFLS_Workbench/Engine/IFLS_SafeApply.lua`
- Undo blocks, UI refresh suppression, pcall error handling, optional rollback

## New: SelfTest
`Scripts/IFLS_Workbench/Tools/IFLS_Workbench_SelfTest.lua`
- Offline checks: module load + JSON presence/parse sanity

## Doctor updated
`Scripts/IFLS_Workbench/Tools/IFLS_Workbench_Doctor.lua` now respects bootstrap `data_root` override when present.
