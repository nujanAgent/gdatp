
# --- animation_edit --------------------------------------------------------------------------------------------------

const ANIMATION_OPS := ["frames_from_sheet", "player_add", "clip_create", "track_add", "preset", "clip_remove", "read"]
const ANIMATION_PRESETS := ["bob", "pulse", "spin", "fade_in", "fade_out", "blink", "shake"]
const LOOP_MODES := {"none": Animation.LOOP_NONE, "linear": Animation.LOOP_LINEAR, "pingpong": Animation.LOOP_PINGPONG}
const INTERPOLATIONS := {"linear": Animation.INTERPOLATION_LINEAR, "nearest": Animation.INTERPOLATION_NEAREST, "cubic": Animation.INTERPOLATION_CUBIC}


## Animation: SpriteFrames cut from a sprite sheet for an AnimatedSprite2D or 3D, and AnimationPlayer clips built from
## value tracks and keys or from ready-made motions. Each change to the open scene is one undo step.
func _animation_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, ANIMATION_OPS)
	if op.begins_with("!"):
		return _bad_op(op, ANIMATION_OPS)
	var params: Dictionary = args.params
	var root = _scene_root(params)
	if root is Dictionary:
		return root
	match op:
		"frames_from_sheet":
			return _frames_from_sheet(root, params)
		"player_add":
			return _player_add(root, params)
		"read":
			return _animation_read(root, params)
		_:
			return _clip_change(root, op, params)


## SpriteFrames from a sheet of equal frames: each animation takes a row, a run of frames, or a list of frame numbers
## counted left to right, top to bottom.
func _frames_from_sheet(root: Node, params: Dictionary) -> Dictionary:
	var found = _node_param(root, params, "node", ["AnimatedSprite2D", "AnimatedSprite3D"])
	if found is Dictionary:
		return found
	var node: Node = found
	var texture_path := _res_path(params.get("texture", ""))
	if texture_path.begins_with("!") or not ResourceLoader.exists(texture_path, "Texture2D"):
		return _fail("not_found", "There is no image %s." % str(params.get("texture", "")), {"next": "files_edit write puts a sprite sheet in the project."})
	var texture := load(texture_path) as Texture2D
	var frame = _cell(params.get("frame_size", null))
	var grid = _cell(params.get("grid", null))
	if frame == null and grid != null and grid.x > 0 and grid.y > 0:
		frame = Vector2i(texture.get_width() / grid.x, texture.get_height() / grid.y)
	if frame == null or frame.x < 1 or frame.y < 1:
		return _fail("missing", "frames_from_sheet needs 'frame_size': [width, height] in pixels, or 'grid': [columns, rows].")
	var columns: int = texture.get_width() / frame.x
	var rows: int = texture.get_height() / frame.y
	var specs = params.get("animations", [])
	if typeof(specs) != TYPE_ARRAY or specs.is_empty():
		return _fail("missing", "frames_from_sheet needs 'animations': [{\"name\": \"run\", \"row\": 0, \"fps\": 10}].")
	var frames := SpriteFrames.new()
	var names: Array = specs.map(func(spec): return str(spec.get("name", "")) if typeof(spec) == TYPE_DICTIONARY else "")
	if not names.has("default"):
		frames.remove_animation("default")
	var made := {}
	for spec in specs:
		var clip_name := str(spec.get("name", "")) if typeof(spec) == TYPE_DICTIONARY else ""
		if clip_name.is_empty():
			return _fail("bad_animation", "Each animation is {\"name\": …, \"row\": n} or {\"name\": …, \"frames\": [numbers]}.")
		var indexes: Array = []
		if typeof(spec.get("frames", null)) == TYPE_ARRAY:
			indexes = spec.frames.map(func(i): return int(i))
		elif spec.has("row"):
			var first := int(spec.get("from", 0))
			var last := int(spec.get("to", columns - 1))
			indexes = range(first, last + 1).map(func(column): return int(spec.row) * columns + column)
		else:
			indexes = range(int(spec.get("from", 0)), int(spec.get("to", columns * rows - 1)) + 1)
		if not frames.has_animation(clip_name):
			frames.add_animation(clip_name)
		frames.set_animation_speed(clip_name, float(spec.get("fps", 8)))
		frames.set_animation_loop(clip_name, _flag(spec.get("loop", true)))
		for index in indexes:
			if index < 0 or index >= columns * rows:
				return _fail("bad_frame", "Frame %d is outside the sheet's %d frames (%d columns, %d rows)." % [index, columns * rows, columns, rows])
			var piece := AtlasTexture.new()
			piece.atlas = texture
			piece.region = Rect2(Vector2((index % columns) * frame.x, (index / columns) * frame.y), Vector2(frame))
			frames.add_frame(clip_name, piece)
		made[clip_name] = indexes.size()
	var first_name: String = names[0]
	var autoplay := str(params.get("play", first_name))
	var steps: Array = []
	_set_step(node, "sprite_frames", frames, steps)
	_set_step(node, "animation", StringName(autoplay if frames.has_animation(autoplay) else first_name), steps)
	_set_step(node, "autoplay", autoplay if frames.has_animation(autoplay) else "", steps)
	var answer := _commit_steps(root, steps, params)
	answer["animations"] = made
	answer["frame_size"] = _plain(frame)
	answer["sheet"] = {"columns": columns, "rows": rows}
	answer["next"] = "run play shows it moving; animation_edit read lists the animations."
	return answer


