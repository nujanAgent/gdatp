# --- edit -----------------------------------------------------------------------------------------------------------
# A part of the game helper: GDatpPlugin.gameHelperSource appends each gdatp/helper_*.gd after game_helper.gd, so
# these are the same script, sharing its helpers.

## Methods game_edit does not call: freeing at once can crash a running frame (remove frees safely), a new script swaps
## the game's code, and the call family would reach either of those indirectly.
const BLOCKED_CALLS := ["free", "set_script", "call", "callv", "call_deferred", "propagate_call"]


## Sets up a test in the running game: `set` a property, `call` a method, `spawn` a scene or a node, `remove` a node,
## `reload` the scene or `change_scene`, or `pause` with the game's own pause. None of it reaches the project's files.
func _edit(params: Dictionary) -> Dictionary:
	var scene := get_tree().current_scene
	var op := str(params.get("op", ""))
	if scene == null and op in ["set", "call", "spawn", "remove"]:
		return _fail("no_scene", "The game has no current scene.")
	match op:
		"set":
			return await _then_sample(scene, params, _edit_set(scene, params))
		"call":
			return await _then_sample(scene, params, _edit_call(scene, params))
		"spawn":
			return await _edit_spawn(scene, params)
		"remove":
			var path := str(params.get("path", ""))
			var node := _find(scene, path)
			if node == null:
				return _no_node(path)
			if node == scene:
				return _fail("refused", "remove takes a node inside the scene; reload and change_scene replace the whole scene.")
			var removed := _path(scene, node)
			node.queue_free()
			await get_tree().process_frame
			return {"removed": removed}
		"reload":
			var reloaded := get_tree().reload_current_scene()
			if reloaded != OK:
				return _fail("not_reloaded", "The scene could not be reloaded (error %d)." % reloaded)
			await get_tree().scene_changed
			return {"reloaded": get_tree().current_scene.scene_file_path}
		"change_scene":
			var path := _res_path(params.get("scene", ""))
			if path.begins_with("!") or not ResourceLoader.exists(path, "PackedScene"):
				return _fail("not_found", "There is no scene %s." % params.get("scene", ""), {"next": "files_read list with glob *.tscn lists the scenes."})
			var changed := get_tree().change_scene_to_file(path)
			if changed != OK:
				return _fail("not_changed", "The scene could not be changed (error %d)." % changed)
			await get_tree().scene_changed
			return {"scene": get_tree().current_scene.scene_file_path}
		"pause":
			if not can_process():
				return _fail("paused_from_editor", "The game is paused from the editor; run resume first, then the game's own pause can change.")
			get_tree().paused = _flag(params.get("on", true))
			return {"paused": get_tree().paused, "note": "The game's own pause: nodes set to process while paused, such as a pause menu, keep running."}
		_:
			return _fail("unknown_op", "There is no op '%s'." % op, {"ops": ["set", "call", "spawn", "remove", "reload", "change_scene", "pause"]})


## A set or call's answer with the physics frame it happened on and, when the call asks with sample_frames, its node's
## properties read over the frames that follow, in the same call: separate calls are seconds apart and the game runs on
## in between, so a later sample sees long after the change.
func _then_sample(scene: Node, params: Dictionary, answer: Dictionary) -> Dictionary:
	if answer.has("error"):
		return answer
	answer["physics_frame"] = _ran_physics_frames
	if not params.has("sample_frames"):
		return answer
	var properties = params.get("sample_properties", [params.get("property", "")] if answer.has("set") else [])
	if typeof(properties) != TYPE_ARRAY or properties.is_empty() or str(properties[0]).is_empty():
		answer["then"] = {"error": "missing", "message": "call with sample_frames needs sample_properties, such as [\"velocity\"]."}
		return answer
	answer["then"] = await _sample(scene, {"path": params.get("path", "."), "properties": properties, "frames": params.sample_frames})
	return answer


