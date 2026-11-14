# Saving data and keeping content as data: ConfigFile, JSON, versions and Resources

`parts add save` keeps values and a best score in one file.

**Saving.** Use `user://`, which lasts between runs. `ConfigFile` suits settings and scores, and it can store dictionaries:
```gdscript
extends Node

const PATH := "user://save.cfg"
const VERSION := 1
var data := {"best": 0, "unlocked": 1, "sound": true}


func load_save() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	if int(file.get_value("meta", "version", 0)) != VERSION:
		return
	var saved: Dictionary = file.get_value("game", "data", {})
	data.merge(saved, true)


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("meta", "version", VERSION)
	file.set_value("game", "data", data)
	file.save(PATH)
```
Merging over defaults means an older save still works after you add a field. Bump the version only when a change cannot be merged.

**When to save:** on any meaningful change, and on `NOTIFICATION_APPLICATION_PAUSED`, since a phone may kill a paused app without warning. Do not save each frame. For a long run, save enough to resume at the last checkpoint.

**Testing:** the tools run the game repeatedly, and an old save may mask a bug. Delete it when a clean start is needed, using `game_edit` with a call, or an `exec` with `DirAccess.remove_absolute("user://save.cfg")`. Play once from clean, every time before reporting.

**Content as data** is what lets a game grow. Enemies, levels, cards, items and waves live in dictionaries, text or `Resource` files, not code branches. Then a new enemy is one row, and balance is one number.

```gdscript
const ENEMIES := {
	"runner": {"health": 20, "speed": 140.0, "bounty": 3},
	"tank": {"health": 120, "speed": 50.0, "bounty": 10},
}
```

**Custom Resource** when values should be files to edit or share:
```gdscript
class_name WeaponData
extends Resource

@export var title := "Pistol"
@export var damage := 10
@export var seconds_per_shot := 0.3
```

**Levels as text** are easy to write, read, change and print. A short key maps letters to scenes or tiles. Levels stay short enough to reason about, as they are entirely visible at once. For larger maps use `tilemap_edit`.

**Keep the balance in one place** and name your numbers, so that a tuning pass is a single small edit. Note what you measured in DESIGN.md.
