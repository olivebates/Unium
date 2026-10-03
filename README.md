# Hearthline

A native Godot 4.7 puzzle game that scales its board to the display, including fullscreen. Open `project.godot` in Godot and press **F6** with `main.tscn` open, or **F5** to run the project. On Windows, double-click `Play Hearthline.cmd` to use the Godot executable already in this folder.

## Play

- Drag through adjacent tiles to draw one continuous line. Entering a colored tile flips it between light and dark. Gray tiles never change and do not need to be cleared.
- Cross an existing straight section at a right angle and continue straight through it. The starting tile can also be crossed at a right angle to the line's first step, but cannot be entered from behind. Corners and tiles already visited twice cannot be crossed. A light tile at a crossed start or endpoint counts as light when checking for a win.
- The circle marks the start of the line. Drag backwards along the line to undo, or click any tile already on the line to return to that move and continue drawing. Releasing a line that occupies only one tile clears it. **Reset line** clears a longer line completely.
- Make every colored tile light to win. A celebration plays, progress is saved, and the next level opens automatically.
- The menu displays screenshots of levels 1 through the first unsolved level, in left-aligned rows of up to 15, with the whole grid centered. Completed levels have a checkmark and can be replayed. The cards have no hover popups.

## Generation

The level number is the random seed. Each level is generated from a legal solution, then its tiles are flipped to create the starting board. The generated solution visits **level number + 26 tiles**, including the starting tile: 27 for level 1, 28 for level 2, and so on. This is a solution length, not a move limit or a guarantee of the shortest possible solution.

Dimensions vary independently from 3–7 while that range can accommodate the solution. From level 24 onward, the allowed maximum side grows as needed, as requested, keeping the extra move per level. Search prefers legal self-crossings when available, with at most three per generated solution. It has a fixed work budget and uses a guaranteed legal serpentine fallback. Neutral tiles form separate connected groups of 2–4, each touching a dark tile. Five-level sets use a repeating sequence of mint, sky blue, lavender, coral, and amber; a manual hue applies to its whole set. Colors are balanced by relative luminance so each hue has consistent visual weight, including manually chosen hues. Light and dark tiles remain distinct, while gray tiles stay subdued. The play background uses 25% saturation and a hue 150° from the tiles. Pale text and quieter secondary buttons share that split-complementary hue during play; Play and Save buttons have a stronger fill. On the menu, text and buttons use the selected level's main hue. Text shadows use 22% opacity. The default line uses the former custom color of levels 6–10 (#eae345), with a subtle raised shadow. Each five-level area can instead use a manually chosen line color. The completion subtext matches the light tiles. Button labels meet a 4.5:1 contrast target in normal, hover, and pressed states. Hovering over a level fades the menu background to its main hue and updates UI colors over 0.3 seconds. That palette stays until another level is hovered; opening a level fades to the play background hue at the same darkness. Changing to another five-level set fades them over 0.6 seconds. When a drag jumps across multiple tiles, the line alternates legal horizontal and vertical moves toward the cursor, trying the other direction when one is blocked. The line tip follows the resulting route and tile flips animate over 0.2 seconds.

## Editors

Hold all keys in a shortcut together; extra modifiers do not activate it.

| Shortcut | Action |
| --- | --- |
| **Shift + Z + O** | Open / close the level editor for the current level, or the hovered menu level |
| **Ctrl + Z** | Undo an editor stroke, resize, or paste |
| **Ctrl + Y** | Redo an editor change |
| **Shift + Z + I** | Open / close the five-level area color editor |
| **Shift + Z + U** | Open / close rearrange mode in the main menu |
| **Shift + Z + Left / Right** | Open the previous / next level while playing or editing |
| **Arrow keys** | Shift every tile one space in the level editor; tiles wrap around edges |
| **Escape** | Return to the main menu and close editor or rearrange modes |
| **Ctrl + Z + M** | Complete and unlock levels 1–99, then open the refreshed menu |
| **Ctrl + Z + N** | Clear completion except level 1, then open the refreshed menu |
| **Space** | Switch between building and playtesting inside the level editor |

In rearrange mode, choose **Insert** or **Swap**, then drag a level. Insert animates the surrounding cards to show the insertion gap; use the left or right half of a target card for before or after. Swap animates the target into the dragged level's slot. Completion marks move with their puzzles. All unlocked levels remain visible while rearranging, even if the first unsolved level moves to an earlier number. Click **Done**, press **Escape**, or press the shortcut again to return to normal selection.

In the level editor, choose dimensions, paint light/dark/gray tiles, choose a level number, and click **Save level** to replace its generated puzzle. Right-click and drag to paint light tiles regardless of the selected brush. Changing the number loads that level. **Copy** stores the current layout and **Paste** applies it to the selected level as one undoable edit; click **Save level** to keep it. **Insert level here** saves the current design at the selected number and moves later custom levels up one number. **Delete saved level** removes the selected custom level and moves later custom levels down one number. Completion records shift with those numbers, and both structural actions can be undone or redone in the editor. Generated levels have no saved layout to delete. **Reset all to white** clears the grid as one undoable edit. Set **Moves (tiles in line)** and **Required crossovers**, then click **Generate random level** to create a solvable draft at the current dimensions. Moves counts every tile visited, including the starting tile. Both values are required exactly. The suggested move count starts at the level's normal length or the grid area, whichever is smaller. If generation cannot find a matching line, the draft stays unchanged; you can try again or adjust the settings. Each click uses a new random seed, the result can be undone, and **Save level** keeps it. The editor supports 3–128 tiles on each side. Each drag is one undo step. Unsaved layout edits are discarded when closing. Custom puzzles need at least one dark tile; the editor does not prove custom designs solvable.

Press **Space** while the level editor is open to draw a test line on the current unsaved layout. Solving it displays an editor message and does not advance or mark the level complete. Press **Space** again to clear the test line and return to painting.

In the color editor, choose a level number, switch between **Tile hue** and **Line color**, and use the live preview to see the line crossing light and dark tiles. **Use suggested line color** restores the default #eae345. **Copy colors** stores the current tile and line colors; choose another level and use **Paste colors** to preview that scheme there. Click **Save area colors** to update all five levels in the selected set. Close using the same shortcut.

## Saved files

- `data/levels.json`: shipped custom layouts, five-level tile colors, and optional line colors. Editor saves also update this project file when running from writable source.
- `user://levels.json`: writable custom layouts and colors, including line colors in exported builds; merged over the shipped file when loading.
- `user://progress.json`: completed levels and the highest unlocked level retained after rearranging, separate from shared puzzle definitions.

Godot's normal Windows user folder is `%APPDATA%/Godot/app_userdata/Hearthline/`. Existing saves under `Unium`, `Afterglow`, `Glimmer`, and `Strike-through` are read as fallbacks, so progress made before the renames remains available. Old per-level color entries are interpreted as group colors. Writes use a temporary file followed by replacement. Tile values in JSON are `0` = light, `1` = dark, `2` = gray.

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
