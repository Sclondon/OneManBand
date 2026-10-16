extends SceneTree
## Renders every sound in the game to sounds/*.res, so nothing has to be synthesised while it loads.
## godot --headless --path . -s tools/render_samples.gd
##
## Held instruments (piccolo, trumpet, accordion, tuba) are an attack and then a loop of exactly a
## whole number of waves, so they can be held for ever without a click. The rest ring out.

const RATE := 32000
const TABLE := 2048

var noise := RandomNumberGenerator.new()


func _initialize() -> void:
	noise.seed = 1987
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sounds"))
	# Each held instrument has its own way of starting a note and its own colour once it is going:
	#   attack   seconds to speak
	#   scoop    semitones off the note it starts from, sliding in over the attack
	#   bright   a second set of harmonics it starts on and melts out of
	#   vib/rate how far (as a part of the pitch) and how fast (a second) it wobbles
	#   breath   air, bow or reed noise under it
	#   voices   [times the pitch, waves more or fewer in the loop (a slow beat), loudness]
	for m: int in [72, 84, 96]:
		_held("piccolo_%d" % m, m, _piccolo, {"attack": 0.03, "scoop": 0.4, "vib": 0.006, "rate": 7, "breath": 0.11})
	for m: int in [48, 60, 72]:
		_held("trumpet_%d" % m, m, _trumpet, {"attack": 0.06, "scoop": -1.2, "bright": _trumpet_blare, "vib": 0.003, "rate": 5, "breath": 0.004})
	for m: int in [48, 60, 72, 84]:
		_held("accordion_%d" % m, m, _reed, {"attack": 0.07, "breath": 0.004, "voices": [[1, 0, 1.0], [1, 8, 0.85], [1, -7, 0.7], [2, -3, 0.3]]})
	for m: int in [36, 48, 60]:
		_held("tuba_%d" % m, m, _tuba, {"attack": 0.1, "scoop": -0.5, "vib": 0.001, "rate": 4, "breath": 0.012})
	for m: int in [48, 60, 72]:
		_held("organ_%d" % m, m, _organ, {"attack": 0.035, "bright": _organ_chiff, "breath": 0.02, "voices": [[1, 0, 1.0], [1, 2, 0.5], [2, -1, 0.25]]})
	for m: int in [60, 72, 84]:
		_held("theremin_%d" % m, m, _theremin, {"attack": 0.2, "scoop": -3.5, "vib": 0.018, "rate": 5})
	for m: int in [48, 60, 72]:
		_held("viola_%d" % m, m, _viola, {"attack": 0.15, "scoop": -0.2, "vib": 0.006, "rate": 6, "breath": 0.045})
	for m: int in range(48, 85, 4):
		_sung("choir_%d" % m, m)
	for m: int in [36, 48, 60]:
		_held("bassoon_%d" % m, m, _bassoon, {"attack": 0.05, "scoop": -0.3, "vib": 0.003, "rate": 5, "breath": 0.012})
	for m: int in [48, 60, 72]:
		_plucked("guitar_%d" % m, m, 2.4, 0.12, 1.4)
	for m: int in [72, 84, 96]:
		_struck("bells_%d" % m, m)
	_drums()
	# (after the drums, so that theirs is the same noise as it always was)
	for m: int in [48, 60, 72, 84]:
		_plucked("ukulele_%d" % m, m, 1.2, 0.3, 0.45)
	for m: int in [28, 40, 52, 64, 76, 88]:
		_held("electric_%d" % m, m, _overdrive, {"attack": 0.03, "bright": _pick, "vib": 0.003, "rate": 6, "breath": 0.006,
				"voices": [[1, 0, 1.0], [1, 3, 0.6], [2, -2, 0.25]]})
	for m: int in [24, 36, 48, 60, 72, 84, 96]:
		_hammered("piano_%d" % m, m)
	_percussion()
	print("sounds rendered")
	quit()


# How strong harmonic h of a note at hz is, for each of the held instruments

# A flute's: nearly all in the first two
func _piccolo(h: int, _hz: float) -> float:
	return [1.0, 0.38, 0.14, 0.06, 0.025, 0.01][h - 1] if h <= 6 else 0.0


# Brass: a hump round 1300 Hz
func _trumpet(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -0.8) * (1.0 + 2.0 * exp(-pow((at - 1300.0) / 600.0, 2.0))) / (1.0 + pow(at / 3200.0, 4.0))


# (and the rasp it starts with)
func _trumpet_blare(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -0.35) * (1.0 + 2.0 * exp(-pow((at - 2200.0) / 900.0, 2.0))) / (1.0 + pow(at / 5500.0, 4.0))


