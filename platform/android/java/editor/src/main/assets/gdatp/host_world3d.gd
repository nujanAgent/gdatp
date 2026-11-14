
# --- world3d_edit ----------------------------------------------------------------------------------------------------

const WORLD3D_OPS := ["environment", "light", "primitive", "csg", "model", "terrain", "scatter"]
const PRIMITIVES := ["box", "sphere", "capsule", "cylinder", "plane", "prism", "torus"]
const BODIES := {"static": "StaticBody3D", "rigid": "RigidBody3D", "area": "Area3D", "character": "CharacterBody3D", "none": ""}
const CSG_SHAPES := {"box": "CSGBox3D", "sphere": "CSGSphere3D", "cylinder": "CSGCylinder3D", "torus": "CSGTorus3D"}
const CSG_OPERATIONS := {"union": CSGShape3D.OPERATION_UNION, "intersection": CSGShape3D.OPERATION_INTERSECTION, "subtraction": CSGShape3D.OPERATION_SUBTRACTION}


## 3D worlds: the sky and environment, lights, primitive shapes with a body and a matching collision shape, CSG shapes,
## ground from noise and copies scattered over it. Each change to the open scene is one undo step. A model is built from
## parts and saved as its own scene.
func _world3d_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, WORLD3D_OPS)
	if op.begins_with("!"):
		return _bad_op(op, WORLD3D_OPS)
	var params: Dictionary = args.params
	if op == "model":
		return _world_model(params)
	var root = _scene_root(params)
	if root is Dictionary:
		return root
	match op:
		"terrain":
			return _world_terrain(root, params)
		"scatter":
			return _world_scatter(root, params)
		"environment":
			return _world_environment(root, params)
		"light":
			return _world_light(root, params)
		"primitive":
			return _world_primitive(root, params)
		_:
			return _world_csg(root, params)


