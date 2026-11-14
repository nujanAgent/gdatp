extends Node3D
## A first-person player for parts/voxel_world.gd: walks, swims, climbs one-block ledges by pushing into them, breaks and places blocks, moved through the block grid directly so changed terrain never catches it out. It reads the touch part.
## It has no health: keep lives or health in your own game script, and have what hurts the player call that script.
## Use:
##   var player = preload("res://parts/voxel_player.gd").new()
##   player.world = world
##   add_child(player)                  # also add parts/touch.gd with stick(), look(), button("jump", "jump"), button("mine", "mine"), button("place", "place")
##   player.position = world.spawn_point()
##   player.selected_block = Blocks.STONE
##   player.block_broken.connect(func(cell, id): sfx.play(Blocks.SOUND[id]); juice.burst(Vector3(cell) + Vector3.ONE * 0.5, Blocks.DUST[id]))
##   player.block_placed.connect(func(cell, id): sfx.play(Blocks.SOUND[id]))
##   player.stepped.connect(func(id): sfx.play("step", -9.0))
##   player.jumped.connect(func(): sfx.play("jump", -6.0))
##   player.active = false              # while a menu is up: it then turns slowly above the land, so a title shows the game itself
##   player.look_from(place, yaw, pitch)       # or set the view yourself, which ends that slow turn
## It keeps the land around it built and shows a crosshair during play and hides any other node named Crosshair; to draw your own, set show_crosshair = false. Holding on the free screen also breaks, and a quick tap also places. head_in_water is true under water. Change walk_speed, jump_speed and reach to suit.

const Blocks := preload("res://parts/voxel_blocks.gd")

signal block_broken(cell: Vector3i, id: int)
signal block_placed(cell: Vector3i, id: int)
signal stepped(id: int)
signal jumped
signal landed(id: int, speed: float)

const HALF_WIDTH := 0.3
const BODY_HEIGHT := 1.8
const EYE_HEIGHT := 1.62
const SWIM_SPEED := 2.6
const ACCELERATION := 34.0
const AIR_CONTROL := 0.35
const GRAVITY_FORCE := 25.0
const SWIM_RISE := 3.6
const STEP_LENGTH := 2.3
const BASE_FOV := 72.0
const SPRINT_FOV := 80.0
const LOOK_LIMIT := 1.5
const HOLD_TO_BREAK := 0.24
const HEIGHT_FALLBACK := 70.0

var world: Node3D
var walk_speed := 4.4
var sprint_speed := 6.2
var jump_speed := 8.3
var reach := 6.0
var velocity := Vector3.ZERO
var show_crosshair := true
var yaw := 0.0
var pitch := 0.0
var on_floor := false
var in_water := false
var head_in_water := false
var selected_block := Blocks.GRASS
var active := true: set = set_active
var title_turn := true
var camera: Camera3D

var _touch: Node
var _head: Node3D
var _outline: MeshInstance3D
var _crack: MeshInstance3D
var _target := {"hit": false}
var _break_time := 0.0
var _break_cell := Vector3i(0, -1, 0)
var _walked := 0.0
var _bob := 0.0
var _land_dip := 0.0
var _fall_speed := 0.0
var _crosshair: CanvasLayer
var _turn_angle := 0.5
var _turn_place := Vector3.INF
var _play_place := Vector3.INF


func _ready() -> void:
	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.06
	camera.far = 260.0
	_head.add_child(camera)
	camera.make_current()
	_outline = _wire_box()
	add_child(_outline)
	_outline.top_level = true
	_crack = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.004
	_crack.mesh = box
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0, 0, 0, 0.0)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack.material_override = dark
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack.top_level = true
	_crack.visible = false
	add_child(_crack)
	_build_crosshair()


func set_active(value: bool) -> void:
	# Play starts where it was left, or on dry land, unless the game has just put the player somewhere else.
	if value and not active and _turn_place != Vector3.INF and position.is_equal_approx(_turn_place):
		position = _play_place if _play_place != Vector3.INF and _play_place != Vector3.ZERO else world.spawn_point()
		velocity = Vector3.ZERO
		pitch = 0.0
		if _head != null:
			_head.rotation.x = 0.0
	if value:
		_turn_place = Vector3.INF
		_play_place = Vector3.INF
	active = value
	if _crosshair != null:
		_crosshair.visible = value and show_crosshair
		_hide_other_crosshairs()


## Two marks on screen read as a bug, so while this one shows, any other node named as a crosshair is hidden.
func _hide_other_crosshairs() -> void:
	var scene := get_tree().current_scene
	if scene == null or not show_crosshair:
		return
	for other in scene.find_children("*rosshair*", "CanvasItem", true, false):
		other.visible = false


