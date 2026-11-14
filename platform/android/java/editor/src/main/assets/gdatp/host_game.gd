
# --- the running game: its clock, and test set-up ------------------------------------------------------------------
# A part of the tool host: GDatpPlugin.hostSource appends each gdatp/host_*.gd after host.gd, so these are the same
# script, sharing its helpers. The game helper (game_helper.gd) answers the calls made here.

const GAME_CLOCK_OPS := ["pause", "resume", "step", "step_until", "speed", "mute"]
const GAME_EDIT_OPS := ["set", "call", "spawn", "remove", "reload", "change_scene", "pause"]
const MAX_STEP_FRAMES := 600
const STEP_SLEEP_USEC := 2000
## The speeds the Game view offers, from a sixteenth to sixteen times.
const GAME_SPEED_MIN := 0.0625
const GAME_SPEED_MAX := 16.0
## A try plays this long, at this many times normal speed: past most timers in a game, and within one call.
const TRY_SECONDS := 6.0
const TRY_SPEED := 4.0
## A game started for a screenshot runs this long first, past the fade or load of its first frames.
const LOOK_SETTLE_S := 1.0
## How long a screenshot waits for a game that started and has not reached the editor yet.
const LOOK_WAIT_S := 10.0

## Whether NuJan paused the running game from the editor, and the speed it set; each run starts unpaused at 1.
var _game_suspended := false
var _game_speed := 1.0
## Set by run play with frozen, so the game is paused the moment it connects, before its first frames run on.
var _freeze_next_run := false


## Plays the game as a person begins it: from the start, through its first screen's button, then at speed with moves of
## a person's thumbs. What only happens once play has begun, such as a timer that sends the first enemy or a block being
## broken, runs here, and what broke is listed. When nothing broke, the game starts again through its first screen: the
## moves leave it wherever they took it, such as high in the sky of a game that flies, and a look at that frame judges the
## moves rather than the game.
func _try_game(params: Dictionary) -> Dictionary:
	var started := await _play(params)
	if str(started.get("state")) != "live":
		return started
	var entered := await _game_answer("way_in", {}, 3.0)
	_debugger.send_to_game("scene:speed_changed", [TRY_SPEED])
	_game_speed = TRY_SPEED
	var began := Time.get_ticks_msec()
	var moves := 0
	while Time.get_ticks_msec() - began < TRY_SECONDS * 1000.0 and EditorInterface.is_playing_scene() and not _debugger.broken:
		await _game_answer("hands", {"step": moves}, 1.0)
		moves += 1
		await get_tree().create_timer(0.1).timeout
	var waited := (Time.get_ticks_msec() - began) / 1000.0
	if EditorInterface.is_playing_scene() and not _debugger.broken:
		_debugger.send_to_game("scene:speed_changed", [1.0])
	_game_speed = 1.0
	var answer := _run_state()
	answer["pressed"] = str(entered.get("pressed", ""))
	answer["played_s"] = int(waited * TRY_SPEED)
	answer["moves"] = moves
	_add_game_reports(answer)
	if not answer.errors.is_empty():
		answer["next"] = "This broke once play began: fix each error, then run try again."
		return answer
	await _stop_game()
	var again := await _play(params)
	if str(again.get("state")) == "break":
		# A second start is a person's second play, and what the first one saved is loaded by it.
		answer["state"] = "break"
		answer["errors"] = again.get("errors", [])
		answer["next"] = "Nothing broke in %d seconds of play, but the game broke when it started again after them, as a second play would: fix each error, then run try again." % answer.played_s
		return answer
	if str(again.get("state")) == "live":
		await _game_answer("way_in", {}, 3.0)
	answer["state"] = again.get("state", answer.get("state"))
	answer["next"] = "Nothing broke in %d seconds of play and %d moves, and the game has started again at the beginning of play. It tells nothing of what you did not see happen: screenshot target game shows what a player first sees, and input plays it." % [answer.played_s, moves]
	return answer


