# One-touch arcade games: runners, stackers, timing games, built for a thirty second run

**Promise:** understood in one second, a run lasts under a minute, one tap to go again, and a best score to beat. The whole game is one verb tuned very finely.

**Find the tension in one input.** Hold to rise and release to fall. Tap to switch lanes. Tap to stop the moving block. Hold to charge and release to leap. "Tap at the right moment" is improved by a risk: closer to the edge scores more.

**Speed curve:** start slow enough to learn; raise speed smoothly toward a cap. `speed = lerpf(start, top, 1.0 - exp(-seconds / 45.0))`.

**Fair generation:** build from short authored chunks rather than pure random, and choose chunks by current speed. Every obstacle must be reachable: compute reaction time. At speed `v`, obstacles closer than `v * 0.35 s` are not fair. Never spawn in view.

**Pools rather than creating nodes:** a list of obstacles recycled as they leave the screen, since allocating during play stutters on phones.

**Rewards near misses.** Pass close for bonus points with a sound and a flash. Multipliers that grow while nothing is hit and drop when something is. This turns surviving into risking.

**The moment of death is the game's advert:** a short slow motion, a burst, the score counting up, "new best" if earned, and restart within half a second of a tap. No menus between runs.

```gdscript
extends Node

const SAVE := "user://best.cfg"
var best := 0


func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE) == OK:
		best = int(file.get_value("score", "best", 0))


func finish(score: int) -> bool:
	if score <= best:
		return false
	best = score
	var file := ConfigFile.new()
	file.set_value("score", "best", best)
	file.save(SAVE)
	return true
```

**Long-term pull without bloat:** unlockable looks earned by play, daily seeded runs, and milestones the world reacts to (dusk at 500, a storm at 1000): the backdrop changing as score rises makes a run feel like a journey.

**Touch:** the whole screen is the button. No on-screen control unless two are needed, one under each thumb.

**Portrait** suits most of these: falling or climbing suits a tall screen better than running right does. Try up, down, or around a circle before choosing sideways.

**Make it yours.** The input is simple, so everything is in the fiction and the shape: a ferry dodging ice, a bee between flowers, a tongue catching flies, a sign spinner on a crowded street.
