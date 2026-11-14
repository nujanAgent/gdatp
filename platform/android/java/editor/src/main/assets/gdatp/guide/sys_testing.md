# Testing a game with these tools: playing it for real, reading state, and not going in circles

**Play it, do not reason about it.** `run play`, `logs since_last`, then act through `input` with real presses, and read back with `game_read`. Report only what you actually reached.

**Check each change with the smallest thing that can show it:**
- A script compiles: `script_edit` says so, with the line.
- It runs: `run play`, then `logs since_last`.
- It looks right: `screenshot target game`. Look at it rather than assuming.
- It behaves: `game_read sample` of a value over frames while `run step` holds an action, such as jump height or enemy distance.
- Controls work: `input touch` or `tap` on a control's node path. Use `game_read ui` for rectangles.

**Do not go in circles.** If a read returns nothing or the same as last time, asking again the same way will not change it.
- `game_read find` empty: read its `note`, then `game_read tree` to see what is really there. The running scene may be the title or end screen, not the level. Filters narrow together: `text` applies only to nodes showing text.
- The same value twice: the game may be paused, may have ended, or may never have reached this code. Check `run state` and `logs`.
- A node is missing: scenes change; paths in a running game differ from the editor's when a scene is instanced in code.
- Stuck on one bug for three tries: stop, print the state (`print` in the script, then `logs`), and find out what is true before changing anything further.

**Get to any state quickly:** `game_edit` sets values, calls methods and changes scenes without changing files: jump to the last level, give the player one life left, spawn the boss. Then play the real end with `input`.

**Playing through:**
- Win and lose both reached with real play at least once, as well as the way back: restart and a second run.
- Each level finished, or named as not finished.
- For a jump, a shot, a dodge: can the player really do what the level demands? Measure.
- Touch: all controls reached by touch rather than keys.

**Look at it like a stranger:** after each big step, take a screenshot and ask: what am I supposed to do; can I read everything; can I find the player at once; does it look like what the plan says; would I think someone made this on purpose; does it look like the previous game? Compare with what you studied (`study`).

**Reset before final checks:** delete saves, stop the game, start clean with `run play`, and play from the title.

**When you report:** say what you played through and what you did not; say that you cannot hear sound if that is so; name what you would do next. Do not call it complete if a level or an ending was not reached.

**Errors in the log are not optional.** Fix each before moving on. A script's warnings come back apart, under `warnings`: the game runs on, so they wait until the game works. They are nearly always small, but pile up quickly.
