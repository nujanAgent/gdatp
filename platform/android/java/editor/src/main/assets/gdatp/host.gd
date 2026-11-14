@tool
extends Node

## GDatp's tool host. The editor runs it in every project it opens, and it carries out the tools NuJan calls through
## the GDatp singleton: each call arrives as `call_arrived` on the main thread and is answered with `reply`, as JSON.
## Tools take an `op` and its parameters; answers say what to do next, and errors name the fix. Every change NuJan makes
## to a scene is one undo step named "NuJan: …", taken whole or not at all.

const TOOLS := {
	"status": "_status",
	"project_read": "_project_read",
	"files_read": "_files_read",
	"scene_read": "_scene_read",
	"scene_edit": "_scene_edit",
	"script_edit": "_script_edit",
	"run": "_run",
	"undo": "_undo",
	"logs": "_logs",
	"screenshot": "_screenshot",
	"exec": "_exec",
	"input": "_play_input",
	"game_read": "_game_read",
	"game_edit": "_game_edit",
	"docs": "_docs",
	"project_edit": "_project_edit",
	"files_edit": "_files_edit",
	"tilemap_edit": "_tilemap_edit",
	"animation_edit": "_animation_edit",
	"ui_edit": "_ui_edit",
	"resource_edit": "_resource_edit",
	"world3d_edit": "_world3d_edit",
	"audio_edit": "_audio_edit",
	"image_edit": "_image_edit",
	"assets_placed": "_assets_placed",
	"export_game": "_export_game",
}

## Godot 3 class names that models trained on older tutorials still use, and what each is called in Godot 4.
const RENAMED_IN_GODOT_4 := {
	"KinematicBody2D": "CharacterBody2D", "KinematicBody": "CharacterBody3D", "Spatial": "Node3D", "Sprite": "Sprite2D",
	"AnimatedSprite": "AnimatedSprite2D", "Position2D": "Marker2D", "Position3D": "Marker3D", "RayCast": "RayCast3D",
	"CollisionShape": "CollisionShape3D", "CollisionPolygon": "CollisionPolygon3D", "Area": "Area3D",
	"RigidBody": "RigidBody3D", "StaticBody": "StaticBody3D", "MeshInstance": "MeshInstance3D", "Camera": "Camera3D",
	"DirectionalLight": "DirectionalLight3D", "OmniLight": "OmniLight3D", "SpotLight": "SpotLight3D",
	"Particles": "GPUParticles3D", "Particles2D": "GPUParticles2D", "CPUParticles": "CPUParticles3D",
	"NavigationAgent": "NavigationAgent3D", "YSort": "Node2D (with y_sort_enabled)", "TileMap": "TileMapLayer",
	"VisibilityNotifier2D": "VisibleOnScreenNotifier2D", "VisibilityEnabler2D": "VisibleOnScreenEnabler2D",
	"ToolButton": "Button (with flat)", "Listener": "AudioListener3D", "GIProbe": "VoxelGI", "BakedLightmap": "LightmapGI",
	"ViewportContainer": "SubViewportContainer", "Viewport": "SubViewport", "Tween": "a Tween from create_tween()",
}

const IMPORTED_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "wav", "ogg", "mp3", "glb", "gltf", "obj", "fbx", "ttf", "otf", "woff", "woff2"]
const MAX_WRITE_BYTES := 8 * 1024 * 1024

const SCENE_OPS := ["add", "set", "remove", "rename", "move", "duplicate", "attach_script", "connect", "disconnect", "group_add", "group_remove"]
## Files that are never text, passed over without opening them; any other file is text when it has no NUL byte.
const BINARY_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "exr", "hdr", "ktx", "dds", "wav", "ogg", "mp3",
	"glb", "fbx", "blend", "ttf", "otf", "woff", "woff2", "scn", "res", "ctex", "zip", "pck", "so", "mp4", "webm", "ogv"]
const UNDO_PREFIX := "NuJan: "
const MAX_READ_CHARS := 20000
const MAX_LIST := 500
const MAX_HITS := 50
const RECENT_OUTCOMES := 100
## How long exec's code may run in the editor before a loop in it is stopped, unless the call asks for another limit.
const EXEC_SECONDS := 30.0
const EXEC_SECONDS_MAX := 240.0
## How long past its limit exec waits for code whose loop the limit stopped to return, before it answers that the code
## is waiting on a signal or a timer, which the limit does not stop.
const EXEC_GRACE_SECONDS := 1.0
## A picture's longest side when the call names none: enough for a vision model to read a game's text.
const SHOT_SIZE := 1024
## How much restore history a project keeps: entries from the last RESTORE_DAYS, at most RESTORE_ENTRIES of each kind,
## and kept file copies up to RESTORE_COPY_BYTES; the oldest go first, with their copies.
const RESTORE_DAYS := 30
const RESTORE_ENTRIES := 100
const RESTORE_COPY_BYTES := 256 * 1024 * 1024

var _bridge: Object
var _logger: _Capture
var _debugger: _Debugger
var _outcomes := {}
var _outcome_order: Array = []
var _file_backups: Array = []
## Where the last logs read of each source ended: an editor entry's number, and the Output panel's and the Errors tab's
## length, last item and run, so since_last returns only what is new.
var _logs_read := {"editor": 0, "output": {"count": 0, "last": "", "run": 0}, "errors": {"count": 0, "last": "", "run": 0}, "warnings": {"count": 0, "last": "", "run": 0}}
var _run_id := 0
var _run_by_nujan := false
var _game_token := ""
var _game_call_id := 0
var _setting_backups: Array = []
## With _file_backups and _setting_backups, the restore history: what NuJan changed, deleted or overwrote, kept in
## GDatp's own storage so it outlives the editor.
var _trash: Array = []
var _copy_serial := 0
## The names of NuJan's scene steps that scene_edit saved, so taking one back or redoing it saves the scene too.
var _saved_steps := {}
## Whether exec's code is running in the editor; one runs at a time, under one time limit.
var _exec_running := false
## Numbers each exec, so code that returns after its call was answered is told apart from the exec under way.
var _exec_serial := 0
## What the code of the exec under way returned, as {"value": …}; empty until it returns.
var _exec_returned := {}
## How many errors the editor had logged at the last status, so the next one says how many are new.
var _status_errors_seen := 0


func _ready() -> void:
	if not Engine.has_singleton("GDatp"):
		return
	_logger = _Capture.new()
	OS.add_logger(_logger)
	_debugger = _Debugger.new()
	_debugger.host = self
	get_parent().add_debugger_plugin(_debugger)
	_bridge = Engine.get_singleton("GDatp")
	_load_restore_history()
	_bridge.connect("call_arrived", _on_call_arrived)
	_bridge.hostListening()


func _exit_tree() -> void:
	if _bridge and _bridge.is_connected("call_arrived", _on_call_arrived):
		_bridge.disconnect("call_arrived", _on_call_arrived)
	_bridge = null
	if _logger:
		OS.remove_logger(_logger)
	if _debugger and get_parent():
		get_parent().remove_debugger_plugin(_debugger)


func _on_call_arrived(id: String, tool: String, args_json: String) -> void:
	var answer: Dictionary
	var parsed = JSON.parse_string(args_json) if not args_json.strip_edges().is_empty() else {}
	if typeof(parsed) != TYPE_DICTIONARY:
		answer = _fail("bad_arguments", "The arguments must be a JSON object.")
	elif not TOOLS.has(tool):
		answer = _fail("unknown_tool", "There is no tool named '%s'." % tool, {"tools": TOOLS.keys(), "did_you_mean": _nearest(tool, TOOLS.keys())})
	else:
		var args := _repaired(parsed)
		answer = _project_refusal(args.params)
		if answer.is_empty():
			match tool:
				"run":
					answer = await _run(args)
				"exec":
					answer = await _exec(args)
				"screenshot":
					answer = await _screenshot(args)
				"input":
					answer = await _play_input(args)
				"game_read":
					answer = await _game_read(args)
				"game_edit":
					answer = await _game_edit(args)
				"files_edit":
					answer = await _files_edit(args)
				"audio_edit":
					answer = await _audio_edit(args)
				"image_edit":
					answer = await _image_edit(args)
				"assets_placed":
					answer = await _assets_placed(args)
				_:
					answer = call(TOOLS[tool], args)
			var request_id := str(args.params.get("request_id", ""))
			if not request_id.is_empty():
				_remember(request_id, tool, answer)
	if _bridge:
		_bridge.reply(id, answer["_raw"] if answer.has("_raw") else JSON.stringify(answer))


## Runs one recorded step; the undo history calls it for NuJan's steps.
func _invoke(step: Callable) -> void:
	step.call()


# --- status ---------------------------------------------------------------------------------------------------------

func _status(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var readiness := "ready"
	if EditorInterface.get_resource_filesystem().is_scanning():
		readiness = "importing"
	elif EditorInterface.is_playing_scene():
		readiness = "playing"
	# GDatp's own wait for an opening project polls this, which leaves the errors counted since the last status alone.
	if _flag(args.params.get("readiness_only", false)):
		return {"readiness": readiness}
	var selected: Array = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		selected.append(_node_path(node))
	var errors := _logger.count("error")
	var errors_new := errors - _status_errors_seen
	_status_errors_seen = errors
	var answer := {
		"godot": Engine.get_version_info().string,
		"project": ProjectSettings.get_setting("application/config/name", ""),
		"project_path": ProjectSettings.globalize_path("res://"),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"current_scene": root.scene_file_path if root else "",
		"open_scenes": Array(EditorInterface.get_open_scenes()),
		"unsaved_scenes": Array(EditorInterface.get_unsaved_scenes()),
		"unsaved_scripts": _unsaved_scripts(),
		"readiness": readiness,
		"playing": EditorInterface.get_playing_scene() if EditorInterface.is_playing_scene() else "",
		"run": _run_state(),
		"selection": selected,
		"errors_logged": errors,
		"errors_since_last_status": errors_new,
		"on_main_thread": OS.get_thread_caller_id() == OS.get_main_thread_id(),
	}
	var versions = JSON.parse_string(str(_bridge.versions())) if _bridge else null
	if versions is Dictionary:
		answer.merge(versions)
	var request_id := str(args.params.get("request_id", ""))
	if not request_id.is_empty():
		answer["request"] = _outcomes.get(request_id, {"known": false, "note": "No write with that request_id reached the editor since it opened this project."})
	return answer


# --- project_read ---------------------------------------------------------------------------------------------------

func _project_read(args: Dictionary) -> Dictionary:
	var op := _op(args, ["info", "settings", "input_map", "autoloads"])
	if op.begins_with("!"):
		return _bad_op(op, ["info", "settings", "input_map", "autoloads"])
	var params: Dictionary = args.params
	match op:
		"info":
			return {
				"name": ProjectSettings.get_setting("application/config/name", ""),
				"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
				"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
				"renderer_mobile": ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", ""),
				"viewport_size": [ProjectSettings.get_setting("display/window/size/viewport_width", 0), ProjectSettings.get_setting("display/window/size/viewport_height", 0)],
				"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode", ""),
				"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect", ""),
				"orientation": ProjectSettings.get_setting("display/window/handheld/orientation", 0),
				"features": Array(ProjectSettings.get_setting("application/config/features", PackedStringArray())),
			}
		"settings":
			var prefix: String = str(params.get("prefix", ""))
			var found := {}
			for property in ProjectSettings.get_property_list():
				var setting: String = property.name
				if not setting.contains("/") or not setting.begins_with(prefix) or setting.begins_with("input/"):
					continue
				if not ProjectSettings.has_setting(setting):
					continue
				found[setting] = _plain(ProjectSettings.get_setting(setting))
				if found.size() >= MAX_LIST:
					break
			return {"prefix": prefix, "settings": found, "count": found.size()}
		"input_map":
			var builtin := _flag(params.get("builtin", false))
			var actions := {}
			var unchanged_builtin := 0
			for property in ProjectSettings.get_property_list():
				var setting: String = property.name
				if not setting.begins_with("input/"):
					continue
				var events := _event_texts(ProjectSettings.get_setting(setting))
				if setting.begins_with("input/ui_") and not builtin and events == _event_texts(ProjectSettings.property_get_revert(setting)):
					unchanged_builtin += 1
					continue
				actions[setting.trim_prefix("input/")] = events
			var answer := {"actions": actions, "count": actions.size()}
			if unchanged_builtin > 0:
				answer["builtin_left_out"] = unchanged_builtin
				answer["next"] = "Godot's own ui_* actions the project has not changed are left out; builtin: true lists them."
			return answer
		_:
			var autoloads := {}
			for property in ProjectSettings.get_property_list():
				var setting: String = property.name
				if setting.begins_with("autoload/"):
					var value: String = ProjectSettings.get_setting(setting)
					autoloads[setting.trim_prefix("autoload/")] = {"path": value.trim_prefix("*"), "singleton": value.begins_with("*")}
			return {"autoloads": autoloads}


# --- files_read -----------------------------------------------------------------------------------------------------

## files_read's answers name the open project, because res:// paths look the same in every project.
func _files_read(args: Dictionary) -> Dictionary:
	var answer := _files_read_open_project(args)
	if not answer.has("error"):
		answer["project"] = str(ProjectSettings.get_setting("application/config/name", ""))
	return answer


