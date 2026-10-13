class_name Band
extends Node
## One Man Band. Five buttons play five notes, the way an ocarina's holes do, on whichever of his
## instruments the bandsman has in his hands, and a loop station keeps what was played going
## while the next thing goes on top.
##
## This is the glue: it owns the sound (Synth), the loops (Looper), the scene (Stage, Bandsman)
## and the controls (Hud), and turns a pressed button into what it does.

const KEYS := {
	KEY_A: "n0", KEY_S: "n1", KEY_D: "n2", KEY_F: "n3", KEY_G: "n4",
	KEY_LEFT: "flat", KEY_RIGHT: "sharp", KEY_DOWN: "down", KEY_UP: "up",
	KEY_1: "i0", KEY_2: "i1", KEY_3: "i2", KEY_4: "i3", KEY_5: "i4", KEY_6: "i5", KEY_7: "i6",
	KEY_SPACE: "play", KEY_R: "rec", KEY_Z: "undo", KEY_M: "metro", KEY_ESCAPE: "close",
}
const FOV := 38.0
# What the camera has to keep in the picture: the middle of him, and how tall and wide he is
const SUBJECT := Vector3(0.0, 1.5, 0.0)
const TALL := 2.8
const BROAD := 2.4

var save_path := "user://one_man_band.json"
var show_help_first := true

var synth: Synth
var looper: Looper
var stage: Stage
var man: Bandsman
var hud: Hud
var view: SubViewport
var camera: Camera3D

var inst := 0
var key := 0
var tuning := 0
var mods := {"flat": false, "sharp": false, "down": false, "up": false}
var held := {}            # button (or "m60" for a MIDI key) -> [voice, recording token]
var recent: Array[int] = []
var midi_open := false
var _page_listener: JavaScriptObject   # (kept, or the browser's side of it is let go)
var _radio_wait := 0.0
var time := 0.0
var _dirty := false
var _since_save := 0.0


func _ready() -> void:
	synth = Synth.new()
	add_child(synth)
	looper = Looper.new()
	looper.synth = synth
	add_child(looper)

	view = SubViewport.new()
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	stage = Stage.new()
	view.add_child(stage)
	man = Bandsman.new()
	man.stage = stage
	man.position.y = Stage.FLOOR
	view.add_child(man)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.far = 200.0
	view.add_child(camera)

	var screen := TextureRect.new()
	screen.texture = view.get_texture()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	hud = Hud.new()
	hud.band = self
	add_child(hud)

	looper.note_on.connect(_loop_note)
	if OS.has_feature("web"):
		_page_listener = JavaScriptBridge.create_callback(_page_said)
		JavaScriptBridge.get_interface("window").addEventListener("message", _page_listener)
	looper.changed.connect(func() -> void: _dirty = true)
	if not load_game():
		load_demo()
		hud.help_open = show_help_first
	man.choose(inst, true)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var s := get_viewport().get_visible_rect().size
	var k := N64.LINES / minf(s.x, s.y)
	view.size = Vector2i(maxi(2, roundi(s.x * k)), maxi(2, roundi(s.y * k)))
	hud.layout(s)
	_aim()


# Stands the camera off far enough to fit him in the part of the screen the controls leave clear,
# and to one side so that he sits in the middle of that part
func _aim() -> void:
	var s := hud.size_now
	var clear := hud.free_rect
	var half := tan(deg_to_rad(FOV) / 2.0)
	var away := maxf(TALL / (2.0 * half * clear.size.y / s.y), BROAD / (2.0 * half * (s.x / s.y) * clear.size.x / s.x))
	var basis := Basis(Vector3.UP, 0.1 * sin(time * 0.23) + 0.12) * Basis(Vector3.RIGHT, -0.08)
	var mid := clear.get_center()
	var across := (mid.x - s.x / 2.0) / (s.x / 2.0) * half * (s.x / s.y) * away
	var up := -(mid.y - s.y / 2.0) / (s.y / 2.0) * half * away
	camera.basis = basis
	camera.position = SUBJECT + basis.z * away - basis.x * across - basis.y * up


