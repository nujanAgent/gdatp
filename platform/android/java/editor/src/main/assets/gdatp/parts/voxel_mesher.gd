extends RefCounted
## Turns one chunk's blocks into meshes for parts/voxel_world.gd, which calls it: only faces something can see, corners darkened
## where blocks meet, and see-through blocks on their own surface. Runs on a worker thread and touches nothing shared.

const Blocks := preload("res://parts/voxel_blocks.gd")

const SIZE := 16
const HEIGHT := 64
const PAD_XZ := SIZE + 2
const PAD_LAYER := PAD_XZ * PAD_XZ

## Shade on each face, so the shape of the land reads whatever the light is doing: +X, -X, top, bottom, +Z, -Z.
const FACE_SHADE := [0.80, 0.80, 1.0, 0.62, 0.90, 0.90]
## How dark a corner is by how many blocks crowd it.
const AO_LEVEL := [0.42, 0.62, 0.82, 1.0]
const UV_INSET := 0.0015

static var _faces: Array = _build_faces()


## For each face: its normal, the block's neighbour offset in the padded array, and for each corner its position, its
## texture coordinate, and the offsets of the two sides and the corner block that crowd it.
static func _build_faces() -> Array:
	var frames := [
		[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), "vu"],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), "uv"],
		[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0), "flat"],
		[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), "flat"],
		[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), "uv"],
		[Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), "vu"],
	]
	var faces := []
	for frame in frames:
		var n: Vector3i = frame[0]
		var u: Vector3i = frame[1]
		var v: Vector3i = frame[2]
		var corners := []
		for sign_pair in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var su: int = sign_pair[0]
			var sv: int = sign_pair[1]
			var place := Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5 + Vector3(u) * 0.5 * su + Vector3(v) * 0.5 * sv
			var a := (su + 1) * 0.5
			var b := (sv + 1) * 0.5
			var uv := Vector2(a, b)
			match frame[3]:
				"uv":
					uv = Vector2(a, 1.0 - b)
				"vu":
					uv = Vector2(b, 1.0 - a)
			corners.append({
				"position": place,
				"uv": uv,
				"side_a": _offset(n + u * su),
				"side_b": _offset(n + v * sv),
				"corner": _offset(n + u * su + v * sv),
			})
		faces.append({"normal": Vector3(n), "neighbour": _offset(n), "corners": corners})
	return faces


static func _offset(d: Vector3i) -> int:
	return d.x + d.z * PAD_XZ + d.y * PAD_LAYER


## The arrays for a chunk's solid surface and its see-through surface, either null when it has none. [param tiles] holds each
## block's atlas tiles for top, side and bottom, and [param columns] and [param rows] the atlas's shape.
static func build(data: PackedByteArray, x_minus: PackedByteArray, x_plus: PackedByteArray, z_minus: PackedByteArray, z_plus: PackedByteArray, tiles: Array, columns: int, rows: int) -> Array:
	var padded := _pad(data, x_minus, x_plus, z_minus, z_plus)
	var solid := _Surface.new()
	var clear := _Surface.new()
	var occludes: Array = Blocks.OPAQUE
	var see_through: Array = Blocks.CLEAR
	var tile_w := 1.0 / columns
	var tile_h := 1.0 / rows
	for y in HEIGHT:
		for z in SIZE:
			var i := 1 + (z + 1) * PAD_XZ + (y + 1) * PAD_LAYER
			for x in SIZE:
				var id: int = padded[i]
				if id != Blocks.AIR:
					for f in 6:
						var face: Dictionary = _faces[f]
						var next: int = padded[i + int(face.neighbour)]
						if occludes[next] == 1 or next == id:
							continue
						var faces_of: Array = tiles[id]
						var tile: int = faces_of[0] if f == 2 else (faces_of[2] if f == 3 else faces_of[1])
						var target := clear if see_through[id] == 1 else solid
						var lowered := id == Blocks.WATER and padded[i + PAD_LAYER] != Blocks.WATER
						_add_face(target, face, f, Vector3(x, y, z), i, padded, occludes, tile, columns, tile_w, tile_h, lowered)
				i += 1
	return [solid.arrays(), clear.arrays()]


static func _add_face(s: _Surface, face: Dictionary, f: int, at: Vector3, i: int, padded: PackedByteArray, occludes: Array, tile: int, columns: int, tile_w: float, tile_h: float, lowered: bool) -> void:
	var origin_uv := Vector2((tile % columns) * tile_w, floori(float(tile) / columns) * tile_h)
	var base := s.vertices.size()
	var shade: float = FACE_SHADE[f]
	var levels := [0, 0, 0, 0]
	var corners: Array = face.corners
	var normal: Vector3 = face.normal
	for c in 4:
		var corner: Dictionary = corners[c]
		var side_a: int = occludes[padded[i + int(corner.side_a)]]
		var side_b: int = occludes[padded[i + int(corner.side_b)]]
		var diagonal: int = occludes[padded[i + int(corner.corner)]]
		var level := 0 if (side_a == 1 and side_b == 1) else 3 - (side_a + side_b + diagonal)
		levels[c] = level
		var place: Vector3 = at + (corner.position as Vector3)
		if lowered and place.y > at.y + 0.5:
			place.y -= 0.12
		var uv: Vector2 = corner.uv
		s.vertices.append(place)
		s.normals.append(normal)
		s.uvs.append(origin_uv + Vector2(
			clampf(uv.x, UV_INSET, 1.0 - UV_INSET) * tile_w,
			clampf(uv.y, UV_INSET, 1.0 - UV_INSET) * tile_h))
		var light: float = shade * float(AO_LEVEL[level])
		s.colors.append(Color(light, light, light))
	# Cut the quad along the brighter diagonal, or the shading on it creases.
	if levels[0] + levels[2] >= levels[1] + levels[3]:
		s.add_triangles(base, 0, 2, 1, 0, 3, 2)
	else:
		s.add_triangles(base, 1, 0, 3, 1, 3, 2)


## The chunk with one block of each neighbour around it, so a look across a border needs no lookup. An absent neighbour reads as air.
static func _pad(data: PackedByteArray, x_minus: PackedByteArray, x_plus: PackedByteArray, z_minus: PackedByteArray, z_plus: PackedByteArray) -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(PAD_LAYER * (HEIGHT + 2))
	for y in HEIGHT:
		var layer := (y + 1) * PAD_LAYER
		var from := y * SIZE * SIZE
		for z in SIZE:
			var row := layer + (z + 1) * PAD_XZ
			var read := from + z * SIZE
			for x in SIZE:
				padded[row + 1 + x] = data[read + x]
			if not x_minus.is_empty():
				padded[row] = x_minus[read + SIZE - 1]
			if not x_plus.is_empty():
				padded[row + SIZE + 1] = x_plus[read]
		if not z_minus.is_empty():
			for x in SIZE:
				padded[layer + 1 + x] = z_minus[from + (SIZE - 1) * SIZE + x]
		if not z_plus.is_empty():
			for x in SIZE:
				padded[layer + (SIZE + 1) * PAD_XZ + 1 + x] = z_plus[from + x]
	return padded


class _Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add_triangles(base: int, a: int, b: int, c: int, d: int, e: int, f: int) -> void:
		indices.append(base + a)
		indices.append(base + b)
		indices.append(base + c)
		indices.append(base + d)
		indices.append(base + e)
		indices.append(base + f)

	func arrays() -> Variant:
		if vertices.is_empty():
			return null
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = vertices
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_TEX_UV] = uvs
		out[Mesh.ARRAY_COLOR] = colors
		out[Mesh.ARRAY_INDEX] = indices
		return out
