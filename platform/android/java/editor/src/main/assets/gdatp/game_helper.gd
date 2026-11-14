extends Node

## GDatp's helper inside a game the editor started. The editor sends it tool calls through the debugger; each is answered
## with a "gdatp:reply" message. It works while the game is paused too, and coordinates are the game window's pixels, as
## in the game's screenshots at full size. The helper_*.gd parts (input, checks, test set-up) follow this script, then
## the shared_*.gd parts, so values are typed and shown as the editor's tools type and show them.

const WATCH_GROUP := "nujan_watch"
const MAX_NODES := 300
const ANY_ORIENTATION := 6
const UPRIGHT_ORIENTATIONS := [1, 3, 5]

## Frames the game has run since the helper joined it, drawn and physics. Neither counts while the editor has the game
## paused, so they move by exactly what run step moves; the engine's own counters run on through a pause.
var _ran_frames := 0
var _ran_physics_frames := 0


func _ready() -> void:
	_keep_project_shape()
	EngineDebugger.send_message("gdatp:ready", [])


## A game is played the way round its project says, while the editor's window here may be the other way round. Keeping the
## project's shape makes a test show what will ship: its framing, its controls and its text. This helper never ships.
func _keep_project_shape() -> void:
	var orientation := int(ProjectSettings.get_setting("display/window/handheld/orientation", 0))
	if orientation == ANY_ORIENTATION:
		return
	var window := get_tree().root
	if (orientation in UPRIGHT_ORIENTATIONS) != (window.size.y > window.size.x):
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func _process(_delta: float) -> void:
	_ran_frames += 1


func _physics_process(_delta: float) -> void:
	_ran_physics_frames += 1


func handle(id: String, tool: String, args_json: String) -> void:
	var parsed = JSON.parse_string(args_json) if not args_json.strip_edges().is_empty() else {}
	var params: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var answer: Dictionary
	match tool:
		"screenshot":
			answer = await _screenshot(params)
		"input":
			answer = await _play_steps(params)
		"read":
			answer = await _read(params)
		"frame":
			answer = await _frame(params)
		"edit":
			answer = await _edit(params)
		"exec":
			answer = await _exec(params)
		"way_in":
			answer = await _way_in()
		"hands":
			answer = await _hands(int(params.get("step", 0)))
		_:
			answer = {"error": "unknown_tool", "message": "The game helper has no tool '%s'." % tool}
	EngineDebugger.send_message("gdatp:reply", [id, JSON.stringify(answer)])


## Where the game is once the frame being drawn now is done: its frame count, whether the editor has it paused, and the
## result of `checks` when given. Stepping a paused game asks for this after each frame it lets through.
func _frame(params: Dictionary) -> Dictionary:
	if _flag(params.get("after_draw", false)):
		await RenderingServer.frame_post_draw
	var answer := {"frame": _ran_frames, "suspended": not can_process()}
	var checks = params.get("checks", [])
	if typeof(checks) == TYPE_ARRAY and not checks.is_empty():
		answer["check"] = _check(get_tree().current_scene, checks)
	return answer


## Taps the button that begins the game, as a person does on a title screen, and says what it read on it. A game with
## no such button on screen has begun already.
func _way_in() -> Dictionary:
	var scene := get_tree().current_scene
	if scene == null:
		return {"pressed": ""}
	var buttons: Array = scene.find_children("*", "BaseButton", true, false).filter(func(found): return found.is_visible_in_tree() and not found.disabled and not str(found.get("text")).is_empty())
	if buttons.is_empty():
		return {"pressed": ""}
	var words := RegEx.create_from_string("(?i)play|start|begin|new|resume|continue|again|retry")
	var begins: Array = buttons.filter(func(found): return words.search(str(found.get("text"))) != null)
	var button: BaseButton = begins[0] if not begins.is_empty() else buttons[0]
	var middle := _window_rect(button).get_center()
	await _tap([middle.x, middle.y])
	return {"pressed": str(button.get("text"))}


