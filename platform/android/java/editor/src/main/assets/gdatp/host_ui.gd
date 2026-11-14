
# --- ui_edit ---------------------------------------------------------------------------------------------------------

const UI_OPS := ["build", "anchor", "touch_button", "touch_joystick", "read"]
const ANCHOR_PRESETS := {
	"top_left": Control.PRESET_TOP_LEFT, "top_right": Control.PRESET_TOP_RIGHT, "bottom_left": Control.PRESET_BOTTOM_LEFT,
	"bottom_right": Control.PRESET_BOTTOM_RIGHT, "center_left": Control.PRESET_CENTER_LEFT, "center_top": Control.PRESET_CENTER_TOP,
	"center_right": Control.PRESET_CENTER_RIGHT, "center_bottom": Control.PRESET_CENTER_BOTTOM, "center": Control.PRESET_CENTER,
	"left_wide": Control.PRESET_LEFT_WIDE, "top_wide": Control.PRESET_TOP_WIDE, "right_wide": Control.PRESET_RIGHT_WIDE,
	"bottom_wide": Control.PRESET_BOTTOM_WIDE, "vcenter_wide": Control.PRESET_VCENTER_WIDE,
	"hcenter_wide": Control.PRESET_HCENTER_WIDE, "full_rect": Control.PRESET_FULL_RECT,
}
const SIZE_FLAGS := {
	"fill": Control.SIZE_FILL, "expand": Control.SIZE_EXPAND, "expand_fill": Control.SIZE_EXPAND_FILL,
	"shrink_begin": Control.SIZE_SHRINK_BEGIN, "shrink_center": Control.SIZE_SHRINK_CENTER, "shrink_end": Control.SIZE_SHRINK_END,
}
const TOUCH_LAYER := "TouchControls"
const JOYSTICK_MODES := {"fixed": 0, "dynamic": 1, "following": 2}


## Interfaces: a Control tree built from one nested description, anchors, buttons a thumb presses and a virtual
## joystick for touch screens, and the layout read back. Each change to the open scene is one undo step.
func _ui_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, UI_OPS)
	if op.begins_with("!"):
		return _bad_op(op, UI_OPS)
	var params: Dictionary = args.params
	var root = _scene_root(params)
	if root is Dictionary:
		return root
	match op:
		"build":
			return _ui_build(root, params)
		"anchor":
			return _ui_anchor(root, params)
		"touch_button":
			return _touch_button(root, params)
		"touch_joystick":
			return _touch_joystick(root, params)
		_:
			return _ui_read(root, params)


## Builds `tree` ({type, name, text, properties, anchor, margin, min_size, h, v, theme, children}) under `parent`.
func _ui_build(root: Node, params: Dictionary) -> Dictionary:
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var spec = params.get("tree", null)
	if typeof(spec) != TYPE_DICTIONARY:
		return _fail("missing", "build needs 'tree': {\"type\": \"VBoxContainer\", \"anchor\": \"center\", \"children\": [{\"type\": \"Label\", \"text\": \"Score: 0\"}]}.")
	var layouts: Array = []
	var made = _ui_node(spec, layouts, "tree")
	if made is Dictionary:
		return made
	var steps: Array = []
	_add_layout_step(root, parent, made, layouts, steps)
	var answer := _commit_steps(root, steps, params)
	answer["nodes"] = _count_nodes(made)
	answer["next"] = "ui_edit read shows the layout as rectangles; screenshot editor_2d shows it."
	return answer


