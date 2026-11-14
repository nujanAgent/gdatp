
# --- image_edit ------------------------------------------------------------------------------------------------------

const IMAGE_OPS := ["pixels", "noise", "gradient", "info", "palette", "look", "resize", "crop", "flip", "rotate", "recolor", "pixelate", "sheet"]
const IMAGE_MAX_SIDE := 4096
const IMAGE_MAX_GENERATED := 2048
const IMAGE_LOOK_SIDE := 1024
const IMAGE_SAMPLE_PIXELS := 200000.0
const NOISE_TYPES := {"simplex": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "perlin": FastNoiseLite.TYPE_PERLIN, "cellular": FastNoiseLite.TYPE_CELLULAR, "value": FastNoiseLite.TYPE_VALUE}


## Pictures in the project: written from rows of pixels, noise or gradients; read for size and colours; shown to the
## model; and changed into new files. A new picture is imported before the answer returns.
func _image_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, IMAGE_OPS)
	if op.begins_with("!"):
		return _bad_op(op, IMAGE_OPS)
	var params: Dictionary = args.params
	match op:
		"pixels":
			return await _image_pixels(params)
		"noise":
			return await _image_noise(params)
		"gradient":
			return await _image_gradient(params)
		"sheet":
			return await _image_sheet(params)
	var path := _res_path(params.get("path", ""))
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	var image := _image_open(path)
	if image == null:
		return _fail("not_found", "%s could not be read as a picture." % path, {"next": "files_read list shows the project's files."})
	match op:
		"info":
			return _image_info(path, image)
		"palette":
			return {"path": path, "colors": _image_palette(image, int(params.get("count", 6)))}
		"look":
			return _image_look(path, image)
		"resize":
			var wanted := _image_wanted_size(params, image)
			if wanted == Vector2i.ZERO:
				return _fail("bad_value", "resize needs size [w, h] or scale, up to %d a side." % IMAGE_MAX_SIDE)
			image.resize(wanted.x, wanted.y, Image.INTERPOLATE_NEAREST if str(params.get("filter", "lanczos")) == "nearest" else Image.INTERPOLATE_LANCZOS)
		"crop":
			var rect := _numbers(params.get("rect", []), ["x", "y", "w", "h"])
			if rect.size() != 4:
				return _fail("bad_value", "crop needs rect [x, y, w, h].")
			image = image.get_region(Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])))
		"flip":
			if str(params.get("axis", "x")) == "y":
				image.flip_y()
			else:
				image.flip_x()
		"rotate":
			var turns := posmod(int(params.get("turns", 1)), 4)
			for _i in turns:
				image.rotate_90(CLOCKWISE)
		"recolor":
			var failed := _image_recolor(image, params)
			if not failed.is_empty():
				return failed
		"pixelate":
			var width := clampi(int(params.get("width", 64)), 2, IMAGE_MAX_SIDE)
			image.resize(width, maxi(1, int(round(float(image.get_height()) * width / image.get_width()))), Image.INTERPOLATE_BILINEAR)
			if params.has("colors"):
				var failed := _image_recolor(image, {"colors": params.colors})
				if not failed.is_empty():
					return failed
	return await _image_save(_image_target(params, path), image)


