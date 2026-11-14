# Roguelikes and dungeon crawlers: turn-based grids, generated levels, runs and permadeath

**The promise:** every run differs, death ends it, and the player's knowledge grows. Decisions come from items that combine.

**Turns:** the world moves only when the player does. Keep actors in a list, each with a position on a grid, and animate after the logic has resolved. This makes a deep game feasible with small art, and it plays well one-handed.

**The map:** make rooms joined by corridors, or carve with a walker, then keep only what a flood fill reaches. Seed the generator so a run can be repeated.

```gdscript
extends Node

const WIDTH := 40
const HEIGHT := 24
var rng := RandomNumberGenerator.new()
var floor_cells := {}


func carve(steps: int) -> void:
	var at := Vector2i(20, 12)
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var heading: Vector2i = directions[rng.randi_range(0, 3)]
	for _i in steps:
		floor_cells[at] = true
		if rng.randf() < 0.3:
			heading = directions[rng.randi_range(0, 3)]
		var next: Vector2i = at + heading
		if next.x > 0 and next.y > 0 and next.x < WIDTH - 1 and next.y < HEIGHT - 1:
			at = next
```

**Field of view:** cast rays to the edge of a radius with `Vector2i` steps, or use recursive shadowcasting. Keep seen cells dim and visible ones bright; not knowing is half the tension.

**Enemies have one idea each:** a slow hard hitter, a ranged one that flees, one that summons, one that only moves when you do not. A* (`AStarGrid2D`) or a distance map reached from the player, which many enemies can share cheaply.

**Items should combine.** Damage bonuses bore; rules excite: "fire spreads over oil", "your shield also hits", "teleport swaps places". Identify potions by using them. Three choices after each room or level is a strong shape.

**Structure:** 3 to 5 areas, each with its own enemies and look; each floor a little harder; a boss at each area's end. A run of 10 to 25 minutes suits a phone, with a save at each step so nothing is lost when the phone is put down.

**After death:** a short telling of the run: what killed you, what you carried, how far you got; then one tap to go again. Unlock new starts or items, which add choice rather than raw power.

**Real-time versions** (action roguelike): rooms with doors that lock until they are clear, see `genre_action_topdown`.

**Make it yours.** A dungeon that is a stomach. A heist with a crew that dies for good. Tiles that are also the items. A grid that scrolls so you can never go back. The rules are small enough for a very strange idea to fit.
