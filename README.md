# Hearthline

A native Godot 4.7 puzzle game that scales its board to the display, including fullscreen. Open `project.godot` in Godot and press **F6** with `main.tscn` open, or **F5** to run the project. On Windows, double-click `Play Hearthline.cmd` to use the Godot executable already in this folder.

## Play

- Drag through adjacent tiles to draw one continuous line. Entering a colored tile flips it between light and dark. Gray tiles never change and do not need to be cleared.
- Cross an existing straight section at a right angle and continue straight through it. The starting tile can also be crossed at a right angle to the line's first step, but cannot be entered from behind. Corners and tiles already visited twice cannot be crossed. A light tile at a crossed start or endpoint counts as light when checking for a win.
- The circle marks the start of the line. Drag backwards along the line to undo, or click any visited tile other than the start to return to that move and continue drawing. Clicking the start clears the entire line, even when the line crosses it. Releasing a line that occupies only one tile also clears it. **Reset line** clears a longer line completely.
- Make every colored tile light to win. A celebration plays and progress is saved. It stays open with **Back to Puzzle Selection** and **Next Puzzle** buttons; Next opens the adjacent unlocked puzzle and is hidden at the last available puzzle. At that boundary the message reads **Good job! You must complete more puzzles to continue.** Whenever that completion unlocks a new group, the message instead reads **New puzzles unlocked!** Each newly completed puzzle gives one credit. Completed puzzles show a large green checkmark inside a thick green circle at the top right of their play screen, with the credit balance beside it.
- Level 1 marks its leftmost dark tile **Drag** with white, black-outlined text. The finish tile has no label.
- The menu opens levels in groups of five. Completing any three puzzles in a group opens the next five, and unlocked groups stay open. The top right shows your credits. Every available level appears in one scrollable grid, followed by a gray question mark card with a red outline hinting at more levels. Completed levels have green outlines, unfinished levels have yellow outlines, and levels without a known solution have red outlines. Clicking the question mark shakes the screen and floats **Complete more puzzles...** upward from the pointer.
- In a puzzle, **Previous puzzle** and **Skip** visit adjacent unlocked levels, including completed puzzles. Previous wraps from the first level; Skip at the last unlocked level shakes the screen and displays **Complete more puzzles...**. The puzzle slides while the buttons stay put. Hint sits beside All puzzles in that button row.
- Except on level 1, **Hint -2** followed by a vector coin icon spends two credits to reveal the solution start as white outlined text. The button then reads **Hint -1** with the same icon; that second purchase costs one credit and reveals the finish, then the button disappears. If there are not enough coins, clicking Hint floats a red **Need more coins...** message upward without spending anything. The credit balance and falling coin use the same SVG artwork. Purchased hints stay visible on their puzzle across visits and restarts. The button waits for a falling coin and the hint's fade before it can be pressed again, and Space does not activate it. Puzzles without a known solution cannot offer hints.
- Opening a puzzle expands its menu card into the board over 0.2 seconds while the surrounding controls fade. Returning shrinks the board into its card and brings it into view in the scrollable grid. Skip and Previous puzzle push the old board left or right; Previous also wraps from the first level.

## Generation

The level number is the random seed. Each level is generated from a legal solution, then its tiles are flipped to create the starting board. Automatic levels contain a solution visiting **50–80 tiles**, including the starting tile and repeated visits at crossovers. This is a solution length, not a move limit or a guarantee of the shortest possible solution.

