
# --- world3d_edit: model, terrain, scatter; scene_read: spatial -------------------------------------------------------

const MODEL_MAX_PARTS := 200
const TERRAIN_MAX_CELLS := 160
const SCATTER_MAX := 4000
const SCATTER_MAX_BODIES := 80
const SPATIAL_MAX_LISTED := 60
const SPATIAL_MAX_ISSUES := 20
const TERRAIN_META := "gdatp_terrain"


## A model built from a list of parts and saved as a scene. A part with a `pivot` turns about that point, so a body can be
## animated by rotating its joints. A part's `at` is measured from its parent part's centre.
func _world_model(params: Dictionary) -> Dictionary:
	var parts: Array = params.get("parts", [])
	if parts.is_empty() or parts.size() > MODEL_MAX_PARTS:
		return _fail("missing", "model needs parts: 1 to %d of {name, shape, size, at, color}, optionally parent and pivot; guide sys_models3d has an example." % MODEL_MAX_PARTS)
	var save_path := _res_path(params.get("save", ""))
	if save_path.begins_with("!") or save_path.get_extension() != "tscn":
		return _fail("bad_path", "save names a .tscn file for the model, such as res://models/guard.tscn.")
	var body_kind := str(params.get("body", "none"))
	if not BODIES.has(body_kind):
		return _fail("bad_value", "body is one of: %s." % ", ".join(PackedStringArray(BODIES.keys())))
	var root: Node3D = ClassDB.instantiate(BODIES[body_kind]) if BODIES[body_kind] != "" else Node3D.new()
	root.name = save_path.get_file().get_basename().to_pascal_case()
	var made := {}
	var centres := {}
	var materials := {}
	for part in parts:
		if not part is Dictionary:
			root.free()
			return _fail("bad_value", "Each part is an object with name, shape, size and at.")
		var failed := _model_part(root, part, made, centres, materials)
		if not failed.is_empty():
			root.free()
			return failed
	var has_joints := parts.any(func(part): return part.has("pivot"))
	if _flag(params.get("merge", false)):
		if has_joints:
			root.free()
			return _fail("bad_value", "merge joins parts into one mesh, so parts with a pivot cannot turn; leave out merge or the pivots.")
		_model_merge(root)
	var bounds := _model_bounds(root)
	if BODIES[body_kind] != "":
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = shape
		collision.position = bounds.get_center()
		root.add_child(collision)
	for child in root.find_children("*", "", true, false):
		child.owner = root
	var packed := PackedScene.new()
	var packing := packed.pack(root)
	root.free()
	if packing != OK:
		return _fail("not_saved", "The model could not be packed (%s)." % error_string(packing))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	var saved := ResourceSaver.save(packed, save_path)
	if saved != OK:
		return _fail("not_saved", "%s could not be written (%s)." % [save_path, error_string(saved)])
	EditorInterface.get_resource_filesystem().update_file(save_path)
	return {"saved": save_path, "parts": parts.size(), "joints": has_joints, "size": [snappedf(bounds.size.x, 0.01), snappedf(bounds.size.y, 0.01), snappedf(bounds.size.z, 0.01)],
		"next": "scene_edit ops [{op: add, scene: this file, name, properties}] places it. A joint is a Node3D named after its part: rotate it to animate."}


func _model_part(root: Node3D, part: Dictionary, made: Dictionary, centres: Dictionary, materials: Dictionary) -> Dictionary:
	var label := str(part.get("name", ""))
	if label.is_empty() or made.has(label):
		return _fail("bad_value", "Each part needs its own name; '%s' is empty or used twice." % label)
	var mesh = _model_mesh(part)
	if mesh is Dictionary:
		return mesh
	var material := _model_material(part, materials)
	if material == null:
		return _fail("bad_value", "color in part '%s' is not a colour." % label)
	mesh.surface_set_material(0, material)
	var parent_name := str(part.get("parent", ""))
	if not parent_name.is_empty() and not made.has(parent_name):
		return _fail("bad_value", "Part '%s' names parent '%s', which is not listed before it." % [label, parent_name])
	var parent: Node3D = made[parent_name] if not parent_name.is_empty() else root
	var from_parent: Vector3 = centres.get(parent_name, Vector3.ZERO)
	var at := _model_vector(part.get("at"), Vector3.ZERO)
	var pivot := _model_vector(part.get("pivot"), Vector3.ZERO)
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	var top: Node3D = mesh_node
	if part.has("pivot"):
		var joint := Node3D.new()
		joint.name = label
		mesh_node.name = "Mesh"
		mesh_node.position = -pivot
		joint.add_child(mesh_node)
		joint.position = at + from_parent + pivot
		top = joint
		centres[label] = -pivot
	else:
		mesh_node.name = label
		mesh_node.position = at + from_parent
		centres[label] = Vector3.ZERO
	if part.has("rotation_degrees"):
		top.rotation_degrees = _model_vector(part.rotation_degrees, Vector3.ZERO)
	if part.has("scale"):
		top.scale = _model_vector(part.scale, Vector3.ONE)
	parent.add_child(top)
	made[label] = top
	return {}


