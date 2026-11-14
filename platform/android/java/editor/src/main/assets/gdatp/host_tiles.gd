
# --- tilemap_edit ----------------------------------------------------------------------------------------------------

const TILE_OPS := ["tileset_create", "layer_add", "cells_set", "rect_fill", "map_from_ascii", "erase", "clear", "read"]
const TILE_READ_MAX := Vector2i(160, 80)
const TILE_MARKS := "#=@%&*+xoOXABCDEFGHIJKLMNPQRSTUVWYZabcdefghijklmnpqrstuvwyz0123456789"


## TileSets cut from an atlas image, TileMapLayer nodes, and their cells: single cells, rectangles and whole maps drawn
## as text. Changes to the open scene are one undo step; a TileSet file is kept in GDatp's trash before it is replaced.
func _tilemap_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, TILE_OPS)
	if op.begins_with("!"):
		return _bad_op(op, TILE_OPS)
	var params: Dictionary = args.params
	if op == "tileset_create":
		return _tileset_create(params)
	var root = _scene_root(params)
	if root is Dictionary:
		return root
	if op == "layer_add":
		return _tile_layer_add(root, params)
	var found := _find_node(root, str(params.get("layer", "")))
	if found == null:
		return _missing_node(root, params.get("layer", ""))
	if not found is TileMapLayer:
		return _fail("wrong_node", "%s is a %s, not a TileMapLayer." % [found.name, found.get_class()], {"next": "tilemap_edit layer_add makes one."})
	var layer := found as TileMapLayer
	if op == "read":
		return _tile_read(layer)
	if layer.tile_set == null:
		return _fail("no_tileset", "%s has no TileSet." % layer.name, {"next": "tilemap_edit tileset_create makes one; scene_edit set tile_set gives it to the layer."})
	var before: PackedByteArray = layer.tile_map_data
	var changed := _tile_change(layer, op, params)
	if changed.has("error"):
		layer.tile_map_data = before
		return changed
	var after: PackedByteArray = layer.tile_map_data
	var paint := func():
		layer.tile_map_data = after
	var unpaint := func():
		layer.tile_map_data = before
	var steps: Array = [{"do": paint, "undo": unpaint, "text": "%s %s" % [op, layer.name]}]
	var answer := _commit_steps(root, steps, params)
	answer.merge(changed)
	answer["used_cells"] = layer.get_used_cells().size()
	answer["next"] = "tilemap_edit read shows the layer as text; screenshot editor_2d shows it drawn."
	return answer


## Sets cells on [layer] for [op]; what changed, or a refusal naming the cell and the tile it wanted.
func _tile_change(layer: TileMapLayer, op: String, params: Dictionary) -> Dictionary:
	var count := 0
	match op:
		"cells_set":
			var cells = params.get("cells", [])
			if typeof(cells) != TYPE_ARRAY or cells.is_empty():
				return _fail("missing", "cells_set needs 'cells': [{\"at\": [x, y], \"atlas\": [column, row]}].")
			for cell in cells:
				if typeof(cell) != TYPE_DICTIONARY:
					return _fail("bad_cell", "Each cell is {\"at\": [x, y], \"atlas\": [column, row], \"source\": 0}.")
				var at = _cell(cell.get("at", null))
				if at == null:
					return _fail("bad_cell", "A cell's 'at' is [x, y] in cells.")
				if cell.get("atlas", null) == null:
					layer.erase_cell(at)
				else:
					var tile := _tile(layer, cell.get("source", 0), cell.get("atlas", null), cell.get("alt", 0))
					if tile.has("error"):
						return tile
					layer.set_cell(at, tile.source, tile.atlas, tile.alt)
				count += 1
		"rect_fill":
			var rect := _numbers(params.get("rect", []), ["x", "y", "w", "h"])
			if rect.size() != 4 or rect[2] < 1 or rect[3] < 1:
				return _fail("bad_rect", "rect_fill needs 'rect': [x, y, width, height] in cells.")
			var tile := _tile(layer, params.get("source", 0), params.get("atlas", null), params.get("alt", 0))
			if tile.has("error"):
				return tile
			for y in range(int(rect[1]), int(rect[1] + rect[3])):
				for x in range(int(rect[0]), int(rect[0] + rect[2])):
					layer.set_cell(Vector2i(x, y), tile.source, tile.atlas, tile.alt)
					count += 1
		"map_from_ascii":
			var rows = params.get("rows", [])
			var legend = params.get("legend", {})
			if typeof(rows) != TYPE_ARRAY or rows.is_empty() or typeof(legend) != TYPE_DICTIONARY:
				return _fail("missing", "map_from_ascii needs 'rows' (strings, one per row of cells) and 'legend' ({\"#\": [column, row]}).")
			var origin = _cell(params.get("origin", [0, 0]))
			if origin == null:
				return _fail("bad_cell", "'origin' is [x, y] in cells.")
			var tiles := {}
			for mark in legend:
				if legend[mark] == null:
					tiles[str(mark)] = null
					continue
				var entry = legend[mark]
				var tile := _tile(layer, entry.get("source", 0) if typeof(entry) == TYPE_DICTIONARY else 0,
					entry.get("atlas", null) if typeof(entry) == TYPE_DICTIONARY else entry, 0)
				if tile.has("error"):
					tile["mark"] = str(mark)
					return tile
				tiles[str(mark)] = tile
			for y in rows.size():
				var row := str(rows[y])
				for x in row.length():
					var mark := row[x]
					if not tiles.has(mark):
						if mark == " " or mark == ".":
							continue
						return _fail("unknown_mark", "Row %d uses '%s', which the legend does not name." % [y + 1, mark], {"legend": legend.keys()})
					var at: Vector2i = origin + Vector2i(x, y)
					if tiles[mark] == null:
						layer.erase_cell(at)
					else:
						layer.set_cell(at, tiles[mark].source, tiles[mark].atlas, tiles[mark].alt)
					count += 1
		"erase":
			var cells = params.get("cells", [])
			if typeof(cells) != TYPE_ARRAY or cells.is_empty():
				return _fail("missing", "erase needs 'cells': [[x, y], …].")
			for item in cells:
				var at = _cell(item)
				if at == null:
					return _fail("bad_cell", "Each cell to erase is [x, y].")
				layer.erase_cell(at)
				count += 1
		"clear":
			count = layer.get_used_cells().size()
			layer.clear()
	return {"cells_changed": count}