## One move of a person's thumbs, by step: walking, looking, pressing under the right thumb, and answering a button with
## words on it. A paused game has its menu answered first, so play goes on past a pause or an end. The top of the screen
## is left alone, since a pause button lives there.
func _hands(step: int) -> Dictionary:
	if get_tree().paused:
		return await _way_in()
	var window := Vector2(get_window().size)
	match step % 5:
		0:
			return await _swipe({"from": [window.x * 0.12, window.y * 0.75], "to": [window.x * 0.12, window.y * 0.55], "ms": 400})
		1:
			return await _swipe({"from": [window.x * 0.55, window.y * 0.45], "to": [window.x * 0.4, window.y * 0.45], "ms": 250})
		2:
			return await _tap([window.x * 0.9, window.y * 0.75])
		3:
			return await _tap([window.x * 0.78, window.y * 0.85])
		_:
			return await _way_in()


# --- screenshot -----------------------------------------------------------------------------------------------------

## A burst's frames sit this far apart in its picture.
const BURST_GAP_PX := 4
## Frames are compared as a grid this many cells across. A cell has changed when its brightness moved by CHANGE_LIGHT, which
## a change of a few pixels inside it, such as a blinking cursor, does not reach. A still scene draws the same pixels each
## frame, so one changed cell is something that moved: a player one cell wide walking changes about three.
const CHANGE_CELLS_ACROSS := 96
const CHANGE_LIGHT := 0.06
## A region is enlarged at most this many times, in whole steps, so its pixels stay sharp.
const REGION_ENLARGE_MAX := 4
const REGION_MIN_PX := 16
## Around a node with no size of its own, a region spans this share of the window's shorter side.
const REGION_AROUND_SHARE := 0.3
## A burst frame's number, as the rows of a figure three pixels wide and five high.
const DIGITS := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]


