extends CharacterBody3D
## A first-person body that walks, sprints and jumps on physics ground, with a camera that bobs and leans into speed. It reads the touch part.
## Use:
##   var hero = preload("res://parts/first_person.gd").new()
##   hero.position = Vector3(0, 2, 0)
##   add_child(hero)                    # also add parts/touch.gd with stick(), look() and button("jump", "jump")
##   hero.camera                        # the Camera3D; hero.eye_way() is where it looks
##   hero.stepped.connect(func(): sfx.play("step"))
##   hero.jumped.connect(func(): sfx.play("jump"))
##   hero.landed.connect(func(speed): sfx.play("land"))
##   hero.active = false                # while a menu is up
## Change hero.walk_speed, sprint_speed, jump_speed and gravity to suit the game. Ground needs a StaticBody3D with a collision shape.

signal stepped
signal jumped
signal landed(speed: float)

const EYE_HEIGHT := 1.62
const BODY_HEIGHT := 1.8
const LOOK_LIMIT := 1.5
const STEP_LENGTH := 2.3
const COYOTE_SECONDS := 0.1
const BUFFER_SECONDS := 0.12

var walk_speed := 4.6
var sprint_speed := 6.6
var jump_speed := 7.4
var gravity_force := 22.0
var acceleration := 34.0
var air_control := 0.35
var active := true
var yaw := 0.0
var pitch := 0.0
var camera: Camera3D

var _head: Node3D
var _touch: Node
var _walked := 0.0
var _bob := 0.0
var _dip := 0.0
var _since_ground := 0.0
var _since_press := 1.0
var _fall := 0.0


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = BODY_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = BODY_HEIGHT * 0.5
	add_child(collider)
	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.06
	camera.far = 400.0
	_head.add_child(camera)
	camera.make_current()


func eye_way() -> Vector3:
	return -camera.global_transform.basis.z


func _physics_process(delta: float) -> void:
	if _touch == null:
		_touch = get_tree().get_first_node_in_group("parts_touch")
	var wish := Vector2.ZERO
	var jump_down := false
	if active and _touch != null:
		var moved: Vector2 = _touch.take_look()
		yaw -= moved.x
		pitch = clampf(pitch - moved.y, -LOOK_LIMIT, LOOK_LIMIT)
		wish = _touch.move
		jump_down = _touch.held("jump")
	rotation.y = yaw
	_head.rotation.x = pitch
	var sprinting := wish.length() > 0.92
	var top := sprint_speed if sprinting else walk_speed
	var target := (-transform.basis.z * -wish.y + transform.basis.x * wish.x) * top
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
	if is_on_floor() and not was_on_floor and _fall < -5.0:
		_dip = clampf(-_fall * 0.012, 0.0, 0.16)
		landed.emit(-_fall)
	if is_on_floor():
		_fall = 0.0
	_feel(delta)


func _feel(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat > 0.5:
		_walked += flat * delta
		_bob += flat * delta * 2.4
		if _walked > STEP_LENGTH:
			_walked = 0.0
			stepped.emit()
	_dip = move_toward(_dip, 0.0, delta * 0.5)
	var motion := minf(flat / walk_speed, 1.2)
	_head.position.y = EYE_HEIGHT - _dip + sin(_bob * 2.0) * 0.022 * motion
	_head.position.x = cos(_bob) * 0.012 * motion
	var wanted := 80.0 if flat > walk_speed + 0.6 else 72.0
	camera.fov = lerpf(camera.fov, wanted, clampf(delta * 7.0, 0.0, 1.0))