func _process(delta: float) -> void:
	time += delta
	man.phase = looper.beat_phase()
	man.holding = not held.is_empty()
	_aim()
	if _radio_wait > 0.0:
		_radio_wait -= delta
		if _radio_wait <= 0.0:
			hud.toast("No answer. The radio is in the Wayside arcade")
	_since_save += delta
	if _dirty and _since_save > 3.0:
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if looper != null and _dirty:
			save_game()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var id: String = KEYS.get(event.physical_keycode, "")
		if id != "":
			hud.key(id, event.pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventMIDI:
		if event.message == MIDI_MESSAGE_NOTE_ON and event.velocity > 0:
			_midi_on(event.pitch)
		elif event.message == MIDI_MESSAGE_NOTE_OFF or event.message == MIDI_MESSAGE_NOTE_ON:
			_note_off("m%d" % event.pitch)


# A button of the Hud (or the key that stands for it) has gone down
func press(id: String) -> void:
	var n := _numbered(id, "n")
	var i := _numbered(id, "i")
	var s := _numbered(id, "s")
	if n >= 0:
		_pad_on(n)
	elif i >= 0:
		choose(i)
	elif s >= 0:
		looper.go_to(s)
	elif mods.has(id):
		mods[id] = true
	else:
		match id:
			"rec":
				looper.toggle_record()
			"play":
				looper.toggle_play()
			"undo":
				looper.undo()
			"clear":
				looper.clear_track(inst)
			"mute":
				looper.muted[inst] = not looper.muted[inst]
				_dirty = true
			"metro":
				looper.metronome = not looper.metronome
				_dirty = true
			"bpm-":
				looper.bpm = maxf(50.0, looper.bpm - 5.0)
				_dirty = true
			"bpm+":
				looper.bpm = minf(200.0, looper.bpm + 5.0)
				_dirty = true
			"bars":
				looper.next_bars()
			"menu":
				hud.menu_open = true
			"close":
				hud.menu_open = false
				hud.help_open = false
			"tuning":
				tuning = (tuning + 1) % Kit.TUNINGS.size()
				_dirty = true
			"key":
				key = (key + 1) % 12
				_dirty = true
			"snap":
				looper.next_snap()
			"chain":
				looper.chain = not looper.chain
				_dirty = true
			"demo":
				load_demo()
				hud.menu_open = false
				hud.toast("The house band. Press play, then join in")
			"new":
				new_song()
				hud.menu_open = false
				hud.toast("A clean sheet")
			"export":
				export_midi()
				hud.menu_open = false
			"radio":
				send_to_radio()
				hud.menu_open = false
			"midi":
				open_midi()
			"sound":
				synth.sound = not synth.sound
				_dirty = true
			"help":
				hud.menu_open = false
				hud.help_open = true


func release(id: String) -> void:
	var n := _numbered(id, "n")
	if n >= 0:
		_note_off(n)
	elif mods.has(id):
		mods[id] = false


func choose(which: int) -> void:
	if which == inst:
		return
	for k: Variant in held.keys():
		_note_off(k)
	inst = which
	man.choose(inst)
	recent.clear()
	_dirty = true


# The note button `b` gives right now. For the drums it is how far the drum is bent instead.
func pad_note(b: int) -> int:
	if Kit.is_drums(inst):
		return (2 if mods.sharp else 0) - (2 if mods.flat else 0) + (5 if mods.up else 0) - (5 if mods.down else 0)
	var steps: Array = Kit.TUNINGS[tuning].steps
	return Kit.INSTRUMENTS[inst].base + key + steps[b] + (1 if mods.sharp else 0) - (1 if mods.flat else 0) \
			+ (12 if mods.up else 0) - (12 if mods.down else 0)


# The button that would give note `n` on instrument `i` with nothing held, or -1
func pad_of(i: int, n: int) -> int:
	var steps: Array = Kit.TUNINGS[tuning].steps
	for b in steps.size():
		if posmod(n - Kit.INSTRUMENTS[i].base - key - steps[b], 12) == 0:
			return b
	return -1


func _pad_on(b: int) -> void:
	if held.has(b):
		return
	var n := pad_note(b)
	held[b] = [synth.play(inst, b, n), looper.record_on(inst, b, n)]
	man.on_note(inst, b, true)
	hud.played_by_hand(b)
	if not Kit.is_drums(inst):
		_listen(b)


func _midi_on(pitch: int) -> void:
	var id := "m%d" % pitch
	if held.has(id):
		return
	var b := pitch % 5 if Kit.is_drums(inst) else pad_of(inst, pitch)
	var n := 0 if Kit.is_drums(inst) else pitch
	held[id] = [synth.play(inst, b, n), looper.record_on(inst, b, n)]
	man.on_note(inst, maxi(b, 0), true)
	hud.played_by_hand(b)


func _note_off(id: Variant) -> void:
	if not held.has(id):
		return
	synth.stop(held[id][0])
	looper.record_off(held[id][1])
	held.erase(id)


func _loop_note(i: int, b: int, _n: int) -> void:
	man.on_note(i, maxi(b, 0), false)
	hud.played_by_loop(i)


# Has one of the tunes in the book just been finished?
func _listen(b: int) -> void:
	recent.append(b)
	if recent.size() > 8:
		recent.pop_front()
	for tune in Kit.TUNES:
		var pads: Array = tune.pads
		if recent.size() >= pads.size() and recent.slice(-pads.size()) == pads:
			recent.clear()
			_tune(tune)
			return


func _tune(tune: Dictionary) -> void:
	await get_tree().create_timer(0.5).timeout
	for step: int in [0, 4, 7, 12]:
		synth.play(Kit.BELLS, -1, 74 + key + step, 0.8)
		await get_tree().create_timer(0.09).timeout
	man.startle()
	match tune.does:
		"sun":
			stage.set_night(not stage.night)
		"storm":
			stage.set_rain(not stage.rain)
		"fireflies":
			stage.set_fireflies(not stage.fireflies)
	hud.toast("The %s %s" % [tune.name, tune.hint])
	_dirty = true


func new_song() -> void:
	looper.stop()
	looper.wipe()
	looper.bpm = 110.0
	looper.bars = 2
	looper.chain = false
	looper.changed.emit()


func load_demo() -> void:
	looper.stop()
	key = 0
	tuning = 0
	looper.from_dict(_demo())


# A couple of bars for the house band: drums, tuba, accordion, guitar and bells, with the piccolo
# and the trumpet left for whoever is playing. Notes are [beat, length, note].
func _demo() -> Dictionary:
	var tracks := []
	for i in Kit.INSTRUMENTS.size():
		tracks.append([])
	var drums: Array = tracks[Kit.DRUMS]
	for t: float in [0.0, 2.0, 4.0, 6.0, 7.5]:
		drums.append([t, 0.1, 0, 0])
	for t: float in [1.0, 3.0, 5.0, 7.0]:
		drums.append([t, 0.1, 1, 0])
	for k in 16:
		drums.append([k * 0.5, 0.1, 2, 0])
	drums.append([0.0, 0.1, 4, 0])
	_add(tracks, Kit.TUBA, [[0, 0.8, 38], [1.5, 0.4, 45], [2, 0.8, 38], [3, 0.4, 41], [3.5, 0.4, 45],
			[4, 0.8, 43], [5.5, 0.4, 50], [6, 0.8, 45], [7, 0.4, 45], [7.5, 0.4, 48]])
	var stabs := []
	for t: float in [0.5, 1.5, 2.5, 3.5]:
		for n: int in [62, 65, 69]:
			stabs.append([t, 0.3, n])
	for t: float in [4.5, 5.5]:
		for n: int in [62, 67, 71]:
			stabs.append([t, 0.3, n])
	for t: float in [6.5, 7.5]:
		for n: int in [64, 69, 72]:
			stabs.append([t, 0.3, n])
	_add(tracks, Kit.ACCORDION, stabs)
	var picked := []
	var run := [50, 57, 62, 65, 57, 62, 65, 69, 55, 59, 62, 67, 57, 60, 64, 69]
	for k in run.size():
		picked.append([k * 0.5, 0.4, run[k]])
	_add(tracks, Kit.GUITAR, picked)
	_add(tracks, Kit.BELLS, [[0, 0.5, 86], [1.5, 0.5, 81], [4, 0.5, 83], [5.5, 0.5, 79], [6, 0.5, 81], [7, 0.5, 84]])
	return {"bpm": 108.0, "bars": 2, "snap": 0.25, "sections": [tracks, [], [], []]}


func _add(tracks: Array, i: int, notes: Array) -> void:
	for note: Array in notes:
		tracks[i].append([note[0], note[1], pad_of(i, note[2]), note[2]])


func export_midi() -> void:
	var bytes := MidiFile.write(looper)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, "one-man-band.mid", "audio/midi")
		hud.toast("Saved one-man-band.mid")
	else:
		var path := "user://one-man-band.mid"
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		hud.toast("Saved to " + ProjectSettings.globalize_path(path))


