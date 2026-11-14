# --- values: JSON to typed values and back --------------------------------------------------------------------------
# Shared by the tool host and the game helper: GDatpPlugin appends each gdatp/shared_*.gd to both scripts, so the
# editor and the running game read and write values the same way. Only engine APIs a running game has belong here.

const LAYER_HINTS := [
	PROPERTY_HINT_LAYERS_2D_PHYSICS, PROPERTY_HINT_LAYERS_2D_RENDER, PROPERTY_HINT_LAYERS_2D_NAVIGATION,
	PROPERTY_HINT_LAYERS_3D_PHYSICS, PROPERTY_HINT_LAYERS_3D_RENDER, PROPERTY_HINT_LAYERS_3D_NAVIGATION,
	PROPERTY_HINT_LAYERS_AVOIDANCE,
]
const LAYER_SETTINGS := {
	PROPERTY_HINT_LAYERS_2D_PHYSICS: "2d_physics", PROPERTY_HINT_LAYERS_2D_RENDER: "2d_render",
	PROPERTY_HINT_LAYERS_2D_NAVIGATION: "2d_navigation", PROPERTY_HINT_LAYERS_3D_PHYSICS: "3d_physics",
	PROPERTY_HINT_LAYERS_3D_RENDER: "3d_render", PROPERTY_HINT_LAYERS_3D_NAVIGATION: "3d_navigation",
	PROPERTY_HINT_LAYERS_AVOIDANCE: "avoidance",
}
## A screenshot burst: at most this many frames, this far apart, within this span. The game helper takes the frames and
## the tool host waits for them, so both read these.
const BURST_MAX := 9
const BURST_EVERY_MS := 250.0
const BURST_EVERY_MS_MIN := 33.0
const BURST_EVERY_MS_MAX := 2000.0
const BURST_SPAN_MS_MAX := 12000.0


func _fail(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var answer := {"error": code, "message": message}
	answer.merge(extra)
	return answer


## A yes or no that also accepts the strings "true" and "false" and numbers, as models send them.
func _flag(value) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).to_lower() in ["true", "yes", "1"]
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		_:
			return false


func _nearest(word: String, words: Array) -> String:
	var best := ""
	var best_score := 0.3
	for candidate in words:
		var score := word.similarity(str(candidate))
		if score > best_score:
			best = str(candidate)
			best_score = score
	return best


## A project path, or "!" and why it is refused: paths stay inside res:// and out of .godot.
func _res_path(value) -> String:
	var path := str(value).strip_edges()
	if path.is_empty():
		return "!A path is needed, starting with res://."
	if not path.begins_with("res://"):
		path = "res://" + path.trim_prefix("/")
	path = path.simplify_path()
	if not path.begins_with("res://") or path.contains(".."):
		return "!%s is outside the project." % value
	if path == "res://.godot" or path.begins_with("res://.godot/"):
		return "!The editor's own .godot folder is not part of the project's files."
	return path


func _numbers(value, keys: Array) -> Array:
	var numbers: Array = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			numbers.append(float(item))
	elif typeof(value) == TYPE_DICTIONARY:
		for key in keys:
			if value.has(key):
				numbers.append(float(value[key]))
	return numbers


## A value written as text, read as what the text holds: "5" is 5, "true" is true, "[100, 200]" a list; other text,
## and every value that is not text, stays as it is. Hosts that need a type on every parameter send an open-ended one
## as text.
func _loose(value):
	if typeof(value) != TYPE_STRING:
		return value
	var text: String = value.strip_edges()
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	if text in ["true", "false"]:
		return text == "true"
	if text.begins_with("[") or text.begins_with("{"):
		var json := JSON.new()
		if json.parse(text) == OK:
			return json.data
	return value


func _enum_value(wanted: String, hint: String):
	var index := 0
	for item in hint.split(","):
		var parts: PackedStringArray = str(item).split(":")
		var label: String = parts[0].strip_edges()
		var number := int(parts[1]) if parts.size() > 1 else index
		if label.to_lower() == wanted.to_lower() or label.to_snake_case() == wanted.to_snake_case():
			return number
		index = number + 1
	return null


func _is_any_class(object: Object, classes: String) -> bool:
	for candidate in classes.split(","):
		if object.is_class(str(candidate).strip_edges()):
			return true
	return false


## [value] converted to the type of [object]'s property [name], as {"value": …} or a refusal naming real properties.
func _typed_for(object: Object, property_name: String, value) -> Dictionary:
	var info := {}
	for property in object.get_property_list():
		if property.name == property_name:
			info = property
			break
	if info.is_empty():
		var names: Array = object.get_property_list().filter(func(p): return p.usage & PROPERTY_USAGE_EDITOR).map(func(p): return p.name)
		return _fail("unknown_property", "%s has no property '%s'." % [object.get_class(), property_name], {"did_you_mean": _nearest(property_name, names)})
	return _typed(value, info)


