extends Node
## Sound effects made in code, so a game has sound with no files: each is built the first time it plays, and varies a little each time.
## Use:
##   var sfx = preload("res://parts/sfx.gd").new()
##   add_child(sfx)
##   sfx.play("jump")
##   sfx.play("hit", -6.0)              # a volume in decibels
##   sfx.ambient("wind")                # a quiet bed under the game: wind, rain, cave, sea, or "" for none
## Names: click jump land step step_hard coin pickup hit hurt shoot laser explode power win lose dash swing
##        dig_soft dig_hard wood glass splash bird door alarm

const RATE := 22050
const VOICES := 10

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var _bed: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("parts_sfx")
	_rng.randomize()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_players.append(voice)
	_bed = AudioStreamPlayer.new()
	add_child(_bed)


func play(sound: String, volume_db := 0.0) -> void:
	if not _sounds.has(sound):
		_sounds[sound] = _make(sound)
	var options: Array = _sounds[sound]
	if options.is_empty():
		return
	var voice := _players[_next]
	_next = (_next + 1) % VOICES
	voice.stream = options[_rng.randi_range(0, options.size() - 1)]
	voice.volume_db = volume_db
	voice.pitch_scale = _rng.randf_range(0.94, 1.06)
	voice.play()


func ambient(bed: String, volume_db := -18.0) -> void:
	_bed.stop()
	if bed.is_empty():
		return
	_bed.stream = _bed_loop(bed)
	_bed.volume_db = volume_db
	_bed.play()


func _make(sound: String) -> Array:
	match sound:
		"click":
			return [_sweep(880.0, 660.0, 0.05, 0.22, "sine")]
		"jump":
			return [_sweep(240.0, 520.0, 0.11, 0.2, "square")]
		"land":
			return [_noise(0.09, 900.0, 0.5)]
		"step":
			return [_noise(0.07, 1300.0, 0.26), _noise(0.06, 1600.0, 0.26)]
		"step_hard":
			return [_noise(0.05, 3400.0, 0.3), _noise(0.05, 2900.0, 0.3)]
		"coin":
			return [_tones([988.0, 1319.0], 0.07, 0.24, "square")]
		"pickup":
			return [_tones([523.0, 659.0, 784.0], 0.06, 0.24, "triangle")]
		"hit":
			return [_mix(_noise_samples(0.09, 3200.0, 0.7), _sweep_samples(300.0, 90.0, 0.1, 0.5, "square"))]
		"hurt":
			return [_sweep(420.0, 110.0, 0.22, 0.3, "saw")]
		"shoot":
			return [_mix(_noise_samples(0.08, 5200.0, 0.4), _sweep_samples(900.0, 180.0, 0.12, 0.26, "square"))]
		"laser":
			return [_sweep(1600.0, 240.0, 0.16, 0.24, "saw")]
		"explode":
			return [_noise(0.65, 700.0, 1.0)]
		"power":
			return [_sweep(220.0, 1320.0, 0.4, 0.22, "triangle")]
		"win":
			return [_tones([523.0, 659.0, 784.0, 1047.0], 0.13, 0.26, "triangle")]
		"lose":
			return [_tones([392.0, 330.0, 262.0, 196.0], 0.17, 0.26, "triangle")]
		"dash":
			return [_noise(0.16, 2600.0, 0.38)]
		"swing":
			return [_noise(0.14, 1500.0, 0.34)]
		"dig_soft":
			return [_noise(0.13, 1800.0, 0.5), _noise(0.11, 2300.0, 0.5)]
		"dig_hard":
			return [_noise(0.10, 5200.0, 0.8), _noise(0.12, 4200.0, 0.8)]
		"wood":
			return [_knock(180.0, 0.12), _knock(150.0, 0.14)]
		"glass":
			return [_chime()]
		"splash":
			return [_noise(0.32, 3400.0, 0.42)]
		"bird":
			return [_bird(2600.0), _bird(3200.0), _bird(2200.0)]
		"door":
			return [_mix(_knock_samples(90.0, 0.2), _sweep_samples(70.0, 50.0, 0.3, 0.4, "sine"))]
		"alarm":
			return [_tones([880.0, 660.0, 880.0, 660.0], 0.14, 0.2, "square")]
	return []


