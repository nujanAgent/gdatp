# Isometric: tiled diamond worlds or a tilted orthographic 3D camera, for tactics and cosy places

**Two ways. The second is usually better here.**

**1. True 3D with an orthographic camera.** This gives isometric looks with real depth, lighting, and easy sorting:
```gdscript
extends Camera3D


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = 16.0
	rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	position = Vector3(20.0, 20.0, 20.0)
```
Everything on a 1-unit grid looks correct at once. Make shapes with `world3d_edit` and `model`. To reach a tap on the ground, use `project_ray_origin` and `project_ray_normal` with a plane at height 0:
```gdscript
func ground_at(camera: Camera3D, screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var along := camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, along)
	return hit if hit != null else Vector3.ZERO
```

**2. 2D tiles.** A `TileMapLayer` whose `TileSet` has shape isometric, with a tile 2 wide by 1 high (such as 64 by 32). Turn on `y_sort_enabled` on the layer and on the sprites' parent, so that nearer things draw on top. Tall objects get their origin at their feet. Convert: `map_to_local` and `local_to_map` already do the diamond maths. Draw each tile as a diamond with a lit top and two shaded sides.

**Reading the height of things** is the style's weakness. Keep the three faces of a block in three distinct values: top lightest, left mid, right dark. Keep the same direction of light for everything. Shadows as a dark parallelogram to one side.

**Palette:** the style flatters clean colours and small details: tiny windows, chimneys, lanterns, people. Use slow, small life: smoke, a walking figure, flickering light. A little animated diorama is the appeal.

**Camera:** drag to pan, and pinch to zoom in steps. Rotation in 90-degree steps is simple with 3D and impossible with 2D tiles. Fade or cut walls that hide the player or the cursor.

**Good fits:** tactics on a grid (with height for cover), city and factory builders, cosy places to decorate, small dungeon crawls, and puzzle dioramas that the player rotates to find a hidden path.

**Touch:** tapping tiles is precise only if tiles are big enough; aim for a tile at least 48 px wide on screen, or zoom in when selecting. Show a highlight of what a tap chose, and allow a second tap to confirm.