func _image_open(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _image_target(params: Dictionary, path: String) -> String:
	return str(params.get("to", path))


## Writes [image] as a PNG at [target] and has the editor import it.
func _image_save(target: String, image: Image) -> Dictionary:
	var path := _res_path(target)
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	if path.get_extension().to_lower() != "png":
		return _fail("bad_path", "A picture is written as a .png file, such as res://art/hero.png; %s is not." % path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var saved := image.save_png(ProjectSettings.globalize_path(path))
	if saved != OK:
		return _fail("not_saved", "%s could not be written (%s)." % [path, error_string(saved)])
	var imported: bool = await _imported(path)
	var answer := {"path": path, "size": [image.get_width(), image.get_height()], "imported": imported}
	answer["next"] = "image_edit look shows it to you; a Sprite2D's texture or a tileset can use it."
	return answer


## Rows of letters become pixels by a palette, so exact pixel art can be written as text. `frames` makes a sheet side by side.
func _image_pixels(params: Dictionary) -> Dictionary:
	var palette = params.get("palette")
	if not palette is Dictionary or palette.is_empty():
		return _fail("missing", "pixels needs palette, such as {\".\": \"transparent\", \"k\": \"#1a1c2c\"}: one character for each colour.")
	var frames: Array = params.get("frames", [params.get("rows", [])])
	if frames.is_empty() or not frames[0] is Array or frames[0].is_empty():
		return _fail("missing", "pixels needs rows: an array of equal-length strings, one character for each pixel. frames takes several of those.")
	var colors := {}
	for key in palette:
		var name_of_color := str(palette[key])
		colors[str(key)] = Color(0, 0, 0, 0) if name_of_color == "transparent" or name_of_color == "" else Color.from_string(name_of_color, Color(0, 0, 0, 0))
	var height: int = frames[0].size()
	var width: int = str(frames[0][0]).length()
	if width == 0 or width * frames.size() > IMAGE_MAX_GENERATED or height > IMAGE_MAX_GENERATED:
		return _fail("bad_value", "rows are at most %d characters long and %d in number." % [IMAGE_MAX_GENERATED, IMAGE_MAX_GENERATED])
	var image := Image.create_empty(width * frames.size(), height, false, Image.FORMAT_RGBA8)
	for f in frames.size():
		var rows: Array = frames[f]
		if rows.size() != height:
			return _fail("bad_value", "Frame %d has %d rows; the first has %d. All frames are the same size." % [f, rows.size(), height])
		for y in height:
			var row := str(rows[y])
			if row.length() != width:
				return _fail("bad_value", "Row %d of frame %d has %d characters; the first has %d." % [y, f, row.length(), width])
			for x in width:
				var letter := row[x]
				if not colors.has(letter):
					if letter == "." or letter == " ":
						continue
					return _fail("bad_value", "'%s' in row %d is not in palette, which has: %s." % [letter, y, " ".join(PackedStringArray(colors.keys()))])
				image.set_pixel(f * width + x, y, colors[letter])
	var scale := clampi(int(params.get("scale", 1)), 1, 32)
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var answer: Dictionary = await _image_save(str(params.get("path", "")), image)
	if frames.size() > 1 and not answer.has("error"):
		answer["frame_size"] = [width * scale, height * scale]
		answer["frames"] = frames.size()
	return answer


func _image_ramp(values, fallback: Array) -> Gradient:
	var gradient := Gradient.new()
	var list: Array = values if values is Array and values.size() >= 2 else fallback
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in list.size():
		offsets.append(float(i) / (list.size() - 1))
		colors.append(Color.from_string(str(list[i]), Color.MAGENTA))
	gradient.offsets = offsets
	gradient.colors = colors
	return gradient


func _image_size_param(params: Dictionary, fallback: int) -> Vector2i:
	var size := _numbers(params.get("size", [fallback, fallback]), ["w", "h"])
	if size.size() != 2:
		return Vector2i(fallback, fallback)
	return Vector2i(clampi(int(size[0]), 1, IMAGE_MAX_GENERATED), clampi(int(size[1]), 1, IMAGE_MAX_GENERATED))


## Noise as a picture, tiling by default: cloud, grain, marble or dissolve patterns, coloured by `colors` from low to high.
func _image_noise(params: Dictionary) -> Dictionary:
	var size := _image_size_param(params, 256)
	var noise := FastNoiseLite.new()
	noise.seed = int(params.get("seed", 1))
	noise.frequency = float(params.get("frequency", 0.02))
	noise.fractal_octaves = clampi(int(params.get("octaves", 4)), 1, 8)
	var kind := str(params.get("type", "simplex"))
	if not NOISE_TYPES.has(kind):
		return _fail("bad_value", "type is one of: %s." % ", ".join(PackedStringArray(NOISE_TYPES.keys())))
	noise.noise_type = NOISE_TYPES[kind]
	var plain: Image = noise.get_seamless_image(size.x, size.y) if _flag(params.get("tileable", true)) else noise.get_image(size.x, size.y)
	var ramp := _image_ramp(params.get("colors"), ["#000000", "#ffffff"])
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			image.set_pixel(x, y, ramp.sample(plain.get_pixel(x, y).r))
	return await _image_save(str(params.get("path", "")), image)


## A gradient as a picture: vertical, horizontal or radial, smooth or in `steps` bands.
func _image_gradient(params: Dictionary) -> Dictionary:
	var size := _image_size_param(params, 256)
	var ramp := _image_ramp(params.get("colors"), ["#000000", "#ffffff"])
	var steps := int(params.get("steps", 0))
	var direction := str(params.get("direction", "vertical"))
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var t := float(y) / maxf(size.y - 1, 1)
			if direction == "horizontal":
				t = float(x) / maxf(size.x - 1, 1)
			elif direction == "radial":
				t = clampf(Vector2(x, y).distance_to(centre) / centre.length(), 0.0, 1.0)
			if steps > 1:
				t = floorf(t * steps) / (steps - 1) if t < 1.0 else 1.0
			image.set_pixel(x, y, ramp.sample(clampf(t, 0.0, 1.0)))
	return await _image_save(str(params.get("path", "")), image)


## Pictures of one size joined into a sheet for animation_edit.
func _image_sheet(params: Dictionary) -> Dictionary:
	var paths: Array = params.get("images", [])
	if paths.is_empty():
		return _fail("missing", "sheet needs images: an array of pictures of one size, and path for the new sheet.")
	var first: Image = null
	var columns := clampi(int(params.get("columns", paths.size())), 1, paths.size())
	var rows := ceili(float(paths.size()) / columns)
	var sheet: Image = null
	for i in paths.size():
		var source := _res_path(paths[i])
		var image := null if source.begins_with("!") else _image_open(source)
		if image == null:
			return _fail("not_found", "%s could not be read as a picture." % str(paths[i]))
		if first == null:
			first = image
			sheet = Image.create_empty(image.get_width() * columns, image.get_height() * rows, false, Image.FORMAT_RGBA8)
		elif image.get_size() != first.get_size():
			return _fail("bad_value", "%s is %s, but the first is %s. image_edit resize can match them." % [source, image.get_size(), first.get_size()])
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i((i % columns) * image.get_width(), (i / columns) * image.get_height()))
	var answer: Dictionary = await _image_save(str(params.get("path", "")), sheet)
	if not answer.has("error"):
		answer["frame_size"] = [first.get_width(), first.get_height()]
		answer["frames"] = paths.size()
		answer["columns"] = columns
	return answer


func _image_wanted_size(params: Dictionary, image: Image) -> Vector2i:
	var wanted := Vector2i.ZERO
	if params.has("scale"):
		wanted = Vector2i(int(image.get_width() * float(params.scale)), int(image.get_height() * float(params.scale)))
	else:
		var size := _numbers(params.get("size", []), ["w", "h"])
		if size.size() == 2:
			wanted = Vector2i(int(size[0]), int(size[1]))
	if wanted.x < 1 or wanted.y < 1 or wanted.x > IMAGE_MAX_SIDE or wanted.y > IMAGE_MAX_SIDE:
		return Vector2i.ZERO
	return wanted


## `map` swaps exact colours, within `tolerance`; `colors` moves every pixel to the nearest of them.
func _image_recolor(image: Image, params: Dictionary) -> Dictionary:
	var palette: Array = []
	var from: Array = []
	var to: Array = []
	if params.get("colors") is Array:
		for value in params.colors:
			palette.append(Color.from_string(str(value), Color.MAGENTA))
	elif params.get("map") is Dictionary:
		for key in params.map:
			from.append(Color.from_string(str(key), Color.MAGENTA))
			to.append(Color.from_string(str(params.map[key]), Color.MAGENTA))
	if palette.is_empty() and from.is_empty():
		return _fail("missing", "recolor needs map {\"#old\": \"#new\"} or colors [\"#a\", \"#b\"].")
	var tolerance := float(params.get("tolerance", 0.08))
	for y in image.get_height():
		for x in image.get_width():
			var seen := image.get_pixel(x, y)
			if seen.a < 0.01:
				continue
			if not palette.is_empty():
				var best: Color = palette[0]
				var best_gap := INF
				for candidate: Color in palette:
					var gap := _color_gap(seen, candidate)
					if gap < best_gap:
						best_gap = gap
						best = candidate
				image.set_pixel(x, y, Color(best, seen.a))
			else:
				for i in from.size():
					if _color_gap(seen, from[i]) <= tolerance:
						image.set_pixel(x, y, Color(to[i], seen.a))
						break
	return {}


func _color_gap(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _image_info(path: String, image: Image) -> Dictionary:
	var used := image.get_used_rect()
	return {"path": path, "size": [image.get_width(), image.get_height()], "has_transparency": image.detect_alpha() != Image.ALPHA_NONE,
		"used_rect": [used.position.x, used.position.y, used.size.x, used.size.y], "colors": _image_palette(image, 6)}


## The main colours of a picture by how much of it they cover, skipping ones close to a colour already chosen.
func _image_palette(image: Image, wanted: int) -> Array:
	var step := maxi(1, int(ceil(sqrt(image.get_width() * image.get_height() / IMAGE_SAMPLE_PIXELS))))
	var counts := {}
	var total := 0
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var seen := image.get_pixel(x, y)
			if seen.a < 0.5:
				continue
			var key := Vector3i(int(seen.r * 15.0), int(seen.g * 15.0), int(seen.b * 15.0))
			counts[key] = int(counts.get(key, 0)) + 1
			total += 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var chosen: Array = []
	var picked: Array = []
	for key: Vector3i in keys:
		var color := Color((key.x + 0.5) / 15.0, (key.y + 0.5) / 15.0, (key.z + 0.5) / 15.0)
		var close := false
		for other: Color in picked:
			if _color_gap(color, other) < 0.14:
				close = true
				break
		if close:
			continue
		picked.append(color)
		chosen.append({"color": "#" + color.to_html(false), "share": snappedf(float(counts[key]) / maxi(total, 1), 0.01)})
		if chosen.size() >= clampi(wanted, 1, 16):
			break
	return chosen


## A copy in the cache for the tool's answer to attach as a picture, so the model sees it.
func _image_look(path: String, image: Image) -> Dictionary:
	var longest := maxi(image.get_width(), image.get_height())
	var original := image.get_size()
	if longest > IMAGE_LOOK_SIDE:
		image.resize(original.x * IMAGE_LOOK_SIDE / longest, original.y * IMAGE_LOOK_SIDE / longest, Image.INTERPOLATE_LANCZOS)
	var dir := OS.get_cache_dir().path_join("gdatp")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := dir.path_join("look_%d.png" % Time.get_ticks_msec())
	var saved := image.save_png(shot)
	if saved != OK:
		return _fail("not_saved", "The picture could not be prepared (%s)." % error_string(saved))
	return {"path": shot, "of": path, "size": [original.x, original.y]}


## Told that files have been placed in the project from outside: has the editor find and import them before answering.
func _assets_placed(args: Dictionary) -> Dictionary:
	var first := str(args.params.get("first", ""))
	if first.is_empty():
		EditorInterface.get_resource_filesystem().scan()
		return {"imported": true}
	return {"imported": await _imported(first)}


## The editor setting under which the engine's Android exporter opens Android's installer after every export.
const EXPORT_OPENS_INSTALLER := "export/android/install_exported_apk"


## Exports the open project with the settings GDatp worked out, saving every open scene first. Called by GDatp's export tool,
## which leaves the installer to GDatp: it is offered once, when the turn that exported ends, so the engine's own prompt after
## each export is held off for this call and the person's setting is put back after it.
func _export_game(args: Dictionary) -> Dictionary:
	EditorInterface.save_all_scenes()
	var params: Dictionary = args.params
	var settings := EditorInterface.get_editor_settings()
	var opens_installer: Variant = settings.get_setting(EXPORT_OPENS_INSTALLER) if settings.has_setting(EXPORT_OPENS_INSTALLER) else null
	if opens_installer != null:
		settings.set_setting(EXPORT_OPENS_INSTALLER, false)
	var result: Dictionary = get_parent().export_android(params.settings, str(params.path), str(params.get("exclude", "")))
	if opens_installer != null:
		settings.set_setting(EXPORT_OPENS_INSTALLER, opens_installer)
	if int(result.get("error", FAILED)) != OK:
		return _fail("export_failed", "The export stopped (%s)." % error_string(int(result.get("error", FAILED))), {"messages": result.get("messages", [])})
	return {"exported": str(params.path), "messages": result.get("messages", [])}