func _typed(value, info: Dictionary) -> Dictionary:
	var type := int(info.type)
	if not type in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		value = _loose(value)
	match type:
		TYPE_BOOL:
			return {"value": _flag(value)}
		TYPE_INT:
			if typeof(value) == TYPE_STRING and int(info.hint) == PROPERTY_HINT_ENUM:
				var index = _enum_value(str(value), str(info.hint_string))
				if index == null:
					return _fail("bad_value", "%s is one of: %s." % [info.name, info.hint_string])
				return {"value": index}
			if typeof(value) == TYPE_ARRAY or (typeof(value) == TYPE_STRING and _is_flags(info)):
				return _flags_value(value, info)
			return {"value": int(value)}
		TYPE_FLOAT:
			return {"value": float(value)}
		TYPE_STRING:
			return {"value": str(value)}
		TYPE_STRING_NAME:
			return {"value": StringName(str(value))}
		TYPE_NODE_PATH:
			return {"value": NodePath(str(value))}
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			var numbers := _numbers(value, ["x", "y", "z", "w"])
			var size: int = {TYPE_VECTOR2: 2, TYPE_VECTOR2I: 2, TYPE_VECTOR3: 3, TYPE_VECTOR3I: 3, TYPE_VECTOR4: 4, TYPE_VECTOR4I: 4}[type]
			if numbers.size() != size:
				return _fail("bad_value", "%s takes %d numbers, like %s." % [info.name, size, str([0, 0, 0, 0].slice(0, size))])
			match type:
				TYPE_VECTOR2:
					return {"value": Vector2(numbers[0], numbers[1])}
				TYPE_VECTOR2I:
					return {"value": Vector2i(int(numbers[0]), int(numbers[1]))}
				TYPE_VECTOR3:
					return {"value": Vector3(numbers[0], numbers[1], numbers[2])}
				TYPE_VECTOR3I:
					return {"value": Vector3i(int(numbers[0]), int(numbers[1]), int(numbers[2]))}
				TYPE_VECTOR4:
					return {"value": Vector4(numbers[0], numbers[1], numbers[2], numbers[3])}
				_:
					return {"value": Vector4i(int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3]))}
		TYPE_COLOR:
			if typeof(value) == TYPE_STRING:
				if Color.html_is_valid(value):
					return {"value": Color.html(value)}
				var named := Color.from_string(value, Color(0, 0, 0, 0))
				if named == Color(0, 0, 0, 0) and value.to_lower() != "transparent":
					return _fail("bad_value", "'%s' is not a colour; use #rrggbb, #rrggbbaa or a name like red." % value)
				return {"value": named}
			var parts := _numbers(value, ["r", "g", "b", "a"])
			if parts.size() < 3:
				return _fail("bad_value", "A colour is #rrggbb, a name, or [r, g, b] or [r, g, b, a] from 0 to 1.")
			return {"value": Color(parts[0], parts[1], parts[2], parts[3] if parts.size() > 3 else 1.0)}
		TYPE_RECT2, TYPE_RECT2I:
			var rect: Array = []
			if typeof(value) == TYPE_DICTIONARY:
				rect = _numbers(value.get("position", [0, 0]), ["x", "y"]) + _numbers(value.get("size", [0, 0]), ["x", "y"])
			else:
				rect = _numbers(value, ["x", "y", "w", "h"])
			if rect.size() != 4:
				return _fail("bad_value", "A rectangle is [x, y, width, height] or {position, size}.")
			if type == TYPE_RECT2:
				return {"value": Rect2(rect[0], rect[1], rect[2], rect[3])}
			return {"value": Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))}
		TYPE_OBJECT:
			return _typed_resource(value, info)
		TYPE_PACKED_VECTOR2_ARRAY:
			var points := PackedVector2Array()
			for point in (value if typeof(value) == TYPE_ARRAY else []):
				var xy := _numbers(point, ["x", "y"])
				if xy.size() != 2:
					return _fail("bad_value", "%s takes a list of [x, y] points." % info.name)
				points.append(Vector2(xy[0], xy[1]))
			return {"value": points}
		_:
			return _typed_more(value, info)