func _files_read_open_project(args: Dictionary) -> Dictionary:
	var op := _op(args, ["list", "read", "search"])
	if op.begins_with("!"):
		return _bad_op(op, ["list", "read", "search"])
	var params: Dictionary = args.params
	match op:
		"list":
			var dir := _res_path(params.get("dir", "res://"))
			if dir.begins_with("!"):
				return _fail("bad_path", dir.substr(1))
			if not DirAccess.dir_exists_absolute(dir):
				return _fail("not_found", "There is no folder %s." % dir, {"next": "files_read list with dir res:// shows the project's top level."})
			var glob: String = str(params.get("glob", "*"))
			var files: Array = []
			_walk(dir, _flag(params.get("recursive", true)), glob, files)
			var offset := int(params.get("offset", 0))
			var limit := mini(int(params.get("limit", 200)), MAX_LIST)
			return {"dir": dir, "files": files.slice(offset, offset + limit), "total": files.size(), "offset": offset}
		"read":
			var path := _res_path(params.get("path", ""))
			if path.begins_with("!"):
				return _fail("bad_path", path.substr(1))
			if not FileAccess.file_exists(path):
				return _fail("not_found", "There is no file %s." % path, {"next": "files_read list or search finds it."})
			if not _is_text_file(path):
				return _fail("not_text", "%s is a binary file; files_read reads text." % path,
					{"next": "screenshot or scene_read shows what an image or scene holds."})
			var lines := FileAccess.get_file_as_string(path).split("\n")
			var first := maxi(int(params.get("from_line", 1)), 1)
			var last := mini(int(params.get("to_line", lines.size())), lines.size())
			var text := "\n".join(lines.slice(first - 1, last))
			var answer := {"path": path, "from_line": first, "to_line": last, "lines": lines.size(), "text": text.left(MAX_READ_CHARS)}
			if text.length() > MAX_READ_CHARS:
				answer["truncated"] = true
				answer["next"] = "Read the rest with from_line and to_line."
			if path.get_extension() == "tscn":
				answer["hint"] = "scene_read tree shows this scene as nodes."
			return answer
		_:
			var needle: String = str(params.get("text", ""))
			if needle.is_empty():
				return _fail("missing", "search needs 'text', or 'text' with 'regex': true.")
			var regex: RegEx = null
			if _flag(params.get("regex", false)):
				regex = RegEx.create_from_string(needle)
				if regex == null or not regex.is_valid():
					return _fail("bad_regex", "'%s' is not a valid regular expression." % needle)
			var files: Array = []
			_walk(_res_path(params.get("dir", "res://")), true, "*", files)
			var hits: Array = []
			for file in files:
				if not _is_text_file(file):
					continue
				var lines := FileAccess.get_file_as_string(file).split("\n")
				for i in lines.size():
					var line: String = lines[i]
					var matched := regex.search(line) != null if regex else line.findn(needle) != -1
					if matched:
						hits.append({"path": file, "line": i + 1, "text": line.strip_edges().left(200)})
						if hits.size() >= MAX_HITS:
							return {"hits": hits, "more": true, "next": "Narrow the search with dir or a longer text."}
			return {"hits": hits, "more": false}


# --- scene_read -----------------------------------------------------------------------------------------------------

func _scene_read(args: Dictionary) -> Dictionary:
	var op := _op(args, ["tree", "node", "find", "spatial"])
	if op.begins_with("!"):
		return _bad_op(op, ["tree", "node", "find", "spatial"])
	var params: Dictionary = args.params
	var scene_path: String = str(params.get("scene", ""))
	var root := EditorInterface.get_edited_scene_root()
	if op == "spatial":
		if root == null or (not scene_path.is_empty() and root.scene_file_path != scene_path):
			return _fail("no_scene", "spatial reads the scene open in the editor.", {"next": "scene_edit new_scene or open it first."})
		return _scene_spatial(root)
	if not scene_path.is_empty() and (root == null or root.scene_file_path != scene_path):
		if op == "tree":
			return _closed_scene_tree(scene_path)
		return _closed_scene_lookup(op, scene_path, params)
	if root == null:
		return _fail("no_scene", "No scene is open in the editor.", {"next": "scene_read tree with scene res://... reads a scene file."})
	if op == "tree":
		var nodes: Array = []
		_tree(root, root, 0, int(params.get("depth", 6)), nodes)
		var offset := int(params.get("offset", 0))
		var limit := mini(int(params.get("limit", 200)), MAX_LIST)
		return {"scene": root.scene_file_path, "nodes": nodes.slice(offset, offset + limit), "total": nodes.size(), "offset": offset}
	return _scene_lookup(op, root, params)


## node and find in [root], a scene open in the editor or one built from its file.
func _scene_lookup(op: String, root: Node, params: Dictionary) -> Dictionary:
	if op == "node":
		var node := _find_node(root, str(params.get("path", ".")))
		if node == null:
			return _missing_node(root, params.get("path", ""))
		return _describe(root, node, _flag(params.get("all", false)))
	var name_part: String = str(params.get("name", ""))
	var type: String = str(params.get("class", ""))
	var group: String = str(params.get("group", ""))
	var script_path: String = str(params.get("script", ""))
	var found: Array = []
	for node in [root] + root.find_children("*", "", true, true):
		if not name_part.is_empty() and node.name.findn(name_part) == -1:
			continue
		if not type.is_empty() and not node.is_class(type):
			continue
		if not group.is_empty() and not node.is_in_group(group):
			continue
		if not script_path.is_empty() and (node.get_script() == null or node.get_script().resource_path != script_path):
			continue
		found.append({"path": _node_path(node, root), "class": node.get_class()})
		if found.size() >= MAX_LIST:
			break
	var answer := {"scene": root.scene_file_path, "found": found}
	if found.is_empty():
		answer["note"] = "No node has all of these together. The scene's root is %s (%s) with %d nodes; scene_read tree shows them. Asking again the same way will find nothing more." % [root.name, root.get_class(), root.get_child_count(true) + root.find_children("*", "", true, true).size()]
	return answer


## node and find in a scene that is not open: built from its file, read, and freed, leaving the editor as it was.
func _closed_scene_lookup(op: String, scene_path: String, params: Dictionary) -> Dictionary:
	var path := _res_path(scene_path)
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	if not ResourceLoader.exists(path, "PackedScene"):
		return _fail("not_found", "There is no scene %s." % path, {"next": "files_read list with glob *.tscn lists the scenes."})
	var root := (load(path) as PackedScene).instantiate()
	if root == null:
		return _fail("not_built", "Godot could not build %s from its file." % path, {"next": "logs shows why."})
	var answer := _scene_lookup(op, root, params)
	answer["open"] = false
	root.free()
	return answer


func _closed_scene_tree(scene_path: String) -> Dictionary:
	var path := _res_path(scene_path)
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	if not ResourceLoader.exists(path, "PackedScene"):
		return _fail("not_found", "There is no scene %s." % path, {"next": "files_read list with glob *.tscn lists the scenes."})
	var state: SceneState = (load(path) as PackedScene).get_state()
	var nodes: Array = []
	# Paths start with the root's name, as they do for the open scene, so node and find take them as they are.
	var root_name := str(state.get_node_name(0)) if state.get_node_count() > 0 else ""
	for i in state.get_node_count():
		var relative := str(state.get_node_path(i))
		var node_path := root_name if relative == "." else root_name + "/" + relative.trim_prefix("./")
		var entry := {"path": node_path, "class": str(state.get_node_type(i))}
		var instance := state.get_node_instance(i)
		if instance != null:
			entry["instance"] = instance.resource_path
		nodes.append(entry)
	return {"scene": path, "nodes": nodes, "total": nodes.size(), "open": false, "next": "scene_edit with scene: %s opens and changes it." % path}


func _tree(root: Node, node: Node, depth: int, max_depth: int, out: Array) -> void:
	var entry := {"path": _node_path(node), "class": node.get_class(), "depth": depth}
	if node.get_script() != null:
		entry["script"] = node.get_script().resource_path
	var warnings: Array = Array(get_parent().node_warnings(node))
	if not warnings.is_empty():
		entry["warnings"] = warnings
	if node != root and not node.scene_file_path.is_empty():
		entry["instance"] = node.scene_file_path
	out.append(entry)
	if depth >= max_depth or (node != root and not node.scene_file_path.is_empty()):
		return
	for child in node.get_children():
		if child.owner == root:
			_tree(root, child, depth + 1, max_depth, out)


func _describe(root: Node, node: Node, all: bool) -> Dictionary:
	var properties := {}
	for property in node.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE) or property.name in ["script", "owner"]:
			continue
		var value = node.get(property.name)
		if not all:
			var default_value = ClassDB.class_get_property_default_value(node.get_class(), property.name)
			if typeof(value) == typeof(default_value) and value == default_value:
				continue
		properties[property.name] = _plain(value)
	var connections: Array = []
	for signal_info in node.get_signal_list():
		for connection in node.get_signal_connection_list(signal_info.name):
			if not (int(connection.flags) & CONNECT_PERSIST):
				continue
			var target = connection.callable.get_object()
			if target is Node and (target == root or root.is_ancestor_of(target)):
				connections.append({"signal": signal_info.name, "to": _node_path(target, root), "method": connection.callable.get_method()})
	return {
		"path": _node_path(node, root),
		"class": node.get_class(),
		"script": node.get_script().resource_path if node.get_script() != null else "",
		"groups": Array(node.get_groups()).filter(func(g): return not str(g).begins_with("_")),
		"warnings": Array(get_parent().node_warnings(node)),
		"properties": properties,
		"connections": connections,
		"children": node.get_children().filter(func(c): return c.owner == root).map(func(c): return str(c.name)),
	}


# --- scene_edit -----------------------------------------------------------------------------------------------------

## Applies a list of steps to the open scene as one undo step: each step is tried on the scene, and if one fails the
## steps before it are taken back and nothing changes; when all succeed they are taken back and committed again through
## the editor's undo history, so the person sees one "NuJan: …" step they can undo.
func _scene_edit(args: Dictionary) -> Dictionary:
	var params: Dictionary = args.params
	var ops = params.get("ops", [])
	if typeof(ops) == TYPE_STRING:
		ops = JSON.parse_string(ops)
	if typeof(ops) != TYPE_ARRAY or ops.is_empty():
		if args.op.is_empty():
			return _fail("missing", "scene_edit needs 'ops': a list of steps, each with an 'op'.", {"ops": ["new_scene"] + SCENE_OPS})
		var single := params.duplicate()
		single["op"] = args.op
		ops = [single]
	var made := {}
	if typeof(ops[0]) == TYPE_DICTIONARY and str(ops[0].get("op", "")) == "new_scene":
		made = _new_scene(ops[0])
		if made.has("error"):
			made["step"] = 1
			return made
		ops = ops.slice(1)
		if ops.is_empty():
			return made
	var root := EditorInterface.get_edited_scene_root()
	var scene_path := str(params.get("scene", ""))
	if scene_path.is_empty() and made.is_empty():
		return _which_scene()
	if not scene_path.is_empty() and made.is_empty() and (root == null or root.scene_file_path != scene_path):
		var opened := _open_scene(scene_path, _flag(params.get("open", true)))
		if opened.has("error"):
			return opened
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		return _fail("no_scene", "No scene is open in the editor.", {"next": "Start the ops with a new_scene step, or name a scene with open: true."})

	var steps: Array = []
	var notes: Array = []
	for i in ops.size():
		var step = ops[i]
		if typeof(step) != TYPE_DICTIONARY:
			_take_back(steps)
			return _fail("bad_step", "Step %d is not an object with an 'op'." % (i + 1))
		var result := _scene_step(root, step, steps)
		if result.has("error"):
			_take_back(steps)
			result["step"] = i + 1
			result["changed"] = "nothing: the steps before it were taken back"
			return result
		if result.has("note"):
			notes.append(result.note)
	var answer := _commit_steps(root, steps, params, notes)
	if not made.is_empty():
		answer["new_scene"] = made.scene
	answer["next"] = "scene_read tree shows the result; run play runs it."
	return answer


## Commits [steps], each already applied to check it, as one undo step named "NuJan: …", reads back what they set,
## and saves the scene unless `save` is false. Every tool that changes the open scene ends here.
func _commit_steps(root: Node, steps: Array, params: Dictionary, notes: Array = []) -> Dictionary:
	_take_back(steps)
	var action := UNDO_PREFIX + _summary(steps)
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	for step in steps:
		undo_redo.add_do_method(self, "_invoke", step.do)
		if step.has("made"):
			undo_redo.add_do_reference(step.made)
	for i in range(steps.size() - 1, -1, -1):
		undo_redo.add_undo_method(self, "_invoke", steps[i].undo)
		if steps[i].has("removed"):
			undo_redo.add_undo_reference(steps[i].removed)
	undo_redo.commit_action(true)

	var checks := _read_back(root, steps)
	var answer := {"scene": root.scene_file_path, "steps": steps.map(func(s): return s.text), "undo": action, "can_undo": true}
	var made_nodes: Array = steps.filter(func(s): return s.has("made") and is_instance_valid(s.made) and s.made.is_inside_tree()).map(func(s): return _node_path(s.made))
	if not made_nodes.is_empty():
		answer["made"] = made_nodes
	if not checks.is_empty():
		answer["mismatches"] = checks
	if not notes.is_empty():
		answer["notes"] = notes
	if _flag(params.get("save", true)):
		var saved := EditorInterface.save_scene()
		answer["saved"] = saved == OK
		if saved == OK:
			_saved_steps[action] = true
		else:
			answer["save_error"] = saved
	return answer


## What a tool that changes a scene answers when it is not told which: working on whatever is open sends a change to the wrong
## scene without a word, and a model then goes round undoing it.
func _which_scene() -> Dictionary:
	var open_now := EditorInterface.get_edited_scene_root()
	return _fail("which_scene", "Say which scene with 'scene', such as res://main.tscn; naming one opens it. Open now: %s." % (open_now.scene_file_path if open_now != null else "none"))


## The scene a tool works in, the one `scene` names, opened if it is not open; a refusal when none is named.
func _scene_root(params: Dictionary):
	var root := EditorInterface.get_edited_scene_root()
	var scene_path := str(params.get("scene", ""))
	if scene_path.is_empty():
		return _which_scene()
	if root == null or root.scene_file_path != _res_path(scene_path):
		var opened := _open_scene(_res_path(scene_path), _flag(params.get("open", true)))
		if opened.has("error"):
			return opened
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		return _fail("no_scene", "No scene is open in the editor.", {"next": "scene_edit new_scene makes one, or name a scene with open: true."})
	return root