# Reeds: odd harmonics, and a nasal hump round 2000 Hz
func _reed(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -0.6) * (1.0 if h % 2 == 1 else 0.35) * (1.0 + 1.5 * exp(-pow((at - 2000.0) / 600.0, 2.0))) / (1.0 + pow(at / 4200.0, 3.0))


# Dark and round
func _tuba(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -1.3) * (1.0 + 1.5 * exp(-pow((at - 250.0) / 200.0, 2.0))) / (1.0 + pow(at / 1200.0, 2.0))


# A little pipe organ with its stops out: the note, its octaves and the fifths between them,
# as so many ranks of pipes sounding together
func _organ(h: int, hz: float) -> float:
	var ranks := {1: 1.0, 2: 0.8, 3: 0.45, 4: 0.5, 6: 0.22, 8: 0.25, 12: 0.08, 16: 0.08}
	return float(ranks.get(h, 0.02 if h < 12 else 0.0)) / (1.0 + pow(h * hz / 6000.0, 4.0))


# (the puff of high wind as a pipe starts to speak)
func _organ_chiff(h: int, hz: float) -> float:
	var at := h * hz
	return _organ(h, hz) * 0.6 + 0.5 * exp(-pow((at - 3200.0) / 1200.0, 2.0)) / sqrt(h)


# A double reed down a long wooden tube: dry and woody, with humps round 480 and 1150 Hz
func _bassoon(h: int, hz: float) -> float:
	var at := h * hz
	var tube := 0.45 + 1.7 * exp(-pow((at - 480.0) / 200.0, 2.0)) + 0.8 * exp(-pow((at - 1150.0) / 300.0, 2.0))
	return pow(h, -0.7) * tube / (1.0 + pow(at / 3000.0, 3.0))


# The choir: seven small voices that are not quite together. Each has a head of its own size
# (so its mouth's humps lie a little higher or lower), a vowel of its own between "oh" and
# "ah", a wobble at its own speed, a pitch a hair off the others', and comes in when it is
# ready. Two seconds go round, long enough that they never seem to repeat.
func _sung(file: String, midi: int) -> void:
	var hz := _pitch(midi)
	var seconds := 2.0
	var cycles := roundi(hz * seconds)
	var loop := roundi(cycles * RATE / hz)
	var pre := int(0.3 * RATE)
	var out := PackedFloat32Array()
	out.resize(pre + loop)
	for s in 7:
		var size := 0.93 + 0.025 * s
		var open := float(s % 3) / 2.0
		var table := _wave(hz, func(h: int, f: float) -> float: return _mouth(h, f, size, open))
		var waves := float(cycles + [0, 2, -2, 3, -3, 1, -1][s])
		var rate := float([9, 11, 10, 12, 9, 11, 10][s])
		var depth := (0.004 + 0.0012 * (s % 4)) * hz * seconds / (TAU * rate)
		var turn := s * 0.9
		var late := 0.02 * ((s * 3) % 7)
		for i in pre + loop:
			var u := float(i - pre) / loop
			var phase := waves * u + depth * sin(TAU * rate * u + turn)
			var at := fposmod(phase, 1.0) * TABLE
			var k := int(at) % TABLE
			var v := lerpf(table[k], table[(k + 1) % TABLE], at - int(at))
			var come := clampf((float(i) / RATE - late) / 0.16, 0.0, 1.0) if i < pre else 1.0
			var swell := 1.0 + 0.15 * sin(TAU * (1 + s % 3) * u + turn * 2.0)
			out[i] += v * swell * sin(come * PI / 2.0)
	var peak := _peak(out)
	var air := 0.0
	for i in pre + loop:
		air = lerpf(air, noise.randf_range(-1.0, 1.0), 0.18)
		out[i] = out[i] / peak + air * 0.035 * minf(1.0, float(i) / (0.1 * RATE))
	_save(file, out, 0.7, pre)


# How loud harmonic h of a sung note is: a voice's own falling-away, strong at the bottom, and
# the humps of the mouth it comes out of
func _mouth(h: int, hz: float, size: float, open: float) -> float:
	var at := h * hz / size
	var f1 := lerpf(620.0, 980.0, open)
	var f2 := lerpf(1050.0, 1450.0, open)
	var humps := 0.07 + 0.3 / (1.0 + pow(at / 450.0, 2.0)) + exp(-pow((at - f1) / 140.0, 2.0)) \
			+ 0.6 * exp(-pow((at - f2) / 170.0, 2.0)) + 0.22 * exp(-pow((at - 3200.0) / 380.0, 2.0))
	return pow(h, -1.3) * humps / (1.0 + pow(at / 6000.0, 4.0))


# Almost a pure tone
func _theremin(h: int, _hz: float) -> float:
	return [1.0, 0.13, 0.05, 0.012][h - 1] if h <= 4 else 0.0


