# Shaders that change a game's look: water, wind, dissolve, outlines, grain, on phone budgets

A few short shaders change a game's identity more than many sprites do. Write `.gdshader` files with `files_edit`, and assign them with `resource_edit`. `files_edit` reports compile errors for shaders.

**Screen effects:** a `ColorRect` covering the screen inside a high `CanvasLayer`, with a material using `hint_screen_texture`. One or two at most on phones; test on the slowest one.

**Grain and tint over everything:**
```glsl
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec3 tint = vec3(1.0, 0.95, 0.85);
uniform float grain = 0.04;

void fragment() {
	vec3 seen = texture(screen_texture, SCREEN_UV).rgb * tint;
	float n = fract(sin(dot(SCREEN_UV * 800.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(seen + (n - 0.5) * grain, 1.0);
}
```

**Dissolve** for deaths and transitions:
```glsl
shader_type canvas_item;
uniform sampler2D pattern : repeat_enable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge : source_color = vec4(1.0, 0.6, 0.2, 1.0);

void fragment() {
	vec4 seen = texture(TEXTURE, UV);
	float n = texture(pattern, UV).r;
	if (n < amount) {
		discard;
	}
	COLOR = mix(seen, edge, step(n, amount + 0.05) * step(0.001, amount));
}
```
Make `pattern` with `image_edit noise`. Tween `amount` from 0 to 1.

**Wind in 3D** moves the tops of plants, trees and banners by height:
```glsl
shader_type spatial;
uniform vec4 colour : source_color = vec4(0.35, 0.55, 0.3, 1.0);
uniform float sway = 0.15;

void vertex() {
	float t = TIME * 1.6 + NODE_POSITION_WORLD.x * 0.7 + NODE_POSITION_WORLD.z * 0.5;
	VERTEX.x += sin(t) * sway * VERTEX.y;
	VERTEX.z += cos(t * 0.8) * sway * 0.5 * VERTEX.y;
}

void fragment() {
	ALBEDO = colour.rgb;
	ROUGHNESS = 1.0;
}
```

**Simple water:** a flat plane with moving colour bands:
```glsl
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.05, 0.25, 0.4, 1.0);
uniform vec4 shallow : source_color = vec4(0.2, 0.6, 0.65, 1.0);
uniform float waves = 0.12;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.8 + TIME) * cos(VERTEX.z * 0.6 + TIME * 0.7) * waves;
}

void fragment() {
	float band = 0.5 + 0.5 * sin(UV.x * 40.0 + UV.y * 30.0 + TIME);
	ALBEDO = mix(deep.rgb, shallow.rgb, band * 0.4);
	ROUGHNESS = 0.2;
	METALLIC = 0.1;
}
```

**Palette swap and colour control in 2D:** map a sprite's grey value to a colour ramp: `COLOR.rgb = texture(ramp, vec2(seen.r, 0.0)).rgb;`, so that a single sprite gives many enemy colours, and a whole game can change season.

**Scrolling and wobble:** `UV += TIME * speed` scrolls textures. Sine offsets to `UV` make heat or underwater wobble.

**Compatibility renderer limits:** `hint_screen_texture` and `render_mode` work, but some effects need the Mobile renderer: real glow on 2D, `SSAO`, volumetric fog. `resource_edit`, `world3d_edit` and `sys_performance` tell you what applies. Avoid loops and `discard` on fullscreen effects on low-end phones.

**Keep it the look, not the effect:** every game's shader should be chosen by the plan in DESIGN.md. Bloom added to everything looks like every other game that did the same.
