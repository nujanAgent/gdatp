# Paper and hand-made: cut-out layers, stop motion, soft shadows, craft textures

**The idea:** the world looks physically made from card, cloth or clay, shot on a table. Imperfection sells it.

**Layers with real depth:** several parallax layers with soft drop shadows beneath each, giving the impression of stacked sheets. Draw a shadow as a dark, blurred, offset copy of each shape (in SVG add a duplicate with `filter`, or a second `Sprite2D` tinted black at low alpha, offset down and to the right).

**Stop motion is the key trick.** Animate at 8 to 12 poses a second rather than smoothly. Step the position and rotation, and swap between two or three drawn variants of a sprite even when still ("boil").

```gdscript
extends Sprite2D

@export var frames_per_second := 10.0
@export var jitter := 1.5
var _rest := Vector2.ZERO
var _clock := 0.0


func _ready() -> void:
	_rest = position


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 1.0 / frames_per_second:
		return
	_clock = 0.0
	position = _rest + Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
	rotation = randf_range(-0.012, 0.012)
```

**Texture over everything:** a paper grain from `image_edit noise`, on a full-screen multiply layer or as part of each sprite. Slightly uneven edges in shapes; SVG paths with small wobbles instead of perfect curves. Visible tabs, staples, string or sticks for things that move like puppets.

**Colour:** muted, like real card: ochre, faded teal, dusty red, kraft brown, off-white rather than pure white. Nothing at full saturation. Warm light from one side.

**Movement like a puppet:** limbs pinned at joints, rotating around pins (`Node2D` pivots with a `Sprite2D` child offset), with little overlap. Things enter by sliding in from off stage, or folding up like a pop-up book, using a tween on `scale.y` from 0 with a bounce.

**A stage:** treat the screen as a theatre or a shoebox: painted backdrop, scenery slid on, a floor line. Transitions as curtains or pages turning (`sys_flow`).

**3D form:** thin box or plane meshes with a card texture, flat colour and low roughness; a strong directional light casting soft shadows onto what is behind; the camera shifting slightly for parallax, so that shapes reveal their flatness. A diorama box round the whole level.

**Other materials to try, in the same way:** felt with fuzzy edges; clay with fingerprint noise; knitted squares for pixels; watercolour with bleeding edges and paper showing through; linocut with two colours and carved lines.

**Sound completes it:** rustles, taps, paper slides, a soft pluck, wood knocks, rather than electronic beeps.