## A node for [spec] and its children, or a refusal naming where in the tree it is; anchors wait in [layouts] until the
## tree is in the scene, where they have a parent to measure.
func _ui_node(spec: Dictionary, layouts: Array, where: String):
	var made = _new_node(str(spec.get("type", "")))
	if made is Dictionary:
		made["at"] = where
		return made
	var node: Node = made
	if spec.has("name"):
		node.name = str(spec.name)
	if spec.has("text"):
		if not "text" in node:
			node.free()
			return _fail("no_text", "A %s has no text; %s." % [node.get_class(), where])
		node.set("text", str(spec.text))
	var props = spec.get("properties", {})
	if typeof(props) == TYPE_DICTIONARY:
		for key in props:
			var value := _typed_for(node, str(key), props[key])
			if value.has("error"):
				node.free()
				value["at"] = where
				return value
			node.set(str(key), value.value)
	if node is Control:
		var control := node as Control
		if spec.has("min_size"):
			var size := _numbers(spec.min_size, ["x", "y"])
			if size.size() == 2:
				control.custom_minimum_size = Vector2(size[0], size[1])
		for axis in ["h", "v"]:
			if spec.has(axis):
				var flag := str(spec[axis])
				if not SIZE_FLAGS.has(flag):
					node.free()
					return _fail("bad_value", "%s is one of: %s; %s." % [axis, ", ".join(PackedStringArray(SIZE_FLAGS.keys())), where])
				control.set("size_flags_horizontal" if axis == "h" else "size_flags_vertical", SIZE_FLAGS[flag])
		var themed := _theme_overrides(control, spec.get("theme", {}))
		if themed.has("error"):
			node.free()
			themed["at"] = where
			return themed
		if spec.has("anchor"):
			if not ANCHOR_PRESETS.has(str(spec.anchor)):
				node.free()
				return _fail("bad_value", "anchor is one of: %s; %s." % [", ".join(PackedStringArray(ANCHOR_PRESETS.keys())), where])
			layouts.append([control, ANCHOR_PRESETS[str(spec.anchor)], int(spec.get("margin", 0))])
	var children = spec.get("children", [])
	if typeof(children) == TYPE_ARRAY:
		for i in children.size():
			if typeof(children[i]) != TYPE_DICTIONARY:
				node.free()
				return _fail("bad_child", "Each child is an object with a 'type'; %s.children[%d]." % [where, i])
			var child = _ui_node(children[i], layouts, "%s.children[%d]" % [where, i])
			if child is Dictionary:
				node.free()
				return child
			node.add_child(child, true)
	return node


