# Low-poly 3D: flat-shaded facets, palette materials, fog and warm light

**Definition:** few polygons, with facets shown, flat colour and no textures. Its success comes from light and palette more than from models.

**Flat shading:** visible facets need separate normals for each face. On a `StandardMaterial3D` set `shading_mode` per pixel with `disable_ambient_light` off and, for meshes built by code, generate with `SurfaceTool` without smoothing (`set_smooth_group(-1)`, then `generate_normals()`). The `world3d_edit` terrain, lathe and extrude shapes take `flat: true`. Sphere primitives can be reduced to a small `radial_segments` and `rings`, for chunky forms: 8 and 4 look deliberate.

**Materials are colours.** Keep a palette of 8 to 12 shared materials rather than one per object. Roughness at 1, metallic at 0. Only one or two emissive colours, for what matters.

**Light does the work:**
- A warm low sun (`#ffd9a0`) at a raking angle, with long shadows on the ground: never straight above.
- Cool ambient (`#5a6a9a`) so shade has a colour. Warm light against cool shade is what makes it attractive.
- Fog in a sky or horizon colour hides the world's edge, and separates layers: far things pale into it.
- `world3d_edit environment` sets all of this. In Compatibility, shadows cost a lot on old phones: use one directional light, and blob shadows on moving things if needed.

**Choose a mood:** dawn pastels; sunset orange and purple; blue night with warm windows; overcast and monochrome; autumn. An unchosen "default sunny day" is what makes low-poly look generic. So is a mid-green ground and light blue sky.

**Models:** build with `world3d_edit model` from parts (`sys_models3d`). A tree is a cylinder and three stacked cones, each a little offset and rotated; a rock a low sphere, squashed. Variation across copies in scale and rotation hides repetition (`world3d_edit scatter`). Exaggerate proportions: big heads, thick trunks, stubby fingers; realism looks wrong in this style.

**World:** terrain with terraces rather than smooth hills: quantise the height (`round(h * 6) / 6`), for steps. Water is a flat plane with a slightly animated vertex shader, and a pale band where it touches land.

**Camera:** a higher angle and narrower FOV (30 to 45) make it look like a diorama, and pair well with a tilted orthographic view. Wide angles look cheap.

**Details that lift it:** swaying grass and trees via a vertex shader (`sys_shaders`); particles such as leaves or fireflies; a few lit windows; slow clouds as blobs casting moving shadows.

**Avoid:** too many colours; thin, fiddly parts; smooth-shaded spheres beside flat-shaded objects; plain capsules for characters.
