class_name Synth
extends Node
## Plays the rendered samples (tools/render_samples.gd): a pool of voices, one note each. A note
## is the nearest sample played faster or slower.

const VOICES := 28

var samples: Array[Dictionary] = []   # for each instrument, the note a sample is of -> the sample
var drums: Array[AudioStreamWAV] = []
var ticks: Array[AudioStreamWAV] = []
var voices: Array[Dictionary] = []
var next_id := 1
var sound := true:
	set(value):
		sound = value
		AudioServer.set_bus_mute(0, not sound)


func _ready() -> void:
	for kit in Kit.INSTRUMENTS:
		var set := {}
		for base: int in kit.bases:
			set[base] = load("res://sounds/%s_%d.res" % [kit.id, base])
		samples.append(set)
	for i in 5:
		drums.append(load("res://sounds/drums_%d.res" % i))
	for i in 2:
		ticks.append(load("res://sounds/tick_%d.res" % i))
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append({"player": p, "id": 0, "held": false, "release": 0.09, "fade": null})


# Starts a note and returns what to stop it by. For the drums `b` is which drum and `n` how far
# to bend it; for the rest `n` is the note.
func play(inst: int, b: int, n: int, loud := 1.0) -> int:
	var kit := Kit.INSTRUMENTS[inst]
	var stream: AudioStreamWAV
	var pitch := 1.0
	if Kit.is_drums(inst):
		stream = drums[posmod(b, 5)]
		pitch = pow(2.0, n / 12.0)
	else:
		var base: int = kit.bases[0]
		for other: int in kit.bases:
			if absi(n - other) < absi(n - base):
				base = other
		stream = samples[inst][base]
		pitch = pow(2.0, (n - base) / 12.0)
	var v := _voice()
	var p: AudioStreamPlayer = v.player
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = kit.db + linear_to_db(loud)
	p.play()
	v.id = next_id
	v.held = kit.held
	v.release = kit.get("release", 0.09)
	next_id += 1
	return v.id


func stop(id: int) -> void:
	for v in voices:
		if v.id == id and v.held:
			var p: AudioStreamPlayer = v.player
			v.id = 0
			v.fade = create_tween()
			v.fade.tween_property(p, "volume_db", -60.0, v.release)
			v.fade.tween_callback(p.stop)
			return


func tick(bar: bool) -> void:
	var v := _voice()
	v.player.stream = ticks[0 if bar else 1]
	v.player.pitch_scale = 1.0
	v.player.volume_db = -8.0
	v.player.play()
	v.id = 0
	v.held = false


func hush() -> void:
	for v in voices:
		if v.held and v.id != 0:
			stop(v.id)


# One that is silent, or else the one that has been sounding longest
func _voice() -> Dictionary:
	var best: Dictionary = voices[0]
	for v in voices:
		if not v.player.playing:
			best = v
			break
		if v.id < best.id:
			best = v
	if best.fade != null:
		best.fade.kill()
		best.fade = null
	return best