## Colours, font sizes, constants and flat styles a control uses in place of its theme's.
func _theme_overrides(control: Control, theme) -> Dictionary:
	if typeof(theme) != TYPE_DICTIONARY:
		return {}
	for key in theme.get("colors", {}):
		var color := _typed(theme.colors[key], {"name": key, "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
		if color.has("error"):
			return color
		control.add_theme_color_override(key, color.value)
	for key in theme.get("font_sizes", {}):
		control.add_theme_font_size_override(key, int(theme.font_sizes[key]))
	for key in theme.get("constants", {}):
		control.add_theme_constant_override(key, int(theme.constants[key]))
	for key in theme.get("styles", {}):
		var style = theme.styles[key]
		if typeof(style) != TYPE_DICTIONARY:
			return _fail("bad_style", "A style is {\"bg_color\": \"#20242c\", \"corner_radius\": 12, \"border_width\": 2, \"border_color\": …, \"content_margin\": 8}.")
		var box := StyleBoxFlat.new()
		if style.has("bg_color"):
			box.bg_color = _typed(style.bg_color, {"key": "bg_color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""}).get("value", box.bg_color)
		if style.has("border_color"):
			box.border_color = _typed(style.border_color, {"key": "border_color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""}).get("value", box.border_color)
		box.set_corner_radius_all(int(style.get("corner_radius", 0)))
		box.set_border_width_all(int(style.get("border_width", 0)))
		box.set_content_margin_all(float(style.get("content_margin", -1)))
		control.add_theme_stylebox_override(key, box)
	return {}


## Adds [node] under [parent], then applies [layouts], the anchors that need the node in the tree, as one step.
func _add_layout_step(root: Node, parent: Node, node: Node, layouts: Array, steps: Array) -> void:
	var do_add := func():
		parent.add_child(node, true)
		_own(node, root)
		for layout in layouts:
			# Sized first: a control just added has not measured its minimum size, so MINSIZE would anchor a 0x0 box.
			var control: Control = layout[0]
			control.size = control.size.max(control.custom_minimum_size).max(control.get_combined_minimum_size())
			control.set_anchors_and_offsets_preset(layout[1], Control.PRESET_MODE_KEEP_SIZE, layout[2])
	var undo_add := func():
		parent.remove_child(node)
	steps.append({"do": do_add, "undo": undo_add, "made": node, "text": "add " + str(node.name), "check": {"node": node, "parent": parent}})
	do_add.call()


func _count_nodes(node: Node) -> int:
	return 1 + node.find_children("*", "", true, false).size()


func _ui_anchor(root: Node, params: Dictionary) -> Dictionary:
	var found = _node_param(root, params, "node", ["Control"])
	if found is Dictionary:
		return found
	var control := found as Control
	var preset := str(params.get("preset", ""))
	if not ANCHOR_PRESETS.has(preset):
		return _fail("bad_value", "preset is one of: %s." % ", ".join(PackedStringArray(ANCHOR_PRESETS.keys())), {"did_you_mean": _nearest(preset, ANCHOR_PRESETS.keys())})
	var steps: Array = []
	var before := [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, control.offset_left, control.offset_top, control.offset_right, control.offset_bottom]
	var margin := int(params.get("margin", 0))
	var do_anchor := func(): control.set_anchors_and_offsets_preset(ANCHOR_PRESETS[preset], Control.PRESET_MODE_MINSIZE, margin)
	var undo_anchor := func():
		control.anchor_left = before[0]
		control.anchor_top = before[1]
		control.anchor_right = before[2]
		control.anchor_bottom = before[3]
		control.offset_left = before[4]
		control.offset_top = before[5]
		control.offset_right = before[6]
		control.offset_bottom = before[7]
	steps.append({"do": do_anchor, "undo": undo_anchor, "text": "anchor %s %s" % [control.name, preset]})
	do_anchor.call()
	return _commit_steps(root, steps, params)


## The CanvasLayer touch controls go on, so they stay put while a camera moves; made when the scene has none.
func _touch_layer(root: Node, steps: Array) -> Node:
	var layer := root.get_node_or_null(TOUCH_LAYER)
	if layer != null:
		return layer
	layer = CanvasLayer.new()
	layer.name = TOUCH_LAYER
	_add_step(root, root, layer, steps)
	return layer


## A round button the player's thumb presses, which presses an input action: a TouchScreenButton drawn as a soft
## circle, with a label, in a Control anchored to a corner of the screen.
func _touch_button(root: Node, params: Dictionary) -> Dictionary:
	var action := str(params.get("action", ""))
	if action.is_empty():
		return _fail("missing", "touch_button needs 'action', the input action it presses, such as jump.")
	var anchor := str(params.get("anchor", "bottom_right"))
	if not ANCHOR_PRESETS.has(anchor):
		return _fail("bad_value", "anchor is one of: %s." % ", ".join(PackedStringArray(ANCHOR_PRESETS.keys())))
	var radius := float(params.get("radius", 56))
	var steps: Array = []
	var layer := _touch_layer(root, steps)
	var holder := Control.new()
	holder.name = str(params.get("name", action.to_pascal_case() + "Button"))
	holder.custom_minimum_size = Vector2(radius, radius) * 2.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := TouchScreenButton.new()
	button.name = "Touch"
	button.action = action
	# A thumb sliding from one button onto the next presses it, as a thumb does on a real pad.
	button.passby_press = true
	button.texture_normal = _circle(radius, Color(1, 1, 1, 0.35))
	button.texture_pressed = _circle(radius, Color(1, 1, 1, 0.6))
	var shape := CircleShape2D.new()
	shape.radius = radius
	button.shape = shape
	button.shape_centered = true
	holder.add_child(button)
	if params.has("text"):
		var label := Label.new()
		label.name = "Label"
		label.text = str(params.text)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", int(radius * 0.6))
		holder.add_child(label)
	_add_layout_step(root, layer, holder, [[holder, ANCHOR_PRESETS[anchor], int(params.get("margin", 32))]], steps)
	var answer := _commit_steps(root, steps, params)
	answer["action"] = action
	if not InputMap.has_action(action) and not ProjectSettings.has_setting("input/" + action):
		answer["next"] = "The project has no input action %s yet; project_edit input_action_set adds it, and the game reads it with Input.is_action_pressed." % action
	return answer


## Godot's VirtualJoystick, which presses the four direction actions as the thumb moves, anchored to a corner.
func _touch_joystick(root: Node, params: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("VirtualJoystick"):
		return _fail("unavailable", "This editor has no VirtualJoystick.")
	var mode := str(params.get("mode", "dynamic"))
	if not JOYSTICK_MODES.has(mode):
		return _fail("bad_value", "mode is one of: fixed, dynamic, following.")
	var anchor := str(params.get("anchor", "bottom_left"))
	if not ANCHOR_PRESETS.has(anchor):
		return _fail("bad_value", "anchor is one of: %s." % ", ".join(PackedStringArray(ANCHOR_PRESETS.keys())))
	var size := float(params.get("size", 160))
	var steps: Array = []
	var layer := _touch_layer(root, steps)
	var joystick: Control = ClassDB.instantiate("VirtualJoystick")
	joystick.name = str(params.get("name", "Joystick"))
	var actions = params.get("actions", {})
	var directions := {"left": "ui_left", "right": "ui_right", "up": "ui_up", "down": "ui_down"}
	for direction in directions:
		var wanted = actions.get(direction, directions[direction]) if typeof(actions) == TYPE_DICTIONARY else directions[direction]
		joystick.set("action_" + direction, StringName(str(wanted)))
	joystick.set("joystick_mode", JOYSTICK_MODES[mode])
	joystick.set("joystick_size", size)
	joystick.set("tip_size", size / 2.0)
	joystick.custom_minimum_size = Vector2(size, size) * 1.5
	_add_layout_step(root, layer, joystick, [[joystick, ANCHOR_PRESETS[anchor], int(params.get("margin", 32))]], steps)
	var answer := _commit_steps(root, steps, params)
	answer["actions"] = directions.keys().map(func(d): return str(joystick.get("action_" + d)))
	answer["next"] = "The game reads it with Input.get_vector(left, right, up, down); input sends taps to test it in a running game."
	return answer


## A soft round texture of [radius], drawn by the engine, so a button needs no image file.
func _circle(radius: float, color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.add_point(0.85, color)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(radius * 2.0)
	texture.height = int(radius * 2.0)
	return texture


## The controls under `node` (the scene by default) as rectangles in the base viewport, with their text and what
## looks wrong: no size, or outside the screen.
func _ui_read(root: Node, params: Dictionary) -> Dictionary:
	var found = _node_param(root, params, "node")
	if found is Dictionary:
		return found
	var screen := Rect2(Vector2.ZERO, Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height")))
	var controls: Array = []
	var nodes: Array = [found] + found.find_children("*", "Control", true, false)
	for node in nodes:
		if not node is Control:
			continue
		var rect: Rect2 = node.get_global_rect()
		var entry := {"path": _node_path(node), "type": node.get_class(), "rect": _plain(rect), "visible": node.is_visible_in_tree()}
		if "text" in node and not str(node.get("text")).is_empty():
			entry["text"] = str(node.get("text"))
		var problems: Array = []
		if rect.size.x < 1 or rect.size.y < 1:
			problems.append("no size")
		elif not screen.encloses(rect):
			problems.append("partly outside the %dx%d screen" % [screen.size.x, screen.size.y])
		if not problems.is_empty():
			entry["problems"] = problems
		controls.append(entry)
		if controls.size() >= MAX_LIST:
			break
	return {"screen": _plain(screen.size), "controls": controls}
