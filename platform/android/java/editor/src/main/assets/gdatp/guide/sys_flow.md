# Game flow: a way in, pause, an end, a way back, and scene changes that do not dead-end

`parts add screens` gives the title, pause and end screens with Android's back button handled.

A game is complete when nothing dead-ends: title, play, pause, end, play again. Write this for each game, shaped by it: a racer's end is a results table, a story's end is the story's.

**One autoload holds what crosses scenes** (register with `project_edit`):
```gdscript
extends Node

var score := 0
var level := 0
var _fade: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func go_to(scene_path: String) -> void:
	var out := create_tween()
	out.tween_property(_fade, "modulate:a", 1.0, 0.2)
	await out.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)
	var back := create_tween()
	back.tween_property(_fade, "modulate:a", 0.0, 0.25)
```
Vary the transition to suit the style: a curtain, a page turn, an iris closing, or a pixel wipe.

**Pause:** `get_tree().paused = true` stops everything except nodes with `process_mode` set to `PROCESS_MODE_ALWAYS` or `WHEN_PAUSED`, which the pause menu needs. A pause button is required on a phone. Pause when the app goes away too:
```gdscript
extends Node

@export var pause_menu: Control


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		get_tree().paused = true
		pause_menu.show()
```

**Checks to play through with `input`:** title to game; pause and resume; win reached for real; lose reached for real; replay works after each, and no state is left over (score reset, enemies gone, timers stopped, `paused` false). A stale autoload value is the classic second-run bug, so always play a second run.

**Title:** show the game's own look at once: the world behind the title rather than a colour and a button. Text that invites: a verb ("Tap to fly"), not "Start".

**Ending:** say what happened; show the score and any new best; one tap to play again. Play stops behind it: nothing the player does reaches the game under the panel. Read gameplay touches in `_unhandled_input`, which a panel with `mouse_filter` set to stop takes first (`_input` runs before any panel), or check the game's state before acting on them.

**First 20 seconds:** teach the verb by making the player do it, with a hint that goes away when done. No wall of text. A hint on a screen is best next to where the thing is.

**Settings:** only sound and music toggles at minimum, kept by `sys_save`. A back gesture or button should not quit without asking while a game is running: set `application/config/quit_on_go_back` false and handle `NOTIFICATION_WM_GO_BACK_REQUEST`.

**Scenes:** one scene for each screen, and one for each kind of thing (player, enemy). Keep scene transitions in the autoload, so nothing else needs to know the file layout.
