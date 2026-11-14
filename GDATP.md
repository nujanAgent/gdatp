# GDatp

GDatp is NuJan's Godot editor for Android: Godot's own Android editor, built from Godot's source with a small set of
changes, so that a person and NuJan work in the same editor. NuJan reaches it through ATP (App Tools Protocol for
Android) tools, as PC agents reach Godot's desktop editor through MCP servers. Package `com.gd.atp`, named GDatp.

- **Upstream:** Godot `4.7.2-stable` (`ed1daf0`), MIT. GDatp's changes are made as separate commits on top of that
  tag, so they can be moved onto each new Godot release; this repository publishes the files they add or change
  ("Building").

## What the branch changes

| Where | What |
| --- | --- |
| `platform/android/java/editor/build.gradle` | Package `com.gd.atp`, name GDatp; the debug build keeps the package id |
| `editor/src/main/java/com/gd/atp/GDatpPlugin.kt` | The bridge to the editor: a call made on any thread reaches the tool host as the `GDatp` singleton's `call_arrived` signal on the engine's main thread, and the host answers with `reply`; it also hands the editor the host's source |
| `modules/gdatp/` | An editor plugin, built only into the Android editor, that compiles the tool host's GDScript and runs it in every project the editor opens, so no files are added to the person's project; it also gives the host the editor's own undo and redo, a node's Scene dock warnings, every error and warning the script editor finds in a script, and the file each script editor tab edits with whether it is unsaved, which scripts cannot reach |
| `editor/src/main/assets/gdatp/host.gd`, `host_*.gd`, `shared_*.gd` | The tool host: the tools themselves, in GDScript, shipped in the APK; `GDatpPlugin.hostSource` appends each `host_*.gd` part (shared steps, tiles, animation, UI, resources, 3D, the running game) and each `shared_*.gd` part after `host.gd` as one script. `shared_values.gd`, values typed from JSON and shown as JSON, goes into the game helper too, so the editor and the running game read values the same way |
| `editor/src/main/assets/gdatp/game_helper.gd`, `helper_*.gd`, `modules/gdatp/gdatp_game_helper.*` | The game helper, with its parts for input, checks and test set-up: when a game the editor started connects to the editor's debugger, the host writes a new token to GDatp's private cache and sends the helper's GDScript; the game compiles it only with that token, and only from a token file written after the game's process began (a game that takes minutes to reach its first frame is still admitted), and obeys tool calls for the rest of the run only with the same token, because any app on the phone can reach the debugger's port. Its `input` message presses actions and switches input on for a frame that stepping lets through, since suspending a game switches its input off |
| `BaseGodotEditor.kt` | Registers `GDatpPlugin` as a host plugin of the editor (not of the games it starts); asks for All files access once, from the editor, and never from a game |
| `editor/src/debug/` | `DebugCallReceiver`: calls the editor's tools from a computer in debug builds (below) |
| `gdatp/checks/bridge-check/` | A small project (a main scene, a scripted player, a label) used to check the tools on a phone |
| `gdatp/checks/tools_schema_check.py` | Holds `tools.json` to the form model providers receive: an object root, a type on every parameter, items on every array; a parameter without a type is sent as a string by some hosts and dropped by some providers. Every tool's description is at most 120 characters, since every request carries every definition |
| `gdatp/checks/atp_drop_check.py` | Holds the vendored ATP drop to its `SHA256SUMS`: every listed file matches its hash, and nothing else is in its folder but GDatp's two `build.gradle.kts` files and build output |
| `gdatp/tools/export_overlay.py`, `gdatp/tools/apply_to_godot.sh` | The published repository and its way back to a source tree: the export writes every file GDatp adds or changes, as committed, with `gdatp/overlay.sha256`; the apply script clones Godot's tag, checks its commit, and copies and checks each listed file |
| `platform/android/java/third_party/atp/` | ATP's wire module and provider kit, vendored as identical bytes from the ATP drop (its `README.md` and `SHA256SUMS`); the two `build.gradle.kts` files are GDatp's own |
| `editor/src/main/res/xml/atp_provider.xml`, `res/values/gdatp_atp.xml` | What an app reads before it connects: one server, and the groups `read`, `edit` and `run`, which the consent screen may grant, and `exec`, which it may not |
| `editor/src/main/assets/gdatp/tools.json`, `GDatpTools.kt` | The tools as ATP offers them, in MCP's own `tools/list` shape. `status` and the project tools answer from Kotlin, with or without an editor; every other tool is run by the tool host through `GDatpPlugin.call`, after the editor is brought on screen |
| `editor/src/main/assets/gdatp/instructions.md` | How the tools fit together when a model builds a game: small checked steps, read before changing, run and check after each change, art as SVG, feel and sound. Sent as MCP's server `instructions` with every channel's `initialize` (the kit's limit is 8,000 characters); a host may give it to its model as GDatp's own text. Every tool and action it names must exist in `tools.json` |
| `editor/src/main/java/com/gd/atp/GDatpProjects.kt` | The projects GDatp can open (its own `files/projects`, the Project Manager's `projects.cfg`, and shared Documents with All files access), and new ones made from a template (`2d`, `3d`, `empty`) as Godot's Project Manager would write them |

## Tools so far

| Tool | Ops |
| --- | --- |
| `status` | the editor's state: project, open, current and unsaved scenes, the script editor's unsaved scripts and text files, readiness, the run, the selection, the errors logged and how many since the last `status`, and the versions of Godot, GDatp (`gdatp`) and the ATP spec (`atp_spec`); with `request_id`, whether that write landed. With no project ready, GDatp answers itself: `closed`, `not_on_screen`, `project_manager`, `loading_project` or `restarting`, with the projects and the next step; a project opening on screen is waited for, up to 30 s, as the other tools wait for it, and within a minute of `project_open` the restarting editor and the project's import are waited for too, up to 30 s in all (a marker in GDatp's cache, `gdatp/opening`; the wait polls the host's status with `readiness_only`, which leaves the error count alone), so one call answers once the project is ready rather than `closed` or `importing` |
| `projects` | the projects GDatp can open, newest first: name, path, main scene, last change. With `project`, that project's renderer, file, scene and script counts, size (Godot's `.godot` import cache left out) and whether it is in GDatp's storage; with `deleted: true`, the projects in GDatp's trash, each with the time it was deleted and the time it is kept until |
| `projects_edit` | `rename` (the `config/name` in `project.godot`; the folder keeps its name), `duplicate` (a copy in GDatp's storage without `.godot`, which the editor rebuilds on opening, refused when the phone would keep less than 256 MiB free; listed in the Project Manager), `delete` (a project in GDatp's own storage moves to `files/projects-trash/<folder>@<time>` and leaves the Project Manager's list; one elsewhere is the person's to remove) and `restore` (the most recently deleted project of that name or folder, back into GDatp's storage and the list). The trash keeps a project 30 days; older ones are removed when the trash is next read or written. `rename` and `delete` refuse the project open in the editor (`project_open`), and refuse when GDatp cannot tell which project is open (`not_checked`). Needs no open project |
| `parts` | tested systems a game is built on, carried in the app and copied into `res://parts` on `add`, from `assets/gdatp/parts/`: `list`, `add`, `show`. `project_create` places the ones nearly every game needs, because a model left to think of them often does not. |
| `guide` | how to make games: a list of topics, or one topic: `start`, `ideas`, `study`, `assets`, `genre_*`, `style_*`, `sys_*`, from `assets/gdatp/guide/`. Needs no open project. |
| `project_create` | a new, empty project, `template` `2d` (default), `3d` (a light, an environment and a camera) or `empty`; `orientation` `landscape` or `portrait`, `pixel_art`, `renderer` `compatibility` (default), `mobile` or `forward_plus`; with the settings Godot's Project Manager gives every new project (`EditorNode::get_initial_settings()`: `canvas_items` stretch, Jolt Physics for 3D, Direct3D 12 on Windows) and the files it writes: `icon.svg` (the engine's `editor/icons/DefaultProjectIcon.svg`, copied into the assets by the `copyEngineAssets` build task), `.gitignore`, `.gitattributes`, `.editorconfig`; opened unless `open: false`, and listed in the Project Manager |
| `project_open` | opens a project by name or path, refused with a code to confirm with, since a model told a new game needs a new project still opened an earlier one with the same name, and set a flag in the schema without reading anything; with the editor closed it starts into it, and with another project open the editor restarts into it, as Godot does to switch projects. A project with unsaved scenes, scripts or text files (`status` lists `unsaved_scenes` and `unsaved_scripts`) is not switched away from: the call answers `unsaved_work` with the list, and the person saves or discards them first. `project_create` with `open` follows the same rule. The restart ends GDatp's process (Godot's `ProcessPhoenix`) a few seconds after the answer; a call that reaches the old process in that time runs nothing: `status` answers `editor: restarting`, and every other tool but `projects` fails with `restarting`, rather than acting on the project being closed or being cut off with its outcome unknown |
| `project_read` | `info`, `settings` (by prefix), `input_map` (the project's actions; `builtin: true` adds Godot's own), `autoloads` |
| `files_read` | `list`, `read` (line ranges), `search` (text or regex); any file is text unless its kind is binary (images, sounds, models, fonts, binary scenes and resources) or it has a NUL byte in its first 8 KB; answers name the open project |
| `scene_read` | `tree` (open or closed scenes, a closed one from its saved state; the Scene dock's warnings per node), `node` (changed properties, groups, saved connections, warnings) and `find`, both on a closed scene too, which is built from its file, read and freed; `spatial` reads 3D places and sizes, what the camera sees, and what floats or overlaps. |
| `scene_edit` | a list of steps as one undo step named "NuJan: …": `new_scene` first, then `add` (a class, a script class or a scene to instance), `set`, `remove`, `rename`, `move`, `duplicate`, `attach_script`, `connect`, `disconnect`, `group_add`, `group_remove`; values typed from JSON (`[x, y]`, `#rrggbb`, `"res://…"`, `{"type": "CircleShape2D", "radius": 16}`, transforms as `{origin, rotation_degrees, scale}`, layers as numbers or names) and read back; `set` takes indexed paths such as `shape:size` and `modulate:a`; saved by default; another scene only with `open: true` |
| `script_edit` | `create`, `replace`, `patch` (edits applied in order: exact `old`/`new` found once, or every match with `all`; `line`/`text` inserts before a line; `delete_from`/`delete_to` removes lines); refused with every compile error, each with its line and column, when the code does not compile, and nothing is written; a written script's warnings come back with it, and a `class_name` another script holds is an error |
| `run` | `play` (`main`, `current` or a path; answers `live`, `break` with the error, `not_live` or `stopped`; `frozen` pauses it as it connects, after its first frame), `stop`, `restart`, `state`; `pause` and `resume` from the editor, as the Game view's suspend does, leaving the game's own pause alone; `step` (1 to 600 drawn frames); `step_until` (frames until every check passes, as in `game_read check`, and the game stays paused there); both take `hold` (actions down for every frame) and `press` (actions down for the first frame, which counts as just pressed), let go at the end; `speed` (0.0625 to 16 times); `mute` |
| `undo` | `undo` and `redo` (NuJan's steps only, unless `any: true`; a step `scene_edit` saved is saved again when taken back or redone, so the file matches the editor), `history` (the scene's last 20 steps and `restorable`: the scripts, settings and files that can still be put back), `restore_file` (the text before NuJan's last script change; refused with `person_editing` while the script has unsaved changes in the script editor, as `script_edit` is), `restore_setting`. The restore history is kept per project in GDatp's storage (`files/gdatp-restore/<md5 of the project path>/`), so it outlives the editor and a project switch: entries from the last 30 days, at most 100 of each kind, and kept copies up to 256 MB, the oldest dropped first with their copies. Copies kept before the history existed are in `files/gdatp-trash/` and are not listed |
| `logs` | the editor's log, the Output panel (which also shows the game's prints) and the debugger's Errors tab |
| `screenshot` | `target` `editor`, `editor_2d`, `editor_3d` or `game`, at most `max_size` px, saved in GDatp's cache; `editor_2d` and `editor_3d` bring that view to the front first, since a hidden view draws nothing, and show `scene` first when given; the answer names the scene and says when that view of it is empty; a game's picture names its full size, which is the space input coordinates use. `game` with no game running starts one as `run play` does (`scene`, the main one when left out), lets it run a second, and says so in `started`: models stopped the game and then asked to see it, 18 of 31 failed looks in one run. `burst` takes 2 to 9 frames `every_ms` apart (33 to 2000, within 12 s) as one picture in reading order, each numbered in its corner, with each frame's `changed` (the share of a 96-cell-wide grid of brightness that moved; a still scene draws the same pixels, so any is real) and `where` (that part, in full_size pixels), a `summary`, and actions in `hold` down throughout and in `press` for the first frame; a paused game is refused, since every frame would be the same. `region` [x, y, width, height] in full_size pixels, or `around` a node's path (a control's or sprite's rectangle with room around it, else a square around its point, through the camera in 3D), shows only that part, enlarged up to four times in whole steps; only a whole frame is measured by the look check, so a region clears no finding |
| `exec` | GDScript in the editor, or with `target: game` in the running game; `return` sends a value back, and prints are captured in the editor. In the editor it runs under a time limit (`seconds`, 30 by default, at most 240): once it passes, the VM ends a loop in the code at its next turn with the error "Stopped: the code ran past its time limit." and the result says `stopped`. Only the code's own loops are stopped; a long call into the engine runs on, and code still waiting on a signal or a timer a second past the limit is answered `timeout` and left waiting, so the next exec can run. Over ATP, GDatp waits for the answer as long as the limit and 10 s more, and at least 40 s |
| `input` | plays the running game: steps of `tap` (`[x, y]` or a node's path), `swipe` and `touch` (with a finger `index`, so a held joystick and a button work together), `mouse` (button, double), `action`, `key`, `hold` and `release` (an action or a key left down across steps, let go at the end unless `keep_held`), `text` (into the focused control), `wait_ms`, `wait_frames`, `wait_until` (checks, with a timeout that stops the steps); each step says what it hit, and `observe` reads nodes afterwards. One call's steps take at most 50 s, each wait and hold counted in full and frames at the game's frame rate (20 to 60 a second), so the editor's 60 s wait covers them; a longer list is refused with `too_long` before its first step. A place is in the game window's pixels (the screenshot's `full_size`); a node's path is placed where the project's stretch draws it, at the middle of a control and of a touch button's shape |
| `game_read` | the running game as data: `tree`, `node` (changed properties; `on_floor` and `velocity` for character bodies, `linear_velocity` and `sleeping` for rigid ones, overlapping bodies for areas; `properties` reads named values, indexed or engine getters such as `is_on_floor`), `find` (nodes by `class` or script class, `name` part or pattern, `group`, `text`, with their places, a 2D node's `on_screen` point in window pixels too, for nodes a script made), `ui` (visible controls with text, rectangle in window pixels, disabled), `audio` (each bus's volume, mute and loudest level in the last frame; each audio player, whether it is playing and where), `watch` (the `nujan_watch` group), `monitors`, `check` (pass or fail per check: a node's property, or a group's count, against `equals`, `not_equals`, `near` with `tolerance`, `gt`, `lt`, `contains` or `exists`), `sample` (up to 8 values over 1 to 300 physics frames, with first, last, lowest and highest) |
| `game_edit` | sets up a test in the running game, saved nowhere: `set` (typed and read back), `call` (a method of the node or its script, arguments typed to its parameters, a node argument by path; `free` and `set_script` are refused), `spawn` (a scene or a node class, with properties), `remove`, `reload`, `change_scene`, `pause` (the game's own pause) |
| `docs` | this editor's own class reference: `class` (summary, properties, method and signal signatures with a line each; `filter`), `member` (`Class.member` in full), `search` (class names); Godot 3 names are answered with their Godot 4 names |
| `project_edit` | `setting_set` (typed to the setting's own type), `main_scene_set`, `input_action_set` (keys, mouse and joypad events, merged), `input_action_remove`, `autoload_add`, `autoload_remove`; through ProjectSettings, saved, each change one step "NuJan: <key>" of the editor's own history, so the person's undo in the editor takes it back as `undo restore_setting` does |
| `files_edit` | `write` (text, or base64 for images and sounds, which are imported before it answers; a `.gdshader` or `.gdshaderinc` is checked first as the shader editor checks it, `GDatpEditorPlugin::check_shader`, and refused with `does_not_compile`, its line and every error, when it does not compile, its warnings listed when it does), `mkdir`, `move` (a file or folder, through the FileSystem dock's own move, `FileSystemDock::move_path`: its `.import` and `.uid` go with it, and the scenes, resources and project settings that refer to it are rewritten, listed as `updated`; scripts whose text still names the old path are listed as `scripts_naming_old_path`; refused with `person_editing` while an open scene that refers to it has unsaved changes, since the move would save them), `delete` and an overwriting `write` (the earlier file is kept in the restore history), `restore` (refused with `open_in_editor` while the file is an open scene, and with `person_editing` while it has unsaved changes in the script editor); scripts go through `script_edit` and open scenes through `scene_edit` |
| `tilemap_edit` | `tileset_create` (a TileSet from an atlas image: a tile per non-empty cell of `tile_size`, each with a square collision shape unless `collision: none`), `layer_add` (a TileMapLayer), `cells_set`, `rect_fill`, `map_from_ascii` (rows of marks and a legend of atlas cells), `erase`, `clear`, `read` (the layer as text with its legend, and the TileSet's tiles) |
| `animation_edit` | `frames_from_sheet` (SpriteFrames for an AnimatedSprite2D or 3D from a sheet: rows, runs or lists of frames, fps, loop, the animation that plays), `player_add`, `clip_create`, `track_add` (a value track, keys typed to the property), `preset` (`bob`, `pulse`, `spin`, `fade_in`, `fade_out`, `blink`, `shake`), `clip_remove`, `read`; `autoplay` |
| `ui_edit` | `build` (a Control tree from one description: anchors, size flags, minimum sizes, theme colours, font sizes, constants and flat styles), `anchor`, `touch_button` (a TouchScreenButton drawn as a circle, pressing an input action, anchored to a corner of the screen, pressed too by a thumb sliding onto it), `touch_joystick` (Godot's VirtualJoystick), `read` (rectangles, text, and what is outside the screen) |
| `resource_edit` | any Resource by class and properties: `create` (a .tres), `set`, `call` (such as `Curve.add_point`, arguments typed to the method), `duplicate`, `read`; in a file (kept in GDatp's trash first) or held by a node of the open scene (`node`, `property`, one undo step) |
| `audio_edit` | `sfx` (a WAV from a `preset`, `jump`, `land`, `coin`, `powerup`, `hit`, `stomp`, `explosion`, `laser`, `blip`, `win` or `lose`, or from `wave`, `from`, `to`, `ms`, `steps`, `step_ms`, `volume`), `music` (a looping WAV from a `mood`, `happy`, `calm`, `tense`, `dark` or `heroic`, with `tempo`, `bars`, `key_hz`, `seed`; its `smpl` chunk marks the loop). Mono 16-bit at 22,050 Hz, written into the project and imported, with no download and no key |
| `world3d_edit` | `environment` (a procedural sky or a colour, ambient light, fog, glow, tone mapping; says what Compatibility does not draw), `light` (`sun`, `omni`, `spot`), `primitive` (box, sphere, capsule, cylinder, plane, prism or torus in a colour, inside a static, rigid, area or character body with a matching collision shape), `csg` |
| `image_edit` | exact pixel art from rows of letters (`pixels`), `noise` and `gradient` textures, `look` shows the picture to the model, `info`, `palette` (its main colours), `resize`, `crop`, `flip`, `rotate`, `recolor`, `pixelate`, `sheet`. |
| `assets` | `search`, `look` (a preview picture) and `fetch` from Poly Haven, ambientCG, Godot's Asset Library, or an address found on the web. See Fetching assets below. |
| `export` | the open game as an APK anyone can install. See Exporting below. |

Each takes `op` and `params`; parameters written beside `op`, or `params` sent as a JSON string, are accepted too.
Paths stay inside `res://` and out of `.godot`. A write that names a `project` other than the open one is refused.

## Games are written for themselves

There are no game templates. Two complete games were tried as starting points, and every game then came out as one of them: a wrestling game
whose `DESIGN.md` still spoke of floating islands, with the template's gem, guard and portal files. What a model cannot build well from nothing is
taught instead, in `guide`, with working numbers and code: how each genre works, how to get each look, how each system is built, how to invent and how
to study a reference. The code blocks in it compile: `gdatp/checks` does not run them, so run them on a phone after changing them (each block through
`script_edit` or `files_edit` in a scratch folder).

What every game needs and a free model writes badly is ready as `parts`: touch controls, title and pause screens, sound, music, a sky, painted textures, hero controllers, tile levels and a voxel world. A part is a system with no game in it: no scene, no rules, no content, and `GDatpAudit` does not count its code as the game's. Each is one file, compiles with no warnings, and starts with `##` lines saying how to use it, which is what `parts add` answers with. The same free model that wrote a flat green blockout on its own gets textured land, a sky and real controls from a hundred lines over parts, and two games from them share nothing a player can see. After changing a part, write it through `script_edit` on a phone and play it.

Three things hold a model to the job, since it follows what a tool says more surely than what it read earlier:

- `project_create` refuses a `2d` or `3d` project until `guide` topic `start` has been read.
- Each screenshot of the running game also measures the frame (`_look_check` in the game helper): a flat colour over a quarter of it, the engine's default grey, a nearly black frame, bare surfaces in 3D, text too small,
  off the screen or on top of other text. What it finds stays under `unfinished` until a later look at that scene finds otherwise. Its `look_for` is what a host's vision model should be asked: judged rather than described, a broken frame is called broken. A burst's `look_for` asks what happens across its frames: what should move and does not, flicker, a jump, something that vanishes. Each answer's `next` names the tool that goes further: a burst that found a change points to `region` on it and `game_read find`, one that found none to `game_read sample` and `input`.
- A game run from the editor keeps the shape its project says (`_keep_project_shape`), with bars beside it when the editor's window is the other way round, so a test shows what ships.
- `run try` starts the game, taps the button that begins it, plays 24 game seconds in 6 with a person's moves (walking, looking, pressing under the right thumb, answering a menu) and lists what broke: a `run play` only reaches the first screen, so code that runs once play has begun, such as a spawn timer, meets no check otherwise. Until a try has passed on the code as it stands, `unfinished` says so, in the answer to each edit too, so a host that holds a model to `unfinished` sends it back to play what it just changed.
- When nothing broke, `run try` starts the game again through its first screen, so a screenshot after it shows what a player first sees.
  The moves leave a game wherever they took it: a voxel game whose try flew its player up into a night sky had that frame judged as 92%
  one flat colour after every try, and its model could never clear the finding.
- `run` and `logs` give GDScript's warnings as `warnings`, apart from `errors` (`_add_game_reports`): they name a habit of the code and the game runs on, so a model is not sent to tidy code that works.
- `edit` takes the names models give its two texts besides `old` and `new` (`new_text`, `old_string`, `search`, `replacement` and the like, `_edit_in_our_words`), a `line` given beside them says which match is meant, a line 0 or an empty text is a slot filled in for the sake of it and is dropped, and `{delete_from, delete_to, new}` replaces those lines, because a refused edit sends a weak model round the same call until a guard stops the turn.
- A call under way when the editor leaves the screen is answered at once with `left_the_screen`: the editor's main loop stops with it, so the call would otherwise wait out its whole time limit, two minutes for a `run`, for an answer that cannot come. A person looking at the chat during a turn does exactly this.
- `GDatpAudit` lists a script that is an autoload and also on a node in a scene: it runs twice, with its own copy of everything it makes, and taps land on one copy while the other shows. It also lists a script reading both `InputEventScreenTouch` and `InputEventMouseButton`, unless the project turns `emulate_mouse_from_touch` off or the script asks `is_touchscreen_available`: a phone sends each tap as both, so a toggle tapped once ends where it started, and no run reports an error.
- `GDatpAudit` also lists code that never runs: a script nothing loads, and a `has_method` check for a method no running script has. A feature written this way fails silently, so no error reports it. Reading the guide and studying are asked for only until the game has its first 200 lines: they shape a game before it is written, and on a follow-up change they only delay it. What counts as studied is read from the file's first bytes, because a marker file passed the older check.
- Each `run` that starts the game answers with `unfinished`, from `GDatpAudit`: what its files lack of a complete game. A host may hold a model to
  that list; NuJan sends a model that stops with it non-empty back once each time the list is shorter than it has been, as it does for any tool that gives one.
- A tool that changes a scene refuses unless it is told which (`which_scene`), and naming one opens it. Working on whichever was open sent a model
  round in circles for 250 steps.

`projects` lists what earlier games' plans say they are, so a new one can differ.

## Exporting

`export` makes an APK with the engine's own Android exporter through `GDatpEditorPlugin::export_android`, signs it with a key made on this phone
(`GDatpExport`), and copies it to `Download/GDatp`.

With `install`, Android's installer asks the person once the host's turn ends (`turn_ended`, SPEC 7.5), for the last game the turn exported
(`GDatpInstallOffer`). A model exports as it goes: opening the installer on every export asked the person 31 times in one turn. The engine's
own exporter also opens the installer after every export while the editor setting `export/android/install_exported_apk` is on, which it is
by default, so a tool's export holds that setting off for its call and puts the person's value back after it (`_export_game`); an export from
the editor's own Project > Export still asks as the engine does. The installer
comes up at once when the editor is on screen, since Android lets only an app on screen open a screen, and otherwise the next time the editor
comes to the front, within 30 minutes. A host that names no turns never says one ended, so its export opens the installer at once. It needs the release template in the assets, which is not in git:

```bash
scons platform=android target=template_release arch=arm64 -j10 generate_apk=no
cd platform/android/java
JAVA_HOME="<path to JDK 17>" ./gradlew generateGodotTemplates
cp ../../../bin/android_release.apk editor/src/main/assets/gdatp/export/android_release.apk
```

## Fetching assets

`assets` searches Poly Haven and ambientCG (both CC0, with public interfaces; Poly Haven asks that calls name the software and that its content be
credited, which `search` and the credits file do), Godot's Asset Library, and direct addresses a model found itself with the licence it read there.
Everything fetched for the game gets a line in `res://assets/CREDITS.md`. `into: study` places a project to read, or a picture to learn from, in `res://study/`, which Godot ignores, so it is
never built into a game and needs no licence line. `GDatpAudit` lists a game as unfinished until something is kept there: a `Studied:` line is not evidence on its own.

## Over ATP

GDatp is an ATP provider through the provider kit: an app on the phone (NuJan) connects once, with the person's
consent on the kit's screen, and lists and calls the tools above. NuJan names them as it names any app's, `atp_gd_<tool>` for a new
connection, from the package name, and knows nothing else about GDatp.

| Group | Tools | At consent |
| --- | --- | --- |
| none | `status` | always |
| `read` | `projects`, `project_read`, `files_read`, `scene_read`, `docs`, `logs`, `game_read`, `screenshot` | granted |
| `edit` | `project_create`, `project_open`, `projects_edit`, `scene_edit`, `script_edit`, `files_edit`, `project_edit`, `undo`, `tilemap_edit`, `animation_edit`, `ui_edit`, `resource_edit`, `world3d_edit` | granted |
| `run` | `run`, `input`, `game_edit` | granted |
| `exec` | `exec` | off; the consent screen cannot grant it. The person turns it on per app in Connected apps, which asks again first |

Connected apps is the kit's screen (`AtpConnectionsActivity`): each app connected to GDatp, a switch per group, and
Disconnect. It opens from GDatp's launcher icon (long-press, `res/xml/gdatp_shortcuts.xml`), from the gear on GDatp's
page in Android's app settings (`APPLICATION_PREFERENCES` in the manifest), or from a host for the person
(`com.nujan_agent.atp.action.CONNECTED_APPS`). The consent screen and a refused call name it through
`atp_grants_place`.

- The editor runs tools only while it is on screen and a project is open. A tool that needs it brings it to the front
  first, through the kit's UI hand-off (ATP `SPEC.md` 9.1): GDatp asks, and NuJan starts GDatp's editor screen while
  NuJan itself is on screen. A tool then waits up to 30 s for a project that is still opening; in the Project Manager
  it answers `no_project` with the projects to open. A person and NuJan work side by side: NuJan's turn goes on in the
  background while GDatp is in front.
- Opening another project restarts the editor's process, as Godot's own project switch does, and the ATP channel
  closes with it; NuJan binds again on its next call. The answer is sent before the restart.
- `screenshot` is offered over ATP with its picture attached as MCP image content, 1024 px on its
  longest side unless the call names `max_size`; the host's vision model reads it with the call's `question`. The
  file in GDatp's cache is deleted once it is attached.
- Changing the definitions: edit `tools.json` (a tool's description at most 120 characters, its detail in its
  parameters' descriptions; every array with its `items`), then run `gdatp/checks/tools_schema_check.py`; the tool
  host is what runs them.
- Updating the kit: export a newer drop from the ATP repository (https://github.com/nujanAgent/atp) with
  `tools/export-drop.ps1 -Tag <tag> -Dest <this repo>/platform/android/java/third_party/atp`.

## Calling the editor's tools from a computer

In a debug build, with a project open in the editor:

```bash
adb shell am broadcast -n com.gd.atp/com.gd.atp.DebugCallReceiver --es tool status --es args '{}'
```

The answer is the broadcast's `data`, as JSON. Only the shell may send it (the receiver requires `DUMP`).
Without an editor running the answer is `no_editor`; with the editor off screen, `not_on_screen` (its main loop
does not run then); in the Project Manager, `no_project`; after 8 s without an answer, `timeout`.

To run the bridge check: install the debug APK, copy `gdatp/checks/bridge-check` into GDatp's own storage
(`adb push` to `/data/local/tmp`, then `run-as com.gd.atp cp -r` into `files/projects/`), open it with
`adb shell am start -a android.intent.action.VIEW -d file:///data/user/0/com.gd.atp/files/projects/bridge-check/project.godot -n com.gd.atp/org.godotengine.editor.ProjectManager`,
and call `status`: it answers with the project's name, the open scenes and `"on_main_thread": true`. Without All
files access GDatp cannot read files adb wrote in shared storage, which is why the check lives in its own storage.

With arguments, use `gdatp/tools/gdcall.sh`, which quotes them for the phone's shell (a plain `adb shell` call
loses the JSON's double quotes there):

```bash
gdatp/tools/gdcall.sh <serial> scene_read '{"op":"tree","params":{"scene":"res://main.tscn"}}'
```

## Building

Run these in a Godot `4.7.2-stable` tree with GDatp's files over it, which `sh gdatp/tools/apply_to_godot.sh <new
folder>` makes from this repository. The published repository is written by `gdatp/tools/export_overlay.py`: every
file GDatp adds or changes, as committed, with `gdatp/overlay.sha256` listing each one's SHA-256.

Needs the Android SDK with NDK `29.0.14206865`, build-tools `36.1.0` and platform 36; JDK 17; Python 3 with SCons 4
(`uv tool install scons --python 3.12`); and Swappy, Android's frame pacing library (Apache-2.0, already in
`COPYRIGHT.txt`), whose prebuilt libraries Godot's own script downloads into `thirdparty/swappy-frame-pacing/`, where
git ignores them.

```bash
export ANDROID_HOME="<path to the Android SDK>"
python misc/scripts/install_swappy_android.py           # once: godot-swappy.zip, 7.0 MB, the release Godot pins
python gdatp/checks/tools_schema_check.py               # every tool parameter typed, every description short
python gdatp/checks/atp_drop_check.py                   # the vendored ATP drop exactly as exported
scons platform=android target=editor arch=arm64 -j10   # the editor library, optimized, without LTO
cd platform/android/java
rm -f editor/build/outputs/apk/android/debug/*.apk     # the packager reuses an old APK and grows it with every build
JAVA_HOME="<path to JDK 17>" ./gradlew generateGodotEditor        # JDK 17 itself: on 21 this says BUILD SUCCESSFUL and builds nothing
adb install -r ../../../bin/android_editor_builds/android_editor-android-debug.apk
```

`target=editor` without `dev_build` or `production` puts the library in `lib/libs/tools/debug/`, which the Gradle
debug build packages: optimized native code, a debuggable app. A store build would add `production=yes` (LTO) and the
release build type with GDatp's own signing key.

Swappy paces frames only for the Vulkan renderers (the editor's own drawing, and games on Mobile or Forward+); games
on the Compatibility renderer, which new projects in GDatp get, draw through OpenGL ES without it.

## Its own name and look

The Godot Foundation's trademark policy (https://godot.foundation/policies-and-procedures/trademark-policy) lets software
made with Godot say so, and reserves the Godot logo, or anything derived from it, as the logo of Godot alone. So GDatp
looks like GDatp wherever it speaks for itself, and names Godot where it describes what it is made with:

- The launcher icon: an orange game pad cross with a white editing pointer, as vectors on the adaptive icon grid with a
  one-colour layer for themed icons (`editor/src/main/res/.../gdatp_icon*`).
- The same mark, on its dark square, in the editor's icons (`editor/icons/Logo.svg`, `TitleBarLogo.svg`, `Godot.svg`):
  the About box, the Project Manager's corner button, and the About item of the Help menu.
- The editor's start-up splash (`main/splash_editor.png`, used because `no_editor_splash` defaults to off): the mark,
  "GDatp", and "made with Godot Engine". Games keep Godot's own splash, which the policy encourages them to show.
- The About box is "About GDatp": GDatp's name and line, "Made with" Godot's version, Godot's copyright and credits in
  full, and "GDatp is not affiliated with or endorsed by the Godot Foundation."
- Help's "Report a Bug" and "Suggest a Feature" open GDatp's issues, since a problem met in GDatp is GDatp's to sort out
  first; the documentation, forum, community and "Support Godot Development" stay Godot's.
- The Project Manager does not check for new Godot releases (`engine_update_check` defaults to off): a Godot update is
  not a GDatp update.
- A new project's icon is a plain play sign on slate (`editor/icons/DefaultProjectIcon.svg`), neither Godot's logo nor
  GDatp's, since an exported game is neither.
- The game's window is labelled "GDatp game window".

The engine's name stays in `version.py`: the version line, the log's first line, Vulkan's engine name and the note on a
material converted to a shader say what the editor is made with. An Android export of a project with no name of its own
is also called by it (`platform/android/export/export_plugin.cpp`), which `project_create` avoids by always naming one.

## Not in this build

- Perfetto (tracing), which Godot's official builds include (`misc/scripts/install_perfetto.py`).
