extends CanvasLayer
## Touch controls for a phone: a thumb stick or arrows, a drag to look, and buttons with drawn icons, all multi-touch. Keys and a mouse work too.
## Use:
##   var touch = preload("res://parts/touch.gd").new()
##   add_child(touch)
##   touch.stick()                         # the left thumb moves; read touch.move, a Vector2 from -1 to 1
##   touch.arrows()                        # or left and right buttons, for a side-on game; also read touch.move
##   touch.look()                          # a drag on the free screen; read touch.take_look(), radians since the last read
##   touch.button("jump", "jump")          # a name and an icon, placed for the right thumb in the order added
##   touch.button("fire", "fire", KEY_F)   # with a key as well; the first buttons also get Space, E and Q
##   touch.held("jump")                    # true while pressed
##   touch.took("fire")                    # true once for each press
##   touch.took_tap()                      # true once for a quick tap on the free screen
##   touch.pressed.connect(func(button_name): print(button_name))
##   touch.active = false                  # hides it and lets go; screens does this for its menus
## Icons: jump fire sword shield mine place use dash bomb reload up down left right pause, or any short text.
## A Control in the group "touch_ignore" keeps its touches: use it for your own buttons on the play screen.

signal pressed(button_name: String)

const STICK_REACH := 86.0
const TAP_SECONDS := 0.24
const TAP_TRAVEL := 16.0
const MOUSE_FINGER := 1000
const AUTO_KEYS: Array[Key] = [KEY_SPACE, KEY_E, KEY_Q, KEY_F, KEY_R]
const RIGHT_THUMB: Array[Vector2] = [Vector2(112, 124), Vector2(262, 96), Vector2(150, 278), Vector2(306, 244), Vector2(420, 96), Vector2(456, 240)]

var active := true: set = set_active
var move := Vector2.ZERO
var look_speed := 0.0042
var tint := Color.WHITE

var _glass: Control
var _has_stick := false
var _has_arrows := false
var _has_look := false
var _buttons: Array[Dictionary] = []
var _fingers := {}
var _stick_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _look := Vector2.ZERO
var _tapped := false
var _taken := {}


func _ready() -> void:
	layer = 50
	add_to_group("parts_touch")
	_glass = Control.new()
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.draw.connect(_paint)
	add_child(_glass)


func stick() -> void:
	_has_stick = true


func arrows() -> void:
	_has_arrows = true


func look() -> void:
	_has_look = true


func button(button_name: String, icon := "", key: Key = KEY_NONE) -> void:
	var count := _buttons.filter(func(entry: Dictionary) -> bool: return not entry.corner).size()
	var chosen := key
	if chosen == KEY_NONE and count < AUTO_KEYS.size():
		chosen = AUTO_KEYS[count]
	var shown := icon if not icon.is_empty() else button_name
	var corner := shown == "pause"
	_buttons.append({"name": button_name, "icon": shown, "key": KEY_ESCAPE if corner else chosen, "corner": corner, "place": count, "was_down": false})


func held(button_name: String) -> bool:
	for entry in _buttons:
		if entry.name == button_name:
			return bool(entry.was_down) or _finger_on(button_name)
	return false


func took(button_name: String) -> bool:
	var was_taken: bool = _taken.get(button_name, false)
	_taken.erase(button_name)
	return was_taken


func took_tap() -> bool:
	var was_tapped := _tapped
	_tapped = false
	return was_tapped


func take_look() -> Vector2:
	var moved := _look
	_look = Vector2.ZERO
	return moved


## How long a finger has rested on the free screen without dragging, in seconds; 0 when none has.
func look_hold() -> float:
	for finger: Dictionary in _fingers.values():
		if finger.role == "look" and finger.travel < TAP_TRAVEL:
			return finger.age
	return 0.0


func set_active(value: bool) -> void:
	active = value
	if _glass != null:
		_glass.visible = value
	if not value:
		_fingers.clear()
		_stick = Vector2.ZERO
		_look = Vector2.ZERO
		_taken.clear()
		_tapped = false


func _unit() -> float:
	return minf(_glass.size.x, _glass.size.y) / 720.0


func _process(delta: float) -> void:
	for finger: Dictionary in _fingers.values():
		finger.age += delta
	var keys := Vector2(
		float(_key_down(KEY_D, KEY_RIGHT)) - float(_key_down(KEY_A, KEY_LEFT)),
		float(_key_down(KEY_S, KEY_DOWN)) - float(_key_down(KEY_W, KEY_UP)))
	move = _stick
	if _has_arrows:
		move = Vector2(float(_finger_on("arrow_right")) - float(_finger_on("arrow_left")), 0.0)
	if keys != Vector2.ZERO:
		move = keys.normalized()
	for entry in _buttons:
		var down: bool = entry.key != KEY_NONE and Input.is_physical_key_pressed(entry.key)
		if down and not entry.was_down:
			_press(entry.name)
		entry.was_down = down
	if active:
		_glass.queue_redraw()


