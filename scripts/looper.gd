class_name Looper
extends Node
## The loop station. A song is four sections; a section is a track for each instrument; a track
## is notes placed on a loop of so many bars. While it records, whatever is played goes on the
## track of the instrument it was played on, over what is already there.
##
## A note is {t: beat it starts on, d: beats it lasts, b: button (or -1), n: note}.

signal note_on(inst: int, b: int, n: int)   # one played by the loop
signal beat(index: int)
signal changed

const SECTIONS := 4
const BEATS := 4
const BAR_CHOICES := [1, 2, 4, 8]
const SNAPS := [0.25, 0.5, 0.0]
const UNDO_DEPTH := 30

var synth: Synth
var bpm := 110.0
var bars := 2
var snap := 0.25          # beats; 0 leaves notes where they were played
var metronome := false
var chain := false        # go on to the next section with anything in it each time round
var playing := false
var recording := false
var counting := false     # the bar of ticks before a recording starts
var pos := 0.0
var section := 0
var queued := -1
var muted: Array[bool] = []
var sections: Array = []

var _count := 0.0
var _counted := 0
var _open := {}           # notes still held down: token -> note
var _sounding: Array = [] # [voice, beats it has left]
var _undo: Array = []
var _snapped := {}        # instruments already saved for undo this time round
var _token := 0


func _init() -> void:
	wipe()


func wipe() -> void:
	sections.clear()
	for s in SECTIONS:
		var tracks := []
		for i in Kit.INSTRUMENTS.size():
			tracks.append([])
		sections.append(tracks)
	muted.clear()
	for i in Kit.INSTRUMENTS.size():
		muted.append(false)
	_undo.clear()
	_open.clear()
	section = 0
	queued = -1


func length() -> float:
	return float(bars * BEATS)


# How far through the beat it is, or -1 at a standstill
func beat_phase() -> float:
	if counting:
		return fposmod(_count, 1.0)
	return fposmod(pos, 1.0) if playing else -1.0


func track(inst: int) -> Array:
	return sections[section][inst]


func has_notes(s: int, inst: int) -> bool:
	return not sections[s][inst].is_empty()


func section_empty(s: int) -> bool:
	for t: Array in sections[s]:
		if not t.is_empty():
			return false
	return true


func song_empty() -> bool:
	for s in SECTIONS:
		if not section_empty(s):
			return false
	return true


func toggle_play() -> void:
	if playing or counting:
		stop()
	else:
		start()


func start() -> void:
	playing = true
	counting = false
	pos = 0.0
	changed.emit()


func stop() -> void:
	playing = false
	recording = false
	counting = false
	pos = 0.0
	_close_open()
	for s: Array in _sounding:
		synth.stop(s[0])
	_sounding.clear()
	_end_take()
	if queued >= 0:
		section = queued
		queued = -1
	changed.emit()


# From a standstill this counts a bar in first
func toggle_record() -> void:
	if recording:
		recording = false
		if counting:
			counting = false
		_close_open()
	else:
		recording = true
		if not playing:
			counting = true
			_count = 0.0
			_counted = 0
	_end_take()
	changed.emit()


func go_to(s: int) -> void:
	if s == section:
		queued = -1
	elif playing:
		queued = s
	else:
		section = s
	changed.emit()


func set_bars(count: int) -> void:
	# Going up to twice as long plays what was there twice, so it sounds the same until changed
	if count == bars * 2:
		var old := length()
		for tracks: Array in sections:
			for t: Array in tracks:
				for note: Dictionary in t.duplicate():
					if note.t < old:
						var again := note.duplicate()
						again.t += old
						t.append(again)
					else:
						t.erase(note)
	bars = count
	if pos >= length():
		pos = fmod(pos, length())
	changed.emit()


func next_bars() -> void:
	set_bars(BAR_CHOICES[(BAR_CHOICES.find(bars) + 1) % BAR_CHOICES.size()])


func next_snap() -> void:
	snap = SNAPS[(SNAPS.find(snap) + 1) % SNAPS.size()]
	changed.emit()


func clear_track(inst: int) -> void:
	if track(inst).is_empty():
		return
	_snapshot(inst)
	track(inst).clear()
	changed.emit()


# --- Step entry: notes written in at a cursor, as a sequencer takes them from a keyboard --------

# A note written in on beat `t`, `d` beats long, in place of the same note if it is there already.
# Everything written in until end_chord is taken back by one undo.
func place(inst: int, t: float, d: float, b: int, n: int) -> void:
	if not _snapped.has(inst):
		_snapshot(inst)
		_snapped[inst] = true
	var notes := track(inst)
	for note: Dictionary in notes.duplicate():
		if note.b == b and note.n == n and absf(note.t - t) < 0.01:
			notes.erase(note)
	notes.append({"t": t, "d": d, "b": b, "n": n})
	changed.emit()


func end_chord() -> void:
	_end_take()


# Takes out what of `inst` starts in the `d` beats from beat `t`; says whether there was any
func erase(inst: int, t: float, d: float) -> bool:
	var gone := track(inst).filter(func(note: Dictionary) -> bool: return note.t > t - 0.01 and note.t < t + d - 0.01)
	if gone.is_empty():
		return false
	_snapshot(inst)
	for note: Dictionary in gone:
		track(inst).erase(note)
	changed.emit()
	return true


