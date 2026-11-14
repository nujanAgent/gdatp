# Running well on phones: renderers, budgets, pooling, and what to do when frames drop

**Choose the renderer at `project_create`:**
- **`compatibility`** (OpenGL ES 3): runs on every phone, the cheapest, and best for 2D. Fewer lighting features: no real glow on 2D, no volumetric fog, limited lights per object, and `parts sky` has no clouds or stars on it. Fake those (`style_neon`, `style_moody3d`).
- **`mobile`** (Vulkan): better lights and post effects, and what a 3D game should use. A phone without good Vulkan drivers falls back to compatibility by itself.
- **`forward_plus`**: desktop, avoid on phones.

Use `mobile` for 3D and `compatibility` for 2D. It is possible to change later, but the look will shift.

**Budgets for a middling phone at 60 frames a second, or 30 for 3D:**
| Thing | About |
| --- | --- |
| Draw calls (`game_read monitors`) | under 100 to 150 |
| 3D triangles in view | under 100,000 |
| Dynamic lights in view | 1 with shadow plus 2 to 4 without |
| Rigid bodies | 150 in 2D, 50 in 3D |
| Particles on screen | a few hundred |
| Textures | 1K or smaller, 2K only near the camera |

**Measure:** `game_read monitors` gives frame time and draw calls. Check on the slowest phone you can use. Look at the worst moments, like the most enemies at once, rather than the title screen.

**The cheap wins, in order:**
1. **Fewer draw calls:** `MultiMesh` for many copies; merged meshes for static scenery; shared materials; 2D sprites sharing one texture batch by themselves.
2. **Pool, do not allocate:** recycle bullets, particles and numbers. `instantiate` and `queue_free` many times a second stutters.
3. **Do less often:** run AI and paths a few times a second, staggered across enemies. Turn off `_process` for things out of view with `VisibleOnScreenNotifier`.
4. **Physics:** simple collision shapes rather than trimesh; layers and masks so that things only test what they need. Do not have thousands of `Area` overlaps.
5. **Shorter sight:** fog and doors let far objects be skipped. Use visibility ranges for distant detail.
6. **Render smaller:** `rendering/scaling_3d/scale` at 0.7 keeps the UI sharp while the 3D cost falls.
7. **Shadows:** a smaller shadow atlas or blob shadows on characters. Real-time shadows are often the single largest cost.

**Battery and heat:** phones throttle. A game running flat out at 120 fps gets slower after minutes. Cap with `Engine.max_fps = 60` or 30 in slow scenes; set `application/run/low_processor_mode` for puzzle and menu games, so that it draws only on change.

**Memory and space:** a very large texture costs much more once loaded than its file size suggests: 2048 by 2048 is 16 MB uncompressed. Prefer SVG or small tiles for 2D. Audio: music as Ogg or short WAV loops. First import takes time on a phone, so avoid huge asset packs: pick what you use and delete the rest.

**Screen sizes:** test portrait and landscape as chosen, with notch-safe margins: `DisplayServer.get_display_safe_area()`. Use `stretch mode canvas_items`, aspect `expand`, and anchor HUD elements to corners.

**Do not optimise blindly.** Measure, fix the largest, measure again.
