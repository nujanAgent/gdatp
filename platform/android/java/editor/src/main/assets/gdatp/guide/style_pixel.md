# Pixel art: a low-resolution world, limited palette, sharp scaling and small animation

`parts add paint` paints pixel surfaces in code, in your own colours.

**The settings make the look.** Create with `pixel_art: true`, or set the default texture filter to nearest. Then render small and scale up: with `project_edit`, set `display/window/size/viewport_width` and `height` to 320 by 180 (or 180 by 320 upright), `display/window/stretch/mode` to `viewport`, and `display/window/stretch/scale_mode` to `integer`. Also set `rendering/2d/snap/snap_2d_transforms_to_pixel` true. Everything including text then sits on the big pixel grid.

**Making sprites:** `image_edit pixels` writes a PNG from rows of letters and a palette, one letter per pixel, and is the way to draw exact pixels. `scale` stays 1 when the viewport is low resolution.

```
palette: {".": "transparent", "k": "#1a1c2c", "c": "#73eff7", "w": "#f4f4f4"}
rows:  "..kkkk..",
       ".kccwck.",
       ".kccckk.",
       "..kkkk.."
```

**Rules that make it look deliberate:**
- A fixed palette of 8 to 16 colours for the entire game. Well-known ones are a good start: dark blue-black as the outline, two ramps of hue that shift as they go lighter (toward warm yellow) and darker (toward cool purple), rather than simply adding white or black.
- Characters of 16 by 16 or 24 by 24; tiles of 16 by 16. Choose one size of pixel. Never scale a sprite by a fraction or rotate it smoothly, since mixed pixel sizes break the look.
- Read at thumbnail size: a clear silhouette first, details last. Outline with a dark colour, not pure black, or use none at all.
- Dither sparingly, for large gradients.

**Motion:** few frames are the style: 2 for idle, 4 for walk, 3 to 4 for an attack. `animation_edit` makes `SpriteFrames` from a sheet that `image_edit sheet` builds. Add a bob by moving a whole pixel at a time. Use stepped tweens rather than smooth rotation.

**Font:** a pixel font, placed by `assets`, or draw letters as sprites. With `viewport` stretch, normal fonts become blurry or jagged.

**Light without losing pixels:** colour swap instead of real lights: `CanvasModulate` for time of day; an extra lighter or darker palette for shade; flashes by swapping to white with a small shader.

**Backgrounds:** two or three parallax layers with fewer, darker colours, so the play layer stands out. A horizon gradient with stepped bands instead of a smooth one.

**Styles within pixel art, so that games differ:** Game Boy (4 greens or any 4 colours); 8-bit bright on black; 16-bit lush with many shades; 1-bit (`style_onebit`); isometric (`style_iso`). Pick one, name it in DESIGN.md, and stay inside its limits. The limits are the look.
