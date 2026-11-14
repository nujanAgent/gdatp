# Vector and flat design: clean shapes in SVG, strong composition and a chosen shape language

**How:** write SVG with `files_edit` into `res://art/`; Godot imports it as a texture at the size written, so draw at the size used. Or draw at runtime with `Polygon2D`, `Line2D` and `_draw()`, which stay crisp when scaled.

**Choose a shape language. It carries the mood before anything else:**
- **Round and soft:** friendly, cute, safe. Big heads, no corners.
- **Sharp and angular:** danger, speed, aggression. Triangles, slanted lines.
- **Square and heavy:** solid, stubborn, mechanical.
- **Long and thin:** eerie, elegant, fragile.
Heroes and enemies should differ in shape, not only in colour.

**Beyond three flat colours and an outline, which every model reaches for first:**
- **Limited palette plus one accent:** two near-neutrals and one loud colour that only ever means "this matters".
- **Gradient flat:** large soft gradients in the backdrop with flat objects on top.
- **No outlines at all:** shapes separated only by value, with a shaded side made of a darker second shape.
- **Geometric abstraction:** everything built from circles and bars, like a modernist poster.
- **Long shadows, cut paper, isometric shapes, or a single line drawing:** see `style_paper`, `style_iso`, `style_ink`.

**SVG example:** a shape with a shaded side and no outline.
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
  <circle cx="64" cy="64" r="56" fill="#ffb84d"/>
  <path d="M64 8 a56 56 0 0 1 0 112 a72 72 0 0 0 0 -112" fill="#f28f3b"/>
  <circle cx="84" cy="52" r="9" fill="#2b2d42"/>
</svg>
```

**Composition counts for more than detail:** large, medium and small shapes on screen; lots of empty space; the player the brightest thing; the backdrop much lower in contrast. Check your screenshot at a small size: can you tell what matters?

**Motion** gives flat art its life, since there are no textures to look at: squash and stretch, overshoot in tweens (`Tween.TRANS_BACK`), small secondary motion like a tail or an antenna lagging behind, things that pop in rather than appear.

**Depth:** parallax in 3 layers; distant ones pale and close to the sky's colour; a soft shadow ellipse below objects.

**Texture:** a faint noise or grain over everything (`sys_shaders`), which removes the "default vector" feel cheaply.

**Text:** a font with a personality, placed with `assets`. It affects the whole impression. Don't leave Godot's default for the title.
