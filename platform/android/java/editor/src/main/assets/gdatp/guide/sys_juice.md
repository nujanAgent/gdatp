# Game feel: hit stop, squash and stretch, flashes, easing, numbers and impact

`parts add juice` gives shake, a stop on impact, pops, flashes, bursts and floating numbers.

Each action gets a response in several channels at once: motion, picture, sound. Scale it by how much the action matters. Keep each effect small and short, then check the sum.

**Hit stop:** freezing briefly gives impact more weight than anything else:
```gdscript
extends Node


func hit_stop(seconds: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
```
Use 40 to 100 ms: more for bigger hits. Reset the time scale on scene change, or the next scene plays slowly.

**Flash white:** a canvas shader with a uniform, tweened from 1 to 0:
```glsl
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 seen = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(seen.rgb, vec3(1.0), flash), seen.a);
}
```

**Squash and stretch:** keep volume: `scale = Vector2(1.0 / s, s)`. Stretch on a jump, squash on landing, recovering with a springy tween:
```gdscript
func land(sprite: Node2D) -> void:
	sprite.scale = Vector2(1.3, 0.75)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.25)
```

**Easing makes everything feel designed:** no linear movement in the interface. `TRANS_BACK` overshoots, for friendly pops; `TRANS_ELASTIC`, for bouncy rewards; `TRANS_QUINT` for snappy, slick motion; `TRANS_EXPO`, for cinematic motion. Stagger lists by 0.05 s for each item.

**Numbers and text:** damage or score pops out at the event, rises and fades in 0.6 s; bigger for bigger numbers. Score counts up rather than jumping. Bars lag behind: an instant bar and a slower white one that catches up, so that damage reads.

**Particles for every action:** dust at feet on landing and turning; sparks on hit; a burst and a ring on a kill; a trail on anything fast. See `sys_particles`. A persistent trace of battle (stains, scorch marks, debris) makes it feel like the world remembers.

**Sound scaled too:** pitch varied by a random 10 percent, so nothing repeats; layered low thump plus high crack for hits; rising pitch for chains. See `sys_audio`.

**Screen:** shake (`sys_camera`), brief zoom, slow motion on the final blow, screen-wide flash for huge events. A vignette tint at low health.

**Anticipation:** a small wind-up before any big action tells the eye what comes. A short back-step before a dash. A charge glow before a shot.

**Follow-through:** things settle after they stop: hair, capes, antennae and tails lag behind (a simple spring on a child's position).

**Waiting matters:** give idle things a breath: bob, blink, shift weight. A still world looks dead.

**Do not overdo it.** Too much shake and flash makes it hard to read and tiring. If you cannot see what is happening in your own screenshots, take some out. Respect the look: a calm game has calm responses, like soft sounds and slow easing.