func _wave(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var made := AudioStreamWAV.new()
	made.format = AudioStreamWAV.FORMAT_16_BITS
	made.mix_rate = RATE
	made.data = bytes
	if loop:
		made.loop_mode = AudioStreamWAV.LOOP_FORWARD
		made.loop_end = samples.size()
	return made


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> AudioStreamWAV:
	var longest := a if a.size() >= b.size() else b
	var other := b if a.size() >= b.size() else a
	var out := longest.duplicate()
	for i in other.size():
		out[i] += other[i]
	return _wave(out)


func _shape(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(phase, TAU) < PI else -1.0
		"saw":
			return fmod(phase, TAU) / PI - 1.0
		"triangle":
			return absf(fmod(phase, TAU) / PI - 1.0) * 2.0 - 1.0
	return sin(phase)


func _sweep_samples(from: float, to: float, seconds: float, gain: float, kind: String) -> PackedFloat32Array:
	var count := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var progress := float(i) / count
		phase += TAU * lerpf(from, to, progress) / RATE
		out[i] = _shape(kind, phase) * pow(1.0 - progress, 1.4) * gain
	return out


func _sweep(from: float, to: float, seconds: float, gain: float, kind: String) -> AudioStreamWAV:
	return _wave(_sweep_samples(from, to, seconds, gain, kind))


func _tones(pitches: Array, seconds: float, gain: float, kind: String) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for pitch: float in pitches:
		out.append_array(_sweep_samples(pitch, pitch, seconds, gain, kind))
	return _wave(out)


## Filtered noise with a sharp start, the body of every dig, step and blast.
func _noise_samples(seconds: float, cutoff: float, gain: float) -> PackedFloat32Array:
	var count := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var smoothing := clampf(TAU * cutoff / RATE, 0.0, 1.0)
	var low := 0.0
	var grain := 0.0
	for i in count:
		if i % 40 == 0:
			grain = _rng.randf_range(0.4, 1.0)
		low += (_rng.randf_range(-1.0, 1.0) - low) * smoothing
		out[i] = low * pow(1.0 - float(i) / count, 2.2) * gain * grain * 1.6
	return out


func _noise(seconds: float, cutoff: float, gain: float) -> AudioStreamWAV:
	return _wave(_noise_samples(seconds, cutoff, gain))


func _knock_samples(pitch: float, seconds: float) -> PackedFloat32Array:
	var count := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / RATE
		out[i] = (sin(TAU * pitch * t) * 0.7 + sin(TAU * pitch * 2.7 * t) * 0.25 + _rng.randf_range(-0.2, 0.2) * exp(-t * 90.0)) * exp(-t * 34.0) * 0.75
	return out


func _knock(pitch: float, seconds: float) -> AudioStreamWAV:
	return _wave(_knock_samples(pitch, seconds))


func _chime() -> AudioStreamWAV:
	var count := int(0.28 * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / RATE
		var ring := sin(TAU * 2100.0 * t) * 0.3 + sin(TAU * 3170.0 * t) * 0.25 + sin(TAU * 4820.0 * t) * 0.2
		out[i] = (ring + _rng.randf_range(-0.5, 0.5) * exp(-t * 60.0)) * exp(-t * 16.0) * 0.6
	return _wave(out)


func _bird(pitch: float) -> AudioStreamWAV:
	var count := int(0.42 * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var chirp := fmod(float(i) / RATE * 7.0, 1.0)
		phase += TAU * (pitch + sin(chirp * PI) * 900.0) / RATE
		out[i] = sin(phase) * sin(chirp * PI) * 0.34
	return _wave(out)


func _bed_loop(bed: String) -> AudioStreamWAV:
	var count := RATE * 5
	var out := PackedFloat32Array()
	out.resize(count)
	var smoothing := 0.028
	var gusts := 2.0
	match bed:
		"rain":
			smoothing = 0.5
			gusts = 0.0
		"cave":
			smoothing = 0.008
			gusts = 1.0
		"sea":
			smoothing = 0.06
			gusts = 1.0
	var low := 0.0
	for i in count:
		var progress := float(i) / count
		var swell := 0.55 + 0.45 * sin(progress * TAU * gusts) * sin(progress * TAU * (gusts + 1.0))
		low += (_rng.randf_range(-1.0, 1.0) - low) * smoothing
		# Fades into itself at both ends, so the loop has no seam.
		var seam := clampf(minf(progress, 1.0 - progress) * 20.0, 0.0, 1.0)
		out[i] = low * swell * seam * (1.0 if smoothing > 0.2 else 3.2)
	return _wave(out, true)
