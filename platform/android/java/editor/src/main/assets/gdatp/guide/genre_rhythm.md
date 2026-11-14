# Rhythm games: the audio clock, charts, timing windows and latency

**Never time by frames or by a `Timer`.** The song is the clock. Read its position from the audio engine, and correct for what has not reached the speaker yet.

```gdscript
extends Node

@export var player: AudioStreamPlayer
@export var bpm := 120.0
@export var offset_seconds := 0.0


func song_time() -> float:
	var heard := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	return heard - AudioServer.get_output_latency() + offset_seconds


func beat() -> float:
	return song_time() * bpm / 60.0
```

**The chart is data:** a list of beats and lanes. Notes are drawn from it, each placed by `(note_beat - beat()) * pixels_per_beat`, so they stay in time even when frames drop.

**Timing windows:** Perfect within ±45 ms, Good within ±90 ms, Miss beyond. Judge against the time of the press event. Phones have more latency than consoles, so widen by a little and always offer a calibration screen: tap along with a click and store the mean error in `offset_seconds`, saved in settings. Bluetooth headphones add a lot.

**Making music and charts together:** `audio_edit music` writes a looping tune from a mood and tempo, and it reports the tempo. Chart it by the bar: patterns of 1, 2 and 4 bars that repeat and vary. Start with quarter notes only, adding eighths only in later sections. Follow what can be heard, since notes that land on nothing feel wrong. Layer several stems and switch them on as the player does well: a strong reward that makes a person feel they are playing the music.

**Feedback is all on the beat:** the whole world pulses: background, camera, characters bob by `beat()` fraction. A hit gives a burst, a judgement word and rising combo; a miss dims or removes a layer, instead of playing a harsh sound on top of the music.

**Forgiving structure:** a health meter that refills, so one mistake does not end a song. Difficulty by more notes rather than tighter windows.

**Touch:** whole-screen zones rather than small buttons; 2 to 4 lanes are plenty on a phone. Use the press event's moment rather than the release. Lanes reaching the thumbs. Portrait suits falling notes.

**Beyond falling notes:** a rhythm game is any game where acting on the beat matters: attacks that land harder on the beat, dungeon moves on the beat, a chef chopping to it, a duel of call and response. Make the world act in time with the song.

**Make it yours.** A verb with its own natural beat: rowing, hammering, marching, knitting, conducting a tiny orchestra, a heart that must keep pace.
