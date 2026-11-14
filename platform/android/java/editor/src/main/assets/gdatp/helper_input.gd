# --- input ----------------------------------------------------------------------------------------------------------
# A part of the game helper: GDatpPlugin.gameHelperSource appends each gdatp/helper_*.gd after game_helper.gd, so
# these are the same script, sharing its helpers.

## The longest one input call's steps may take, each at its longest: the editor waits a minute for the game's answer,
## and the rest is room for frames that run slower than counted.
const STEPS_MS_MAX := 50000.0
## A wait_ms step, and an action or a key held for its ms, lasts at most this long.
const HOLD_MS_MAX := 10000.0
## A long press, swipe, pinch or gamepad step lasts at most this long.
const GESTURE_MS_MAX := 5000.0
## wait_frames waits at most this many frames, and wait_until at most this long for its checks.
const WAIT_FRAMES_MAX := 600
const WAIT_UNTIL_MS_MAX := 15000
## A text step types at most this many characters, one a frame.
const TEXT_MAX := 500
## The frames any step takes besides its own time: a tap three, a double click five.
const STEP_FRAMES := 5

## Actions and keys a `hold` step pressed and no `release` step let go of yet.
var _held: Array = []


## Plays a list of steps, each one of: tap ([x, y], a node path or {"text": ...}), long_press ({at, ms}), swipe ({from,
## to, ms, index}), pinch ({center, from, to, ms}), touch ({at, pressed, index}), mouse ({at, button, double}), action
## ({name, ms}), key ({name, ms}), joypad ({button, ms} or {axis, value, ms}), hold and release (an action or key name),
## text, wait_ms, wait_frames and wait_until ({checks, timeout_ms}); then reads the nodes named in `observe`. What a
## hold step pressed is let go at the end unless `keep_held` is true.
func _play_steps(params: Dictionary) -> Dictionary:
	var steps = params.get("steps", [])
	if typeof(steps) != TYPE_ARRAY or steps.is_empty():
		return {"error": "missing", "message": "input needs 'steps', for example [{\"tap\": [200, 300]}, {\"wait_ms\": 300}]."}
	# The editor stops waiting for the answer while the game would play on, so a list that could outlast its wait is
	# refused before the first step.
	var fps := clampf(Engine.get_frames_per_second(), 20.0, 60.0)
	var longest := _steps_worst_ms(steps, 1000.0 / fps)
	if longest > STEPS_MS_MAX:
		return {"error": "too_long", "message": "These steps could take up to %d s, counting each wait and hold in full and frames at %d a second; one input call plays at most %d s of steps." % [ceili(longest / 1000.0), roundi(fps), int(STEPS_MS_MAX / 1000.0)],
			"next": "Split them across several input calls."}
	var done: Array = []
	var stopped := {}
	for i in steps.size():
		var step = steps[i]
		if typeof(step) != TYPE_DICTIONARY or step.is_empty():
			stopped = {"error": "bad_step", "message": "Step %d is not an object." % (i + 1)}
			break
		var kind: String = step.keys()[0]
		var value = step[kind]
		var result: Dictionary
		match kind:
			"tap":
				result = await _tap(value)
			"long_press":
				result = await _long_press(value)
			"swipe":
				result = await _swipe(value)
			"pinch":
				result = await _pinch(value)
			"joypad":
				result = await _joypad(value)
			"touch":
				result = await _touch_step(value)
			"mouse":
				result = await _mouse(value)
			"action":
				result = await _action(value)
			"key":
				result = await _key(value)
			"hold":
				result = await _hold(value, true)
			"release":
				result = await _hold(value, false)
			"text":
				result = await _text(value)
			"wait_ms":
				await get_tree().create_timer(clampf(float(value), 0.0, HOLD_MS_MAX) / 1000.0, true, false, true).timeout
				result = {"waited_ms": float(value)}
			"wait_frames":
				result = await _wait_frames(value)
			"wait_until":
				result = await _wait_until(value)
			_:
				result = {"error": "unknown_step", "message": "Step %d is '%s'; steps are tap, long_press, swipe, pinch, touch, mouse, action, key, joypad, hold, release, text, wait_ms, wait_frames and wait_until." % [i + 1, kind]}
		if result.has("error"):
			result["step"] = i + 1
			stopped = result
			break
		result["step"] = kind
		done.append(result)
	var released: Array = []
	if not _flag(params.get("keep_held", false)):
		for held in _held.duplicate():
			await _hold(held, false)
			released.append(held)
	if not stopped.is_empty():
		stopped["done"] = done
		if not released.is_empty():
			stopped["released"] = released
		return stopped
	var answer := {"done": done}
	if not released.is_empty():
		answer["released"] = released
	elif not _held.is_empty():
		answer["held"] = _held.duplicate()
	var observe = params.get("observe", [])
	if typeof(observe) == TYPE_ARRAY and not observe.is_empty():
		var observed := {}
		for path in observe:
			observed[str(path)] = _node_state(get_tree().current_scene, str(path))
		answer["observed"] = observed
	return answer


