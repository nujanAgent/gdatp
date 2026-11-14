# 3D models without a modelling app: bodies from parts, jointed animation, props, and imports

A capsule with a face is a placeholder. A body with shoulders, hips, hands, a costume and proportions that suit the game takes minutes.

**`world3d_edit` op `model`** builds a saved scene from a list of parts. Each part has a shape, a size, a place, a colour and optionally a `parent` and a `pivot`, the point it turns about:
```json
{"op": "model", "params": {"save": "res://models/wrestler.tscn", "parts": [
  {"name": "hips", "shape": "box", "size": [0.5, 0.3, 0.3], "at": [0, 1.0, 0], "color": "#2b3a67"},
  {"name": "chest", "parent": "hips", "shape": "capsule", "size": [0.38, 0.8], "at": [0, 0.5, 0], "color": "#d9a066"},
  {"name": "head", "parent": "chest", "shape": "sphere", "size": [0.3], "at": [0, 0.55, 0], "color": "#d9a066"},
  {"name": "mask", "parent": "head", "shape": "sphere", "size": [0.31], "at": [0, 0.02, 0], "scale": [1, 0.55, 1], "color": "#c1272d"},
  {"name": "arm_l", "parent": "chest", "shape": "capsule", "size": [0.13, 0.7], "at": [-0.5, 0.2, 0], "pivot": [0, 0.3, 0], "color": "#d9a066"},
  {"name": "arm_r", "parent": "chest", "shape": "capsule", "size": [0.13, 0.7], "at": [0.5, 0.2, 0], "pivot": [0, 0.3, 0], "color": "#d9a066"},
  {"name": "leg_l", "parent": "hips", "shape": "capsule", "size": [0.16, 0.9], "at": [-0.15, -0.5, 0], "pivot": [0, 0.4, 0], "color": "#2b3a67"},
  {"name": "leg_r", "parent": "hips", "shape": "capsule", "size": [0.16, 0.9], "at": [0.15, -0.5, 0], "pivot": [0, 0.4, 0], "color": "#2b3a67"}
]}}
```
Shapes: box `[x,y,z]`; sphere `[radius]`; capsule and cylinder `[radius, height]`; cone `[radius, height]`; torus `[inner, outer]`; `lathe` spins a `profile` of `[radius, height]` points (bottles, lamps, hats, vases, tree trunks); `extrude` thickens an `outline` of `[x, y]` points by `depth` (signs, swords, cut-outs, roofs). Materials per part: `color`, `metallic`, `roughness`, `emission`, `unshaded`, `flat`. `body` on the root (`static`, `area`, `character`) adds a matching collision box.

**Proportions set the character, more than detail does:** a heroic adult is about 7 heads tall; chibi 2 to 3; a scary giant has long arms and a small head; a child has a big head, short limbs and a big coat. Exaggerate. Silhouette test: all one colour, can you tell who it is, and which way they face? Add one or two strong details: a cape, a hat, a mask, a huge weapon, a tail, or a glowing eye.

**Animating jointed bodies:** rotate parts about their pivots. A part with a `pivot` is a `Node3D` joint holding the mesh, so its rotation swings from that point.

```gdscript
extends Node3D

@export var stride := 0.7
@onready var arm_l: Node3D = $hips/chest/arm_l
@onready var arm_r: Node3D = $hips/chest/arm_r
@onready var leg_l: Node3D = $hips/leg_l
@onready var leg_r: Node3D = $hips/leg_r
var _phase := 0.0


func walk(delta: float, speed: float) -> void:
	_phase += delta * speed * 2.0
	var swing := sin(_phase) * stride * clampf(speed, 0.0, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = -swing * 0.7
	arm_r.rotation.x = swing * 0.7
	$hips.position.y = 1.0 + absf(cos(_phase)) * 0.04
```
For attacks, tween joints quickly: `create_tween().tween_property(arm_r, "rotation:x", -2.2, 0.08)`, then ease back slowly. An `AnimationPlayer` from `animation_edit` can key joints too. Lean the body into motion; squash on landing by scaling the root.

**Props:** a lamp from a lathe plus an emissive sphere; a table from 5 boxes; a tree from a cylinder and stacked cones or squashed spheres; a house from boxes with an extruded roof; a car from boxes, with cylinders as wheels. Compose bigger scenes from these with `scene_edit`.

**Many copies** merge for speed: `merge: true` joins parts with no joints into one mesh; `world3d_edit scatter` places hundreds as one `MultiMesh`.

**Real models:** `assets` fetches CC0 glTF. Skeleton animations in a `.glb` arrive in an `AnimationPlayer`. Check triangle counts (`sys_performance`): photo-scanned models can be too heavy.

**Check placement with `scene_read spatial`,** which gives sizes and what floats or overlaps. Feet should touch the ground: the model's root at its feet makes everything simpler. Facing: Godot's front is negative Z, so build characters facing -Z.
