extends RefCounted
## Paints pixel-art surfaces in code, as images, textures, 3D materials or an atlas of tiles, in the default colours or the game's own.
## Use:
##   const Paint = preload("res://parts/paint.gd")
##   $Sprite2D.texture = Paint.texture("brick")
##   $Floor.material_override = Paint.material("stone", 16, 4.0)          # tiled 4 times across the mesh
##   var look = {"base": Color("4a3f6b"), "dark": Color("2f2848"), "light": Color("6d5f96")}
##   Paint.texture("cobble", 32, look)                                    # any kind, any size, your colours
##   var sheet = Paint.atlas(["grass_top", "dirt", "stone"])              # {texture, image, columns, rows, size, index: {name: tile}}
##   Paint.seed_value = hash("my game")                                   # so this game's surfaces are its own
## Kinds: grass_top grass_side dirt stone cobble brick planks wood_side wood_top leaves sand gravel snow snow_side ice water
##        lava metal glass crystal floor roof moss cloth concrete

const KINDS := {
	"grass_top": ["5c8a3a", "4d7a30", "6b9a45"],
	"grass_side": ["7a5a3c", "624730", "5c8a3a"],
	"dirt": ["7a5a3c", "624730", "8b6a4a"],
	"stone": ["83858a", "6e7076", "95979c"],
	"cobble": ["7b7d83", "55565c", "8f9197"],
	"brick": ["9a4f3e", "c2b8ab", "ab5c49"],
	"planks": ["ad8650", "7b5d36", "bd9660"],
	"wood_side": ["6a4d2e", "523a20", "785a38"],
	"wood_top": ["b08c58", "6a4d2e", "98774a"],
	"leaves": ["3f7429", "336322", "4c8433"],
	"sand": ["d6c690", "c6b57e", "e2d4a0"],
	"gravel": ["84807a", "6b6762", "9a968f"],
	"snow": ["eaf1f6", "d8e4ee", "f6fafc"],
	"snow_side": ["7a5a3c", "624730", "eaf1f6"],
	"ice": ["a9d3ec", "8fc0e0", "cfe8f6"],
	"water": ["2c6cc4", "2964b8", "3a78cc"],
	"lava": ["e8641e", "a82c10", "ffc23a"],
	"metal": ["8d949c", "6c727a", "b4bbc3"],
	"glass": ["dcf0fa", "e4f4fc", "ffffff"],
	"crystal": ["8a5cd8", "5e3aa8", "c6a4f6"],
	"floor": ["b9b2a4", "8c867a", "c9c3b6"],
	"roof": ["8c3f34", "6c2e26", "a24d40"],
	"moss": ["5f7f3e", "4a6830", "76964f"],
	"cloth": ["b0413e", "8f3331", "c75350"],
	"concrete": ["9b9c9e", "88898b", "a9aaac"],
}

static var seed_value := 90210


## An image of [param kind], [param size] pixels square, in the default colours or those in [param colours] (base, dark, light).
static func tile(kind: String, size := 16, colours := {}) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	_paint_into(image, Vector2i.ZERO, size, kind, colours)
	return image


## A texture of [param kind]; a sprite or a tile drawn with it keeps its hard pixels when its filter is nearest.
static func texture(kind: String, size := 16, colours := {}) -> ImageTexture:
	return ImageTexture.create_from_image(tile(kind, size, colours))


## A 3D material of [param kind], repeated [param repeats] times across the mesh.
static func material(kind: String, size := 16, repeats := 1.0, colours := {}) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.albedo_texture = texture(kind, size, colours)
	made.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	made.uv1_scale = Vector3(repeats, repeats, repeats)
	made.roughness = 0.95
	made.metallic_specular = 0.2
	if kind in ["glass", "water", "ice", "leaves"]:
		made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return made


