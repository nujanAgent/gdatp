extends Node3D
## A world of blocks without end: built on worker threads around the player, changeable block by block, with what changed kept apart so it can be saved. Shape it to suit the game.
## Use:
##   var world = preload("res://parts/voxel_world.gd").new()
##   world.terrain = {"hills": 1.0, "peaks": 1.0, "sea": 21, "trees": 1.0, "caves": true, "snow_line": 44, "ground": 24}
##   world.height_at = func(x, z): return 20 + int(sin(x * 0.1) * 6.0)    # or your own land; used from worker threads, so read nothing that changes
##   world.block_for = func(x, y, z, top): return Blocks.STONE            # or your own layers; return Blocks.AIR for empty
##   add_child(world)                  # starts with a random seed, and parts/voxel_player.gd keeps the land around it built
##   world.begin(seed, world_edits)    # optional, before the first frame: to pick the seed, or load edits from world.edits()
##   world.update(place)               # each frame, only with no voxel_player
##   world.readiness()                 # from 0 to 1 for the ground near the player: wait for 1 before play
##   world.spawn_point()               # dry land near the middle
##   world.block_at(x, y, z); world.set_block(x, y, z, id); world.surface_at(x, z)
##   world.raycast(from, way, 6.0)     # {hit, cell, normal, id}
##   world.icon(block_id)              # a texture of the block, for a hotbar
## The world needs light and a sky: add parts/sky.gd. Blocks and their looks come from parts/voxel_blocks.gd. Walk in it with parts/voxel_player.gd.

const Blocks := preload("res://parts/voxel_blocks.gd")
const Mesher := preload("res://parts/voxel_mesher.gd")
const Paint := preload("res://parts/paint.gd")

const SIZE := Mesher.SIZE
const HEIGHT := Mesher.HEIGHT
const LOAD_RADIUS := 5
const MAX_TASKS := 3
const MESHES_PER_FRAME := 2

var terrain := {}
var height_at := Callable()
var block_for := Callable()
var seed_value := 1337
var solid_material: StandardMaterial3D
var clear_material: StandardMaterial3D
var atlas_texture: ImageTexture

var _sheet: Dictionary
var _tiles: Array = []
var _sea := 21
var _ground := 24
var _hills := 1.0
var _peaks := 1.0
var _trees := 1.0
var _caves := true
var _snow_line := 44
var _columns := {}
var _instances := {}
var _dirty := {}
var _edits := {}
var _busy := {}
var _tasks: Array[int] = []
var _finished_columns: Array = []
var _finished_meshes: Array = []
var _lock := Mutex.new()
var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _cave_noise := FastNoiseLite.new()
var _center := Vector2i(1 << 20, 0)
var _wanted: Array[Vector2i] = []
var _begun := false


