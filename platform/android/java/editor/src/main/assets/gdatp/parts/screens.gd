extends CanvasLayer
## The screens around a game, in its own colour and ready for a phone: title, pause, end, with a score and bars during play.
## Use:
##   var screens = preload("res://parts/screens.gd").new()
##   screens.accent = Color("d9762b")          # the game's colour; set it before add_child
##   add_child(screens)
##   screens.play.connect(start_game)          # Play on the title and Play again on the end screen
##   screens.to_title.connect(back_to_title)   # optional: leaving to the title from pause or the end screen
##   screens.show_title("Game name", "One line that sells it")     # the world behind it stays visible: keep something moving there
##   screens.show_game()                       # when play starts: shows the pause button and lets touch work
##   screens.show_end("You made it", "Score 120")
##   screens.say("Wave 3")                     # a line in the middle of the screen that fades
##   screens.text("score", "Score 12")         # a named line at the top left, or with "right" at the top right
##   screens.bar("health", 0.7, Color("d04a3a"))   # a named bar under those lines, from 0 to 1
##   screens.theme_for_ui()                    # a Theme in this look for your own panels and buttons
##   screens.play_label = "Continue"           # what the title's button says; set it before show_title
## Android's back button pauses during play. Pausing stops the tree, and sound can be switched off from the pause screen.

signal play
signal resume
signal to_title

const SETTINGS := "user://settings.cfg"

var accent := Color("3f8f46")
var play_label := "Play"

var _title: Control
var _pause: Control
var _end: Control
var _game: Control
var _title_name: Label
var _title_line: Label
var _title_play: Button
var _end_name: Label
var _end_line: Label
var _sound_button: Button
var _left: VBoxContainer
var _right: VBoxContainer
var _said: Label
var _lines := {}
var _bars := {}
var _playing := false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_sound(_sound_is_on())
	_game = _build_game()
	_title = _build_title()
	_pause = _build_pause()
	_end = _build_end()
	for screen: Control in [_game, _title, _pause, _end]:
		screen.visible = false
		add_child(screen)


func show_title(game_name: String, line := "") -> void:
	_playing = false
	_title_name.text = game_name
	_title_name.add_theme_font_size_override("font_size", _title_size(game_name))
	_title_line.text = line
	_title_play.text = play_label
	_only(_title)
	_set_touch(false)
	get_tree().paused = false


func show_game() -> void:
	_playing = true
	_only(_game)
	_set_touch(true)
	get_tree().paused = false


func show_pause() -> void:
	_playing = false
	_only(_pause)
	_set_touch(false)
	get_tree().paused = true


func show_end(heading: String, line := "") -> void:
	_playing = false
	_end_name.text = heading
	_end_line.text = line
	_only(_end)
	_set_touch(false)


func say(line: String, seconds := 2.0) -> void:
	_said.text = line
	_said.visible = true
	_said.modulate.a = 1.0
	_said.scale = Vector2.ONE * 0.8
	_said.pivot_offset = _said.size * 0.5
	var tween := create_tween()
	tween.tween_property(_said, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(seconds)
	tween.tween_property(_said, "modulate:a", 0.0, 0.4)


func text(line_name: String, value: String, side := "left") -> void:
	if not _lines.has(line_name):
		var label := _outlined(30, Color.WHITE, 8)
		(_right if side == "right" else _left).add_child(label)
		_lines[line_name] = label
	_lines[line_name].text = value


func bar(bar_name: String, value: float, colour := Color("d04a3a"), side := "left") -> void:
	if not _bars.has(bar_name):
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(300, 26)
		meter.max_value = 1.0
		meter.step = 0.001
		meter.show_percentage = false
		meter.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 0.5), 8))
		var fill := _flat(colour, 8)
		meter.add_theme_stylebox_override("fill", fill)
		(_right if side == "right" else _left).add_child(meter)
		_bars[bar_name] = meter
	_bars[bar_name].value = clampf(value, 0.0, 1.0)


