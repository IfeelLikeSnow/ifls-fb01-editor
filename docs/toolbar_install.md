# IFLS FB-01 Toolbar (Pro Option C)

This repo can generate a toolbar import file automatically.

## Install
1. Open the FB-01 Editor.
2. Open **About / ReaPack** panel.
3. Choose a toolbar slot (1–16).
4. Click **Install IFLS Toolbar**.

The script will:
- register the IFLS toolbar action scripts in REAPER (Actions list)
- generate a `.ReaperMenu` file with the correct `_RS...` command IDs
- write it into `REAPER resource path/MenuSets/`

## Activate in REAPER
1. `Options → Customize menus/toolbars…`
2. Select **Floating toolbar N**
3. Click **Import…** and select:
   `MenuSets/IFLS_FB01_Toolbar_Floating_N.ReaperMenu`

References:
- `.ReaperMenu` toolbars contain `icon_X=` and `item_X=` entries with action IDs (example: FilmSync.ReaperMenu).