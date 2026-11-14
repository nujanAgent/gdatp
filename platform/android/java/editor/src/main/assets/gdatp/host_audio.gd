
# --- audio_edit ------------------------------------------------------------------------------------------------------

const AUDIO_OPS := ["sfx", "music"]
const AUDIO_RATE := 22050
const AUDIO_MAX_BARS := 16
## Each effect is one voice whose pitch slides, in Hz and milliseconds. `steps` are semitones it jumps to in turn.
const SFX_PRESETS := {
	"jump": {"wave": "square", "from": 280.0, "to": 720.0, "ms": 170, "volume": 0.5},
	"land": {"wave": "noise", "from": 900.0, "to": 200.0, "ms": 90, "volume": 0.4},
	"coin": {"wave": "square", "from": 990.0, "to": 990.0, "ms": 220, "steps": [0, 7], "step_ms": 70, "volume": 0.45},
	"powerup": {"wave": "square", "from": 440.0, "to": 440.0, "ms": 420, "steps": [0, 4, 7, 12], "step_ms": 90, "volume": 0.45},
	"hit": {"wave": "saw", "from": 320.0, "to": 70.0, "ms": 220, "volume": 0.55},
	"stomp": {"wave": "square", "from": 220.0, "to": 70.0, "ms": 130, "volume": 0.55},
	"explosion": {"wave": "noise", "from": 2400.0, "to": 120.0, "ms": 520, "volume": 0.7},
	"laser": {"wave": "saw", "from": 1500.0, "to": 200.0, "ms": 180, "volume": 0.4},
	"blip": {"wave": "triangle", "from": 880.0, "to": 880.0, "ms": 70, "volume": 0.45},
	"win": {"wave": "square", "from": 523.25, "to": 523.25, "ms": 760, "steps": [0, 4, 7, 12, 7, 12], "step_ms": 125, "volume": 0.45},
	"lose": {"wave": "triangle", "from": 392.0, "to": 392.0, "ms": 800, "steps": [0, -2, -4, -7], "step_ms": 190, "volume": 0.55},
}
## Semitones above the key of each chord's root, whether it is minor, and the scale a melody walks.
const MUSIC_MOODS := {
	"happy": {"chords": [[0, false], [7, false], [9, true], [5, false]], "scale": [0, 2, 4, 7, 9], "tempo": 132},
	"calm": {"chords": [[0, false], [9, true], [5, false], [7, false]], "scale": [0, 2, 4, 7, 9], "tempo": 84},
	"tense": {"chords": [[0, true], [8, false], [3, false], [10, false]], "scale": [0, 3, 5, 7, 10], "tempo": 148},
	"dark": {"chords": [[0, true], [5, true], [0, true], [7, false]], "scale": [0, 3, 5, 6, 10], "tempo": 96},
	"heroic": {"chords": [[0, false], [5, false], [7, false], [0, false]], "scale": [0, 2, 4, 5, 7, 9], "tempo": 120},
}


## Sound with no download and no key: an effect from a preset or your own numbers, or a looping tune from a mood. Both are
## written as a WAV file in the project and imported.
func _audio_edit(args: Dictionary) -> Dictionary:
	var op := _op(args, AUDIO_OPS)
	if op.begins_with("!"):
		return _bad_op(op, AUDIO_OPS)
	var params: Dictionary = args.params
	var path := _res_path(params.get("path", ""))
	if path.begins_with("!"):
		return _fail("bad_path", path.substr(1))
	if path.get_extension().to_lower() != "wav":
		return _fail("bad_path", "path names a .wav file, such as res://audio/jump.wav.")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", hash(path)))
	var written: Dictionary
	if op == "sfx":
		written = _audio_sfx(params, rng)
	else:
		written = _audio_music(params, rng)
	if written.has("error"):
		return written
	return await _audio_save(path, written)


