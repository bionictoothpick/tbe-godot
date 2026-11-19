# The Butterfly Effect: Godot edition

This is a community rebuild of **[The Butterfly Effect](https://github.com/the-butterfly-effect/tbe)**
(TBE) in **Godot 4.7**. TBE is a free physics puzzle game where you combine simple things to
reach a simple goal in the most complicated way possible.

**All credit for the game goes to its original creators:** Peter van Ginneken and
Klaas van Gend, together with everyone who contributed levels, art, translations
and playtesting (see [Credits](#credits)). This port is not affiliated with or endorsed
by them. It exists to keep their game alive on a modern engine.

All 86 original levels and nearly all of the original art are included. The four
penguin sprites are left out for licensing reasons; see [License](#license).

Open the folder in Godot 4.7 and press **F5**.

## Playing

* **Drag** items from the toolbox on the right into the scene.
* Rotate an item with the **mouse wheel** or **Q/E**. Hold **Shift** for fine steps.
* To resize, drag the **yellow dot** (only on items that can be resized).
* To put an item back, **right-click** it, press **Del**, or drag it onto the toolbox.
* **Space** plays or pauses and **R** resets. **⏩** speeds things up.
* Click **Post-it notes** to read hints.
* **🔊** (or **M**) turns sound on or off. The game remembers your choice.
* Items that overlap turn **red**, and you can't press Play until you fix them.
* **💾 Save** stores your arrangement, and it comes back automatically the next time
  you open the level. Winning solutions are saved too. Your arrangement is also
  saved whenever you leave the level or press Play.

## Adding a new object

Objects are data, not code. Each object is one `ObjectDef` resource in
`objects/defs/`.

1. In the FileSystem dock, duplicate an existing file, e.g. `objects/defs/BowlingBall.tres`.
2. Select the copy and set these fields in the Inspector:
   * `type_name`: the unique name used in level files.
   * `display_name`, `tooltip`, `category`: what players see.
   * `image`: the name of an image in `assets/images/`, without the extension.
     Drop new art (SVG works best) into that folder.
   * `shape` and `width`/`height` in meters. For a `POLYGON` shape, also set `polygons`.
   * `mass`: in kg. **0 means fixed in place.** Also `bounciness` and `friction`.
3. The new object is available in levels right away.

To give an object a special ability (floating, exploding, flying and so on):

1. Write a script that `extends ObjectBehavior`. The examples are in `scripts/behaviors/`.
2. Override the hooks you need: `physics_tick`, `on_impact`, `on_play_start`,
   `on_clicked`, `is_sharp_at`, `on_explosion`.
3. Set the script as the def's `behavior`.

## Level editor

Open it from the main menu with **✎ Level Editor**.

* **Add tab:** drag any object, or a joint (pivot, glue, link), into the scene.
* **In the scene:**
  * Drag an object to move it. Hold Shift to snap.
  * Use the mouse wheel or Q/E to rotate.
  * Drag the yellow dots to resize.
  * Arrow keys nudge the selected object.
  * Del or right-click deletes, and Ctrl+D duplicates.
  * Ctrl+wheel zooms and middle-drag pans. Ctrl+Z and Ctrl+Y undo and redo.
* **Edit tab:** exact position, size, angle, mass, bounciness, friction, image and tooltip
  for the selected object, plus a **Name (ID)**. Goals and joints refer to objects by
  this name. Other properties go in as `key = value` lines, for example Post-it
  pages or the butterfly's target.
* **Toolbox tab:** what the player gets to place. The easiest workflow is to build
  the working solution in the scene, then use **Move to player's toolbox** on each piece.
* **Goals tab:** "Win when *ball* moves right of x = 4", "Lose when *butterfly* changes
  state", and so on.
* **Level tab:** title, author, description, scene size and sky colors.
* **▶ Test** plays the level as a player would and checks that it can be won.
  **✎ Back to editor** returns with nothing lost.
* **💾 Save** writes the level to `user://levels/`. It then shows up with a ★ at the end
  of the level list. Opening a built-in level and saving it makes your own copy.

## Adding a new level by hand

Levels use the original TBE XML format and live in `assets/levels/`.

1. Copy a small level, such as `finished/bouncing_balls.xml`, and edit it.
   * Positions (`X`, `Y`) are object **centers** in meters, with Y pointing up.
   * `angle` is in radians.
2. List the file in `assets/levels/levels.xml` to give it a place in the
   sequence. Any `.xml` you put in `user://levels/` also shows up at the end of the list.

Goal types:

* `distance`: `object1`/`object2` with `lessthan`/`morethan`.
* `positionchange`: `object` with `xover`, `xbelow`, `yover`, `ybelow`, `xchanged`, `ychanged`,
  `anglechanged` or `anythingchanged`.
* `statechange`: `object`, for example a popped balloon.

Add `isFail="true"` to a goal to make it a losing condition.

## Project layout

| Path | What |
|---|---|
| `scripts/object_def.gd` | The object definition resource (Inspector-editable) |
| `scripts/tbe_object.gd` | A physics object built from a def + level data |
| `scripts/world.gd` | Builds levels, joints, runs the simulation, checks goals |
| `scripts/game.gd` | The play screen: toolbox, drag/rotate/resize, play/reset, dialogs |
| `scripts/editor.gd` | The level editor |
| `scripts/level_data.gd` | Reads/writes the level XML format |
| `scripts/behaviors/` | Butterfly, balloon, sharp things, cola+mint, dynamite, detonator, notes |
| `scripts/autoload/` | `Catalog` (objects), `Images` (crisp SVG rendering), `Levels`, `Progress` (saves), `Sfx` (sounds) |
| `tools/generate_object_defs.py` | One-off importer of the original C++ object tables |
| `tools/smoke_test.tscn` | Headless check that loads and simulates every level |
| `tools/input_test.tscn` | Plays level 2 with real mouse events: drag from toolbox, drag again, right-click back (run windowed) |
| `tools/sound_test.tscn` | Headless check that every sound is built and that settled levels go quiet |
| `tools/editor_test.tscn` | Drives the editor end to end: build, goal, toolbox, save, reload, test-play, win (run windowed) |

All test tools use a throw-away save, so they never touch your real progress.

**Input diagnostics** (off by default) help track down mouse problems. They log every
click the play screen receives to `input_log.txt`, and save a screenshot to `diag/`
each time an item is dropped, both in the game's user-data folder. Turn them on in
*Project Settings → Tbe → Debug → Input Diagnostics*, or start the game with:

```
godot --path . -- --input-diagnostics
```

To run the headless check:

```
godot --headless --fixed-fps 60 --path . res://tools/smoke_test.tscn
```

## How this port was made

The original game is written in C++ with Qt and Box2D. Development stopped around
2020, before its planned new interface was finished. This port is a fresh
implementation in Godot 4.7 (GDScript). It keeps the original's content and
behaviour:

* **Levels are unchanged.** The game reads the original XML level files directly,
  and the level editor writes the same format. The 86 files in `assets/levels/` are
  byte-for-byte copies of the originals.
* **The art is unchanged.** The SVG and bitmap images are copied as they are. SVGs
  are rendered at runtime at whatever size they are shown, so they stay sharp.
* **The objects keep their original numbers.** `tools/generate_object_defs.py` read
  the object tables (sizes, masses, bounciness, outlines and texts) from the original
  C++ source and wrote one Godot resource per object in `objects/defs/`.
* **Special behaviours were re-implemented** (butterfly, balloons, cola and mint,
  dynamite and so on) by following the original source code.
* **The physics runs on Godot's own engine,** with a few Box2D habits emulated so that
  levels play as they were designed (see [Known gaps](#known-gaps)).

New in this version: a modern interface, "save my solution", data-driven objects,
an in-game level editor, sound effects, and automated tests.

**Sound.** The original game had no sound. The sound effects here are generated in
code when the game starts (`scripts/autoload/sfx.gd`), so there are no audio files and
no extra licenses. Objects knock, clink, thud or bounce depending on what they are
made of. Balloons pop, dynamite booms, the detonator rings, cola fizzes, and a short
tune plays when you win or lose. To change an object's collision sound, edit the
`MATERIAL` table in `sfx.gd`, or give the object a `Sound` property (`wood`, `metal`,
`ball`, `soft` or `none`) in the level editor.

## Credits

**The Butterfly Effect** (2009–2020) was created by:

* **Peter van Ginneken** (project management)
* **Klaas van Gend** (development, and most of the levels)
* **Wuzzy**, who contributed many levels
* **Alexey Loginov**, who started and managed the translations
* The many contributors who sent fixes, and the volunteers who playtested the levels

The original list is in [`AUTHORS`](AUTHORS), and each level file names its author.
The art comes from many artists, mostly via openclipart.org. Every image's author,
source and license is listed in [`assets/images/CREDITS.txt`](assets/images/CREDITS.txt).

The original project lives at <https://github.com/the-butterfly-effect/tbe>.
This port is built with the [Godot Engine](https://godotengine.org) (MIT license).

## Known gaps

* **Penguins** (`Pingus*`) are not implemented yet. They appear in 9 levels and show up as
  placeholder boxes. Their original sprites are not included (see [License](#license)).
* **"Jumping Around 1"** (level 4) can't be solved yet with this physics engine.
* Physics runs on Godot's built-in engine, not Box2D (the original engine). These Box2D
  habits are emulated:
  * Slow impacts don't bounce.
  * Fixed objects have a 1 cm collision skin.
  * Bounciness acts roughly like Box2D's "larger of the two" rule.

  With no help from the player, two levels still solve themselves: "The Butterfly effect
  102" and "Geyser". Both are in the original's own `needs-polish` folder. Friction
  is mixed differently too: Godot takes the minimum, Box2D takes √(a·b).
* **Exporting:** add `*.svg, *.xml` under *Filters to export non-resource files* in
  the export preset. Without this, levels won't load and the SVG art loses its sharpness.

## License

This port keeps the original project's licensing.

* **Code:** **GNU General Public License, version 2 only** (GPL-2.0-only), the same as
  the original. The full text is in [`COPYING`](COPYING). The code is a new
  implementation, but it is derived from the original (object data, texts and
  behaviour), so it stays under the original's license. You may use, change and share
  it under those terms. If you distribute it, including exported builds, you must
  also make the source available under GPL-2.0-only.
* **Levels:** each level file keeps its own license, written in its `<license>` tag:
  85 are CC0, 4 are GPLv2 and 1 is WTFPL. New levels made with the editor default to CC0.
* **Art:** each image keeps its own license, listed in
  [`assets/images/CREDITS.txt`](assets/images/CREDITS.txt). Most are public domain, CC0 or
  WTFPL. A few require attribution (CC BY-SA 3.0, and photo textures from mayang.com
  and samuraisquirrel.com), and that file provides it. Please keep it with the art.
* **Left out:** the original penguin sprites (from the game Pingus) are licensed
  GPLv3-or-later. That doesn't combine cleanly with GPL-2.0-only code, so they are not
  included. Penguins will need replacement art under a compatible license.
* **Godot Engine** is MIT-licensed. Exported builds contain it, and its license text
  must be included with them.