func _player_add(root: Node, params: Dictionary) -> Dictionary:
	var parent = _node_param(root, params, "parent")
	if parent is Dictionary:
		return parent
	var player := AnimationPlayer.new()
	player.name = str(params.get("name", "AnimationPlayer"))
	player.add_animation_library("", AnimationLibrary.new())
	var steps: Array = []
	_add_step(root, parent, player, steps)
	var answer := _commit_steps(root, steps, params)
	answer["next"] = "animation_edit clip_create, track_add or preset with player %s." % _node_path(player)
	return answer


## Clip changes work on a copy of the player's library, which the undo step swaps in and out whole.
func _clip_change(root: Node, op: String, params: Dictionary) -> Dictionary:
	var found = _node_param(root, params, "player", ["AnimationPlayer"])
	if found is Dictionary:
		return found
	var player := found as AnimationPlayer
	var old_library: AnimationLibrary = player.get_animation_library("") if player.has_animation_library("") else null
	var library: AnimationLibrary = old_library.duplicate(true) if old_library else AnimationLibrary.new()
	var clip := str(params.get("clip", params.get("kind", "") if op == "preset" else ""))
	if clip.is_empty():
		return _fail("missing", "%s needs 'clip', the animation's name." % op)
	var changed := {}
	match op:
		"clip_create":
			if library.has_animation(clip) and not _flag(params.get("replace", false)):
				return _fail("exists", "The player already has a clip %s." % clip, {"next": "Repeat with replace: true, or track_add adds to it."})
			var made = _new_clip(float(params.get("length", 1.0)), str(params.get("loop", "none")))
			if made is Dictionary:
				return made
			if library.has_animation(clip):
				library.remove_animation(clip)
			library.add_animation(clip, made)
			changed = {"clip": clip, "length": made.length}
		"track_add":
			if not library.has_animation(clip):
				return _fail("not_found", "The player has no clip %s." % clip, {"clips": Array(library.get_animation_list())})
			var track := _add_track(player, library.get_animation(clip), params)
			if track.has("error"):
				return track
			changed = track
		"preset":
			var built := _preset_clip(player, params)
			if built.has("error"):
				return built
			if library.has_animation(clip):
				library.remove_animation(clip)
			library.add_animation(clip, built.clip)
			changed = {"clip": clip, "preset": str(params.get("kind", "")), "tracks": built.tracks}
		"clip_remove":
			if not library.has_animation(clip):
				return _fail("not_found", "The player has no clip %s." % clip, {"clips": Array(library.get_animation_list())})
			library.remove_animation(clip)
			changed = {"removed": clip}
	var swap_in := func():
		if player.has_animation_library(""):
			player.remove_animation_library("")
		player.add_animation_library("", library)
	var swap_out := func():
		player.remove_animation_library("")
		if old_library:
			player.add_animation_library("", old_library)
	var steps: Array = [{"do": swap_in, "undo": swap_out, "text": "%s %s" % [op, clip]}]
	swap_in.call()
	if _flag(params.get("autoplay", false)) and op != "clip_remove":
		_set_step(player, "autoplay", clip, steps)
	var answer := _commit_steps(root, steps, params)
	answer.merge(changed)
	answer["next"] = "animation_edit read shows the clips; run play plays the autoplay clip."
	return answer