## A resource for an object property: "res://…" loads one, {"type": "RectangleShape2D", "size": [32, 32]} makes one.
func _typed_resource(value, info: Dictionary) -> Dictionary:
	var wanted := str(info.hint_string)
	if value == null:
		return {"value": null}
	if typeof(value) == TYPE_STRING:
		var path := _res_path(value)
		if path.begins_with("!") or not ResourceLoader.exists(path):
			return _fail("not_found", "There is no resource %s." % value, {"next": "files_read list finds the project's files."})
		var resource := load(path)
		if not wanted.is_empty() and not _is_any_class(resource, wanted):
			return _fail("wrong_type", "%s is a %s; %s takes %s." % [path, resource.get_class(), info.name, wanted])
		return {"value": resource}
	if typeof(value) == TYPE_DICTIONARY and value.has("type"):
		var type := str(value.type)
		if not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type, "Resource") or not ClassDB.can_instantiate(type):
			var names: Array = Array(ClassDB.get_inheriters_from_class(wanted if ClassDB.class_exists(wanted) else "Resource"))
			return _fail("unknown_class", "There is no resource class '%s'." % type, {"did_you_mean": _nearest(type, names)})
		var resource: Resource = ClassDB.instantiate(type)
		if not wanted.is_empty() and not _is_any_class(resource, wanted):
			return _fail("wrong_type", "%s takes %s, not %s." % [info.name, wanted, type])
		for key in value:
			if key == "type":
				continue
			var inner := _typed_for(resource, str(key), value[key])
			if inner.has("error"):
				return inner
			resource.set(str(key), inner.value)
		return {"value": resource}
	return _fail("bad_value", "%s takes a resource: \"res://…\" or {\"type\": \"%s\", …}." % [info.name, wanted if not wanted.is_empty() else "Resource"])


## [value] typed for an indexed property such as "shape:size", a property of a sub-resource, or "modulate:a", one
## part of a vector or colour.
func _typed_indexed(object: Object, property: String, value) -> Dictionary:
	var at := property.rfind(":")
	var holder = object.get_indexed(NodePath(property.left(at)))
	var leaf := property.substr(at + 1)
	if holder is Object:
		return _typed_for(holder, leaf, value)
	if holder == null:
		return _fail("unknown_property", "%s has nothing at '%s'." % [object.get_class(), property.left(at)],
			{"next": "Set the resource first, such as {\"shape\": {\"type\": \"RectangleShape2D\"}}, then its properties."})
	if typeof(holder) in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR, TYPE_QUATERNION]:
		value = _loose(value)
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		if typeof(holder) in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I, TYPE_RECT2I]:
			return {"value": int(value)}
		return {"value": float(value)}
	return {"value": value}


func _is_flags(info: Dictionary) -> bool:
	return int(info.hint) == PROPERTY_HINT_FLAGS or int(info.hint) in LAYER_HINTS


## Bits from names or numbers: a layer property takes layer numbers (1 to 32) or the names the project gave them, and a
## flags property the names its hint lists.
func _flags_value(value, info: Dictionary) -> Dictionary:
	var items: Array = value if typeof(value) == TYPE_ARRAY else Array(str(value).split(","))
	var hint := int(info.hint)
	var bits := 0
	if hint in LAYER_HINTS:
		var kind: String = LAYER_SETTINGS[hint]
		for item in items:
			var layer := _layer_number(item, kind)
			if layer < 1 or layer > 32:
				return _fail("bad_value", "%s takes layer numbers 1 to 32 or layer names; '%s' is neither." % [info.name, str(item)],
					{"next": "project_read settings with prefix layer_names/%s lists the names." % kind})
			bits |= 1 << (layer - 1)
		return {"value": bits}
	if hint == PROPERTY_HINT_FLAGS:
		var flags := {}
		var bit := 1
		for entry in str(info.hint_string).split(","):
			var parts: PackedStringArray = str(entry).split(":")
			var mask := int(parts[1]) if parts.size() > 1 else bit
			flags[parts[0].strip_edges().to_lower()] = mask
			bit = mask << 1
		for item in items:
			var flag_name := str(item).strip_edges().to_lower()
			if not flags.has(flag_name):
				return _fail("bad_value", "%s takes flags from: %s." % [info.name, info.hint_string])
			bits |= int(flags[flag_name])
		return {"value": bits}
	return _fail("bad_value", "%s takes a number." % info.name)


func _layer_number(item, kind: String) -> int:
	if typeof(item) in [TYPE_INT, TYPE_FLOAT]:
		return int(item)
	var wanted := str(item).strip_edges()
	if wanted.is_valid_int():
		return int(wanted)
	for layer in range(1, 33):
		var setting := "layer_names/%s/layer_%d" % [kind, layer]
		if ProjectSettings.has_setting(setting) and str(ProjectSettings.get_setting(setting)).to_lower() == wanted.to_lower():
			return layer
	return 0