func _ready() -> void:
	_sea = terrain.get("sea", _sea)
	_ground = terrain.get("ground", _ground)
	_hills = terrain.get("hills", _hills)
	_peaks = terrain.get("peaks", _peaks)
	_trees = terrain.get("trees", _trees)
	_caves = terrain.get("caves", _caves)
	_snow_line = terrain.get("snow_line", _snow_line)
	var kinds: Array = []
	for faces: Array in Blocks.FACES:
		for kind: String in faces:
			if not kinds.has(kind):
				kinds.append(kind)
	_sheet = Paint.atlas(kinds, 16, Blocks.COLOURS)
	for faces: Array in Blocks.FACES:
		var index: Dictionary = _sheet.index
		_tiles.append([index[faces[0]], index[faces[1]], index[faces[2]]])
	atlas_texture = _sheet.texture
	solid_material = _material(BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	clear_material = _material(BaseMaterial3D.TRANSPARENCY_ALPHA)
	if not _begun:
		begin(randi() % 1000000, {})


func _material(transparency: BaseMaterial3D.Transparency) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.albedo_texture = atlas_texture
	made.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	made.vertex_color_use_as_albedo = true
	made.roughness = 1.0
	made.metallic_specular = 0.0
	made.transparency = transparency
	if transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		made.alpha_scissor_threshold = 0.5
	return made


func begin(new_seed: int, saved_edits: Dictionary) -> void:
	_begun = true
	seed_value = new_seed
	_edits = saved_edits
	for noise: FastNoiseLite in [_height_noise, _detail_noise, _ridge_noise, _cave_noise]:
		noise.seed = new_seed
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.0035
	_height_noise.fractal_octaves = 3
	_detail_noise.seed = new_seed + 1
	_detail_noise.frequency = 0.021
	_detail_noise.fractal_octaves = 2
	_ridge_noise.seed = new_seed + 2
	_ridge_noise.frequency = 0.008
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 3
	_cave_noise.seed = new_seed + 3
	_cave_noise.frequency = 0.045
	_cave_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


func edits() -> Dictionary:
	return _edits


## A texture of one side of [param block], for a hotbar or a menu.
func icon(block: int) -> AtlasTexture:
	var tile: int = _tiles[block][1]
	var tile_size: int = _sheet.size
	var columns: int = _sheet.columns
	var made := AtlasTexture.new()
	made.atlas = atlas_texture
	made.region = Rect2(tile % columns * tile_size, floori(float(tile) / columns) * tile_size, tile_size, tile_size)
	return made


## Dry land near the middle of the world, with room above it and no tree in the way. Land with nothing rising around it
## comes first, so a game begins looking out over the world and not at a wall.
func spawn_point() -> Vector3:
	var enclosed := Vector3.INF
	for ring in 64:
		for side in 8:
			var angle := TAU * side / 8.0
			var x := floori(cos(angle) * ring * 6.0)
			var z := floori(sin(angle) * ring * 6.0)
			var top := surface_at(x, z)
			if top > _sea + 1 and top < HEIGHT - 12 and not _tree_near(x, z):
				var place := Vector3(x + 0.5, top + 1.05, z + 0.5)
				if _open_around(x, z, top):
					return place
				if enclosed == Vector3.INF:
					enclosed = place
	return enclosed if enclosed != Vector3.INF else Vector3(0.5, HEIGHT - 4.0, 0.5)


func _open_around(x: int, z: int, top: int) -> bool:
	for side in 8:
		var angle := TAU * side / 8.0
		for reach in [2.0, 4.0, 6.0]:
			if surface_at(x + floori(cos(angle) * reach), z + floori(sin(angle) * reach)) > top + 1:
				return false
	return true


func _tree_near(x: int, z: int) -> bool:
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if _tree_at(x + dx, z + dz) > 0:
				return true
	return false


## Keeps the world around [param focus] built. Called once a frame.
func update(focus: Vector3) -> void:
	var center := Vector2i(int(floor(focus.x)) >> 4, int(floor(focus.z)) >> 4)
	if center != _center:
		_center = center
		_plan()
		_drop_far()
	_collect()
	_launch()


## How much of the nearest ground is ready, from 0 to 1.
func readiness() -> float:
	var built := 0
	var total := 0
	for x in range(_center.x - 2, _center.x + 3):
		for z in range(_center.y - 2, _center.y + 3):
			total += 1
			if _instances.has(Vector2i(x, z)):
				built += 1
	return float(built) / total


func _plan() -> void:
	_wanted.clear()
	for x in range(_center.x - LOAD_RADIUS - 1, _center.x + LOAD_RADIUS + 2):
		for z in range(_center.y - LOAD_RADIUS - 1, _center.y + LOAD_RADIUS + 2):
			_wanted.append(Vector2i(x, z))
	var middle := _center
	_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - middle).length_squared() < (b - middle).length_squared())


func _drop_far() -> void:
	var limit := LOAD_RADIUS + 3
	for key: Vector2i in _instances.keys():
		if maxi(absi(key.x - _center.x), absi(key.y - _center.y)) > limit:
			for node: Node in _instances[key]:
				node.queue_free()
			_instances.erase(key)
	for key: Vector2i in _columns.keys():
		if maxi(absi(key.x - _center.x), absi(key.y - _center.y)) > limit + 1:
			_columns.erase(key)
			_dirty.erase(key)


func _collect() -> void:
	_lock.lock()
	var columns := _finished_columns
	_finished_columns = []
	var meshes := _finished_meshes
	var done := meshes.slice(0, MESHES_PER_FRAME)
	_finished_meshes = meshes.slice(MESHES_PER_FRAME)
	_lock.unlock()
	for item: Array in columns:
		var key: Vector2i = item[0]
		var data: PackedByteArray = item[1]
		_apply_edits(key, data)
		_columns[key] = data
		_busy.erase(key)
		_dirty[key] = true
	for item: Array in done:
		_apply_mesh(item[0], item[1], item[2])
	var open: Array[int] = []
	for task in _tasks:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			open.append(task)
	_tasks = open


