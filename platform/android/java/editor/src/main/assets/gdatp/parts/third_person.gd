extends CharacterBody3D
## A third-person hero on physics ground: runs where the camera faces, turns smoothly, jumps, with a camera on an arm that keeps out of walls and a simple body that swings as it runs. It reads the touch part.
## Use:
##   var hero = preload("res://parts/third_person.gd").new()
##   hero.body_colour = Color("c8553d")
##   hero.position = Vector3(0, 2, 0)
##   add_child(hero)                    # also add parts/touch.gd with stick(), look() and button("jump", "jump")
##   hero.use_model(my_node3d)          # replaces the simple body with your own, facing -Z
##   hero.jumped.connect(func(): sfx.play("jump"))
##   hero.landed.connect(func(speed): sfx.play("land"))
##   hero.stepped.connect(func(): sfx.play("step"))
##   hero.swing()                       # plays the simple body's arm swing, for an attack
##   hero.active = false                # while a menu is up
## Change hero.run_speed, jump_speed, gravity_force, arm_length to suit. Ground needs a StaticBody3D with a collision shape.

signal stepped
signal jumped
signal landed(speed: float)

const COYOTE_SECONDS := 0.12
const BUFFER_SECONDS := 0.14
const STEP_LENGTH := 2.4

var run_speed := 6.0
var jump_speed := 8.2
var gravity_force := 24.0
var acceleration := 30.0
var air_control := 0.45
var arm_length := 5.2
var body_colour := Color("c8553d")
var skin_colour := Color("e8bd9a")
var active := true
var camera: Camera3D

var _touch: Node
var _pivot: Node3D
var _arm: SpringArm3D
var _model: Node3D
var _limbs := {}
var _yaw := 0.0
var _pitch := -0.3
var _since_ground := 0.0
var _since_press := 1.0
var _stride := 0.0
var _walked := 0.0
var _fall := 0.0
var _swing_left := 0.0


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)
	_model = Node3D.new()
	add_child(_model)
	_build_body()
	_pivot = Node3D.new()
	_pivot.top_level = true
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = arm_length
	_arm.margin = 0.15
	_arm.add_excluded_object(get_rid())
	var ball := SphereShape3D.new()
	ball.radius = 0.2
	_arm.shape = ball
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 500.0
	_arm.add_child(camera)
	camera.make_current()


func use_model(node: Node3D) -> void:
	for child in _model.get_children():
		child.queue_free()
	_limbs.clear()
	_model.add_child(node)


func swing() -> void:
	_swing_left = 0.28


func _build_body() -> void:
	var cloth := _look(body_colour)
	var skin := _look(skin_colour)
	var dark := _look(body_colour.darkened(0.45))
	_part("torso", Vector3(0.56, 0.68, 0.32), Vector3(0, 1.08, 0), cloth)
	_part("head", Vector3(0.42, 0.42, 0.42), Vector3(0, 1.66, 0), skin)
	_limbs["arm_l"] = _limb(Vector3(0.18, 0.62, 0.2), Vector3(-0.39, 1.4, 0), cloth)
	_limbs["arm_r"] = _limb(Vector3(0.18, 0.62, 0.2), Vector3(0.39, 1.4, 0), cloth)
	_limbs["leg_l"] = _limb(Vector3(0.22, 0.74, 0.24), Vector3(-0.15, 0.74, 0), dark)
	_limbs["leg_r"] = _limb(Vector3(0.22, 0.74, 0.24), Vector3(0.15, 0.74, 0), dark)


func _look(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	return material


func _part(part_name: String, size: Vector3, place: Vector3, look: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = look
	node.position = place
	_model.add_child(node)
	return node


## A limb hangs from a joint at [param place], so turning the joint swings it.
func _limb(size: Vector3, place: Vector3, look: Material) -> Node3D:
	var joint := Node3D.new()
	joint.position = place
	_model.add_child(joint)
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = look
	node.position.y = -size.y * 0.5
	joint.add_child(node)
	return joint


func _physics_process(delta: float) -> void:
	if _touch == null:
		_touch = get_tree().get_first_node_in_group("parts_touch")
	var wish := Vector2.ZERO
	var jump_down := false
	if active and _touch != null:
		var moved: Vector2 = _touch.take_look()
		_yaw -= moved.x
		_pitch = clampf(_pitch - moved.y, -1.1, 0.45)
		wish = _touch.move
		jump_down = _touch.held("jump")
	var facing := Basis(Vector3.UP, _yaw)
	var target := facing * Vector3(wish.x, 0, wish.y) * run_speed
	var grip := acceleration * (1.0 if is_on_floor() else air_control) * delta
	velocity.x = move_toward(velocity.x, target.x, grip)
	velocity.z = move_toward(velocity.z, target.z, grip)
	_since_ground = 0.0 if is_on_floor() else _since_ground + delta
	_since_press = 0.0 if jump_down else _since_press + delta
	if not is_on_floor():
		velocity.y -= gravity_force * delta
		_fall = minf(_fall, velocity.y)
	if _since_press < BUFFER_SECONDS and _since_ground < COYOTE_SECONDS:
		velocity.y = jump_speed
		_since_ground = COYOTE_SECONDS
		_since_press = BUFFER_SECONDS
		jumped.emit()
	var was_on_floor := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_on_floor and _fall < -6.0:
		landed.emit(-_fall)
	if is_on_floor():
		_fall = 0.0
	_animate(delta)


func _process(delta: float) -> void:
	_pivot.global_position = _pivot.global_position.lerp(global_position + Vector3.UP * 1.45, clampf(delta * 12.0, 0.0, 1.0))
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


func _animate(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	var speed := flat.length()
	if speed > 0.3:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-flat.x, -flat.y), clampf(delta * 12.0, 0.0, 1.0))
	if is_on_floor() and speed > 0.5:
		_stride += speed * delta * 2.2
		_walked += speed * delta
		if _walked > STEP_LENGTH:
			_walked = 0.0
			stepped.emit()
	_swing_left = maxf(_swing_left - delta, 0.0)
	if _limbs.is_empty():
		return
	var reach := sin(_stride * 2.0) * minf(speed / run_speed, 1.0) * 0.8
	if not is_on_floor():
		reach = 0.5
	_limbs.leg_l.rotation.x = reach
	_limbs.leg_r.rotation.x = -reach
	_limbs.arm_l.rotation.x = -reach * 0.7
	_limbs.arm_r.rotation.x = reach * 0.7 if _swing_left <= 0.0 else -2.6 * sin(_swing_left / 0.28 * PI)
