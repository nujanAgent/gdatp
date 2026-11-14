# Moody cinematic 3D: darkness, fog, silhouettes, one warm light, and huge scale

**The look:** a dim, oversized world like a dark storybook; mostly shadow with a few pools of light; desaturated with one accent; a small figure against a huge room; fog between depth layers.

**Use the Mobile renderer if the phone can run it,** for better lights and glow. Compatibility also works, using the tricks below.

**Environment:** `world3d_edit environment`: sky colour, `ambient_energy` very low (0.05 to 0.15) with a slightly blue ambient; fog on, with a density of 0.04 to 0.1, colour a dark desaturated blue or brown; a filmic tone map. Do not make everything equally dark: **dark and low-contrast is mud; dark with strong highlights is mood.**

**Light as composition:**
- One key light per scene: a warm `OmniLight3D` or `SpotLight3D` through a door, a window or a lamp, with strong range falloff. Up to about 4 lights in view on phones.
- A cold, faint rim from behind the character, so that their outline separates from the dark.
- A lit doorway or a pale wall behind a dark figure gives a silhouette, which is the strongest image in this style.
- A window's light on the floor can be a fake: a transparent quad with an additive gradient, like the light beams:
```glsl
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 colour : source_color = vec4(1.0, 0.8, 0.55, 1.0);
uniform float strength = 0.35;

void fragment() {
	float fade = (1.0 - UV.y) * smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	ALBEDO = colour.rgb;
	ALPHA = fade * strength;
}
```
Dust particles falling slowly within those beams add a lot.

**Scale:** this is the core of the look. Build furniture and doors huge against a tiny character: 5 to 10 times larger than expected. Keep camera far, so that the character fills about 3 to 5 percent of screen height, and low, to make things loom. Rooms with very high ceilings, disappearing into dark.

**Composition and camera:** a side-on rail with a slow drift (`genre_stealth_horror`). Foreground objects (dark shapes passing close to the camera) add depth for almost nothing. Slight tilt. Layers of depth separated by fog.

**Palette:** a narrow range of grey-brown or grey-blue, with a single saturated accent reserved for the player, such as a yellow coat, red balloon or similar. Never a mid-tone character on a mid-tone background.

**Materials:** rough; little specular; a few glossy surfaces such as wet floor or polished wood catching the light. Fetch rough CC0 textures (`assets`, `style_pbr`) or paint vertex colour.

**Grading through a full-screen shader:** vignette and film grain tie the picture together:
```glsl
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float vignette = 1.1;
uniform float grain = 0.05;

void fragment() {
	vec3 seen = texture(screen_texture, SCREEN_UV).rgb;
	float edge = distance(SCREEN_UV, vec2(0.5));
	seen *= 1.0 - smoothstep(0.3, 0.85, edge) * vignette;
	float n = fract(sin(dot(SCREEN_UV * 1000.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(seen + (n - 0.5) * grain, 1.0);
}
```

**Characters:** stylised and odd: long limbs, large heads, no faces, lit from behind; slow unnatural motion. Avoid plain capsules (`sys_models3d`).

**Check it on the phone's screen.** Screens differ, and a scene that looks fine in a picture can be black in a bright room. The player, the path and every threat must be findable at a glance at full brightness, and at half.
