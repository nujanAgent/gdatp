# Start here: the order of work that gives a game its own idea and look

A project here starts empty on purpose. There are no game templates, because a game that starts as a copy stays one: a wrestling game built from an island hopper still has an island hopper's bones. What every game needs is ready as `parts`, tested on phones: touch controls, title and pause screens, sound, music, a sky, painted textures, hero controllers, tile levels, a voxel world. They hold no game. You write what they do not: this game's rules, goals, enemies, levels and look, and these topics teach how.

1. **Check what exists.** `projects` lists earlier games with their pitch and look. A new game differs from them in its verb and its look, unless a sequel was asked for. A request to make a game means a new project, even when one has a similar name: open an earlier one only when asked to change it.
2. **Idea.** Read `ideas` unless the person gave a full one. What the person asked for is the brief: a fighting game is a fighting game, never another genre in costume.
3. **Study.** Read `study`, and look at real examples of any game, genre or style that was named. Never skip this when the person said "like X" or "reference X". Keep the pictures you learned from with `assets` `fetch`, `url` and `into: study`: each run of the game asks for them.
4. **Read the topics this game needs:** its genre (`genre_*`), its look (`style_*`), and the systems it uses (`sys_*`). If no genre fits, read the two closest and combine them.
5. **Write `res://DESIGN.md`:** pitch, core verb and its decision, the one thing only this game has, what you studied and took from it, win and lose, content, look with palette, sound, controls. Later games read it, so keep those words as line starts: `Pitch:`, `Core verb:`, `The one thing:`, `Look:`.
6. **`project_create`** with the renderer the look needs (`sys_performance`). It places the parts nearly every game needs, and says how to wire each in; `parts list` shows the rest, and `parts add` places them. The window grows to fit a phone of any shape, so lay everything out from `get_viewport_rect().size`, never from a number of your own: a background sized in pixels leaves bars of bare grey on a phone.
7. **Build the core verb first,** by touch, on the parts. Run it and play it with `input`. If ten seconds of it is dull, change the verb now. Everything after this costs more to change.
8. **Then the end of a run, then the way in and back** (`sys_flow`). Now it is a game, however small.
9. **Then the look.** Apply the style to everything at once rather than to one sprite at a time.
10. **Then content and feel,** one thing at a time, playing after each (`sys_levels`, `sys_juice`, `sys_audio`).
11. **Before reporting,** read `sys_testing` and do what it says: reach a real end, take a screenshot, and compare it honestly with what you studied.
12. **When it is finished and the person wants it,** `export` makes an APK they can install and share.

A game of real size is many files. Keep each script about one thing, write each one whole in a single call, and decide the file layout in DESIGN.md before the second script.

What makes a game feel made rather than generated: one clear idea pushed further than expected; a look applied to everything; levels or waves that were designed rather than repeated; a reaction to everything the player does; and leaving out whatever does not serve the idea.
