
# --- steps shared by the authoring tools ------------------------------------------------------------------------------

## Sets [property] of [node] (indexed paths such as "shape:size" too) as a step of an undoable change, applied now so
## later steps see it.
func _set_step(node: Node, property: String, value, steps: Array) -> void:
	var path := NodePath(property)
	var old_value = node.get_indexed(path)
	var do_set := func(): node.set_indexed(path, value)
	var undo_set := func(): node.set_indexed(path, old_value)
	steps.append({"do": do_set, "undo": undo_set, "text": "set %s.%s" % [node.name, property], "check": {"node": node, "indexed": path, "value": value}})
	do_set.call()


## Adds [node], with any children it already has, under [parent] as a step of an undoable change; each is owned by
## [root], so the scene saves them.
func _add_step(root: Node, parent: Node, node: Node, steps: Array) -> void:
	var do_add := func():
		parent.add_child(node, true)
		_own(node, root)
	var undo_add := func():
		parent.remove_child(node)
	steps.append({"do": do_add, "undo": undo_add, "made": node, "text": "add " + str(node.name), "check": {"node": node, "parent": parent}})
	do_add.call()


func _own(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_own(child, root)


## The node a tool's [key] parameter names in [root], or a refusal; [classes] limits it to those classes.
func _node_param(root: Node, params: Dictionary, key: String, classes: Array = []):
	var node := _find_node(root, str(params.get(key, "")))
	if node == null:
		return _missing_node(root, params.get(key, ""))
	if not classes.is_empty() and not classes.any(func(c): return node.is_class(c)):
		return _fail("wrong_node", "%s is a %s; this needs a %s." % [node.name, node.get_class(), " or ".join(PackedStringArray(classes))])
	return node