func _model_vector(value, fallback: Vector3) -> Vector3:
	var list := _numbers(value, ["x", "y", "z"]) if value != null else []
	return Vector3(list[0], list[1], list[2]) if list.size() == 3 else fallback


## The mesh for a part; a failure as a Dictionary.
func _model_mesh(part: Dictionary):
	var shape := str(part.get("shape", ""))
	var size: Array = part.get("size", [1]) if part.get("size", [1]) is Array else [part.get("size")]
	var a := float(size[0]) if size.size() > 0 else 1.0
	var b := float(size[1]) if size.size() > 1 else a
	var c := float(size[2]) if size.size() > 2 else a
	var segments := clampi(int(part.get("segments", 16)), 3, 64)
	var mesh
	match shape:
		"box":
			mesh = BoxMesh.new()
			mesh.size = Vector3(a, b, c)
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = a
			mesh.height = a * 2.0
			mesh.radial_segments = segments
			mesh.rings = maxi(segments / 2, 2)
		"capsule":
			mesh = CapsuleMesh.new()
			mesh.radius = a
			mesh.height = maxf(b, a * 2.0)
			mesh.radial_segments = segments
			mesh.rings = maxi(segments / 4, 1)
		"cylinder", "cone":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.0 if shape == "cone" else a
			mesh.bottom_radius = a
			mesh.height = b
			mesh.radial_segments = segments
		"torus":
			mesh = TorusMesh.new()
			mesh.inner_radius = a
			mesh.outer_radius = maxf(b, a + 0.01)
			mesh.rings = segments
			mesh.ring_segments = maxi(segments / 2, 3)
		"prism":
			mesh = PrismMesh.new()
			mesh.size = Vector3(a, b, c)
		"plane":
			mesh = PlaneMesh.new()
			mesh.size = Vector2(a, b)
		"lathe":
			return _model_lathe(part, segments)
		"extrude":
			return _model_extrude(part)
		_:
			return _fail("bad_value", "shape is box, sphere, capsule, cylinder, cone, torus, prism, plane, lathe or extrude; '%s' is not." % shape)
	return _flat_mesh(mesh) if _flag(part.get("flat", false)) else _plain_mesh(mesh)


## A primitive as an ArrayMesh, so that all shapes take a material the same way and can be merged.
func _plain_mesh(mesh: Mesh) -> ArrayMesh:
	var plain := ArrayMesh.new()
	plain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	return plain


