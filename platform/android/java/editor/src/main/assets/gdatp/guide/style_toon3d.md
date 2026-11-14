# Toon 3D: hard-band shading, thick outlines, rim light, like an animated film or comic

**Shading in bands** instead of a smooth gradient. Assign this as a `ShaderMaterial` with `resource_edit`. It runs on Compatibility too.

```glsl
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec4 base : source_color = vec4(0.9, 0.5, 0.3, 1.0);
uniform vec4 shade : source_color = vec4(0.45, 0.25, 0.35, 1.0);
uniform float edge : hint_range(0.0, 1.0) = 0.45;
uniform float rim_power = 3.0;

void fragment() {
	ALBEDO = vec3(1.0);
}

void light() {
	float amount = step(edge, dot(NORMAL, LIGHT) * ATTENUATION);
	DIFFUSE_LIGHT += mix(shade.rgb, base.rgb, amount) * LIGHT_COLOR / 3.14159;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += step(0.6, rim) * amount * vec3(0.25);
}
```

**Outlines by inverted hull:** a second material, set as `next_pass`, draws the mesh again slightly larger and from the inside:
```glsl
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 line : source_color = vec4(0.07, 0.05, 0.1, 1.0);
uniform float thickness = 0.02;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = line.rgb;
}
```
Use thick lines on characters and thin ones on the environment. It needs smooth normals, or the hull breaks at the corners of boxes; use more rounded shapes where it does.

**Light plan:** one main directional light sets the bands. Keep shadows clean and hard. Ambient is low-importance, since shade colour comes from the shader. A saturated sky, and clouds as simple shapes.

**Colour:** saturated, with a shaded version shifted toward purple or blue, rather than a darker one. A coloured shade makes it look painted. Faces and hair stay simple.

**Motion gives it the animated look:** hold poses, snap quickly between them, smear stretched shapes on fast moves, and exaggerate squash and stretch on bodies. Limit animation to 12 poses a second for characters, for an anime feel, while the camera stays smooth.

**Effects drawn rather than simulated:** impact stars as flat shapes facing the camera; speed lines around the view when fast; solid-coloured explosions, with hard-edged puffs of smoke (spheres that scale and cut off); hit flashes in white.

**Variations:** comic with halftone dots on shaded parts (dots from a screen pattern in `fragment`); western cartoon with rubbery shapes; anime with detailed skies against plain characters; ink wash in black and white with one colour.

**World:** simple, readable, bold shapes with a few big details. Toon makes dense textures look wrong, so paint big flat colours.
