extends SceneTree
## Smoke test: the house band, fingers and keys on the buttons, sliding between notes, recording a
## loop after the count-in, hearing it come round, taking it back, longer loops, sections, mute,
## a tune from the book, the MIDI file, and saving.
## godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/smoke.gd
## (touches are sent as window pixels, like a real finger)

var save := "user://smoke_test.json"
var main: Band
var failures := 0
var from_loop := {}


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	main = _start()
	_run.call_deferred()


func _start() -> Band:
	var m: Band = load("res://main.tscn").instantiate()
	m.save_path = save
	m.show_help_first = false
	root.add_child(m)
	return m


# Counts what the loop plays, by instrument
func _listen() -> void:
	main.looper.note_on.connect(func(i: int, _b: int, _n: int) -> void: from_loop[i] = from_loop.get(i, 0) + 1)


func _run() -> void:
	await _frames(5)
	_listen()
	var looper := main.looper
	_check(looper.has_notes(0, Kit.TUBA) and looper.has_notes(0, Kit.DRUMS), "a first visit gets the house band")
	_check(not looper.has_notes(0, Kit.OCARINA), "with the ocarina left for the player")
	for id: String in ["n0", "n4", "flat", "up", "i6", "rec", "play", "s3", "menu"]:
		var r: Rect2 = main.hud.buttons[id].rect
		_check(Rect2(Vector2.ZERO, main.hud.size_now).encloses(r), "%s is on the screen" % id)

	# Notes: a finger, two at once, a slide, a key, and the benders
	await _touch("n2", true)
	_check(main.held.has(2), "a finger on a button holds its note")
	await _touch("n4", true, 1)
	_check(main.held.size() == 2, "two fingers hold two")
	await _touch("n2", false)
	await _touch("n4", false, 1)
	_check(main.held.is_empty(), "and lifting them lets go")
	await _touch("n1", true)
	await _drag("n2")
	_check(main.held.has(2) and not main.held.has(1), "sliding onto the next button plays it instead")
	await _touch("n2", false)
	await _key(KEY_A, true)
	_check(main.held.has(0), "a key plays its button")
	await _key(KEY_A, false)
	_check(main.pad_note(0) == 62 and main.pad_note(4) == 74, "the ocarina is tuned D to D")
	await _touch("sharp", true)
	await _touch("up", true, 1)
	_check(main.pad_note(0) == 62 + 13, "sharp and the octave bend what is played")
	await _touch("sharp", false)
	await _touch("up", false, 1)

	# A new song: record the trumpet after the count-in
	main.press("new")
	_check(looper.song_empty(), "a new song is empty")
	await _touch("i1", true)
	await _touch("i1", false)
	_check(main.inst == Kit.TRUMPET and main.man.inst == Kit.TRUMPET, "tapping an instrument puts it in his hands")
	await _touch("rec", true)
	await _touch("rec", false)
	_check(looper.counting and looper.recording and not looper.playing, "record counts a bar in first")
	await _touch("n3", true)
	await _touch("n3", false)
	_check(looper.track(Kit.TRUMPET).is_empty(), "what is played during the count is not kept")
	while looper.counting:
		await process_frame
	_check(looper.playing, "then it runs")
	await _frames(40)
	from_loop.clear()
	await _touch("n0", true)
	await _frames(12)
	await _touch("n0", false)
	var notes := looper.track(Kit.TRUMPET)
	_check(notes.size() == 1, "a note played while recording goes on the track")
	if notes.size() == 1:
		_check(is_equal_approx(fmod(notes[0].t, 0.25), 0.0), "snapped to a sixteenth")
		_check(notes[0].d > 0.2 and notes[0].n == 62 and notes[0].b == 0, "with its length, note and button")
	_check(from_loop.get(Kit.TRUMPET, 0) == 0, "and is not played twice the first time round")
	await _frames(int(looper.length() * 60.0 / looper.bpm * 60.0) + 10)
	_check(from_loop.get(Kit.TRUMPET, 0) == 1, "then it comes round once each loop (%d)" % from_loop.get(Kit.TRUMPET, 0))

	# Drums over it, mute, undo
	main.press("i6")
	await _touch("n0", true)
	await _touch("n0", false)
	await _touch("n1", true)
	await _touch("n1", false)
	_check(looper.track(Kit.DRUMS).size() == 2, "the drums go on a track of their own")
	main.press("rec")
	_check(not looper.recording and looper.playing, "record again stops recording and keeps playing")
	await _touch("n2", true)
	await _touch("n2", false)
	_check(looper.track(Kit.DRUMS).size() == 2, "and nothing more is kept")
	main.press("mute")
	from_loop.clear()
	await _frames(int(looper.length() * 60.0 / looper.bpm * 60.0) + 10)
	_check(from_loop.get(Kit.DRUMS, 0) == 0 and from_loop.get(Kit.TRUMPET, 0) >= 1, "a muted track is silent and the rest go on")
	main.press("mute")
	main.press("undo")
	_check(looper.track(Kit.DRUMS).is_empty() and looper.track(Kit.TRUMPET).size() == 1, "undo takes back the last take only")
	main.press("i1")
	main.press("clear")
	_check(looper.track(Kit.TRUMPET).is_empty(), "clear empties this instrument's track")
	main.press("undo")
	_check(looper.track(Kit.TRUMPET).size() == 1, "and that can be taken back too")

	# Longer loops and sections
	main.press("bars")
	_check(looper.bars == 4 and looper.track(Kit.TRUMPET).size() == 2, "doubling the loop plays what was there twice")
	main.press("s1")
	_check(looper.section == 0 and looper.queued == 1, "another section waits for the end of the loop")
	await _frames(int(looper.length() * 60.0 / looper.bpm * 60.0) + 10)
	_check(looper.section == 1 and looper.track(Kit.TRUMPET).is_empty(), "and then takes over")
	main.press("play")
	_check(not looper.playing, "stop stops")
	main.press("s0")
	_check(looper.section == 0, "at a standstill a section changes at once")

	# The MIDI file
	var bytes := MidiFile.write(looper)
	_check(bytes.slice(0, 4).get_string_from_ascii() == "MThd" and bytes[11] == 2, "the MIDI file has a tempo track and one for the trumpet")

	# A tune from the book
	main.press("i0")
	for b: int in Kit.TUNES[0].pads:
		main.press("n%d" % b)
		await _frames(3)
		main.release("n%d" % b)
		await _frames(3)
	await _frames(90)
	_check(main.stage.night, "the Sun Tune brings the night")
	_check(main.man.stare > 0.0, "and gives him a start")

	# Saving
	main.save_game()
	main.queue_free()
	await _frames(3)
	main = _start()
	await _frames(5)
	_check(main.looper.bars == 4 and main.looper.track(Kit.TRUMPET).size() == 2 and main.stage.night and main.inst == 0,
			"the song, the night and the instrument are all there next time")

	# The menu
	await _touch("menu", true)
	await _touch("menu", false)
	_check(main.hud.menu_open, "the menu opens")
	await _touch("menu:tuning", true)
	await _touch("menu:tuning", false)
	_check(main.tuning == 1 and main.pad_note(0) == 60, "and changes the tuning")
	await _touch("menu:close", true)
	await _touch("menu:close", false)
	_check(not main.hud.menu_open, "and shuts")

	print("smoke: %d failures" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAILED: ", what)
	else:
		print("ok: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _touch(id: String, down: bool, finger := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.pressed = down
	e.position = root.get_final_transform() * main.hud.buttons[id].rect.get_center()
	Input.parse_input_event(e)
	await _frames(2)


func _drag(id: String, finger := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = finger
	e.position = root.get_final_transform() * main.hud.buttons[id].rect.get_center()
	Input.parse_input_event(e)
	await _frames(2)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	await _frames(2)