func _scene_step(root: Node, step: Dictionary, steps: Array) -> Dictionary:
	var op := str(step.get("op", ""))
	match op:
		"add":
			var parent := _find_node(root, str(step.get("parent", ".")))
			if parent == null:
				return _missing_node(root, step.get("parent", ""))
			var node: Node
			var scene := str(step.get("scene", ""))
			if not scene.is_empty():
				var path := _res_path(scene)
				if path.begins_with("!") or not ResourceLoader.exists(path, "PackedScene"):
					return _fail("not_found", "There is no scene %s to add." % scene, {"next": "files_read list with glob *.tscn lists the scenes."})
				if path == root.scene_file_path:
					return _fail("recursive", "A scene cannot contain itself.")
				node = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			else:
				var made = _new_node(str(step.get("type", "")))
				if made is Dictionary:
					return made
				node = made
			var wanted_name := str(step.get("name", ""))
			if not wanted_name.is_empty():
				node.name = wanted_name
			var props = step.get("properties", {})
			if typeof(props) != TYPE_DICTIONARY:
				node.free()
				return _fail("bad_properties", "'properties' must be an object of property names and values.")
			for key in props:
				var value := _typed_for(node, str(key), props[key])
				if value.has("error"):
					node.free()
					return value
				node.set(str(key), value.value)
			var do_add := func():
				parent.add_child(node, true)
				node.owner = root
			var undo_add := func():
				parent.remove_child(node)
			steps.append({"do": do_add, "undo": undo_add, "made": node, "text": "add " + str(node.name), "check": {"node": node, "parent": parent}})
			do_add.call()
			return {}
		"set":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			var props = step.get("properties", {})
			if typeof(props) != TYPE_DICTIONARY or props.is_empty():
				return _fail("bad_properties", "set needs 'properties': an object of property names and values.")
			for key in props:
				# "shape:size" sets a property of the node's shape, and "modulate:a" one part of a colour.
				var property := str(key)
				var value := _typed_indexed(node, property, props[key]) if property.contains(":") else _typed_for(node, property, props[key])
				if value.has("error"):
					return value
				var new_value = value.value
				var indexed := NodePath(property)
				var old_value = node.get_indexed(indexed)
				var do_set := func():
					node.set_indexed(indexed, new_value)
				var undo_set := func():
					node.set_indexed(indexed, old_value)
				steps.append({"do": do_set, "undo": undo_set, "text": "set %s.%s" % [node.name, property], "check": {"node": node, "indexed": indexed, "value": new_value}})
				do_set.call()
			return {}
		"remove":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			if node == root:
				return _fail("root", "The scene's root cannot be removed.", {"next": "Make a new scene with new_scene instead."})
			var parent := node.get_parent()
			var index := node.get_index()
			var owners := _owners(node)
			var do_remove := func():
				parent.remove_child(node)
			var undo_remove := func():
				parent.add_child(node)
				parent.move_child(node, index)
				for owned in owners:
					owned.owner = owners[owned]
			steps.append({"do": do_remove, "undo": undo_remove, "removed": node, "text": "remove " + str(node.name)})
			do_remove.call()
			return {}
		"rename":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			var new_name := str(step.get("name", ""))
			if new_name.is_empty() or new_name.validate_node_name() != new_name:
				return _fail("bad_name", "'%s' cannot be a node's name." % new_name, {"did_you_mean": new_name.validate_node_name()})
			var old_name := str(node.name)
			var do_rename := func():
				node.name = new_name
			var undo_rename := func():
				node.name = old_name
			steps.append({"do": do_rename, "undo": undo_rename, "text": "rename %s to %s" % [old_name, new_name], "check": {"node": node, "name": new_name}})
			do_rename.call()
			return {}
		"move":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			var target := _find_node(root, str(step.get("parent", ".")))
			if target == null:
				return _missing_node(root, step.get("parent", ""))
			if node == root or node == target or node.is_ancestor_of(target):
				return _fail("bad_move", "%s cannot be moved under %s." % [node.name, target.name])
			var old_parent := node.get_parent()
			var old_index := node.get_index()
			var index := int(step.get("index", -1))
			var keep_global := _flag(step.get("keep_global", true))
			var do_move := func():
				node.reparent(target, keep_global)
				if index >= 0:
					target.move_child(node, mini(index, target.get_child_count() - 1))
			var undo_move := func():
				node.reparent(old_parent, keep_global)
				old_parent.move_child(node, old_index)
			steps.append({"do": do_move, "undo": undo_move, "text": "move %s under %s" % [node.name, target.name], "check": {"node": node, "parent": target}})
			do_move.call()
			return {}
		"duplicate":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			if node == root:
				return _fail("root", "The scene's root cannot be duplicated.")
			var parent := node.get_parent()
			var copy := node.duplicate()
			var copy_name := str(step.get("name", ""))
			if not copy_name.is_empty():
				copy.name = copy_name
			var do_copy := func():
				parent.add_child(copy, true)
				copy.owner = root
				for child in copy.find_children("*", "", true, false):
					if child.owner == null:
						child.owner = root
			var undo_copy := func():
				parent.remove_child(copy)
			steps.append({"do": do_copy, "undo": undo_copy, "made": copy, "text": "duplicate " + str(node.name), "check": {"node": copy, "parent": parent}})
			do_copy.call()
			return {}
		"attach_script":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			var path := _res_path(step.get("script", ""))
			if path.begins_with("!") or not ResourceLoader.exists(path, "Script"):
				return _fail("not_found", "There is no script %s." % step.get("script", ""), {"next": "Write it first with script_edit create."})
			var new_script: Script = load(path)
			if new_script.get_instance_base_type() != StringName() and not node.is_class(new_script.get_instance_base_type()):
				return _fail("wrong_base", "%s extends %s, but %s is a %s." % [path, new_script.get_instance_base_type(), node.name, node.get_class()])
			var old_script = node.get_script()
			var do_attach := func():
				node.set_script(new_script)
			var undo_attach := func():
				node.set_script(old_script)
			steps.append({"do": do_attach, "undo": undo_attach, "text": "attach %s to %s" % [path.get_file(), node.name], "check": {"node": node, "script": new_script}})
			do_attach.call()
			return {}
		"connect", "disconnect":
			var from := _find_node(root, str(step.get("from", "")))
			if from == null:
				return _missing_node(root, step.get("from", ""))
			var to := _find_node(root, str(step.get("to", "")))
			if to == null:
				return _missing_node(root, step.get("to", ""))
			var signal_name := str(step.get("signal", ""))
			if not from.has_signal(signal_name):
				var names := from.get_signal_list().map(func(s): return s.name)
				return _fail("unknown_signal", "%s has no signal '%s'." % [from.get_class(), signal_name], {"did_you_mean": _nearest(signal_name, names)})
			var method := str(step.get("method", ""))
			var callable := Callable(to, method)
			if op == "connect":
				if method.is_empty() or not to.has_method(method):
					return _fail("unknown_method", "%s has no method '%s'." % [to.name, method], {"next": "Add the method to its script with script_edit, then connect."})
				if from.is_connected(signal_name, callable):
					return _fail("connected", "%s.%s is already connected to %s.%s." % [from.name, signal_name, to.name, method])
				var do_connect := func():
					from.connect(signal_name, callable, CONNECT_PERSIST)
				var undo_connect := func():
					from.disconnect(signal_name, callable)
				steps.append({"do": do_connect, "undo": undo_connect, "text": "connect %s.%s" % [from.name, signal_name], "check": {"from": from, "signal": signal_name, "callable": callable, "connected": true}})
				do_connect.call()
			else:
				if not from.is_connected(signal_name, callable):
					return _fail("not_connected", "%s.%s is not connected to %s.%s." % [from.name, signal_name, to.name, method])
				var do_disconnect := func():
					from.disconnect(signal_name, callable)
				var undo_disconnect := func():
					from.connect(signal_name, callable, CONNECT_PERSIST)
				steps.append({"do": do_disconnect, "undo": undo_disconnect, "text": "disconnect %s.%s" % [from.name, signal_name], "check": {"from": from, "signal": signal_name, "callable": callable, "connected": false}})
				do_disconnect.call()
			return {}
		"group_add", "group_remove":
			var node := _find_node(root, str(step.get("node", step.get("path", ""))))
			if node == null:
				return _missing_node(root, step.get("node", step.get("path", "")))
			var group := str(step.get("group", ""))
			if group.is_empty():
				return _fail("missing", "%s needs 'group'." % op)
			var adding := op == "group_add"
			if adding == node.is_in_group(group):
				return {"note": "%s %s in group %s already." % [node.name, "is" if adding else "is not", group]}
			var do_group := func():
				if adding:
					node.add_to_group(group, true)
				else:
					node.remove_from_group(group)
			var undo_group := func():
				if adding:
					node.remove_from_group(group)
				else:
					node.add_to_group(group, true)
			steps.append({"do": do_group, "undo": undo_group, "text": "%s %s %s" % ["group" if adding else "ungroup", node.name, group], "check": {"node": node, "group": group, "in": adding}})
			do_group.call()
			return {}
		"new_scene":
			return _fail("bad_step", "new_scene can only be the first step.")
		_:
			return _fail("unknown_op", "There is no scene_edit op '%s'." % op, {"ops": ["new_scene"] + SCENE_OPS, "did_you_mean": _nearest(op, SCENE_OPS)})


func _take_back(steps: Array) -> void:
	for i in range(steps.size() - 1, -1, -1):
		steps[i].undo.call()


## What each step should have changed, read back from the scene after the commit; empty when all of it holds.
func _read_back(root: Node, steps: Array) -> Array:
	var mismatches: Array = []
	for step in steps:
		if not step.has("check"):
			continue
		var check: Dictionary = step.check
		if check.has("parent"):
			if not is_instance_valid(check.node) or check.node.get_parent() != check.parent:
				mismatches.append(step.text + ": the node is not where it was put")
		elif check.has("property") or check.has("indexed"):
			var now = check.node.get_indexed(check.indexed) if check.has("indexed") else check.node.get(check.property)
			if not _same(now, check.value):
				mismatches.append("%s: it holds %s" % [step.text, str(_plain(now))])
		elif check.has("name"):
			if str(check.node.name) != check.name:
				mismatches.append("%s: Godot named it %s" % [step.text, check.node.name])
		elif check.has("script"):
			if check.node.get_script() != check.script:
				mismatches.append(step.text + ": the script is not attached")
		elif check.has("callable"):
			if check.from.is_connected(check.signal, check.callable) != check.connected:
				mismatches.append(step.text + ": the connection did not change")
		elif check.has("group"):
			if check.node.is_in_group(check.group) != check["in"]:
				mismatches.append(step.text + ": the group did not change")
	return mismatches


func _summary(steps: Array) -> String:
	var texts: Array = steps.map(func(s): return s.text)
	var summary := ", ".join(PackedStringArray(texts))
	return summary if summary.length() <= 80 else summary.left(77) + "..."


func _new_scene(step: Dictionary) -> Dictionary:
	var path := _res_path(step.get("path", ""))
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	if path.get_extension() != "tscn":
		return _fail("bad_path", "A scene's path ends in .tscn, like res://player.tscn.")
	if FileAccess.file_exists(path):
		return _fail("exists", "%s already exists." % path, {"next": "Name it with scene and open: true to edit it, or choose another path."})
	var made = _new_node(str(step.get("root", step.get("type", "Node2D"))))
	if made is Dictionary:
		return made
	var root: Node = made
	var root_name := str(step.get("name", path.get_file().get_basename().to_pascal_case()))
	root.name = root_name
	var packed := PackedScene.new()
	var packed_ok := packed.pack(root)
	root.free()
	if packed_ok != OK:
		return _fail("not_made", "Godot could not make the scene (error %d)." % packed_ok)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := ResourceSaver.save(packed, path)
	if saved != OK:
		return _fail("not_saved", "Godot could not save %s (error %d)." % [path, saved])
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	var root_now := EditorInterface.get_edited_scene_root()
	if root_now == null or root_now.scene_file_path != path:
		return _fail("not_opened", "%s was saved but the editor did not open it." % path)
	return {"scene": path, "root": root_name, "opened": true, "next": "Add nodes with scene_edit add."}


func _open_scene(scene_path: String, open: bool) -> Dictionary:
	var path := _res_path(scene_path)
	if path.begins_with("!") or not ResourceLoader.exists(path, "PackedScene"):
		return _fail("not_found", "There is no scene %s." % scene_path, {"next": "files_read list with glob *.tscn lists the scenes."})
	if not open:
		return _fail("not_open", "%s is not the scene open in the editor." % path,
			{"next": "Leave out open: false to open it in the editor."})
	EditorInterface.open_scene_from_path(path)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		return _fail("not_opened", "The editor did not open %s." % path)
	return {}


## A new node of an engine class, or of a project's named script class (made from its engine base, with the script
## attached afterwards, so its _init does not run here); a refusal with the nearest names otherwise.
func _new_node(type: String):
	if type.is_empty():
		return _fail("missing", "A node needs 'type', an engine class such as Sprite2D, or 'scene', a res:// scene to add.")
	for global_class in ProjectSettings.get_global_class_list():
		if str(global_class["class"]) == type:
			var base := str(global_class["base"])
			if not ClassDB.class_exists(base) or not ClassDB.is_parent_class(base, "Node"):
				return _fail("not_a_node", "%s is a script class, but not a node." % type)
			var node: Node = ClassDB.instantiate(base)
			node.set_script(load(global_class["path"]))
			node.name = type
			return node
	if not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type, "Node"):
		if RENAMED_IN_GODOT_4.has(type):
			return _fail("renamed", "%s is the Godot 3 name; in Godot 4 it is %s." % [type, RENAMED_IN_GODOT_4[type]], {"did_you_mean": RENAMED_IN_GODOT_4[type]})
		var names: Array = Array(ClassDB.get_inheriters_from_class("Node"))
		return _fail("unknown_class", "There is no node class '%s'." % type, {"did_you_mean": _nearest(type, names)})
	if not ClassDB.can_instantiate(type):
		return _fail("abstract_class", "%s cannot be made directly; use one of the classes that extend it." % type)
	var node: Node = ClassDB.instantiate(type)
	node.name = type
	return node


