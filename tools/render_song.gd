extends SceneTree
## Plays a One Man Band song into a WAV file, without the game running: every note of every section
## that has anything in it, in turn (as song mode plays them), through the same samples, loudness,
## held notes and release as the band (Kit, Synth). What rings on past the end is laid over the
## start, so the file loops without a seam. Other games use it to take their music from here.
##   godot --headless --path . -s tools/render_song.gd -- <song.json> <out.wav> [rate]
## A song is what Looper.to_dict() saves: {bpm, bars, sections: [[a track per instrument]]}, a
## note being [beat, beats long, button, note].

const RATE := 32000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("render_song: <song.json> <out.wav> [rate]")
		quit(1)
		return
	var song: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var rate := int(args[2]) if args.size() > 2 else RATE
	var out := _render(song, rate)
	_save(out, rate, args[1])
	print("rendered %s: %.1f s" % [args[1], out.size() / float(rate)])
	quit()


var _cache := {}


## A sample as floats, at its own rate: [frames, mix_rate, loop_begin, loops]
func _sample(path: String) -> Array:
	if _cache.has(path):
		return _cache[path]
	var wav: AudioStreamWAV = load(path)
	var data := wav.data
	var frames := PackedFloat32Array()
	frames.resize(data.size() / 2)
	for i in frames.size():
		frames[i] = data.decode_s16(i * 2) / 32768.0
	var entry := [frames, wav.mix_rate, wav.loop_begin, wav.loop_mode == AudioStreamWAV.LOOP_FORWARD]
	_cache[path] = entry
	return entry


func _render(song: Dictionary, rate: int) -> PackedFloat32Array:
	var bpm := float(song.get("bpm", 110.0))
	var bars := int(song.get("bars", 2))
	var beat_time := 60.0 / bpm
	var parts: Array = []
	for section: Array in song.get("sections", []):
		var any := false
		for track: Array in section:
			any = any or not track.is_empty()
		if any:
			parts.append(section)
	var length := int(parts.size() * bars * 4 * beat_time * rate)
	var tail := rate * 4
	var mix := PackedFloat32Array()
	mix.resize(length + tail)
	var muted: Array = song.get("muted", [])
	for p in parts.size():
		var section: Array = parts[p]
		for inst in mini(section.size(), Kit.INSTRUMENTS.size()):
			if inst < muted.size() and bool(muted[inst]):
				continue
			var kit: Dictionary = Kit.INSTRUMENTS[inst]
			for note: Array in section[inst]:
				var start := (p * bars * 4 + float(note[0])) * beat_time
				var held := float(note[1]) * beat_time
				_play(mix, rate, kit, inst, int(note[2]), int(note[3]), start, held)
	# What rings on past the end comes round to the start
	for i in tail:
		mix[i] += mix[length + i]
	mix.resize(length)
	var peak := 0.0
	for v in mix:
		peak = maxf(peak, absf(v))
	if peak > 0.89:
		for i in mix.size():
			mix[i] *= 0.89 / peak
	return mix


## One note into the mix: the nearest sample played faster or slower; a held instrument holds
## (looping) for as long as the note and then dies away over its release; the rest ring out
func _play(mix: PackedFloat32Array, rate: int, kit: Dictionary, inst: int, b: int, n: int, start: float, held: float) -> void:
	var path: String
	var pitch := 1.0
	if Kit.is_drums(inst):
		path = "res://sounds/drums_%d.res" % Kit.drum(b, n)
		pitch = pow(2.0, Kit.drum_bend(n) / 12.0)
	else:
		var base: int = kit.bases[0]
		for other: int in kit.bases:
			if absi(n - other) < absi(n - base):
				base = other
		path = "res://sounds/%s_%d.res" % [kit.id, base]
		pitch = pow(2.0, (n - base) / 12.0)
	var s := _sample(path)
	var frames: PackedFloat32Array = s[0]
	var step := pitch * float(s[1]) / rate
	var loop_begin := float(s[2])
	var loops: bool = s[3] and kit.held
	var gain := db_to_linear(float(kit.db))
	var release := float(kit.get("release", 0.09))
	var first := int(start * rate)
	var hold := int(held * rate) if kit.held else 1 << 30
	var fade := int(release * rate)
	var at := 0.0
	var i := 0
	while first + i < mix.size():
		var k := int(at)
		if k >= frames.size() - 1:
			if loops:
				at = loop_begin + fmod(at - loop_begin, frames.size() - 1 - loop_begin)
				k = int(at)
			else:
				break
		var v := lerpf(frames[k], frames[k + 1], at - k) * gain
		if i > hold:
			var gone := float(i - hold) / maxf(fade, 1)
			if gone >= 1.0:
				break
			v *= 1.0 - gone
		mix[first + i] += v
		at += step
		i += 1


func _save(mix: PackedFloat32Array, rate: int, path: String) -> void:
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i in mix.size():
		data.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(path)
