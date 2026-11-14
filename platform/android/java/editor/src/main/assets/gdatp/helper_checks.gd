# --- checks ---------------------------------------------------------------------------------------------------------
# A part of the game helper: GDatpPlugin.gameHelperSource appends each gdatp/helper_*.gd after game_helper.gd, so
# these are the same script, sharing its helpers.

const CHECK_KINDS := ["equals", "not_equals", "near", "gt", "lt", "contains"]
## Names a model uses for a body's state that are engine methods rather than properties.
const GETTER_ALIASES := {"on_floor": "is_on_floor", "on_wall": "is_on_wall", "on_ceiling": "is_on_ceiling"}
const MAX_SAMPLE_FRAMES := 300
const MAX_SAMPLE_PROPERTIES := 8
## Whether an engine method needs no arguments, by "Class.method".
var _getters := {}


## Pass or fail for each check against the running game's state, so a test's outcome comes from the game and not from
## a reading of its picture.
func _check(scene: Node, checks: Array) -> Dictionary:
	var results: Array = []
	var failed := 0
	for check in checks:
		var result := _check_one(scene, check)
		if not result.get("passed", false):
			failed += 1
		results.append(result)
	return {"passed": failed == 0, "failed": failed, "results": results, "frame": _ran_frames}


## One check: a node at `path` (or the count of a `group`), a `property` of it, and one of equals, not_equals, near
## (with `tolerance`), gt, lt and contains; or `exists`. Values are typed as the property is, so [x, y] matches a vector.
func _check_one(scene: Node, check) -> Dictionary:
	if typeof(check) != TYPE_DICTIONARY:
		return {"passed": false, "error": "bad_check", "message": "A check is {\"path\", \"property\", and one of equals, not_equals, near, gt, lt, contains, exists}."}
	var result := {}
	var actual = null
	if check.has("group"):
		result["group"] = str(check.group)
		actual = get_tree().get_nodes_in_group(str(check.group)).size()
		result["property"] = "count"
	else:
		var path := str(check.get("path", "."))
		result["path"] = path
		var node := _find(scene, path)
		if check.has("exists"):
			result["exists"] = node != null
			result["passed"] = (node != null) == _flag(check.exists)
			return result
		if node == null:
			result.merge({"passed": false, "error": "not_found", "message": "There is no node '%s' in the running scene." % path})
			return result
		var property := str(check.get("property", ""))
		result["property"] = property
		var read := _value_of(node, property)
		if read.has("error"):
			result.merge(read)
			result["passed"] = false
			return result
		actual = read.value
	result["actual"] = _shown(scene, actual)
	var kind := ""
	for candidate in CHECK_KINDS:
		if check.has(candidate):
			kind = candidate
			break
	if kind.is_empty():
		result.merge({"passed": false, "error": "bad_check", "message": "A check names one of: equals, not_equals, near, gt, lt, contains, exists."})
		return result
	var wanted = check[kind]
	result[kind] = wanted
	if not typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH]:
		wanted = _loose(wanted)
	match kind:
		"equals", "not_equals":
			var same := _equal(scene, actual, wanted)
			result["passed"] = same if kind == "equals" else not same
		"near":
			result["tolerance"] = absf(float(check.get("tolerance", 0.01)))
			result["passed"] = _within(_plain(actual), wanted, result.tolerance)
		"gt", "lt":
			if not typeof(actual) in [TYPE_INT, TYPE_FLOAT] or not typeof(wanted) in [TYPE_INT, TYPE_FLOAT]:
				result.merge({"passed": false, "error": "not_a_number", "message": "%s compares numbers; %s is %s." % [kind, result.property, type_string(typeof(actual))]})
			else:
				result["passed"] = float(actual) > float(wanted) if kind == "gt" else float(actual) < float(wanted)
		"contains":
			if typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH]:
				result["passed"] = str(actual).to_lower().contains(str(wanted).to_lower())
			elif typeof(actual) == TYPE_ARRAY or typeof(actual) >= TYPE_PACKED_BYTE_ARRAY:
				result["passed"] = false
				for item in Array(actual):
					if _equal(scene, item, wanted):
						result["passed"] = true
						break
			else:
				result.merge({"passed": false, "error": "not_a_list", "message": "contains looks in text or a list; %s is %s." % [result.property, type_string(typeof(actual))]})
	return result