func theme_for_ui() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("normal", "Button", _button_style(accent))
	theme.set_stylebox("hover", "Button", _button_style(accent.lightened(0.1)))
	theme.set_stylebox("pressed", "Button", _button_style(accent.darkened(0.15)))
	theme.set_stylebox("disabled", "Button", _button_style(accent.darkened(0.5)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "Panel", _flat(Color(0.05, 0.06, 0.09, 0.82), 14))
	theme.set_stylebox("panel", "PanelContainer", _flat(Color(0.05, 0.06, 0.09, 0.82), 14))
	theme.set_font_size("font_size", "Button", 34)
	theme.set_font_size("font_size", "Label", 30)
	theme.set_color("font_color", "Button", Color.WHITE)
	return theme


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _pause != null and _pause.visible:
		show_game()
		resume.emit()
	elif (what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED) and _playing:
		show_pause()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE and _playing:
		show_pause()


func _only(screen: Control) -> void:
	for each: Control in [_title, _pause, _end, _game]:
		each.visible = each == screen


func _set_touch(on: bool) -> void:
	get_tree().call_group("parts_touch", "set_active", on)
	get_tree().call_group("parts_play_only", "set_visible", on)


func _click() -> void:
	get_tree().call_group("parts_sfx", "play", "click")


func _title_size(game_name: String) -> int:
	var width := get_viewport().get_visible_rect().size.x * 0.84
	return clampi(int(width / maxf(game_name.length() * 0.62, 1.0)), 44, 122)


func _build_title() -> Control:
	var root := _full()
	root.add_child(_veil(Color(0.02, 0.03, 0.08, 0.1), Color(0.02, 0.03, 0.08, 0.72)))
	var column := _column(18)
	root.add_child(_centred(column))
	_title_name = _outlined(110, Color("f8f4e6"), 22)
	_title_line = _outlined(32, Color(1, 1, 1, 0.94), 8)
	_title_play = _button(play_label, func() -> void:
		_click()
		play.emit())
	column.add_child(_title_name)
	column.add_child(_title_line)
	column.add_child(_gap(22))
	column.add_child(_title_play)
	return root


func _build_pause() -> Control:
	var root := _full()
	root.add_child(_veil(Color(0.02, 0.03, 0.08, 0.62), Color(0.02, 0.03, 0.08, 0.72)))
	var column := _column(16)
	root.add_child(_centred(column))
	column.add_child(_outlined(72, Color.WHITE, 16, "Paused"))
	column.add_child(_gap(10))
	column.add_child(_button("Resume", func() -> void:
		_click()
		show_game()
		resume.emit()))
	_sound_button = _button("", _toggle_sound)
	_show_sound()
	column.add_child(_sound_button)
	column.add_child(_button("Quit to title", func() -> void:
		_click()
		get_tree().paused = false
		to_title.emit()))
	return root


func _build_end() -> Control:
	var root := _full()
	root.add_child(_veil(Color(0.02, 0.03, 0.08, 0.5), Color(0.02, 0.03, 0.08, 0.78)))
	var column := _column(16)
	root.add_child(_centred(column))
	_end_name = _outlined(84, Color("f8f4e6"), 18)
	_end_line = _outlined(36, Color(1, 1, 1, 0.94), 8)
	column.add_child(_end_name)
	column.add_child(_end_line)
	column.add_child(_gap(16))
	column.add_child(_button("Play again", func() -> void:
		_click()
		play.emit()))
	column.add_child(_button("Quit to title", func() -> void:
		_click()
		to_title.emit()))
	return root


func _build_game() -> Control:
	var root := _full()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left = VBoxContainer.new()
	_left.position = Vector2(26, 18)
	_left.add_theme_constant_override("separation", 8)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_left)
	_right = VBoxContainer.new()
	_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right.offset_left = -130
	_right.offset_right = -110
	_right.offset_top = 18
	_right.alignment = BoxContainer.ALIGNMENT_BEGIN
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_right)
	_said = _outlined(64, Color("fff4c8"), 14)
	_said.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_said.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_said.grow_vertical = Control.GROW_DIRECTION_BOTH
	_said.visible = false
	root.add_child(_said)
	var pause := Button.new()
	pause.custom_minimum_size = Vector2(72, 72)
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause.offset_left = -92
	pause.offset_right = -20
	pause.offset_top = 18
	pause.offset_bottom = 90
	pause.add_theme_stylebox_override("normal", _round(Color(0.03, 0.04, 0.07, 0.42), 36, Color(1, 1, 1, 0.62)))
	pause.add_theme_stylebox_override("hover", _round(Color(0.03, 0.04, 0.07, 0.42), 36, Color(1, 1, 1, 0.62)))
	pause.add_theme_stylebox_override("pressed", _round(Color(1, 1, 1, 0.45), 36, Color(1, 1, 1, 0.62)))
	pause.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause.add_to_group("touch_ignore")
	pause.pressed.connect(func() -> void:
		_click()
		show_pause())
	for x: float in [25.0, 40.0]:
		var stroke := ColorRect.new()
		stroke.color = Color(1, 1, 1, 0.95)
		stroke.position = Vector2(x, 22)
		stroke.size = Vector2(8, 28)
		stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pause.add_child(stroke)
	root.add_child(pause)
	return root


func _full() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root


func _centred(inside: Control) -> CenterContainer:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(inside)
	return holder


func _column(separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	return column


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	return gap


func _veil(top: Color, bottom: Color) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0, 1)
	var veil := TextureRect.new()
	veil.texture = texture
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return veil


func _outlined(font_size: int, colour: Color, outline: int, words := "") -> Label:
	var label := Label.new()
	label.text = words
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", accent.darkened(0.7))
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_y", maxi(int(font_size * 0.08), 2))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(words: String, action: Callable) -> Button:
	var made := Button.new()
	made.text = words
	made.custom_minimum_size = Vector2(420, 84)
	made.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	made.add_theme_font_size_override("font_size", 34)
	made.add_theme_color_override("font_color", Color.WHITE)
	made.add_theme_color_override("font_hover_color", Color.WHITE)
	made.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
	made.add_theme_stylebox_override("normal", _button_style(accent))
	made.add_theme_stylebox_override("hover", _button_style(accent.lightened(0.1)))
	made.add_theme_stylebox_override("pressed", _button_style(accent.darkened(0.15)))
	made.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	made.pressed.connect(action)
	return made


func _button_style(fill: Color) -> StyleBoxFlat:
	var style := _flat(fill, 12)
	style.border_color = fill.darkened(0.4)
	style.border_width_bottom = 8
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	return style


func _flat(fill: Color, corner: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(corner)
	return style


func _round(fill: Color, corner: int, edge: Color) -> StyleBoxFlat:
	var style := _flat(fill, corner)
	style.border_color = edge
	style.set_border_width_all(3)
	return style


func _sound_is_on() -> bool:
	var config := ConfigFile.new()
	return config.load(SETTINGS) != OK or bool(config.get_value("sound", "on", true))


func _apply_sound(on: bool) -> void:
	AudioServer.set_bus_mute(0, not on)


func _toggle_sound() -> void:
	var on := AudioServer.is_bus_mute(0)
	_apply_sound(on)
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("sound", "on", on)
	config.save(SETTINGS)
	_show_sound()
	_click()


func _show_sound() -> void:
	_sound_button.text = "Sound: off" if AudioServer.is_bus_mute(0) else "Sound: on"