## [mesh] with a separate normal for each face, so its facets show.
func _flat_mesh(mesh: Mesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := _mesh_indices(arrays)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in count:
		tool.add_vertex(vertices[indices[i] if not indices.is_empty() else i])
	tool.generate_normals()
	return tool.commit()


## A surface's indices; empty for one that lists each triangle's corners in full, as a mesh with separate faces does.
func _mesh_indices(arrays: Array) -> PackedInt32Array:
	return PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else arrays[Mesh.ARRAY_INDEX]


## A shape spun round the Y axis from a profile of [radius, height] points, bottom to top.
func _model_lathe(part: Dictionary, segments: int):
	var profile: Array = part.get("profile", [])
	if profile.size() < 2:
		return _fail("missing", "lathe needs profile: at least 2 [radius, height] points, from bottom to top.")
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if _flag(part.get("flat", false)):
		tool.set_smooth_group(-1)
	for s in segments:
		var angle_a := TAU * s / segments
		var angle_b := TAU * (s + 1) / segments
		for j in profile.size() - 1:
			var low: Array = profile[j]
			var high: Array = profile[j + 1]
			var a := Vector3(cos(angle_a) * float(low[0]), float(low[1]), sin(angle_a) * float(low[0]))
			var b := Vector3(cos(angle_b) * float(low[0]), float(low[1]), sin(angle_b) * float(low[0]))
			var c := Vector3(cos(angle_a) * float(high[0]), float(high[1]), sin(angle_a) * float(high[0]))
			var d := Vector3(cos(angle_b) * float(high[0]), float(high[1]), sin(angle_b) * float(high[0]))
			for corner in [a, c, b, b, c, d]:
				tool.add_vertex(corner)
	tool.generate_normals()
	return tool.commit()


## A flat outline of [x, y] points thickened along Z by `depth`.
func _model_extrude(part: Dictionary):
	var outline := PackedVector2Array()
	for point in part.get("outline", []):
		outline.append(Vector2(float(point[0]), float(point[1])))
	if outline.size() < 3:
		return _fail("missing", "extrude needs outline: at least 3 [x, y] points, and depth.")
	if not Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var triangles := Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		return _fail("bad_value", "The outline crosses itself, so it cannot be filled.")
	var half := float(part.get("depth", 0.2)) / 2.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for i in range(0, triangles.size(), 3):
		for k in [0, 1, 2]:
			var p := outline[triangles[i + k]]
			tool.add_vertex(Vector3(p.x, p.y, half))
		for k in [2, 1, 0]:
			var p := outline[triangles[i + k]]
			tool.add_vertex(Vector3(p.x, p.y, -half))
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		for corner in [Vector3(p.x, p.y, half), Vector3(p.x, p.y, -half), Vector3(q.x, q.y, half), Vector3(q.x, q.y, half), Vector3(p.x, p.y, -half), Vector3(q.x, q.y, -half)]:
			tool.add_vertex(corner)
	tool.generate_normals()
	return tool.commit()


## One material for each distinct look, shared between parts so the model takes few draw calls; null for a bad colour.
func _model_material(part: Dictionary, materials: Dictionary) -> StandardMaterial3D:
	var keys := ["color", "metallic", "roughness", "emission", "emission_energy", "unshaded", "alpha"]
	var key := ""
	for name_of_key in keys:
		key += str(part.get(name_of_key, "")) + "|"
	if materials.has(key):
		return materials[key]
	var color := _typed(part.get("color", "#b0b0b0"), {"name": "color", "type": TYPE_COLOR, "hint": 0, "hint_string": ""})
	if color.has("error"):
		return null
	var material := StandardMaterial3D.new()
	material.albedo_color = color.value
	material.metallic = float(part.get("metallic", 0.0))
	material.roughness = float(part.get("roughness", 0.9))
	if part.has("emission"):
		material.emission_enabled = true
		material.emission = Color.from_string(str(part.emission), Color.WHITE)
		material.emission_energy_multiplier = float(part.get("emission_energy", 1.5))
	if _flag(part.get("unshaded", false)):
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if part.has("alpha"):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = float(part.alpha)
	materials[key] = material
	return material


## Where [node] sits within [top], which need not be in the tree.
func _within(top: Node3D, node: Node3D) -> Transform3D:
	var place := node.transform
	var at: Node = node.get_parent()
	while at != null and at != top:
		if at is Node3D:
			place = at.transform * place
		at = at.get_parent()
	return place


func _model_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = _within(root, node) * node.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


## Joins every mesh in [root] into one, with its colour in the vertices.
func _model_merge(root: Node3D) -> void:
	var merged := _merged_mesh(root)
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	var node := MeshInstance3D.new()
	node.name = "Mesh"
	node.mesh = merged
	root.add_child(node)


## One mesh from all the meshes under [root], colours kept in the vertices, for many copies at the cost of one.
func _merged_mesh(root: Node3D) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var place := _within(root, node)
		var mesh: Mesh = node.mesh
		var surface_material: Material = mesh.surface_get_material(0)
		var color: Color = surface_material.albedo_color if surface_material is StandardMaterial3D else Color.WHITE
		var arrays := mesh.surface_get_arrays(0)
		var own_colors := PackedColorArray() if arrays[Mesh.ARRAY_COLOR] == null else PackedColorArray(arrays[Mesh.ARRAY_COLOR])
		tool.set_color(color)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := _mesh_indices(arrays)
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in count:
			var at: int = indices[i] if not indices.is_empty() else i
			if not own_colors.is_empty():
				tool.set_color(own_colors[at])
			if not normals.is_empty():
				tool.set_normal((place.basis * normals[at]).normalized())
			tool.add_vertex(place * vertices[at])
	var mesh := tool.commit()
	mesh.surface_set_material(0, _vertex_color_material())
	return mesh


## Colours in vertices are the ones the palette names, so they are marked sRGB; otherwise they come out far too bright.
func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	return material


func _terrain_noise(settings: Dictionary) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = int(settings.seed)
	noise.frequency = float(settings.frequency)
	noise.fractal_octaves = int(settings.octaves)
	noise.noise_type = NOISE_TYPES.get(settings.type, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	return noise


func _terrain_height(noise: FastNoiseLite, settings: Dictionary, x: float, z: float) -> float:
	var h := pow((noise.get_noise_2d(x, z) + 1.0) / 2.0, float(settings.power))
	var terraces := int(settings.terraces)
	if terraces > 1:
		h = roundf(h * terraces) / terraces
	return h * float(settings.height)


## Ground from noise as one mesh with its colour by height, and a static body to walk on, added to the open scene.
func _world_terrain(root: Node, params: Dictionary) -> Dictionary:
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var size := _numbers(params.get("size", [64, 64]), ["x", "z"])
	if size.size() != 2:
		return _fail("bad_value", "size is [x, z] in metres.")
	var cells := clampi(int(params.get("resolution", 64)), 4, TERRAIN_MAX_CELLS)
	var settings := {"seed": int(params.get("seed", 1)), "frequency": float(params.get("frequency", 0.03)), "octaves": clampi(int(params.get("octaves", 4)), 1, 8),
		"type": str(params.get("noise", "simplex")), "power": float(params.get("power", 1.4)), "terraces": int(params.get("terraces", 0)), "height": float(params.get("height", 6.0))}
	var noise := _terrain_noise(settings)
	var bands: Array = params.get("colors", [[0.0, "#7a8450"], [0.55, "#6b6b5e"], [0.85, "#d8d8d8"]])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if _flag(params.get("flat", true)):
		tool.set_smooth_group(-1)
	var step_x: float = size[0] / cells
	var step_z: float = size[1] / cells
	var highest := float(settings.height)
	for iz in cells:
		for ix in cells:
			var x0: float = -size[0] / 2.0 + ix * step_x
			var z0: float = -size[1] / 2.0 + iz * step_z
			var corners := [Vector2(x0, z0), Vector2(x0 + step_x, z0), Vector2(x0, z0 + step_z), Vector2(x0 + step_x, z0 + step_z)]
			var points: Array = corners.map(func(c): return Vector3(c.x, _terrain_height(noise, settings, c.x, c.y), c.y))
			for triangle in [[0, 1, 2], [1, 3, 2]]:
				var middle: float = (points[triangle[0]].y + points[triangle[1]].y + points[triangle[2]].y) / 3.0 / maxf(highest, 0.001)
				tool.set_color(_terrain_band(bands, middle))
				for k: int in triangle:
					tool.add_vertex(points[k])
	tool.generate_normals()
	var mesh := tool.commit()
	mesh.surface_set_material(0, _vertex_color_material())
	var body := StaticBody3D.new()
	body.name = str(params.get("name", "Terrain"))
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	body.set_meta(TERRAIN_META, settings)
	var placed := _place3d(body, params, Vector3.ZERO)
	if placed.has("error"):
		body.free()
		return placed
	var steps: Array = []
	_add_step(root, parent, body, steps)
	var answer := _commit_steps(root, steps, params)
	answer["size"] = size
	answer["highest"] = highest
	answer["next"] = "world3d_edit scatter with on: \"%s\" places things on it. Heights run from 0 to %s." % [_node_path(body), highest]
	return answer


func _terrain_band(bands: Array, height: float) -> Color:
	var chosen := "#808080"
	for band in bands:
		if height >= float(band[0]):
			chosen = str(band[1])
	return Color.from_string(chosen, Color.GRAY)


## Copies of a model spread over an area, kept apart and optionally on a terrain from world3d_edit, as one MultiMesh so that
## hundreds cost one draw. The copies' collision is one body, for at most a few of them.
func _world_scatter(root: Node, params: Dictionary) -> Dictionary:
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var source := _res_path(params.get("from", ""))
	if source.begins_with("!") or not ResourceLoader.exists(source, "PackedScene"):
		return _fail("not_found", "from names a saved model scene, such as res://models/tree.tscn; world3d_edit model makes one.")
	var count := clampi(int(params.get("count", 50)), 1, SCATTER_MAX)
	var area := _numbers(params.get("area", [64, 64]), ["x", "z"])
	if area.size() != 2:
		return _fail("bad_value", "area is [x, z] in metres.")
	var settings := {}
	var noise: FastNoiseLite = null
	var ground_y := float(params.get("y", 0.0))
	if params.has("on"):
		var ground = _node_param(root, params, "on")
		if ground is Dictionary:
			return ground
		if not ground.has_meta(TERRAIN_META):
			return _fail("bad_value", "on names a terrain made by world3d_edit terrain; '%s' is not one. Give y for flat ground." % params.on)
		settings = ground.get_meta(TERRAIN_META)
		noise = _terrain_noise(settings)
		ground_y = ground.position.y
	var model: Node3D = (load(source) as PackedScene).instantiate()
	var mesh := _merged_mesh(model)
	var footprint := _model_bounds(model)
	model.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 1))
	var scale_range := _numbers(params.get("scale", [0.8, 1.25]), ["min", "max"])
	var gap := float(params.get("min_gap", 0.0))
	var spots: Array = []
	var tries := count * 8
	while spots.size() < count and tries > 0:
		tries -= 1
		var at := Vector2(rng.randf_range(-area[0] / 2.0, area[0] / 2.0), rng.randf_range(-area[1] / 2.0, area[1] / 2.0))
		var clear := true
		if gap > 0.0:
			for other: Vector2 in spots:
				if other.distance_squared_to(at) < gap * gap:
					clear = false
					break
		if clear:
			spots.append(at)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = spots.size()
	var body: StaticBody3D = null
	var collide := _flag(params.get("collide", false))
	if collide and spots.size() > SCATTER_MAX_BODIES:
		return _fail("bad_value", "collide is for at most %d copies; scatter the rest without it." % SCATTER_MAX_BODIES)
	var node := MultiMeshInstance3D.new()
	node.name = str(params.get("name", source.get_file().get_basename().to_pascal_case() + "s"))
	node.multimesh = multi
	if collide:
		body = StaticBody3D.new()
		body.name = "Bodies"
		node.add_child(body)
	for i in spots.size():
		var at: Vector2 = spots[i]
		var y := ground_y
		if noise != null:
			y += _terrain_height(noise, settings, at.x, at.y)
		var size := rng.randf_range(scale_range[0], scale_range[1]) if scale_range.size() == 2 else 1.0
		var place := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU) if _flag(params.get("yaw", true)) else 0.0).scaled(Vector3.ONE * size), Vector3(at.x, y, at.y))
		multi.set_instance_transform(i, place)
		if body != null:
			var shape := BoxShape3D.new()
			shape.size = footprint.size * size
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = Vector3(at.x, y + footprint.get_center().y * size, at.y)
			body.add_child(collision)
	var steps: Array = []
	_add_step(root, parent, node, steps)
	var answer := _commit_steps(root, steps, params)
	answer["placed"] = spots.size()
	answer["triangles_each"] = mesh.get_faces().size() / 3
	return answer