Automatic puzzles start on a canvas with independently chosen width and height of **12–15 tiles**. A seeded construction selects a legal **50–80 tile** route with **7–10 crossovers**. Unused outer space is cropped to the full solution bounds before adding **one light row/column on every side**, so the final board can be smaller than the initial canvas. The route is remapped into that crop, preserving its crossings and solution. Work is bounded to keep level loading responsive. Generated puzzles use only light and dark tiles. The editor generator keeps its chosen dimensions, move count, and exact crossover settings without padding. Default five-level group hues use seeded variation with wide spacing between neighboring groups, while manually assigned group colors take priority. Colors are balanced by relative luminance so each hue has consistent visual weight, including manually chosen hues. Light and dark tiles remain distinct; gray tiles remain available for custom editor layouts. The play background uses 25% saturation and a hue 150° from the tiles. Pale text and quieter secondary buttons share that split-complementary hue during play; primary buttons have a stronger fill. On the menu, text and buttons use the selected level's main hue. Text shadows use 22% opacity. The default line uses the former custom color of levels 6–10 (#eae345), with a subtle raised shadow. Each five-level area can instead use a manually chosen line color. The completion subtext matches the light tiles. Button labels meet a 4.5:1 contrast target in normal, hover, and pressed states. Hovering over a level fades the menu background to its main hue and updates UI colors over 0.3 seconds. That palette stays until another level is hovered; opening a level fades to the play background hue at the same darkness. Puzzle navigation blends the background over the 0.2-second screen transition; each screen keeps its own text and button palette as it moves or fades. When a drag jumps across multiple tiles, the line alternates legal horizontal and vertical moves toward the cursor, trying the other direction when one is blocked. The line tip follows the resulting route and tile flips animate over 0.2 seconds.

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
| **Shift + Z + M** | Complete and unlock levels 1–99, then open the refreshed menu |
| **Shift + Z + N** | Clear completion except level 1 and reset purchased hints, then open the refreshed menu |
| **Shift + Z + B**, then click a level | Complete every level through that one, clear completion after it, and refresh unlocked groups |
| **Space** | Switch between building and playtesting inside the level editor |

In rearrange mode, choose **Insert** or **Swap**, then drag a level. Insert animates the surrounding cards to show the insertion gap; use the left or right half of a target card for before or after. Swap animates the target into the dragged level's slot. Completion marks move with their puzzles, and unlocked groups remain visible when completion marks move. Click **Done**, press **Escape**, or press the shortcut again to return to normal selection.

The red **Delete Progress** button at the bottom left of the main menu opens three short confirmations. The final confirmation clears completed levels, credits, unlocked groups, and purchased hints and returns to the initial five puzzles. Cancelling any step keeps progress. Custom puzzle layouts and colors remain available.

In the level editor, choose dimensions, paint light/dark/gray tiles, choose a level number, and click **Save level** to replace its generated puzzle. Right-click and drag to paint light tiles regardless of the selected brush. Changing the number loads that level. **Copy** stores the current layout and **Paste** applies it to the selected level as one undoable edit; click **Save level** to keep it. **Insert level here** saves the current design at the selected number and moves later custom levels up one number. **Delete saved level** removes the selected custom level and moves later custom levels down one number. Completion records shift with those numbers, and both structural actions can be undone or redone in the editor. Levels generated on demand have no saved layout to delete until you save or generate one in the editor. **Reset all to white** clears the grid as one undoable edit. Set **Moves (tiles in line)** and **Required crossovers**, then click **Generate random level** to create and save a solvable puzzle at the current dimensions, including its full solution. Moves counts every tile visited, including the starting tile. Both values are required exactly. The editor's suggested move count starts at the level number plus 26 or the grid area, whichever is smaller. If generation cannot find a matching line, the draft stays unchanged; you can try again or adjust the settings. Each click uses a new random seed and saves the result; Undo restores the previous draft and saved level. The editor supports 3–128 tiles on each side. Each drag is one undo step. Solving a playtest saves the layout and full line, including its start and finish for hints, without marking it complete. A later edit and save clears the old solution. Unsaved layout edits are discarded when closing. Custom puzzles need at least one dark tile; use **Solve puzzle** to check a design.

**Suggest gray tiles** applies one small placement to the current draft: a light tile or connected pair bridging dark groups, a junction, or a known crossover. It keeps all dark targets, avoids known start/finish tiles and existing gray patches, and leaves any existing solution playable. This uses layout heuristics, so it may report that no useful placement was found. The editor explains each suggestion. **Ctrl + Z** undoes the whole placement and **Ctrl + Y** redoes it; **Save level** keeps the edit. As with painting, editing clears the recorded solution; use Solve puzzle or playtest to record it again.

Press **Space** while the level editor is open to draw a test line on the current unsaved layout. Solving it displays an editor message and does not advance or mark the level complete. Press **Space** again to clear the test line and return to painting.