# A bowed string, with the three humps a viola's body gives it
func _viola(h: int, hz: float) -> float:
	var at := h * hz
	var body := 0.45 + 1.6 * exp(-pow((at - 380.0) / 160.0, 2.0)) + 1.2 * exp(-pow((at - 1100.0) / 300.0, 2.0)) + 0.7 * exp(-pow((at - 2600.0) / 500.0, 2.0))
	return (1.0 / h) * body / (1.0 + pow(at / 4500.0, 3.0))


# An electric guitar through an amplifier turned up too far: every harmonic, falling away slowly,
# a honk in the middle, and the top cut off where the speaker gives out
func _overdrive(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -0.55) * (1.0 + 1.2 * exp(-pow((at - 850.0) / 450.0, 2.0))) / (1.0 + pow(at / 3600.0, 4.0))


# (and the pick's scrape as it starts)
func _pick(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -0.3) * (1.0 + 1.5 * exp(-pow((at - 2600.0) / 900.0, 2.0))) / (1.0 + pow(at / 6000.0, 4.0))


func _pitch(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


# One wave of a tone whose harmonic h has the strength amp.call(h, hz), as loud as it will go
func _wave(hz: float, amp: Callable) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(TABLE)
	var count := mini(28, int(13500.0 / hz))
	for h in range(1, count + 1):
		var a: float = amp.call(h, hz)
		if a <= 0.0005:
			continue
		for i in TABLE:
			table[i] += a * sin(TAU * h * i / TABLE)
	var peak := _peak(table)
	for i in TABLE:
		table[i] /= peak
	return table


func _held(file: String, midi: int, amp: Callable, how: Dictionary) -> void:
	var attack: float = how.get("attack", 0.04)
	var scoop: float = how.get("scoop", 0.0)
	var vibrato: float = how.get("vib", 0.0)
	var rate: float = how.get("rate", 5)
	var breath: float = how.get("breath", 0.0)
	var bright: Callable = how.get("bright", Callable())
	var voices: Array = how.get("voices", [[1, 0, 1.0]])
	var hz := _pitch(midi)
	var cycles := roundi(hz)
	var loop := roundi(cycles * RATE / hz)
	var pre := int(attack * RATE)
	var out := PackedFloat32Array()
	out.resize(pre + loop)
	for voice: Array in voices:
		var table := _wave(hz * voice[0], amp)
		var sharp := _wave(hz * voice[0], bright) if bright.is_valid() else table
		var waves: float = cycles * voice[0] + voice[1]
		var depth := vibrato * hz / (TAU * rate)
		var gain: float = voice[2]
		# Where in its wave it is through the attack, worked back from where the loop begins,
		# so that a note that slides in arrives exactly on it
		var before := PackedFloat32Array()
		before.resize(pre + 1)
		for i in range(pre - 1, -1, -1):
			var left := 1.0 - float(i) / pre
			before[i] = before[i + 1] - waves / loop * pow(2.0, scoop * left * left / 12.0)
		for i in pre + loop:
			var u := float(i - pre) / loop
			var phase := before[i] if i < pre else waves * u + depth * sin(TAU * rate * u)
			var at := fposmod(phase, 1.0) * TABLE
			var k := int(at) % TABLE
			var v := lerpf(table[k], table[(k + 1) % TABLE], at - int(at))
			if i < pre and bright.is_valid():
				v = lerpf(lerpf(sharp[k], sharp[(k + 1) % TABLE], at - int(at)), v, float(i) / pre)
			out[i] += gain * v
	var peak := _peak(out)
	var hiss := 0.0
	for i in pre + loop:
		hiss = lerpf(hiss, noise.randf_range(-1.0, 1.0), 0.3)
		var start := float(i) / pre if i < pre else 1.0
		# A puff of air as the note speaks, and a little under it all the way through
		out[i] = out[i] / peak * sin(start * PI / 2.0) + hiss * breath * (1.0 + 5.0 * (1.0 - start)) * start
	_save(file, out, 0.7, pre)


# A string: every harmonic rings, the high ones dying first. `where` is how far along the string
# it is plucked (nearer the middle is rounder), `ring` how long it rings for.
func _plucked(file: String, midi: int, seconds := 1.9, where := 0.18, ring := 1.0) -> void:
	var hz := _pitch(midi)
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for h in range(1, mini(24, int(13000.0 / hz)) + 1):
		var a := sin(PI * h * where) / h
		var tone := hz * h * sqrt(1.0 + 0.00012 * h * h)
		var keep := exp(-1.0 / (RATE * ring / (1.0 + 0.3 * h) * pow(220.0 / hz, 0.3)))
		var env := a
		var step := TAU * tone / RATE
		for i in n:
			out[i] += env * sin(step * i)
			env *= keep
	for i in int(0.004 * RATE):
		out[i] += noise.randf_range(-0.3, 0.3) * (1.0 - i / (0.004 * RATE))
	_fade(out, 0.002, 0.08)
	_save(file, out, 0.75)


# A piano note: a felt hammer on three strings not quite in tune with each other (so the note
# swims a little as it dies), struck an eighth of the way along; it dies fast at first and then
# slowly, the high harmonics first, and the low notes ring the longest. The game damps it when
# the key comes up.
func _hammered(file: String, midi: int) -> void:
	var hz := _pitch(midi)
	var seconds := clampf(5.0 - (midi - 36) * 0.05, 2.0, 5.5)
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# (the low strings are stiffer for their length: their harmonics run sharper)
	var stiff := 0.0004 * pow(2.0, (midi - 60) / 24.0)
	var hard := clampf((midi - 30) / 60.0, 0.0, 1.0)
	for h in range(1, mini(30, int(12000.0 / hz)) + 1):
		var a := absf(sin(PI * h / 8.0)) / pow(h, 1.1 - 0.3 * hard)
		var tone := hz * h * sqrt(1.0 + stiff * h * h)
		var ring := 3.2 * pow(130.0 / hz, 0.45) / (1.0 + 0.12 * h * h * hz / 500.0)
		var quick := exp(-1.0 / (RATE * ring * 0.18))
		var slow := exp(-1.0 / (RATE * ring))
		# (only the low harmonics are worth three strings: the swimming is not heard in the rest)
		var strings := 3 if h <= 6 else 1
		for s in strings:
			var step: float = TAU * tone * (1.0 + [0.0, 0.0011, -0.0008][s]) / RATE
			var fast := a * 0.6 / strings
			var long := a * 0.4 / strings
			var turn := s * 1.7 + h
			for i in n:
				out[i] += (fast + long) * sin(step * i + turn)
				fast *= quick
				long *= slow
	# The thump of the hammer, and its felt on the string
	for i in int(0.03 * RATE):
		var t := float(i) / RATE
		out[i] += (noise.randf_range(-1.0, 1.0) * 0.25 * exp(-t / 0.004) + sin(TAU * 70.0 * t) * 0.2 * exp(-t / 0.02)) * 0.5
	_fade(out, 0.001, 0.3)
	_save(file, out, 0.75)


# A little bar of metal: a few partials that are not in tune with each other
func _struck(file: String, midi: int) -> void:
	var hz := _pitch(midi)
	var n := int(1.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var parts := [[1.0, 1.0, 0.8], [2.756, 0.42, 0.4], [5.404, 0.2, 0.16], [8.933, 0.07, 0.07]]
	for part: Array in parts:
		if hz * part[0] > 14000.0:
			continue
		var keep := exp(-1.0 / (RATE * part[2] * pow(1046.0 / hz, 0.35)))
		var env: float = part[1]
		var step: float = TAU * hz * part[0] / RATE
		for i in n:
			out[i] += env * sin(step * i)
			env *= keep
	_fade(out, 0.001, 0.1)
	_save(file, out, 0.6)


func _drums() -> void:
	# Three kits of five, in the order of Kit.DRUM_NAMES. The trap set:
	_save("drums_0", _room(_thump(0.42, 150.0, 47.0, 0.028, 0.16, 0.5, 1.6)), 0.92)    # Kick
	_save("drums_1", _room(_snare(0.36, 190.0, 0.09, 0.16)), 0.86)                     # Snare
	_save("drums_2", _metal(0.12, 0.028, 7000.0, 0.5), 0.5)                            # Hat
	_save("drums_3", _room(_thump(0.5, 190.0, 108.0, 0.06, 0.2, 0.25, 1.2)), 0.85)     # Tom
	_save("drums_4", _cymbal(1.8, 0.55, 1.0), 0.55)                                    # Crash
	# The big low ones:
	_save("drums_5", _room(_thump(0.9, 95.0, 36.0, 0.06, 0.38, 0.2, 1.3), 0.3), 0.95)  # Boom
	_save("drums_6", _rim(), 0.8)                                                      # Rim
	_save("drums_7", _metal(0.6, 0.22, 6000.0, 0.6), 0.45)                             # Open (hat)
	_save("drums_8", _room(_thump(0.7, 120.0, 66.0, 0.07, 0.3, 0.22, 1.2)), 0.9)       # Floor (tom)
	_save("drums_9", _ride(), 0.5)                                                     # Ride
	# The toys:
	_save("drums_10", _room(_clap()), 0.8)                                             # Clap
	_save("drums_11", _block(), 0.8)                                                   # Block
	_save("drums_12", _shake(), 0.5)                                                   # Shake
	_save("drums_13", _cowbell(), 0.6)                                                 # Bell
	_save("drums_14", _cymbal(0.7, 0.2, 1.5), 0.5)                                     # Splash
	var out: PackedFloat32Array
	# The metronome: a high tick for the bar and a lower one for the other beats
	for k in 2:
		out = _blank(0.04)
		for i in out.size():
			var t := float(i) / RATE
			out[i] = sin(TAU * (1760.0 if k == 0 else 1175.0) * t) * exp(-t / 0.007)
		_save("tick_%d" % k, out, 0.6)


func _blank(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


func _peak(out: PackedFloat32Array) -> float:
	var peak := 0.0001
	for v in out:
		peak = maxf(peak, absf(v))
	return peak


func _fade(out: PackedFloat32Array, start: float, end: float) -> void:
	var a := int(start * RATE)
	var b := int(end * RATE)
	for i in a:
		out[i] *= float(i) / a
	for i in b:
		out[out.size() - 1 - i] *= float(i) / b


func _save(file: String, out: PackedFloat32Array, level: float, loop_from := -1) -> void:
	var peak := _peak(out)
	var data := PackedByteArray()
	data.resize(out.size() * 2)
	for i in out.size():
		data.encode_s16(i * 2, int(clampf(out[i] / peak * level, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop_from >= 0:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = loop_from
		wav.loop_end = out.size()
	ResourceSaver.save(wav, "res://sounds/%s.res" % file)


# --- The hand percussion ----------------------------------------------------------------
# Three kits of five, in the order of Kit.PERCUSSION_NAMES: shaken and scraped, skins, bright things

func _percussion() -> void:
	_save("percussion_0", _guiro(), 0.75)                                                    # Guiro
	_save("percussion_1", _cuica(520.0, 0.42), 0.7)                                          # Cuica
	_save("percussion_2", _tambourine(), 0.6)                                                # Tambourine
	_save("percussion_3", _maracas(), 0.55)                                                  # Maracas
	_save("percussion_4", _agogo(), 0.6)                                                     # Agogo
	_save("percussion_5", _room(_thump(0.55, 250.0, 196.0, 0.012, 0.22, 0.35, 1.15)), 0.85)  # Conga
	_save("percussion_6", _room(_thump(0.25, 440.0, 392.0, 0.008, 0.09, 0.45, 1.2)), 0.8)    # Bongo
	_save("percussion_7", _room(_thump(1.1, 105.0, 58.0, 0.03, 0.5, 0.25, 1.5), 0.25), 0.95) # Surdo
	_save("percussion_8", _timbale(), 0.75)                                                  # Timbale
	_save("percussion_9", _cajon(), 0.85)                                                    # Cajon
	_save("percussion_10", _claves(), 0.75)                                                  # Claves
	_save("percussion_11", _triangle(), 0.5)                                                 # Triangle
	_save("percussion_12", _vibraslap(), 0.6)                                                # Vibraslap
	_save("percussion_13", _whistle(), 0.5)                                                  # Whistle
	_save("percussion_14", _chimes(), 0.5)                                                   # Chimes


# A stick drawn down the ridges of a gourd: a run of little ticks, quickening and then slowing,
# each one a knock of hollow wood
func _guiro() -> PackedFloat32Array:
	var out := _blank(0.42)
	var at := 0.0
	while at < 0.34:
		var start := int(at * RATE)
		var hz := 1700.0 + 500.0 * sin(at * 9.0)
		for i in range(start, mini(start + int(0.012 * RATE), out.size())):
			var t := float(i - start) / RATE
			out[i] += (noise.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * hz * t)) * exp(-t / 0.0025) * (0.6 + 0.4 * sin(at * 9.0))
		at += 0.009 + 0.006 * absf(cos(at * 9.0))
	_high(out, 900.0)
	_low(out, 6000.0)
	_fade(out, 0.0, 0.03)
	return out


# A friction drum, a stick rubbed inside it: a voice that whoops up and falls back, nasal
func _cuica(hz: float, seconds: float) -> PackedFloat32Array:
	var out := _blank(seconds)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var u := t / seconds
		var f := hz * (1.0 + 0.55 * sin(PI * minf(u * 1.4, 1.0)) - 0.15 * u)
		phase += TAU * f / RATE
		var loud := minf(1.0, t / 0.015) * (1.0 - u) * (1.0 - u * 0.5)
		out[i] = (sin(phase) + 0.45 * sin(phase * 2.0) + 0.25 * sin(phase * 3.0) + 0.12 * sin(phase * 4.0)) * loud
	_fade(out, 0.0, 0.04)
	return out


# A tambourine struck: the skin's thump and the jingles clashing and ringing on
func _tambourine() -> PackedFloat32Array:
	var out := _blank(0.5)
	var jingles := _blank(0.5)
	for i in out.size():
		var t := float(i) / RATE
		var ring := 0.0
		for hz: float in [5200.0, 6100.0, 7300.0, 8600.0, 9900.0]:
			ring += signf(sin(TAU * hz * t + hz))
		jingles[i] = (ring / 5.0 * 0.5 + noise.randf_range(-1.0, 1.0) * 0.6) * (exp(-t / 0.13) + 0.5 * exp(-t / 0.02))
		out[i] = sin(TAU * 210.0 * t) * 0.6 * exp(-t / 0.03)
	_high(jingles, 4000.0)
	for i in out.size():
		out[i] += jingles[i]
	_fade(out, 0.0, 0.08)
	return out


# Seeds thrown against the shell of a gourd: a soft swish and a hard rattle on the end of it
func _maracas() -> PackedFloat32Array:
	var out := _blank(0.14)
	for i in out.size():
		var t := float(i) / RATE
		var loud := minf(1.0, t / 0.03) * 0.35 + (exp(-(t - 0.04) / 0.018) if t >= 0.04 else 0.0)
		out[i] = noise.randf_range(-1.0, 1.0) * loud
	_high(out, 5000.0)
	_high(out, 5000.0)
	_fade(out, 0.0, 0.03)
	return out


# The high bell of an agogo: two partials that do not agree, ringing a while
func _agogo() -> PackedFloat32Array:
	var out := _blank(0.5)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = (sin(TAU * 930.0 * t) + 0.5 * sin(TAU * 2480.0 * t) * exp(-t / 0.06) + 0.25 * sin(TAU * 4170.0 * t) * exp(-t / 0.03)) \
				* (exp(-t / 0.16) + 0.4 * exp(-t / 0.01)) + noise.randf_range(-1.0, 1.0) * 0.3 * exp(-t / 0.0015)
	_fade(out, 0.0, 0.06)
	return out


# A timbale: a high, tight skin in a steel shell that rings on after it
func _timbale() -> PackedFloat32Array:
	var out := _thump(0.6, 420.0, 340.0, 0.01, 0.12, 0.6, 1.2)
	for i in out.size():
		var t := float(i) / RATE
		out[i] += (sin(TAU * 1170.0 * t) * 0.3 + sin(TAU * 1890.0 * t) * 0.2 + sin(TAU * 3020.0 * t) * 0.12) * exp(-t / 0.22)
	return _room(out)


# A wooden box sat on and slapped: a low boom and the wires inside it buzzing
func _cajon() -> PackedFloat32Array:
	var out := _thump(0.4, 150.0, 82.0, 0.012, 0.11, 0.6, 1.4)
	var wires := _snare(0.4, 300.0, 0.01, 0.07)
	for i in out.size():
		out[i] += wires[i] * 0.35
	return _room(out)


# Two sticks of hard wood knocked together
func _claves() -> PackedFloat32Array:
	var out := _blank(0.16)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = sin(TAU * 2480.0 * t) * exp(-t / 0.035) + 0.3 * sin(TAU * 6810.0 * t) * exp(-t / 0.008)
	_fade(out, 0.0, 0.03)
	return out


# A steel triangle: many high partials, out of tune with each other, ringing a long time
func _triangle() -> PackedFloat32Array:
	var out := _blank(1.6)
	var parts := [[1830.0, 1.0, 0.9], [4930.0, 0.5, 0.6], [6720.0, 0.4, 0.5], [8410.0, 0.3, 0.35], [10150.0, 0.2, 0.25], [11900.0, 0.12, 0.2]]
	for i in out.size():
		var t := float(i) / RATE
		var v := 0.0
		for part: Array in parts:
			v += sin(TAU * float(part[0]) * t) * float(part[1]) * exp(-t / float(part[2]))
		out[i] = v + noise.randf_range(-1.0, 1.0) * 0.4 * exp(-t / 0.001)
	_fade(out, 0.0, 0.3)
	return out


# A vibraslap: a wooden ball knocks the box of loose teeth, and they rattle on, slowing
func _vibraslap() -> PackedFloat32Array:
	var out := _blank(0.9)
	var at := 0.0
	var gap := 0.022
	while at < 0.82:
		var start := int(at * RATE)
		var loud := exp(-at / 0.3)
		for i in range(start, mini(start + int(0.02 * RATE), out.size())):
			var t := float(i - start) / RATE
			out[i] += (sin(TAU * 2900.0 * t) + 0.6 * sin(TAU * 4400.0 * t) + noise.randf_range(-0.5, 0.5)) * exp(-t / 0.004) * loud
		at += gap
		gap *= 1.04
	_high(out, 1500.0)
	_fade(out, 0.0, 0.08)
	return out


# A samba whistle, blown hard: a shrill note with the pea in it trilling
func _whistle() -> PackedFloat32Array:
	var out := _blank(0.42)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var f := 2750.0 * (1.0 + 0.035 * sin(TAU * 26.0 * t))
		phase += TAU * f / RATE
		var loud := minf(1.0, t / 0.02) * (1.0 - smoothstep(0.32, 0.42, t))
		out[i] = (sin(phase) + 0.12 * sin(phase * 2.0)) * loud * (0.8 + 0.2 * sin(TAU * 26.0 * t)) + noise.randf_range(-1.0, 1.0) * 0.1 * loud
	return out


# A mark tree: a hand drawn along a row of little hanging rods, each pinging a little higher
func _chimes() -> PackedFloat32Array:
	var out := _blank(1.7)
	for k in 14:
		var start := int((k * 0.045 + noise.randf_range(0.0, 0.01)) * RATE)
		var hz := 2800.0 * pow(2.0, k / 9.0)
		for i in range(start, out.size()):
			var t := float(i - start) / RATE
			var over := 0.3 * sin(TAU * hz * 2.76 * t) * exp(-t / 0.08) if hz * 2.76 < 15000.0 else 0.0
			out[i] += (sin(TAU * hz * t) + over) * exp(-t / 0.45) * 0.4
	_fade(out, 0.0, 0.3)
	return out


# --- What the drums are made of ---------------------------------------------------------

# A drum with a skin: a tone that falls from one pitch to another as it dies, the stick's
# click on the front of it, and all of it pushed a little into the red so it has some weight
func _thump(seconds: float, from_hz: float, to_hz: float, drop: float, ring: float, click: float, drive: float) -> PackedFloat32Array:
	var out := _blank(seconds)
	var phase := 0.0
	var last := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (to_hz + (from_hz - to_hz) * exp(-t / drop)) / RATE
		var hiss := noise.randf_range(-1.0, 1.0)
		var body := sin(phase) + 0.25 * sin(phase * 1.5 + 0.4) * exp(-t / (ring * 0.4))
		out[i] = tanh((body * exp(-t / ring) + (hiss - last) * click * exp(-t / 0.004)) * drive)
		last = hiss
	_fade(out, 0.0, 0.04)
	return out


# A snare: two notes of its skin, and the wires under it, which crack and then rattle on
func _snare(seconds: float, hz: float, skin_ring: float, wire_ring: float) -> PackedFloat32Array:
	var out := _blank(seconds)
	var phase := 0.0
	var low := 0.0
	var last := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (hz + 60.0 * exp(-t / 0.012)) / RATE
		var hiss := noise.randf_range(-1.0, 1.0)
		low += (hiss - low) * 0.55
		var wires := low - last * 0.85
		last = low
		var skin := sin(phase) * 0.6 + sin(phase * 1.78) * 0.3
		out[i] = tanh((skin * exp(-t / skin_ring) + wires * 1.6 * (0.7 * exp(-t / wire_ring) + 0.3 * exp(-t / (wire_ring * 0.25)))
				+ hiss * 0.5 * exp(-t / 0.002)) * 1.5)
	_fade(out, 0.0, 0.04)
	return out


# Hi-hats: six square waves that do not agree with each other, and hiss, with the bottom taken off
func _metal(seconds: float, ring: float, cut_hz: float, hiss_part: float) -> PackedFloat32Array:
	var out := _blank(seconds)
	for i in out.size():
		var t := float(i) / RATE
		var sum := 0.0
		for hz: float in [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]:
			sum += signf(sin(TAU * hz * 1.9 * t + hz))
		out[i] = (sum / 6.0 + noise.randf_range(-1.0, 1.0) * hiss_part) * (exp(-t / ring) + 0.4 * exp(-t / (ring * 0.2)))
	_high(out, cut_hz)
	_high(out, cut_hz)
	_fade(out, 0.0, minf(0.03, seconds * 0.3))
	return out


# A cymbal struck on its edge: a wash of hiss with a shimmer of high clashing tones in it
func _cymbal(seconds: float, ring: float, bright: float) -> PackedFloat32Array:
	var out := _blank(seconds)
	for i in out.size():
		var t := float(i) / RATE
		var shimmer := 0.0
		for hz: float in [2350.0, 3170.0, 4410.0, 5230.0, 6790.0, 8110.0]:
			shimmer += signf(sin(TAU * hz * bright * t + hz))
		out[i] = noise.randf_range(-1.0, 1.0) * (0.7 * exp(-t / ring) + 0.3 * exp(-t / (ring * 0.15))) \
				+ shimmer / 6.0 * 0.55 * exp(-t / (ring * 0.7))
	_high(out, 3000.0 * bright)
	_fade(out, 0.0, seconds * 0.25)
	return out


# A ride cymbal: the ping of the stick's tip, clear, over a little wash
func _ride() -> PackedFloat32Array:
	var out := _blank(1.2)
	var wash := _blank(1.2)
	for i in out.size():
		var t := float(i) / RATE
		var ping := 0.0
		var k := 1.0
		for hz: float in [1470.0, 2210.0, 3180.0, 4370.0, 5600.0]:
			ping += sin(TAU * hz * t) / k
			k += 0.6
		out[i] = ping * 0.5 * exp(-t / 0.4) + noise.randf_range(-1.0, 1.0) * 0.6 * exp(-t / 0.001)
		wash[i] = noise.randf_range(-1.0, 1.0) * 0.4 * exp(-t / 0.3)
	_high(wash, 5000.0)
	for i in out.size():
		out[i] += wash[i]
	_fade(out, 0.0, 0.3)
	return out


# The stick laid across the snare's rim: a dry knock
func _rim() -> PackedFloat32Array:
	var out := _blank(0.1)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = sin(TAU * 1750.0 * t) * exp(-t / 0.012) + sin(TAU * 520.0 * t) * 0.6 * exp(-t / 0.02) \
				+ noise.randf_range(-1.0, 1.0) * 0.6 * exp(-t / 0.002)
	_fade(out, 0.0, 0.02)
	return out


# Hands: three claps not quite together, and the room after them
func _clap() -> PackedFloat32Array:
	var out := _blank(0.34)
	for i in out.size():
		var t := float(i) / RATE
		var loud := 0.0
		for at: float in [0.0, 0.011, 0.022]:
			if t >= at:
				loud += exp(-(t - at) / 0.006)
		if t >= 0.03:
			loud += 0.7 * exp(-(t - 0.03) / 0.085)
		out[i] = noise.randf_range(-1.0, 1.0) * loud
	_high(out, 800.0)
	_low(out, 3400.0)
	_fade(out, 0.0, 0.05)
	return out


# A woodblock
func _block() -> PackedFloat32Array:
	var out := _blank(0.14)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = sin(TAU * 920.0 * t) * exp(-t / 0.03) + 0.4 * sin(TAU * 2390.0 * t) * exp(-t / 0.015) \
				+ noise.randf_range(-1.0, 1.0) * 0.3 * exp(-t / 0.0015)
	_fade(out, 0.0, 0.03)
	return out


# A tambourine shaken once: the jingles swell, clash, and rattle to a stop
func _shake() -> PackedFloat32Array:
	var out := _blank(0.32)
	for i in out.size():
		var t := float(i) / RATE
		var jingle := 0.0
		for hz: float in [6100.0, 7300.0, 8900.0, 10300.0]:
			jingle += signf(sin(TAU * hz * t + hz))
		var loud := (1.0 - exp(-t / 0.008)) * exp(-t / 0.07) + (0.5 * exp(-(t - 0.06) / 0.05) if t >= 0.06 else 0.0)
		out[i] = (jingle / 4.0 * 0.6 + noise.randf_range(-1.0, 1.0)) * loud
	_high(out, 5000.0)
	_fade(out, 0.0, 0.06)
	return out


# A cowbell: two square waves a fifth or so apart, through a tin box
func _cowbell() -> PackedFloat32Array:
	var out := _blank(0.45)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = (signf(sin(TAU * 540.0 * t)) + signf(sin(TAU * 800.0 * t))) * (exp(-t / 0.12) + 0.6 * exp(-t / 0.012))
	_high(out, 500.0)
	_low(out, 3600.0)
	_fade(out, 0.0, 0.08)
	return out


# A small wooden room round a drum: a few early echoes off its walls
func _room(out: PackedFloat32Array, wet := 0.18) -> PackedFloat32Array:
	var dry := out.duplicate()
	for tap: Array in [[0.013, 1.0], [0.019, -0.8], [0.029, 0.6], [0.041, -0.45], [0.058, 0.3]]:
		var shift := int(float(tap[0]) * RATE)
		for i in range(shift, out.size()):
			out[i] += dry[i - shift] * float(tap[1]) * wet
	return out


# Takes off what is below `hz` (gently: once through is 6 dB an octave)
func _high(out: PackedFloat32Array, hz: float) -> void:
	var a := exp(-TAU * hz / RATE)
	var was_in := 0.0
	var was_out := 0.0
	for i in out.size():
		var now := out[i]
		was_out = a * (was_out + now - was_in)
		was_in = now
		out[i] = was_out


# Takes off what is above `hz`
func _low(out: PackedFloat32Array, hz: float) -> void:
	var a := 1.0 - exp(-TAU * hz / RATE)
	var held := 0.0
	for i in out.size():
		held += (out[i] - held) * a
		out[i] = held
