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
	_check(not looper.has_notes(0, Kit.PICCOLO), "with the piccolo left for the player")
	for id: String in ["n0", "n4", "down", "up", "i6", "i12", "i13", "i14", "i15", "rec", "step", "play", "s3", "menu"]:
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
	_check(main.pad_note(0) == 74 and main.pad_note(4) == 86, "the piccolo is tuned D to D")
	await _touch("up", true, 1)
	_check(main.pad_note(0) == 74 + 12, "the octave key lifts what is played")
	await _touch("up", false, 1)
	_check(main.pad_note(0) == 74 + 12, "and stays on when the finger is lifted")
	await _touch("down", true, 1)
	await _touch("down", false, 1)
	_check(main.pad_note(0) == 74 - 12, "the other octave key puts it out")
	await _touch("down", true, 1)
	await _touch("down", false, 1)
	_check(main.pad_note(0) == 74 - 24, "a second tap goes a second octave")
	await _touch("down", true, 1)
	await _touch("down", false, 1)
	_check(main.pad_note(0) == 74, "and a third puts it out")
	await _touch("sharp", true, 1)
	await _touch("sharp", false, 1)
	_check(main.pad_note(0) == 75, "sharp lifts a button a half step")
	await _touch("sharp", true, 1)
	await _touch("sharp", false, 1)
	_check(main.pad_note(0) == 74, "and a second tap turns it off")
	# The stick: a finger on it, pushed to the top, bends a held note up a whole tone
	var hub: Vector2 = main.hud.stick_at * main.hud.fit
	var e := InputEventScreenTouch.new()
	e.index = 3
	e.pressed = true
	e.position = root.get_final_transform() * hub
	Input.parse_input_event(e)
	var push := InputEventScreenDrag.new()
	push.index = 3
	push.position = root.get_final_transform() * (hub - Vector2(0, main.hud.stick_reach * main.hud.fit))
	Input.parse_input_event(push)
	await _touch("n0", true)
	await _frames(30)
	_check(main.bend > 1.9, "the stick pushed up bends a whole tone (%.2f)" % main.bend)
	var sounding: AudioStreamPlayer = null
	for v in main.synth.voices:
		if v.id == main.held[0][0]:
			sounding = v.player
	_check(sounding != null and sounding.playing and is_equal_approx(sounding.pitch_scale, pow(2.0, 4.0 / 12.0)), "and the note that is sounding goes up with it, still held")
	await _touch("n0", false)
	e = InputEventScreenTouch.new()
	e.index = 3
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(20)
	_check(absf(main.bend) < 0.05, "and let go, it springs back")

	# A new song: record the trumpet after the count-in
	main.press("new")
	_check(looper.song_empty(), "a new song is empty")
	# The tempo: a tap is one beat a minute, a hold runs on in fives
	await _touch("bpm+", true)
	await _touch("bpm+", false)
	_check(looper.bpm == 111.0, "a tap on the tempo is one bpm (%d)" % looper.bpm)
	await _touch("bpm-", true)
	await _touch("bpm-", false)
	_check(looper.bpm == 110.0, "and back down one")
	await _touch("bpm+", true)
	await _frames(180)
	await _touch("bpm+", false)
	var ran := looper.bpm
	_check(ran > 125.0 and ran < 200.0 and fmod(ran, 5.0) == 0.0, "held, it runs, and lands on the fives (%d)" % ran)
	await _frames(20)
	_check(looper.bpm == ran, "and stops when let go")
	looper.bpm = 110.0
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

	# The new instruments, and the electric's reach: low E to the top of the neck and past
	looper = main.looper
	for i: int in [Kit.UKULELE, Kit.ELECTRIC, Kit.PIANO]:
		main.press("i%d" % i)
		await _frames(2)
		_check(main.inst == i and main.man.inst == i, "%s goes in his hands" % Kit.INSTRUMENTS[i].name)
		main.press("n2")
		await _frames(2)
		_check(main.held.has(2), "and plays")
		main.release("n2")
	# The hand percussion: three kits of five, changed by the octave keys, as the drums are
	main.press("i%d" % Kit.PERCUSSION)
	_check(main.synth.drums[Kit.PERCUSSION].size() == 15 and main.synth.drums[Kit.PERCUSSION].all(func(s: AudioStreamWAV) -> bool: return s != null),
			"the percussion has fifteen sounds")
	var kits := []
	for id: String in ["", "down", "up"]:
		if id != "":
			main.press(id)
		kits.append(Kit.hit_names(Kit.PERCUSSION)[Kit.drum(0, main.pad_note(0))])
	main.press("up")
	_check(kits == ["Guiro", "Conga", "Claves"] and not main.mods.up and not main.two, "the octave keys change its kit (%s)" % ", ".join(kits))
	main.press("n2")
	_check(main.held.has(2) and main.man.inst == Kit.PERCUSSION, "and it plays in his hands")
	main.release("n2")
	main.press("i%d" % Kit.ELECTRIC)
	for id: String in ["down", "down", "flat"]:
		main.press(id)
	var lowest := main.pad_note(0)
	for id: String in ["down", "flat", "up", "up", "sharp"]:
		main.press(id)
	var highest := main.pad_note(4)
	_check(lowest <= 40 and highest >= 86, "the electric reaches from below low E to the top of the neck (%d to %d)" % [lowest, highest])
	for id: String in ["up", "sharp"]:
		main.press(id)
	_check(not main.mods.up and not main.mods.sharp and main.pad_note(0) == 50, "and the keys go off again")

	# Step entry: notes written in at a cursor
	main.press("new")
	main.press("i%d" % Kit.PIANO)
	await _touch("step", true)
	await _touch("step", false)
	_check(main.stepping and main.hud.buttons.has("rest"), "the pencil starts writing notes in, with its own keys")
	_check(Rect2(Vector2.ZERO, main.hud.size_now).encloses(main.hud.buttons["erase"].rect), "which are on the screen")
	looper.bars = 2
	main.cursor = 0.0
	await _touch("n0", true)
	await _touch("n0", false)
	var written := looper.track(Kit.PIANO)
	_check(written.size() == 1 and written[0].t == 0.0 and written[0].d == 0.25 and written[0].n == main.pad_note(0), "a note goes in at the cursor, a sixteenth long")
	_check(main.cursor == 0.25, "and the cursor moves on")
	await _touch("len", true)
	await _touch("len", false)
	_check(main.step_len == 0.5, "the length key makes them eighths")
	await _touch("n1", true)
	await _touch("n3", true, 1)
	await _touch("n1", false)
	_check(main.cursor == 0.25, "the cursor waits while a button is still down")
	await _touch("n3", false, 1)
	_check(written.size() == 3 and written[1].t == 0.25 and written[2].t == 0.25 and written[2].d == 0.5, "two together are a chord")
	_check(main.cursor == 0.75, "and then it moves on by an eighth")
	await _touch("rest", true)
	await _touch("rest", false)
	_check(main.cursor == 1.25 and written.size() == 3, "a rest leaves a gap")
	main.press("undo")
	_check(looper.track(Kit.PIANO).size() == 1, "undo takes the whole chord back")
	await _key(KEY_LEFT, true)
	await _key(KEY_LEFT, false)
	_check(main.cursor == 0.75 and absf(main.bend) < 0.01, "the left arrow moves the cursor back, not the stick")
	main.step_to(0.1)
	await _touch("erase", true)
	await _touch("erase", false)
	_check(looper.track(Kit.PIANO).is_empty(), "erase takes out what is under the cursor")
	main.step_to(7.9)
	_check(main.cursor == 7.75, "the cursor goes to the last sixteenth at most")
	await _touch("n2", true)
	await _touch("n2", false)
	_check(main.cursor == 0.25, "and goes round to the start after the end")
	main._midi_on(64)
	main._note_off("m64")
	_check(looper.track(Kit.PIANO).back().n == 64 and looper.track(Kit.PIANO).back().t == 0.25, "a MIDI key writes in too")
	await _touch("step", true)
	await _touch("step", false)
	_check(not main.stepping and not main.hud.buttons.has("rest"), "and the pencil again puts it all away")

	# The song as sound
	var render := SongRender.new(looper.to_dict())
	while not render.work(50):
		pass
	_check(render.bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and render.frames > SongRender.RATE * 4 * 60.0 / looper.bpm,
			"the WAV has the song in it, ringing on at the end (%d samples)" % render.frames)
	var loud := 0
	for i in range(44, render.bytes.size(), 2):
		loud = maxi(loud, absi(render.bytes.decode_s16(i)))
	_check(loud > 3000 and loud <= 32767 * 0.9, "and is loud enough without clipping (%d)" % loud)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://one-man-band.wav"))
	main.export_wav()
	for k in 600:
		if main._render == null:
			break
		await process_frame
	_check(FileAccess.file_exists("user://one-man-band.wav"), "and the menu's save writes it out a little each frame")

	# A song saved before the new instruments came still loads as it was
	var old_save := "user://smoke_old.json"
	var tracks := []
	for i in 12:
		tracks.append([])
	tracks[Kit.BASSOON] = [[0.5, 1.0, 1, 50]]
	tracks[Kit.DRUMS] = [[0.0, 0.1, 0, 0], [2.0, 0.1, 1, 40]]
	var f := FileAccess.open(old_save, FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "inst": Kit.BASSOON, "key": 2, "tuning": 3, "night": false, "sound": true,
			"song": {"bpm": 97.0, "bars": 4, "snap": 0.5, "metronome": false, "chain": false, "muted": [false, false, false, false, false, false, true, false, false, false, false, false],
			"sections": [tracks, [], [], []]}}))
	f.close()
	main.save_path = old_save
	_check(main.load_game(), "an old save loads")
	_check(main.inst == Kit.BASSOON and main.key == 2 and main.tuning == 3 and looper.bpm == 97.0 and looper.bars == 4, "with its instrument, key, tuning, tempo and length")
	_check(looper.sections[0][Kit.BASSOON] == [{"t": 0.5, "d": 1.0, "b": 1, "n": 50}] and looper.sections[0][Kit.DRUMS].size() == 2 and looper.muted[Kit.DRUMS],
			"and every note and mute in it")
	_check(looper.sections[0].size() == Kit.INSTRUMENTS.size() and looper.sections[0][Kit.PIANO].is_empty(), "with room for the new instruments")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_save))
	main.save_path = save
	main.load_game()

	# The menu
	await _touch("menu", true)
	await _touch("menu", false)
	_check(main.hud.menu_open, "the menu opens")
	await _touch("menu:tuning", true)
	await _touch("menu:tuning", false)
	_check(main.tuning == 1 and main.pad_note(0) == 72, "and changes the tuning")
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
	e.position = root.get_final_transform() * main.hud.on_screen(id)
	Input.parse_input_event(e)
	await _frames(2)


func _drag(id: String, finger := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = finger
	e.position = root.get_final_transform() * main.hud.on_screen(id)
	Input.parse_input_event(e)
	await _frames(2)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	await _frames(2)
