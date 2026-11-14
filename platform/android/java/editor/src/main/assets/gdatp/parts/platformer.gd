extends CharacterBody2D
## A side-on hero with the feel of a good platformer: quick to start and stop, forgiving jumps, a higher jump when held, a wall slide if you want one, and a camera that looks ahead. It reads the touch part.
## Use:
##   var hero = preload("res://parts/platformer.gd").new()
##   hero.position = Vector2(64, 64)
##   hero.body_colour = Color("e0702c")     # the drawn body, or hero.art = your Sprite2D or AnimatedSprite2D
##   add_child(hero)                        # also add parts/touch.gd with arrows() and button("jump", "jump")
##   hero.jumped.connect(func(): sfx.play("jump"))
##   hero.landed.connect(func(): sfx.play("land"))
##   hero.camera.limit_left = 0             # the Camera2D that follows
##   hero.bounce()                          # a jump from a stomp or a spring
##   hero.hurt_from(enemy.global_position)  # knocked back and blinking, unharmed for a moment; returns false while unharmed
##   hero.active = false                    # while a menu is up
## Change hero.run_speed, jump_speed, rise_gravity, fall_gravity, wall_slide, air_jumps to suit. Solid ground needs a StaticBody2D or parts/level2d.gd.

signal jumped
signal landed

const COYOTE_SECONDS := 0.1
const BUFFER_SECONDS := 0.12
const HURT_SECONDS := 1.0

var run_speed := 280.0
var acceleration := 2200.0
var braking := 2800.0
var air_acceleration := 1500.0
var jump_speed := 560.0
var rise_gravity := 1300.0
var fall_gravity := 2100.0
var low_jump_gravity := 3000.0
var fall_limit := 900.0
var wall_slide := false
var air_jumps := 0
var body_size := Vector2(26, 40)
var body_colour := Color("e0702c")
var art: Node2D
var active := true
var facing := 1.0
var camera: Camera2D

var _touch: Node
var _since_ground := 1.0
var _since_press := 1.0
var _air_jumps_left := 0
var _hurt_left := 0.0
var _was_on_floor := true
var _look := Node2D.new()
var _drawn_blink := 0.0


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = body_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position.y = -body_size.y * 0.5
	add_child(collider)
	add_child(_look)
	if art != null:
		_look.add_child(art)
	else:
		_look.draw.connect(_paint_body)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.drag_vertical_enabled = true
	camera.drag_top_margin = 0.25
	camera.drag_bottom_margin = 0.2
	add_child(camera)
	camera.make_current()


func bounce(strength := 0.8) -> void:
	velocity.y = -jump_speed * strength
	_air_jumps_left = air_jumps


func hurt_from(source: Vector2, push := 320.0) -> bool:
	if _hurt_left > 0.0:
		return false
	_hurt_left = HURT_SECONDS
	velocity = Vector2(signf(global_position.x - source.x) * push, -jump_speed * 0.55)
	return true


func _physics_process(delta: float) -> void:
	if _touch == null:
		_touch = get_tree().get_first_node_in_group("parts_touch")
	var wish := 0.0
	var jump_held := false
	var jump_pressed := false
	if active and _touch != null:
		wish = signf(_touch.move.x) if absf(_touch.move.x) > 0.2 else 0.0
		jump_held = _touch.held("jump")
		jump_pressed = _touch.took("jump")
	_run(wish, delta)
	_since_ground = 0.0 if is_on_floor() else _since_ground + delta
	_since_press = 0.0 if jump_pressed else _since_press + delta
	if is_on_floor():
		_air_jumps_left = air_jumps
	_fall(jump_held, wish, delta)
	if _since_press < BUFFER_SECONDS:
		_try_jump(wish)
	move_and_slide()
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_feel(delta)


func _run(wish: float, delta: float) -> void:
	var change := braking if wish == 0.0 else (acceleration if is_on_floor() else air_acceleration)
	if wish != 0.0 and signf(velocity.x) != wish and velocity.x != 0.0:
		change = braking
	velocity.x = move_toward(velocity.x, wish * run_speed, change * delta)
	if wish != 0.0:
		facing = wish


func _fall(jump_held: bool, wish: float, delta: float) -> void:
	if is_on_floor():
		return
	var pull := fall_gravity
	if velocity.y < 0.0:
		pull = rise_gravity if jump_held else low_jump_gravity
	velocity.y = minf(velocity.y + pull * delta, fall_limit)
	if wall_slide and is_on_wall() and velocity.y > 0.0 and wish != 0.0:
		velocity.y = minf(velocity.y, 120.0)


func _try_jump(wish: float) -> void:
	if _since_ground < COYOTE_SECONDS:
		_leap(jump_speed)
	elif wall_slide and is_on_wall():
		_leap(jump_speed * 0.92)
		velocity.x = get_wall_normal().x * run_speed
		facing = signf(velocity.x)
	elif _air_jumps_left > 0:
		_air_jumps_left -= 1
		_leap(jump_speed * 0.86)
	elif wish != 0.0:
		pass


func _leap(speed: float) -> void:
	velocity.y = -speed
	_since_ground = COYOTE_SECONDS
	_since_press = BUFFER_SECONDS
	_look.scale = Vector2(0.75, 1.25)
	jumped.emit()


func _feel(delta: float) -> void:
	if is_on_floor() and not _was_on_floor:
		_look.scale = Vector2(1.25, 0.75)
		landed.emit()
	_was_on_floor = is_on_floor()
	_look.scale = _look.scale.lerp(Vector2.ONE, clampf(delta * 12.0, 0.0, 1.0))
	_look.scale.x = absf(_look.scale.x) * (facing if art != null else 1.0)
	camera.offset.x = lerpf(camera.offset.x, facing * 60.0, clampf(delta * 2.5, 0.0, 1.0))
	var blink := 0.35 if _hurt_left > 0.0 and fmod(_hurt_left, 0.16) < 0.08 else 1.0
	if blink != _drawn_blink:
		_drawn_blink = blink
		_look.modulate.a = blink
	if art == null:
		_look.queue_redraw()


func _paint_body() -> void:
	var w := body_size.x
	var h := body_size.y
	var stride := sin(global_position.x * 0.09) * 5.0 if is_on_floor() and absf(velocity.x) > 20.0 else 0.0
	var dark := body_colour.darkened(0.45)
	_look.draw_rect(Rect2(-w * 0.34 + stride * 0.4, -h * 0.28, w * 0.28, h * 0.28), dark)
	_look.draw_rect(Rect2(w * 0.06 - stride * 0.4, -h * 0.28, w * 0.28, h * 0.28), dark)
	_look.draw_rect(Rect2(-w * 0.5, -h * 0.82, w, h * 0.58), body_colour)
	_look.draw_rect(Rect2(-w * 0.5, -h * 0.34, w, h * 0.1), body_colour.darkened(0.2))
	_look.draw_rect(Rect2(-w * 0.42, -h, w * 0.84, h * 0.34), body_colour.lightened(0.18))
	_look.draw_rect(Rect2(facing * w * 0.12 - w * 0.08, -h * 0.9, w * 0.16, h * 0.14), Color.WHITE)
	_look.draw_rect(Rect2(facing * w * 0.2 - w * 0.04, -h * 0.87, w * 0.08, h * 0.09), Color("20242c"))