func _key_down(a: Key, b: Key) -> bool:
	return Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	elif event is InputEventScreenDrag:
		_finger_moved(event.index, event.position, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and not Input.is_emulating_touch_from_mouse():
		if event.pressed:
			_finger_down(MOUSE_FINGER, event.position)
		else:
			_finger_up(MOUSE_FINGER)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _fingers.has(MOUSE_FINGER):
		_finger_moved(MOUSE_FINGER, event.position, event.relative)


func _finger_down(index: int, at: Vector2) -> void:
	for control: Node in get_tree().get_nodes_in_group("touch_ignore"):
		if control is Control and control.is_visible_in_tree() and control.get_global_rect().has_point(at):
			return
	var role := "look" if _has_look else ""
	var on_button := _button_at(at)
	if not on_button.is_empty():
		role = on_button
		_press(on_button)
	elif _has_arrows and at.distance_to(_arrow_place(false)) < 78.0 * _unit():
		role = "arrow_left"
	elif _has_arrows and at.distance_to(_arrow_place(true)) < 78.0 * _unit():
		role = "arrow_right"
	elif _has_stick and at.x < _glass.size.x * 0.42 and at.y > _glass.size.y * 0.3:
		role = "stick"
		_stick_origin = at
		_stick = Vector2.ZERO
	_fingers[index] = {"role": role, "age": 0.0, "travel": 0.0}


func _finger_moved(index: int, at: Vector2, relative: Vector2) -> void:
	if not _fingers.has(index):
		return
	var finger: Dictionary = _fingers[index]
	finger.travel += relative.length()
	if finger.role == "stick":
		var reach := STICK_REACH * _unit()
		var pulled := at - _stick_origin
		if pulled.length() > reach:
			# The stick follows a thumb that overshoots, so reversing is instant.
			_stick_origin = at - pulled.normalized() * reach
			pulled = at - _stick_origin
		_stick = pulled / reach
	elif finger.role == "look":
		_look += relative * look_speed / _unit()


func _finger_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var finger: Dictionary = _fingers[index]
	if finger.role == "stick":
		_stick = Vector2.ZERO
	elif finger.role in ["look", ""] and finger.travel < TAP_TRAVEL and finger.age < TAP_SECONDS:
		_tapped = true
	_fingers.erase(index)


func _finger_on(role: String) -> bool:
	for finger: Dictionary in _fingers.values():
		if finger.role == role:
			return true
	return false


func _press(button_name: String) -> void:
	_taken[button_name] = true
	pressed.emit(button_name)


func _button_at(at: Vector2) -> String:
	for entry in _buttons:
		if at.distance_to(_button_place(entry)) < _button_radius(entry) * 1.12:
			return entry.name
	return ""


func _button_place(entry: Dictionary) -> Vector2:
	var unit := _unit()
	if entry.corner:
		return Vector2(_glass.size.x - 58.0 * unit, 56.0 * unit)
	var from_corner: Vector2 = RIGHT_THUMB[mini(entry.place, RIGHT_THUMB.size() - 1)] * unit
	return _glass.size - from_corner


func _button_radius(entry: Dictionary) -> float:
	if entry.corner:
		return 34.0 * _unit()
	return (68.0 if entry.place == 0 else 58.0) * _unit()


func _arrow_place(right: bool) -> Vector2:
	var unit := _unit()
	return Vector2((250.0 if right else 92.0) * unit, _glass.size.y - 104.0 * unit)


func _paint() -> void:
	var unit := _unit()
	if _has_stick:
		var thumb := _finger_on("stick")
		var origin := _stick_origin if thumb else Vector2(150.0 * unit, _glass.size.y - 160.0 * unit)
		_glass.draw_circle(origin, STICK_REACH * unit, Color(0, 0, 0, 0.2))
		_glass.draw_arc(origin, STICK_REACH * unit, 0.0, TAU, 48, Color(tint, 0.5), 3.0 * unit, true)
		_glass.draw_circle(origin + _stick * STICK_REACH * unit * 0.8, 38.0 * unit, Color(tint, 0.55 if thumb else 0.3))
	if _has_arrows:
		_paint_button(_arrow_place(false), 68.0 * unit, _finger_on("arrow_left"), "left")
		_paint_button(_arrow_place(true), 68.0 * unit, _finger_on("arrow_right"), "right")
	for entry in _buttons:
		_paint_button(_button_place(entry), _button_radius(entry), _finger_on(entry.name) or entry.was_down, entry.icon)


func _paint_button(at: Vector2, radius: float, down: bool, icon: String) -> void:
	_glass.draw_circle(at, radius, Color(tint, 0.5) if down else Color(0.03, 0.04, 0.07, 0.42))
	_glass.draw_arc(at, radius, 0.0, TAU, 48, Color(tint, 0.62), maxf(radius * 0.05, 2.0), true)
	_paint_icon(at, radius * 0.42, icon)


func _paint_icon(at: Vector2, s: float, icon: String) -> void:
	var ink := Color(tint, 0.95)
	var line := maxf(s * 0.26, 3.0)
	match icon:
		"jump", "up":
			_stroke(at, [Vector2(-s, s * 0.5), Vector2(0, -s * 0.6), Vector2(s, s * 0.5)], ink, line)
		"down":
			_stroke(at, [Vector2(-s, -s * 0.5), Vector2(0, s * 0.6), Vector2(s, -s * 0.5)], ink, line)
		"left":
			_stroke(at, [Vector2(s * 0.5, -s), Vector2(-s * 0.6, 0), Vector2(s * 0.5, s)], ink, line)
		"right":
			_stroke(at, [Vector2(-s * 0.5, -s), Vector2(s * 0.6, 0), Vector2(-s * 0.5, s)], ink, line)
		"fire":
			_glass.draw_circle(at, s * 0.42, ink)
			for i in 8:
				var way := Vector2.RIGHT.rotated(i * TAU / 8.0)
				_glass.draw_line(at + way * s * 0.68, at + way * s * 1.08, ink, line * 0.6, true)
		"sword":
			_stroke(at, [Vector2(-s, s), Vector2(s, -s)], ink, line)
			_stroke(at, [Vector2(-s * 0.95, s * 0.2), Vector2(-s * 0.2, s * 0.95)], ink, line)
		"shield":
			_stroke(at, [Vector2(-s, -s * 0.7), Vector2(s, -s * 0.7), Vector2(s * 0.8, s * 0.3), Vector2(0, s * 1.05), Vector2(-s * 0.8, s * 0.3), Vector2(-s, -s * 0.7)], ink, line * 0.8)
		"mine":
			_stroke(at, [Vector2(-s, s), Vector2(s * 0.5, -s * 0.5)], ink, line)
			_stroke(at, [Vector2(-s * 0.3, -s * 0.95), Vector2(s * 0.6, -s * 0.65), Vector2(s * 0.95, s * 0.3)], ink, line)
		"place":
			_glass.draw_rect(Rect2(at - Vector2(s, s), Vector2(s, s) * 2.0), ink, false, line * 0.8)
			_stroke(at, [Vector2(-s * 0.5, 0), Vector2(s * 0.5, 0)], ink, line * 0.7)
			_stroke(at, [Vector2(0, -s * 0.5), Vector2(0, s * 0.5)], ink, line * 0.7)
		"use":
			_glass.draw_arc(at, s, 0.0, TAU, 32, ink, line * 0.8, true)
			_glass.draw_circle(at, s * 0.36, ink)
		"dash":
			_stroke(at, [Vector2(-s, -s * 0.8), Vector2(0, 0), Vector2(-s, s * 0.8)], ink, line)
			_stroke(at, [Vector2(0, -s * 0.8), Vector2(s, 0), Vector2(0, s * 0.8)], ink, line)
		"bomb":
			_glass.draw_circle(at + Vector2(-s * 0.1, s * 0.15), s * 0.78, ink)
			_stroke(at, [Vector2(s * 0.4, -s * 0.5), Vector2(s * 0.95, -s * 1.0)], ink, line * 0.7)
		"reload":
			_glass.draw_arc(at, s * 0.9, -PI * 0.3, PI * 1.35, 24, ink, line * 0.8, true)
			_stroke(at, [Vector2(s * 0.75, -s * 1.05), Vector2(s * 0.62, -s * 0.42), Vector2(s * 1.25, -s * 0.5)], ink, line * 0.7)
		"pause":
			_glass.draw_rect(Rect2(at + Vector2(-s, -s), Vector2(s * 0.7, s * 2.0)), ink)
			_glass.draw_rect(Rect2(at + Vector2(s * 0.3, -s), Vector2(s * 0.7, s * 2.0)), ink)
		_:
			var font := ThemeDB.fallback_font
			var font_size := int(s * 1.5)
			var width := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_glass.draw_string(font, at + Vector2(-width * 0.5, font_size * 0.36), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)


func _stroke(at: Vector2, points: Array, ink: Color, line: float) -> void:
	var placed := PackedVector2Array()
	for point: Vector2 in points:
		placed.append(at + point)
	_glass.draw_polyline(placed, ink, line, true)
