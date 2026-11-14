# Tower defense: paths, waves, economy and the decisions that make it more than placing things

**Core decision:** where to put limited money, now or later, given what is coming. Show what the next wave holds, so the choice is informed.

**The field:** either a fixed `Path2D` that enemies follow with `PathFollow2D`, or a free grid where placing towers shapes the path. With `AStarGrid2D`, refuse a placement that blocks every route. Mazing is the richer game.

```gdscript
extends Node2D

const CELL := Vector2i(64, 64)
var grid := AStarGrid2D.new()


func _ready() -> void:
	grid.region = Rect2i(0, 0, 12, 20)
	grid.cell_size = CELL
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()


func can_place(cell: Vector2i, start: Vector2i, goal: Vector2i) -> bool:
	if grid.is_point_solid(cell):
		return false
	grid.set_point_solid(cell, true)
	var open := not grid.get_id_path(start, goal).is_empty()
	grid.set_point_solid(cell, false)
	return open
```

**Towers have roles, so combinations matter:** steady single-target damage; splash; slow or stun; armour piercing; a support that boosts neighbours. Each upgrades in two directions, so a choice is made rather than a number raised. Targeting: first by default; let the player set nearest or strongest.

**Enemies ask questions:** fast ones test coverage, armoured ones test damage type, flyers ignore the maze, swarms test splash, a boss tests everything. Introduce one new kind every few waves, always alone first.

**Waves are data:**
```gdscript
const WAVES := [
	{"kind": "runner", "count": 8, "gap": 0.6},
	{"kind": "tank", "count": 3, "gap": 1.5},
]
```

**Economy:** money per kill plus a bonus for finishing a wave early; a tower sold returns about 70 percent. Too much money removes the decisions, so measure: a good player should afford about two thirds of what they want. Enemy health rises about 8 to 12 percent a wave.

**Feel:** a range circle while placing; projectiles you can follow; enemies that visibly slow, burn or flash; a coin number on each kill; a fast-forward button, since waiting is the genre's weakness.

**Touch:** tap an empty cell for a small ring of towers with prices, tap a tower for upgrade and sell, and keep everything larger than a fingertip. Portrait suits a path running top to bottom, with the shop along the bottom.

**Make it yours.** Towers that move on a track. Enemies that rearrange the map. You build by drawing walls. Rhythm-timed shots. Defending something that walks. A puzzle version with a fixed budget for each level.
