# Puzzle games: grid logic, match games, physics puzzles, and designing levels with an aha

**Keep the rules in plain data, and let nodes only show them.** The state is an array; a move changes the array; pieces animate to match. This gives you undo, solving checks and level testing for almost nothing.

```gdscript
extends Node2D

const WIDTH := 6
var cells := PackedInt32Array()
var history: Array[PackedInt32Array] = []


func at(x: int, y: int) -> int:
	return cells[y * WIDTH + x]


func set_at(x: int, y: int, value: int) -> void:
	history.append(cells.duplicate())
	cells[y * WIDTH + x] = value


func undo() -> void:
	if not history.is_empty():
		cells = history.pop_back()
```

**Moves animate in a queue.** Apply the rule at once, then play tweens in order and ignore input until they finish. Cascades read clearly when each step gets about 0.15 s.

**Kinds, and what each needs:**
- **Push and block (Sokoban style):** cells for wall, floor, goal, crate; full undo; a move count. Small boards with few pieces are the hardest and best.
- **Match games:** swap neighbours; find runs of 3 or more; clear, drop, refill, repeat. Refuse a swap that matches nothing, shake to say so, and reshuffle when no move remains. Give each cascade rising pitch.
- **Logic (nonogram, minesweeper, sudoku style):** generate from a solved state; check that a solver needs no guessing.
- **Flow and connection:** the player draws; the check is a flood fill.
- **Physics puzzles:** see `genre_physics`.
- **Spatial 3D:** rotate a small diorama to find a path; a fixed set of camera angles is enough.

**Designing a good level:**
1. Find one insight, such as "you must move this crate away in order to bring it back".
2. Build the smallest board where only that insight solves it.
3. Remove everything that does not serve it.
4. Solve it yourself by running moves through the tools, and check a wrong first move is possible.
Each new mechanic gets a first level with almost nothing to do but discover it, then two that use it, then one that surprises with it.

**Generate and verify:** for endless puzzles, make levels by playing backwards from the solved state, or generate and keep those a small search proves solvable. Never give an unsolvable level, nor one already solved as it opens: a search that proves a level can be solved does not prove there is anything to do in it, so have it report the fewest moves as well, and keep only levels that need the moves they are meant to.

**Respect the player:** no timer unless time is the idea; instant restart and unlimited undo; a level select that shows progress; a hint that grows gradually; a satisfying moment on solving, such as everything lighting up in sequence.

**Touch:** tap or swipe at thumb reach; boards in the upper part of an upright screen; pieces at least 64 px.

**Make it yours.** A rule with a feeling attached: untangling headphones, sorting a tiny post office, closing a suitcase, lighting a town. A theme that changes how the rule is understood is worth more than more mechanics.