func _launch() -> void:
	# What the player just changed is built first, then the nearest missing ground.
	for key: Vector2i in _dirty.keys():
		if _tasks.size() >= MAX_TASKS:
			return
		if _instances.has(key) and _can_mesh(key) and not _busy.has(key):
			_start_mesh(key)
	for key in _wanted:
		if _tasks.size() >= MAX_TASKS:
			return
		if _busy.has(key):
			continue
		if not _columns.has(key):
			_busy[key] = true
			_tasks.append(WorkerThreadPool.add_task(_generate.bind(key)))
		elif _dirty.has(key) and _can_mesh(key):
			_start_mesh(key)


func _can_mesh(key: Vector2i) -> bool:
	if maxi(absi(key.x - _center.x), absi(key.y - _center.y)) > LOAD_RADIUS:
		return false
	for way: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _columns.has(key + way):
			return false
	return true


func _start_mesh(key: Vector2i) -> void:
	_dirty.erase(key)
	_busy[key] = true
	_tasks.append(WorkerThreadPool.add_task(_mesh.bind(key, _columns[key], _columns[key + Vector2i.LEFT], _columns[key + Vector2i.RIGHT], _columns[key + Vector2i.UP], _columns[key + Vector2i.DOWN])))


func _mesh(key: Vector2i, data: PackedByteArray, x_minus: PackedByteArray, x_plus: PackedByteArray, z_minus: PackedByteArray, z_plus: PackedByteArray) -> void:
	var arrays := Mesher.build(data, x_minus, x_plus, z_minus, z_plus, _tiles, _sheet.columns, _sheet.rows)
	_lock.lock()
	_finished_meshes.append([key, arrays[0], arrays[1]])
	_lock.unlock()


func _apply_mesh(key: Vector2i, solid: Variant, clear: Variant) -> void:
	_busy.erase(key)
	if _instances.has(key):
		for node: Node in _instances[key]:
			node.queue_free()
	var nodes: Array[Node] = []
	var origin := Vector3(key.x * SIZE, 0, key.y * SIZE)
	if solid != null:
		nodes.append(_add_surface(solid, solid_material, origin))
	if clear != null:
		var water := _add_surface(clear, clear_material, origin)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes.append(water)
	_instances[key] = nodes


func _add_surface(arrays: Array, surface: Material, origin: Vector3) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, surface)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = origin
	add_child(node)
	return node


func _land_height(wx: int, wz: int) -> int:
	if height_at.is_valid():
		return clampi(int(height_at.call(wx, wz)), 1, HEIGHT - 12)
	var land := _height_noise.get_noise_2d(wx, wz)
	var rolling := _detail_noise.get_noise_2d(wx, wz)
	var ridges := maxf(0.0, _ridge_noise.get_noise_2d(wx, wz) + 0.1) * clampf((land + 0.1) * 2.2, 0.0, 1.0)
	return clampi(int(_ground + (land * 15.0 + rolling * 4.5) * _hills + ridges * 26.0 * _peaks), 3, HEIGHT - 12)


## A tree stands here when the place's own hash says so, so its neighbours can tell without being generated.
func _tree_at(wx: int, wz: int) -> int:
	if _trees <= 0.0:
		return 0
	var mark := hash(Vector3i(wx, seed_value, wz))
	if posmod(mark, maxi(int(97.0 / _trees), 1)) != 0:
		return 0
	return 4 + posmod(mark >> 8, 3)


func _generate(key: Vector2i) -> void:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * HEIGHT)
	var ox := key.x * SIZE
	var oz := key.y * SIZE
	var own_layers := block_for.is_valid()
	for z in SIZE:
		for x in SIZE:
			var wx := ox + x
			var wz := oz + z
			var top := _land_height(wx, wz)
			var beach := top <= _sea + 1
			var snowy := top >= _snow_line
			for y in top + 1:
				var id := Blocks.STONE
				if own_layers:
					id = block_for.call(wx, y, wz, top)
				elif y == top:
					id = Blocks.SAND if beach else (Blocks.SNOW if snowy else Blocks.GRASS)
				elif y >= top - 3:
					id = Blocks.SAND if beach else Blocks.DIRT
				if _caves and y < top - 4 and y > 3 and absf(_cave_noise.get_noise_3d(wx, y, wz)) < 0.055:
					id = Blocks.AIR
				data[x + z * SIZE + y * SIZE * SIZE] = id
			for y in range(top + 1, _sea + 1):
				data[x + z * SIZE + y * SIZE * SIZE] = Blocks.WATER
	_plant_trees(data, ox, oz)
	_lock.lock()
	_finished_columns.append([key, data])
	_lock.unlock()