## The scene's WorldEnvironment, made when it has none: a procedural sky or a plain colour, ambient light, fog, glow
## and tone mapping. Effects the Compatibility renderer does not draw are named in the answer.
func _world_environment(root: Node, params: Dictionary) -> Dictionary:
	var environment := Environment.new()
	var sky := str(params.get("sky", "procedural"))
	if sky == "procedural":
		var material := ProceduralSkyMaterial.new()
		for pair in [["sky_top_color", "sky_top_color"], ["sky_horizon_color", "sky_horizon_color"], ["ground_color", "ground_bottom_color"], ["horizon_color", "ground_horizon_color"]]:
			if params.has(pair[0]):
				var color := _typed(params[pair[0]], {"name": pair[0], "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
				if color.has("error"):
					return color
				material.set(pair[1], color.value)
		var made_sky := Sky.new()
		made_sky.sky_material = material
		environment.sky = made_sky
		environment.background_mode = Environment.BG_SKY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	elif sky == "color":
		var color := _typed(params.get("background_color", "#6fa8dc"), {"name": "background_color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
		if color.has("error"):
			return color
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = color.value
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = color.value.lerp(Color.WHITE, 0.5)
	else:
		return _fail("bad_value", "sky is procedural or color.")
	environment.ambient_light_energy = float(params.get("ambient_energy", 1.0))
	var tonemaps := {"linear": Environment.TONE_MAPPER_LINEAR, "reinhard": Environment.TONE_MAPPER_REINHARDT, "filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES}
	environment.tonemap_mode = tonemaps.get(str(params.get("tonemap", "filmic")), Environment.TONE_MAPPER_FILMIC)
	environment.fog_enabled = _flag(params.get("fog", false))
	if environment.fog_enabled and params.has("fog_density"):
		environment.fog_density = float(params.fog_density)
	environment.glow_enabled = _flag(params.get("glow", false))
	var steps: Array = []
	var holder := root.find_children("*", "WorldEnvironment", true, false)
	if holder.is_empty():
		var node := WorldEnvironment.new()
		node.name = "WorldEnvironment"
		node.environment = environment
		_add_step(root, root, node, steps)
	else:
		_set_step(holder[0], "environment", environment, steps)
	var answer := _commit_steps(root, steps, params)
	var renderer := str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", ""))
	if renderer == "gl_compatibility":
		answer["renderer"] = "Compatibility: it draws the sky, ambient light, fog, glow and tone mapping, but not SSAO, SSR, SDFGI or volumetric fog."
	return answer


func _world_light(root: Node, params: Dictionary) -> Dictionary:
	var kinds := {"sun": "DirectionalLight3D", "omni": "OmniLight3D", "spot": "SpotLight3D"}
	var kind := str(params.get("kind", "sun"))
	if not kinds.has(kind):
		return _fail("bad_value", "kind is sun, omni or spot.")
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var light: Light3D = ClassDB.instantiate(kinds[kind])
	light.name = str(params.get("name", kinds[kind]))
	var placed := _place3d(light, params, Vector3(-50, 30, 0) if kind == "sun" else Vector3.ZERO)
	if placed.has("error"):
		light.free()
		return placed
	if params.has("color"):
		var color := _typed(params.color, {"name": "color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
		if color.has("error"):
			light.free()
			return color
		light.light_color = color.value
	light.light_energy = float(params.get("energy", 1.0))
	light.shadow_enabled = _flag(params.get("shadows", kind == "sun"))
	if params.has("range"):
		light.set("omni_range" if kind == "omni" else "spot_range", float(params.range))
	var steps: Array = []
	_add_step(root, parent, light, steps)
	return _commit_steps(root, steps, params)


## A primitive mesh in a colour, inside a body with a collision shape of the same size: box, sphere, capsule, cylinder,
## plane, prism or torus. `body` none leaves just the mesh.
func _world_primitive(root: Node, params: Dictionary) -> Dictionary:
	var shape := str(params.get("shape", ""))
	if not PRIMITIVES.has(shape):
		return _fail("bad_value", "shape is one of: %s." % ", ".join(PackedStringArray(PRIMITIVES)), {"did_you_mean": _nearest(shape, PRIMITIVES)})
	var body_kind := str(params.get("body", "static"))
	if not BODIES.has(body_kind):
		return _fail("bad_value", "body is one of: %s." % ", ".join(PackedStringArray(BODIES.keys())))
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var size := _numbers(params.get("size", [1, 1, 1]), ["x", "y", "z"])
	if size.size() != 3:
		return _fail("bad_value", "size is [x, y, z].")
	var radius := float(params.get("radius", 0.5))
	var height := float(params.get("height", 1.0))
	# Untyped: each shape has its own mesh and collision classes, with their own properties.
	var mesh
	var collision
	match shape:
		"box":
			mesh = BoxMesh.new()
			mesh.size = Vector3(size[0], size[1], size[2])
			collision = BoxShape3D.new()
			collision.size = mesh.size
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = radius
			mesh.height = radius * 2.0
			collision = SphereShape3D.new()
			collision.radius = radius
		"capsule":
			mesh = CapsuleMesh.new()
			mesh.radius = radius
			mesh.height = max(height, radius * 2.0)
			collision = CapsuleShape3D.new()
			collision.radius = radius
			collision.height = mesh.height
		"cylinder":
			mesh = CylinderMesh.new()
			mesh.top_radius = radius
			mesh.bottom_radius = radius
			mesh.height = height
			collision = CylinderShape3D.new()
			collision.radius = radius
			collision.height = height
		"plane":
			mesh = PlaneMesh.new()
			mesh.size = Vector2(size[0], size[2])
			collision = BoxShape3D.new()
			collision.size = Vector3(size[0], 0.02, size[2])
		_:
			mesh = PrismMesh.new() if shape == "prism" else TorusMesh.new()
			if shape == "prism":
				mesh.size = Vector3(size[0], size[1], size[2])
			collision = mesh.create_convex_shape()
	var material := StandardMaterial3D.new()
	var color := _typed(params.get("color", "#d0d0d0"), {"name": "color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
	if color.has("error"):
		return color
	material.albedo_color = color.value
	mesh.material = material
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh
	var label := str(params.get("name", shape.capitalize()))
	var top: Node3D = mesh_node
	if BODIES[body_kind] != "":
		var body: Node3D = ClassDB.instantiate(BODIES[body_kind])
		body.name = label
		body.add_child(mesh_node)
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		shape_node.shape = collision
		body.add_child(shape_node)
		top = body
	else:
		mesh_node.name = label
	var placed := _place3d(top, params, Vector3.ZERO)
	if placed.has("error"):
		top.free()
		return placed
	var steps: Array = []
	_add_step(root, parent, top, steps)
	var answer := _commit_steps(root, steps, params)
	answer["next"] = "run play shows it; scene_read node %s lists what it holds." % _node_path(top)
	return answer


func _world_csg(root: Node, params: Dictionary) -> Dictionary:
	var shape := str(params.get("shape", "box"))
	if not CSG_SHAPES.has(shape):
		return _fail("bad_value", "shape is one of: %s." % ", ".join(PackedStringArray(CSG_SHAPES.keys())))
	var operation := str(params.get("operation", "union"))
	if not CSG_OPERATIONS.has(operation):
		return _fail("bad_value", "operation is union, intersection or subtraction.")
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var node: CSGShape3D = ClassDB.instantiate(CSG_SHAPES[shape])
	node.name = str(params.get("name", "CSG" + shape.capitalize()))
	node.operation = CSG_OPERATIONS[operation]
	node.use_collision = _flag(params.get("use_collision", parent is Node3D and not (parent is CSGShape3D)))
	var size := _numbers(params.get("size", [1, 1, 1]), ["x", "y", "z"])
	match shape:
		"box":
			if size.size() == 3:
				node.set("size", Vector3(size[0], size[1], size[2]))
		"sphere":
			node.set("radius", float(params.get("radius", 0.5)))
		"cylinder":
			node.set("radius", float(params.get("radius", 0.5)))
			node.set("height", float(params.get("height", 1.0)))
		"torus":
			node.set("inner_radius", float(params.get("inner_radius", 0.5)))
			node.set("outer_radius", float(params.get("outer_radius", 1.0)))
	if params.has("color"):
		var color := _typed(params.color, {"name": "color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
		if color.has("error"):
			node.free()
			return color
		var material := StandardMaterial3D.new()
		material.albedo_color = color.value
		node.set("material", material)
	var placed := _place3d(node, params, Vector3.ZERO)
	if placed.has("error"):
		node.free()
		return placed
	var steps: Array = []
	_add_step(root, parent, node, steps)
	var answer := _commit_steps(root, steps, params)
	answer["note"] = "CSG costs more each frame than a plain mesh; on a phone, keep CSG for blocking out levels."
	return answer


## Puts [node] at `position` and turns it by `rotation_degrees` ([default_rotation] when not given).
func _place3d(node: Node3D, params: Dictionary, default_rotation: Vector3) -> Dictionary:
	var at := _numbers(params.get("position", [0, 0, 0]), ["x", "y", "z"])
	var turn := _numbers(params.get("rotation_degrees", [default_rotation.x, default_rotation.y, default_rotation.z]), ["x", "y", "z"])
	if at.size() != 3 or turn.size() != 3:
		return _fail("bad_value", "position and rotation_degrees are [x, y, z].")
	node.position = Vector3(at[0], at[1], at[2])
	node.rotation_degrees = Vector3(turn[0], turn[1], turn[2])
	return {}