## Whether [actual] is [wanted] once [wanted] is typed as [actual] is; a node matches its name or its path.
func _equal(scene: Node, actual, wanted) -> bool:
	if actual is Node:
		return str(actual.name) == str(wanted) or (scene != null and _path(scene, actual) == str(wanted))
	if typeof(actual) == TYPE_NIL or typeof(wanted) == TYPE_NIL:
		return typeof(actual) == typeof(wanted)
	var typed := _typed(wanted, {"name": "value", "type": typeof(actual), "hint": PROPERTY_HINT_NONE, "hint_string": ""})
	return not typed.has("error") and _same(actual, typed.value)


func _within(actual, wanted, tolerance: float) -> bool:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(wanted) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(actual) - float(wanted)) <= tolerance
	if typeof(actual) == TYPE_ARRAY and typeof(wanted) == TYPE_ARRAY and actual.size() == wanted.size():
		for i in actual.size():
			if not _within(actual[i], wanted[i], tolerance):
				return false
		return true
	return false


## A property of a node in the running game, as {"value": …}: indexed paths such as position:y, or an engine getter
## that needs no arguments, named is_, get_, has_ or can_ (is_on_floor, get_overlapping_bodies, get_child_count), so a
## check can ask what a node's stored properties do not hold. Script methods are not called.
func _value_of(node: Node, property: String) -> Dictionary:
	if property.is_empty():
		return {"error": "missing", "message": "A check needs 'property', such as position:x or is_on_floor."}
	var method: String = GETTER_ALIASES.get(property.trim_suffix("()"), property.trim_suffix("()"))
	if _is_getter(node, method):
		return {"value": node.call(method)}
	var base := property.get_slice(":", 0)
	if not base in node:
		var names: Array = []
		for info in node.get_property_list():
			if info.usage & (PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE):
				names.append(info.name)
		return _fail("unknown_property", "%s has no property '%s'." % [node.get_class(), base], {"did_you_mean": _nearest(base, names)})
	return {"value": node.get_indexed(NodePath(property))}


func _is_getter(node: Node, method: String) -> bool:
	if not (method.begins_with("is_") or method.begins_with("get_") or method.begins_with("has_") or method.begins_with("can_")):
		return false
	var key := node.get_class() + "." + method
	if not _getters.has(key):
		var needs_none := false
		for info in ClassDB.class_get_method_list(node.get_class()):
			if info.name == method:
				needs_none = info.args.size() == info.default_args.size()
				break
		_getters[key] = needs_none
	return _getters[key]


## A value as JSON for an answer: a node as its path in the running scene, a list of nodes as their paths.
func _shown(scene: Node, value):
	if value is Node:
		return _path(scene, value) if scene != null and (value == scene or scene.is_ancestor_of(value)) else str(value.name)
	if typeof(value) == TYPE_ARRAY:
		var shown: Array = []
		for item in value:
			shown.append(_shown(scene, item))
		return shown
	return _plain(value)


## A node's properties read on each of the next `frames` physics frames, every `every` frames, for movement over time
## such as a jump's arc; numbers also get their first, last, lowest and highest.
func _sample(scene: Node, params: Dictionary) -> Dictionary:
	var path := str(params.get("path", "."))
	var node := _find(scene, path)
	if node == null:
		return {"error": "not_found", "message": "There is no node '%s' in the running scene." % path}
	var wanted = params.get("properties", [])
	if typeof(wanted) != TYPE_ARRAY or wanted.is_empty():
		return {"error": "missing", "message": "sample needs 'properties', such as [\"position:y\", \"velocity\", \"is_on_floor\"]."}
	var properties: Array = wanted.slice(0, MAX_SAMPLE_PROPERTIES).map(func(item): return str(item))
	for property in properties:
		var first := _value_of(node, property)
		if first.has("error"):
			return first
	if not can_process():
		return {"error": "paused", "message": "The game is paused from the editor, so nothing would change; run resume lets it go on first."}
	var frames := clampi(int(params.get("frames", 30)), 1, MAX_SAMPLE_FRAMES)
	var every := clampi(int(params.get("every", 1)), 1, 60)
	var columns := {}
	for property in properties:
		columns[property] = []
	var start_frame := _ran_physics_frames
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(node):
			return {"error": "gone", "message": "%s left the scene after %d frames." % [path, i], "samples": columns}
		if not can_process():
			return {"error": "paused", "message": "The game was paused from the editor after %d frames." % i, "samples": columns}
		if i % every != 0:
			continue
		for property in properties:
			columns[property].append(_shown(scene, _value_of(node, property).get("value")))
	var summary := {}
	for property in properties:
		var numbers: Array = columns[property].filter(func(item): return typeof(item) in [TYPE_INT, TYPE_FLOAT])
		if numbers.size() == columns[property].size() and not numbers.is_empty():
			summary[property] = {"first": numbers[0], "last": numbers[-1], "min": numbers.min(), "max": numbers.max()}
	return {"path": path, "frames": frames, "every": every, "from_physics_frame": start_frame, "samples": columns, "summary": summary}


