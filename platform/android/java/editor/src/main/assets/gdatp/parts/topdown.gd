extends CharacterBody2D
## A hero seen from above: moves in any direction with weight, dashes, and is knocked back when hurt, with a camera that looks ahead. It reads the touch part.
## Use:
##   var hero = preload("res://parts/topdown.gd").new()
##   hero.position = Vector2(200, 200)
##   hero.body_colour = Color("4f9ad8")     # the drawn body, or hero.art = your Sprite2D or AnimatedSprite2D
##   add_child(hero)                        # also add parts/touch.gd with stick() and button("dash", "dash")
##   hero.facing                            # a Vector2 of length 1: aim with it
##   hero.dashed.connect(func(): sfx.play("dash"))
##   hero.hurt_from(enemy.global_position)  # knocked back and blinking, unharmed for a moment; returns false while unharmed
##   hero.active = false                    # while a menu is up
## Change hero.run_speed, dash_speed, dash_seconds, dash_wait to suit. Walls need a StaticBody2D or parts/level2d.gd.

signal dashed

const HURT_SECONDS := 0.9

var run_speed := 260.0
var acceleration := 2000.0
var braking := 2400.0
var dash_speed := 720.0
var dash_seconds := 0.14
var dash_wait := 0.6
var body_radius := 18.0
var body_colour := Color("4f9ad8")
var art: Node2D
var active := true
var facing := Vector2.RIGHT
var camera: Camera2D

var _touch: Node
var _dash_left := 0.0
var _dash_ready := 0.0
var _hurt_left := 0.0
var _look := Node2D.new()


func _ready() -> void:
	var shape := CircleShape2D.new()
	shape.radius = body_radius
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	add_child(_look)
	if art != null:
		_look.add_child(art)
	else:
		_look.draw.connect(_paint_body)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func hurt_from(source: Vector2, push := 420.0) -> bool:
	if _hurt_left > 0.0:
		return false
	_hurt_left = HURT_SECONDS
	velocity = (global_position - source).normalized() * push
	return true


func _physics_process(delta: float) -> void:
	if _touch == null:
		_touch = get_tree().get_first_node_in_group("parts_touch")
	var wish := Vector2.ZERO
	if active and _touch != null:
		wish = _touch.move
		if _touch.took("dash") and _dash_ready <= 0.0:
			_dash_left = dash_seconds
			_dash_ready = dash_wait
			dashed.emit()
	if wish.length() > 0.15:
		facing = wish.normalized()
	if _dash_left > 0.0:
		_dash_left -= delta
		velocity = facing * dash_speed
	else:
		var change := braking if wish == Vector2.ZERO else acceleration
		velocity = velocity.move_toward(wish.limit_length(1.0) * run_speed, change * delta)
	move_and_slide()
	_dash_ready = maxf(_dash_ready - delta, 0.0)
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_look.modulate.a = 0.35 if _hurt_left > 0.0 and fmod(_hurt_left, 0.16) < 0.08 else 1.0
	camera.offset = camera.offset.lerp(facing * 50.0, clampf(delta * 2.0, 0.0, 1.0))
	if art != null:
		art.rotation = facing.angle()
	else:
		_look.queue_redraw()


func _paint_body() -> void:
	_look.draw_circle(Vector2(0, body_radius * 0.3), body_radius * 1.02, Color(0, 0, 0, 0.26))
	_look.draw_circle(Vector2.ZERO, body_radius, body_colour.darkened(0.3))
	_look.draw_circle(Vector2.ZERO, body_radius * 0.82, body_colour)
	_look.draw_circle(-facing * body_radius * 0.15, body_radius * 0.46, body_colour.lightened(0.2))
	_look.draw_circle(facing * body_radius * 0.56, body_radius * 0.26, Color.WHITE)
	_look.draw_circle(facing * body_radius * 0.66, body_radius * 0.14, Color("20242c"))
