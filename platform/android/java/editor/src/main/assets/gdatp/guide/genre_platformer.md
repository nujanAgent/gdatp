# Platformers: precision, metroidvania, puzzle platformers and how movement is tuned

`parts add platformer level2d backdrop2d touch` gives a hero with a good jump, a level from rows of text, and a painted background. The level, the enemies and the idea are yours.

Only make one when it is what was asked for, or when your own rule transforms it. The movement is the game, so it needs tuning by measurement.

**Tuning, start here and measure:** jump height 3 to 4 tiles, time to apex 0.35 s. From those: `gravity = 2 * height / t²`, `jump_velocity = gravity * t`. Fall at 1.6 times that gravity. Run speed about 6 to 8 tiles a second, reached in 0.1 s on the ground and 0.2 s in the air.

**Forgiveness:** coyote time 0.1 s; jump buffer 0.12 s; releasing early cuts the jump by half; hitboxes smaller than the sprite; corners that nudge a jumper past a ledge's edge.

```gdscript
extends CharacterBody2D

const RUN := 320.0
const ACCEL := 3000.0
const GRAVITY := 1600.0
const JUMP := -640.0
const COYOTE := 0.1
const BUFFER := 0.12

var _since_floor := 0.0
var _since_press := 1.0


func _physics_process(delta: float) -> void:
	_since_floor = 0.0 if is_on_floor() else _since_floor + delta
	_since_press = 0.0 if Input.is_action_just_pressed("jump") else _since_press + delta
	var falling := velocity.y > 0.0
	velocity.y += GRAVITY * (1.6 if falling else 1.0) * delta
	if _since_press < BUFFER and _since_floor < COYOTE:
		velocity.y = JUMP
		_since_press = 1.0
		_since_floor = 1.0
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5
	var wanted := Input.get_axis("move_left", "move_right") * RUN
	velocity.x = move_toward(velocity.x, wanted, ACCEL * delta)
	move_and_slide()
```

**Kinds that are not "run right and collect":**
- **Precision:** one screen, one hard room at a time, instant retry, death is cheap. The dash or wall jump is the toy.
- **Metroidvania:** a connected map with gates opened by abilities. Design the map on paper first: each ability opens two or three old places.
- **Puzzle platformer:** the rule is the game: time loops, swapping bodies, gravity, carrying things.
- **Side-view cinematic:** weighty movement, big silhouettes, see `genre_stealth_horror`.

**Levels:** teach a thing safely, test it with danger, then twist it by combining it with an earlier thing (`sys_levels`). The reward for exploring should be more than coins: a shortcut, a secret room, a new ability.

**Enemies** are moving level design: each has one rule the player learns: patrols a ledge, jumps when you jump, can only be hit from behind.

**Camera:** smoothing with a lead in the facing direction, a little more room below when falling, and limits at the level's edges.
