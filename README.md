# Afterglow

A native Godot 4.7 puzzle game. Open `project.godot` in Godot and press **F6** with `main.tscn` open, or **F5** to run the project. On Windows, double-click `Play Afterglow.cmd` to use the Godot executable already in this folder.

## Play

- Drag through adjacent tiles to draw one continuous line. Entering a colored tile flips it between light and dark. Gray tiles never change and do not need to be cleared.
- Cross an existing straight section at a right angle and continue straight through it. Corners, the starting tile, and tiles already visited twice cannot be crossed.
- Drag backwards along the line to undo. Release and click the endpoint to continue. **Reset line** clears it completely.
- Make every colored tile light to win. A celebration plays, progress is saved, and the next level opens automatically.
- The menu displays screenshots of levels 1 through the first unsolved level. Completed levels have a checkmark and can be replayed.

## Generation

The level number is the random seed. Each level is generated from a legal solution, then its tiles are flipped to create the starting board. The generated solution visits **level number + 6 tiles**, including the starting tile: seven for level 1, eight for level 2, and so on. This is a solution length, not a move limit or a guarantee of the shortest possible solution.

Dimensions vary independently from 3–7 while that range can accommodate the solution. From level 44 onward, the allowed maximum side grows as needed, as requested, keeping the extra move per level. Search has a fixed work budget and a guaranteed legal serpentine fallback. Neutral tiles form separate connected groups of 2–4, each touching a dark tile. The seeded palette changes every five levels; a manual color overrides only its chosen level.

## Editors

Hold all keys in a shortcut together; extra modifiers do not activate it.

| Shortcut | Action |
| --- | --- |
| **Shift + Z + O** | Open / close the level editor |
| **Ctrl + Z** | Undo an editor stroke, resize, or load |
| **Ctrl + Y** | Redo an editor change |
| **Shift + Z + I** | Open / close the per-level color editor |

In the level editor, choose dimensions, paint light/dark/gray tiles, choose a level number, and click **Save level** to replace its generated puzzle. **Load level** loads the chosen number; changing the number alone lets you save your current design under another number. **Reset all to white** clears the grid as one undoable edit. The editor supports 3–128 tiles on each side. Each drag is one undo step. Unsaved layout edits are discarded when closing. Custom puzzles need at least one dark tile; the editor does not prove custom designs solvable.

In the color editor, choose a level number, pick a color (or enter its hex code), and click **Save level color**. Close using the same shortcut.

## Saved files

- `data/levels.json`: shipped custom layouts and per-level colors. Editor saves also update this project file when running from writable source.
- `user://levels.json`: writable custom layouts/colors, including in exported builds; merged over the shipped file when loading.
- `user://progress.json`: completed levels, separate from shared puzzle definitions.

Godot's normal Windows user folder is `%APPDATA%/Godot/app_userdata/Afterglow/`. Existing saves under `Unium` are read as a fallback, so progress made before the rename remains available. Writes use a temporary file followed by replacement. Tile values in JSON are `0` = light, `1` = dark, `2` = gray.

## Verification

`tests/test_game.gd` checks 150 deterministic generated levels, increasing lengths, legal solutions, gray clusters, palettes, crossing rules, fast drag sampling, backtracking/resume, editor undo/redo, keyboard chords, persistence, and completion/progression. `tests/visual_smoke.gd` captures menu, gameplay, line, and editor screenshots using the actual renderer.

Run the tests from PowerShell with isolated user data (so tests don't affect your progress):

```powershell
New-Item -ItemType Directory -Force .test-user | Out-Null
$env:APPDATA = Join-Path (Get-Location) '.test-user'
Start-Process -FilePath .\Godot_v4.7.1-stable_win64.exe -ArgumentList '--headless', '--path', '.', '--script', 'tests/test_game.gd', '--log-file', '.test-user/tests.log' -WindowStyle Hidden -Wait
Get-Content .test-user/tests.log
```

For screenshots, use `tests/visual_smoke.gd` without `--headless`. Screenshots and test saves stay in the ignored `.test-user/` folder. Tests disable writes to the project's levels file.