## Where 3D things are in the open scene: each one's place and size, what the camera can see, and what floats or overlaps.
## Things that look right in a picture can be off by a little, and this reads it as numbers.
func _scene_spatial(root: Node) -> Dictionary:
	if not root is Node3D:
		return _fail("bad_value", "spatial reads 3D scenes; the open scene's root is %s." % root.get_class())
	var camera: Camera3D = null
	var found_cameras := root.find_children("*", "Camera3D", true, true)
	if not found_cameras.is_empty():
		camera = found_cameras[0]
	var entries: Array = []
	var boxes: Array = []
	var triangles := 0
	for node in [root] + root.find_children("*", "VisualInstance3D", true, true):
		if not node is GeometryInstance3D or not node.is_visible_in_tree():
			continue
		var box: AABB = node.global_transform * node.get_aabb()
		if node is MeshInstance3D and node.mesh != null:
			triangles += node.mesh.get_faces().size() / 3
		elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			triangles += node.multimesh.mesh.get_faces().size() / 3 * node.multimesh.instance_count
		boxes.append({"path": _node_path(node, root), "box": box})
		if entries.size() < SPATIAL_MAX_LISTED:
			var entry := {"path": _node_path(node, root), "center": _rounded(box.get_center()), "size": _rounded(box.size), "bottom": snappedf(box.position.y, 0.01), "top": snappedf(box.end.y, 0.01)}
			if camera != null:
				entry["from_camera"] = snappedf(camera.global_position.distance_to(box.get_center()), 0.1)
				entry["in_view"] = camera.is_position_in_frustum(box.get_center())
			entries.append(entry)
	var whole := _spatial_whole_things(root)
	var answer := {"things": entries, "total": boxes.size(), "triangles": triangles, "floating": _spatial_floating(whole), "overlapping": _spatial_overlaps(whole)}
	if camera != null:
		answer["camera"] = {"path": _node_path(camera, root), "at": _rounded(camera.global_position), "looks_toward": _rounded(-camera.global_basis.z), "fov": camera.fov}
	else:
		answer["camera"] = "This scene has no Camera3D, so nothing shows when it runs on its own."
	var lights := root.find_children("*", "Light3D", true, true)
	answer["lights"] = lights.size()
	if boxes.size() > SPATIAL_MAX_LISTED:
		answer["note"] = "The first %d of %d are listed." % [SPATIAL_MAX_LISTED, boxes.size()]
	return answer


