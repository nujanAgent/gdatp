# Cameras in 2D and 3D: following, leading, shake, framing, and collisions with walls

**A camera is a game-feel tool.** It shows what the player needs to see next, and moves smoothly but with intent.

**2D:** `Camera2D` with `position_smoothing_enabled` and a speed of about 5 to 8. Lead in the moving direction: move a target point ahead of the player by a little of the velocity. Set `limit_*` to the level's edges.

**Shake that feels good:** build up trauma, decay it, and shake by its square, with smooth noise, not random jumps:
```gdscript
extends Camera2D

@export var reach := 18.0
var trauma := 0.0
var _noise := FastNoiseLite.new()
var _clock := 0.0


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func _process(delta: float) -> void:
	trauma = maxf(trauma - delta * 1.5, 0.0)
	_clock += delta * 60.0
	var strength := trauma * trauma * reach
	offset = Vector2(_noise.get_noise_2d(_clock, 0.0), _noise.get_noise_2d(0.0, _clock)) * strength
	rotation = _noise.get_noise_2d(_clock, _clock) * 0.05 * trauma * trauma
```
Hits add 0.2 to 0.4; explosions 0.6. Make shake a setting for those who dislike it.

**3D chase:** a pivot that follows the target with `lerp`, a `SpringArm3D` child with a small `CollisionShape`, for walls, and a `Camera3D` at its end. Set the arm's `add_excluded_object` to the player's RID. The arm's length is the zoom.
```gdscript
extends Node3D

@export var target: Node3D
@export var follow := 8.0
@export var height := 1.4


func _process(delta: float) -> void:
	var wanted := target.global_position + Vector3.UP * height
	global_position = global_position.lerp(wanted, clampf(follow * delta, 0.0, 1.0))
```

**Fixed or rail cameras** often serve a phone better than an orbit: no thumb is taken up, the picture stays composed. For a rail, keep the camera at the same side and distance, sliding along a `Path3D` by the player's progress.

**Framing two things** (fighter, boss): centre between them, distance by gap, clamped.

**Field of view and lens:** a narrow FOV (30 to 45) from far away looks like a miniature; 60 to 75 is neutral; 90 is fast and distorted. Widen with speed. In 2D, zoom in for drama, out to reveal.

**Tell the camera's story:** look briefly at a door that has opened; a slow push-in on a boss; a small lag on a landing; a brief zoom at a kill. Never take over the player's control suddenly without reason.

**A camera that faces away from what you built** is a common first bug. Godot's cameras look down their negative Z. Check by `screenshot` that the player is where you expect, and use `scene_read spatial` to read where things are.

**Upright screens:** a tall view shows more above and below, so place the player low, and design levels going up or down. Check both ends of the screen: on an upright phone, a side-on game sees far less to the sides.