func _edit_set(scene: Node, params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	var node := _find(scene, path)
	if node == null:
		return _no_node(path)
	var property := str(params.get("property", ""))
	if property.is_empty() or not params.has("value"):
		return _fail("missing", "set needs 'path', 'property' and 'value'.")
	var typed: Dictionary = _typed_indexed(node, property, params.value) if property.contains(":") else _typed_for(node, property, params.value)
	if typed.has("error"):
		return typed
	node.set_indexed(NodePath(property), typed.value)
	var now = node.get_indexed(NodePath(property))
	var answer := {"set": _path(scene, node), "property": property, "value": _shown(scene, now)}
	if not _same(now, typed.value):
		answer["note"] = "The node holds another value than the one set; its own code may have changed it."
	return answer


func _edit_call(scene: Node, params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	var node := _find(scene, path)
	if node == null:
		return _no_node(path)
	var method := str(params.get("method", ""))
	if method.is_empty():
		return _fail("missing", "call needs 'path' and 'method', and 'args' when the method takes any.")
	if method in BLOCKED_CALLS:
		return _fail("refused", "game_edit does not call %s." % method, {"next": "remove frees a node safely." if method == "free" else "exec runs any code, when it is turned on."})
	if not node.has_method(method):
		var names: Array = []
		for info in node.get_method_list():
			names.append(info.name)
		return _fail("unknown_method", "%s has no method '%s'." % [_path(scene, node), method], {"did_you_mean": _nearest(method, names)})
	var given = params.get("args", [])
	var typed := _typed_args(scene, node, method, given if typeof(given) == TYPE_ARRAY else [given])
	if typed.has("error"):
		return typed
	var returned = node.callv(method, typed.value)
	return {"called": method, "on": _path(scene, node), "returned": _shown(scene, returned)}


## [args] typed as [method] declares its parameters: a node parameter takes a node's path in the running scene, and an
## untyped one takes the JSON as it is.
func _typed_args(scene: Node, node: Node, method: String, args: Array) -> Dictionary:
	var declared := {}
	for info in node.get_method_list():
		if info.name == method:
			declared = info
			break
	var parameters: Array = declared.get("args", [])
	var required: int = parameters.size() - declared.get("default_args", []).size()
	var vararg := int(declared.get("flags", 0)) & METHOD_FLAG_VARARG != 0
	if args.size() < required or (args.size() > parameters.size() and not vararg):
		var names: Array = parameters.map(func(parameter): return str(parameter.name))
		return _fail("bad_args", "%s takes %d to %d arguments (%s); %d were given." % [method, required, parameters.size(), ", ".join(names), args.size()])
	var typed: Array = []
	for i in args.size():
		var arg = args[i]
		if i >= parameters.size() or int(parameters[i].type) == TYPE_NIL:
			typed.append(_loose(arg))
			continue
		var info: Dictionary = parameters[i]
		if int(info.type) == TYPE_OBJECT and typeof(arg) == TYPE_STRING and not str(arg).begins_with("res://"):
			var target := _find(scene, str(arg))
			if target == null:
				return _fail("not_found", "Argument %d names no node '%s' in the running scene." % [i + 1, arg])
			typed.append(target)
			continue
		var value := _typed(arg, info)
		if value.has("error"):
			return value
		typed.append(value.value)
	return {"value": typed}


func _edit_spawn(scene: Node, params: Dictionary) -> Dictionary:
	var parent_path := str(params.get("parent", "."))
	var parent := _find(scene, parent_path)
	if parent == null:
		return _no_node(parent_path)
	var made: Node = null
	if params.has("scene"):
		var path := _res_path(params.scene)
		if path.begins_with("!") or not ResourceLoader.exists(path, "PackedScene"):
			return _fail("not_found", "There is no scene %s." % params.scene, {"next": "files_read list with glob *.tscn lists the scenes."})
		made = (load(path) as PackedScene).instantiate()
	elif params.has("type"):
		var type := str(params.type)
		if not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type, "Node") or not ClassDB.can_instantiate(type):
			return _fail("unknown_class", "There is no node class '%s'." % type, {"did_you_mean": _nearest(type, Array(ClassDB.get_inheriters_from_class("Node")))})
		made = ClassDB.instantiate(type)
	else:
		return _fail("missing", "spawn needs 'scene', a res:// .tscn, or 'type', a node class such as Sprite2D.")
	if params.has("name"):
		made.name = str(params.name)
	var properties = params.get("properties", {})
	if typeof(properties) != TYPE_DICTIONARY:
		properties = {}
	# Global placements need the node in the tree; everything else is set first, so the node's _ready sees it.
	var placed: Array = properties.keys().filter(func(key): return str(key).begins_with("global_"))
	for key in properties:
		if not placed.has(key):
			var refused := _set_on(made, str(key), properties[key])
			if not refused.is_empty():
				made.free()
				return refused
	parent.add_child(made, true)
	for key in placed:
		var refused := _set_on(made, str(key), properties[key])
		if not refused.is_empty():
			made.queue_free()
			return refused
	await get_tree().process_frame
	return {"spawned": _path(scene, made), "class": made.get_class()}


## Sets a typed property on [node]; the refusal, or an empty Dictionary once it is set.
func _set_on(node: Node, property: String, value) -> Dictionary:
	var typed: Dictionary = _typed_indexed(node, property, value) if property.contains(":") else _typed_for(node, property, value)
	if typed.has("error"):
		typed["note"] = "Nothing was spawned."
		return typed
	node.set_indexed(NodePath(property), typed.value)
	return {}


func _no_node(path: String) -> Dictionary:
	return _fail("not_found", "There is no node '%s' in the running scene." % path, {"next": "game_read find locates nodes by class, name, group or text."})