## A look at the running game, starting it first when none is running: the call asks to see the game, and a game stopped
## a moment earlier has nothing to show. The actions a burst holds or presses are checked against the project here.
func _game_screenshot(params: Dictionary) -> Dictionary:
	for key in ["hold", "press"]:
		var actions := _input_actions(_loose(params.get(key, [])))
		if actions.has("error"):
			return actions
		params[key] = actions.actions
	var started := ""
	if not EditorInterface.is_playing_scene() or not _debugger.live or _debugger.broken:
		var begun := await _start_to_look(params)
		if begun.has("error"):
			return begun
		started = str(begun.started)
	var burst := clampi(int(_loose(params.get("burst", 1))), 1, BURST_MAX)
	var shot := await _game_call("screenshot", params, 10.0 + (BURST_SPAN_MS_MAX / 1000.0 if burst > 1 else 0.0))
	if started.is_empty() or not shot.has("_raw"):
		return shot
	return {"_raw": _raw_with(str(shot._raw), "started", started)}


## Starts the game for a look at it as run play does, or waits for one that started and has not reached the editor yet;
## {"started": what was done} once it is live, else why it is not.
func _start_to_look(params: Dictionary) -> Dictionary:
	var waited := 0.0
	while EditorInterface.is_playing_scene() and not _debugger.live and not _debugger.broken and waited < LOOK_WAIT_S:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if EditorInterface.is_playing_scene() and _debugger.broken:
		return _fail("break", "The game stopped at an error, so it has nothing to show.", {"errors": _debugger_errors().slice(-5), "next": "Fix the script, then run restart."})
	if EditorInterface.is_playing_scene() and _debugger.live:
		return {"started": ""}
	if EditorInterface.is_playing_scene():
		return _fail("not_live", "The game started but has not reached the editor's debugger.", {"next": "logs shows what it printed; run restart starts it again."})
	var named := str(params.get("scene", "")).strip_edges()
	var begun := await _play({"scene": "main" if named.is_empty() else named})
	if begun.has("error"):
		return begun
	match str(begun.get("state")):
		"live":
			await get_tree().create_timer(LOOK_SETTLE_S).timeout
			var which := str(begun.get("scene", ""))
			if named.is_empty():
				return {"started": "No game was running, so this started the main scene, %s, as run play does: the picture is its first screen, and the game runs on. To see another scene, name it in scene." % which}
			return {"started": "No game was running, so this started %s as run play does: the picture is its first screen, and the game runs on." % which}
		"break":
			return _fail("break", "No game was running, and the one this started stopped at an error before a picture could be taken.", {"errors": begun.get("errors", []), "next": "Fix each error, then screenshot target game again."})
		_:
			return _fail("not_running", "No game was running, and the one this started did not reach the editor.", {"state": begun.get("state", ""), "next": "logs shows why."})


## [raw], a JSON object as the game wrote it, with [key] added in front: written into the text, since parsing it and
## writing it again would turn its whole numbers into decimals.
func _raw_with(raw: String, key: String, value) -> String:
	var body := raw.strip_edges()
	if not body.begins_with("{"):
		return raw
	var rest := body.substr(1).strip_edges()
	return "{%s:%s%s%s" % [JSON.stringify(key), JSON.stringify(value), "" if rest.begins_with("}") else ",", rest]


