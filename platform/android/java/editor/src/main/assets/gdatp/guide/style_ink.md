# Ink and sketch: hand-drawn lines that boil, brush black, comic panels on paper

**The idea:** the world looks drawn by hand a moment ago. Lines tremble, black is bold, and paper shows through. Often one or two inks only.

**Boiling lines:** redraw lines with small offsets at about 8 times a second. A canvas shader does this to any sprite:

```glsl
shader_type canvas_item;
uniform float amount = 1.6;
uniform float rate = 8.0;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	float tick = floor(TIME * rate);
	VERTEX += (vec2(noise(VERTEX * 0.01 + tick), noise(VERTEX * 0.013 - tick)) - 0.5) * amount;
}

void fragment() {
	float tick = floor(TIME * rate);
	vec2 wobble = (vec2(noise(UV * 13.0 + tick), noise(UV * 17.0 - tick)) - 0.5) * 0.004;
	COLOR = texture(TEXTURE, UV + wobble);
}
```

**Drawing it:** SVG strokes, with `stroke-linecap="round"`, drawn with deliberately imperfect paths and a pen width that varies: a brush line is a filled shape, not a stroke. Or use `Line2D` with a width curve, so ends taper. Use `_draw()` to draw hatching lines, for shade rather than a fill.

**Palette:** warm off-white paper (`#f2ead8`), near-black ink (`#1c1a17`), and at most one accent such as red or indigo. Red only for what kills you is a strong rule. Fill big shapes with black: dramatic blacks (in the style of woodcut or noir) beat many grey lines.

**Hatching for depth and shade:** lines close together for dark, far apart for light. Bold outlines near, thin grey ones far.

**Comic forms:** panels that slide in, speech balloons, sound words drawn as big letters at a hit ("KRAK"). Hits that burst with ink splats: a particle system with drop-shaped sprites and black colour, which stay on the ground as stains.

**Paper in the world:** a subtle paper texture over everything by a full-screen multiply layer, as well as smudges and pencil guidelines left visible.

**Characters** with very simple forms: stick figures with a personality, big heads, single-line limbs. Timing and pose do the work. Exaggerate strongly: a line character can stretch to twice its length.

**Motion:** a low animation rate of 8 to 12 poses a second; quick, inked smear lines for fast moves instead of motion blur.

**3D form:** inverted hull outlines in black (`style_toon3d`); a screen shader for hatching in dark zones (`style_onebit` shows how to read light); white surfaces. It looks like a moving architect's sketch.

**Variations:** Japanese brush in black with a red seal; children's crayon on lined paper; ballpoint on a school notebook; a scientist's field notebook with arrows and labels; chalk on a blackboard, with the colours inverted.
