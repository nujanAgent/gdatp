# Particles: dust, sparks, explosions, smoke, rain and magic, with values that look right

**Use `CPUParticles2D` and `CPUParticles3D`.** They run reliably on all phones and the Compatibility renderer. `GPUParticles` are for very large counts on the Mobile renderer.

Bursts: `one_shot` on, `explosiveness` 1, then `emitting = true`; remove the node on `finished`. Keep counts modest: 8 to 30 for a burst, 100 a screen at most.

**Recipes (2D, per property):**

| Effect | Amount | Life | Spread | Speed | Gravity | Scale | Colour |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Landing dust | 8 | 0.35 | 60 | 40 to 90 | -20 | 4 to 8, shrinking | ground tone, fading |
| Sparks | 16 | 0.3 | 180 | 150 to 400 | 500 | 2 to 3 | white to orange |
| Coin burst | 12 | 0.5 | 180 | 80 to 200 | 300 | 4 | gold, fading |
| Smoke | 12 | 1.2 | 25 | 20 to 40 | -40 | 10 to 28, growing | grey, fading |
| Rain | 80 | 0.7 | 5 | 700 | 0 | thin streak | pale, low alpha |
| Magic | 20 | 0.9 | 180 | 10 to 40 | -30 | 3, pulsing | accent colour |

```gdscript
extends Node

func burst(parent: Node, at: Vector2, tint: Color, count := 16) -> void:
	var fx := CPUParticles2D.new()
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = count
	fx.lifetime = 0.45
	fx.spread = 180.0
	fx.initial_velocity_min = 80.0
	fx.initial_velocity_max = 260.0
	fx.gravity = Vector2(0.0, 400.0)
	fx.scale_amount_min = 2.0
	fx.scale_amount_max = 5.0
	var fade := Gradient.new()
	fade.set_color(0, tint)
	fade.set_color(1, Color(tint, 0.0))
	fx.color_ramp = fade
	fx.position = at
	fx.finished.connect(fx.queue_free)
	parent.add_child(fx)
	fx.emitting = true
```

**Texture sets the style.** A small soft circle gives smoke and glow. A square in pixel art. A leaf, a star, a shard of paper, an ink drop. Drawn SVG particles matching the game's look separate it from the default dots. Use additive blending (`CanvasItemMaterial`) for fire and magic.

**Shape of emission:** a line for rain across the screen's top (`emission_shape` rectangle, off-screen), a ring for shockwaves, a point for sparks. Use `direction` and `spread` to make a directional spray opposite to a hit, showing force.

**Layers make good effects:** an explosion is a flash (one frame, big, white), a ring expanding quickly, sparks, then slow smoke. Each is small; together they read as something strong.

**Ambient particles give life for very little:** drifting motes in a beam of light, falling leaves, snow, embers, bubbles, fireflies. Slow and sparse, placed to fit the mood. Attach to the camera, so they are always in view.

**3D:** `CPUParticles3D` with a `QuadMesh`, a material with billboard on, unshaded. Use fewer, larger ones. A flat, drawn impact on a quad facing the camera costs little.

**Keep it readable:** particles must not hide the player or a threat. Effects that matter to the game should differ in colour from the decorative ones.