## Pauses, resumes, steps or speeds the running game from the editor, as the Game view's buttons do: the game's own
## code and its own pause are left as they are, and game_read and screenshot see the game where it stopped.
func _game_clock(op: String, params: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene() or not _debugger.live:
		return _fail("not_running", "No game is running.", {"next": "run play starts one."})
	match op:
		"pause", "resume":
			_suspend_game(op == "pause")
			var answer := await _game_answer("frame", {}, 5.0)
			if answer.has("error"):
				return answer
			var paused := bool(answer.get("suspended", _game_suspended))
			_game_suspended = paused
			return {"state": "paused" if paused else "running", "frame": int(answer.get("frame", 0)),
				"next": "run step moves it one frame at a time; run resume lets it go on." if paused else "run pause stops it again."}
		"speed":
			var scale := clampf(float(params.get("scale", 1.0)), GAME_SPEED_MIN, GAME_SPEED_MAX)
			_debugger.send_to_game("scene:speed_changed", [scale])
			_game_speed = scale
			return {"speed": scale, "note": "Game time runs at %s times its normal speed until the run ends or speed changes it." % scale}
		"mute":
			var muted := _flag(params.get("on", true))
			_debugger.send_to_game("scene:debug_mute_audio", [muted])
			return {"muted": muted}
		_:
			return await _step_game(op, params)


## Lets the paused game run one drawn frame at a time; step_until stops at the first frame where every check passes.
## Actions in `hold` are down for every frame of the call and those in `press` for its first frame only, so a press is
## that frame's "just pressed"; both are let go at the end.
func _step_game(op: String, params: Dictionary) -> Dictionary:
	var checks: Array = []
	if op == "step_until":
		var given = params.get("checks", [])
		if typeof(given) != TYPE_ARRAY or given.is_empty():
			return _fail("missing", "step_until needs 'checks', such as [{\"path\": \"Main/Player\", \"property\": \"is_on_floor\", \"equals\": true}].")
		checks = given
	var held := _input_actions(params.get("hold", []))
	var pressed := _input_actions(params.get("press", []))
	for actions in [held, pressed]:
		if actions.has("error"):
			return actions
	var limit := clampi(int(params.get("frames", 1 if checks.is_empty() else 300)), 1, MAX_STEP_FRAMES)
	# Sent even when NuJan paused it: the person may have resumed it from the game's own menu since.
	var was_running := not _game_suspended
	_suspend_game(true)
	# Each frame waits on the editor's own loop, which sleeps 100 ms between frames while the game has the focus.
	var editor_sleep := OS.low_processor_usage_mode_sleep_usec
	OS.low_processor_usage_mode_sleep_usec = mini(editor_sleep, STEP_SLEEP_USEC)
	var stepped := 0
	var last := {}
	while stepped < limit:
		var press: Array = held.actions + pressed.actions if stepped == 0 else []
		var release: Array = pressed.actions if stepped == 1 else []
		_debugger.send_to_game("gdatp:input", [_game_token, press, release])
		_debugger.send_to_game("scene:next_frame", [])
		last = await _game_answer("frame", {"after_draw": true, "checks": checks}, 5.0)
		if last.has("error"):
			break
		stepped += 1
		if not checks.is_empty() and bool(last.check.passed):
			break
	OS.low_processor_usage_mode_sleep_usec = editor_sleep
	# Lets go of what this call pressed, and pauses again, which switches the paused game's input off as before.
	_debugger.send_to_game("gdatp:input", [_game_token, [], held.actions + pressed.actions])
	_suspend_game(true)
	if last.has("error"):
		last["stepped"] = stepped
		return last
	var answer := {"stepped": stepped, "frame": int(last.get("frame", 0)), "state": "paused"}
	if was_running:
		answer["note"] = "The game was running; it was paused first."
	if checks.is_empty():
		answer["next"] = "game_read and screenshot see this frame; run resume lets the game go on."
		return answer
	answer["passed"] = bool(last.check.passed)
	answer["checks"] = last.check.results
	answer["next"] = "The game is paused at the first frame that passed." if answer.passed else "No frame within %d passed every check; the results are the last frame's." % limit
	return answer


func _suspend_game(on: bool) -> void:
	_debugger.send_to_game("scene:suspend_changed", [on])
	_game_suspended = on


## The project's input actions named in [value] (one name or a list) as {"actions": […]}, or a refusal naming them.
func _input_actions(value) -> Dictionary:
	var names: Array = value if typeof(value) == TYPE_ARRAY else ([] if str(value).is_empty() else [value])
	var actions: Array = []
	for item in names:
		var action := str(item)
		if not ProjectSettings.has_setting("input/" + action) and not action.begins_with("ui_"):
			var known: Array = []
			for property in ProjectSettings.get_property_list():
				if str(property.name).begins_with("input/") and not str(property.name).begins_with("input/ui_"):
					known.append(str(property.name).trim_prefix("input/"))
			return _fail("unknown_action", "The project has no input action '%s'." % action, {"actions": known, "did_you_mean": _nearest(action, known)})
		actions.append(action)
	return {"actions": actions}


## Sets up a test in the running game: set a property, call a method, spawn or remove a node, reload or change the
## scene, or the game's own pause. Nothing here is saved in the project, and it all ends with the run.
func _game_edit(args: Dictionary) -> Dictionary:
	if args.op.is_empty():
		return _fail("missing", "game_edit needs 'op', one of: %s." % ", ".join(GAME_EDIT_OPS))
	if not GAME_EDIT_OPS.has(args.op):
		return _bad_op("!" + args.op, GAME_EDIT_OPS)
	var params: Dictionary = args.params.duplicate()
	params["op"] = args.op
	return await _game_call("edit", params, 15.0)


## The game helper's answer as a Dictionary, for the host's own use; a refusal as it came.
func _game_answer(tool: String, params: Dictionary, timeout_s: float) -> Dictionary:
	var answer := await _game_call(tool, params, timeout_s)
	if not answer.has("_raw"):
		return answer
	return JSON.parse_string(answer._raw)