func _build_crosshair() -> void:
	_crosshair = CanvasLayer.new()
	_crosshair.layer = 40
	_crosshair.visible = active and show_crosshair
	add_child(_crosshair)
	var mark := Control.new()
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.draw.connect(func() -> void:
		for bar: Rect2 in [Rect2(-11, -1.5, 22, 3), Rect2(-1.5, -11, 3, 22)]:
			mark.draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.4))
		for bar: Rect2 in [Rect2(-11, -1.5, 22, 3), Rect2(-1.5, -11, 3, 22)]:
			mark.draw_rect(bar, Color(1, 1, 1, 0.9)))
	_crosshair.add_child(mark)


func _process(delta: float) -> void:
	if world == null:
		return
	world.update(position)
	if not active and title_turn:
		_turn_over_land(delta)


func _turn_over_land(delta: float) -> void:
	if _turn_place == Vector3.INF:
		_play_place = position
		_turn_place = world.spawn_point() + Vector3(0, 9, 0)
	_turn_angle += delta * 0.045
	position = _turn_place
	yaw = _turn_angle
	pitch = -0.24
	rotation.y = yaw
	_head.rotation.x = pitch


func look_from(place: Vector3, new_yaw: float, new_pitch: float) -> void:
	title_turn = false
	position = place
	yaw = new_yaw
	pitch = new_pitch
	rotation.y = yaw
	if _head != null:
		_head.rotation.x = pitch


func look_way() -> Vector3:
	return -camera.global_transform.basis.z


func _wire_box() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var o := -0.002
	var s := 1.002
	var corners := [
		Vector3(o, o, o), Vector3(s, o, o), Vector3(s, o, s), Vector3(o, o, s),
		Vector3(o, s, o), Vector3(s, s, o), Vector3(s, s, s), Vector3(o, s, s),
	]
	for pair: Array in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		mesh.surface_add_vertex(corners[pair[0]])
		mesh.surface_add_vertex(corners[pair[1]])
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	return node


func _physics_process(delta: float) -> void:
	if _touch == null:
		_touch = get_tree().get_first_node_in_group("parts_touch")
	if not active or _touch == null:
		_outline.visible = false
		_crack.visible = false
		return
	var moved: Vector2 = _touch.take_look()
	yaw -= moved.x
	pitch = clampf(pitch - moved.y, -LOOK_LIMIT, LOOK_LIMIT)
	rotation.y = yaw
	_head.rotation.x = pitch
	_move(delta)
	_feel(delta)
	_reach_for_blocks(delta)


func _move(delta: float) -> void:
	var wish: Vector2 = _touch.move
	var feet := Vector3i(floori(position.x), floori(position.y + 0.2), floori(position.z))
	in_water = world.block_at(feet.x, feet.y, feet.z) == Blocks.WATER
	head_in_water = world.block_at(feet.x, floori(position.y + EYE_HEIGHT), feet.z) == Blocks.WATER
	var top_speed := SWIM_SPEED if in_water else (sprint_speed if wish.length() > 0.92 else walk_speed)
	var target := (-transform.basis.z * -wish.y + transform.basis.x * wish.x) * top_speed
	var grip := ACCELERATION * (1.0 if on_floor or in_water else AIR_CONTROL) * delta
	velocity.x = move_toward(velocity.x, target.x, grip)
	velocity.z = move_toward(velocity.z, target.z, grip)
	var jump_down: bool = _touch.held("jump")
	if in_water:
		velocity.y = move_toward(velocity.y, SWIM_RISE if jump_down else -1.6, 14.0 * delta)
	else:
		velocity.y -= GRAVITY_FORCE * delta
		if jump_down and on_floor:
			velocity.y = jump_speed
			on_floor = false
			jumped.emit()
	_fall_speed = minf(_fall_speed, velocity.y)
	var was_on_floor := on_floor
	_slide(Vector3(velocity.x, 0, 0) * delta)
	_slide(Vector3(0, 0, velocity.z) * delta)
	_auto_step(wish)
	on_floor = false
	_slide(Vector3(0, velocity.y, 0) * delta)
	if on_floor and not was_on_floor and _fall_speed < -6.0:
		_land_dip = clampf(-_fall_speed * 0.012, 0.0, 0.16)
		landed.emit(_ground_block(), -_fall_speed)
	if on_floor:
		_fall_speed = 0.0
	if position.y < -20.0:
		position.y = HEIGHT_FALLBACK