## The game as its window shows it: one frame, or with `burst` several frames as one picture. With `region`, only that part
## of the screen, enlarged so that small things can be read. The host fills in max_size when the call names none.
func _screenshot(params: Dictionary) -> Dictionary:
	var count := clampi(int(_loose(params.get("burst", 1))), 1, BURST_MAX)
	if count > 1:
		return await _burst(params, count)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return {"error": "no_picture", "message": "The game had nothing to capture."}
	image = _on_window(image)
	var region := _region(params, image.get_size())
	if region.has("error"):
		return region
	var answer := _shot_answer(image.get_size())
	if region.is_empty():
		answer["look_check"] = _look_check(image)
		image = _fitted(image, int(params.max_size))
	else:
		# Only a whole frame is measured: a part of it would clear what was found in the rest.
		var rect: Rect2i = region.rect
		var times := _enlargement(rect.size, int(params.max_size))
		image = _fitted(image.get_region(rect), int(params.max_size), times)
		answer["region"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		answer["note"] = "This is the part of the screen at %s in full_size pixels, shown %d times larger. Input coordinates are still in full_size pixels." % [str(answer.region), times]
	var saved := _saved(image, "game")
	if saved.has("error"):
		return saved
	answer["path"] = saved.path
	answer["size"] = [image.get_width(), image.get_height()]
	return answer


## Several frames of the running game a moment apart, as one picture: in reading order, left to right and then down, each
## numbered in its corner. Each frame also says how much of the picture changed since the one before and where, since a
## model reads a number more surely than it compares pictures. Actions in `hold` are down for the whole burst and those in
## `press` for its first frame, so a burst shows what an action does.
func _burst(params: Dictionary, count: int) -> Dictionary:
	if not can_process():
		return {"error": "paused", "message": "The game is paused from the editor, so every frame of a burst would be the same.",
			"next": "run resume lets it go on; run step moves it a frame at a time."}
	var every_ms := clampf(float(_loose(params.get("every_ms", BURST_EVERY_MS))), BURST_EVERY_MS_MIN, minf(BURST_EVERY_MS_MAX, BURST_SPAN_MS_MAX / (count - 1)))
	var held := _action_names(params.get("hold", []))
	var pressed := _action_names(params.get("press", []))
	for names in [held, pressed]:
		if names.has("error"):
			return names
	for action in held.names + pressed.names:
		Input.action_press(action)
	var shots: Array = []
	var last: Image = null
	var region := {}
	var area := Rect2i()
	var layout := {}
	var began := Time.get_ticks_msec()
	for i in count:
		if i > 0:
			await get_tree().create_timer(every_ms / 1000.0, true, false, true).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			break
		image = _on_window(image)
		if i == 0:
			for action in pressed.names:
				Input.action_release(action)
			region = _region(params, image.get_size())
			if region.has("error"):
				break
			area = Rect2i(Vector2i.ZERO, image.get_size()) if region.is_empty() else region.rect
			layout = _burst_layout(count, area.size, int(params.max_size), not region.is_empty())
		var part: Image = image if region.is_empty() else image.get_region(area)
		var tile_size: Vector2i = layout.tile
		var tile := part.duplicate() as Image
		tile.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST if int(layout.times) > 1 else Image.INTERPOLATE_BILINEAR)
		shots.append({"tile": tile, "cells": _cells(part), "ms": Time.get_ticks_msec() - began, "frame": _ran_frames})
		last = image
	for action in held.names:
		Input.action_release(action)
	if region.has("error"):
		return region
	if shots.is_empty():
		return {"error": "no_picture", "message": "The game had nothing to capture."}
	var columns: int = layout.columns
	var rows: int = layout.rows
	var tile_size: Vector2i = layout.tile
	var first: Image = shots[0].tile
	var sheet := Image.create(columns * tile_size.x + (columns - 1) * BURST_GAP_PX, rows * tile_size.y + (rows - 1) * BURST_GAP_PX, false, first.get_format())
	sheet.fill(Color.WHITE)
	var frames: Array = []
	var moved := 0
	var where := Rect2i()
	for i in shots.size():
		var tile: Image = shots[i].tile
		_number(tile, i + 1)
		var corner := Vector2i((i % columns) * (tile_size.x + BURST_GAP_PX), floori(float(i) / columns) * (tile_size.y + BURST_GAP_PX))
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, tile_size), corner)
		var entry := {"n": i + 1, "ms": shots[i].ms, "frame": shots[i].frame}
		if i > 0:
			var change := _changed(shots[i - 1].cells, shots[i].cells, area)
			entry.merge(change)
			if change.has("where"):
				moved += 1
				var spot: Array = change.where
				var box := Rect2i(int(spot[0]), int(spot[1]), int(spot[2]), int(spot[3]))
				where = where.merge(box) if moved > 1 else box
		frames.append(entry)
	var during := ""
	if not held.names.is_empty():
		during = " with %s held" % ", ".join(PackedStringArray(held.names))
	elif not pressed.names.is_empty():
		during = " after %s was pressed" % ", ".join(PackedStringArray(pressed.names))
	var answer := _shot_answer(last.get_size())
	answer["burst"] = shots.size()
	answer["every_ms"] = roundi(every_ms)
	answer["grid"] = [columns, rows]
	answer["frames"] = frames
	answer["from_first_to_last"] = _changed(shots[0].cells, shots[-1].cells, area).changed
	if moved == 0:
		answer["summary"] = "Nothing on the screen changed in %d frames over %.1f s%s." % [shots.size(), float(shots[-1].ms) / 1000.0, during]
		answer["next"] = "If something should move here, it does not: game_read sample reads a node's values over frames, and input plays the game."
	else:
		answer["summary"] = "The picture changed between %d of %d pairs of frames%s, within [%d, %d, %d, %d] in full_size pixels." % [
			moved, shots.size() - 1, during, where.position.x, where.position.y, where.size.x, where.size.y]
		answer["next"] = "screenshot with that rectangle as region shows it closer, and game_read find names what is there."
	answer["note"] = "Frames are numbered in reading order, left to right and then down. changed is the share of the picture that differs from the frame before, and where is that part, in full_size pixels, which input takes."
	if region.is_empty():
		answer["look_check"] = _look_check(last)
	else:
		answer["region"] = [area.position.x, area.position.y, area.size.x, area.size.y]
		answer["note"] += " Each frame is the part of the screen at %s, which stays where it was at the first frame." % str(answer.region)
	var saved := _saved(sheet, "game-burst")
	if saved.has("error"):
		return saved
	answer["path"] = saved.path
	answer["size"] = [sheet.get_width(), sheet.get_height()]
	return answer


