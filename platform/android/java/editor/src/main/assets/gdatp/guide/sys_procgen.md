# Generating content: seeds, noise, rooms, chunks, and checking that what is made can be played

**Generate from authored pieces first.** Pure randomness looks like noise. Hand-designed chunks, combined by rules, look designed and vary every time.

**Seed everything** with your own `RandomNumberGenerator`, so a bug can be reproduced by its seed, and a daily challenge costs nothing. Print the seed in the log.

**Noise for terrain and texture:**
```gdscript
extends Node

var noise := FastNoiseLite.new()


func _ready() -> void:
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 4


func height_at(x: float, y: float) -> float:
	var h := (noise.get_noise_2d(x, y) + 1.0) / 2.0
	return pow(h, 1.6) * 12.0
```
A power curve flattens valleys and sharpens peaks. Quantise it for terraces. `world3d_edit terrain` makes a mesh and collision from these same settings; `image_edit noise` makes a texture.

**Rooms and corridors:** pick room rectangles that do not overlap, sort by position, and join each to the next by an L-shaped corridor; add a few extra links so that it is not one long line. Mark the farthest room from the start as the goal, by a flood fill.

**Authored chunks:** levels written as text, each with the same entrance and exit height, chosen by difficulty. Only allow a chunk after one it can follow. This is how fair endless games are built.
```gdscript
const CHUNKS := [
	["........", "..##....", "########"],
	["........", "....^^..", "########"],
]
```

**Scatter by rule, not uniformly:** use Poisson-like spacing by rejecting points too near others; more trees where noise is high; none on slopes or paths. Clusters look natural, even grids do not. `world3d_edit scatter` does this.

**Grammars and stamps:** a town is a street, with houses along it, each house a small set of parts. Names too: join syllables from a list suited to the world.

**Always validate.** Generated content must be checked by code, not by hope:
- Is every required place reached by a flood fill or `AStarGrid2D`?
- Are obstacles within jump range? Compute from measured jump numbers.
- Is the difficulty within range: counts of hazards, gap sizes?
If a check fails, try the next seed, and log how many tries were needed.

**Tune by looking at many.** Generate 20, then screenshot, or print them as text and read them. Bad ones are usually a rule's fault. A model can check its own generator cheaply by printing the map as text in `logs`.

**Limit the scale:** a generated world larger than can be interesting becomes empty. Give it a purpose: rare landmarks placed first, then the generator fills in around them.

**On phones:** generate over several frames (`await get_tree().process_frame` every few hundred steps), or during a loading screen, to avoid a freeze.
