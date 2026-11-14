# Story games: visual novels, point and click, detective games and choices that matter

**Small and specific beats long and vague.** One night, one house, one decision. Write the whole thing as a person would: a beginning that sets a question, turns that change what it means, and an ending the choices earned. Write the story before the systems.

**Keep the story as data,** read by one player script, so it can grow.
```gdscript
const STORY := {
	"door": {"text": "The door is open. It was locked this morning.",
		"choices": [["Go in", "hall"], ["Call out", "voice", "called"]]},
	"voice": {"text": "Nothing answers. Then, upstairs, a chair moves.",
		"choices": [["Go in", "hall"]]},
}
var flags := {}


func pick(choice: Array) -> String:
	if choice.size() > 2:
		flags[choice[2]] = true
	return choice[1]
```
A choice may set a flag, and later text checks flags. A few flags that matter beat many that do not.

**Choices that count:** avoid many branches that rejoin as if nothing happened. Let a small choice return later, with a character remembering. Two or three different endings, each decided by things the player can recognise as their doing. A choice between two things the player wants is the strongest form.

**Showing text:** one line at a time, revealed by characters at about 40 a second, with a tap to finish a line and a tap to go on. Text at least 2.2% of the screen's height (29 px in a game 1280 high), as the look check measures, with a clear panel behind. Let the reader go back through what was said, and save at each scene.

**Point and click:** scenes with tappable places. On a phone there is no hovering, so offer a button that briefly marks everything interactive. A carried item is used on a thing by dragging. Puzzles come from the logic of the world, not from arbitrary item combinations, and a character's remark gives a hint after a failure.

**Detective games:** the player collects statements and evidence and links them; a wrong accusation has a cost. The test is whether they can reach the truth by reasoning, rather than by tapping everything.

**Life in plain scenes:** a character's expression changes with their mood (even simple drawn shapes); a small sound per line; music that changes at turns; backgrounds that shift with time of day; screen moves on a shock. Limited art with strong composition works: silhouettes, one colour, a single detail.

**Generated art:** keep one style for each character and scene (`style_*`), and reuse poses. Consistency matters more than detail.

**Make it yours.** A story told only through a phone's messages on screen. A night shift on a radio helpline. A trial where you are the only witness and you lie. Translating letters with a growing dictionary. A form that is the game.
