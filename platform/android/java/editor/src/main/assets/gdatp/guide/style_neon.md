# Neon and glow: bright lines on black, additive light, trails, and arcade energy

**Base:** near-black background (never pure grey), with thin bright shapes. Everything that matters emits light. Everything else is nearly invisible.

**Glow in 2D:** for the Mobile renderer, set a `WorldEnvironment` with background mode Canvas, `glow_enabled` on, and modulate bright colours above 1.0 (`Color(3, 0.5, 3)`) so that only they bloom; set `rendering/viewport/hdr_2d` on. For the Compatibility renderer, fake it cheaply, which also runs on every phone: draw a soft round sprite with additive blending behind each shape.

```gdscript
extends Node2D

@export var colour := Color("29f0ff")
@export var radius := 40.0


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func _draw() -> void:
	for i in range(6, 0, -1):
		var faint := Color(colour, 0.05 * (7 - i))
		draw_circle(Vector2.ZERO, radius * i / 6.0, faint)
```

**Shapes:** `Line2D` with a width and round caps; polygons drawn only as outlines. Double-stroke a line: a wide faint additive one and a thin white core. That one trick makes it look lit.

**Trails:** record the last 20 positions in a `Line2D` with a width curve and a gradient fading out, or use `CPUParticles2D` emitting along the path. A moving thing should always have a trail.

**Everything reacts:** background grid lines that bend away from explosions (grid points pushed by distance), pulses to the music's beat, and hits that spray dozens of additive particles and tint the whole screen for a frame or two. A short screen shake, plus a brief flash.

**Colour:** two complementary hues (cyan and magenta, or orange and blue), plus white for the hot centre. Limit it. Reds for danger stand out, if reserved for that.

**Post-effects via screen shader:** a slight chromatic aberration and scan lines give a CRT feel:
```glsl
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float split = 0.002;

void fragment() {
	float r = texture(screen_texture, SCREEN_UV + vec2(split, 0.0)).r;
	float g = texture(screen_texture, SCREEN_UV).g;
	float b = texture(screen_texture, SCREEN_UV - vec2(split, 0.0)).b;
	float lines = 0.92 + 0.08 * sin(SCREEN_UV.y * 900.0);
	COLOR = vec4(vec3(r, g, b) * lines, 1.0);
}
```
Apply it on a full-screen `ColorRect` in a top `CanvasLayer`. A phone pays for each screen shader, so test on the slowest one you have.

**Text:** a thin geometric font with its own glow, in the same colour as what it describes.

**3D neon:** an unshaded material with `emission` on; dark environment; glow enabled in `WorldEnvironment` with the Mobile renderer; wireframe-looking meshes of thin boxes; fog in a saturated colour.

**Make it mean something:** neon suits speed, music, machines and cities at night. If the game is a quiet garden, it needs another look.