Click **Solve puzzle** at the top of the editor controls to find a legal line for the current draft. A saved solution appears in playtest mode immediately; otherwise the editor searches for a legal line. A found line is saved with its start and finish for hints, just like solving a playtest yourself. The search follows the same crossing and tile-flipping rules as play, and keeps the editor responsive. Each frame shows the last checked route on the board and its length in tiles, including repeated crossover visits. The final solution also shows its length. Complex puzzles can take a long time; **Cancel solve** or **Space** returns to building, and leaving the editor stops the search. An exhaustive search that finds no route reports that no legal solution exists. The generated move and crossover settings do not restrict the solver, and the returned line is not necessarily the shortest.

In the color editor, choose a level number, switch between **Tile hue** and **Line color**, and use the live preview to see the line crossing light and dark tiles. **Use suggested line color** restores the default #eae345. **Copy colors** stores the current tile and line colors; choose another level and use **Paste colors** to preview that scheme there. Click **Save area colors** to update all five levels in the selected set. Close using the same shortcut.

## Saved files

- `data/levels.json`: shipped custom layouts, optional full solutions and endpoints, five-level tile colors, and optional line colors. Editor saves also update this project file when running from writable source.
- `user://levels.json`: writable custom layouts and colors, including line colors in exported builds; merged over the shipped file when loading.
- `user://progress.json`: completed levels, unlocked groups, credit balance, and purchased hints, separate from shared puzzle definitions.

Godot's normal Windows user folder is `%APPDATA%/Godot/app_userdata/Hearthline/`. Existing saves under `Unium`, `Afterglow`, `Glimmer`, and `Strike-through` are read as fallbacks, so progress made before the renames remains available. Old per-level color entries are interpreted as group colors. Writes use a temporary file followed by replacement. Tile values in JSON are `0` = light, `1` = dark, `2` = gray.

## Verification

`tests/test_game.gd` checks 150 deterministic generated levels, 50–80 tile solutions, 7–10 crossovers, initial dimensions, tight cropping, light borders, gray suggestions, palettes, crossing rules, fast drag sampling, backtracking/resume, editor undo/redo, keyboard chords, persistence, and completion/progression. `tests/visual_smoke.gd` captures menu, gameplay, line, editor, and completed puzzle screenshots using the actual renderer. `tests/test_menu_transitions.gd` checks zoom and slide transitions, interruption cleanup, scroll restoration, hover animation, and background thumbnail preparation. It reports timings for a 105-card menu and captures transition frames when run without `--headless`.

`tests/test_solver.gd` compares the solver with independently enumerated legal routes on all 3×3 dark/light layouts and several gray-tile patterns. It also checks search responsiveness, stale generated solutions, editor cancellation, solution display, and saved endpoints.

Menu thumbnails are prepared by a worker and cached as small images, without live puzzle boards, per-card viewports, or GPU readbacks. Unsolved cards have a yellow background glow that fades in and out over 2.4 seconds using a shared shader, without rebuilding thumbnails each frame. Completed cards have no glow. Visible cards load first. An unchanged menu stays in memory during play so returning reuses its controls and scroll position. Changes to progress, layouts, or colors invalidate it. Puzzle tiles cache their geometry and share three base styles. Their drawing lives outside Control theme notifications, so moving, scaling, or recoloring screen controls does not rebuild every tile.

Run the tests from PowerShell with isolated user data (so tests don't affect your progress):

```powershell
New-Item -ItemType Directory -Force .test-user | Out-Null
$env:APPDATA = Join-Path (Get-Location) '.test-user'
Start-Process -FilePath .\Godot_v4.7.1-stable_win64.exe -ArgumentList '--headless', '--path', '.', '--script', 'tests/test_game.gd', '--log-file', '.test-user/tests.log' -WindowStyle Hidden -Wait
Get-Content .test-user/tests.log
```

For screenshots, use `tests/visual_smoke.gd` without `--headless`. Screenshots and test saves stay in the ignored `.test-user/` folder. Tests disable writes to the project's levels file.

To profile thumbnail preparation with 105 freshly generated puzzles, run `tests/test_menu_transitions.gd` without `--headless` and append `-- --generated` to the Godot arguments.

To profile actual menu-to-puzzle and puzzle-to-puzzle frames, run `tests/profile_board_transitions.gd` without `--headless` using the same isolated user data. It reports setup time, frame timings, and tile redraw counts, and fails if static tiles are repeatedly redrawn during a transition.
