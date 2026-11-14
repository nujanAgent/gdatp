extends CanvasLayer
## A row of slots along the bottom of the screen: pictures and numbers, a clear mark on the chosen one, its name shown briefly when chosen. For blocks, weapons, spells, anything held.
## Use:
##   var bar = preload("res://parts/hotbar.gd").new()
##   bar.items = [{"name": "Grass", "icon": world.icon(Blocks.GRASS)}, {"name": "Sword", "icon": sword_texture, "count": 3}]
##   add_child(bar)
##   bar.chosen.connect(func(slot): print(bar.items[slot].name))
##   bar.selected                 # the slot in use
##   bar.set_count(1, 2)          # changes the number on a slot
##   bar.visible = false          # while a menu is up; parts/screens.gd does this for its menus
## The number keys and the mouse wheel choose too. It takes its own touches, so the touch part ignores it.

signal chosen(slot: int)

const SLOT := 78.0
const GAP := 8.0

var items: Array = []
var selected := 0

var _glass: Control
var _toast := ""
var _toast_left := 0.0


func _ready() -> void:
	layer = 55
	add_to_group("parts_play_only")
	_glass = Control.new()
	_glass.draw.connect(_paint)
	_glass.gui_input.connect(_glass_input)
	_glass.add_to_group("touch_ignore")
	add_child(_glass)
	_place_glass()
	get_viewport().size_changed.connect(_place_glass)


func set_count(slot: int, count: int) -> void:
	items[slot]["count"] = count
	_glass.queue_redraw()


func choose(slot: int) -> void:
	selected = clampi(slot, 0, items.size() - 1)
	_toast = str(items[selected].get("name", ""))
	_toast_left = 1.4
	_glass.queue_redraw()
	chosen.emit(selected)


func _place_glass() -> void:
	var size := get_viewport().get_visible_rect().size
	var width := items.size() * SLOT + maxi(items.size() - 1, 0) * GAP
	_glass.position = Vector2((size.x - width) * 0.5, size.y - SLOT - 12.0)
	_glass.size = Vector2(width, SLOT)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_glass.queue_redraw()


func _glass_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		choose(int(event.position.x / (SLOT + GAP)))
	elif event is InputEventScreenTouch and event.pressed:
		choose(int(event.position.x / (SLOT + GAP)))


func _unhandled_input(event: InputEvent) -> void:
	if not visible or items.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var number: int = event.keycode - KEY_1
		if number >= 0 and number < items.size():
			choose(number)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			choose(posmod(selected - 1, items.size()))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			choose(posmod(selected + 1, items.size()))


func _paint() -> void:
	var font := ThemeDB.fallback_font
	for i in items.size():
		var rect := Rect2(Vector2(i * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
		_glass.draw_rect(rect, Color(0.04, 0.05, 0.08, 0.62))
		var item: Dictionary = items[i]
		var picture: Texture2D = item.get("icon")
		if picture != null:
			_glass.draw_texture_rect(picture, rect.grow(-12.0), false)
		else:
			var short_name := str(item.get("name", "")).left(5)
			_glass.draw_string(font, rect.position + Vector2(0, SLOT * 0.62), short_name, HORIZONTAL_ALIGNMENT_CENTER, SLOT, 20, Color.WHITE)
		_label(font, rect.position + Vector2(7, 24), str(i + 1), 20)
		if item.has("count"):
			_label(font, rect.position + Vector2(SLOT - 30, SLOT - 8), str(item.count), 22)
		if i == selected:
			_glass.draw_rect(rect.grow(1.0), Color.WHITE, false, 5.0)
		else:
			_glass.draw_rect(rect, Color(1, 1, 1, 0.22), false, 2.0)
	if _toast_left > 0.0:
		var alpha := clampf(_toast_left * 2.0, 0.0, 1.0)
		var at := Vector2(0, -18.0)
		_glass.draw_string_outline(font, at, _toast, HORIZONTAL_ALIGNMENT_CENTER, _glass.size.x, 30, 7, Color(0, 0, 0, 0.6 * alpha))
		_glass.draw_string(font, at, _toast, HORIZONTAL_ALIGNMENT_CENTER, _glass.size.x, 30, Color(1, 1, 1, alpha))


func _label(font: Font, at: Vector2, words: String, font_size: int) -> void:
	_glass.draw_string_outline(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0, 0, 0, 0.8))
	_glass.draw_string(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
