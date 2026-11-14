# Studying a game, a genre or a visual style before building it

When a game, an era or a style is named, what you remember of it is not enough: look at it. This is what separates "like X" from "X with the name changed". Use whatever tools the host gives you for the web and for looking at pictures and videos: search, read a page, open images, watch gameplay.

**Look for:**
- **Pictures:** several screenshots from different moments, not just the box art. Screenshots of the game in play matter most.
- **How it plays:** a review, a guide, a wiki's page on its mechanics, a developer's talk or post-mortem.
- **Video:** gameplay shows pacing, timing and what happens on a hit, which no screenshot can.
- **Source you may read:** the `assets` tool finds open source Godot projects (`source: godot`, `type: project`), which it can place in a folder to read but not run. Read how something is built, then write your own for this game.

**Keep what you learned from:** `assets` `fetch` with `url` and `into: study` puts a picture in `res://study/`, where it is never imported or built into the game, so it needs no licence line. A `Studied:` line with nothing behind it is a claim you have not earned.

**When a site refuses the picture:** many do. A game on Steam lists its real screenshots: take the number from its store address, read `https://store.steampowered.com/api/appdetails?appids=NUMBER&filters=basic,screenshots` with the host's web tool, and fetch a `path_full` address from the answer. `image_edit look` then shows you what you kept. If every source refuses, say so in your report instead of writing that you studied it.

**Write these as facts in `res://DESIGN.md`:**
- **Camera:** side, top, over the shoulder, fixed? How far away? Does it move, and how?
- **Scale:** how big is the player against the screen and the world? This one fact defines many games.
- **Colour:** the 5 or 6 main colours as hex. If a picture is in the project, `image_edit palette` reads them. Where does each go?
- **Light:** bright and even, or dark with pools of light? Warm against cold? Hard shadows or none?
- **Shapes:** round or sharp? Thick outlines? Blocky, thin, exaggerated? How detailed against how plain?
- **Motion:** snappy or weighty? How long does a jump or an attack take? How many frames does the animation seem to have?
- **Pacing:** how long is a level, a wave, a round? How often does something new appear?
- **Controls:** what does the player press, and how would that work on a phone?
- **Sound:** what is heard most? Is the music constant or rare?
- **The one thing:** what would be lost if this were removed?

**Then decide what to take.** Take principles, structure, proportions and feel. Never copy characters, names, logos, levels, music or art owned by someone else; a game inspired by another has its own of each. When the person asks for a named property, build the same kind of game with original characters and names, and tell them that you did.

**Check against it at the end.** Put your screenshot beside what you studied and list three differences. Fix the biggest one. A person who says "it looks generic" means this step was skipped: go back and look, rather than adjusting colours from memory.

If nothing can be looked up here, say so and work from what you know, naming what you are unsure of.
