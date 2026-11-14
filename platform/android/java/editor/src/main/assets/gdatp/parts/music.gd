extends Node
## Background music written in code: a looping piece in the mood you pick, a different tune for each number you give it.
## Use:
##   var music = preload("res://parts/music.gd").new()
##   add_child(music)
##   music.play("calm", 7)         # calm, happy, tense, dark, chip; the number picks the tune
##   music.volume_db = -16.0
##   music.stop()
## The piece is written on a worker thread, so play returns at once and the music fades in a moment later.

const RATE := 16000

## beats a minute, the scale's steps, the bar chords as steps from the root, the root as a MIDI note, what plays over them.
const MOODS := {
	"calm": {"bpm": 72, "scale": [0, 2, 4, 7, 9], "chords": [[0, 4, 7], [-3, 0, 4], [-7, -3, 0], [-5, -1, 2]], "root": 57, "arp": 0.16, "beat": 0.0, "lead": "sine"},
	"happy": {"bpm": 112, "scale": [0, 2, 4, 7, 9], "chords": [[0, 4, 7], [-5, -1, 2], [-3, 0, 4], [-7, -3, 0]], "root": 60, "arp": 0.2, "beat": 0.1, "lead": "triangle"},
	"tense": {"bpm": 124, "scale": [0, 3, 5, 6, 7, 10], "chords": [[0, 3, 7], [0, 3, 7], [-4, 0, 3], [-2, 2, 5]], "root": 50, "arp": 0.2, "beat": 0.16, "lead": "saw"},
	"dark": {"bpm": 60, "scale": [0, 1, 3, 7, 8], "chords": [[0, 3, 7], [-4, 0, 3], [1, 5, 8], [0, 3, 7]], "root": 45, "arp": 0.1, "beat": 0.0, "lead": "sine"},
	"chip": {"bpm": 138, "scale": [0, 2, 4, 5, 7, 9, 11], "chords": [[0, 4, 7], [-3, 0, 4], [-7, -3, 0], [-5, -1, 2]], "root": 60, "arp": 0.22, "beat": 0.14, "lead": "square"},
}
const BARS := 8

var volume_db := -14.0

var _player: AudioStreamPlayer
var _task := -1
var _written: AudioStreamWAV
var _lock := Mutex.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("parts_music")
	_player = AudioStreamPlayer.new()
	add_child(_player)
	set_process(false)


func play(mood := "calm", tune := 1) -> void:
	_wait_for_writer()
	_task = WorkerThreadPool.add_task(_write.bind(MOODS.get(mood, MOODS["calm"]), tune))
	set_process(true)


func stop() -> void:
	_player.stop()


func _process(_delta: float) -> void:
	_lock.lock()
	var written := _written
	_written = null
	_lock.unlock()
	if written == null:
		return
	set_process(false)
	_player.stream = written
	_player.volume_db = -40.0
	_player.play()
	create_tween().tween_property(_player, "volume_db", volume_db, 1.6)


func _exit_tree() -> void:
	_wait_for_writer()


func _wait_for_writer() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _write(mood: Dictionary, tune: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tune * 7919 + 13
	var beat_length := 60.0 / float(mood.bpm)
	var bar_length := beat_length * 4.0
	var total := int(bar_length * BARS * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var root: int = mood.root + rng.randi_range(-2, 2)
	var chords: Array = mood.chords
	var scale_steps: Array = mood.scale
	for bar in BARS:
		var chord: Array = chords[bar % chords.size()]
		var start := bar * bar_length
		for step: int in chord:
			_note(out, total, start, bar_length * 1.25, root + step, 0.075, "pad", 0.32)
		_note(out, total, start, bar_length * 0.9, root + int(chord[0]) - 12, 0.2, "sine", 0.02)
		if float(mood.beat) > 0.0:
			for beat in 4:
				_kick(out, total, start + beat * beat_length, float(mood.beat))
	var arp_note := rng.randi_range(0, scale_steps.size() - 1)
	var eighth := beat_length * 0.5
	for i in BARS * 8:
		if rng.randf() < 0.28:
			continue
		arp_note = posmod(arp_note + rng.randi_range(-2, 2), scale_steps.size())
		var octave := 12 if rng.randf() < 0.3 else 0
		_note(out, total, i * eighth, eighth * 1.8, root + 12 + int(scale_steps[arp_note]) + octave, float(mood.arp), mood.lead, 0.006)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(tanh(out[i] * 1.3) * 30000.0))
	var wave_file := AudioStreamWAV.new()
	wave_file.format = AudioStreamWAV.FORMAT_16_BITS
	wave_file.mix_rate = RATE
	wave_file.data = bytes
	wave_file.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave_file.loop_end = total
	_lock.lock()
	_written = wave_file
	_lock.unlock()


## One note added into [param out]; what runs past the end wraps to the start, so the loop has no seam.
func _note(out: PackedFloat32Array, total: int, start: float, seconds: float, midi: int, gain: float, kind: String, attack: float) -> void:
	var pitch := 440.0 * pow(2.0, (midi - 69) / 12.0)
	var first := int(start * RATE)
	var count := int(seconds * RATE)
	var turn := TAU * pitch / RATE
	var detune := turn * 1.004
	var rise := maxf(attack * RATE, 1.0)
	var phase := 0.0
	var other := 0.0
	for i in count:
		phase += turn
		var fall := 1.0 - float(i) / count
		var envelope := minf(i / rise, 1.0) * fall * fall
		var value := 0.0
		match kind:
			"pad":
				other += detune
				value = sin(phase) + sin(other) * 0.8 + sin(phase * 2.0) * 0.2
			"sine":
				value = sin(phase)
			"triangle":
				value = absf(fmod(phase, TAU) / PI - 1.0) * 2.0 - 1.0
			"square":
				value = (1.0 if fmod(phase, TAU) < PI else -1.0) * 0.6
			"saw":
				value = (fmod(phase, TAU) / PI - 1.0) * 0.6
		out[(first + i) % total] += value * envelope * gain


func _kick(out: PackedFloat32Array, total: int, start: float, gain: float) -> void:
	var first := int(start * RATE)
	var count := int(0.14 * RATE)
	var phase := 0.0
	for i in count:
		var progress := float(i) / count
		phase += TAU * lerpf(120.0, 42.0, progress) / RATE
		out[(first + i) % total] += sin(phase) * (1.0 - progress) * (1.0 - progress) * gain * 2.0
