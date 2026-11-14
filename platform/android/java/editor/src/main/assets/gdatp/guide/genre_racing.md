# Racing games: arcade cars, tracks, drift, opponents and speed on a phone

**Arcade handling is a fake on purpose.** A simple controller feels better than a simulated car, and is easier to tune than `VehicleBody3D`. Use a `CharacterBody3D` or a body with its own forces, keep speed and heading as numbers, and steer the heading by speed.

```gdscript
extends CharacterBody3D

const TOP := 34.0
const ACCEL := 16.0
const TURN := 1.9
const GRIP := 3.5
const GRAVITY := 24.0

var speed := 0.0
var heading := 0.0
var drift := Vector3.ZERO


func _physics_process(delta: float) -> void:
	var steer := Input.get_axis("steer_right", "steer_left")
	speed = move_toward(speed, TOP, ACCEL * delta)
	heading += steer * TURN * delta * clampf(speed / 10.0, 0.0, 1.0)
	rotation.y = heading
	var forward := -transform.basis.z
	drift = drift.lerp(forward * speed, clampf(GRIP * delta, 0.0, 1.0))
	velocity.x = drift.x
	velocity.z = drift.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
```
A lower `GRIP` slides more. A drift button that lowers it and charges a boost is the genre's best idea.

**The track:** a `Path3D` as its spine. A `CSGPolygon3D` in path mode extrudes the road, walls and kerbs from it. Scatter scenery beside it (`world3d_edit scatter`). Bake checkpoints along the curve: the next must be passed before the following counts, which gives lap counting and "wrong way". Use `get_closest_offset` on the curve for race positions.

**Opponents** follow the curve: aim at a point some way ahead of their closest offset, the look-ahead growing with speed. Give each a slight line offset so they spread out. Rubber band gently: faster behind the player, slower ahead, without visible cheating.

**Sensing speed:** camera following with a delay, FOV widening as speed rises (70 to 90), roadside things close to the track passing fast, speed lines or wind particles, an engine pitch tied to speed, and a shake at boost. Reach of view matters less than things going past.

**Touch:** auto-accelerate with left and right zones or tilt (`Input.get_accelerometer`), plus one button for drift or boost, so the game needs only two thumbs. Offer tilt only as an option.

**2D top-down:** the same maths in `CharacterBody2D`; the track from a `Line2D` wide stroke; a rotating or fixed camera. It is cheap, reads well, and suits an upright phone.

**Structure:** a few short tracks of 45 to 90 seconds a lap, three laps, unlocks through a cup or a time-trial ghost. A ghost is a saved list of positions, so a rival is cheap.

**Make it yours.** Racing shopping trolleys down a hill. Boats with wakes that push others. A track being built ahead as you drive. Delivery with fragile cargo. Downhill bikes. Racing where drifting paints the road.