## Every node under [node], with [node] itself, and the owner each has now.
func _owners(node: Node) -> Dictionary:
	var owners := {node: node.owner}
	for child in node.find_children("*", "", true, false):
		owners[child] = child.owner
	return owners


# --- script_edit ----------------------------------------------------------------------------------------------------

## What a file waits for when it preloads one not written yet.
var _MISSING_FILE: RegEx = RegEx.create_from_string("Preload file \"([^\"]+)\" does not exist")
## Scripts kept although a file they preload is not written yet, with those files.
var _waiting_scripts := {}

## Writes GDScript only when it compiles, so a broken script never reaches the project; the file's previous text is
## kept so undo restore_file can bring it back. A file that preloads one not written yet is kept and said to be waiting,
## so a game's files can be written in any order; each later write checks the scripts waiting for it.
func _script_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, ["create", "replace", "patch"])
	if op.begins_with("!"):
		return _bad_op(op, ["create", "replace", "patch"])
	var params: Dictionary = args.params
	var path := _res_path(params.get("path", ""))
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	if path.get_extension() != "gd":
		return _fail("bad_path", "script_edit writes GDScript files, ending in .gd.")
	var exists := FileAccess.file_exists(path)
	var previous: String = FileAccess.get_file_as_string(path) if exists else ""
	var content := ""
	match op:
		"create", "replace":
			content = str(params.get("content", ""))
		_:
			if not exists:
				return _fail("not_found", "There is no script %s." % path, {"next": "Use create to make it."})
			var edits = params.get("edits", [])
			if typeof(edits) != TYPE_ARRAY or edits.is_empty():
				return _fail("missing", "patch needs 'edits': a list of {old, new}, {line, text} or {delete_from, delete_to}.")
			content = previous
			for i in edits.size():
				if typeof(edits[i]) != TYPE_DICTIONARY:
					return _fail("bad_edit", "Edit %d is not an object." % (i + 1))
				var applied = _patched(content, edits[i], i + 1, path)
				if applied is Dictionary:
					return applied
				content = applied
	if content.strip_edges().is_empty():
		return _fail("missing", "'content' is empty.")
	var editing := _person_editing(path)
	if not editing.is_empty():
		return editing
	# The compiler reads a script's own inner classes from its file, so a new one has to be there to be checked.
	if not exists and not _store_script(path, content):
		return _fail("not_written", "Godot could not write %s (error %d)." % [path, FileAccess.get_open_error()])
	var found := _script_problems(content, path)
	var waiting := _files_missing(found.errors)
	if not found.errors.is_empty() and waiting.is_empty():
		if not exists:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var first: Dictionary = found.errors[0]
		var count: int = found.errors.size()
		return _fail("does_not_compile", "%s (line %d)%s" % [first.message, first.line, "" if count == 1 else ", and 1 more error" if count == 2 else ", and %d more errors" % (count - 1)],
			{"line": first.line, "errors": found.errors, "path": path, "written": false, "next": "Fix every listed line; nothing was written."})
	if not _store_script(path, content):
		return _fail("not_written", "Godot could not write %s (error %d)." % [path, FileAccess.get_open_error()])
	_file_backups.append({"path": path, "text": previous, "existed": exists, "at": Time.get_unix_time_from_system()})
	_save_restore_history()
	EditorInterface.get_resource_filesystem().update_file(path)
	if ResourceLoader.has_cached(path):
		var loaded: Script = load(path)
		loaded.source_code = content
		loaded.reload(true)
	_show_in_script_editor(path, content)
	var written := FileAccess.get_file_as_string(path) == content
	var answer := {"path": path, "op": op, "lines": content.count("\n") + 1, "written": written,
		"can_undo": "undo restore_file brings back the earlier text",
		"next": "Attach it with scene_edit attach_script, or run play to try it."}
	if not found.warnings.is_empty():
		answer["warnings"] = found.warnings
	if waiting.is_empty():
		_waiting_scripts.erase(path)
	else:
		_waiting_scripts[path] = waiting
		answer["waiting_for"] = waiting
		answer["next"] = "Kept, waiting for the files it preloads. Write them next: each write checks what was waiting for it."
	var rechecked := _recheck_waiting(path)
	if not rechecked.is_empty():
		answer["still_broken"] = rechecked
		answer["next"] = "These scripts were waiting for this file and still do not compile: fix each listed line."
	return answer