func _plant_trees(data: PackedByteArray, ox: int, oz: int) -> void:
	for wz in range(oz - 3, oz + SIZE + 3):
		for wx in range(ox - 3, ox + SIZE + 3):
			var trunk := _tree_at(wx, wz)
			if trunk == 0:
				continue
			var top := _land_height(wx, wz)
			if top <= _sea + 1 or top >= _snow_line - 4:
				continue
			for y in range(top + 1, top + 1 + trunk):
				_put(data, wx - ox, y, wz - oz, Blocks.WOOD, true)
			var crown := top + trunk
			for dy in range(-2, 3):
				var reach := 2 if dy < 1 else 1
				for dz in range(-reach, reach + 1):
					for dx in range(-reach, reach + 1):
						var far_corner := absi(dx) == reach and absi(dz) == reach
						if far_corner and (dy == 2 or posmod(hash(Vector3i(wx + dx, crown + dy, wz + dz)), 3) == 0):
							continue
						_put(data, wx - ox + dx, crown + dy, wz - oz + dz, Blocks.LEAVES, false)


func _put(data: PackedByteArray, x: int, y: int, z: int, id: int, replace: bool) -> void:
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE or y < 0 or y >= HEIGHT:
		return
	var i := x + z * SIZE + y * SIZE * SIZE
	if replace or data[i] == Blocks.AIR:
		data[i] = id


func _apply_edits(key: Vector2i, data: PackedByteArray) -> void:
	var changes: Dictionary = _edits.get(key, {})
	for i: int in changes:
		data[i] = changes[i]


## The block at a place. Ground that is not generated yet reads as stone, so nothing falls through it.
func block_at(x: int, y: int, z: int) -> int:
	if y >= HEIGHT:
		return Blocks.AIR
	if y < 0:
		return Blocks.STONE
	var column: Variant = _columns.get(Vector2i(x >> 4, z >> 4))
	if column == null:
		return Blocks.STONE
	return (column as PackedByteArray)[(x & 15) + (z & 15) * SIZE + y * SIZE * SIZE]


func set_block(x: int, y: int, z: int, id: int) -> void:
	if y < 0 or y >= HEIGHT:
		return
	var key := Vector2i(x >> 4, z >> 4)
	if not _columns.has(key):
		return
	var lx := x & 15
	var lz := z & 15
	var i := lx + lz * SIZE + y * SIZE * SIZE
	var column: PackedByteArray = _columns[key]
	column[i] = id
	_columns[key] = column
	if not _edits.has(key):
		_edits[key] = {}
	_edits[key][i] = id
	_dirty[key] = true
	if lx == 0:
		_dirty[key + Vector2i.LEFT] = true
	if lx == SIZE - 1:
		_dirty[key + Vector2i.RIGHT] = true
	if lz == 0:
		_dirty[key + Vector2i.UP] = true
	if lz == SIZE - 1:
		_dirty[key + Vector2i.DOWN] = true


func surface_at(x: int, z: int) -> int:
	return _land_height(x, z)


## Steps along the look ray a block at a time. Hits the first block that is not air or water.
func raycast(from: Vector3, way: Vector3, reach: float) -> Dictionary:
	var cell := Vector3i(floori(from.x), floori(from.y), floori(from.z))
	var stride := Vector3i(int(signf(way.x)), int(signf(way.y)), int(signf(way.z)))
	var delta := Vector3(_inverse(way.x), _inverse(way.y), _inverse(way.z))
	var edge := Vector3(_to_edge(from.x, stride.x, delta.x), _to_edge(from.y, stride.y, delta.y), _to_edge(from.z, stride.z, delta.z))
	var normal := Vector3i.ZERO
	var travelled := 0.0
	while travelled <= reach:
		var id := block_at(cell.x, cell.y, cell.z)
		if id != Blocks.AIR and id != Blocks.WATER:
			return {"hit": true, "cell": cell, "normal": normal, "id": id}
		if edge.x < edge.y and edge.x < edge.z:
			travelled = edge.x
			edge.x += delta.x
			cell.x += stride.x
			normal = Vector3i(-stride.x, 0, 0)
		elif edge.y < edge.z:
			travelled = edge.y
			edge.y += delta.y
			cell.y += stride.y
			normal = Vector3i(0, -stride.y, 0)
		else:
			travelled = edge.z
			edge.z += delta.z
			cell.z += stride.z
			normal = Vector3i(0, 0, -stride.z)
	return {"hit": false}


func _inverse(value: float) -> float:
	return 1e9 if is_zero_approx(value) else absf(1.0 / value)


func _to_edge(from: float, stride: int, delta: float) -> float:
	var whole := floorf(from)
	return (whole + 1.0 - from) * delta if stride > 0 else (from - whole) * delta


func _exit_tree() -> void:
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