# --- look check -------------------------------------------------------------------------------------------------------

const LOOK_SAMPLES_ACROSS := 160
const LOOK_FLAT_PERCENT := 25
const LOOK_MAX_NOTES := 5
const LOOK_MIN_TEXT_SHARE := 0.022
const LOOK_OVERLAP_SHARE := 0.2
## A line of text fills less of its box than its box suggests: this much at top and bottom is empty.
const LOOK_LINE_PADDING := 0.16
## A pixel is nearly black when even its brightest channel is below this: a deep blue night is dark but coloured.
const LOOK_DARK_LIGHT := 0.1
const LOOK_DARK_PERCENT := 60
const LOOK_BLOCK_PX := 24
const LOOK_BLOCK_SPREAD := 0.014
const LOOK_FLAT_SURFACE_PERCENT := 72
const LOOK_EDGE_PX := 1.0
const ENGINE_DEFAULT_CLEAR := Color(0.3, 0.3, 0.3)


## What anyone would see at once in this frame, measured: a model reads numbers more surely than it reads a picture.
func _look_check(image: Image) -> Array:
	var window := _shown_area(image)
	var found := _flat_colours(image, Rect2i(window)) + _too_dark(image, Rect2i(window))
	if get_viewport().get_camera_3d() != null:
		found += _bare_surfaces(image, Rect2i(window))
	var scene := get_tree().current_scene
	if scene == null:
		return found
	if scene is Control and scene.size.x < 1.0 and scene.get_child_count() > 0:
		found.append("The scene's root \"%s\" has no size, so whatever fills it draws nothing. Give it the full-screen layout: ui_edit anchor, preset full_rect." % scene.name)
	var texts: Array = []
	for node in scene.find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and node.modulate.a > 0.1 and "text" in node and not str(node.text).strip_edges().is_empty():
			texts.append({"words": str(node.text).strip_edges().left(30), "rect": _text_rect(node), "height": _text_height(node)})
	for text in texts:
		if text.height < window.size.y * LOOK_MIN_TEXT_SHARE:
			found.append("\"%s\" is too small to read on a phone: %d px tall on a screen %d px high. Make it at least %d." % [
				text.words, roundi(text.height), roundi(window.size.y), ceili(window.size.y * LOOK_MIN_TEXT_SHARE)])
		if not window.grow(LOOK_EDGE_PX).encloses(text.rect):
			found.append("\"%s\" runs off the screen." % text.words)
	for i in texts.size():
		for j in range(i + 1, texts.size()):
			# The same words twice in one place are copies of one thing, such as a floating number shown again.
			if texts[i].words == texts[j].words:
				continue
			var first_words := _ink(texts[i].rect)
			var second_words := _ink(texts[j].rect)
			if first_words.intersection(second_words).get_area() > minf(first_words.get_area(), second_words.get_area()) * LOOK_OVERLAP_SHARE:
				found.append("\"%s\" and \"%s\" are drawn on top of each other. Place them apart (ui_edit build)." % [texts[i].words, texts[j].words])
	# Several copies of one label, such as floating numbers, say one thing once, so the notes left are other findings.
	var notes: Array = []
	for note in found:
		if not notes.has(note):
			notes.append(note)
	return notes.slice(0, LOOK_MAX_NOTES)


## The part of the window the game draws in, without the bars beside a project kept to its own shape.
func _shown_area(image: Image) -> Rect2:
	var root := get_tree().root
	var to_window := root.get_final_transform()
	var visible := root.get_visible_rect()
	var area := Rect2(to_window * visible.position, to_window.basis_xform(visible.size)).abs()
	return area.intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))


