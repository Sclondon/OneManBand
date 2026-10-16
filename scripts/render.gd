class_name SongRender
extends RefCounted
## Plays a song into a WAV file without the game's speakers: every note of every section that has
## anything in it, in turn (as song mode plays them), through the same samples, loudness, held
## notes and release as the band (Kit, Synth). It is done a slice at a time by `work`, so that the
## game can go on while it is written (Band.export_wav); tools/render_song.gd does it all at once,
## for other games' music.
##
## A song is what Looper.to_dict() saves: {bpm, bars, muted, sections: [[a track per instrument]]},
## a note being [beat, beats long, button, note].

const RATE := 32000
const TAIL := 4.0         # seconds the last notes are given to ring on
const SLICE := 16384      # samples levelled or written out between looks at the clock

var rate := RATE
var progress := 0.0       # how much of it has been done, 0 to 1
var bytes := PackedByteArray()   # the .wav file, once `work` says it is done
var frames := 0           # how many samples long it came out
var _seamless := false
var _mix := PackedFloat32Array()
var _length := 0
var _jobs: Array = []     # [instrument, button, note, start, held], all still to do
var _count := 0
var _stage := 0           # 0 the notes, 1 finding the loudest point, 2 writing out, 3 done
var _at := 0
var _peak := 0.0
var _cache := {}


## `seamless` lays what rings on past the end over the start, so that it loops without a seam (for
## a game's music); otherwise it rings out at the end
func _init(song: Dictionary, sample_rate := RATE, seamless := false) -> void:
	rate = sample_rate
	_seamless = seamless
	var beat_time := 60.0 / float(song.get("bpm", 110.0))
	var bars := int(song.get("bars", 2))
	var muted: Array = song.get("muted", [])
	var parts: Array = []
	for section: Array in song.get("sections", []):
		if section.any(func(track: Array) -> bool: return not track.is_empty()):
			parts.append(section)
	for p in parts.size():
		var section: Array = parts[p]
		for inst in mini(section.size(), Kit.INSTRUMENTS.size()):
			if inst < muted.size() and bool(muted[inst]):
				continue
			for note: Array in section[inst]:
				if float(note[0]) >= bars * 4:
					continue
				_jobs.append([inst, int(note[2]), int(note[3]), (p * bars * 4 + float(note[0])) * beat_time, float(note[1]) * beat_time])
	_length = int(parts.size() * bars * 4 * beat_time * rate)
	_mix.resize(_length + int(TAIL * rate))
	_count = _jobs.size()


## Gets on with it for about `msec` milliseconds; true once `bytes` holds the whole file
func work(msec: int) -> bool:
	var until := Time.get_ticks_msec() + msec
	while _stage < 3 and Time.get_ticks_msec() < until:
		match _stage:
			0:
				if _jobs.is_empty():
					_close()
				else:
					var job: Array = _jobs.pop_back()
					_play(job[0], job[1], job[2], job[3], job[4])
			1:
				for i in range(_at, mini(_at + SLICE, _mix.size())):
					_peak = maxf(_peak, absf(_mix[i]))
				_at += SLICE
				if _at >= _mix.size():
					_begin_file()
			2:
				# (no louder than it can be)
				var k := 32767.0 * (0.89 / _peak if _peak > 0.89 else 1.0)
				for i in range(_at, mini(_at + SLICE, frames)):
					bytes.encode_s16(44 + i * 2, int(clampf(_mix[i] * k, -32767.0, 32767.0)))
				_at += SLICE
				if _at >= frames:
					_stage = 3
					_mix = PackedFloat32Array()
	var done := float(_count - _jobs.size()) / maxf(_count, 1)
	match _stage:
		0:
			progress = 0.8 * done
		1:
			progress = 0.8 + 0.05 * _at / maxf(_mix.size(), 1)
		2:
			progress = 0.85 + 0.15 * _at / maxf(frames, 1)
		_:
			progress = 1.0
	return _stage == 3


# Every note is in: what rings on past the end is laid over the start, or the silence after it cut off
func _close() -> void:
	if _seamless:
		for i in _mix.size() - _length:
			_mix[i] += _mix[_length + i]
		_mix.resize(_length)
	else:
		var last := _length
		for i in range(_mix.size() - 1, _length - 1, -1):
			if absf(_mix[i]) > 0.0005:
				last = i + 1
				break
		_mix.resize(last)
	_stage = 1
	_at = 0


# The head of the .wav file: plain 16 bit samples, one channel
func _begin_file() -> void:
	frames = _mix.size()
	bytes.resize(44 + frames * 2)
	bytes.encode_u32(0, 0x46464952)        # RIFF
	bytes.encode_u32(4, 36 + frames * 2)
	bytes.encode_u32(8, 0x45564157)        # WAVE
	bytes.encode_u32(12, 0x20746d66)       # fmt
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, 1)
	bytes.encode_u32(24, rate)
	bytes.encode_u32(28, rate * 2)
	bytes.encode_u16(32, 2)
	bytes.encode_u16(34, 16)
	bytes.encode_u32(36, 0x61746164)       # data
	bytes.encode_u32(40, frames * 2)
	_stage = 2
	_at = 0


## A sample as floats, at its own rate: [frames, mix_rate, loop_begin, loops]
func _sample(path: String) -> Array:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStreamWAV = load(path)
	var data := stream.data
	var floats := PackedFloat32Array()
	floats.resize(data.size() / 2)
	for i in floats.size():
		floats[i] = data.decode_s16(i * 2) / 32768.0
	var entry := [floats, stream.mix_rate, stream.loop_begin, stream.loop_mode == AudioStreamWAV.LOOP_FORWARD]
	_cache[path] = entry
	return entry


## One note into the mix: the nearest sample played faster or slower; a held instrument holds
## (looping) for as long as the note and then dies away over its release; the rest ring out
func _play(inst: int, b: int, n: int, start: float, held: float) -> void:
	var kit: Dictionary = Kit.INSTRUMENTS[inst]
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
	var wave: PackedFloat32Array = s[0]
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
	while first + i < _mix.size():
		var k := int(at)
		if k >= wave.size() - 1:
			if loops:
				at = loop_begin + fmod(at - loop_begin, wave.size() - 1 - loop_begin)
				k = int(at)
			else:
				break
		var v := lerpf(wave[k], wave[k + 1], at - k) * gain
		if i > hold:
			var gone := float(i - hold) / maxf(fade, 1)
			if gone >= 1.0:
				break
			v *= 1.0 - gone
		_mix[first + i] += v
		at += step
		i += 1
