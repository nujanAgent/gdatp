extends CanvasLayer
## A painted background for a side-on 2D game: a graded sky, a sun or moon, drifting clouds and layers of land that move with the camera at their own speeds.
## Use:
##   var backdrop = preload("res://parts/backdrop2d.gd").new()
##   backdrop.mood = "dusk"            # day, dusk, night, cave, sea, candy
##   backdrop.land = "hills"           # hills, peaks, city, forest, or none
##   add_child(backdrop)
## Give your own colours by adding to moods before add_child: backdrop.moods["ember"] = [top, bottom, sun, far land, near land].

const LAYERS := 3

var moods := {
	"day": ["4f93e0", "cfe8f6", "fff4c4", "9dc0d8", "5c8a5a"],
	"dusk": ["3a3a78", "f29a68", "ffd08a", "7a5478", "3c2a50"],
	"night": ["0a1030", "27305e", "e4e8f6", "1c2448", "10162e"],
	"cave": ["120f18", "2a2230", "000000", "1f1a26", "14111a"],
	"sea": ["2f7fb8", "a8e0e0", "fff4c4", "6fb4c4", "2f7f8c"],
	"candy": ["f28fb8", "ffe4b0", "fff4f0", "d88ac8", "8a6ac8"],
}
var mood := "day"
var land := "hills"
var seed_value := 11

var _sky: TextureRect
var _bands: Array[Control] = []
var _clouds: Control
var _chosen: Array
var _drift := 0.0


func _ready() -> void:
	layer = -100
	follow_viewport_enabled = false
	_chosen = moods.get(mood, moods["day"])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(_chosen[0]))
	gradient.set_color(1, Color(_chosen[1]))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_to = Vector2(0, 1)
	_sky = TextureRect.new()
	_sky.texture = fill
	_sky.stretch_mode = TextureRect.STRETCH_SCALE
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)
	_clouds = _surface()
	_clouds.draw.connect(_paint_clouds)
	add_child(_clouds)
	for depth in LAYERS:
		var band := _surface()
		band.draw.connect(_paint_land.bind(depth, band))
		add_child(band)
		_bands.append(band)


func _surface() -> Control:
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return surface


func _process(delta: float) -> void:
	_drift += delta
	_clouds.queue_redraw()
	for band in _bands:
		band.queue_redraw()


func _camera_x() -> float:
	var camera := get_viewport().get_camera_2d()
	return camera.get_screen_center_position().x if camera != null else 0.0


func _paint_clouds() -> void:
	var size := _clouds.size
	var sun_colour := Color(_chosen[2])
	if mood != "cave":
		var at := Vector2(size.x * 0.76, size.y * 0.2)
		_clouds.draw_circle(at, size.y * 0.13, Color(sun_colour, 0.18))
		_clouds.draw_circle(at, size.y * 0.09, Color(sun_colour, 0.35))
		_clouds.draw_circle(at, size.y * 0.062, sun_colour)
	if mood == "night":
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for _i in 90:
			_clouds.draw_rect(Rect2(rng.randf() * size.x, rng.randf() * size.y * 0.7, 2, 2), Color(1, 1, 1, rng.randf_range(0.3, 0.9)))
	if mood == "cave" or mood == "night":
		return
	var puff := Color(1, 1, 1, 0.8)
	for i in 6:
		var wrap_width := size.x + 400.0
		var x := fposmod(i * 317.0 + _drift * (9.0 + i * 2.0) - _camera_x() * 0.04, wrap_width) - 200.0
		var y := size.y * (0.1 + 0.07 * (i % 4))
		var unit := 26.0 + 8.0 * (i % 3)
		_clouds.draw_circle(Vector2(x, y), unit, puff)
		_clouds.draw_circle(Vector2(x + unit * 1.1, y + 6.0), unit * 0.82, puff)
		_clouds.draw_circle(Vector2(x - unit * 1.1, y + 8.0), unit * 0.72, puff)
		_clouds.draw_rect(Rect2(x - unit * 1.8, y + 4.0, unit * 3.6, unit * 0.68), puff)


func _paint_land(depth: int, band: Control) -> void:
	if land == "none":
		return
	var size := band.size
	var near := float(depth) / (LAYERS - 1)
	var colour := Color(_chosen[3]).lerp(Color(_chosen[4]), near)
	var speed := lerpf(0.08, 0.36, near)
	var base := size.y * lerpf(0.56, 0.78, near)
	var scroll := _camera_x() * speed + seed_value * 97.0 * (depth + 1)
	match land:
		"city":
			_paint_city(band, size, colour, base, scroll, depth)
		"forest":
			_paint_hills(band, size, colour, base, scroll, depth, 22.0)
			_paint_trees(band, size, colour, base, scroll, depth)
		"peaks":
			_paint_hills(band, size, colour, base, scroll, depth, 110.0 - depth * 30.0)
		_:
			_paint_hills(band, size, colour, base, scroll, depth, 56.0 - depth * 10.0)


func _height(x: float, depth: int, reach: float) -> float:
	var wide := x * (0.004 + depth * 0.0012)
	var shape := sin(wide) * 0.55 + sin(wide * 2.3 + 1.1 + depth) * 0.3 + sin(wide * 5.1 + 2.2) * 0.15
	if land == "peaks":
		shape = 1.0 - absf(sin(wide * 0.9)) * 1.6 + sin(wide * 3.7) * 0.2
	return shape * reach


func _paint_hills(band: Control, size: Vector2, colour: Color, base: float, scroll: float, depth: int, reach: float) -> void:
	var points := PackedVector2Array()
	points.append(Vector2(0, size.y))
	var x := 0.0
	while x <= size.x + 16.0:
		points.append(Vector2(x, base - _height(x + scroll, depth, reach)))
		x += 16.0
	points.append(Vector2(size.x + 16.0, size.y))
	band.draw_colored_polygon(points, colour)


func _paint_trees(band: Control, size: Vector2, colour: Color, base: float, scroll: float, depth: int) -> void:
	var gap := 70.0 - depth * 12.0
	var first := floorf(scroll / gap) * gap
	var x := first
	while x < scroll + size.x + gap:
		var turn := posmod(hash(int(x)) , 100) / 100.0
		var tall := (54.0 + turn * 46.0) * (0.7 + depth * 0.25)
		var foot := Vector2(x - scroll, base - _height(x, depth, 22.0) + 6.0)
		band.draw_colored_polygon(PackedVector2Array([foot + Vector2(-tall * 0.28, 0), foot + Vector2(0, -tall), foot + Vector2(tall * 0.28, 0)]), colour)
		x += gap


func _paint_city(band: Control, size: Vector2, colour: Color, base: float, scroll: float, depth: int) -> void:
	var gap := 62.0 + depth * 18.0
	var x := floorf(scroll / gap) * gap
	while x < scroll + size.x + gap:
		var turn := posmod(hash(int(x) + depth), 100) / 100.0
		var tall := 50.0 + turn * (170.0 - depth * 30.0)
		band.draw_rect(Rect2(x - scroll, base - tall, gap - 4.0, size.y - base + tall), colour)
		x += gap