func _rounded(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


## The scene's direct children as one box each, leaving out scattered fields and terrain, whose single boxes say nothing
## about what is touching what.
func _spatial_whole_things(root: Node) -> Array:
	var things: Array = []
	for child in root.get_children():
		if not child is Node3D or child is MultiMeshInstance3D or child.has_meta(TERRAIN_META):
			continue
		var box := AABB()
		var first := true
		for node in [child] + child.find_children("*", "GeometryInstance3D", true, false):
			if not node is GeometryInstance3D:
				continue
			var part: AABB = node.global_transform * node.get_aabb()
			box = part if first else box.merge(part)
			first = false
		if not first:
			things.append({"path": _node_path(child, root), "box": box})
	return things


## Things with nothing under them within reach, which are usually meant to rest on something.
func _spatial_floating(boxes: Array) -> Array:
	var floating: Array = []
	for item in boxes:
		var box: AABB = item.box
		var nearest_gap := INF
		for other in boxes:
			if other == item:
				continue
			var below: AABB = other.box
			var over_it: bool = below.position.x < box.end.x and below.end.x > box.position.x and below.position.z < box.end.z and below.end.z > box.position.z
			if over_it and below.position.y < box.position.y:
				nearest_gap = minf(nearest_gap, box.position.y - below.end.y)
		if nearest_gap > 0.05 and nearest_gap != INF:
			floating.append({"path": item.path, "gap_below": snappedf(nearest_gap, 0.01)})
		if floating.size() >= SPATIAL_MAX_ISSUES:
			break
	return floating


func _spatial_overlaps(boxes: Array) -> Array:
	var overlaps: Array = []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a: String = boxes[i].path
			var b: String = boxes[j].path
			if a.begins_with(b) or b.begins_with(a):
				continue
			var shared: AABB = boxes[i].box.intersection(boxes[j].box)
			if shared.has_volume() and shared.get_volume() > 0.02:
				overlaps.append({"a": a, "b": b, "volume": snappedf(shared.get_volume(), 0.01)})
			if overlaps.size() >= SPATIAL_MAX_ISSUES:
				return overlaps
	return overlaps