func _shot_answer(full: Vector2i) -> Dictionary:
	var scene := get_tree().current_scene
	return {"target": "game", "full_size": [full.x, full.y], "frame": _ran_frames, "project": str(ProjectSettings.get_setting("application/config/name", "")),
		"note": "Input coordinates are in full_size pixels.", "scene": scene.scene_file_path if scene != null else ""}


func _saved(image: Image, prefix: String) -> Dictionary:
	var dir := OS.get_cache_dir().path_join("gdatp")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%s-%d.png" % [prefix, Engine.get_process_frames()])
	var saved := image.save_png(path)
	if saved != OK:
		return {"error": "not_saved", "message": "The picture could not be saved (error %d)." % saved}
	return {"path": path}


## [image] at most [max_size] on its longest side, or [times] larger with its pixels kept sharp.
func _fitted(image: Image, max_size: int, times := 1) -> Image:
	if times > 1:
		image.resize(image.get_width() * times, image.get_height() * times, Image.INTERPOLATE_NEAREST)
		return image
	var longest := maxi(image.get_width(), image.get_height())
	if longest > max_size:
		var scale := float(max_size) / longest
		image.resize(roundi(image.get_width() * scale), roundi(image.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	return image


## How many times larger a region of [size] can be shown within [max_size], in whole steps.
func _enlargement(size: Vector2i, max_size: int) -> int:
	return clampi(floori(float(max_size) / maxi(size.x, size.y)), 1, REGION_ENLARGE_MAX)


## How a burst of [count] frames of [size] fits within [max_size]: one row for two or three frames, two by two for four,
## and rows of three beyond. A region's frames may be shown larger, in whole steps.
func _burst_layout(count: int, size: Vector2i, max_size: int, enlarge: bool) -> Dictionary:
	var columns := count if count <= 3 else (2 if count == 4 else 3)
	var rows := ceili(float(count) / columns)
	var scale := minf(float(max_size - BURST_GAP_PX * (columns - 1)) / (columns * size.x), float(max_size - BURST_GAP_PX * (rows - 1)) / (rows * size.y))
	var times := 1
	if enlarge and scale >= 2.0:
		times = mini(floori(scale), REGION_ENLARGE_MAX)
		scale = times
	else:
		scale = minf(scale, 1.0)
	return {"columns": columns, "rows": rows, "times": times, "tile": Vector2i(maxi(1, floori(size.x * scale)), maxi(1, floori(size.y * scale)))}


## The game's input actions named in [value], one name or a list, as {"names": […]}, or a refusal listing the ones it has.
func _action_names(value) -> Dictionary:
	var given = _loose(value)
	var listed: Array = given if typeof(given) == TYPE_ARRAY else ([] if str(given).is_empty() else [given])
	var names: Array = []
	for item in listed:
		var action := str(item)
		if not InputMap.has_action(action):
			var actions := InputMap.get_actions().filter(func(known): return not str(known).begins_with("ui_"))
			return {"error": "unknown_action", "message": "The game has no input action '%s'." % action, "actions": actions}
		names.append(action)
	return {"names": names}


## The part of the window a call names: `around` a node's path, which takes where that node is drawn, or `region` as
## [x, y, width, height] in full_size pixels; {} when it names neither. A path sent as region is taken as around.
func _region(params: Dictionary, window: Vector2i) -> Dictionary:
	var given = _loose(params.get("region", ""))
	var named = params.get("around", "")
	var around := "" if named == null else str(named).strip_edges()
	if around.is_empty() and (typeof(given) == TYPE_STRING or typeof(given) == TYPE_STRING_NAME):
		around = str(given).strip_edges()
	var area := Rect2()
	if not around.is_empty():
		var placed := _node_area(around, window)
		if placed.has("error"):
			return placed
		area = placed.area
	elif given == null or typeof(given) == TYPE_STRING or typeof(given) == TYPE_STRING_NAME:
		return {}
	else:
		var numbers := _numbers(given, ["x", "y", "width", "height"])
		if numbers.size() != 4:
			numbers = _numbers(given, ["x", "y", "w", "h"])
		if numbers.size() != 4:
			return {"error": "bad_region", "message": "region is [x, y, width, height] in full_size pixels, such as [100, 200, 300, 150]; around takes a node's path, such as Main/Player."}
		area = Rect2(numbers[0], numbers[1], numbers[2], numbers[3]).abs()
	var rect := Rect2i(area).intersection(Rect2i(Vector2i.ZERO, window))
	if rect.size.x < REGION_MIN_PX or rect.size.y < REGION_MIN_PX:
		return {"error": "bad_region", "message": "That region is not on the %dx%d screen." % [window.x, window.y], "full_size": [window.x, window.y]}
	return {"rect": rect}


## Where the node at [path] is drawn, in the window's pixels: a control's or a sprite's rectangle with room around it, or
## the space around the point a node stands at, in 2D or through the camera in 3D.
func _node_area(path: String, window: Vector2i) -> Dictionary:
	var scene := get_tree().current_scene
	var node: Node = _find(scene, path) if scene != null else null
	if node == null:
		return {"error": "not_found", "message": "There is no node '%s' in the running scene." % path, "next": "game_read find lists the nodes and where they are."}
	var shown := Rect2()
	if node is Control:
		shown = _window_rect(node)
	elif node is CanvasItem and node.has_method("get_rect"):
		shown = _window_rect(node, node.call("get_rect"))
	if shown.has_area():
		return {"area": shown.grow(maxf(shown.size.x, shown.size.y) * 0.25 + 8.0)}
	var point := Vector2.INF
	if node is CanvasItem:
		point = _window_rect(node).position
	elif node is Node3D:
		var camera := get_viewport().get_camera_3d()
		var at := (node as Node3D).global_position
		if camera != null and not camera.is_position_behind(at):
			point = get_tree().root.get_final_transform() * camera.unproject_position(at)
	if not point.is_finite():
		return {"error": "no_place", "message": "%s is not drawn anywhere on the screen." % path}
	var side := minf(window.x, window.y) * REGION_AROUND_SHARE
	return {"area": Rect2(point - Vector2(side, side) / 2.0, Vector2(side, side))}


## The picture as a grid of brightness, CHANGE_CELLS_ACROSS wide, each cell taken from the pixels under it.
func _cells(image: Image) -> Dictionary:
	var across := CHANGE_CELLS_ACROSS
	var down := maxi(1, roundi(float(across) * image.get_height() / image.get_width()))
	var small := image.duplicate() as Image
	small.resize(across, down, Image.INTERPOLATE_LANCZOS)
	var light := PackedFloat32Array()
	light.resize(across * down)
	for y in down:
		for x in across:
			light[y * across + x] = small.get_pixel(x, y).get_luminance()
	return {"across": across, "down": down, "light": light}


## How much of the picture differs between two grids of brightness taken from [area] of the window, and where, in the
## window's pixels.
func _changed(before: Dictionary, now: Dictionary, area: Rect2i) -> Dictionary:
	var was: PackedFloat32Array = before.light
	var is_now: PackedFloat32Array = now.light
	if was.size() != is_now.size():
		return {"changed": 1.0}
	var across: int = now.across
	var down: int = now.down
	var changed := 0
	var low := Vector2i(across, down)
	var high := Vector2i(-1, -1)
	for y in down:
		for x in across:
			if absf(is_now[y * across + x] - was[y * across + x]) > CHANGE_LIGHT:
				changed += 1
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	var answer := {"changed": snappedf(float(changed) / (across * down), 0.0001)}
	if changed > 0:
		var cell := Vector2(float(area.size.x) / across, float(area.size.y) / down)
		var corner := Vector2(area.position) + Vector2(low) * cell
		var extent := Vector2(high - low + Vector2i.ONE) * cell
		answer["where"] = [roundi(corner.x), roundi(corner.y), roundi(extent.x), roundi(extent.y)]
	return answer


## [number] in the top-left corner of [image], light on dark, so a frame can be named by its number.
func _number(image: Image, number: int) -> void:
	var glyph: String = DIGITS[number % 10]
	var px := clampi(floori(image.get_height() / 48.0), 2, 4)
	image.fill_rect(Rect2i(0, 0, px * 5, px * 7), Color.BLACK)
	for row in 5:
		for column in 3:
			if glyph[row * 3 + column] == "1":
				image.fill_rect(Rect2i(px * (column + 1), px * (row + 1), px, px), Color.WHITE)


## The frame as the window shows it. Input and every rectangle here use the window's pixels, and a project kept to its own
## shape draws in only part of the window.
func _on_window(image: Image) -> Image:
	var window := get_tree().root.size
	if image.get_size() == window:
		return image
	var framed := Image.create(window.x, window.y, false, image.get_format())
	framed.fill(Color.BLACK)
	framed.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(get_tree().root.get_final_transform().origin))
	return framed


# --- read -----------------------------------------------------------------------------------------------------------

func _read(params: Dictionary) -> Dictionary:
	var scene := get_tree().current_scene
	if scene == null:
		return {"error": "no_scene", "message": "The game has no current scene."}
	var op := str(params.get("op", "tree"))
	match op:
		"tree":
			var nodes: Array = []
			for node in [scene] + scene.find_children("*", "", true, false):
				if nodes.size() >= MAX_NODES:
					break
				var entry := {"path": _path(scene, node), "class": node.get_class()}
				if node is CanvasItem:
					entry["visible"] = node.is_visible_in_tree()
				if node is Node2D:
					entry["position"] = [node.global_position.x, node.global_position.y]
				nodes.append(entry)
			return {"scene": scene.scene_file_path, "nodes": nodes, "paused": not can_process(), "game_paused": get_tree().paused, "frame": _ran_frames}
		"node":
			var state := _node_state(scene, str(params.get("path", ".")))
			var wanted = params.get("properties", [])
			if state.has("error") or typeof(wanted) != TYPE_ARRAY or wanted.is_empty():
				return state
			var node := _find(scene, str(params.get("path", ".")))
			var read := {}
			for property in wanted.slice(0, 20):
				var value := _value_of(node, str(property))
				read[str(property)] = _shown(scene, value.value) if value.has("value") else value
			state["read"] = read
			return state
		"find":
			return _find_nodes(scene, params)
		"audio":
			return _audio(scene)
		"check":
			var checks = params.get("checks", [])
			if typeof(checks) != TYPE_ARRAY or checks.is_empty():
				return {"error": "missing", "message": "check needs 'checks', such as [{\"path\": \"Main/Player\", \"property\": \"is_on_floor\", \"equals\": true}]."}
			return _check(scene, checks)
		"sample":
			return await _sample(scene, params)
		"ui":
			var controls: Array = []
			for node in Array(scene.find_children("*", "Control", true, false)):
				if not node.is_visible_in_tree():
					continue
				var entry := {"path": _path(scene, node), "class": node.get_class(), "rect": _rect(_window_rect(node))}
				if "text" in node:
					entry["text"] = str(node.text)
				if "disabled" in node:
					entry["disabled"] = node.disabled
				controls.append(entry)
			return {"controls": controls, "note": "Rects are [x, y, width, height] in full_size pixels, the space input takes."}
		"watch":
			var watched := {}
			for node in get_tree().get_nodes_in_group(WATCH_GROUP):
				watched[_path(scene, node)] = node.call("_nujan_state") if node.has_method("_nujan_state") else _node_state(scene, _path(scene, node)).get("properties", {})
			return {"watched": watched, "note": "Nodes in the group nujan_watch, with their _nujan_state() when they have one."}
		"monitors":
			return {
				"fps": Performance.get_monitor(Performance.TIME_FPS),
				"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			}
		_:
			return {"error": "unknown_op", "message": "There is no op '%s'." % op, "ops": ["tree", "node", "find", "ui", "audio", "watch", "monitors", "check", "sample"]}


## What the game is sounding: each audio bus with its volume, mute and the loudest level it carried in the last frame,
## and each audio player in the running scene with whether it is playing and where. A player on a muted bus is silent.
func _audio(scene: Node) -> Dictionary:
	var buses: Array = []
	for i in AudioServer.bus_count:
		buses.append({
			"name": AudioServer.get_bus_name(i),
			"volume_db": AudioServer.get_bus_volume_db(i),
			"mute": AudioServer.is_bus_mute(i),
			"peak_db": maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0)),
		})
	var players: Array = []
	var total := 0
	for node in [scene] + scene.find_children("*", "", true, false):
		if not (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
			continue
		total += 1
		if players.size() >= MAX_NODES:
			continue
		players.append({
			"path": _path(scene, node),
			"playing": node.playing,
			"stream": node.stream.get_class() if node.stream != null else "",
			"bus": str(node.bus),
			"volume_db": node.volume_db,
			"position_s": node.get_playback_position() if node.playing else 0.0,
		})
	return {"buses": buses, "players": players, "total_players": total,
		"note": "peak_db is the loudest level a bus carried in the last frame; -200 is silence."}


## The running scene's nodes that match every filter given: `class` (an engine class, its subclasses, or a script's
## class_name), `name` (part of the name, or a pattern with * and ?), `group`, and `text` (part of a control's text);
## each with its path, class, place and text, so a node made in code is found without guessing its name.
func _find_nodes(scene: Node, params: Dictionary) -> Dictionary:
	var wanted_class := str(params.get("class", ""))
	var pattern := str(params.get("name", ""))
	var group := str(params.get("group", ""))
	var text := str(params.get("text", "")).to_lower()
	if wanted_class.is_empty() and pattern.is_empty() and group.is_empty() and text.is_empty():
		return {"error": "missing", "message": "find needs at least one of: class, name, group, text."}
	var found: Array = []
	var total := 0
	var nodes: Array = [scene] + scene.find_children("*", "", true, false)
	for node in nodes:
		if not _class_matches(node, wanted_class) or not _name_matches(node, pattern):
			continue
		if not group.is_empty() and not node.is_in_group(group):
			continue
		if not _text_matches(node, text):
			continue
		total += 1
		if found.size() >= MAX_NODES:
			continue
		var entry := {"path": _path(scene, node), "class": node.get_class()}
		if node is Node2D:
			entry["global_position"] = [node.global_position.x, node.global_position.y]
			var at := _window_rect(node).position
			entry["on_screen"] = [at.x, at.y]
		elif node is Node3D:
			entry["global_position"] = [node.global_position.x, node.global_position.y, node.global_position.z]
		elif node is Control:
			entry["rect"] = _rect(_window_rect(node))
		if "text" in node:
			entry["text"] = str(node.get("text"))
		var script = node.get_script()
		if script != null:
			entry["script"] = script.resource_path
		found.append(entry)
	var answer := {"found": found, "total": total}
	if total == 0:
		answer["note"] = _why_nothing_found(scene, nodes, wanted_class, pattern, group, text)
	return answer


func _class_matches(node: Node, wanted: String) -> bool:
	return wanted.is_empty() or node.is_class(wanted) or _has_script_class(node, wanted)


func _name_matches(node: Node, pattern: String) -> bool:
	if pattern.is_empty():
		return true
	var node_name := str(node.name)
	if pattern.contains("*") or pattern.contains("?"):
		return node_name.matchn(pattern)
	return node_name.to_lower().contains(pattern.to_lower())


func _text_matches(node: Node, text: String) -> bool:
	return text.is_empty() or ("text" in node and str(node.get("text")).to_lower().contains(text))


## Why a find came back empty: what each filter matches alone, and what the running scene is, since asking again the same way
## cannot find more.
func _why_nothing_found(scene: Node, nodes: Array, wanted_class: String, pattern: String, group: String, text: String) -> String:
	var parts: Array = []
	if not wanted_class.is_empty():
		parts.append(_alone("class '%s'" % wanted_class, nodes.filter(func(n): return _class_matches(n, wanted_class))))
	if not pattern.is_empty():
		parts.append(_alone("name '%s'" % pattern, nodes.filter(func(n): return _name_matches(n, pattern))))
	if not group.is_empty():
		parts.append(_alone("group '%s'" % group, nodes.filter(func(n): return n.is_in_group(group))))
	if not text.is_empty():
		parts.append(_alone("text '%s'" % text, nodes.filter(func(n): return _text_matches(n, text))) + " (text looks only in nodes that show text, such as Label and Button)")
	return "No node has all of these together. Alone: %s. The running scene is %s (%s) with %d nodes; game_read tree shows them. Asking again the same way will find nothing more." % ["; ".join(parts), scene.name, scene.get_class(), nodes.size()]


func _alone(what: String, matched: Array) -> String:
	var names: Array = matched.slice(0, 5).map(func(n): return str(n.name))
	return "%s matches %d%s" % [what, matched.size(), (" (%s)" % ", ".join(names)) if not names.is_empty() else ""]


func _has_script_class(node: Node, wanted: String) -> bool:
	var script = node.get_script()
	while script != null:
		if str(script.get_global_name()) == wanted:
			return true
		script = script.get_base_script()
	return false


func _node_state(scene: Node, path: String) -> Dictionary:
	var node := _find(scene, path)
	if node == null:
		return {"error": "not_found", "message": "There is no node '%s' in the running scene." % path}
	# Only what differs from the class's defaults, as the editor's scene_read shows a node.
	var properties := {}
	for property in node.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE) or property.name in ["script", "owner"]:
			continue
		var value = node.get(property.name)
		var default_value = ClassDB.class_get_property_default_value(node.get_class(), property.name)
		if typeof(value) == typeof(default_value) and value == default_value:
			continue
		properties[property.name] = _plain(value)
	var state := {"path": _path(scene, node), "class": node.get_class(), "properties": properties}
	if node is CharacterBody2D or node is CharacterBody3D:
		state["on_floor"] = node.call("is_on_floor")
		state["velocity"] = _plain(node.get("velocity"))
	if node is RigidBody2D or node is RigidBody3D:
		state["linear_velocity"] = _plain(node.get("linear_velocity"))
		state["sleeping"] = node.get("sleeping")
	if (node is Area2D or node is Area3D) and node.get("monitoring"):
		state["overlapping_bodies"] = _shown(scene, node.call("get_overlapping_bodies"))
	if node is CanvasItem:
		state["visible"] = (node as CanvasItem).is_visible_in_tree()
	return state


