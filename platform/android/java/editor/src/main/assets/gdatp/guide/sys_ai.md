# Enemies and characters that behave: state machines, steering, navigation, sensing, groups

**Believable beats clever.** The player has to read what an enemy is about to do, and respond. A telegraph before each attack makes a good enemy, however simple the rules.

**State machine, as plain code:**
```gdscript
extends CharacterBody2D

enum State { PATROL, CHASE, WINDUP, STRIKE, RECOVER }

@export var target: Node2D
@export var speed := 90.0
var state := State.PATROL
var _timer := 0.0


func _physics_process(delta: float) -> void:
	_timer -= delta
	var gap := global_position.distance_to(target.global_position)
	match state:
		State.PATROL:
			velocity = Vector2.ZERO
			if gap < 260.0:
				state = State.CHASE
		State.CHASE:
			velocity = global_position.direction_to(target.global_position) * speed
			if gap < 60.0:
				_enter(State.WINDUP, 0.5)
		State.WINDUP:
			velocity = Vector2.ZERO
			if _timer <= 0.0:
				_enter(State.STRIKE, 0.15)
		State.STRIKE:
			if _timer <= 0.0:
				_enter(State.RECOVER, 0.7)
		State.RECOVER:
			velocity = Vector2.ZERO
			if _timer <= 0.0:
				state = State.CHASE
	move_and_slide()


func _enter(next: State, seconds: float) -> void:
	state = next
	_timer = seconds
```
Recovery is the player's opening. Show each state: a raised arm, a colour, a sound.

**Finding the way:**
- **Grid games:** `AStarGrid2D.get_id_path(from, to)`. For many enemies chasing one goal, compute one distance map by flood fill, and each walks downhill.
- **2D or 3D worlds:** `NavigationRegion` with a baked mesh, and a `NavigationAgent` on each enemy: set `target_position`, then move toward `get_next_path_position()`. Update the target a few times a second, not each frame.
- **Simple chasers in open arenas** need no paths at all. Add separation so that they do not stack: push away from neighbours nearby.

**Sensing:** distance first (cheap), then angle, then a ray for walls (costly, so a few times a second). Remember the last place the player was seen. Show "?" then "!" when alerted.

**Variety cheaply:** one movement with different parameters and one extra rule each: charges in straight lines; keeps distance; flees at low health; shoots only when you stop; explodes near you.

**Groups:** only two attack at once, while the others circle. A token system is simple: an enemy asks an autoload for a token before attacking. This makes crowds fair, and looks clever.

**Difficulty:** adjust reaction delay, windup length, and numbers, rather than damage. Slow reactions feel fair. A rising count of enemies is more interesting than more health.

**Bosses:** phases, each a new pattern taught by a clear tell. The player learns it, and then wins by reading it. Mid-health change of behaviour with a visible moment.

**Non-enemies:** a character with routines (walks to a bench, looks at the player, waves) makes a world alive for a few lines. Animals that scatter, crowds reacting to the player.

**Test by playing, with numbers:** `game_read sample` the enemy's state and position over frames, and check that the attack lands and can be dodged. A patrol that never meets the player, or an enemy that walks off a ledge, is found only this way.