## The longest [steps] can take, in ms: each step's own time as long as the step lets it last, and its frames at
## [frame_ms] each.
func _steps_worst_ms(steps: Array, frame_ms: float) -> float:
	var total := 0.0
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY or step.is_empty():
			continue
		var kind: String = step.keys()[0]
		var value = step[kind]
		var options: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
		total += STEP_FRAMES * frame_ms
		match kind:
			"wait_ms":
				total += clampf(float(value), 0.0, HOLD_MS_MAX)
			"action":
				total += clampf(_named_ms(value, 100.0), 0.0, HOLD_MS_MAX)
			"key":
				total += clampf(_named_ms(value, 50.0), 0.0, HOLD_MS_MAX)
			"long_press":
				total += clampf(_named_ms(value, 600.0), 50.0, GESTURE_MS_MAX)
			"joypad":
				total += clampf(_named_ms(value, 100.0 if options.has("button") else 300.0), 16.0, GESTURE_MS_MAX)
			"swipe", "pinch":
				total += _gesture_frames(clampf(_named_ms(value, 300.0), 50.0, GESTURE_MS_MAX)) * frame_ms
			"wait_frames":
				total += clampi(int(value), 0, WAIT_FRAMES_MAX) * frame_ms
			"wait_until":
				total += clampi(int(options.get("timeout_ms", 3000)), 0, WAIT_UNTIL_MS_MAX)
			"text":
				var typed: String = str(options.get("string", "")) if typeof(value) == TYPE_DICTIONARY else str(value)
				total += mini(typed.length(), TEXT_MAX) * frame_ms
	return total


## The frames a swipe or a pinch of [ms] moves over, a point each frame.
func _gesture_frames(ms: float) -> int:
	return maxi(2, int(ms / 16.0))


## The ms a timed step names, or [fallback] when it names none or is given only a place or a name.
func _named_ms(value, fallback: float) -> float:
	return float(value.get("ms", fallback)) if typeof(value) == TYPE_DICTIONARY else fallback


