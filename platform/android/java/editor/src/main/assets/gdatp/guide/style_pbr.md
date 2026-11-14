# Realistic materials: photo textures, sky from an HDRI, and real light on a phone's budget

**The look:** materials that respond to light like real ones. It relies on textures, a real sky and restraint. Fetch them with `assets` (`source: ambientcg` for materials, `source: polyhaven` for HDRIs, textures and models; all CC0).

**Material:** on a `StandardMaterial3D`, set the albedo, normal and roughness maps; add ambient occlusion if there is one. Use 1K textures on phones: 2K only for the things closest to the camera. `uv1_triplanar` textures terrain and level geometry without any UV work, which is excellent for CSG walls and generated ground:
```gdscript
func stone(albedo: Texture2D, normal: Texture2D, roughness: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo
	material.normal_enabled = true
	material.normal_texture = normal
	material.roughness_texture = roughness
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	return material
```

**Sky:** a `PanoramaSkyMaterial` from an HDRI in `WorldEnvironment`, for both the background and ambient light. Reflections and mood come along for free. Use a 1K HDRI on a phone; for most games it can be blurred with no loss.

**Renderer:** the Mobile renderer gives far better results, and needs Vulkan. Check `sys_performance` and test on the slowest phone you have. Set this at `project_create` time.

**Keep it real:**
- One sun plus the sky. A few local lights. Soft shadows at moderate resolution.
- Scale matters, since real materials betray wrong sizes: a door is 2 m, a brick about 20 cm; set `uv1_scale` accordingly.
- Dirt, wear and variation stop it looking like a demo: decals, a second material near the ground, darker corners.
- Avoid high-poly models: fetched models can have a hundred thousand triangles. Check a model's size before use, keep few of them in view, or use a low level of detail.

**Mix with the rest:** photo textures on simple shapes can look cheap if left at that. Either make the shapes convincing, or go somewhere stylised: real material on miniature, toy-like shapes with a shallow view is very attractive, and needs less detail.

**Water, glass, metal:** metal has a metallic of 1 and depends on reflections, so give it a sky; glass needs transparency and low roughness, and is costly; water is a plane with moving normal maps.

**Weight of the project:** textures take lots of space, and the first import of many takes a long time on a phone. Fetch only what is used, at 1K, then look at file size with `projects` and download nothing further.

**Credit:** CC0 needs none, but `assets` writes a `res://assets/CREDITS.md`, and a line on a credits screen is good manners.