func _audio_sfx(params: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sound := {}
	var preset := str(params.get("preset", ""))
	if preset != "":
		if not SFX_PRESETS.has(preset):
			return _fail("bad_value", "preset is one of: %s; or leave it out and give wave, from, to and ms." % ", ".join(PackedStringArray(SFX_PRESETS.keys())))
		sound = SFX_PRESETS[preset].duplicate()
	for key in ["wave", "from", "to", "ms", "steps", "step_ms", "volume"]:
		if params.has(key):
			sound[key] = params[key]
	if not sound.has("wave") or not sound.has("from"):
		return _fail("missing", "sfx needs 'preset' (%s), or 'wave', 'from' and 'ms'." % ", ".join(PackedStringArray(SFX_PRESETS.keys())))
	var wave := str(sound.wave)
	if not wave in ["square", "triangle", "saw", "sine", "noise"]:
		return _fail("bad_value", "wave is square, triangle, saw, sine or noise.")
	var ms := clampf(float(sound.get("ms", 200)), 10.0, 4000.0)
	var samples := PackedFloat32Array()
	samples.resize(int(ms / 1000.0 * AUDIO_RATE))
	# A little difference between one effect and the next, so a game's sounds do not all come out the same.
	var detune: float = 1.0 + rng.randf_range(-0.02, 0.02) if not params.has("from") else 1.0
	var from := float(sound.from) * detune
	var to := float(sound.get("to", sound.from)) * detune
	var steps: Array = sound.get("steps", [0])
	var step_samples := maxf(1.0, float(sound.get("step_ms", ms)) / 1000.0 * AUDIO_RATE)
	var phase := 0.0
	var held := 0.0
	var volume := clampf(float(sound.get("volume", 0.5)), 0.0, 1.0)
	var count := samples.size()
	for i in count:
		var done := float(i) / count
		var step_index := mini(int(i / step_samples), steps.size() - 1)
		var hz: float = lerpf(from, to, done) * pow(2.0, float(steps[step_index]) / 12.0)
		phase = fmod(phase + hz / AUDIO_RATE, 1.0)
		if phase < hz / AUDIO_RATE:
			held = rng.randf_range(-1.0, 1.0)
		var attack := minf(1.0, i / (AUDIO_RATE * 0.002))
		samples[i] = _audio_wave(wave, phase, held) * volume * attack * pow(1.0 - done, 1.6)
	return {"samples": samples, "loop": false, "seconds": snappedf(ms / 1000.0, 0.01)}


func _audio_music(params: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var mood_name := str(params.get("mood", "happy"))
	if not MUSIC_MOODS.has(mood_name):
		return _fail("bad_value", "mood is one of: %s." % ", ".join(PackedStringArray(MUSIC_MOODS.keys())))
	var mood: Dictionary = MUSIC_MOODS[mood_name]
	var tempo := clampf(float(params.get("tempo", mood.tempo)), 50.0, 220.0)
	var bars := clampi(int(params.get("bars", 8)), 1, AUDIO_MAX_BARS)
	var root := float(params.get("key_hz", 130.81))
	var beat := 60.0 / tempo
	var length := int(bars * 4 * beat * AUDIO_RATE)
	var samples := PackedFloat32Array()
	samples.resize(length)
	var chords: Array = mood.chords
	var scale: Array = mood.scale
	var degree := 0
	for bar in bars:
		var chord: Array = chords[bar % chords.size()]
		var semitone := float(chord[0])
		var third := 3.0 if chord[1] else 4.0
		var at := bar * 4 * beat
		for b in 4:
			# Bass on each beat, up an octave on the off-beat.
			_audio_note(samples, "triangle", root * pow(2.0, semitone / 12.0), at + b * beat, beat * 0.45, 0.32)
			_audio_note(samples, "triangle", root * 2.0 * pow(2.0, semitone / 12.0), at + (b + 0.5) * beat, beat * 0.3, 0.2)
			# Off-beat hat, with the snare on two and four.
			_audio_note(samples, "noise", 7000.0, at + (b + 0.5) * beat, 0.03, 0.07)
			if b % 2 == 1:
				_audio_note(samples, "noise", 2600.0, at + b * beat, 0.09, 0.14)
			# Chord tones under the tune.
			for tone in [0.0, third, 7.0]:
				_audio_note(samples, "square", root * 2.0 * pow(2.0, (semitone + tone) / 12.0), at + b * beat + tone * 0.002, beat * 0.2, 0.045)
		# A tune that walks the scale, and comes to rest at the end of each second bar.
		var eighth := 0
		while eighth < 8:
			var run := 1 if rng.randf() < 0.6 else 2
			if rng.randf() > 0.2:
				degree = clampi(degree + rng.randi_range(-2, 2), -2, scale.size() + 2)
				var octave := int(floor(float(degree) / scale.size()))
				var pitch := float(scale[posmod(degree, scale.size())]) + 12.0 * octave
				if eighth == 6 and bar % 2 == 1:
					pitch = semitone
				_audio_note(samples, "square", root * 4.0 * pow(2.0, pitch / 12.0), at + eighth * beat / 2.0, run * beat * 0.42, 0.13)
			eighth += run
	var peak := 0.001
	for value in samples:
		peak = maxf(peak, absf(value))
	var gain := minf(1.0, 0.85 / peak)
	for i in length:
		samples[i] *= gain
	return {"samples": samples, "loop": true, "seconds": snappedf(float(length) / AUDIO_RATE, 0.01), "tempo": tempo, "bars": bars, "mood": mood_name}


func _audio_note(samples: PackedFloat32Array, wave: String, hz: float, at: float, seconds: float, volume: float) -> void:
	var start := int(at * AUDIO_RATE)
	var count := int(seconds * AUDIO_RATE)
	var phase := 0.0
	var held := 0.0
	var step := hz / AUDIO_RATE
	for i in count:
		var where := start + i
		if where >= samples.size():
			return
		phase += step
		if phase >= 1.0:
			phase -= 1.0
			held = randf_range(-1.0, 1.0)
		var attack := minf(1.0, i / 40.0)
		samples[where] += _audio_wave(wave, phase, held) * volume * attack * (1.0 - float(i) / count)


func _audio_wave(wave: String, phase: float, held: float) -> float:
	match wave:
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"triangle":
			return 4.0 * absf(phase - 0.5) - 1.0
		"saw":
			return 2.0 * phase - 1.0
		"sine":
			return sin(phase * TAU)
	return held


## 16-bit mono PCM. A tune also carries a `smpl` chunk marking its whole length as a loop, which Godot's importer reads.
func _audio_save(path: String, written: Dictionary) -> Dictionary:
	var samples: PackedFloat32Array = written.samples
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var chunk := PackedByteArray()
	if written.loop:
		chunk.resize(68)
		chunk.encode_u32(0, 0x6c706d73)  # "smpl"
		chunk.encode_u32(4, 60)
		chunk.encode_u32(16, int(1000000000.0 / AUDIO_RATE))
		chunk.encode_u32(20, 60)
		chunk.encode_u32(36, 1)
		chunk.encode_u32(52, 0)
		chunk.encode_u32(56, samples.size() - 1)
	var head := PackedByteArray()
	head.resize(44)
	head.encode_u32(0, 0x46464952)  # "RIFF"
	head.encode_u32(4, 36 + pcm.size() + chunk.size())
	head.encode_u32(8, 0x45564157)  # "WAVE"
	head.encode_u32(12, 0x20746d66)  # "fmt "
	head.encode_u32(16, 16)
	head.encode_u16(20, 1)
	head.encode_u16(22, 1)
	head.encode_u32(24, AUDIO_RATE)
	head.encode_u32(28, AUDIO_RATE * 2)
	head.encode_u16(32, 2)
	head.encode_u16(34, 16)
	head.encode_u32(36, 0x61746164)  # "data"
	head.encode_u32(40, pcm.size())
	if FileAccess.file_exists(path):
		_keep_in_trash(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("not_written", "Godot could not write %s (error %d)." % [path, FileAccess.get_open_error()])
	file.store_buffer(head + pcm + chunk)
	file.close()
	var answer := {"path": path, "seconds": written.seconds, "loops": written.loop, "imported": await _imported(path)}
	for key in ["tempo", "bars", "mood"]:
		if written.has(key):
			answer[key] = written[key]
	answer["next"] = "Play it from an AudioStreamPlayer whose stream is load(\"%s\")." % path
	return answer
