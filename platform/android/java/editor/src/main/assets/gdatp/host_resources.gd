
# --- resource_edit ---------------------------------------------------------------------------------------------------

const RESOURCE_OPS := ["create", "set", "call", "duplicate", "read"]


## Resources by class and properties: materials, environments, curves, gradients, styles, label settings and every
## other Resource, in a .tres file or held by a node in the open scene (`node` and `property`). A file is kept in
## GDatp's trash before it changes; a change to the open scene is one undo step.
func _resource_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, RESOURCE_OPS)
	if op.begins_with("!"):
		return _bad_op(op, RESOURCE_OPS)
	var params: Dictionary = args.params
	match op:
		"create":
			return _resource_create(params)
		"duplicate":
			return _resource_duplicate(params)
	var held = _held_resource(params)
	if held is Dictionary and held.has("error"):
		return held
	var resource: Resource = held.resource
	match op:
		"read":
			return _resource_read(resource, held)
		"set":
			var props = params.get("properties", {})
			if typeof(props) != TYPE_DICTIONARY or props.is_empty():
				return _fail("missing", "set needs 'properties': an object of property names and values.")
			var typed := {}
			for key in props:
				var value := _typed_indexed(resource, str(key), props[key]) if str(key).contains(":") else _typed_for(resource, str(key), props[key])
				if value.has("error"):
					return value
				typed[str(key)] = value.value
			var set_all := func():
				for key in typed:
					resource.set_indexed(NodePath(key), typed[key])
				return {"set": typed.keys()}
			return _resource_change(held, params, set_all)
		_:
			var method := str(params.get("method", ""))
			var found := resource.get_method_list().filter(func(m): return m.name == method)
			if found.is_empty():
				var names: Array = resource.get_method_list().map(func(m): return m.name)
				return _fail("unknown_method", "%s has no method '%s'." % [resource.get_class(), method], {"did_you_mean": _nearest(method, names)})
			var given = params.get("args", [])
			if typeof(given) != TYPE_ARRAY:
				return _fail("bad_value", "'args' is a list of the method's arguments.")
			var arguments: Array = found[0].args
			if given.size() > arguments.size():
				return _fail("bad_value", "%s takes %d arguments." % [method, arguments.size()])
			var typed_args: Array = []
			for i in given.size():
				var value := _typed(given[i], arguments[i])
				if value.has("error"):
					return value
				typed_args.append(value.value)
			var call_it := func():
				return {"called": method, "returned": _plain(resource.callv(method, typed_args))}
			return _resource_change(held, params, call_it)


## The resource a call names: a res:// file (`path`), or one a node of the open scene holds (`node` and `property`).
func _held_resource(params: Dictionary):
	if params.has("node"):
		var root = _scene_root(params)
		if root is Dictionary:
			return root
		var node = _node_param(root, params, "node")
		if node is Dictionary:
			return node
		var property := str(params.get("property", ""))
		var held = node.get_indexed(NodePath(property)) if not property.is_empty() else null
		if not held is Resource:
			return _fail("no_resource", "%s holds no resource at '%s'." % [node.name, property], {"next": "scene_edit set gives it one: {\"%s\": {\"type\": …}}." % property})
		# A resource the node loads from its own file is changed in that file, which saving the scene would not write.
		if held.resource_path.begins_with("res://") and not held.resource_path.contains("::"):
			return {"resource": held, "path": held.resource_path}
		return {"resource": held, "root": root, "node": node, "property": property}
	var path := _res_path(params.get("path", ""))
	if path.begins_with("!") or not ResourceLoader.exists(path):
		return _fail("not_found", "There is no resource %s." % str(params.get("path", "")), {"next": "resource_edit create makes one; files_read list finds the project's files."})
	return {"resource": load(path), "path": path}


