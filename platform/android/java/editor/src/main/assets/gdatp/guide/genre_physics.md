# Physics games: slingshots, golf, pinball, stacking, ragdolls and toys that are fun to break

**Physics is fun when the player sees a result they caused.** Set up, release, and watch; retry at once; the outcome is never quite the same.

**Aiming by drag:** press, drag back, see a dotted line predicting the path, and release. The prediction teaches the physics, which makes skill possible.

```gdscript
extends Node2D

const POWER := 6.0
const GRAVITY := Vector2(0.0, 980.0)
@export var ball: RigidBody2D
var _start := Vector2.ZERO
var _aiming := false
var _pull := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_start = event.position
			_aiming = true
		elif _aiming:
			_aiming = false
			ball.apply_central_impulse(_pull * POWER)
			queue_redraw()
	elif event is InputEventScreenDrag and _aiming:
		_pull = (_start - event.position).limit_length(220.0)
		queue_redraw()


func _draw() -> void:
	if not _aiming:
		return
	var velocity := _pull * POWER / ball.mass
	for i in range(1, 14):
		var t := i * 0.07
		draw_circle(to_local(ball.global_position) + velocity * t + GRAVITY * t * t / 2.0, 4.0, Color.WHITE)
```

**Settings that matter:**
- Fast, small objects pass through walls: set `continuous_cd` on a RigidBody, and make walls thick.
- Stacks jitter: lower bounce, raise friction, and let bodies sleep. Fewer, larger pieces hold better.
- Set a `physics_material_override` for every kind of thing: rubber bounces, wood knocks, ice slides. Each has its sound on impact, with volume from impact speed in `body_entered`, using `contact_monitor` on.
- Do not change a RigidBody's position directly while it simulates; use impulses, or `_integrate_forces`.
- Budgets on a phone: 2D about 150 active bodies; 3D about 50. Jolt is on by default in 3D.

**Kinds:**
- **Slingshot:** structures to bring down, few shots, a star score by what remains.
- **Golf and billiards:** angle and strength; the level shape is the puzzle; the camera follows and then shows the result.
- **Pinball:** flippers on the two sides of the screen fit a phone very well; bumpers with hard bounces and lights; a story on the table.
- **Stacking and balance:** drop or place things that topple, with a wobble you can feel; or a tower that has to survive a shake.
- **Ragdoll and joints:** bodies linked by `PinJoint2D` or `Generic6DOFJoint3D`. Bad control is funny if failure is safe and quick.
- **Vehicles and contraptions:** the player builds from parts, then watches it go or fall apart. Share what was made.

**Fair randomness:** physics is chaotic; a level must not depend on a lucky bounce. Test each level several times by script through `game_edit` and `input`.

**Feel:** a slow motion on the last piece falling; big dust and debris; a camera that pulls back to show everything; a rising tone for a chain of knocks.

**Make it yours.** Bowling with a cow. Rescuing people from a tilting ship. A crane operator on a windy day. A pet that you fling to where it wants to be. A delicate moving job on a staircase.
