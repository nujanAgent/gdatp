# Fetching art, models, sound, fonts and code from outside, with licences kept straight

Fetched assets are optional. Use them when the style wants them, such as real textures, a character that is too hard to build from parts, or a font with character. They do not replace a look: a mix of kits with no shared style is worse than simple art of your own.

**The `assets` tool:**
- `search` with `source`, `query`, and sometimes `type`: returns a list with ids, names, licences and sizes. Needs no open project.
- `look` with `source` and `id`: shows you a preview picture, so that you can judge before spending space and time.
- `fetch` with `source` and `id` (or `url`): downloads it into `res://assets/...`, imports it, and writes a line in `res://assets/CREDITS.md`.

**Sources:**
| source | What | Licence |
| --- | --- | --- |
| `polyhaven` | HDRI skies, PBR textures, photo-scanned models (`type`: `hdris`, `textures`, `models`) | CC0 |
| `ambientcg` | PBR materials, some HDRIs and models (`type`: `material`, `hdri`, `3d-model`, `decal`) | CC0 |
| `godot` | Godot's Asset Library: addons, tools and whole open source projects (`type`: `addon`, `project`) | as each lists, usually MIT |
| `url` | A direct https address to a file that you found by searching the web: PNG, JPG, SVG, GLB, glTF, OGG, WAV, MP3, TTF, OTF, or a ZIP of them. Pass `license` and `credit`. | what you read on its page |

**Finding more through web search:** many game artists publish CC0 packs, on their own sites and on open game art sites. Search for "CC0" with what you need (for example "CC0 knight sprite sheet"), open the page, read its licence, then `fetch` with `url`, `license`, `credit`. Check that a page says CC0 or similar; "free" alone may not allow use in a game. Well-known CC0 makers exist for low-poly kits, sprites and interface sets. Respect a site's own rules.

**Licences:**
- **CC0:** free for any use, credit not needed but kind. Default choice.
- **CC BY:** use with credit: put it on a credits screen. Say so to the person.
- **MIT and similar, for code:** keep the licence file with it.
- **CC BY-SA, GPL:** these have conditions on what you share; ask the person first.
- **NC (non-commercial), "personal use only", no licence stated:** do not use, unless the person says so knowing what it means.
Never use art taken from commercial games, or a named character.

**Keeping a picture to learn from:** `fetch` with `url` and `into: study` places it in `res://study/`, marked so that it is not imported or built into the game. It needs no `license`, and this is the only place a screenshot of someone else's game may go.

**Reading code to learn:** `fetch` from `godot` with `into: study` places a project in `res://study/<name>/`, marked so that it is not imported or built into the game. Read it with `files_read` to see how something was done, then write your own version for this game. Delete it before finishing, with `files_edit`. Addons go into `res://addons/`, and need turning on with `project_edit`.

**Weight:** phones have limited space, and the first import of big textures is slow. Fetch 1K or smaller; never a whole pack when three files will do. A `fetch` reports the bytes. Delete what you do not use.

**Making it fit:**
- `image_edit` recolours, resizes, crops and pixelates fetched pictures toward the game's palette and pixel size.
- Materials and light unify fetched 3D models: override their material colours, or use one shared palette texture.
- Scale fetched models to match: a door about 2 m, a person about 1.7 m, unless the game means otherwise.

**The person's own files:** they can copy files to the project's folder too; `files_read list` shows them after that. Connected tools through the host, such as image generators, can also supply images, which `files_edit` writes into the project.