## Runs [change] on the held resource: in the open scene as one undo step that swaps a copy in and out, in a file after
## keeping the old file in GDatp's trash.
func _resource_change(held: Dictionary, params: Dictionary, change: Callable) -> Dictionary:
	var resource: Resource = held.resource
	if held.has("node"):
		var before: Resource = resource.duplicate(true)
		var result: Dictionary = change.call()
		var node: Node = held.node
		var path := NodePath(held.property)
		var swap_in := func():
			node.set_indexed(path, resource)
		var swap_out := func():
			node.set_indexed(path, before)
		var steps: Array = [{"do": swap_in, "undo": swap_out, "text": "change %s.%s" % [node.name, held.property]}]
		var answer := _commit_steps(held.root, steps, params)
		answer.merge(result)
		return answer
	if FileAccess.file_exists(held.path):
		_keep_in_trash(held.path)
	var answer: Dictionary = change.call()
	var saved := ResourceSaver.save(resource, held.path)
	if saved != OK:
		return _fail("not_saved", "Godot could not save %s (error %d)." % [held.path, saved])
	EditorInterface.get_resource_filesystem().update_file(held.path)
	answer["path"] = held.path
	answer["can_undo"] = "files_edit restore brings back the file as it was"
	return answer


func _resource_create(params: Dictionary) -> Dictionary:
	var path := _res_path(params.get("path", ""))
	if path.begins_with("!") or not path.get_extension() in ["tres", "res"]:
		return _fail("bad_path", "create needs 'path', a res:// .tres file.")
	var type := str(params.get("type", ""))
	if not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type, "Resource") or not ClassDB.can_instantiate(type):
		return _fail("unknown_class", "There is no resource class '%s' to make." % type, {"did_you_mean": _nearest(type, Array(ClassDB.get_inheriters_from_class("Resource")))})
	if FileAccess.file_exists(path) and not _flag(params.get("replace", false)):
		return _fail("exists", "%s already exists." % path, {"next": "resource_edit set changes it, or create with replace: true."})
	var resource: Resource = ClassDB.instantiate(type)
	var props = params.get("properties", {})
	if typeof(props) == TYPE_DICTIONARY:
		for key in props:
			var value := _typed_indexed(resource, str(key), props[key]) if str(key).contains(":") else _typed_for(resource, str(key), props[key])
			if value.has("error"):
				return value
			resource.set_indexed(NodePath(str(key)), value.value)
	if FileAccess.file_exists(path):
		_keep_in_trash(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := ResourceSaver.save(resource, path)
	if saved != OK:
		return _fail("not_saved", "Godot could not save %s (error %d)." % [path, saved])
	EditorInterface.get_resource_filesystem().update_file(path)
	return {"path": path, "type": type, "next": "scene_edit set gives it to a node's property, as {\"<property>\": \"%s\"}." % path}


func _resource_duplicate(params: Dictionary) -> Dictionary:
	var from := _res_path(params.get("from", params.get("path", "")))
	var to := _res_path(params.get("to", ""))
	if from.begins_with("!") or not ResourceLoader.exists(from):
		return _fail("not_found", "There is no resource %s." % str(params.get("from", "")))
	if to.begins_with("!") or not to.get_extension() in ["tres", "res"]:
		return _fail("bad_path", "duplicate needs 'to', a res:// .tres file.")
	if FileAccess.file_exists(to):
		return _fail("exists", "%s already exists." % to)
	var copy: Resource = load(from).duplicate(_flag(params.get("deep", true)))
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var saved := ResourceSaver.save(copy, to)
	if saved != OK:
		return _fail("not_saved", "Godot could not save %s (error %d)." % [to, saved])
	EditorInterface.get_resource_filesystem().update_file(to)
	return {"from": from, "to": to}


## The resource's class and the properties that differ from a new one of its class.
func _resource_read(resource: Resource, held: Dictionary) -> Dictionary:
	var fresh = ClassDB.instantiate(resource.get_class()) if ClassDB.can_instantiate(resource.get_class()) else null
	var properties := {}
	for property in resource.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE) or property.name in ["resource_local_to_scene", "resource_name", "resource_path", "script"]:
			continue
		var value = resource.get(property.name)
		if fresh != null and value == fresh.get(property.name):
			continue
		properties[property.name] = _plain(value)
	var answer := {"type": resource.get_class(), "properties": properties}
	if held.has("path"):
		answer["path"] = held.path
	else:
		answer["held_by"] = "%s.%s" % [_node_path(held.node), held.property]
	return answer