## A tile of [layer]'s TileSet as {source, atlas, alt}, or a refusal listing what the source has.
func _tile(layer: TileMapLayer, source_value, atlas_value, alt_value) -> Dictionary:
	var source_id := int(source_value)
	if not layer.tile_set.has_source(source_id):
		return _fail("no_source", "The TileSet has no source %d." % source_id, {"sources": range(layer.tile_set.get_source_count()).map(func(i): return layer.tile_set.get_source_id(i))})
	var atlas = _cell(atlas_value)
	if atlas == null:
		return _fail("bad_tile", "A tile is named by its 'atlas' coordinates, [column, row] in the atlas image.")
	var source := layer.tile_set.get_source(source_id)
	if source is TileSetAtlasSource and not (source as TileSetAtlasSource).has_tile(atlas):
		return _fail("no_tile", "Source %d has no tile at %s." % [source_id, str(atlas)], {"next": "tilemap_edit read lists the tiles the layer's TileSet has."})
	return {"source": source_id, "atlas": atlas, "alt": int(alt_value)}


## [value] as a cell or atlas coordinate, or null.
func _cell(value):
	var xy := _numbers(value, ["x", "y"])
	if xy.size() != 2:
		return null
	return Vector2i(int(xy[0]), int(xy[1]))


## The layer as text, a mark per tile in a legend, and the TileSet's tiles, so a model without pictures can see it.
func _tile_read(layer: TileMapLayer) -> Dictionary:
	var answer := {"layer": _node_path(layer), "used_cells": layer.get_used_cells().size()}
	if layer.tile_set != null:
		var sources: Array = []
		for i in layer.tile_set.get_source_count():
			var id := layer.tile_set.get_source_id(i)
			var source := layer.tile_set.get_source(id)
			var entry := {"source": id, "type": source.get_class()}
			if source is TileSetAtlasSource:
				var atlas := source as TileSetAtlasSource
				entry["tile_size"] = _plain(atlas.texture_region_size)
				entry["texture"] = atlas.texture.resource_path if atlas.texture else null
				entry["tiles"] = range(atlas.get_tiles_count()).map(func(t): return _plain(atlas.get_tile_id(t)))
			sources.append(entry)
		answer["tile_size"] = _plain(layer.tile_set.tile_size)
		answer["sources"] = sources
	var used := layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		return answer
	var shown := Rect2i(used.position, used.size.min(TILE_READ_MAX))
	var marks := {}
	var legend := {}
	var rows: Array = []
	for y in range(shown.position.y, shown.end.y):
		var row := ""
		for x in range(shown.position.x, shown.end.x):
			var at := Vector2i(x, y)
			var source_id := layer.get_cell_source_id(at)
			if source_id == -1:
				row += "."
				continue
			var key := "%d:%s" % [source_id, str(layer.get_cell_atlas_coords(at))]
			if not marks.has(key):
				var mark := TILE_MARKS[marks.size() % TILE_MARKS.length()]
				marks[key] = mark
				legend[mark] = {"source": source_id, "atlas": _plain(layer.get_cell_atlas_coords(at))}
			row += marks[key]
		rows.append(row)
	answer["origin"] = _plain(shown.position)
	answer["rows"] = rows
	answer["legend"] = legend
	if shown.size != used.size:
		answer["cut"] = "The layer spans %s cells; the first %s are shown." % [str(used.size), str(shown.size)]
	return answer


