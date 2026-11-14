# Touch controls: designing for thumbs, sticks, drags, swipes, pinch, tilt and many fingers

A tested version of all this is `parts add touch`: a stick or arrows, a drag to look, and drawn buttons. Write your own only for controls that are this game's own idea.

**Choose the control from the verb, before the layout.** A joystick is one answer of many, and often not the best. Can the player touch the thing itself? Drag to aim, tap what you want, swipe to move, hold to charge, tilt to steer, or two zones under two thumbs. Direct control feels better than a virtual gamepad.

**One tap, one event.** A phone sends each touch as `InputEventScreenTouch` and again as an emulated `InputEventMouseButton`. Code that reads both does everything twice, and nothing reports it: a mirror turned twice has not moved. In `_input`, read `InputEventScreenTouch` alone.

**Rules:** at least 64 px, preferably 80 or more. Thumbs rest low at the sides: nothing important in the top middle. Keep controls off the action, in their own band in portrait. Show pressed state and give a sound. Nothing should need precise starting position: a floating stick appears where the thumb lands. `ui_edit` builds touch buttons and joysticks; a `TouchScreenButton` maps to input actions, and works with several fingers.

**Floating stick** (put in a Control across the left half, mouse filter stop):
```gdscript
extends Control

const REACH := 90.0
var value := Vector2.ZERO
var _finger := -1
var _centre := Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0:
			_finger = event.index
			_centre = event.position
		elif not event.pressed and event.index == _finger:
			_finger = -1
			value = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _finger:
		value = ((event.position - _centre) / REACH).limit_length(1.0)
```
For fingers anywhere on the screen, rather than on one Control, handle `InputEventScreenTouch` and `InputEventScreenDrag` in `_input`, keeping a dictionary by `event.index`.

**Swipe:** on release, compare distance and time: more than 60 px in under 0.3 s is a swipe; take the larger axis.

**Pinch and pan:** keep touches by index; with two, compare the distance now to before for zoom, and the midpoint's movement for pan.
```gdscript
extends Camera2D

var _touches := {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		var before: float = _spread()
		_touches[event.index] = event.position
		if _touches.size() == 1:
			position -= event.relative / zoom
		elif _touches.size() == 2 and before > 0.0:
			zoom = (zoom * _spread() / before).clamp(Vector2(0.5, 0.5), Vector2(3.0, 3.0))


func _spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])
```

**Tilt:** `Input.get_accelerometer()` in 3-axis units; smooth it, and add a dead zone near flat. Offer it only as an option, since many people play lying down.

**Assist:** touch lacks precision, so let the game help: auto-aim toward the nearest target within a cone; snap to grid; generous hit areas; jump timing that is forgiving.

**Test as a thumb would,** with `input touch` at the actual node. Check that two fingers at once work: move and act together. A control that overlaps another will steal touches. Use `game_read ui` to see each control's rectangle.

**Keys** can stay in for other devices: map `Input` actions, and let touch trigger the same actions.
