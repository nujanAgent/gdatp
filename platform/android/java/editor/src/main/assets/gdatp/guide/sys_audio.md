# Sound and music: making effects and tunes, buses, variation, layers that follow play

`parts add sfx music` gives effects and looping music made in code, with no files. Use `audio_edit` for sounds of this game's own.

**Making it:** `audio_edit sfx` makes an effect from a preset, or from your own numbers; `audio_edit music` makes a looping tune from a mood, tempo and key. Change the numbers per game, so that it does not sound like the last one: different waves, slower slides, lower pitches. `assets` can fetch CC0 sounds from a direct address.

**Fit the world.** A paper game sounds like paper; a machine like metal. Low notes and few of them are often stronger than busy tunes. Silence with distant sounds suits horror; a game about a quiet garden does not need a chiptune at all. Decide the sound's mood in DESIGN.md, as you did the picture's.

**Buses:** make `Music` and `Effects` under `Master` (with `exec` calling `AudioServer.add_bus`, or a saved bus layout) so that each can be muted and saved in settings.
```gdscript
extends Node

@export var players := 8
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for _i in players:
		var player := AudioStreamPlayer.new()
		player.bus = "Effects"
		add_child(player)
		_pool.append(player)


func play(stream: AudioStream, volume_db := 0.0, spread := 0.1) -> void:
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - spread, 1.0 + spread)
	player.play()
```
A pool keeps one sound from cutting off the same player's previous one. An autoload lets anything call it.

**Variation:** a random pitch of 5 to 10 percent stops the machine-gun effect. Rising pitch through a combo is one of the strongest rewards.

**Positional sound:** `AudioStreamPlayer2D` and `3D` fade with distance, for off-screen threats. A distant footstep can carry a horror game.

**Music that follows play:** two or three layers of equal length, all playing, with volumes faded by game state. Calm layer always; percussion joined in during danger. Start them together, so that they stay in step. Or cross-fade between two tracks with a tween on `volume_db`. Duck the music by a few dB beneath important sounds, or during a boss's words.

**Looping:** for `audio_edit music` the file already loops cleanly. For fetched WAV or Ogg, set `loop` on the imported stream, or `loop_mode` on `AudioStreamWAV`.

**Checking without ears:** you probably cannot listen to it, so check what you can. `game_read audio` shows bus levels and players; -200 is silence, and it should rise during a sound. Test mute, restart, and scene changes for sounds that keep playing or double up. When handing over, say plainly that you did not hear it, and name what to listen for.

**Volume sanity:** keep effects at about 0 to -6 dB, and music at -12 to -18, so effects read over it. Phone speakers have almost no bass: a sound that relies on low notes needs a higher harmonic too.

**Phone starts muted?** Nothing needs doing in native builds, unlike on the web. Do not assume people have sound on: every sound needs a visual partner.
