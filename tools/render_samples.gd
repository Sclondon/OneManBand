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
	for m: int in [72, 84, 96]:
		_held("piccolo_%d" % m, m, _piccolo, 0.03, 0.004, 0.05, [[1, 0, 1.0]])
	for m: int in [48, 60, 72]:
		_held("trumpet_%d" % m, m, _trumpet, 0.035, 0.0035, 0.006, [[1, 0, 1.0]])
	for m: int in [48, 60, 72]:
		_held("accordion_%d" % m, m, _reed, 0.05, 0.0, 0.004, [[1, 0, 1.0], [1, 4, 0.8], [2, -3, 0.3]])
	for m: int in [36, 48, 60]:
		_held("tuba_%d" % m, m, _tuba, 0.06, 0.002, 0.008, [[1, 0, 1.0]])
	for m: int in [48, 60, 72]:
		_plucked("guitar_%d" % m, m)
	for m: int in [72, 84, 96]:
		_struck("bells_%d" % m, m)
	_drums()
	print("sounds rendered")
	quit()


# How strong harmonic h of a note at hz is, for each of the held instruments
func _piccolo(h: int, _hz: float) -> float:
	return [1.0, 0.38, 0.14, 0.06, 0.025, 0.01][h - 1] if h <= 6 else 0.0


func _trumpet(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -0.8) * (1.0 + 2.0 * exp(-pow((at - 1300.0) / 600.0, 2.0))) / (1.0 + pow(at / 3200.0, 4.0))


func _reed(h: int, hz: float) -> float:
	return pow(h, -0.75) * (1.0 if h % 2 == 1 else 0.6) / (1.0 + pow(h * hz / 3800.0, 3.0))


func _tuba(h: int, hz: float) -> float:
	var at := h * hz
	return pow(h, -1.3) * (1.0 + 1.5 * exp(-pow((at - 250.0) / 200.0, 2.0))) / (1.0 + pow(at / 1200.0, 2.0))


func _pitch(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


# One wave of a tone whose harmonic h has the strength amp.call(h, hz)
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
	return table


# `voices` are [times the pitch, waves more or fewer in the loop (a slow beat), loudness]
func _held(file: String, midi: int, amp: Callable, attack: float, vibrato: float, breath: float, voices: Array) -> void:
	var hz := _pitch(midi)
	var cycles := roundi(hz)
	var loop := roundi(cycles * RATE / hz)
	var pre := int(attack * RATE)
	var out := PackedFloat32Array()
	out.resize(pre + loop)
	for voice: Array in voices:
		var table := _wave(hz * voice[0], amp)
		var waves: float = cycles * voice[0] + voice[1]
		var depth := vibrato * hz / (TAU * 5.0)
		var gain: float = voice[2]
		for i in pre + loop:
			var u := float(i - pre) / loop
			var at := fposmod(waves * u + depth * sin(TAU * 5.0 * u), 1.0) * TABLE
			var k := int(at) % TABLE
			out[i] += gain * lerpf(table[k], table[(k + 1) % TABLE], at - int(at))
	var peak := _peak(out)
	var hiss := 0.0
	for i in pre + loop:
		hiss = lerpf(hiss, noise.randf_range(-1.0, 1.0), 0.3)
		var start := float(i) / pre if i < pre else 1.0
		# A puff of air as the note speaks, and a little under it all the way through
		out[i] = out[i] / peak * sin(start * PI / 2.0) + hiss * breath * (1.0 + 5.0 * (1.0 - start)) * start
	_save(file, out, 0.7, pre)


# A string: every harmonic rings, the high ones dying first
func _plucked(file: String, midi: int) -> void:
	var hz := _pitch(midi)
	var n := int(1.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for h in range(1, mini(24, int(13000.0 / hz)) + 1):
		var a := sin(PI * h * 0.18) / h
		var tone := hz * h * sqrt(1.0 + 0.00012 * h * h)
		var keep := exp(-1.0 / (RATE * 1.0 / (1.0 + 0.3 * h) * pow(220.0 / hz, 0.3)))
		var env := a
		var step := TAU * tone / RATE
		for i in n:
			out[i] += env * sin(step * i)
			env *= keep
	for i in int(0.004 * RATE):
		out[i] += noise.randf_range(-0.3, 0.3) * (1.0 - i / (0.004 * RATE))
	_fade(out, 0.002, 0.08)
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
	# Kick
	var out := _blank(0.36)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (46.0 + 115.0 * exp(-t / 0.03)) / RATE
		out[i] = sin(phase) * exp(-t / 0.11) + noise.randf_range(-0.35, 0.35) * exp(-t / 0.003)
	_fade(out, 0.0, 0.03)
	_save("drums_0", out, 0.9)
	# Snare
	out = _blank(0.3)
	var last := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var hiss := noise.randf_range(-1.0, 1.0)
		out[i] = sin(TAU * 185.0 * t) * exp(-t / 0.05) * 0.5 + sin(TAU * 330.0 * t) * exp(-t / 0.03) * 0.25 \
				+ (hiss - last * 0.6) * exp(-t / 0.07) * 0.55
		last = hiss
	_fade(out, 0.0, 0.03)
	_save("drums_1", out, 0.85)
	# Hat
	out = _blank(0.1)
	last = 0.0
	for i in out.size():
		var t := float(i) / RATE
		var hiss := noise.randf_range(-1.0, 1.0)
		out[i] = (hiss - last) * exp(-t / 0.02)
		last = hiss
	_fade(out, 0.0, 0.01)
	_save("drums_2", out, 0.5)
	# Tom
	out = _blank(0.42)
	phase = 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (98.0 + 75.0 * exp(-t / 0.05)) / RATE
		out[i] = sin(phase) * exp(-t / 0.13) + noise.randf_range(-0.2, 0.2) * exp(-t / 0.004)
	_fade(out, 0.0, 0.03)
	_save("drums_3", out, 0.85)
	# Crash
	out = _blank(1.4)
	last = 0.0
	for i in out.size():
		var t := float(i) / RATE
		var hiss := noise.randf_range(-1.0, 1.0)
		var ring := 0.0
		for hz: float in [3170.0, 4410.0, 5230.0, 6790.0]:
			ring += signf(sin(TAU * hz * t))
		out[i] = (hiss - last) * exp(-t / 0.33) + ring * 0.07 * exp(-t / 0.22)
		last = hiss
	_fade(out, 0.0, 0.2)
	_save("drums_4", out, 0.55)
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
