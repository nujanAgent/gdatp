# Strategy, management and idle games: economies, placement, time and interfaces on a phone

**These are interface games.** The fun lives in reading numbers and making plans, so the interface comes first, before art.

**Separate the simulation from what shows it.** Keep state in plain objects and tick them on a `Timer`, say 4 times a second, not every frame. Nodes only show it. This allows fast-forward, saving, and thousands of things on a phone.

```gdscript
extends Node

signal changed
var stock := {"wood": 20.0, "food": 10.0}
var buildings: Array[Dictionary] = []


func tick(seconds: float) -> void:
	for building in buildings:
		var needs: Dictionary = building.get("needs", {})
		var can_run := true
		for item in needs:
			if stock.get(item, 0.0) < needs[item] * seconds:
				can_run = false
		if not can_run:
			continue
		for item in needs:
			stock[item] -= needs[item] * seconds
		var makes: Dictionary = building.get("makes", {})
		for item in makes:
			stock[item] = stock.get(item, 0.0) + makes[item] * seconds
	changed.emit()
```

**Economy:** chains where one thing feeds the next, so bottlenecks move and the player keeps solving them. Every purchase should raise a new question. Show rates as well as totals (+3.2 a second), and show why something has stopped.

**Placement:** a grid, a preview that shows valid or not, adjacency that matters (a mill next to a farm earns more). Build by tapping a tool, then the ground, without dragging precisely. Pinch to zoom and drag to pan: `sys_touch` has both.

**Real-time strategy on touch:** tap a unit and tap a target; a drag draws a selection box; few units with strong identities; rock, paper and scissors between kinds. Or make it turn-based on a grid or hexes, which suits a phone better: show the move range and the expected damage before committing.

**Time:** pause, 1x, 3x. Events give texture: a storm, a visitor, a choice between two costs. An adviser or a one-line log says what is going on.

**Idle games:** numbers grow while away: save the time and pay out on return, capped. Costs rise about 1.15 times each purchase, while income grows in steps from multipliers. Each new layer changes what the numbers mean.

**Goals:** without them a sandbox fades. Give a clear aim for each stage: feed 50 people; survive winter; reach the coast. End each map with a result.

**Teach by doing:** start with one building and one need, and unlock the next as it becomes useful, with no text wall.

**Save everything,** every minute and on pausing the app, since people return to these (`sys_save`).

**Make it yours.** Running a lighthouse network. A monster's lair with staff problems. A bee colony. A city that grows on the back of a walking giant. Planning a single perfect day.
