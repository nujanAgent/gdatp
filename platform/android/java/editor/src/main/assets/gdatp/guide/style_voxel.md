# Voxel: worlds and characters built of cubes, generated, merged and lit with fake shade

`parts add voxel_world voxel_player sky touch` gives a working world of blocks with textures, shading, threads and editing. Shape it with its `terrain`, `height_at` and `block_for`, and add blocks with `voxel_blocks`. Make the project with renderer `mobile`, which runs a world of them at 60 fps on a current phone and gives `sky` its clouds and stars.

**Why it suits generated games:** a single simple rule makes everything consistent, and a model can describe a building as data. Destructible worlds are possible.

**Do not make one node per cube.** Past a few hundred, this kills a phone. For many of one cube use a `MultiMeshInstance3D`; for a world, build a mesh, showing only faces that touch air.

```gdscript
extends MeshInstance3D

const FACES := {
	Vector3i.UP: [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	Vector3i.DOWN: [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)],
	Vector3i.LEFT: [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)],
	Vector3i.RIGHT: [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	Vector3i.FORWARD: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	Vector3i.BACK: [Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)],
}


## blocks maps each Vector3i to its Color.
func build(blocks: Dictionary) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for at: Vector3i in blocks:
		for side: Vector3i in FACES:
			if blocks.has(at + side):
				continue
			var corners: Array = FACES[side]
			var shade := 1.0 if side == Vector3i.UP else (0.55 if side == Vector3i.DOWN else 0.78)
			tool.set_color(Color(blocks[at]) * Color(shade, shade, shade))
			for index in [0, 1, 2, 0, 2, 3]:
				tool.add_vertex(Vector3(at) + corners[index])
	tool.generate_normals()
	mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material_override = material
```
Faces wind so that they show from outside; if your world looks inside out, reverse the index order. Split big worlds into chunks of 16 cubes and rebuild only the chunk that changed. Give each chunk a `ConcavePolygonShape3D` from the mesh (`create_trimesh_shape`).

**Generating:** layered noise for height (`FastNoiseLite`); colour by height and slope (grass, stone, snow); caves by a 3D noise threshold; trees as small stamps.

**Shade makes cubes attractive:** the fixed per-face shade above is a cheap fake of sunlight. Add a darker colour for voxels with neighbours above (fake ambient occlusion). A warm directional light on top. A palette as tight as pixel art's: 16 to 32 colours.

**Characters:** written as layers of letters, like pixel art in slices, or a few box parts jointed with `world3d_edit model` so that they can animate.

**Small voxels vs large:** large cubes (1 unit against a 2-unit character) read as building blocks; small ones (0.1 unit) as detailed models. Keep one voxel size across the world.

**Fit for touch:** tapping a block removes it; hold to place. Show the selected face with an outline.

**Avoid looking like the famous block game:** choose a different palette and light, a limited, authored world, and rules of your own. A voxel city under water, tiny villages on a flying turtle, or a destructible castle siege.