func undo() -> bool:
	if _undo.is_empty():
		return false
	var was: Dictionary = _undo.pop_back()
	sections[was.s][was.i] = was.notes
	_open.clear()
	changed.emit()
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


# A note played by hand. Returns what to hand back to record_off when it is let go (0 if it was
# not taken down).
func record_on(inst: int, b: int, n: int) -> int:
	if not recording:
		return 0
	var t := 0.0
	var waits := 1
	if counting:
		# Only one that jumps the first beat by a hair is kept
		if BEATS - _count > 0.3:
			return 0
	else:
		t = pos
		if snap > 0.0:
			t = roundf(t / snap) * snap
		if t >= length():
			t -= length()
			waits = 2
	if not _snapped.has(inst):
		_snapshot(inst)
		_snapped[inst] = true
	# It has already been heard this time round, so the loop leaves it alone until the next
	var note := {"t": t, "d": 0.0, "b": b, "n": n, "wait": waits}
	track(inst).append(note)
	_token += 1
	_open[_token] = note
	changed.emit()
	return _token


func record_off(token: int) -> void:
	if not _open.has(token):
		return
	var note: Dictionary = _open[token]
	note.d = maxf(note.d, maxf(snap * 0.5, 0.12))
	_open.erase(token)


func _process(delta: float) -> void:
	var step := delta * bpm / 60.0
	if counting:
		_count += step
		while _counted < BEATS and _counted <= int(_count):
			synth.tick(_counted == 0)
			beat.emit(_counted)
			_counted += 1
		if _count >= BEATS:
			counting = false
			playing = true
			pos = 0.0
			step = _count - BEATS
			changed.emit()
		else:
			return
	if not playing:
		return
	for note: Dictionary in _open.values():
		note.d = minf(note.d + step, length() - 0.05)
	for i in range(_sounding.size() - 1, -1, -1):
		_sounding[i][1] -= step
		if _sounding[i][1] <= 0.0:
			synth.stop(_sounding[i][0])
			_sounding.remove_at(i)
	var to := pos + step
	if to >= length():
		_fire(pos, length())
		_wrap()
		to = minf(to - length(), length() - 0.01)
		_fire(0.0, to)
	else:
		_fire(pos, to)
	pos = to


# Everything from beat `a` up to, not including, beat `b`
func _fire(a: float, b: float) -> void:
	for k in range(ceili(a), ceili(b)):
		beat.emit(k)
		if metronome:
			synth.tick(k % BEATS == 0)
	for inst in Kit.INSTRUMENTS.size():
		if muted[inst]:
			continue
		for note: Dictionary in sections[section][inst]:
			if note.t >= a and note.t < b and note.get("wait", 0) <= 0:
				_sounding.append([synth.play(inst, note.b, note.n), note.d])
				note_on.emit(inst, note.b, note.n)


func _wrap() -> void:
	for t: Array in sections[section]:
		for note: Dictionary in t:
			if note.has("wait"):
				note.wait -= 1
				if note.wait <= 0:
					note.erase("wait")
	_end_take()
	if queued >= 0:
		section = queued
		queued = -1
		changed.emit()
	elif chain and not recording:
		for k in range(1, SECTIONS):
			var s := (section + k) % SECTIONS
			if not section_empty(s):
				section = s
				changed.emit()
				break


func _close_open() -> void:
	for token: int in _open.keys():
		record_off(token)


func _end_take() -> void:
	_snapped.clear()


func _snapshot(inst: int) -> void:
	_undo.append({"s": section, "i": inst, "notes": track(inst).duplicate(true)})
	if _undo.size() > UNDO_DEPTH:
		_undo.pop_front()


func to_dict() -> Dictionary:
	var out := []
	for tracks: Array in sections:
		var row := []
		for t: Array in tracks:
			var notes := []
			for note: Dictionary in t:
				notes.append([snappedf(note.t, 0.001), snappedf(note.d, 0.001), note.b, note.n])
			row.append(notes)
		out.append(row)
	return {"bpm": bpm, "bars": bars, "snap": snap, "metronome": metronome, "chain": chain,
			"muted": muted.duplicate(), "sections": out}


func from_dict(data: Dictionary) -> void:
	wipe()
	bpm = clampf(float(data.get("bpm", 110.0)), 50.0, 200.0)
	bars = int(data.get("bars", 2))
	if not BAR_CHOICES.has(bars):
		bars = 2
	snap = float(data.get("snap", 0.25))
	metronome = bool(data.get("metronome", false))
	chain = bool(data.get("chain", false))
	var mutes: Array = data.get("muted", [])
	for i in mini(mutes.size(), muted.size()):
		muted[i] = bool(mutes[i])
	var rows: Array = data.get("sections", [])
	for s in mini(rows.size(), SECTIONS):
		for i in mini(rows[s].size(), Kit.INSTRUMENTS.size()):
			for note: Array in rows[s][i]:
				sections[s][i].append({"t": float(note[0]), "d": float(note[1]), "b": int(note[2]), "n": int(note[3])})
	changed.emit()
