extends RefCounted
## The blocks of a voxel world: their surfaces and how they behave. Add your own before the world starts.
## Use:
##   const Blocks = preload("res://parts/voxel_blocks.gd")
##   Blocks.STONE, Blocks.GRASS, Blocks.DIRT, Blocks.WOOD, Blocks.LEAVES, Blocks.GLASS, Blocks.BRICK, Blocks.SAND, Blocks.WATER, Blocks.PLANKS, Blocks.COBBLE, Blocks.SNOW
##   var ruby = Blocks.add("Ruby", {"tile": "crystal", "hardness": 0.9, "sound": "dig_hard", "colours": {"base": Color("c02848"), "dark": Color("801830"), "light": Color("f06080")}})
##   var ash = Blocks.add("Ash", {"top": "gravel", "side": "dirt", "bottom": "stone", "solid": true, "see_through": false})
##   Blocks.NAMES[ruby]; Blocks.HARDNESS[ruby]; Blocks.SOUND[ruby]; Blocks.DUST[ruby]
## tile kinds are those of parts/paint.gd.

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const WOOD := 4
const LEAVES := 5
const GLASS := 6
const BRICK := 7
const SAND := 8
const WATER := 9
const PLANKS := 10
const COBBLE := 11
const SNOW := 12

## Each block's name, the paint kinds on its top, side and bottom, whether it hides what is behind it and shades corners,
## whether a body stops at it, whether it draws on the see-through surface, seconds of holding to break it, its sound, and what flies off it.
static var NAMES: Array = ["Air", "Grass", "Dirt", "Stone", "Wood", "Leaves", "Glass", "Brick", "Sand", "Water", "Planks", "Cobblestone", "Snow"]
static var FACES: Array = [
	["stone", "stone", "stone"], ["grass_top", "grass_side", "dirt"], ["dirt", "dirt", "dirt"], ["stone", "stone", "stone"],
	["wood_top", "wood_side", "wood_top"], ["leaves", "leaves", "leaves"], ["glass", "glass", "glass"], ["brick", "brick", "brick"],
	["sand", "sand", "sand"], ["water", "water", "water"], ["planks", "planks", "planks"], ["cobble", "cobble", "cobble"],
	["snow", "snow_side", "dirt"],
]
static var OPAQUE: Array = [0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1]
static var SOLID: Array = [0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1]
static var CLEAR: Array = [0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0]
static var HARDNESS: Array = [0.0, 0.3, 0.25, 0.75, 0.5, 0.12, 0.15, 0.7, 0.25, 0.0, 0.45, 0.75, 0.2]
static var SOUND: Array = ["", "dig_soft", "dig_soft", "dig_hard", "wood", "dig_soft", "glass", "dig_hard", "dig_soft", "splash", "wood", "dig_hard", "dig_soft"]
static var DUST: Array = [
	Color.WHITE, Color("5c8a3a"), Color("7a5a3c"), Color("83858a"), Color("6a4d2e"), Color("3f7429"), Color("dcf0fa"),
	Color("9a4f3e"), Color("d6c690"), Color("2c6cc4"), Color("ad8650"), Color("7b7d83"), Color("eaf1f6"),
]
## Colours asked for, by paint kind.
static var COLOURS := {}


static func add(block_name: String, details: Dictionary) -> int:
	var id := NAMES.size()
	var own_colours: Dictionary = details.get("colours", {})
	var tile: String = details.get("tile", "stone")
	var faces := [details.get("top", tile), details.get("side", tile), details.get("bottom", tile)]
	if not own_colours.is_empty():
		for i in faces.size():
			# A kind in its own colours gets its own place in the atlas.
			faces[i] = "%s:%s" % [faces[i], block_name]
			COLOURS[faces[i]] = own_colours
	var see_through: bool = details.get("see_through", false)
	NAMES.append(block_name)
	FACES.append(faces)
	OPAQUE.append(0 if see_through else 1)
	SOLID.append(1 if details.get("solid", true) else 0)
	CLEAR.append(1 if see_through else 0)
	HARDNESS.append(details.get("hardness", 0.5))
	SOUND.append(details.get("sound", "dig_soft"))
	DUST.append(own_colours.get("base", details.get("dust", Color(0.6, 0.6, 0.6))))
	return id