## One image holding every kind in [param kinds]: {texture, image, columns, rows, size, index}, with index naming each kind's tile.
static func atlas(kinds: Array, size := 16, colours_by_kind := {}) -> Dictionary:
	var columns := mini(8, kinds.size())
	var rows := ceili(float(kinds.size()) / columns)
	var image := Image.create_empty(size * columns, size * rows, false, Image.FORMAT_RGBA8)
	var index := {}
	for i in kinds.size():
		var kind: String = kinds[i]
		index[kind] = i
		_paint_into(image, Vector2i(i % columns, floori(float(i) / columns)) * size, size, kind, colours_by_kind.get(kind, {}))
	return {"texture": ImageTexture.create_from_image(image), "image": image, "columns": columns, "rows": rows, "size": size, "index": index}


static func _paint_into(image: Image, at: Vector2i, size: int, kind: String, colours: Dictionary) -> void:
	# "stone:Ruby" is stone in colours of its own, with its own place in an atlas.
	var shape := kind.get_slice(":", 0)
	var defaults: Array = KINDS.get(shape, KINDS["stone"])
	var base: Color = colours.get("base", Color(defaults[0]))
	var dark: Color = colours.get("dark", Color(defaults[1]))
	var light: Color = colours.get("light", Color(defaults[2]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) ^ seed_value
	match shape:
		"grass_top", "dirt", "sand", "gravel", "snow", "moss", "concrete":
			_speckle(image, at, size, rng, base, dark, light, _speckle_amount(shape))
		"grass_side":
			_speckle(image, at, size, rng, base, dark, Color(defaults[0]), 0.16)
			_cap(image, at, size, rng, light, 2, 5)
		"snow_side":
			_speckle(image, at, size, rng, base, dark, Color(defaults[0]), 0.16)
			_cap(image, at, size, rng, light, 3, 6)
		"stone", "metal":
			_speckle(image, at, size, rng, base, dark, light, 0.12)
			_scratches(image, at, size, rng, dark)
		"cobble":
			_cells(image, at, size, rng, base, dark, light, 9)
		"crystal":
			_cells(image, at, size, rng, base, dark, light, 5)
		"brick", "roof":
			_courses(image, at, size, rng, base, dark, light, 4, 8)
		"floor":
			_courses(image, at, size, rng, base, dark, light, 8, 8)
		"planks":
			_courses(image, at, size, rng, base, dark, light, 4, 11)
		"wood_side":
			_grain(image, at, size, rng, base, dark, light)
		"wood_top":
			_rings(image, at, size, rng, base, dark, light)
		"leaves":
			_leaves(image, at, size, rng, base, dark, light)
		"glass":
			_glass(image, at, size, base, light)
		"water", "ice":
			_ripples(image, at, size, base, dark, light, 0.72 if shape == "water" else 0.86)
		"lava":
			_ripples(image, at, size, base, dark, light, 1.0)
		_:
			_speckle(image, at, size, rng, base, dark, light, 0.14)


static func _speckle_amount(kind: String) -> float:
	match kind:
		"grass_top":
			return 0.2
		"gravel":
			return 0.42
		"snow", "sand", "concrete":
			return 0.1
	return 0.16


static func _varied(colour: Color, rng: RandomNumberGenerator, amount := 0.018) -> Color:
	var change := rng.randf_range(-amount, amount)
	return Color(clampf(colour.r + change, 0.0, 1.0), clampf(colour.g + change, 0.0, 1.0), clampf(colour.b + change, 0.0, 1.0), colour.a)


static func _speckle(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, base: Color, dark: Color, light: Color, amount: float) -> void:
	for y in size:
		for x in size:
			var roll := rng.randf()
			var colour := base
			if roll < amount:
				colour = dark
			elif roll < amount * 1.7:
				colour = light
			image.set_pixel(at.x + x, at.y + y, _varied(colour, rng))


static func _cap(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, colour: Color, least: int, most: int) -> void:
	var unit := maxf(size / 16.0, 1.0)
	for x in size:
		var depth := int(rng.randi_range(least, most) * unit)
		for y in depth:
			image.set_pixel(at.x + x, at.y + y, _varied(colour, rng))


static func _scratches(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, colour: Color) -> void:
	for _i in int(size * 0.45):
		var x := rng.randi_range(0, size - 5)
		var y := rng.randi_range(0, size - 2)
		for run in rng.randi_range(2, 5):
			image.set_pixel(at.x + x + run, at.y + y, colour.darkened(0.08))


static func _cells(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, base: Color, dark: Color, light: Color, count: int) -> void:
	var centres: Array[Vector2] = []
	var tones: Array[Color] = []
	for _i in count:
		centres.append(Vector2(rng.randf_range(0, size), rng.randf_range(0, size)))
		tones.append(base.lerp(light, rng.randf_range(0.0, 0.7)))
	var seam := size / 16.0 * 1.1
	for y in size:
		for x in size:
			var first := 1e9
			var second := 1e9
			var tone := base
			for i in count:
				var distance := Vector2(x, y).distance_to(centres[i])
				if distance < first:
					second = first
					first = distance
					tone = tones[i]
				elif distance < second:
					second = distance
			image.set_pixel(at.x + x, at.y + y, _varied(dark if second - first < seam else tone, rng))


static func _courses(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, base: Color, seam: Color, light: Color, high: int, wide: int) -> void:
	var unit := maxf(size / 16.0, 1.0)
	var row_height := maxi(int(high * unit), 2)
	var column_width := maxi(int(wide * unit), 2)
	for y in size:
		var row := floori(float(y) / row_height)
		var shift := 0 if row % 2 == 0 else floori(column_width / 2.0)
		for x in size:
			var column := floori(float(x + shift) / column_width)
			var tone := base.lerp(light, float(posmod(hash(Vector2i(column, row)) ^ seed_value, 4)) / 6.0)
			var joint := y % row_height == row_height - 1 or (x + shift) % column_width == column_width - 1
			image.set_pixel(at.x + x, at.y + y, _varied(seam if joint else tone, rng))


static func _grain(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, base: Color, dark: Color, light: Color) -> void:
	var tones: Array[Color] = []
	for x in size:
		var roll := rng.randf()
		tones.append(dark if roll < 0.32 else (light if roll > 0.8 else base))
	for y in size:
		for x in size:
			image.set_pixel(at.x + x, at.y + y, _varied(tones[x], rng))


static func _rings(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, base: Color, bark: Color, light: Color) -> void:
	var middle := (size - 1) * 0.5
	var unit := size / 16.0
	for y in size:
		for x in size:
			var distance := Vector2(x - middle, y - middle).length() / unit
			var colour := bark if distance > 6.8 else (light if int(distance) % 3 == 0 else base)
			image.set_pixel(at.x + x, at.y + y, _varied(colour, rng))


static func _leaves(image: Image, at: Vector2i, size: int, rng: RandomNumberGenerator, base: Color, dark: Color, light: Color) -> void:
	for y in size:
		for x in size:
			var roll := rng.randf()
			var colour := base
			if roll > 0.95:
				colour = Color(0, 0, 0, 0)
			elif roll > 0.8:
				colour = light
			elif roll < 0.34:
				colour = dark
			image.set_pixel(at.x + x, at.y + y, colour)


static func _glass(image: Image, at: Vector2i, size: int, base: Color, light: Color) -> void:
	for y in size:
		for x in size:
			var edge := x == 0 or y == 0 or x == size - 1 or y == size - 1
			var glint := absi(x + y - int(size * 0.5)) <= 1 and x > 1 and y > 1
			var colour := Color(base.r, base.g, base.b, 0.16)
			if edge:
				colour = Color(base.r, base.g, base.b, 0.95)
			elif glint:
				colour = Color(light.r, light.g, light.b, 0.65)
			image.set_pixel(at.x + x, at.y + y, colour)


static func _ripples(image: Image, at: Vector2i, size: int, base: Color, dark: Color, light: Color, opacity: float) -> void:
	var unit := size / 16.0
	for y in size:
		for x in size:
			var wave_height := sin((x + y * 0.5) * 0.8 / unit) + sin((y - x * 0.3) * 1.1 / unit)
			var colour := base
			if wave_height > 1.1:
				colour = light
			elif wave_height < -1.0:
				colour = dark
			image.set_pixel(at.x + x, at.y + y, Color(colour.r, colour.g, colour.b, opacity))