# Sends the loop that is playing (what is not muted of it) up to the page the game is on. In
# the Wayside arcade that page keeps it on the player's account, and the radio on the station's
# bench plays it: on one frequency for them, on another for everyone else.
func send_to_radio() -> void:
	if looper.section_empty(looper.section):
		hud.toast("Nothing to send yet. Record something first")
		return
	if not OS.has_feature("web"):
		hud.toast("The radio is in the Wayside arcade. Play there to send it")
		return
	var tracks: Array = looper.to_dict().sections[looper.section]
	for i in tracks.size():
		if looper.muted[i]:
			tracks[i] = []
	var message := JSON.stringify({"type": "ONE_MAN_BAND_SONG", "song": {"bpm": looper.bpm, "bars": looper.bars, "tracks": tracks}})
	JavaScriptBridge.eval("window.parent.postMessage(%s, '*')" % message)
	_radio_wait = 6.0
	hud.toast("Sending it to the station's radio")


# The page answers: the name the tune was given, or why it was not taken
func _page_said(args: Array) -> void:
	var data: Variant = args[0].data
	if not data is JavaScriptObject or str(data.type) != "ONE_MAN_BAND_SAVED":
		return
	_radio_wait = 0.0
	if data.ok:
		hud.toast("On the radio as %s. Tune to 94.7 at the station" % str(data.name))
	elif str(data.why) == "signin":
		hud.toast("Sign in to put a tune on the radio")
	else:
		hud.toast("The radio would not take it. Try again")


