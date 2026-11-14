extends RefCounted
## Keeps what a player earned between runs, in one file, with a best score ready to use.
## Use:
##   const Save = preload("res://parts/save.gd")
##   Save.put("level", 3)                  # written to the phone at once
##   Save.value("level", 1)                # what was kept, or the default
##   Save.best("score", 120)               # keeps the higher number and returns it
##   Save.has_save()                       # true once anything has been kept
##   Save.clear()

const PATH := "user://save.dat"

static var _data := {}
static var _read := false


static func put(key: String, stored: Variant) -> void:
	_load()
	_data[key] = stored
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_var(_data)


static func value(key: String, fallback: Variant = null) -> Variant:
	_load()
	return _data.get(key, fallback)


static func best(key: String, score: float) -> float:
	var kept := float(value(key, 0.0))
	if score > kept:
		put(key, score)
		return score
	return kept


static func has_save() -> bool:
	_load()
	return not _data.is_empty()


static func clear() -> void:
	_data = {}
	_read = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func _load() -> void:
	if _read:
		return
	_read = true
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file != null:
		var kept: Variant = file.get_var()
		if kept is Dictionary:
			_data = kept
