# Fighting and wrestling games: frames, hitboxes, rounds, and reading an opponent

A fighter is a game of timing and reading, built on frame data. Without startup, recovery and hit reactions it is two things bumping.

**Each fighter is a state machine.** States: idle, walk, crouch, jump, attack, hitstun, blockstun, knockdown, getup. Input only starts something from a state that allows it. Run it in `_physics_process` at the fixed 60 ticks.

**Every attack has three phases, counted in ticks:**
| Move | Startup | Active | Recovery | Damage | Hitstun |
| --- | --- | --- | --- | --- | --- |
| Light | 4 | 2 | 8 | 5 | 12 |
| Medium | 8 | 3 | 14 | 10 | 16 |
| Heavy | 14 | 4 | 22 | 18 | 24, knockdown |
Keep moves as data, not code: a dictionary per move, read by one attack state.

**Hitboxes:** an `Area3D` or `Area2D` for the attack, on only during active ticks, and a hurtbox on each fighter. Mark who has been hit by this swing so one attack hits once. A hit gives: damage, hitstun, push back, 4 to 8 ticks of freeze on both fighters, a flash, a shake, a sound and sparks at the contact point.

**What gives it depth:**
- **Cancels:** light into medium into heavy, allowed only during the first few recovery ticks of a hit. That is a combo.
- **Spacing:** each move has a reach. Walking in and out of it is half the game.
- **Blocking:** holding back or a block button takes reduced damage and blockstun. Throws beat blocking; attacks beat throws.
- **Input buffer:** keep a press for 6 to 8 ticks, so a move pressed slightly early still comes out.

**Opponent:** react after a delay of 10 to 25 ticks by difficulty. Choose by distance: far walks or jumps in, mid pokes, close attacks or throws, and block on seeing an attack start with some chance. Add a little randomness so it can be read but not solved. Never let it read the player's input before it would be visible.

**Wrestling:** add a ring, ropes that throw a running fighter back, grapples started when close (a press chooses the throw), a stamina meter, a pin with a three count that the loser escapes by tapping fast, and crowd noise rising with momentum. Build big, readable animation, since weight is the appeal. Give fighters original names and looks.

**Camera:** frame both fighters: its centre between them, its distance from their gap, within limits. Two thirds of the screen is the fight.

**Touch:** a left stick or left and right buttons; on the right, punch, kick, block or grab, in reach of one thumb. Large, with a clear pressed look.

**Structure:** character select, best of three rounds, a timer, life bars that drain with a delay so damage reads, KO slow motion, then a next opponent or a win screen.

**For 3D fighters** build bodies with jointed parts (`sys_models3d`), so a move is rotations over ticks on arms and legs. Animate attacks by phase: wind up during startup, snap during active, ease back in recovery.
