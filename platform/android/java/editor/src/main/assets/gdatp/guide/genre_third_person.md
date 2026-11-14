# Third-person 3D action and adventure: cameras, movement relative to view, combat and worlds

`parts add third_person touch` gives the hero, its camera arm and a simple body you can replace.

**The camera decides the feel.** Options, from simple to hard: fixed angles per room (cheap, cinematic); a rail along a path; a chase camera that the player only nudges; a free orbit. Choose the least free one that suits the game; touch controls favour less camera work.

**Orbit camera:** a yaw pivot at the player, a `SpringArm3D` child so it does not pass through walls, and a `Camera3D` on the arm. Drag on the right half turns it.

**Move relative to the camera:**
```gdscript
extends CharacterBody3D

const SPEED := 6.0
const TURN := 12.0
const GRAVITY := 20.0
const JUMP := 8.0
@export var camera_pivot: Node3D
@onready var body: Node3D = $Body


func _physics_process(delta: float) -> void:
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(wish.x, 0.0, wish.y).rotated(Vector3.UP, camera_pivot.global_rotation.y)
	velocity.x = move_toward(velocity.x, direction.x * SPEED, 40.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * SPEED, 40.0 * delta)
	if direction.length() > 0.1:
		var target := atan2(-direction.x, -direction.z)
		body.rotation.y = lerp_angle(body.rotation.y, target, TURN * delta)
	velocity.y = (JUMP if Input.is_action_just_pressed("jump") else 0.0) if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
```

**A character needs a body.** A capsule reads as a placeholder. Build jointed models from parts (`sys_models3d`), or fetch models (`assets`). Lean into a turn, stretch on a jump, squash on landing; a blob shadow under the feet helps judge jumps, which is worth a great deal.

**Combat:** swings with a wind up, an active arc and a recovery; a step forward on the swing; a lock-on to the nearest enemy, which also fixes aiming on touch; a dodge with brief invulnerability; enemies that attack one at a time while others circle.

**Worlds:** a small dense place beats a big empty one. Build a hub with routes that return to it; make landmarks visible from far away; use `world3d_edit` terrain and scatter for outdoors and CSG for buildings. Check placement with `scene_read spatial`, since a screenshot cannot show that something floats by a little.

**Reading depth:** a clear shadow, fog that separates near and far, colour-coding what can be walked on.

**Touch:** left stick for moving, drag on the right half for the camera, big buttons for jump and attack near the right thumb. Let the camera follow by itself as the player moves.

**Scale of work:** the failures here are too much space, no animation, and a fighting camera. A 10-minute third-person game done well means one area, three enemy kinds and a clear goal.

**Make it yours.** A character who changes size. A gardener in a hostile garden. A dog fetching things across a village. A mech you repair as you go. A small knight in a giant house.