func _new_clip(length: float, loop: String):
	if not LOOP_MODES.has(loop):
		return _fail("bad_value", "loop is one of: %s." % ", ".join(PackedStringArray(LOOP_MODES.keys())))
	if length <= 0.0:
		return _fail("bad_value", "length is a time in seconds above 0.")
	var clip := Animation.new()
	clip.length = length
	clip.loop_mode = LOOP_MODES[loop]
	return clip


## A value track on [clip] for `path` ("Node:property", from the player's root node), with its keys typed to the
## property: {"time": 0.5, "value": …}.
func _add_track(player: AnimationPlayer, clip: Animation, params: Dictionary) -> Dictionary:
	var track_path := str(params.get("path", ""))
	if not track_path.contains(":"):
		return _fail("bad_path", "A track's 'path' is \"Node:property\", from the player's root node, such as \"Coin:position\".")
	var base := player.get_node_or_null(player.root_node)
	var node_part := track_path.left(track_path.find(":"))
	var property := track_path.substr(track_path.find(":") + 1)
	var target = base.get_node_or_null(NodePath(node_part)) if base else null
	if target == null:
		return _fail("not_found", "No node %s under the player's root node %s." % [node_part, str(player.root_node)])
	var keys = params.get("keys", [])
	if typeof(keys) != TYPE_ARRAY or keys.is_empty():
		return _fail("missing", "track_add needs 'keys': [{\"time\": 0, \"value\": …}].")
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, NodePath(track_path))
	var interpolation := str(params.get("interpolation", "linear"))
	clip.track_set_interpolation_type(track, INTERPOLATIONS.get(interpolation, Animation.INTERPOLATION_LINEAR))
	if str(params.get("update", "continuous")) == "discrete":
		clip.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for key in keys:
		if typeof(key) != TYPE_DICTIONARY or not key.has("time"):
			return _fail("bad_key", "Each key is {\"time\": seconds, \"value\": …}.")
		var value := _typed_indexed(target, property, key.get("value")) if property.contains(":") else _typed_for(target, property, key.get("value"))
		if value.has("error"):
			return value
		clip.track_insert_key(track, float(key.time), value.value)
	if clip.length < float(keys[keys.size() - 1].get("time", 0)):
		clip.length = float(keys[keys.size() - 1].time)
	return {"track": track, "path": track_path, "keys": keys.size()}


