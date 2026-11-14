# Top-down action: twin-stick shooters, bullet hell, hack and slash, horde survival

`parts add topdown level2d touch` gives a hero with a dash and rooms from rows of text.

**Core loop:** move, aim and attack at once, reading many threats. The player's position is the skill.

**Player:** instant-feeling movement (accelerate in 0.05 to 0.1 s), a small hitbox with a visible core, and a dash with brief invulnerability and a cooldown. The dash makes dangerous situations escapable and so makes them fun.

**Weapons:** give each a personality: a fast weak stream, a slow heavy shot with recoil, a spread. Every shot has a muzzle flash, a kick to the camera, a sound with varied pitch; every hit a flash and a number or a burst.

**Enemies are rules:** a chaser, a shooter that keeps its distance, a charger that telegraphs for 0.6 s and then commits, a splitter, a shielded one that must be flanked. Mix two or three at a time. Warn before spawning, so nothing appears on top of the player.

**Bullet patterns** are small loops. A ring: `for i in n: angle = TAU * i / n + offset`. A spiral: raise `offset` each shot. Aimed shots with spread. Slow bullets, bright against the background, are readable; fast ones are unfair.

**Many objects on a phone:** do not use a node and physics body per bullet past about 100. Keep bullets in arrays, move them in one `_process`, test distance to the player, and draw them in one `_draw` or a `MultiMeshInstance2D`.

```gdscript
extends Node2D

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
@export var target_path: NodePath
@onready var target: Node2D = get_node(target_path)


func fire_ring(from: Vector2, count: int, speed: float, offset: float) -> void:
	for i in count:
		var angle := TAU * i / count + offset
		positions.append(from)
		velocities.append(Vector2.from_angle(angle) * speed)


func _process(delta: float) -> void:
	for i in range(positions.size() - 1, -1, -1):
		positions[i] += velocities[i] * delta
		if positions[i].distance_squared_to(target.position) < 100.0:
			target.call("hurt")
		if not get_viewport_rect().has_point(positions[i]):
			positions.remove_at(i)
			velocities.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for p in positions:
		draw_circle(p, 6.0, Color("ff5d73"))
```

**Horde survival:** enemies come endlessly and in growing numbers; attacks fire by themselves; the decision is where to stand and which upgrade to pick from three at each level. Cap live enemies (150 on a phone) and raise their strength instead. Let enemies push apart cheaply rather than with full physics.

**Hack and slash:** an arc that sweeps over 4 to 6 frames rather than a shape appearing, a step forward on each swing, a three-hit chain, enemies with brief flinch and knockback, and a long heavy that clears space.

**Touch:** left stick to move; right stick to aim and shoot, or auto-aim at the nearest enemy with a dash button. Keep the middle of the screen clear of thumbs.

**Structure:** rooms or waves of 30 to 60 seconds with a breather and a choice between them, and a boss that tests what was learned. Runs of 5 to 15 minutes suit a phone.