func _flat_colours(image: Image, area: Rect2i) -> Array:
	var counts := {}
	var seen := 0
	var step := maxi(1, floori(float(area.size.x) / LOOK_SAMPLES_ACROSS))
	for y in range(area.position.y, area.end.y, step):
		for x in range(area.position.x, area.end.x, step):
			var colour := image.get_pixel(x, y).to_html(false)
			counts[colour] = int(counts.get(colour, 0)) + 1
			seen += 1
	var found: Array = []
	for colour in counts:
		var share := floori(100.0 * int(counts[colour]) / seen)
		if share < LOOK_FLAT_PERCENT:
			continue
		if colour == ENGINE_DEFAULT_CLEAR.to_html(false):
			var window := get_viewport().get_visible_rect().size
			found.append("%d%% of this picture is the engine's default grey: nothing is drawn there. This is the game as a phone shows it, not an editor's preview. Its window is %dx%d, so size a background from get_viewport_rect().size rather than from a number; in 3D give it a sky or a world around the camera (world3d_edit environment)." % [share, window.x, window.y])
		else:
			found.append("%d%% of this picture is one flat colour, #%s: nothing is drawn there. Unless the look calls for it, draw something there, or frame the camera so the world fills the screen." % [share, colour])
	return found


func _ink(line: Rect2) -> Rect2:
	var padding := line.size.y * LOOK_LINE_PADDING
	return line.grow_individual(0.0, -padding, 0.0, -padding)


## A frame nearly all black has lost its lights, or its camera is inside something.
func _too_dark(image: Image, area: Rect2i) -> Array:
	var dark := 0
	var seen := 0
	var stride := maxi(1, floori(float(area.size.x) / LOOK_SAMPLES_ACROSS))
	for y in range(area.position.y, area.end.y, stride):
		for x in range(area.position.x, area.end.x, stride):
			seen += 1
			if image.get_pixel(x, y).v < LOOK_DARK_LIGHT:
				dark += 1
	var share := floori(100.0 * dark / maxi(seen, 1))
	if share < LOOK_DARK_PERCENT:
		return []
	return ["%d%% of this picture is nearly black. Unless the look calls for it, the scene has lost its light or the camera is inside something: add light (parts sky) and check where the camera is." % share]


## How much of a 3D frame's lower part, where the world is rather than the sky, is surface with no detail in it at all.
func _bare_surfaces(image: Image, area: Rect2i) -> Array:
	var bare := 0
	var seen := 0
	var top := area.position.y + floori(area.size.y * 0.4)
	for y in range(top, area.end.y - LOOK_BLOCK_PX, LOOK_BLOCK_PX):
		for x in range(area.position.x, area.end.x - LOOK_BLOCK_PX, LOOK_BLOCK_PX):
			var lowest := 1.0
			var highest := 0.0
			for dy in range(0, LOOK_BLOCK_PX, 6):
				for dx in range(0, LOOK_BLOCK_PX, 6):
					var light := image.get_pixel(x + dx, y + dy).get_luminance()
					lowest = minf(lowest, light)
					highest = maxf(highest, light)
			seen += 1
			if highest - lowest < LOOK_BLOCK_SPREAD:
				bare += 1
	var share := floori(100.0 * bare / maxi(seen, 1))
	if share < LOOK_FLAT_SURFACE_PERCENT:
		return []
	return ["%d%% of the world in this picture is bare surface with no detail, which reads as unfinished. Unless the look calls for it, give surfaces texture (parts paint makes grass, stone, brick and more) and light that shows their shape (parts sky)." % share]


func _text_transform(node: Control) -> Transform2D:
	return get_tree().root.get_final_transform() * node.get_global_transform_with_canvas()


func _text_height(node: Control) -> float:
	return node.get_theme_font_size("font_size") * _text_transform(node).get_scale().y


## Where the words themselves are, in the game window's pixels. A label is often far larger than what it says, so its rectangle would overlap others that its words do not touch.
func _text_rect(node: Control) -> Rect2:
	var wraps: bool = "autowrap_mode" in node and node.autowrap_mode != TextServer.AUTOWRAP_OFF
	var size: Vector2 = node.get_theme_font("font").get_multiline_string_size(
		str(node.text), HORIZONTAL_ALIGNMENT_LEFT, node.size.x if wraps else -1.0, node.get_theme_font_size("font_size"))
	var across := 0.5
	if "horizontal_alignment" in node:
		across = [0.0, 0.5, 1.0, 0.0][int(node.horizontal_alignment)]
	elif "alignment" in node:
		across = [0.0, 0.5, 1.0, 0.0][int(node.alignment)]
	var down := 0.5
	if "vertical_alignment" in node:
		down = [0.0, 0.5, 1.0, 0.0][int(node.vertical_alignment)]
	var area := Rect2((node.size - size) * Vector2(across, down), size)
	var to_window := _text_transform(node)
	return Rect2(to_window * area.position, to_window.basis_xform(area.size)).abs()