func _tap(target) -> Dictionary:
	var place := _place(target)
	if place.has("error"):
		return place
	var position: Vector2 = place.position
	_touch(position, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_touch(position, false)
	await get_tree().process_frame
	return {"at": [position.x, position.y], "hit": _hit(position)}


func _swipe(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "bad_step", "message": "swipe takes {\"from\": [x, y], \"to\": [x, y], \"ms\": 300}."}
	var from := _place(value.get("from", []))
	var to := _place(value.get("to", []))
	if from.has("error"):
		return from
	if to.has("error"):
		return to
	var ms := clampf(float(value.get("ms", 300)), 50.0, GESTURE_MS_MAX)
	var index := clampi(int(value.get("index", 0)), 0, 9)
	var steps := _gesture_frames(ms)
	var start: Vector2 = from.position
	var end: Vector2 = to.position
	_touch(start, true, index)
	var last := start
	for i in range(1, steps + 1):
		await get_tree().process_frame
		var point := start.lerp(end, float(i) / steps)
		var drag := InputEventScreenDrag.new()
		drag.index = index
		drag.position = point
		drag.relative = point - last
		drag.velocity = (point - last) * 60.0
		Input.parse_input_event(drag)
		last = point
	_touch(end, false, index)
	await get_tree().process_frame
	return {"from": [start.x, start.y], "to": [end.x, end.y], "ms": ms, "index": index}


## A finger held down on one place and lifted: {"at": [x, y], a node path or {"text": ...}, "ms": 600}.
func _long_press(value) -> Dictionary:
	var target = value.get("at", []) if typeof(value) == TYPE_DICTIONARY else value
	var place := _place(target)
	if place.has("error"):
		return place
	var ms := clampf(_named_ms(value, 600.0), 50.0, GESTURE_MS_MAX)
	var point: Vector2 = place.position
	_touch(point, true)
	await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	_touch(point, false)
	await get_tree().process_frame
	return {"at": [point.x, point.y], "held_ms": ms, "hit": _hit(point)}


## Two fingers moving together or apart around a place, as a zoom does: {"center": [x, y] or a node path, "from": 300,
## "to": 120, "ms": 300}, the distances between the fingers in the game window's pixels.
func _pinch(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "bad_step", "message": "pinch takes {\"center\": [x, y], \"from\": 300, \"to\": 120, \"ms\": 300}."}
	var place := _place(value.get("center", []))
	if place.has("error"):
		return place
	var center: Vector2 = place.position
	var from := float(value.get("from", 300))
	var to := float(value.get("to", 120))
	var ms := clampf(float(value.get("ms", 300)), 50.0, GESTURE_MS_MAX)
	var frames := _gesture_frames(ms)
	var last: Array = [center - Vector2(from / 2.0, 0.0), center + Vector2(from / 2.0, 0.0)]
	for finger in 2:
		_touch(last[finger], true, finger)
	for i in range(1, frames + 1):
		await get_tree().process_frame
		var gap := lerpf(from, to, float(i) / frames)
		var now: Array = [center - Vector2(gap / 2.0, 0.0), center + Vector2(gap / 2.0, 0.0)]
		for finger in 2:
			var drag := InputEventScreenDrag.new()
			drag.index = finger
			drag.position = now[finger]
			drag.relative = now[finger] - last[finger]
			drag.velocity = (now[finger] - last[finger]) * 60.0
			Input.parse_input_event(drag)
		last = now
	for finger in 2:
		_touch(last[finger], false, finger)
	await get_tree().process_frame
	return {"center": [center.x, center.y], "from": from, "to": to, "ms": ms}


## A gamepad's button pressed and let go, {"button": 0, "ms": 100}, or its stick held over, {"axis": 0, "value": 1.0,
## "ms": 300}, then back to the middle.
func _joypad(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or not (value.has("button") or value.has("axis")):
		return {"error": "bad_step", "message": "joypad takes {\"button\": 0, \"ms\": 100} or {\"axis\": 0, \"value\": 1.0, \"ms\": 300}."}
	var ms := clampf(float(value.get("ms", 100 if value.has("button") else 300)), 16.0, GESTURE_MS_MAX)
	if value.has("button"):
		var button := int(value.button) as JoyButton
		for pressed in [true, false]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			event.pressed = pressed
			event.pressure = 1.0 if pressed else 0.0
			Input.parse_input_event(event)
			if pressed:
				await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
		await get_tree().process_frame
		return {"button": button, "held_ms": ms}
	var axis := int(value.axis) as JoyAxis
	var amount := clampf(float(value.get("value", 1.0)), -1.0, 1.0)
	for held in [amount, 0.0]:
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis
		motion.axis_value = held
		Input.parse_input_event(motion)
		if held != 0.0:
			await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	await get_tree().process_frame
	return {"axis": axis, "value": amount, "held_ms": ms}


## One finger put down or lifted: {"at": [x, y] or a node path, "pressed": true, "index": 1}, so two fingers can work at
## once, such as a held joystick and a tapped button.
func _touch_step(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "bad_step", "message": "touch takes {\"at\": [x, y], \"pressed\": true, \"index\": 0}."}
	var place := _place(value.get("at", []))
	if place.has("error"):
		return place
	var index := clampi(int(value.get("index", 0)), 0, 9)
	var pressed := _flag(value.get("pressed", true))
	var point: Vector2 = place.position
	_touch(point, pressed, index)
	await get_tree().process_frame
	return {"at": [point.x, point.y], "index": index, "pressed": pressed}


## A mouse click: {"at": [x, y] or a node path, "button": "left", "double": false}, for games played with a mouse.
func _mouse(value) -> Dictionary:
	var options: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {"at": value}
	var place := _place(options.get("at", []))
	if place.has("error"):
		return place
	var buttons := {"left": [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT], "right": [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MASK_RIGHT],
		"middle": [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_MASK_MIDDLE]}
	var button_name := str(options.get("button", "left"))
	if not buttons.has(button_name):
		return {"error": "bad_step", "message": "button is left, right or middle."}
	var button: Array = buttons[button_name]
	var point: Vector2 = place.position
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var double := _flag(options.get("double", false))
	for click in (2 if double else 1):
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = button[0]
			event.pressed = pressed
			event.button_mask = button[1] if pressed else 0
			event.double_click = pressed and click == 1
			Input.parse_input_event(event)
			await get_tree().process_frame
	return {"at": [point.x, point.y], "button": button_name, "double": double, "hit": _hit(point)}


## Presses an input action or a key and leaves it down, or lets one go: "jump", {"action": "jump"} or {"key": "Space"}.
## A bare name that is not one of the game's actions is taken as a key.
func _hold(value, press: bool) -> Dictionary:
	var action := ""
	var key_name := ""
	if typeof(value) == TYPE_DICTIONARY:
		action = str(value.get("action", value.get("name", "")))
		key_name = str(value.get("key", ""))
	else:
		action = str(value)
	if key_name.is_empty() and not InputMap.has_action(action) and OS.find_keycode_from_string(action) != KEY_NONE:
		key_name = action
		action = ""
	var held := {}
	if not key_name.is_empty():
		var keycode := OS.find_keycode_from_string(key_name)
		if keycode == KEY_NONE:
			return {"error": "unknown_key", "message": "'%s' is not a key name, like Space, Enter, A or Left." % key_name}
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = press
		Input.parse_input_event(event)
		held = {"key": key_name}
	else:
		if not InputMap.has_action(action):
			var actions := InputMap.get_actions().filter(func(a): return not str(a).begins_with("ui_"))
			return {"error": "unknown_action", "message": "The game has no input action '%s'." % action, "actions": actions}
		if press:
			Input.action_press(action)
		else:
			Input.action_release(action)
		held = {"action": action}
	if press and not _held.has(held):
		_held.append(held)
	elif not press:
		_held.erase(held)
	await get_tree().process_frame
	var answer := {}
	answer["held" if press else "released"] = held.values()[0]
	if press and not can_process():
		answer["note"] = "The game is paused from the editor and sees this only once it runs: keep_held keeps it down for run step."
	return answer


## Types text into the control that has focus, one key press per character.
func _text(value) -> Dictionary:
	var text: String = str(value.get("string", "")) if typeof(value) == TYPE_DICTIONARY else str(value)
	if text.is_empty():
		return {"error": "bad_step", "message": "text takes the characters to type, such as {\"text\": \"Player One\"}."}
	var focus := get_viewport().gui_get_focus_owner()
	for character in text.left(TEXT_MAX):
		var down := InputEventKey.new()
		down.unicode = character.unicode_at(0)
		down.pressed = true
		Input.parse_input_event(down)
		var up: InputEventKey = down.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await get_tree().process_frame
	var answer := {"typed": mini(text.length(), TEXT_MAX)}
	var scene := get_tree().current_scene
	answer["focus"] = _path(scene, focus) if focus != null and scene != null else ""
	if focus == null:
		answer["note"] = "No control had focus, so the keys went to the game itself; tap the field first."
	return answer


## Waits until the game has run [value] more frames, 0 to 600; frames paused from the editor do not count.
func _wait_frames(value) -> Dictionary:
	if not can_process():
		return {"error": "paused", "message": "The game is paused from the editor, so no frames run; run step moves it frame by frame, run resume lets it go on."}
	var start := _ran_frames
	var target := start + clampi(int(value), 0, WAIT_FRAMES_MAX)
	while _ran_frames < target and can_process():
		await get_tree().process_frame
	return {"waited_frames": _ran_frames - start}


## Waits, frame by frame, until every check passes or `timeout_ms` runs out; running out stops the steps with the last
## results, as a failed check in a test does.
func _wait_until(value) -> Dictionary:
	var options: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {"checks": value}
	var checks = options.get("checks", [])
	if typeof(checks) != TYPE_ARRAY or checks.is_empty():
		return {"error": "bad_step", "message": "wait_until takes {\"checks\": [{\"path\": …, \"property\": …, \"equals\": …}], \"timeout_ms\": 3000}."}
	var timeout_ms := clampi(int(options.get("timeout_ms", 3000)), 0, WAIT_UNTIL_MS_MAX)
	var started := Time.get_ticks_msec()
	var result := _check(get_tree().current_scene, checks)
	if not result.passed and not can_process():
		return {"error": "paused", "message": "The game is paused from the editor, so nothing can change while waiting; run resume lets it go on, or run step_until steps it until the checks pass.", "results": result.results}
	while not result.passed and Time.get_ticks_msec() - started < timeout_ms:
		await get_tree().process_frame
		result = _check(get_tree().current_scene, checks)
	var waited := Time.get_ticks_msec() - started
	if not result.passed:
		return {"error": "not_met", "message": "The checks did not all pass within %d ms." % timeout_ms, "waited_ms": waited, "results": result.results}
	return {"passed": true, "waited_ms": waited, "frame": result.frame}


func _action(value) -> Dictionary:
	var action := str(value.get("name", "")) if typeof(value) == TYPE_DICTIONARY else str(value)
	var ms := _named_ms(value, 100.0)
	if not InputMap.has_action(action):
		var actions := InputMap.get_actions().filter(func(a): return not str(a).begins_with("ui_"))
		return {"error": "unknown_action", "message": "The game has no input action '%s'." % action, "actions": actions}
	Input.action_press(action)
	await get_tree().create_timer(clampf(ms, 0.0, HOLD_MS_MAX) / 1000.0, true, false, true).timeout
	Input.action_release(action)
	await get_tree().process_frame
	return {"action": action, "held_ms": ms}


func _key(value) -> Dictionary:
	var key_name := str(value.get("name", "")) if typeof(value) == TYPE_DICTIONARY else str(value)
	var ms := _named_ms(value, 50.0)
	var keycode := OS.find_keycode_from_string(key_name)
	if keycode == KEY_NONE:
		return {"error": "unknown_key", "message": "'%s' is not a key name, like Space, Enter, A or Left." % key_name}
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().create_timer(clampf(ms, 0.0, HOLD_MS_MAX) / 1000.0, true, false, true).timeout
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	return {"key": key_name, "held_ms": ms}


func _touch(position: Vector2, pressed: bool, index := 0) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = position
	touch.pressed = pressed
	Input.parse_input_event(touch)


## A point in the game window's pixels: [x, y] as given, the middle of a node named by its path, or of the visible
## control that shows a text, {"text": "Start"}, wherever the project's stretch places it on the screen.
func _place(target) -> Dictionary:
	if typeof(target) == TYPE_ARRAY and target.size() == 2:
		return {"position": Vector2(float(target[0]), float(target[1]))}
	if typeof(target) == TYPE_DICTIONARY and target.has("text"):
		return _place_text(str(target.text))
	if typeof(target) == TYPE_STRING:
		var node := _find(get_tree().current_scene, target)
		if node == null:
			return {"error": "not_found", "message": "There is no node '%s' in the running scene." % target}
		if node is TouchScreenButton:
			return {"position": _window_rect(node, _touch_area(node)).get_center()}
		if node is Control or node is Node2D:
			return {"position": _window_rect(node).get_center()}
		return {"error": "no_place", "message": "%s is a %s, which has no place on the screen." % [target, node.get_class()]}
	return {"error": "bad_step", "message": "A place is [x, y] in the game window's pixels, or a node's path."}


## The middle of the one visible control that shows [text]: exactly, else as part of its text, ignoring case.
func _place_text(text: String) -> Dictionary:
	var scene := get_tree().current_scene
	if scene == null:
		return {"error": "no_scene", "message": "The game has no current scene."}
	var exact: Array = []
	var partial: Array = []
	var controls: Array = scene.find_children("*", "Control", true, false)
	for node in controls:
		if not (node is Control) or not node.is_visible_in_tree() or not ("text" in node):
			continue
		var shown := str(node.get("text"))
		if shown == text:
			exact.append(node)
		elif not text.is_empty() and shown.findn(text) != -1:
			partial.append(node)
	var found := exact if not exact.is_empty() else partial
	if found.size() == 1:
		return {"position": _window_rect(found[0]).get_center()}
	if found.is_empty():
		return {"error": "not_found", "message": "No visible control shows '%s'." % text, "next": "game_read ui lists the controls and their text."}
	return {"error": "ambiguous", "message": "%d visible controls show '%s'; name one by its path." % [found.size(), text],
		"controls": found.map(func(node): return _path(scene, node))}


## The visible control under a point in the game window's pixels, the one a tap there reaches.
func _hit(position: Vector2) -> String:
	var found := ""
	var scene := get_tree().current_scene
	if scene == null:
		return found
	for node in [scene] + scene.find_children("*", "Control", true, false):
		if node is Control and node.is_visible_in_tree() and node.mouse_filter != Control.MOUSE_FILTER_IGNORE and _window_rect(node).has_point(position):
			found = _path(scene, node)
	return found
