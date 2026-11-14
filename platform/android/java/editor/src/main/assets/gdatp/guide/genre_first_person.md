# First-person games: shooters, walking stories, and aiming on a touch screen

`parts add first_person touch` gives the body and camera on physics ground. For a world of blocks use `voxel_world` and `voxel_player`.

**The body:** a `CharacterBody3D` with a `Node3D` head holding a `Camera3D`. Yaw turns the body, pitch turns the head, clamped to about 85 degrees. Moving is relative to where the body faces.

```gdscript
extends CharacterBody3D

const SPEED := 5.5
const GRAVITY := 18.0
@export var look_speed := 0.004
@onready var head: Node3D = $Head
var _look_finger := -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.position.x > get_viewport().get_visible_rect().size.x / 2.0:
		_look_finger = event.index if event.pressed else -1
	elif event is InputEventScreenDrag and event.index == _look_finger:
		rotate_y(-event.relative.x * look_speed)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * look_speed, -1.45, 1.45)


func _physics_process(delta: float) -> void:
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(wish.x, 0.0, wish.y)
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
```

**Aiming on a phone is hard, so help:** slow the look as the crosshair passes an enemy, snap slightly on firing, and make shots forgive a few degrees. Fire can be automatic while an enemy is under the crosshair. Keep enemies few and big.

**Shooting:** a `RayCast3D` from the camera for hitscan, a body for slow projectiles. Weapon feel is everything: recoil on the camera, a bob and sway on the held model, a flash, a decal or spark at the hit, a sound with weight, an enemy reaction that shows the hit landed.

**Enemies:** a `NavigationAgent3D` over a baked navigation mesh, with states for patrol, alert and attack (`sys_ai`). They telegraph before firing; a player must be able to know why they were hit.

**Spaces:** build from CSG or parts on a grid. Corridors and rooms with a landmark in each. Doors and small rewards pull the player on. Light leads: bright doorways draw the eye.

**Walking stories and exploration:** no combat; the verb is noticing. An interact ray with a prompt when looking at something; notes, voices, things that change when you look away. Footsteps by surface. Short (10 to 20 minutes) and specific beats long and vague.

**Comfort:** avoid head bob by default on phones; keep the FOV around 75 to 85; never take control of the camera suddenly.

**Performance:** 3D on phones needs care (`sys_performance`). Short sight lines with doors or fog help a great deal.

**Make it yours.** A shooter whose gun fires the level's objects. A photography game. Delivering mail in a building that rearranges itself. Hunting one creature by sound. Reloading as the core skill.