# Listens for a MIDI keyboard. Only on request, because a browser asks leave for it.
func open_midi() -> void:
	OS.open_midi_inputs()
	midi_open = true
	var found := OS.get_connected_midi_inputs()
	hud.toast("Listening to " + ", ".join(found) if not found.is_empty() else "Listening for a MIDI keyboard")


func save_game() -> void:
	_dirty = false
	_since_save = 0.0
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": 1, "inst": inst, "key": key, "tuning": tuning, "night": stage.night,
			"rain": stage.rain, "fireflies": stage.fireflies, "sound": synth.sound, "song": looper.to_dict()}))
	f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or not data.has("song"):
		return false
	inst = clampi(int(data.get("inst", 0)), 0, Kit.INSTRUMENTS.size() - 1)
	key = posmod(int(data.get("key", 0)), 12)
	tuning = clampi(int(data.get("tuning", 0)), 0, Kit.TUNINGS.size() - 1)
	stage.set_night(bool(data.get("night", false)), true)
	stage.set_rain(bool(data.get("rain", false)))
	stage.set_fireflies(bool(data.get("fireflies", false)))
	synth.sound = bool(data.get("sound", true))
	looper.from_dict(data.song)
	_dirty = false
	return true


# The number after `prefix` if `id` is that prefix and one digit, else -1
static func _numbered(id: String, prefix: String) -> int:
	if id.length() == prefix.length() + 1 and id.begins_with(prefix) and id[-1].is_valid_int():
		return int(id[-1])
	return -1
