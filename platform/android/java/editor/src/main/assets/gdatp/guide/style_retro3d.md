# Retro 3D: early console look with wobbling vertices, low resolution, chunky textures and fog

**The look comes from old hardware's limits:** low resolution, vertices that snap to a coarse grid, textures that warp, short sight lines hidden by fog. It is unsettling, charming, and forgiving of simple models.

**Low resolution:** run the 3D in a `SubViewportContainer` with `stretch` on and `stretch_shrink` set to 3 or 4, with nearest filtering. Put the UI outside it at full resolution, or also low, for a fuller effect.

**Vertex snapping and warping textures:**
```glsl
shader_type spatial;
render_mode unshaded, vertex_lighting, cull_back;
uniform sampler2D albedo : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform float snap = 160.0;
uniform float fog_near = 8.0;
uniform float fog_far = 40.0;
uniform vec4 fog_colour : source_color = vec4(0.1, 0.09, 0.14, 1.0);
varying float depth;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy = round(clip.xy / clip.w * snap) / snap * clip.w;
	POSITION = clip;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec3 seen = texture(albedo, UV).rgb * tint.rgb;
	float mist = clamp((depth - fog_near) / (fog_far - fog_near), 0.0, 1.0);
	ALBEDO = mix(seen, fog_colour.rgb, mist);
}
```
A lower `snap` wobbles more. Use a value of about 120 to 200.

**Textures:** small, 32 to 128 pixels square, with few colours, made by `image_edit pixels` or `image_edit pixelate` on fetched photos (`assets`, ambientCG). Tile them visibly. A photo crunched down and repeated gives the exact flavour of the era.

**Models:** fewer than 500 triangles a character; blocky with hard joints. Separate parts for limbs without any skinning, which matched the era and is simple to build: `sys_models3d`.

**Light:** baked by painting: vertex colours, or dark and light texture variants. A few lights only. Hard contrast between a pale fog and dark geometry, or a black void.

**Fog and draw distance:** the world dissolves very near the player; this is the mood. It also gives high frame rates on phones.

**Animation:** low frame rates of 8 to 15 per second, stepping on keys with no smoothing, and characters who turn on the spot.

**Camera and controls:** fixed camera angles, with cuts between rooms, is the classic survival-horror form, and also suits touch controls. Otherwise a stiff chase camera.

**UI:** chunky pixel fonts, a menu with blocky, colourful frames; a memory card-style save screen is a nice touch.

**Moods:** survival horror in a mansion; bright kids' mascot adventure with primary colours; a racing game on a grid; a surreal dreamlike walking game. Choose: retro alone is not a theme.
