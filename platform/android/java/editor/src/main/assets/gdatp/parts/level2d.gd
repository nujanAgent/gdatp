extends Node2D
## A 2D level from rows of text: painted tiles with collision, and the places you marked for coins, enemies and the rest.
## Use:
##   var level = preload("res://parts/level2d.gd").new()
##   level.cell = 48                       # pixels a tile; 48 suits a 1280 by 720 game
##   level.tiles = {
##       "#": {"kind": "dirt", "top": "grass_top"},         # solid, with another kind where nothing is above it
##       "=": {"kind": "planks", "one_way": true},          # a platform to jump up through
##       "B": "brick",                                      # solid, the short way
##       "~": {"kind": "water", "solid": false},            # drawn but not solid
##   }
##   level.colours = {"dirt": {"base": Color("4a3f6b"), "dark": Color("2f2848"), "light": Color("6d5f96")}}   # optional
##   level.rows = [
##       "..........c.c.c.....",
##       "....S.....=====.....",
##       "##########....######",
##   ]
##   add_child(level)
##   level.where("c")                      # the middles of every c, as Vector2s, to place things on
##   level.bounds()                        # a Rect2 around the level: set a camera's limits from it
## Any letter not in tiles is empty space, so use letters to mark places. Change a tile with level.set_cell_at(column, row, "#").

const Paint := preload("res://parts/paint.gd")

var cell := 48
var tiles := {}
var colours := {}
var rows: Array = []

var _sheet: Dictionary
var _body: StaticBody2D
var _places := {}
var _kinds: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for entry: Variant in tiles.values():
		for kind: String in _kinds_of(entry):
			if not _kinds.has(kind):
				_kinds.append(kind)
	_sheet = Paint.atlas(_kinds, 16, colours) if not _kinds.is_empty() else {}
	_rebuild()


func where(mark: String) -> Array:
	return _places.get(mark, [])


func bounds() -> Rect2:
	var longest := 0
	for row: String in rows:
		longest = maxi(longest, row.length())
	return Rect2(position, Vector2(longest * cell, rows.size() * cell))


func set_cell_at(column: int, row: int, mark: String) -> void:
	if row < 0 or row >= rows.size():
		return
	var line: String = rows[row]
	if column < 0 or column >= line.length():
		return
	rows[row] = line.substr(0, column) + mark + line.substr(column + 1)
	_rebuild()


func _kinds_of(entry: Variant) -> Array:
	if entry is String:
		return [entry]
	var found: Array = [entry.get("kind", "stone")]
	if entry.has("top"):
		found.append(entry.top)
	return found


func _entry(mark: String) -> Dictionary:
	var entry: Variant = tiles.get(mark, null)
	if entry == null:
		return {}
	return {"kind": entry} if entry is String else entry


func _mark_at(column: int, row: int) -> String:
	if row < 0 or row >= rows.size():
		return " "
	var line: String = rows[row]
	return line[column] if column >= 0 and column < line.length() else " "


func _rebuild() -> void:
	if _body != null:
		_body.queue_free()
	_body = StaticBody2D.new()
	add_child(_body)
	_places.clear()
	for row in rows.size():
		var line: String = rows[row]
		var run_start := -1
		var run_one_way := false
		for column in line.length() + 1:
			var mark := line[column] if column < line.length() else " "
			var entry := _entry(mark)
			if entry.is_empty() and mark != "." and mark != " ":
				if not _places.has(mark):
					_places[mark] = []
				_places[mark].append(position + Vector2(column + 0.5, row + 0.5) * cell)
			var solid: bool = not entry.is_empty() and entry.get("solid", true)
			var one_way: bool = solid and entry.get("one_way", false)
			if run_start >= 0 and (not solid or one_way != run_one_way):
				_add_collider(run_start, column, row, run_one_way)
				run_start = -1
			if solid and run_start < 0:
				run_start = column
				run_one_way = one_way
	queue_redraw()


func _add_collider(first: int, past: int, row: int, one_way: bool) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2((past - first) * cell, cell)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2((first + past) * 0.5, row + 0.5) * cell
	collider.one_way_collision = one_way
	_body.add_child(collider)


func _draw() -> void:
	if _sheet.is_empty():
		return
	var texture: Texture2D = _sheet.texture
	var tile_size: int = _sheet.size
	var columns: int = _sheet.columns
	var index: Dictionary = _sheet.index
	for row in rows.size():
		var line: String = rows[row]
		for column in line.length():
			var entry := _entry(line[column])
			if entry.is_empty():
				continue
			var kind: String = entry.get("kind", "stone")
			if entry.has("top") and _entry(_mark_at(column, row - 1)).is_empty():
				kind = entry.top
			var tile: int = index[kind]
			var source := Rect2(tile % columns * tile_size, floori(float(tile) / columns) * tile_size, tile_size, tile_size)
			draw_texture_rect_region(texture, Rect2(Vector2(column, row) * cell, Vector2(cell, cell)), source)