## Transforms, rotations, boxes, planes and packed lists, from the JSON a model writes; the core's _typed hands over
## every type it does not read itself.
func _typed_more(value, info: Dictionary) -> Dictionary:
	match int(info.type):
		TYPE_TRANSFORM2D:
			if typeof(value) != TYPE_DICTIONARY:
				return _fail("bad_value", "%s takes {\"origin\": [x, y], \"rotation_degrees\": 0, \"scale\": [1, 1]}." % info.name)
			var origin := _numbers(value.get("origin", [0, 0]), ["x", "y"])
			var scale := _numbers(value.get("scale", [1, 1]), ["x", "y"])
			if origin.size() != 2 or scale.size() != 2:
				return _fail("bad_value", "origin and scale each take two numbers.")
			return {"value": Transform2D(deg_to_rad(float(value.get("rotation_degrees", 0))), Vector2(scale[0], scale[1]), 0.0, Vector2(origin[0], origin[1]))}
		TYPE_TRANSFORM3D:
			if typeof(value) != TYPE_DICTIONARY:
				return _fail("bad_value", "%s takes {\"origin\": [x, y, z], \"rotation_degrees\": [x, y, z], \"scale\": [1, 1, 1]}." % info.name)
			var basis = _basis(value)
			if basis is Dictionary:
				return basis
			var origin := _numbers(value.get("origin", [0, 0, 0]), ["x", "y", "z"])
			if origin.size() != 3:
				return _fail("bad_value", "origin takes three numbers.")
			return {"value": Transform3D(basis, Vector3(origin[0], origin[1], origin[2]))}
		TYPE_BASIS:
			var basis = _basis(value if typeof(value) == TYPE_DICTIONARY else {"rotation_degrees": value})
			return basis if basis is Dictionary else {"value": basis}
		TYPE_QUATERNION:
			if typeof(value) == TYPE_DICTIONARY:
				var degrees := _numbers(value.get("rotation_degrees", [0, 0, 0]), ["x", "y", "z"])
				if degrees.size() != 3:
					return _fail("bad_value", "rotation_degrees takes three numbers.")
				return {"value": Quaternion.from_euler(Vector3(deg_to_rad(degrees[0]), deg_to_rad(degrees[1]), deg_to_rad(degrees[2])))}
			var q := _numbers(value, ["x", "y", "z", "w"])
			if q.size() != 4:
				return _fail("bad_value", "%s takes [x, y, z, w] or {\"rotation_degrees\": [x, y, z]}." % info.name)
			return {"value": Quaternion(q[0], q[1], q[2], q[3])}
		TYPE_AABB:
			var box: Array = []
			if typeof(value) == TYPE_DICTIONARY:
				box = _numbers(value.get("position", [0, 0, 0]), ["x", "y", "z"]) + _numbers(value.get("size", [0, 0, 0]), ["x", "y", "z"])
			else:
				box = _numbers(value, ["x", "y", "z", "w", "h", "d"])
			if box.size() != 6:
				return _fail("bad_value", "%s takes {\"position\": [x, y, z], \"size\": [w, h, d]}." % info.name)
			return {"value": AABB(Vector3(box[0], box[1], box[2]), Vector3(box[3], box[4], box[5]))}
		TYPE_PLANE:
			var plane := _numbers(value, ["x", "y", "z", "d"])
			if plane.size() != 4:
				return _fail("bad_value", "%s takes [x, y, z, d], the normal and the distance." % info.name)
			return {"value": Plane(Vector3(plane[0], plane[1], plane[2]), plane[3])}
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if typeof(value) != TYPE_ARRAY:
				return _fail("bad_value", "%s takes a list." % info.name)
			match int(info.type):
				TYPE_PACKED_FLOAT32_ARRAY:
					return {"value": PackedFloat32Array(value.map(func(item): return float(item)))}
				TYPE_PACKED_FLOAT64_ARRAY:
					return {"value": PackedFloat64Array(value.map(func(item): return float(item)))}
				TYPE_PACKED_INT32_ARRAY:
					return {"value": PackedInt32Array(value.map(func(item): return int(item)))}
				TYPE_PACKED_INT64_ARRAY:
					return {"value": PackedInt64Array(value.map(func(item): return int(item)))}
				_:
					return {"value": PackedStringArray(value.map(func(item): return str(item)))}
		TYPE_PACKED_VECTOR3_ARRAY:
			var points := PackedVector3Array()
			for point in (value if typeof(value) == TYPE_ARRAY else []):
				var xyz := _numbers(point, ["x", "y", "z"])
				if xyz.size() != 3:
					return _fail("bad_value", "%s takes a list of [x, y, z] points." % info.name)
				points.append(Vector3(xyz[0], xyz[1], xyz[2]))
			return {"value": points}
		TYPE_PACKED_COLOR_ARRAY:
			var colors := PackedColorArray()
			for item in (value if typeof(value) == TYPE_ARRAY else []):
				var color := _typed(item, {"name": info.name, "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
				if color.has("error"):
					return color
				colors.append(color.value)
			return {"value": colors}
		_:
			return {"value": value}


## A rotation and scale from {"rotation_degrees": [x, y, z], "scale": [x, y, z]}, or a refusal.
func _basis(value: Dictionary):
	var degrees := _numbers(value.get("rotation_degrees", [0, 0, 0]), ["x", "y", "z"])
	var scale := _numbers(value.get("scale", [1, 1, 1]), ["x", "y", "z"])
	if degrees.size() != 3 or scale.size() != 3:
		return _fail("bad_value", "rotation_degrees and scale each take three numbers.")
	var radians := Vector3(deg_to_rad(degrees[0]), deg_to_rad(degrees[1]), deg_to_rad(degrees[2]))
	# Rotation after scale, as a Node3D builds its basis from rotation and scale.
	return Basis.from_euler(radians) * Basis.from_scale(Vector3(scale[0], scale[1], scale[2]))


## Whether a value read back is the one written: numbers, vectors and colours within float precision (a colour keeps
## its channels in 32 bits), and names whether a String or a StringName holds them.
func _same(now, wanted) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	var names := [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH]
	if typeof(now) in numbers and typeof(wanted) in numbers:
		return is_equal_approx(float(now), float(wanted))
	if typeof(now) in names and typeof(wanted) in names:
		return str(now) == str(wanted)
	if typeof(now) != typeof(wanted):
		return false
	if typeof(now) in [TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION, TYPE_RECT2, TYPE_AABB, TYPE_PLANE, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_BASIS]:
		return now.is_equal_approx(wanted)
	return now == wanted


## A value as plain JSON: vectors as arrays, colours as #rrggbbaa, resources by type and path.
func _plain(value):
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return "#" + value.to_html(true)
		TYPE_RECT2, TYPE_RECT2I:
			return {"position": [value.position.x, value.position.y], "size": [value.size.x, value.size.y]}
		TYPE_NODE_PATH, TYPE_STRING_NAME:
			return str(value)
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return {"type": value.get_class(), "path": value.resource_path}
			return value.get_class()
		TYPE_ARRAY:
			return value.map(func(item): return _plain(item))
		TYPE_DICTIONARY:
			var plain := {}
			for key in value:
				plain[str(key)] = _plain(value[key])
			return plain
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return Array(value)
		TYPE_PACKED_VECTOR2_ARRAY:
			return Array(value).map(func(point): return [point.x, point.y])
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_NIL:
			return value
		_:
			return _plain_more(value)


## The types the core's _plain hands over, as the same JSON _typed_more reads.
func _plain_more(value):
	match typeof(value):
		TYPE_TRANSFORM2D:
			return {"origin": _plain(value.origin), "rotation_degrees": snappedf(rad_to_deg(value.get_rotation()), 0.001), "scale": _plain(value.get_scale())}
		TYPE_TRANSFORM3D:
			var euler: Vector3 = value.basis.get_euler()
			return {"origin": _plain(value.origin), "rotation_degrees": [snappedf(rad_to_deg(euler.x), 0.001), snappedf(rad_to_deg(euler.y), 0.001), snappedf(rad_to_deg(euler.z), 0.001)], "scale": _plain(value.basis.get_scale())}
		TYPE_BASIS:
			var euler: Vector3 = value.get_euler()
			return {"rotation_degrees": [snappedf(rad_to_deg(euler.x), 0.001), snappedf(rad_to_deg(euler.y), 0.001), snappedf(rad_to_deg(euler.z), 0.001)], "scale": _plain(value.get_scale())}
		TYPE_QUATERNION:
			return [value.x, value.y, value.z, value.w]
		TYPE_AABB:
			return {"position": _plain(value.position), "size": _plain(value.size)}
		TYPE_PLANE:
			return [value.normal.x, value.normal.y, value.normal.z, value.d]
		TYPE_PACKED_VECTOR3_ARRAY:
			return Array(value).map(func(point): return [point.x, point.y, point.z])
		TYPE_PACKED_COLOR_ARRAY:
			return Array(value).map(func(color): return "#" + color.to_html(true))
		_:
			return str(value)