## A ready-made motion on `target` as a clip of value tracks: bob, pulse, spin, fade_in, fade_out, blink or shake.
func _preset_clip(player: AnimationPlayer, params: Dictionary) -> Dictionary:
	var kind := str(params.get("kind", ""))
	if not ANIMATION_PRESETS.has(kind):
		return _fail("bad_value", "kind is one of: %s." % ", ".join(PackedStringArray(ANIMATION_PRESETS)), {"did_you_mean": _nearest(kind, ANIMATION_PRESETS)})
	var base := player.get_node_or_null(player.root_node)
	var target = base.get_node_or_null(NodePath(str(params.get("target", "")))) if base else null
	if target == null:
		return _fail("not_found", "No node %s under the player's root node; 'target' is a path from there." % str(params.get("target", "")))
	var duration := float(params.get("duration", 1.0 if kind in ["bob", "pulse", "spin", "blink"] else 0.5))
	var amount := float(params.get("amount", 0.0))
	var in_3d := target is Node3D
	var path := str(base.get_path_to(target))
	var clip := Animation.new()
	clip.length = duration
	var keys := {}
	match kind:
		"bob":
			var lift := amount if amount > 0.0 else (0.25 if in_3d else 8.0)
			var y: float = target.position.y
			keys[path + ":position:y"] = [[0.0, y], [duration / 2.0, y + (lift if in_3d else -lift)], [duration, y]]
			clip.loop_mode = Animation.LOOP_LINEAR
		"pulse":
			var grow := amount if amount > 0.0 else 1.15
			var scale = target.scale
			keys[path + ":scale"] = [[0.0, scale], [duration / 2.0, scale * grow], [duration, scale]]
			clip.loop_mode = Animation.LOOP_LINEAR
		"spin":
			if in_3d:
				var start: float = target.rotation.y
				keys[path + ":rotation:y"] = [[0.0, start], [duration, start + TAU]]
			else:
				var start: float = target.rotation
				keys[path + ":rotation"] = [[0.0, start], [duration, start + TAU]]
			clip.loop_mode = Animation.LOOP_LINEAR
		"fade_in", "fade_out":
			if not target is CanvasItem:
				return _fail("wrong_node", "Fades change modulate, which 2D nodes and controls have; %s is a %s." % [target.name, target.get_class()])
			keys[path + ":modulate:a"] = [[0.0, 0.0], [duration, 1.0]] if kind == "fade_in" else [[0.0, 1.0], [duration, 0.0]]
		"blink":
			keys[path + ":visible"] = [[0.0, true], [duration / 2.0, false]]
			clip.loop_mode = Animation.LOOP_LINEAR
		"shake":
			var shift := amount if amount > 0.0 else (0.1 if in_3d else 4.0)
			var at = target.position
			var offset = Vector3(shift, 0, 0) if in_3d else Vector2(shift, 0)
			var step := duration / 6.0
			keys[path + ":position"] = [[0.0, at], [step, at + offset], [step * 2, at - offset], [step * 3, at + offset * 0.5], [step * 4, at - offset * 0.5], [duration, at]]
	for track_path in keys:
		var track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track, NodePath(track_path))
		if kind == "blink":
			clip.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
		for key in keys[track_path]:
			clip.track_insert_key(track, key[0], key[1])
	return {"clip": clip, "tracks": keys.keys()}


func _animation_read(root: Node, params: Dictionary) -> Dictionary:
	var found = _node_param(root, params, "player", ["AnimationPlayer", "AnimatedSprite2D", "AnimatedSprite3D"])
	if found is Dictionary:
		return found
	var node = found
	if node is AnimationPlayer:
		var clips: Array = []
		for clip_name in node.get_animation_list():
			var clip: Animation = node.get_animation(clip_name)
			var tracks: Array = []
			for track in clip.get_track_count():
				var keys: Array = []
				for key in min(clip.track_get_key_count(track), 20):
					keys.append({"time": snappedf(clip.track_get_key_time(track, key), 0.001), "value": _plain(clip.track_get_key_value(track, key))})
				tracks.append({"path": str(clip.track_get_path(track)), "keys": keys})
			clips.append({"name": str(clip_name), "length": clip.length, "loop": LOOP_MODES.find_key(clip.loop_mode), "tracks": tracks})
		return {"player": _node_path(node), "autoplay": node.autoplay, "root_node": str(node.root_node), "clips": clips}
	var frames: SpriteFrames = node.sprite_frames
	if frames == null:
		return {"node": _node_path(node), "animations": [], "next": "animation_edit frames_from_sheet gives it frames."}
	var animations: Array = []
	for anim_name in frames.get_animation_names():
		animations.append({"name": anim_name, "frames": frames.get_frame_count(anim_name), "fps": frames.get_animation_speed(anim_name), "loop": frames.get_animation_loop(anim_name)})
	return {"node": _node_path(node), "autoplay": node.autoplay, "animations": animations}