func _store_script(path: String, content: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true


## The script files that [errors] say are missing; empty when every error is a real one in this file.
func _files_missing(errors: Array) -> Array:
	var missing := []
	for entry: Dictionary in errors:
		var found := _MISSING_FILE.search(str(entry.message))
		if found != null and not missing.has(found.get_string(1)):
			missing.append(found.get_string(1))
	return missing


## Compiles what was waiting for [written] again, and gives what still fails with its errors.
func _recheck_waiting(written: String) -> Array:
	var broken := []
	for path: String in _waiting_scripts.keys():
		if not _waiting_scripts[path].has(written) or path == written:
			continue
		var problems := _script_problems(FileAccess.get_file_as_string(path), path)
		var waiting := _files_missing(problems.errors)
		if waiting.is_empty():
			_waiting_scripts.erase(path)
			if not problems.errors.is_empty():
				broken.append({"path": path, "errors": problems.errors})
		else:
			_waiting_scripts[path] = waiting
	return broken


## Every compile error and warning of [source] as the file at [path], as {errors, warnings}, each entry with its line;
## errors also with their column. Checked the way the script editor checks a file, so another file's class_name is a
## clash and this file's own is not.
func _script_problems(source: String, path: String) -> Dictionary:
	var found: Array = get_parent().check_gdscript(source, path)
	return {
		"errors": found.filter(func(entry): return entry.kind == "error").map(_without_kind),
		"warnings": found.filter(func(entry): return entry.kind == "warning").map(_without_kind),
	}


func _without_kind(entry: Dictionary) -> Dictionary:
	var copy := entry.duplicate()
	copy.erase("kind")
	return copy


## The first compile error of [source] as {message, line}, or empty when it compiles: for code that runs without being
## saved anywhere. A `class_name` line is read as a comment here, so it does not clash with the class already loaded.
func _compile_problem(source: String) -> Dictionary:
	var lines := source.split("\n")
	for i in lines.size():
		if lines[i].strip_edges().begins_with("class_name "):
			lines[i] = "#" + lines[i]
	var checker := GDScript.new()
	checker.source_code = "\n".join(lines)
	_logger.begin_capture()
	var result := checker.reload()
	var errors: Array = _logger.end_capture()
	if result == OK:
		return {}
	for error in errors:
		if str(error.file) == "built-in" or str(error.function).begins_with("GDScript"):
			return {"message": str(error.message), "line": int(error.line)}
	return {"message": "It does not compile (error %d)." % result, "line": 0}


## One patch edit applied to [content], as it stands after the edits before it: {old, new} replaces text found once, or
## every match with all; {line, text} inserts text before that line; {delete_from, delete_to} removes those lines, and
## puts new in their place when it is given. The new content, or the failure.
func _patched(content: String, given: Dictionary, number: int, path: String):
	var edit := _edit_in_our_words(given)
	if edit.has("delete_from"):
		var lines := content.split("\n")
		var first := int(edit.delete_from)
		var last := int(edit.get("delete_to", first))
		if first < 1 or last < first or last > lines.size():
			return _fail("bad_edit", "Edit %d deletes lines %d to %d, but %s has %d lines." % [number, first, last, path, lines.size()])
		var replacement := str(edit.new).trim_suffix("\n").split("\n") if edit.has("new") else PackedStringArray()
		return "\n".join(lines.slice(0, first - 1) + replacement + lines.slice(last))
	if edit.has("line") and edit.has("new"):
		return _fail("bad_edit", "Edit %d has both 'line' and 'new'. To swap text: {\"old\": \"the exact text now\", \"new\": \"what replaces it\"}. To insert at a line: {\"line\": 12, \"text\": \"...\"}." % number)
	if edit.has("line"):
		var lines := content.split("\n")
		var at := int(edit.line)
		if at < 1 or at > lines.size() + 1:
			return _fail("bad_edit", "Edit %d inserts before line %d, but %s has %d lines." % [number, at, path, lines.size()])
		var added := str(edit.get("text", "")).trim_suffix("\n").split("\n")
		return "\n".join(lines.slice(0, at - 1) + added + lines.slice(at - 1))
	var old_text := str(edit.get("old", ""))
	if old_text.is_empty():
		return _fail("bad_edit", "Edit %d has none of what an edit needs; it had %s. To swap text: {\"old\": \"the exact text now\", \"new\": \"what replaces it\"}. To insert: {\"line\": 12, \"text\": \"...\"}. To remove lines: {\"delete_from\": 3, \"delete_to\": 5}." % [number, ", ".join(edit.keys())])
	var found := content.count(old_text)
	if found > 1 and edit.has("near_line") and not _flag(edit.get("all", false)):
		return _replaced_nearest(content, old_text, str(edit.get("new", "")), int(edit.near_line))
	if found == 0 or (found > 1 and not _flag(edit.get("all", false))):
		return _fail("bad_edit", "Edit %d's 'old' text is found %d times in %s; it must be found exactly once, or set all." % [number, found, path],
			{"next": "Include more of the surrounding lines in 'old', or read the file with files_read read."})
	return content.replace(old_text, str(edit.get("new", "")))


## [content] with the match of [old_text] that starts nearest to line [line] replaced by [new_text].
func _replaced_nearest(content: String, old_text: String, new_text: String, line: int) -> String:
	var best := -1
	var best_distance := 0
	var at := content.find(old_text)
	while at != -1:
		var distance := absi(content.substr(0, at).count("\n") + 1 - line)
		if best == -1 or distance < best_distance:
			best = at
			best_distance = distance
		at = content.find(old_text, at + 1)
	return content.substr(0, best) + new_text + content.substr(best + old_text.length())


## An edit with the other names models give its two texts changed to 'old' and 'new'. 'text' beside a replacement can only
## be the text to replace, and a line given with them says which match is meant.
func _edit_in_our_words(given: Dictionary) -> Dictionary:
	var edit := given.duplicate()
	# Lines count from 1 and nothing is found from an empty text, so these are slots a model filled in for the sake of it.
	for name in ["line", "delete_from", "delete_to"]:
		if edit.has(name) and int(edit[name]) < 1:
			edit.erase(name)
	for name in ["old", "text"]:
		if edit.has(name) and str(edit[name]).is_empty():
			edit.erase(name)
	if not edit.has("new"):
		for name in ["new_text", "new_string", "replacement", "replace", "to"]:
			if edit.has(name):
				edit["new"] = edit[name]
				break
	if not edit.has("old"):
		for name in ["old_text", "old_string", "search", "find", "from"]:
			if edit.has(name):
				edit["old"] = edit[name]
				break
	if not edit.has("old") and edit.has("new") and edit.has("text"):
		edit["old"] = edit["text"]
	if edit.has("old") and edit.has("new") and edit.has("line"):
		edit["near_line"] = edit["line"]
		edit.erase("line")
	return edit


func _unsaved_in_script_editor(path: String) -> bool:
	return _unsaved_scripts().has(path)


## The refusal while [path] has the person's unsaved changes in the script editor, which writing over it would lose;
## empty when it has none.
func _person_editing(path: String) -> Dictionary:
	if not _unsaved_in_script_editor(path):
		return {}
	return _fail("person_editing", "%s has unsaved changes in the script editor." % path, {"next": "Ask the person to save or close it first."})


## The files open in the script editor with changes not yet saved, scripts and text files alike: the person's typing,
## which a project switch loses.
func _unsaved_scripts() -> Array:
	var unsaved: Array = []
	for tab in _script_tabs():
		if tab.unsaved:
			unsaved.append(tab.path)
	return unsaved


func _show_in_script_editor(path: String, content: String) -> void:
	for tab in _script_tabs():
		if tab.path == path:
			var text_edit = tab.editor.get_base_editor()
			if text_edit is TextEdit:
				text_edit.text = content
				text_edit.tag_saved_version()


## The script editor's tabs that edit a file, each as {path, unsaved, editor}. Each tab is asked for its own file:
## get_open_scripts() leaves out the tabs that are not scripts, so it does not line up with the tabs.
func _script_tabs() -> Array:
	var tabs: Array = []
	for editor in EditorInterface.get_script_editor().get_open_script_editors():
		var tab: Dictionary = get_parent().script_tab(editor)
		if not str(tab.get("path", "")).is_empty():
			tab["editor"] = editor
			tabs.append(tab)
	return tabs


# --- run ------------------------------------------------------------------------------------------------------------

func _run(args: Dictionary) -> Dictionary:
	var ops: Array = ["state", "play", "stop", "restart", "try"] + GAME_CLOCK_OPS
	var op := _op(args, ops)
	if op.begins_with("!"):
		return _bad_op(op, ops)
	var params: Dictionary = args.params
	if GAME_CLOCK_OPS.has(op):
		return await _game_clock(op, params)
	match op:
		"state":
			# The person can pause and resume from the game's own menu too, so the game is asked.
			if EditorInterface.is_playing_scene() and _debugger.live and _debugger.helper_ready:
				var where := await _game_answer("frame", {}, 3.0)
				if not where.has("error"):
					_game_suspended = bool(where.get("suspended", _game_suspended))
			return _run_state()
		"stop":
			if not EditorInterface.is_playing_scene():
				return {"state": "stopped", "note": "No game was running."}
			EditorInterface.stop_playing_scene()
			for _attempt in 20:
				if not EditorInterface.is_playing_scene():
					break
				await get_tree().create_timer(0.25).timeout
			_run_by_nujan = false
			_game_suspended = false
			_game_speed = 1.0
			return {"state": "stopped" if not EditorInterface.is_playing_scene() else "stopping"}
		"restart":
			await _stop_game()
			return await _play(params)
		"try":
			await _stop_game()
			return await _try_game(params)
		_:
			if EditorInterface.is_playing_scene():
				return _fail("already_playing", "A game is running already (%s)." % EditorInterface.get_playing_scene(), {"next": "run stop first, or run restart."})
			return await _play(params)


func _stop_game() -> void:
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
		for _attempt in 20:
			if not EditorInterface.is_playing_scene():
				break
			await get_tree().create_timer(0.25).timeout


func _play(params: Dictionary) -> Dictionary:
	var which := str(params.get("scene", "main"))
	var errors_before := _logger.count("error")
	_debugger.reset()
	_game_suspended = false
	_game_speed = 1.0
	match which:
		"main":
			if str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty():
				return _fail("no_main_scene", "The project has no main scene.", {"next": "Run a scene by its path with scene: \"res://…\", or play the open one with scene: \"current\"."})
			EditorInterface.play_main_scene()
		"current":
			var root := EditorInterface.get_edited_scene_root()
			if root == null or root.scene_file_path.is_empty():
				return _fail("not_saved", "The open scene has not been saved to a file yet.", {"next": "Save it with scene_edit (save is on by default), then run it."})
			EditorInterface.play_current_scene()
		_:
			var path := _res_path(which)
			if path.begins_with("!") or not ResourceLoader.exists(path, "PackedScene"):
				return _fail("not_found", "There is no scene %s." % which, {"next": "files_read list with glob *.tscn lists the scenes."})
			EditorInterface.play_custom_scene(path)
	_freeze_next_run = _flag(params.get("frozen", false))
	_run_id += 1
	_run_by_nujan = true
	var wait_s := clampf(float(params.get("wait_s", 10)), 1.0, 60.0)
	var waited := 0.0
	while waited < wait_s:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		if _debugger.broken or (_debugger.live and waited >= 1.0) or (waited >= 1.0 and not EditorInterface.is_playing_scene()):
			break
	var frozen_at := -1
	if _flag(params.get("frozen", false)) and _debugger.live and not _debugger.broken:
		if not _game_suspended:
			_suspend_game(true)
		var where := await _game_answer("frame", {}, 5.0)
		frozen_at = int(where.get("frame", -1))
	_freeze_next_run = false
	var answer := _run_state()
	if frozen_at >= 0:
		answer["frame"] = frozen_at
	answer["run_id"] = _run_id
	answer["waited_s"] = waited
	_add_game_reports(answer)
	answer["editor_errors"] = _logger.since_count("error", errors_before)
	match answer.state:
		"live" when _game_suspended:
			answer["next"] = "The game is paused at its start: game_edit sets up a test, run step moves it a frame, run resume lets it go."
		"live":
			answer["next"] = "screenshot target game shows it, and with burst how it moves; logs shows what it printed; run stop ends it."
		"break":
			answer["next"] = "The game stopped at an error: read errors, fix the script, then run restart."
		"not_live":
			answer["next"] = "The game started but did not reach the editor's debugger yet; run state again, or logs."
		_:
			answer["next"] = "The game is not running: read errors and logs for why."
	return answer


func _run_state() -> Dictionary:
	var state := "stopped"
	if EditorInterface.is_playing_scene():
		state = "break" if _debugger.broken else ("live" if _debugger.live else "not_live")
	var running := state != "stopped"
	return {"state": state, "scene": EditorInterface.get_playing_scene() if running else "", "by_nujan": _run_by_nujan and running, "run_id": _run_id,
		"paused": _game_suspended and running, "speed": _game_speed}


# --- undo -----------------------------------------------------------------------------------------------------------

func _undo(args: Dictionary) -> Dictionary:
	var op := _op(args, ["undo", "redo", "history", "restore_file", "restore_setting"])
	if op.begins_with("!"):
		return _bad_op(op, ["undo", "redo", "history", "restore_file", "restore_setting"])
	var params: Dictionary = args.params
	if op == "restore_file":
		return _restore_file(params)
	if op == "restore_setting":
		return _restore_setting(params)
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		if op == "history":
			return {"scene": "", "steps": [], "restorable": _restorable()}
		return _fail("no_scene", "No scene is open, so there is no scene history.")
	var manager := EditorInterface.get_editor_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
	match op:
		"history":
			var steps: Array = []
			var current := history.get_current_action()
			var count := history.get_history_count()
			for i in range(count - 1, maxi(-1, count - 21), -1):
				var step_name := history.get_action_name(i)
				steps.append({"step": step_name, "by": "nujan" if step_name.begins_with(UNDO_PREFIX) else "person", "done": i <= current})
			return {"scene": root.scene_file_path, "steps": steps, "restorable": _restorable()}
		"undo":
			var count := clampi(int(params.get("count", 1)), 1, 50)
			var anyone := _flag(params.get("any", false))
			var undone: Array = []
			var answer := {"next": "scene_read tree shows the scene now."}
			for _step in count:
				if not history.has_undo():
					break
				var step_name := history.get_current_action_name()
				if not anyone and not step_name.begins_with(UNDO_PREFIX):
					answer["stopped_at"] = step_name
					answer["note"] = "The next step back is the person's, so it was left; any: true takes back anyone's steps."
					break
				if not get_parent().undo_scene_step():
					break
				undone.append(step_name)
			answer["undone"] = undone
			_follow_on_disk(undone, answer)
			return answer
		_:
			var count := clampi(int(params.get("count", 1)), 1, 50)
			var redone: Array = []
			for _step in count:
				if not history.has_redo():
					break
				if not get_parent().redo_scene_step():
					break
				redone.append(history.get_current_action_name())
			var answer := {"redone": redone}
			_follow_on_disk(redone, answer)
			return answer


## Saves the scene again when a step just undone or redone was one NuJan had saved, so the file on disk matches the
## editor; the person's own unsaved changes are theirs to save.
func _follow_on_disk(steps: Array, answer: Dictionary) -> void:
	if not steps.any(func(step_name): return _saved_steps.has(step_name)):
		return
	var saved := EditorInterface.save_scene()
	answer["saved"] = saved == OK
	if saved != OK:
		answer["save_error"] = saved


func _restore_file(params: Dictionary) -> Dictionary:
	var path := _res_path(params.get("path", ""))
	for i in range(_file_backups.size() - 1, -1, -1):
		var backup: Dictionary = _file_backups[i]
		if backup.path != path:
			continue
		var editing := _person_editing(path)
		if not editing.is_empty():
			return editing
		if backup.existed:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return _fail("not_written", "Godot could not write %s." % path)
			file.store_string(backup.text)
			file.close()
			_show_in_script_editor(path, backup.text)
			if ResourceLoader.has_cached(path):
				var loaded: Script = load(path)
				loaded.source_code = backup.text
				loaded.reload(true)
		else:
			DirAccess.remove_absolute(path)
		_file_backups.remove_at(i)
		_save_restore_history()
		EditorInterface.get_resource_filesystem().update_file(path)
		return {"path": path, "restored": "the text before NuJan's last change" if backup.existed else "removed: NuJan had created it"}
	return _fail("nothing_to_restore", "GDatp keeps no earlier text of %s from NuJan's recent changes." % path, {"next": "undo history lists what can be restored."})


# --- logs -----------------------------------------------------------------------------------------------------------

func _logs(args: Dictionary) -> Dictionary:
	var params: Dictionary = args.params
	var limit := clampi(int(params.get("limit", 40)), 1, 400)
	var source := str(params.get("source", "all"))
	var level := str(params.get("level", "all"))
	var unread := _flag(params.get("since_last", false))
	var answer := {}
	if source in ["editor", "all"]:
		var entries: Array = _logger.recent(400, level)
		if unread:
			var after: int = _logs_read.editor
			entries = entries.filter(func(entry): return entry.seq > after)
		answer["editor"] = entries.slice(maxi(0, entries.size() - limit))
		_logs_read.editor = _logger.latest_seq()
	if source in ["output", "game", "all"]:
		answer["output"] = _unread_part(_output_panel(), "output", unread, limit)
		answer["errors"] = _unread_part(_debugger_errors(), "errors", unread, limit)
		var warnings := _unread_part(_debugger_warnings(), "warnings", unread, limit)
		if not warnings.is_empty():
			answer["warnings"] = warnings
	return answer


## The last [limit] of [items], from where the last read of [key] ended when [unread] is set. The editor can clear the
## Output panel and the Errors tab when a run starts, so after a new run, or when the item at the last read's end is
## not the one read then, the list is a new one, read whole.
func _unread_part(items: Array, key: String, unread: bool, limit: int) -> Array:
	var read: Dictionary = _logs_read[key]
	var seen: int = read.count
	var continues: bool = seen == 0 or (read.run == _run_id and items.size() >= seen and str(items[seen - 1]) == read.last)
	_logs_read[key] = {"count": items.size(), "last": "" if items.is_empty() else str(items.back()), "run": _run_id}
	var part := items.slice(seen) if unread and continues else items
	return part.slice(maxi(0, part.size() - limit))


## The lines of the editor's Output panel, which also shows what a running game prints.
func _output_panel() -> Array:
	for editor_log in EditorInterface.get_base_control().find_children("*", "EditorLog", true, false):
		for label in editor_log.find_children("*", "RichTextLabel", true, false):
			return Array((label as RichTextLabel).get_parsed_text().split("\n", false))
	return []


## What the running game reported as broken, and apart from it GDScript's warnings about its scripts, which name a habit
## of the code while the game runs on. A model given them together stops to tidy code that works.
func _add_game_reports(answer: Dictionary) -> void:
	answer["errors"] = _debugger_errors().slice(-10)
	var warnings := _debugger_warnings()
	if not warnings.is_empty():
		answer["warnings"] = warnings.slice(-5)


func _debugger_errors() -> Array:
	return _debugger_rows().filter(func(row): return not _is_script_warning(row))


func _debugger_warnings() -> Array:
	return _debugger_rows().filter(_is_script_warning).map(func(row): return str(row.get("message", "")))


## Whether a row of the debugger's Errors tab is GDScript's warning about a script: its first detail is the warning's code.
func _is_script_warning(row: Dictionary) -> bool:
	var details: Array = row.get("details", [])
	return not details.is_empty() and RegEx.create_from_string("^[A-Z_]+$").search(str(details[0])) != null


## The rows of the debugger's Errors tab: what a running game reported. The tab is named "Errors", with its count
## added while it has any, and its table is its own child.
func _debugger_rows() -> Array:
	var found: Array = []
	for debugger in EditorInterface.get_base_control().find_children("*", "ScriptEditorDebugger", true, false):
		for tree in debugger.find_children("*", "Tree", true, false):
			if tree.get_parent() == null or not str(tree.get_parent().name).begins_with("Errors"):
				continue
			var root_item: TreeItem = tree.get_root()
			if root_item == null:
				continue
			for item in root_item.get_children():
				var details: Array = []
				for child in item.get_children():
					details.append(child.get_text(1))
				found.append({"time": item.get_text(0), "message": item.get_text(1), "details": details})
	return found


# --- screenshot -----------------------------------------------------------------------------------------------------

func _screenshot(args: Dictionary) -> Dictionary:
	var params: Dictionary = args.params.duplicate()
	var target := str(params.get("target", "editor"))
	var max_size := clampi(int(params.get("max_size", SHOT_SIZE)), 64, 2048)
	params["max_size"] = max_size
	if target != "game" and params.has("scene"):
		# Showing a scene changes nothing in it, so the editor opens it without being told to.
		var shown = _scene_root({"scene": params.scene, "open": true})
		if shown is Dictionary:
			return shown
	var image: Image
	var switched := ""
	match target:
		"editor":
			image = get_viewport().get_texture().get_image()
		"editor_2d":
			switched = await _show_main_screen("2D", EditorInterface.get_editor_viewport_2d())
			image = EditorInterface.get_editor_viewport_2d().get_texture().get_image()
		"editor_3d":
			switched = await _show_main_screen("3D", EditorInterface.get_editor_viewport_3d(0))
			image = EditorInterface.get_editor_viewport_3d(0).get_texture().get_image()
		"game":
			return await _game_screenshot(params)
		_:
			return _fail("unknown_target", "There is no target '%s'." % target, {"targets": ["editor", "editor_2d", "editor_3d", "game"]})
	if image == null or image.is_empty():
		return _fail("no_picture", "The %s had nothing to capture; it may not be on screen." % target)
	var full := [image.get_width(), image.get_height()]
	var longest := maxi(image.get_width(), image.get_height())
	if longest > max_size:
		var scale := float(max_size) / longest
		image.resize(roundi(image.get_width() * scale), roundi(image.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var dir := OS.get_cache_dir().path_join("gdatp")
	DirAccess.make_dir_recursive_absolute(dir)
	var frame := Engine.get_process_frames()
	var path := dir.path_join("%s-%d.png" % [target, frame])
	var saved := image.save_png(path)
	if saved != OK:
		return _fail("not_saved", "The picture could not be saved (error %d)." % saved)
	var answer := {"path": path, "target": target, "size": [image.get_width(), image.get_height()], "full_size": full, "frame": frame}
	# The editor's title bar shows menus, not the project, so a picture alone does not say which project it is.
	var project := str(ProjectSettings.get_setting("application/config/name", ""))
	if not project.is_empty():
		answer["project"] = project
	var notes: Array = [] if switched.is_empty() else [switched]
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		answer["scene"] = root.scene_file_path
		if target == "editor_2d" and root is Node3D:
			notes.append("%s is a 3D scene, so its 2D view is empty; editor_3d shows it." % root.scene_file_path)
		elif target == "editor_3d" and root is CanvasItem:
			notes.append("%s is a 2D scene, so its 3D view is empty; editor_2d shows it." % root.scene_file_path)
	if not notes.is_empty():
		answer["note"] = " ".join(PackedStringArray(notes))
	return answer


## Brings the editor's 2D or 3D screen to the front when another one is showing, since a hidden view has no size to
## draw in; what changed on the person's screen, or "" when nothing did.
func _show_main_screen(screen: String, viewport: SubViewport) -> String:
	var holder := viewport.get_parent() as CanvasItem
	if holder != null and holder.is_visible_in_tree() and viewport.size.x > 16 and viewport.size.y > 16:
		return ""
	EditorInterface.set_main_screen_editor(screen)
	for i in 3:
		await get_tree().process_frame
	return "The editor now shows its %s view." % screen


# --- exec -----------------------------------------------------------------------------------------------------------

## Runs GDScript in the editor: the code is the body of a function given `host`, and `return` sends a value back. It
## runs on the editor's main thread under a time limit: once it passes, a loop in the code ends at its next turn, so the
## editor does not freeze. A long call into the engine itself is not cut short, and code waiting on a signal or a timer
## is not stopped either: its call is answered `timeout` once the limit passes, so the next exec can run.
func _exec(args: Dictionary) -> Dictionary:
	var params: Dictionary = args.params
	if str(params.get("target", "editor")) == "game":
		return await _game_call("exec", params, 30.0)
	var code := str(params.get("code", ""))
	if code.strip_edges().is_empty():
		return _fail("missing", "exec needs 'code': the body of a function; return sends a value back.")
	if _exec_running:
		return _fail("busy", "Another exec is still running in the editor; try again when it has returned.")
	var seconds := clampf(float(params.get("seconds", EXEC_SECONDS)), 1.0, EXEC_SECONDS_MAX)
	var header := "@tool\nextends RefCounted\n\n\nfunc run(host):\n"
	var body := "\n".join(PackedStringArray(Array(code.split("\n")).map(func(line): return "\t" + line)))
	var source := header + body + "\n"
	var problem := _compile_problem(source)
	if not problem.is_empty():
		return _fail("does_not_compile", problem.message, {"line": maxi(0, int(problem.line) - 5)})
	var runner_script := GDScript.new()
	runner_script.source_code = source
	runner_script.reload()
	var runner = runner_script.new()
	_exec_serial += 1
	_exec_returned = {}
	_exec_running = true
	_logger.begin_capture()
	get_parent().watch_exec(runner_script, seconds)
	var deadline := Time.get_ticks_msec() + int((seconds + EXEC_GRACE_SECONDS) * 1000.0)
	# Started without waiting on it, so code that waits on a signal or a timer cannot hold this call past its limit.
	@warning_ignore("missing_await")
	_run_exec_code(runner, _exec_serial)
	while _exec_returned.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var returned := not _exec_returned.is_empty()
	# Code still waiting keeps its watch, so a loop it runs if it resumes is stopped too, until the next exec's watch
	# replaces it.
	var stopped := false
	if returned:
		stopped = get_parent().end_exec_watch()
	_exec_running = false
	var captured: Array = _logger.end_capture()
	var printed: Array = captured.filter(func(e): return e.level == "message").map(func(e): return e.message)
	var errors: Array = captured.filter(func(e): return e.level != "message").map(func(e): return "%s (line %d)" % [e.message, maxi(0, int(e.line) - 5)])
	if not returned:
		return _fail("timeout", "The code was still waiting on a signal or a timer %d s after it started. The time limit stops loops, not waits, so it was left waiting; if it resumes, what it changes then stays changed." % int(seconds),
			{"printed": printed, "errors": errors, "next": "Await only what arrives within the limit, or pass seconds for a longer one, up to %d." % int(EXEC_SECONDS_MAX)})
	var result := {"value": _plain(_exec_returned.value), "printed": printed, "errors": errors}
	if stopped:
		result["stopped"] = "The code was still running after %d s, so its loop was stopped; what it changed before then stays changed. Pass seconds for a longer limit, up to %d." % [int(seconds), int(EXEC_SECONDS_MAX)]
	return result


## Runs an exec's code and keeps what it returns for that exec's call, unless the call was answered before it returned.
func _run_exec_code(runner, serial: int) -> void:
	var value = await runner.run(self)
	if _exec_running and serial == _exec_serial:
		_exec_returned = {"value": value}


# --- docs -----------------------------------------------------------------------------------------------------------

## This editor's own class reference, so names and signatures match the Godot version the project runs on.
func _docs(args: Dictionary) -> Dictionary:
	var op := _op(args, ["class", "member", "search"])
	if op.begins_with("!"):
		return _bad_op(op, ["class", "member", "search"])
	var params: Dictionary = args.params
	match op:
		"class":
			var wanted := str(params.get("name", params.get("class", "")))
			var doc: Dictionary = get_parent().class_doc(wanted)
			if doc.is_empty():
				if RENAMED_IN_GODOT_4.has(wanted):
					return _fail("renamed", "%s is the Godot 3 name; in Godot 4 it is %s." % [wanted, RENAMED_IN_GODOT_4[wanted]], {"did_you_mean": RENAMED_IN_GODOT_4[wanted]})
				return _fail("unknown_class", "There is no class '%s' in this editor's reference." % wanted, {"did_you_mean": _nearest(wanted, Array(get_parent().doc_class_names()))})
			var filter := str(params.get("filter", "")).to_lower()
			var keep := func(entry: Dictionary) -> bool: return filter.is_empty() or str(entry.get("name", "")).to_lower().contains(filter)
			return {
				"class": doc.get("name", wanted),
				"inherits": doc.get("inherits", ""),
				"brief": _doc_text(str(doc.get("brief_description", ""))),
				"description": _doc_text(str(doc.get("description", ""))).left(1500),
				"properties": doc.get("properties", []).filter(keep).map(func(p): return {"name": p.get("name", ""), "type": p.get("type", ""), "default": p.get("default_value", ""), "brief": _first_sentence(str(p.get("description", "")))}),
				"methods": doc.get("methods", []).filter(keep).map(func(m): return {"signature": _signature(m), "brief": _first_sentence(str(m.get("description", "")))}),
				"signals": doc.get("signals", []).filter(keep).map(func(s): return {"signature": _signature(s), "brief": _first_sentence(str(s.get("description", "")))}),
				"constants": doc.get("constants", []).filter(keep).map(func(c): return "%s = %s" % [c.get("name", ""), c.get("value", "")]),
				"next": "docs member with Class.member gives one member in full; the class's parent is in inherits.",
			}
		"member":
			var full := str(params.get("name", params.get("member", "")))
			var parts := full.split(".")
			if parts.size() != 2:
				return _fail("missing", "member takes 'name' as Class.member, like CharacterBody2D.move_and_slide.")
			var doc: Dictionary = get_parent().class_doc(parts[0])
			if doc.is_empty():
				return _fail("unknown_class", "There is no class '%s'." % parts[0], {"did_you_mean": _nearest(parts[0], Array(get_parent().doc_class_names()))})
			var names: Array = []
			for kind in ["methods", "properties", "signals", "constants"]:
				for entry in doc.get(kind, []):
					names.append(str(entry.get("name", "")))
					if str(entry.get("name", "")) == parts[1]:
						var answer := {"class": parts[0], "kind": kind.trim_suffix("s"), "name": parts[1], "description": _doc_text(str(entry.get("description", "")))}
						if kind in ["methods", "signals"]:
							answer["signature"] = _signature(entry)
						if kind == "properties":
							answer["type"] = entry.get("type", "")
							answer["default"] = entry.get("default_value", "")
						if kind == "constants":
							answer["value"] = entry.get("value", "")
						return answer
			return _fail("unknown_member", "%s has no member '%s' of its own." % [parts[0], parts[1]],
				{"did_you_mean": _nearest(parts[1], names), "inherits": doc.get("inherits", ""), "next": "It may belong to the class in inherits."})
		_:
			var words: Array = Array(str(params.get("words", params.get("text", ""))).to_lower().split(" ", false))
			if words.is_empty():
				return _fail("missing", "search needs 'words'.")
			var found: Array = []
			for class_name_found in get_parent().doc_class_names():
				var lowered := str(class_name_found).to_lower()
				if words.all(func(word): return lowered.contains(word)):
					found.append(class_name_found)
				if found.size() >= 30:
					break
			return {"classes": found, "next": "docs class with name gives a class's members."}


## The reference's markup made plain: code in backticks, tags around names dropped, C# examples left out.
func _doc_text(text: String) -> String:
	var plain := text.strip_edges()
	plain = RegEx.create_from_string("\\[csharp\\][\\s\\S]*?\\[/csharp\\]").sub(plain, "", true)
	var fences := {"[codeblocks]": "", "[/codeblocks]": "", "[gdscript]": "\n```\n", "[/gdscript]": "\n```\n", "[codeblock]": "\n```\n", "[/codeblock]": "\n```\n"}
	for tag in fences:
		plain = plain.replace(tag, fences[tag])
	for tag in ["[code]", "[/code]"]:
		plain = plain.replace(tag, "`")
	for tag in ["[b]", "[/b]", "[i]", "[/i]", "[br]"]:
		plain = plain.replace(tag, "")
	plain = RegEx.create_from_string("\\[(?:param|member|method|signal|constant|enum|annotation|theme_item|constructor|operator) ([^\\]]+)\\]").sub(plain, "`$1`", true)
	plain = RegEx.create_from_string("\\[url=[^\\]]*\\]([^\\[]*)\\[/url\\]").sub(plain, "$1", true)
	return RegEx.create_from_string("\\n{3,}").sub(plain, "\n\n", true)


func _first_sentence(text: String) -> String:
	var plain := _doc_text(text)
	var end := plain.find(". ")
	var first := plain.left(end + 1) if end != -1 else plain
	first = first.split("\n")[0]
	return first if first.length() <= 200 else first.left(197) + "..."


func _signature(method: Dictionary) -> String:
	var parts: Array = []
	for argument in method.get("arguments", []):
		var text := "%s: %s" % [argument.get("name", ""), argument.get("type", "")]
		if not str(argument.get("default_value", "")).is_empty():
			text += " = " + str(argument.default_value)
		parts.append(text)
	var signature := "%s(%s)" % [method.get("name", ""), ", ".join(PackedStringArray(parts))]
	if not str(method.get("return_type", "")).is_empty() and method.get("return_type", "") != "void":
		signature += " -> " + str(method.return_type)
	if not str(method.get("qualifiers", "")).is_empty():
		signature += " " + str(method.qualifiers)
	return signature


# --- project_edit ---------------------------------------------------------------------------------------------------

## Changes project settings through ProjectSettings, never by writing project.godot, and saves them; the value each
## setting held before is kept so undo restore_setting can bring it back.
func _project_edit(args: Dictionary) -> Dictionary:
	var ops := ["setting_set", "main_scene_set", "input_action_set", "input_action_remove", "autoload_add", "autoload_remove"]
	var op := _op(args, ops)
	if op.begins_with("!"):
		return _bad_op(op, ops)
	var params: Dictionary = args.params
	match op:
		"setting_set":
			var key := str(params.get("key", params.get("name", "")))
			if not key.contains("/"):
				return _fail("missing", "setting_set needs 'key', a setting's full name like display/window/size/viewport_width.")
			if key.begins_with("input/") or key.begins_with("autoload/"):
				return _fail("wrong_op", "Input actions and autoloads have their own ops.", {"ops": ["input_action_set", "autoload_add"]})
			if not ProjectSettings.has_setting(key) and not _flag(params.get("new", false)):
				var names: Array = ProjectSettings.get_property_list().map(func(p): return p.name).filter(func(n): return str(n).contains("/"))
				return _fail("unknown_setting", "The project has no setting '%s'." % key, {"did_you_mean": _nearest(key, names), "next": "new: true adds a setting of the project's own."})
			var value = params.get("value")
			for property in ProjectSettings.get_property_list():
				if property.name == key:
					var typed := _typed(value, property)
					if typed.has("error"):
						return typed
					value = typed.value
					break
			return _set_setting(key, value)
		"main_scene_set":
			var path := _res_path(params.get("path", params.get("scene", "")))
			if path.begins_with("!") or not ResourceLoader.exists(path, "PackedScene"):
				return _fail("not_found", "There is no scene %s." % params.get("path", ""), {"next": "files_read list with glob *.tscn lists the scenes."})
			return _set_setting("application/run/main_scene", path)
		"input_action_set":
			var action := str(params.get("name", params.get("action", "")))
			if action.is_empty() or action.contains(" "):
				return _fail("missing", "input_action_set needs 'name', a single word like jump.")
			var events: Array = []
			for spec in params.get("events", []):
				var event = _input_event(spec)
				if event is Dictionary:
					return event
				events.append(event)
			var key := "input/" + action
			var current = ProjectSettings.get_setting(key, {"deadzone": 0.2, "events": []})
			var merged: Array = [] if _flag(params.get("replace", false)) else Array(current.get("events", []))
			var texts: Array = merged.map(func(e): return e.as_text())
			for event in events:
				if not texts.has(event.as_text()):
					merged.append(event)
					texts.append(event.as_text())
			return _set_setting(key, {"deadzone": float(params.get("deadzone", current.get("deadzone", 0.2))), "events": merged})
		"input_action_remove":
			var key := "input/" + str(params.get("name", params.get("action", "")))
			if not ProjectSettings.has_setting(key):
				return _fail("not_found", "The project has no input action '%s'." % params.get("name", ""))
			return _set_setting(key, null)
		"autoload_add":
			var autoload_name := str(params.get("name", ""))
			var path := _res_path(params.get("path", ""))
			if autoload_name.is_empty() or autoload_name.validate_node_name() != autoload_name:
				return _fail("missing", "autoload_add needs 'name', a node name like GameState.")
			if path.begins_with("!") or not ResourceLoader.exists(path):
				return _fail("not_found", "There is no script or scene %s." % params.get("path", ""))
			return _set_setting("autoload/" + autoload_name, ("*" if _flag(params.get("singleton", true)) else "") + path)
		_:
			var key := "autoload/" + str(params.get("name", ""))
			if not ProjectSettings.has_setting(key):
				return _fail("not_found", "The project has no autoload '%s'." % params.get("name", ""))
			return _set_setting(key, null)


## Sets a project setting as one step of the editor's own history, "NuJan: <key>", so the person's undo in the editor
## takes it back as undo restore_setting does, and saves it.
func _set_setting(key: String, value) -> Dictionary:
	var existed := ProjectSettings.has_setting(key)
	var before = ProjectSettings.get_setting(key) if existed else null
	_setting_backups.append({"key": key, "value": before, "existed": existed, "at": Time.get_unix_time_from_system()})
	_save_restore_history()
	var history := EditorInterface.get_editor_undo_redo()
	history.create_action(UNDO_PREFIX + key, UndoRedo.MERGE_DISABLE, ProjectSettings)
	history.add_do_method(ProjectSettings, "set_setting", key, value)
	history.add_do_method(ProjectSettings, "save")
	history.add_undo_method(ProjectSettings, "set_setting", key, before)
	history.add_undo_method(ProjectSettings, "save")
	history.commit_action()
	var saved := ProjectSettings.save()
	var answer := {"key": key, "saved": saved == OK, "can_undo": "undo restore_setting, or the editor's own undo, brings back the value before"}
	if typeof(value) == TYPE_NIL:
		answer["removed"] = not ProjectSettings.has_setting(key)
	elif key.begins_with("input/"):
		answer["events"] = _event_texts(ProjectSettings.get_setting(key))
	else:
		answer["value"] = _plain(ProjectSettings.get_setting(key))
	return answer


## An input event from a description: {"key": "Space"}, {"mouse": "left"}, {"joypad_button": 0} or
## {"joypad_axis": 0, "value": -1}; a refusal when it is none of them. Godot does not trigger actions from screen
## touches, so a touch is refused with the node that does.
func _input_event(spec):
	if typeof(spec) != TYPE_DICTIONARY:
		return _fail("bad_event", "An event is an object like {\"key\": \"Space\"}.")
	if spec.has("key"):
		var keycode := OS.find_keycode_from_string(str(spec.key))
		if keycode == KEY_NONE:
			return _fail("bad_event", "'%s' is not a key name, like Space, Enter, A or Left." % spec.key)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		return key_event
	if spec.has("mouse"):
		var buttons := {"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE}
		if not buttons.has(str(spec.mouse)):
			return _fail("bad_event", "A mouse button is left, right or middle.")
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = buttons[str(spec.mouse)]
		return mouse_event
	if spec.has("touch"):
		return _fail("bad_event", "Godot does not trigger input actions from screen touches.",
			{"next": "Add a TouchScreenButton with scene_edit and set its action property to this action's name."})
	if spec.has("joypad_button"):
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = int(spec.joypad_button)
		return button_event
	if spec.has("joypad_axis"):
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = int(spec.joypad_axis)
		axis_event.axis_value = signf(float(spec.get("value", 1.0)))
		return axis_event
	return _fail("bad_event", "An event has key, mouse, joypad_button or joypad_axis.")


func _restore_setting(params: Dictionary) -> Dictionary:
	var key := str(params.get("key", params.get("name", "")))
	for i in range(_setting_backups.size() - 1, -1, -1):
		var backup: Dictionary = _setting_backups[i]
		if backup.key != key:
			continue
		ProjectSettings.set_setting(key, backup.value if backup.existed else null)
		var saved := ProjectSettings.save()
		_setting_backups.remove_at(i)
		_save_restore_history()
		return {"key": key, "restored": "the value before NuJan's change" if backup.existed else "removed: NuJan had added it", "saved": saved == OK}
	return _fail("nothing_to_restore", "GDatp keeps no earlier value of %s from NuJan's recent changes." % key, {"next": "undo history lists what can be restored."})


# --- files_edit -----------------------------------------------------------------------------------------------------

## Changes the project's other files: scripts go through script_edit, and scenes and resources open in the editor
## through scene_edit. A deleted file is kept in GDatp's own storage so files_edit restore can bring it back.
func _files_edit(args: Dictionary) -> Dictionary:
	var ops := ["write", "mkdir", "move", "delete", "restore"]
	var op := _op(args, ops)
	if op.begins_with("!"):
		return _bad_op(op, ops)
	var params: Dictionary = args.params
	match op:
		"write":
			var path := _res_path(params.get("path", ""))
			if path.begins_with("!"):
				return _fail("bad_path", path.substr(1))
			if path.get_extension() == "gd":
				return _fail("wrong_tool", "Scripts are written with script_edit, which checks that they compile.")
			if path.get_file() == "project.godot":
				return _fail("wrong_tool", "Project settings are changed with project_edit.")
			if path in EditorInterface.get_open_scenes():
				return _fail("open_in_editor", "%s is open in the editor; change it with scene_edit." % path)
			var bytes := PackedByteArray()
			if params.has("base64"):
				bytes = Marshalls.base64_to_raw(str(params.base64))
			else:
				bytes = str(params.get("text", "")).to_utf8_buffer()
			if bytes.size() > MAX_WRITE_BYTES:
				return _fail("too_big", "At most %d MB can be written in one call." % (MAX_WRITE_BYTES >> 20))
			# A shader is written only when it compiles, as a script is, so a broken one never reaches the project.
			var shader_warnings: Array = []
			if path.get_extension() in ["gdshader", "gdshaderinc"]:
				var problems: Array = get_parent().check_shader(bytes.get_string_from_utf8(), path)
				var errors := problems.filter(func(problem): return problem.kind == "error")
				if not errors.is_empty():
					return _fail("does_not_compile", "%s (line %d)" % [errors[0].message, errors[0].line],
						{"line": errors[0].line, "errors": errors, "path": path, "written": false, "next": "Fix the line; nothing was written."})
				shader_warnings = problems.filter(func(problem): return problem.kind == "warning")
			if FileAccess.file_exists(path):
				_keep_in_trash(path)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return _fail("not_written", "Godot could not write %s (error %d)." % [path, FileAccess.get_open_error()])
			file.store_buffer(bytes)
			file.close()
			var answer := {"path": path, "bytes": FileAccess.get_file_as_bytes(path).size(), "written": FileAccess.get_file_as_bytes(path) == bytes}
			if not shader_warnings.is_empty():
				answer["warnings"] = shader_warnings
			if path.get_extension().to_lower() in IMPORTED_EXTENSIONS:
				answer["imported"] = await _imported(path)
				if not answer.imported:
					answer["next"] = "Godot did not import it within 10 s; logs shows why, or files_edit write again with a valid file."
			else:
				EditorInterface.get_resource_filesystem().update_file(path)
			return answer
		"mkdir":
			var path := _res_path(params.get("path", ""))
			if path.begins_with("!"):
				return _fail("bad_path", path.substr(1))
			var made := DirAccess.make_dir_recursive_absolute(path)
			EditorInterface.get_resource_filesystem().scan()
			return {"path": path, "made": made == OK}
		"move":
			var from := _res_path(params.get("from", params.get("path", "")))
			var to := _res_path(params.get("to", ""))
			if from.begins_with("!") or to.begins_with("!"):
				return _fail("bad_path", (from if from.begins_with("!") else to).substr(1))
			var is_folder := DirAccess.dir_exists_absolute(from)
			if not FileAccess.file_exists(from) and not is_folder:
				return _fail("not_found", "There is no file or folder %s." % from)
			if FileAccess.file_exists(to) or DirAccess.dir_exists_absolute(to):
				return _fail("exists", "%s already exists." % to)
			# Moving saves the open scenes that refer to what moves, so a person's unsaved changes there wait for them.
			var unsaved := _unsaved_scenes_using(from, is_folder)
			if not unsaved.is_empty():
				return _fail("person_editing", "Moving %s would save the open scenes that refer to it and have unsaved changes: %s." % [from, ", ".join(PackedStringArray(unsaved))],
					{"unsaved": unsaved, "next": "Ask the person to save or discard them, then move it again."})
			DirAccess.make_dir_recursive_absolute(to.get_base_dir())
			var result: Dictionary = get_parent().move_path(from, to)
			if int(result.error) != OK:
				return _fail("not_moved", "Godot could not move %s (error %d)." % [from, int(result.error)])
			var answer := {"from": from, "to": to, "moved": true, "updated": Array(result.updated)}
			var stale := _scripts_naming(from.trim_suffix("/") + "/" if is_folder else from)
			if not stale.is_empty():
				answer["scripts_naming_old_path"] = stale
				answer["next"] = "These scripts still name %s in their text; change them to %s with script_edit." % [from, to]
			return answer
		"delete":
			var path := _res_path(params.get("path", ""))
			if path.begins_with("!"):
				return _fail("bad_path", path.substr(1))
			if not FileAccess.file_exists(path):
				return _fail("not_found", "There is no file %s." % path)
			if path in EditorInterface.get_open_scenes():
				return _fail("open_in_editor", "%s is open in the editor; close it before deleting it." % path)
			var kept := _keep_in_trash(path)
			if kept.is_empty():
				return _fail("not_kept", "%s could not be kept for restoring, so it was not deleted." % path)
			for suffix in ["", ".import", ".uid"]:
				if FileAccess.file_exists(path + suffix):
					DirAccess.remove_absolute(path + suffix)
			EditorInterface.get_resource_filesystem().scan()
			return {"path": path, "deleted": not FileAccess.file_exists(path), "can_undo": "files_edit restore brings it back"}
		_:
			var path := _res_path(params.get("path", ""))
			for i in range(_trash.size() - 1, -1, -1):
				var kept: Dictionary = _trash[i]
				if kept.path != path:
					continue
				if path in EditorInterface.get_open_scenes():
					return _fail("open_in_editor", "%s is open in the editor; close it before restoring it." % path)
				var editing := _person_editing(path)
				if not editing.is_empty():
					return editing
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				for suffix in ["", ".import", ".uid"]:
					if FileAccess.file_exists(kept.copy + suffix):
						DirAccess.copy_absolute(kept.copy + suffix, path + suffix)
				_trash.remove_at(i)
				if FileAccess.file_exists(path):
					_remove_copy(str(kept.copy))
				_save_restore_history()
				var restored := {"path": path, "restored": FileAccess.file_exists(path)}
				if path.get_extension().to_lower() in IMPORTED_EXTENSIONS:
					restored["imported"] = await _imported(path)
				else:
					EditorInterface.get_resource_filesystem().update_file(path)
				return restored
			return _fail("nothing_to_restore", "GDatp keeps no copy of %s from NuJan's recent deletes and overwrites." % path, {"next": "undo history lists what can be restored."})


## Has the editor find a new or changed file that Godot imports, such as an image or a sound, and waits up to 10 s for
## the import; whether the project can now load it.
func _imported(path: String) -> bool:
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.scan()
	var waited := 0.0
	while waited < 10.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		if not filesystem.is_scanning() and ResourceLoader.exists(path):
			return true
	return ResourceLoader.exists(path)


## Copies a project file, with its import settings and uid, into the restore history; the copy's path, or "".
func _keep_in_trash(path: String) -> String:
	if _bridge == null:
		return ""
	var now := Time.get_unix_time_from_system()
	_copy_serial += 1
	var dir := _restore_dir().path_join("copies/%d-%d" % [int(now * 1000.0), _copy_serial])
	DirAccess.make_dir_recursive_absolute(dir)
	var copy := dir.path_join(path.get_file())
	var bytes := 0
	for suffix in ["", ".import", ".uid"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		if DirAccess.copy_absolute(path + suffix, copy + suffix) != OK:
			_remove_copy(copy)
			return ""
		var file := FileAccess.open(copy + suffix, FileAccess.READ)
		bytes += file.get_length() if file != null else 0
	_trash.append({"path": path, "copy": copy, "bytes": bytes, "at": now})
	_save_restore_history()
	return copy


# --- restore history ------------------------------------------------------------------------------------------------

## This project's restore history, in GDatp's own storage: one folder per project path.
func _restore_dir() -> String:
	return str(_bridge.filesDir()).path_join("gdatp-restore").path_join(ProjectSettings.globalize_path("res://").md5_text())


## Reads the restore history kept the last time the editor had this project open.
func _load_restore_history() -> void:
	var text := FileAccess.get_file_as_string(_restore_dir().path_join("history.json"))
	var saved = JSON.parse_string(text) if not text.is_empty() else null
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for entry in saved.get("files", []):
		if entry is Dictionary and entry.has_all(["path", "text", "existed"]):
			_file_backups.append(entry)
	for entry in saved.get("settings", []):
		if entry is Dictionary and entry.has_all(["key", "value", "existed"]):
			var backup: Dictionary = entry.duplicate()
			backup["value"] = str_to_var(str(entry.value))
			_setting_backups.append(backup)
	for entry in saved.get("trash", []):
		if entry is Dictionary and entry.has_all(["path", "copy"]) and FileAccess.file_exists(str(entry.copy)):
			_trash.append(entry)
	_save_restore_history()


## Drops what is past the limits, deleting the copies only those entries held, and writes the rest.
func _save_restore_history() -> void:
	if _bridge == null:
		return
	var oldest := Time.get_unix_time_from_system() - RESTORE_DAYS * 86400.0
	_file_backups = _recent(_file_backups, oldest)
	_setting_backups = _recent(_setting_backups, oldest)
	var recent := _recent(_trash, oldest)
	var kept: Array = []
	var bytes := 0
	for i in range(recent.size() - 1, -1, -1):
		bytes += int(recent[i].get("bytes", 0))
		if bytes > RESTORE_COPY_BYTES:
			break
		kept.push_front(recent[i])
	for entry in _trash:
		if not kept.has(entry):
			_remove_copy(str(entry.copy))
	_trash = kept
	var settings: Array = []
	for backup in _setting_backups:
		var saved: Dictionary = backup.duplicate()
		saved["value"] = var_to_str(backup.value)
		settings.append(saved)
	var dir := _restore_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("history.json.new"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"files": _file_backups, "settings": settings, "trash": _trash}))
	file.close()
	DirAccess.rename_absolute(dir.path_join("history.json.new"), dir.path_join("history.json"))


## The entries made since [oldest], at most RESTORE_ENTRIES of them, oldest first.
func _recent(entries: Array, oldest: float) -> Array:
	var recent := entries.filter(func(entry): return float(entry.get("at", 0.0)) >= oldest)
	return recent.slice(maxi(0, recent.size() - RESTORE_ENTRIES))


## Deletes a kept copy, with its import settings and uid, and the folder that held it; only inside the history.
func _remove_copy(copy: String) -> void:
	if not copy.begins_with(_restore_dir().path_join("copies")):
		return
	for suffix in ["", ".import", ".uid"]:
		if FileAccess.file_exists(copy + suffix):
			DirAccess.remove_absolute(copy + suffix)
	DirAccess.remove_absolute(copy.get_base_dir())


## What undo and files_edit can still put back, newest first.
func _restorable() -> Dictionary:
	var stamp := func(entry: Dictionary) -> String:
		return Time.get_datetime_string_from_unix_time(int(entry.get("at", 0.0)), true) + " UTC"
	var scripts: Array = []
	for i in range(_file_backups.size() - 1, -1, -1):
		scripts.append({"path": _file_backups[i].path, "changed": stamp.call(_file_backups[i])})
	var settings: Array = []
	for i in range(_setting_backups.size() - 1, -1, -1):
		settings.append({"key": _setting_backups[i].key, "changed": stamp.call(_setting_backups[i])})
	var files: Array = []
	for i in range(_trash.size() - 1, -1, -1):
		files.append({"path": _trash[i].path, "kept": stamp.call(_trash[i])})
	return {"scripts": scripts, "settings": settings, "files": files,
		"how": "undo restore_file puts back a script, undo restore_setting a setting, files_edit restore a deleted or overwritten file."}


# --- the running game -----------------------------------------------------------------------------------------------

## Plays the game like a person: taps, swipes, touches, held actions and keys, text, waits and checks, then reads
## `observe`. The game helper refuses steps that could take longer than its STEPS_MS_MAX, which this wait covers.
func _play_input(args: Dictionary) -> Dictionary:
	return await _game_call("input", args.params, 60.0)


## The running game as data: `tree`, `node`, `find`, `ui`, `watch` (the nujan_watch group), `monitors`, `check` or
## `sample`.
func _game_read(args: Dictionary) -> Dictionary:
	var params: Dictionary = args.params.duplicate()
	params["op"] = args.op if not args.op.is_empty() else "tree"
	return await _game_call("read", params, 40.0 if params.op == "sample" else 10.0)


## Sends the game helper into a game that just connected to the editor, with a token only GDatp's own storage holds.
## Each run starts unpaused at normal speed, or paused at once when run play asked for frozen.
func _on_game_started(session_id: int) -> void:
	_game_speed = 1.0
	_game_suspended = _freeze_next_run
	if _freeze_next_run:
		_debugger.get_session(session_id).send_message("scene:suspend_changed", [true])
	if _bridge == null:
		return
	_game_token = Crypto.new().generate_random_bytes(16).hex_encode()
	var dir := OS.get_cache_dir().path_join("gdatp")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("run-token"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(_game_token)
	file.close()
	_debugger.get_session(session_id).send_message("gdatp:helper", [_game_token, _bridge.gameHelperSource()])


## Hands a call to the game helper and waits for its answer, or for the game to stop at an error.
func _game_call(tool: String, params: Dictionary, timeout_s: float) -> Dictionary:
	if not EditorInterface.is_playing_scene() or not _debugger.live:
		return _fail("not_running", "No game is running.", {"next": "run play starts one."})
	var waited := 0.0
	while not _debugger.helper_ready and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not _debugger.helper_ready:
		return _fail("no_helper", "GDatp's helper did not start in the game.", {"next": "logs shows the game's errors; run restart tries again."})
	_game_call_id += 1
	var id := str(_game_call_id)
	if not _debugger.send_to_game("gdatp:call", [_game_token, id, tool, JSON.stringify(params)]):
		return _fail("not_running", "The game's debugger session has ended.")
	# Checked every editor frame, so stepping a paused game a frame at a time is not held to a timer's interval.
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not _debugger.replies.has(id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _debugger.broken:
			return _fail("break", "The game stopped at an error.", {"errors": _debugger_errors().slice(-5), "next": "Fix the script, then run restart."})
	if not _debugger.replies.has(id):
		return _fail("timeout", "The game did not answer within %d s." % timeout_s)
	var raw: String = _debugger.replies[id]
	_debugger.replies.erase(id)
	if typeof(JSON.parse_string(raw)) != TYPE_DICTIONARY:
		return _fail("bad_answer", "The game's answer was not a JSON object.")
	# Passed on as the game wrote it: parsing and writing it again would turn its whole numbers into decimals.
	return {"_raw": raw}


# --- shared ---------------------------------------------------------------------------------------------------------

## Accepts `params` as an object or as a JSON string, and parameters written beside `op` instead of inside `params`.
func _repaired(args: Dictionary) -> Dictionary:
	var params = args.get("params", {})
	if typeof(params) == TYPE_STRING:
		var parsed = JSON.parse_string(params)
		params = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if typeof(params) != TYPE_DICTIONARY:
		params = {}
	for key in args.keys():
		if key != "op" and key != "params" and not params.has(key):
			params[key] = args[key]
	return {"op": str(args.get("op", "")), "params": params}


## A refusal when the call names a project other than the open one, so a write never lands in the wrong project.
func _project_refusal(params: Dictionary) -> Dictionary:
	var expected := str(params.get("project", ""))
	if expected.is_empty():
		return {}
	var open := ProjectSettings.globalize_path("res://")
	if expected.trim_suffix("/") == open.trim_suffix("/") or expected == str(ProjectSettings.get_setting("application/config/name", "")):
		return {}
	return _fail("another_project", "The editor has %s open, not %s." % [open, expected], {"next": "status shows the open project."})


func _remember(request_id: String, tool: String, answer: Dictionary) -> void:
	if not _outcomes.has(request_id):
		_outcome_order.append(request_id)
	var outcome: Dictionary = JSON.parse_string(answer["_raw"]) if answer.has("_raw") else answer
	_outcomes[request_id] = {"known": true, "tool": tool, "done": not outcome.has("error"), "error": outcome.get("error", ""), "undo": outcome.get("undo", "")}
	while _outcome_order.size() > RECENT_OUTCOMES:
		_outcomes.erase(_outcome_order.pop_front())


## The op, or "!" and the op given when it is not one of [ops]; the first op when none was given.
func _op(args: Dictionary, ops: Array) -> String:
	var op: String = args.op
	if op.is_empty():
		return ops[0]
	return op if ops.has(op) else "!" + op


func _bad_op(op: String, ops: Array) -> Dictionary:
	return _fail("unknown_op", "There is no op '%s'." % op.substr(1), {"ops": ops, "did_you_mean": _nearest(op.substr(1), ops)})


## An input action's events as text, as the editor's Input Map shows them.
func _event_texts(action) -> Array:
	var texts: Array = []
	if typeof(action) == TYPE_DICTIONARY:
		for event in action.get("events", []):
			texts.append(event.as_text() if event is InputEvent else str(event))
	return texts


func _missing_node(root: Node, path) -> Dictionary:
	return _fail("not_found", "There is no node '%s' in %s." % [path, root.scene_file_path],
		{"next": "scene_read tree lists the scene's nodes and their paths, which start with the root's name."})


## Whether a file is text: not of a binary kind, and no NUL byte in its first 8 KB.
func _is_text_file(path: String) -> bool:
	if BINARY_EXTENSIONS.has(path.get_extension().to_lower()):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and not file.get_buffer(8192).has(0)


## The open scenes with unsaved changes whose saved file refers to [path], or to a file in it when it is a folder.
func _unsaved_scenes_using(path: String, is_folder: bool) -> Array:
	var prefix := path.trim_suffix("/") + "/"
	var found: Array = []
	for scene in EditorInterface.get_unsaved_scenes():
		for dependency in ResourceLoader.get_dependencies(scene):
			var used: String = dependency.get_slice("::", 2) if dependency.contains("::") else dependency
			if used == path or (is_folder and used.begins_with(prefix)):
				found.append(scene)
				break
	return found


## The scripts whose text names [path]; a move rewrites the references scenes and resources hold, not script text.
func _scripts_naming(path: String) -> Array:
	var scripts: Array = []
	_walk("res://", true, "*.gd", scripts)
	return scripts.filter(func(script_path): return FileAccess.get_file_as_string(script_path).contains(path))


func _walk(dir: String, recursive: bool, glob: String, out: Array) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file in access.get_files():
		if file.match(glob) and not file.ends_with(".uid"):
			out.append(dir.path_join(file))
	if not recursive:
		return
	for sub in access.get_directories():
		if not sub.begins_with("."):
			_walk(dir.path_join(sub), true, glob, out)


func _find_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == str(root.name):
		return root
	return root.get_node_or_null(NodePath(path.trim_prefix(str(root.name) + "/")))


## A node's path from its scene's root, starting with the root's name; the open scene's root unless [scene_root] is given.
func _node_path(node: Node, scene_root: Node = null) -> String:
	var root := scene_root if scene_root != null else EditorInterface.get_edited_scene_root()
	if root == null or node == root:
		return str(node.name)
	if not root.is_ancestor_of(node):
		return str(node.name)
	return str(root.name) + "/" + str(root.get_path_to(node))


## Keeps what the editor logs, from any thread, and what is logged on the main thread while a check or exec runs.
class _Capture extends Logger:
	var _mutex := Mutex.new()
	var _entries: Array = []
	var _seq := 0
	var _counts := {}
	var _capturing := false
	var _captured: Array = []
	var _main_thread := OS.get_main_thread_id()

	func _log_message(message: String, error: bool) -> void:
		_add("error" if error else "message", message.strip_edges(), "", "", 0)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text := rationale if not rationale.is_empty() else code
		_add("warning" if error_type == ERROR_TYPE_WARNING else "error", text, function, file, line)

	func _add(level: String, message: String, function: String, file: String, line: int) -> void:
		_mutex.lock()
		_seq += 1
		_counts[level] = int(_counts.get(level, 0)) + 1
		var entry := {"seq": _seq, "level": level, "message": message.left(2000), "function": function, "file": file, "line": line}
		_entries.append(entry)
		if _entries.size() > 400:
			_entries.pop_front()
		if _capturing and OS.get_thread_caller_id() == _main_thread:
			_captured.append(entry)
		_mutex.unlock()

	func begin_capture() -> void:
		_mutex.lock()
		_captured = []
		_capturing = true
		_mutex.unlock()

	func end_capture() -> Array:
		_mutex.lock()
		_capturing = false
		var captured := _captured
		_captured = []
		_mutex.unlock()
		return captured

	func count(level: String) -> int:
		_mutex.lock()
		var n := int(_counts.get(level, 0))
		_mutex.unlock()
		return n

	func since_count(level: String, before: int) -> int:
		return count(level) - before

	func recent(limit: int, level: String) -> Array:
		_mutex.lock()
		var picked: Array = _entries.filter(func(e): return level == "all" or e.level == level)
		_mutex.unlock()
		return picked.slice(maxi(0, picked.size() - limit))

	## The number of the newest entry, which a later read starts after.
	func latest_seq() -> int:
		_mutex.lock()
		var latest := _seq
		_mutex.unlock()
		return latest


## Follows the editor's debugger sessions, so a run knows when its game is live and when it stopped at an error, and
## carries the "gdatp:" messages between the tool host and the game helper.
class _Debugger extends EditorDebuggerPlugin:
	var host: Node
	var live := false
	var broken := false
	var helper_ready := false
	var replies := {}

	func _setup_session(session_id: int) -> void:
		var session := get_session(session_id)
		session.started.connect(_on_started.bind(session_id))
		session.stopped.connect(_on_stopped)
		session.breaked.connect(_on_breaked)
		session.continued.connect(_on_continued)

	func _has_capture(capture: String) -> bool:
		return capture == "gdatp"

	func _capture(message: String, data: Array, _session_id: int) -> bool:
		match message:
			"gdatp:ready":
				helper_ready = true
			"gdatp:reply":
				if data.size() == 2:
					replies[str(data[0])] = str(data[1])
			_:
				return false
		return true

	func send_to_game(message: String, data: Array) -> bool:
		for session in get_sessions():
			if session.is_active():
				session.send_message(message, data)
				return true
		return false

	func reset() -> void:
		live = false
		broken = false
		helper_ready = false
		replies.clear()

	func _on_started(session_id: int) -> void:
		live = true
		broken = false
		helper_ready = false
		if host:
			host.call("_on_game_started", session_id)

	func _on_stopped() -> void:
		live = false
		broken = false
		helper_ready = false

	func _on_breaked(_can_debug: bool) -> void:
		broken = true

	func _on_continued() -> void:
		broken = false
