# Level and content design: teach, test, twist, pacing, landmarks, and a real difficulty curve

**Content is what separates a game from a demo.** A strong mechanic with one level is still a demo. Design levels on purpose, each with a job; never as the same thing again with bigger numbers.

**Teach, test, twist:** for each new idea: a safe place to try it; a real test with danger; a surprise combining it with an earlier idea. Then a new idea. Four ideas in this pattern make twelve good levels.

**Write the plan as a table in DESIGN.md before building:**
| Level | Job | New idea | What pressure |
| --- | --- | --- | --- |
| 1 | Teach the verb | moving | none |
| 2 | Test the verb | gaps | a timer you can beat easily |
| 3 | Twist | gaps that close | a chaser on the last part |

**Pacing:** tension then release. After a hard part, a quiet part with a reward or a view. A level's end should come slightly sooner than the player wants. Vary length. A boss or set piece per few levels, testing what was learned.

**Difficulty curve:** rising in steps with dips, rather than a straight ramp. Three lengths of game mean different budgets: a jam-sized game of 5 levels; a phone game of 20 short ones.

**Lead the eye.** Light, colour and shape say "go here": a lit doorway, an arrow of coins, a landmark visible from the start. Reward curiosity with a secret just out of the way. Players should never wonder where to go unless searching is the game.

**Landmarks in larger spaces:** something unique and visible from far (a tower, a huge tree), so that the player can navigate without a map. A loop back to the start, unlocked from the far side, makes a small place feel big.

**Make every space specific.** Replace "level 3" by "the flooded kitchen" or "the night market". A setting produces ideas for hazards and puzzles, and the player remembers it.

**Building it:** tile maps with `tilemap_edit`; text maps through your own loader; for 3D, CSG and parts through `world3d_edit` and `scene_edit`. Build the empty shape in plain colours, play through it, then dress it.

**Measure by playing:** walk it with `run step_until` and `input`, reading position and time with `game_read sample`. Can every gap be jumped? How long does a run take? A level that cannot be finished is the most embarrassing bug, and only playing finds it. Reach the end of each level before calling it done, or say plainly which ones you did not reach.

**Enemies, hazards and pickups** are placed like punctuation, for a reason. A spike exactly where a careless jump lands. A coin that teaches a jump's arc.

**Avoid:** long empty distance, pixel-perfect demands in the first level, unseen hazards killing the player without warning, difficulty that comes only from speed, content that repeats without a twist.

**When there is no time for more levels,** cut the count, not the care. Three good levels beat ten filler ones.