# --- exec -----------------------------------------------------------------------------------------------------------

func _exec(params: Dictionary) -> Dictionary:
	var code := str(params.get("code", ""))
	if code.strip_edges().is_empty():
		return {"error": "missing", "message": "exec needs 'code': the body of a function; return sends a value back."}
	var body := "\n".join(PackedStringArray(Array(code.split("\n")).map(func(line): return "\t" + line)))
	var runner_script := GDScript.new()
	runner_script.source_code = "extends RefCounted\n\n\nfunc run(tree):\n" + body + "\n"
	if runner_script.reload() != OK:
		return {"error": "does_not_compile", "message": "The code does not compile; the game's log has the line."}
	var runner = runner_script.new()
	var value = await runner.run(get_tree())
	return {"value": _plain(value)}


# --- shared ---------------------------------------------------------------------------------------------------------

func _find(scene: Node, path: String) -> Node:
	if scene == null:
		return null
	if path.is_empty() or path == "." or path == str(scene.name):
		return scene
	return scene.get_node_or_null(NodePath(path.trim_prefix(str(scene.name) + "/")))


func _path(scene: Node, node: Node) -> String:
	if node == scene:
		return str(scene.name)
	return str(scene.name) + "/" + str(scene.get_path_to(node))


func _rect(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Where [item] is drawn, in the game window's pixels (full_size, the space input steps take): a control's rectangle,
## [area] in the node's own space, or a 2D node's origin as a point. The window scales the canvas when the project
## stretches it to fit the screen.
func _window_rect(item: CanvasItem, area := Rect2()) -> Rect2:
	var to_window := get_tree().root.get_final_transform() * item.get_global_transform_with_canvas()
	if item is Control:
		area = Rect2(Vector2.ZERO, (item as Control).size)
	return Rect2(to_window * area.position, to_window.basis_xform(area.size)).abs()


## Where a touch button takes touches, in its own space: its shape, centred on its texture when the button says so, or
## its whole texture when it has no shape. Its origin is the texture's corner, which a round shape does not reach.
func _touch_area(button: TouchScreenButton) -> Rect2:
	var texture_size := button.texture_normal.get_size() if button.texture_normal != null else Vector2.ZERO
	if button.shape == null:
		return Rect2(Vector2.ZERO, texture_size)
	var area := button.shape.get_rect()
	if button.shape_centered:
		area.position += texture_size / 2
	return area