## Pushing into a one-block ledge climbs it, since a thumb on a stick cannot also press jump.
func _auto_step(wish: Vector2) -> void:
	if not on_floor or wish.length() < 0.2:
		return
	var heading := Vector3(velocity.x, 0, velocity.z)
	if heading.length() < 0.1:
		heading = (-transform.basis.z * -wish.y + transform.basis.x * wish.x)
	var ahead := position + heading.normalized() * (HALF_WIDTH + 0.28)
	var cx := floori(ahead.x)
	var cz := floori(ahead.z)
	var foot := floori(position.y + 0.1)
	if _solid(cx, foot, cz) and not _solid(cx, foot + 1, cz) and not _solid(cx, foot + 2, cz) and not _solid(floori(position.x), foot + 2, floori(position.z)):
		velocity.y = jump_speed * 0.86
		on_floor = false


func _solid(x: int, y: int, z: int) -> bool:
	return Blocks.SOLID[world.block_at(x, y, z)] == 1


func _slide(travel: Vector3) -> void:
	position += travel
	var box_min := Vector3(position.x - HALF_WIDTH, position.y, position.z - HALF_WIDTH)
	var box_max := Vector3(position.x + HALF_WIDTH, position.y + BODY_HEIGHT, position.z + HALF_WIDTH)
	for y in range(floori(box_min.y), floori(box_max.y - 0.0001) + 1):
		for z in range(floori(box_min.z), floori(box_max.z - 0.0001) + 1):
			for x in range(floori(box_min.x), floori(box_max.x - 0.0001) + 1):
				if not _solid(x, y, z):
					continue
				if travel.x > 0.0:
					position.x = x - HALF_WIDTH - 0.0005
					velocity.x = 0.0
				elif travel.x < 0.0:
					position.x = x + 1 + HALF_WIDTH + 0.0005
					velocity.x = 0.0
				elif travel.z > 0.0:
					position.z = z - HALF_WIDTH - 0.0005
					velocity.z = 0.0
				elif travel.z < 0.0:
					position.z = z + 1 + HALF_WIDTH + 0.0005
					velocity.z = 0.0
				elif travel.y > 0.0:
					position.y = y - BODY_HEIGHT - 0.0005
					velocity.y = 0.0
				elif travel.y < 0.0:
					position.y = y + 1.0005
					velocity.y = 0.0
					on_floor = true
				return


func _ground_block() -> int:
	return world.block_at(floori(position.x), floori(position.y - 0.2), floori(position.z))


func _feel(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z).length()
	if on_floor and flat > 0.5:
		_walked += flat * delta
		_bob += flat * delta * 2.4
		if _walked > STEP_LENGTH:
			_walked = 0.0
			stepped.emit(_ground_block())
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.5)
	_head.position.y = EYE_HEIGHT - _land_dip + sin(_bob * 2.0) * 0.022 * minf(flat / walk_speed, 1.2)
	_head.position.x = cos(_bob) * 0.012 * minf(flat / walk_speed, 1.2)
	var wanted_fov := SPRINT_FOV if flat > walk_speed + 0.6 else BASE_FOV
	camera.fov = lerpf(camera.fov, wanted_fov, clampf(delta * 7.0, 0.0, 1.0))


func _reach_for_blocks(delta: float) -> void:
	_target = world.raycast(camera.global_position, look_way(), reach)
	var hit: bool = _target.hit
	_outline.visible = hit
	if hit:
		_outline.global_position = Vector3(_target.cell)
	if hit and (_touch.held("mine") or _touch.look_hold() >= HOLD_TO_BREAK):
		_keep_breaking(delta)
	else:
		_break_time = 0.0
		_crack.visible = false
	var place_now: bool = _touch.took("place")
	var tapped: bool = _touch.took_tap()
	if hit and (place_now or tapped):
		_place()


func _keep_breaking(delta: float) -> void:
	var cell: Vector3i = _target.cell
	if cell != _break_cell:
		_break_cell = cell
		_break_time = 0.0
	_break_time += delta
	var needed: float = Blocks.HARDNESS[_target.id]
	var progress := clampf(_break_time / maxf(needed, 0.01), 0.0, 1.0)
	_crack.visible = true
	_crack.global_position = Vector3(cell) + Vector3.ONE * 0.5
	(_crack.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, progress * 0.55)
	if _break_time >= needed:
		var id: int = _target.id
		world.set_block(cell.x, cell.y, cell.z, Blocks.AIR)
		_break_time = 0.0
		_crack.visible = false
		block_broken.emit(cell, id)


func _place() -> void:
	var cell: Vector3i = _target.cell
	var normal: Vector3i = _target.normal
	var at := cell + normal
	if _overlaps_body(at):
		return
	world.set_block(at.x, at.y, at.z, selected_block)
	block_placed.emit(at, selected_block)


func _overlaps_body(cell: Vector3i) -> bool:
	var body := AABB(position - Vector3(HALF_WIDTH, 0, HALF_WIDTH), Vector3(HALF_WIDTH * 2.0, BODY_HEIGHT, HALF_WIDTH * 2.0))
	return body.intersects(AABB(Vector3(cell), Vector3.ONE))
