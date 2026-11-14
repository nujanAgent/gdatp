extends Node
## What makes an action feel good: screen shake, a stop on impact, a pop, a flash, a burst of bits, a number that floats away, and fades.
## Use:
##   var juice = preload("res://parts/juice.gd").new()
##   add_child(juice)
##   juice.shake(0.5)                              # from 0 to 1; works on whichever camera is current
##   juice.stop_time(0.06)                         # a moment's freeze when something hits
##   juice.pop(node)                               # scales a Node2D, Control or Node3D up and back
##   juice.flash(sprite)                           # a Node2D or Control goes bright and back
##   juice.burst(position, Color("e8c040"), 18)    # a Vector2 bursts in 2D, a Vector3 in 3D
##   juice.floating(position, "+10", Color.WHITE)  # a line that rises and fades; 2D or 3D by the same rule
##   await juice.fade(Color.BLACK, 0.4)            # the screen goes to a colour; juice.fade(Color.TRANSPARENT, 0.4) clears it

var _shake := 0.0
var _veil: ColorRect
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var top := CanvasLayer.new()
	top.layer = 90
	add_child(top)
	_veil = ColorRect.new()
	_veil.color = Color.TRANSPARENT
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_veil)


func shake(strength := 0.5) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


func stop_time(seconds := 0.06) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0


func pop(node: Node, amount := 1.25) -> void:
	if node == null or not "scale" in node:
		return
	var rest: Variant = node.scale
	var tween := node.create_tween()
	tween.tween_property(node, "scale", rest * amount, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", rest, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash(node: CanvasItem, colour := Color(3, 3, 3)) -> void:
	if node == null:
		return
	var rest := node.modulate
	node.modulate = colour
	node.create_tween().tween_property(node, "modulate", rest, 0.18)


func burst(at: Variant, colour := Color.WHITE, count := 18) -> void:
	if at is Vector3:
		_burst_3d(at, colour, count)
	else:
		_burst_2d(at, colour, count)


func floating(at: Variant, words: String, colour := Color.WHITE) -> void:
	if at is Vector3:
		var mark := Label3D.new()
		mark.text = words
		mark.modulate = colour
		mark.outline_modulate = Color(0, 0, 0, 0.8)
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.no_depth_test = true
		mark.font_size = 48
		mark.outline_size = 12
		mark.pixel_size = 0.01
		_scene_root().add_child(mark)
		mark.global_position = at
		var rise := mark.create_tween().set_parallel()
		rise.tween_property(mark, "position:y", mark.position.y + 1.2, 0.8)
		rise.tween_property(mark, "modulate:a", 0.0, 0.8).set_delay(0.25)
		rise.chain().tween_callback(mark.queue_free)
	else:
		var line := Label.new()
		line.text = words
		line.z_index = 90
		line.add_theme_color_override("font_color", colour)
		line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		line.add_theme_constant_override("outline_size", 7)
		# Read at a glance while playing, so it stays above the look check's 2.2% of the screen's height in any game.
		line.add_theme_font_size_override("font_size", maxi(26, ceili(_scene_root().get_viewport().get_visible_rect().size.y * 0.025)))
		_scene_root().add_child(line)
		line.global_position = at
		var drift := line.create_tween().set_parallel()
		drift.tween_property(line, "position:y", line.position.y - 56.0, 0.8)
		drift.tween_property(line, "modulate:a", 0.0, 0.8).set_delay(0.25)
		drift.chain().tween_callback(line.queue_free)


func fade(colour: Color, seconds := 0.4) -> void:
	var tween := create_tween()
	tween.tween_property(_veil, "color", colour, seconds)
	await tween.finished


func _process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(_shake - delta * 2.2, 0.0)
	var amount := _shake * _shake
	var flat := get_viewport().get_camera_2d()
	if flat != null:
		flat.offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amount * 26.0
	var deep := get_viewport().get_camera_3d()
	if deep != null:
		deep.h_offset = _rng.randf_range(-1.0, 1.0) * amount * 0.34
		deep.v_offset = _rng.randf_range(-1.0, 1.0) * amount * 0.34


func _scene_root() -> Node:
	var current := get_tree().current_scene
	return current if current != null else get_tree().root


func _burst_2d(at: Vector2, colour: Color, count: int) -> void:
	var bits := CPUParticles2D.new()
	bits.one_shot = true
	bits.explosiveness = 0.95
	bits.amount = maxi(count, 1)
	bits.lifetime = 0.6
	bits.direction = Vector2.UP
	bits.spread = 180.0
	bits.initial_velocity_min = 70.0
	bits.initial_velocity_max = 220.0
	bits.gravity = Vector2(0, 420)
	bits.scale_amount_min = 3.0
	bits.scale_amount_max = 6.0
	bits.color = colour
	bits.z_index = 50
	_scene_root().add_child(bits)
	bits.global_position = at
	bits.emitting = true
	bits.finished.connect(bits.queue_free)


func _burst_3d(at: Vector3, colour: Color, count: int) -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.11
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	cube.material = look
	var bits := CPUParticles3D.new()
	bits.mesh = cube
	bits.one_shot = true
	bits.explosiveness = 0.95
	bits.amount = maxi(count, 1)
	bits.lifetime = 0.75
	bits.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bits.emission_box_extents = Vector3.ONE * 0.42
	bits.direction = Vector3.UP
	bits.spread = 80.0
	bits.initial_velocity_min = 1.2
	bits.initial_velocity_max = 3.6
	bits.gravity = Vector3(0, -15, 0)
	bits.scale_amount_min = 0.6
	bits.scale_amount_max = 1.3
	bits.color = colour
	_scene_root().add_child(bits)
	bits.global_position = at
	bits.emitting = true
	bits.finished.connect(bits.queue_free)
