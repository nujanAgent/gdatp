# One-bit and dither: two colours only, ordered dithering and stark readable worlds

**The rule:** every pixel is one of two colours. Shade only comes from patterns. It looks striking and hides simple modelling, which is valuable when art is made by code.

**Works on 3D too:** render anything, then a screen shader turns it to two colours with a Bayer matrix.

```glsl
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec4 dark = vec4(0.09, 0.08, 0.13, 1.0);
uniform vec4 light = vec4(0.91, 0.87, 0.75, 1.0);
uniform float cell = 2.0;
uniform float contrast = 1.2;

float bayer(ivec2 p) {
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return float(m[(p.x % 4) + (p.y % 4) * 4]) / 16.0;
}

void fragment() {
	ivec2 p = ivec2(FRAGCOORD.xy / cell);
	vec3 seen = texture(screen_texture, SCREEN_UV).rgb;
	float value = clamp((dot(seen, vec3(0.3, 0.59, 0.11)) - 0.5) * contrast + 0.5, 0.0, 1.0);
	COLOR = value > bayer(p) ? light : dark;
}
```
Put it on a full-screen `ColorRect` in a top `CanvasLayer`. Raise `cell` to 3 or 4 for chunkier pixels. For 3D, use simple grey materials with strong lighting, and let the shader do the rest.

**Choosing the two colours:** the pair sets the mood. Warm paper and dark ink is a book; green and black a terminal; amber and brown an old monitor; pink and deep blue is modern. Change the pair between areas for a strong sense of place.

**Readability is the danger.** Without colour, only value and shape remain:
- Characters and threats are solid and high-contrast against areas of dither pattern.
- Keep important things as plain light or plain dark, never dithered.
- Use outlines of the opposite colour around anything that crosses a busy background.
- Motion draws the eye: keep the background still.
- Give thin elements enough size: 2 big pixels at least.

**2D:** draw with `image_edit pixels` in two letters only; set `pixel_art` and the low resolution from `style_pixel`.

**3D:** an unlit world looks flat, so light with one strong directional light, and shape objects to catch it. Fog fades to the dark or the light colour. Models need only boxes and cylinders.

**UI:** text in a bitmap font, boxes with 1-pixel lines, invert colours on a press.

**Motion and effects:** inverting the entire screen for a frame on a hit is very strong in one-bit. Dissolve via the same dither pattern for transitions.

**What suits it:** detectives, ghost stories, old ships, dark comedy, sparse sci-fi. It gives games a confident identity at very little cost, and it stops any comparison with colourful art.
