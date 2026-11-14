# Card and deck-building games: effects as data, a hand on screen, and a run map

**Core:** a hand of options, not enough energy, and enemies who show what they intend. The decision is sequence and sacrifice, and between fights which card to add.

**Cards are data.** Effects are a list that one interpreter runs, so a hundred cards need no new code.
```gdscript
const CARDS := {
	"strike": {"cost": 1, "text": "Deal 6", "effects": [["damage", 6]]},
	"guard": {"cost": 1, "text": "Block 5", "effects": [["block", 5]]},
	"rush": {"cost": 0, "text": "Deal 3, draw 1", "effects": [["damage", 3], ["draw", 1]]},
}
```

**Piles:** draw, hand, discard, exhaust. On an empty draw pile, shuffle the discard in. Show the counts; let a tap see what is in each.

**Turn flow:** draw 5, energy 3, play cards, end turn, discard the hand, enemies act, then repeat. Run one effect at a time from a queue so that each animates in order and triggers can add to it.

**Enemies show an intent** such as "attacks for 12" or "will block". The fun is answering it. Give each enemy a short pattern with one twist, so it is learnable.

**Showing a hand on a phone:** a fan along the bottom. Each card is a Control, placed by a little maths on its index, and tapping lifts it. Text at least 2.2% of the screen's height (29 px in a game 1280 high), as the look check measures; show a big version while held. Drag up to play, or tap card then target.
```gdscript
func card_place(index: int, count: int, width: float) -> Vector2:
	var t := 0.5 if count == 1 else float(index) / (count - 1)
	return Vector2(lerpf(-width / 2.0, width / 2.0, t), 40.0 * pow(2.0 * t - 1.0, 2.0))
```

**The run:** a branching map of fights, elites, shops, rests and events. After a fight, choose one of three cards or skip: skipping must sometimes be right, since a thin deck is a strong deck. Start with about 10 plain cards.

**Balance by simulation:** with game logic separate from nodes, run a few hundred fights with a simple greedy player inside `exec`, and look at win rates for each card.

**Feel:** cards fly with easing, damage numbers punch out, a screen shake scaled to damage, a pitch rising as a combo grows.

**Make it yours.** Cards that are recipes, spells spoken as sentences, a deck that is a band's setlist, a hand you must keep all of or lose. Different card rules open the design: cards that change when placed next to each other; positions on a board; a hand played in real time.
