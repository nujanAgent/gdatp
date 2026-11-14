# Godot 4 traps: Godot 3 habits that fail here, typing rules, and mistakes that recur

Look up anything uncertain with `docs`, rather than guessing from memory; older tutorials are often Godot 3.

**Renamed in Godot 4:**
| Godot 3 | Godot 4 |
| --- | --- |
| `KinematicBody2D`, `move_and_slide(v)` | `CharacterBody2D`, set `velocity`, then `move_and_slide()` |
| `Spatial`, `translation` | `Node3D`, `position` |
| `yield(x, "done")` | `await x.done` |
| `onready var`, `export var` | `@onready var`, `@export var` |
| `scene.instance()` | `scene.instantiate()` |
| `connect("pressed", self, "f")` | `pressed.connect(f)` |
| `rand_range(a, b)`, `randi() % n` | `randf_range(a, b)`, `randi_range(0, n - 1)` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `Tween.new()` as a node | `create_tween()` |
| `TileMap` | `TileMapLayer` |
| `PoolStringArray`, `PoolVector2Array` | `PackedStringArray`, `PackedVector2Array` |
| `deg2rad`, `stepify` | `deg_to_rad`, `snapped` |

**Typing that bites:**
- `var x := dict["a"]` fails: a Dictionary value has no known type. Use `var x: float = dict["a"]`.
- `:=` from `get_node()` gives `Node`. Write `var bar: ProgressBar = $Bar`.
- Integer division warns: `a / b` with ints. Write `a / float(b)`, or mark it with `@warning_ignore("integer_division")`.
- An unused parameter warns: name it `_delta`. An unused variable, too.
- A local variable with the same name as a member warns (shadowing).
- Warnings count as errors in a run here, so keep scripts clean.

**Input:** an action must exist in the project (`project_edit`) before code asks about it, or it errors each frame. Touch handlers need `InputEventScreenTouch` and `InputEventScreenDrag`, and `event.index` for fingers.

**Physics:** move `CharacterBody` in `_physics_process`, not `_process`. Change a `RigidBody` by impulses. Set collision layers and masks: a body detects only what its mask names, the classic cause of "they pass through each other". An `Area` needs `monitoring` on, and signals connected.

**Nodes:** `@onready` and `$Path` run on entering the tree; calling methods on an instance before `add_child` finds them null. `queue_free` happens at the end of the frame; check `is_instance_valid`. Do not add or free physics nodes inside physics callbacks: use `call_deferred`.

**Scenes:** `change_scene_to_file` frees the current scene at the end of the frame; awaited code in it does not carry on. Autoloads survive, and hold state that must be reset on replay.

**3D:** the forward direction is `-transform.basis.z`. A camera looks along its negative Z. `look_at` fails if the target is at the same position, or straight up. A mesh has no collision unless given a shape. A `CSG` shape needs `use_collision` on.

**Pausing:** `get_tree().paused` stops the UI as well, unless `process_mode` says otherwise. `Engine.time_scale` affects timers, unless told to ignore it.

**Android:** `user://` is writable and `res://` is read-only in an exported game. Do not write to `res://` at runtime.

**Files here:** always use `script_edit` for scripts, as it checks compile errors. Do not edit `.import` files; delete a file via `files_edit`, which also handles its import data.