## Adds a TileMapLayer with a TileSet to the open scene, as one undo step.
func _tile_layer_add(root: Node, params: Dictionary) -> Dictionary:
	var parent := _find_node(root, str(params.get("parent", ".")))
	if parent == null:
		return _missing_node(root, params.get("parent", ""))
	var tileset_path := _res_path(params.get("tileset", ""))
	if tileset_path.begins_with("!") or not ResourceLoader.exists(tileset_path, "TileSet"):
		return _fail("not_found", "There is no TileSet %s." % str(params.get("tileset", "")), {"next": "tilemap_edit tileset_create makes one from an atlas image."})
	var layer := TileMapLayer.new()
	layer.name = str(params.get("name", "TileMapLayer"))
	layer.tile_set = load(tileset_path)
	if params.has("z_index"):
		layer.z_index = int(params.z_index)
	if params.has("y_sort"):
		layer.y_sort_enabled = _flag(params.y_sort)
	var steps: Array = []
	_add_step(root, parent, layer, steps)
	var answer := _commit_steps(root, steps, params)
	answer["next"] = "tilemap_edit cells_set, rect_fill or map_from_ascii with layer %s paints it." % _node_path(layer)
	return answer


## A TileSet from an atlas image: one tile per cell of tile_size that is not empty, each with a full square collision
## shape unless collision is "none"; saved to path.
func _tileset_create(params: Dictionary) -> Dictionary:
	var path := _res_path(params.get("path", ""))
	if path.begins_with("!") or path.get_extension() != "tres":
		return _fail("bad_path", "tileset_create needs 'path', a res:// .tres file for the TileSet.")
	var texture_path := _res_path(params.get("texture", ""))
	if texture_path.begins_with("!") or not ResourceLoader.exists(texture_path, "Texture2D"):
		return _fail("not_found", "There is no image %s." % str(params.get("texture", "")), {"next": "files_edit write puts an image in the project; files_read list finds one."})
	var size = _cell(params.get("tile_size", null))
	if size == null or size.x < 1 or size.y < 1:
		return _fail("missing", "tileset_create needs 'tile_size': [width, height] in pixels.")
	var margins = _cell(params.get("margins", [0, 0]))
	var separation = _cell(params.get("separation", [0, 0]))
	if margins == null or separation == null:
		return _fail("bad_value", "margins and separation are [x, y] in pixels.")
	var texture := load(texture_path) as Texture2D
	var image := texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	var columns := int((texture.get_width() - margins.x + separation.x) / (size.x + separation.x))
	var rows := int((texture.get_height() - margins.y + separation.y) / (size.y + separation.y))
	if columns < 1 or rows < 1:
		return _fail("too_small", "%s is %dx%d, smaller than one %dx%d tile." % [texture_path, texture.get_width(), texture.get_height(), size.x, size.y])

	var tileset := TileSet.new()
	tileset.tile_size = size
	var collide := str(params.get("collision", "full")) != "none"
	if collide:
		tileset.add_physics_layer()
		tileset.set_physics_layer_collision_layer(0, 1)
		tileset.set_physics_layer_collision_mask(0, 1)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = size
	source.margins = margins
	source.separation = separation
	tileset.add_source(source, 0)
	var skip_empty := _flag(params.get("skip_empty", true))
	var half := Vector2(size) / 2.0
	var square := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	var made := 0
	for y in rows:
		for x in columns:
			var region := Rect2i(margins + Vector2i(x, y) * (size + separation), size)
			if skip_empty and image != null and image.get_region(region).is_invisible():
				continue
			source.create_tile(Vector2i(x, y))
			if collide:
				var data := source.get_tile_data(Vector2i(x, y), 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, square)
			made += 1
	if FileAccess.file_exists(path):
		_keep_in_trash(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := ResourceSaver.save(tileset, path)
	if saved != OK:
		return _fail("not_saved", "Godot could not save %s (error %d)." % [path, saved])
	EditorInterface.get_resource_filesystem().update_file(path)
	return {
		"path": path, "tiles": made, "columns": columns, "rows": rows, "source": 0, "collision": collide,
		"next": "tilemap_edit layer_add with tileset %s, then map_from_ascii with a legend of atlas [column, row]." % path,
	}
