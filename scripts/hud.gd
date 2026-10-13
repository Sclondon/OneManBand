class_name Hud
extends Control
## Every control on the screen, drawn by hand and pressed by any number of fingers at once: a
## sheet of music along the top, the loop station under it, the instruments, and the five note
## buttons (each with the name of its note on it), with a stick to bend them and two octave keys. It is dressed like
## the bandstand: parchment, wood and brass.
##
## There are no Button nodes. Each control is a rectangle in `buttons`; a finger going down on
## one calls Band.press(id), and coming up, Band.release(id). Keys stand in for fingers.
##
## Everything is laid out for a screen at least WIDE_MIN across (lying down) or TALL_MIN high
## (upright), and drawn smaller by `fit` on one that is neither, so that it always all fits.

const RYE: FontFile = preload("res://fonts/Rye-Regular.ttf")
const FREDOKA: FontFile = preload("res://fonts/Fredoka.ttf")
const WIDE_MIN := 1080.0
const TALL_MIN := 1100.0

const CREAM := Color("f4e8c4")
const PAPER_D := Color("dfcd9c")
const INK := Color("2a1a12")
const WOOD := Color("75482a")
const WOOD_D := Color("2e1c11")
const BRASS := Color("e6b24a")
const RED := Color("dd3f2e")
const GOLD := Color("f8ca22")
# The five note buttons, lowest to highest
const PAD_COLORS: Array[Color] = [Color("4fb0ff"), Color("58d68d"), Color("f8ca22"), Color("ff9a3d"), Color("ff6b7c")]
const TRANSPORT := ["rec", "play", "undo", "clear", "mute", "metro", "bpm-", "bpm", "bpm+", "bars", "s0", "s1", "s2", "s3", "menu"]
const MENU := ["tuning", "key", "snap", "chain", "demo", "new", "radio", "export", "midi", "sound", "songbook", "help", "close"]
const BENDERS := ["flat", "sharp", "down", "up"]
# In a browser the stick also listens to the page's own touches (see _ready): on some phones
# a finger's sliding never arrives as a drag here, though its going down and coming up do
const PAGE_TOUCHES := """
	(function () {
		if (window.ombTouch) return;
		var canvas = document.querySelector('canvas');
		if (!canvas) return;
		var t = window.ombTouch = { live: {}, text: '' };
		function at(touch) {
			var r = canvas.getBoundingClientRect();
			return [(touch.clientX - r.left) / r.width, (touch.clientY - r.top) / r.height];
		}
		function say() {
			var out = [];
			for (var id in t.live) out.push(t.live[id].join(','));
			t.text = out.join(';');
		}
		function each(e, f) { for (var i = 0; i < e.changedTouches.length; i++) f(e.changedTouches[i]); say(); }
		canvas.addEventListener('touchstart', function (e) { each(e, function (x) { var p = at(x); t.live[x.identifier] = [p[0], p[1], p[0], p[1]]; }); }, { passive: true });
		canvas.addEventListener('touchmove', function (e) { each(e, function (x) { var v = t.live[x.identifier]; if (v) { var p = at(x); v[2] = p[0]; v[3] = p[1]; } }); }, { passive: true });
		var up = function (e) { each(e, function (x) { delete t.live[x.identifier]; }); };
		canvas.addEventListener('touchend', up, { passive: true });
		canvas.addEventListener('touchcancel', up, { passive: true });
	})()
"""

var band: Band
var title_font: Font
var font: Font
var buttons := {}
var fingers := {}
var lit := {}
var wide := true
var fit := 1.0
var size_now := Vector2(1280, 720)   # the screen, in the measure everything here is laid out in
var staff := Rect2()
var free_rect := Rect2(0, 0, 1280, 720)
var menu_rect := Rect2()
var menu_open := false
var help_open := false
var book_open := false
# The stick: pushed up or down it bends what is sounding, sideways it makes it wobble.
# `stick` is where a finger has it, `stick_keys` where the arrow keys do, `stick_now` where
# it has got to (it does not jump), each from -1 to 1 with up as +y
var stick_at := Vector2.ZERO
var stick_reach := 72.0
var stick := Vector2.ZERO
var stick_keys := Vector2.ZERO
var stick_now := Vector2.ZERO
var stick_finger := -1
var stick_by_page := false   # a finger the page saw go down on the stick has it
var toast_text := ""
var toast_left := 0.0
var by_hand: Array = []        # the last notes played, for the staff when nothing is looping: [button, seconds since, name]
var lane_glow: Array[float] = []
var _boxes := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_font = RYE
	var bold := FontVariation.new()
	bold.base_font = FREDOKA
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	font = bold
	for i in Kit.INSTRUMENTS.size():
		lane_glow.append(0.0)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(PAGE_TOUCHES, true)


# `screen` is the real size; everything is then worked out in that divided by `fit`
func layout(screen: Vector2) -> void:
	var as_wide := minf(1.0, screen.x / WIDE_MIN)
	var as_tall := minf(1.0, screen.y / TALL_MIN)
	wide = as_wide > as_tall or (as_wide == as_tall and screen.x >= screen.y)
	fit = as_wide if wide else as_tall
	var s := screen / fit
	size_now = s
	buttons.clear()
	var m := 12.0
	var sw := minf(s.x - 2.0 * m, 880.0)
	staff = Rect2((s.x - sw) / 2.0, m, sw, 150.0)
	var y := staff.end.y + 10.0
	if wide:
		y = _row(TRANSPORT, y, 56.0, minf(s.x - 2.0 * m, 980.0))
	else:
		y = _row(TRANSPORT.slice(0, 6) + ["menu"], y, 58.0, s.x - 2.0 * m)
		y = _row(TRANSPORT.slice(6, 14), y, 58.0, s.x - 2.0 * m)

	# The notes, rising from left to right like a little keyboard: three below, two between them above
	var rad := 54.0
	var pitch := rad * 2.0 + 12.0
	var low := Vector2(s.x - 16.0 - rad - 2.0 * pitch, s.y - 22.0 - rad)
	for b in 5:
		var at := low + Vector2(b * pitch / 2.0, -100.0 if b % 2 == 1 else 0.0)
		buttons["n%d" % b] = {"rect": _around(at, rad), "round": true}
	var pads_left := low.x - rad
	var pads_top := low.y - 100.0 - rad
	# The stick, bottom left, with two rows of keys under it: flat and sharp, then the octaves.
	# Lying down on a phone there is little height, so the stick is made as small as it must be
	var keys_top := s.y - m - 4.0 - 2.0 * 48.0 - 6.0
	for k in 4:
		buttons[BENDERS[k]] = {"rect": Rect2(m + 4.0 + (k % 2) * 108.0, keys_top + (k / 2) * 54.0, 98.0, 48.0)}
	stick_reach = clampf((keys_top - 12.0 - (y if wide else 0.0) - 10.0) / 2.0, 46.0, 72.0)
	stick_at = Vector2(m + 4.0 + 103.0, keys_top - 12.0 - stick_reach)
	var stick_top := stick_at.y - stick_reach - 4.0

	var count := Kit.SHELF.size()
	var x0 := m
	var x1 := s.x - m
	var top := minf(pads_top, stick_top) - 18.0
	if wide:
		x0 = m + 4.0 + 206.0 + 14.0
		x1 = pads_left - 14.0
		top = s.y - m - 4.0
	# In one row if they are a fair size that way, or else in two
	var per := count
	if (x1 - x0 - (count - 1) * 8.0) / count < 58.0:
		per = ceili(count / 2.0)
	var side := clampf((x1 - x0 - (per - 1) * 8.0) / per, 40.0, 92.0)
	var start := (x0 + x1 - per * side - (per - 1) * 8.0) / 2.0
	var block := ceili(float(count) / per) * (side + 8.0) - 8.0
	for k in count:
		buttons["i%d" % Kit.SHELF[k]] = {"rect": Rect2(start + (k % per) * (side + 8.0), top - block + (k / per) * (side + 8.0), side, side)}
	free_rect = Rect2(x0, staff.end.y + 4.0, x1 - x0, top - block - 12.0 - staff.end.y) if wide else Rect2(0.0, y, s.x, top - block - 8.0 - y)

	var cell := Vector2(minf(300.0, (s.x - 64.0) / 2.0), 58.0)
	var rows := ceili(MENU.size() / 2.0)
	menu_rect = Rect2((s.x - cell.x * 2.0 - 44.0) / 2.0, (s.y - rows * (cell.y + 8.0) - 92.0) / 2.0,
			cell.x * 2.0 + 44.0, rows * (cell.y + 8.0) + 92.0)
	for k in MENU.size():
		var at := menu_rect.position + Vector2(16.0 + (k % 2) * (cell.x + 12.0), 70.0 + (k / 2) * (cell.y + 8.0))
		# (the last, on a row by itself, takes the whole of it)
		var alone := k == MENU.size() - 1 and k % 2 == 0
		buttons["menu:" + MENU[k]] = {"rect": Rect2(at, Vector2(cell.x * 2.0 + 12.0, cell.y) if alone else cell)}


# Lays `ids` out in a row `width` wide, centred, and returns where the next row would start
func _row(ids: Array, y: float, h: float, width: float) -> float:
	var weights := {"bpm": 1.25, "bars": 1.25}
	var total := 0.0
	for id: String in ids:
		total += weights.get(id, 1.0)
	var gap := 6.0
	var unit := minf((width - gap * (ids.size() - 1)) / total, 96.0)
	var x := (size_now.x - (unit * total + gap * (ids.size() - 1))) / 2.0
	for id: String in ids:
		var w: float = unit * weights.get(id, 1.0)
		buttons[id] = {"rect": Rect2(x, y, w, h)}
		x += w + gap
	return y + h + 8.0


func _around(c: Vector2, r: float) -> Rect2:
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


# Where the middle of button `id` is on the real screen
func on_screen(id: String) -> Vector2:
	return buttons[id].rect.get_center() * fit


func toast(text: String) -> void:
	toast_text = text
	toast_left = 4.0


func played_by_hand(b: int) -> void:
	by_hand.append([b, 0.0, _label(band.inst, b, band.pad_note(maxi(b, 0))) if b >= 0 else ""])
	if by_hand.size() > 10:
		by_hand.pop_front()
	lane_glow[band.inst] = 1.0


func played_by_loop(i: int) -> void:
	lane_glow[i] = 1.0


# A key that stands for button `id`
func key(id: String, down: bool) -> void:
	var finger := "key:" + id
	if down and not fingers.has(finger):
		if help_open or book_open or (menu_open and id != "close"):
			help_open = false
			book_open = false
			return
		fingers[finger] = id
		_down(id)
	elif not down and fingers.has(finger):
		_up(fingers[finger])
		fingers.erase(finger)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var at: Vector2 = event.position / fit
		if event.index == stick_finger and not event.pressed:
			stick_finger = -1
			stick = Vector2.ZERO
			return
		if event.pressed:
			if help_open or book_open:
				help_open = false
				book_open = false
				return
			if not menu_open and at.distance_to(stick_at) <= stick_reach * 1.2:
				stick_finger = event.index
				_stick_to(at)
				return
			var id := _hit(at)
			if menu_open and id == "":
				menu_open = menu_rect.has_point(at)
				return
			if id != "":
				fingers[event.index] = id
				_down(id)
		elif fingers.has(event.index):
			_up(fingers[event.index])
			fingers.erase(event.index)
	elif event is InputEventScreenDrag and event.index == stick_finger:
		_stick_to(event.position / fit)
	elif event is InputEventScreenDrag and fingers.has(event.index):
		# Sliding from one note button onto another plays it
		var now: String = fingers[event.index]
		if Band._numbered(now, "n") >= 0:
			var id := _hit(event.position / fit)
			if id != now and Band._numbered(id, "n") >= 0:
				_up(now)
				fingers[event.index] = id
				_down(id)


# In a browser: is a finger that went down on the stick still down, and where has it got to?
func _ask_the_page() -> void:
	if not OS.has_feature("web"):
		return
	var had := stick_by_page
	stick_by_page = false
	var screen := get_viewport().get_visible_rect().size
	for touch: String in str(JavaScriptBridge.eval("window.ombTouch ? window.ombTouch.text : ''", true)).split(";", false):
		var n := touch.split_floats(",")
		if n.size() < 4 or menu_open or help_open or book_open:
			continue
		if (Vector2(n[0], n[1]) * screen / fit).distance_to(stick_at) <= stick_reach * 1.2:
			stick_by_page = true
			_stick_to(Vector2(n[2], n[3]) * screen / fit)
			break
	if had and not stick_by_page and stick_finger < 0:
		stick = Vector2.ZERO


func _stick_to(at: Vector2) -> void:
	var push := (at - stick_at) / (stick_reach * 0.8)
	stick = Vector2(push.x, -push.y).limit_length(1.0)


func _hit(at: Vector2) -> String:
	for id: String in buttons:
		if id.begins_with("menu:") != menu_open or id == "bpm":
			continue
		var r: Rect2 = buttons[id].rect
		if buttons[id].has("round"):
			if at.distance_to(r.get_center()) <= r.size.x * 0.5 * 1.1:
				return id
		elif r.grow(3.0).has_point(at):
			return id
	return ""


func _down(id: String) -> void:
	lit[id] = lit.get(id, 0) + 1
	if lit[id] == 1:
		band.press(id.trim_prefix("menu:"))


func _up(id: String) -> void:
	lit[id] = maxi(0, lit.get(id, 0) - 1)
	if lit[id] == 0:
		band.release(id.trim_prefix("menu:"))


func _held(id: String) -> bool:
	return lit.get(id, 0) > 0


func _process(delta: float) -> void:
	toast_left = maxf(0.0, toast_left - delta)
	_ask_the_page()
	stick_now = stick_now.lerp(stick if stick_finger >= 0 or stick_by_page else stick_keys, 1.0 - exp(-20.0 * delta))
	for note: Array in by_hand:
		note[1] += delta
	for i in lane_glow.size():
		lane_glow[i] = maxf(0.0, lane_glow[i] - delta * 4.0)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(fit, fit))
	var looper := band.looper
	_draw_staff()
	# The tempo sits in one well, with its two buttons at the ends
	var well: Rect2 = buttons["bpm-"].rect.merge(buttons["bpm+"].rect)
	_box(well.grow(2.0), Color(WOOD_D, 0.82), 16.0, Color(BRASS, 0.5), 1.5)
	for id: String in TRANSPORT:
		_draw_transport(id)
	for i in Kit.INSTRUMENTS.size():
		var r: Rect2 = buttons["i%d" % i].rect
		var kit := Kit.INSTRUMENTS[i]
		var mine := i == band.inst
		var face := r
		if mine:
			_box(r.grow(3.0), Color(kit.color, 0.35), 18.0)
			_box(r, WOOD_D, 15.0, kit.color, 3.0)
		else:
			face = _plate(r, WOOD.lerp(kit.color, 0.25 * lane_glow[i]), 15.0, _held("i%d" % i))
		_draw_instrument(i, face.get_center(), r.size.x / 78.0 * (1.0 + 0.12 * lane_glow[i]), kit.color)
		if looper.has_notes(looper.section, i):
			draw_circle(r.position + Vector2(12.0, 12.0), 5.5, WOOD_D)
			draw_circle(r.position + Vector2(12.0, 12.0), 4.0, kit.color)
		if looper.muted[i]:
			draw_line(r.position + Vector2(9, 9), r.end - Vector2(9, 9), RED, 4.0, true)
	for id: String in BENDERS:
		var on: bool = band.mods[id]
		var face := _plate(buttons[id].rect, BRASS if on else CREAM, 20.0, on)
		var c := face.get_center()
		if id in ["flat", "sharp"]:
			draw_set_transform(c * fit * 0.3, 0.0, Vector2(fit, fit) * 0.7)
		_draw_bender(id, c, INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(fit, fit))
	_draw_stick()
	for b in 5:
		_draw_pad(b)
	if toast_left > 0.0:
		var a := minf(toast_left * 2.0, 1.0)
		var w := font.get_string_size(toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 48.0
		var r := Rect2((size_now.x - w) / 2.0, free_rect.position.y + (70.0 if wide else 8.0), w, 44.0)
		_box(r.grow(3.0), Color(WOOD_D, 0.8 * a), 25.0)
		_box(r, Color(CREAM, a), 22.0, Color(BRASS, a), 2.0)
		_text(r.get_center(), toast_text, 21, Color(INK, a))
	if menu_open:
		_draw_menu()
	if help_open:
		_draw_help()
	if book_open:
		_draw_book()


# ---- the sheet of music ----

func _draw_staff() -> void:
	var looper := band.looper
	var kit := Kit.INSTRUMENTS[band.inst]
	var live := looper.recording
	_box(Rect2(staff.position + Vector2(0, 5), staff.size).grow(4.0), Color(0, 0, 0, 0.35), 20.0)
	_box(staff.grow(4.0), RED if live else WOOD, 19.0, WOOD_D, 2.0)
	_box(staff, CREAM, 14.0, PAPER_D, 3.0)
	if live:
		_box(staff, Color(RED, 0.08), 14.0)
	var inner := Rect2(staff.position + Vector2(70.0, 34.0), staff.size - Vector2(92.0, 74.0))
	var row := inner.size.y / 5.0
	for i in 5:
		var y := inner.end.y - (i + 0.5) * row
		draw_line(Vector2(inner.position.x - 10.0, y), Vector2(inner.end.x + 10.0, y), Color(INK, 0.5), 1.5)
	draw_line(Vector2(inner.position.x - 10.0, inner.position.y + row * 0.5), Vector2(inner.position.x - 10.0, inner.end.y - row * 0.5), Color(INK, 0.6), 3.0)
	draw_circle(Vector2(staff.position.x + 34.0, inner.get_center().y), 25.0, WOOD_D)
	draw_arc(Vector2(staff.position.x + 34.0, inner.get_center().y), 25.0, 0.0, TAU, 28, kit.color, 2.0, true)
	_draw_instrument(band.inst, Vector2(staff.position.x + 34.0, inner.get_center().y), 0.58, kit.color)
	_text_left(staff.position + Vector2(20.0, 19.0), kit.name, 19, kit.color.darkened(0.55), title_font)
	var tune: String = Kit.note_name(band.key) + " " + Kit.TUNINGS[band.tuning].name
	var about := "Part %s  ·  %d bar%s  ·  %d bpm  ·  %s" % ["ABCD"[looper.section], looper.bars, "" if looper.bars == 1 else "s", int(looper.bpm), tune]
	_text_right(Vector2(staff.end.x - 20.0, staff.position.y + 19.0), about, 15, Color(INK, 0.7))

	var notes := looper.track(band.inst)
	var span := looper.length()
	if notes.is_empty() and not looper.playing and not looper.counting:
		# Nothing looping: the last few notes played, in a row
		for k in by_hand.size():
			var b: int = by_hand[k][0]
			var age: float = by_hand[k][1]
			var x := inner.position.x + (k + 0.5) * inner.size.x / 10.0
			_dot(Vector2(x, inner.end.y - (maxi(b, 0) + 0.5) * row), 12.0, b, clampf(1.6 - age * 0.25, 0.3, 1.0), by_hand[k][2])
	else:
		for k in looper.bars * Looper.BEATS + 1:
			var x := inner.position.x + inner.size.x * k / (looper.bars * Looper.BEATS)
			var bar := k % Looper.BEATS == 0
			draw_line(Vector2(x, inner.position.y + row * (0.5 if bar else 2.0)), Vector2(x, inner.end.y - row * (0.5 if bar else 2.0)),
					Color(INK, 0.6 if bar else 0.2), 2.0 if bar else 1.0)
		for note: Dictionary in notes:
			if note.t >= span:
				continue
			var b: int = note.b if note.b >= 0 else 2
			var at := Vector2(inner.position.x + inner.size.x * note.t / span, inner.end.y - (b + 0.5) * row)
			if kit.held:
				var w: float = minf(inner.size.x * note.d / span, inner.end.x - at.x)
				draw_rect(Rect2(at.x, at.y - 4.0, w, 8.0), Color(PAD_COLORS[b].darkened(0.15), 0.75))
			_dot(at, 10.0, note.b, 1.0, _label(band.inst, note.b, note.n))
		if looper.playing:
			var x := inner.position.x + inner.size.x * looper.pos / span
			draw_line(Vector2(x, inner.position.y - 5.0), Vector2(x, inner.end.y + 5.0), RED, 3.0)
			draw_colored_polygon([Vector2(x - 7.0, inner.position.y - 9.0), Vector2(x + 7.0, inner.position.y - 9.0), Vector2(x, inner.position.y)], RED)
	if looper.counting:
		_text(inner.get_center(), str(Looper.BEATS - looper._counted + 1), 66, RED, title_font)

	# Under the staff, a thin lane for each instrument's track
	var lanes := Rect2(inner.position.x, inner.end.y + 8.0, inner.size.x, 26.0)
	_box(lanes.grow_individual(10.0, 2.0, 10.0, 2.0), Color(WOOD_D, 0.88), 6.0)
	var lane := lanes.size.y / Kit.INSTRUMENTS.size()
	for i in Kit.INSTRUMENTS.size():
		var c: Color = Kit.INSTRUMENTS[i].color
		var y := lanes.position.y + i * lane
		if i == band.inst:
			draw_rect(Rect2(lanes.position.x - 8.0, y, lanes.size.x + 16.0, lane), Color(c, 0.22))
		var a := (0.3 if looper.muted[i] else 0.85) + 0.15 * lane_glow[i]
		for note: Dictionary in looper.sections[looper.section][i]:
			if note.t < span:
				draw_rect(Rect2(lanes.position.x + lanes.size.x * note.t / span, y + 0.5,
						maxf(3.0, lanes.size.x * minf(note.d, 0.5) / span * 0.6), lane - 1.0), Color(c, a))


# A note on the staff: a small copy of the button that played it, with the note's name
func _dot(at: Vector2, r: float, b: int, alpha: float, label := "") -> void:
	var c: Color = PAD_COLORS[b] if b >= 0 else PAPER_D
	draw_circle(at, r + 1.8, Color(INK, alpha))
	draw_circle(at, r, Color(c.lerp(CREAM, 1.0 - alpha), 1.0))
	_text(at, label, int(r * (1.25 if label.length() == 1 else 0.95)), Color(INK, alpha))


# What is written on a note: its name, or the first letter of the drum
func _label(inst: int, b: int, n: int) -> String:
	if Kit.is_drums(inst):
		return Kit.DRUM_NAMES[Kit.drum(b, n)].left(2)
	return Kit.note_name(n)


# ---- the loop station ----

func _draw_transport(id: String) -> void:
	var looper := band.looper
	var r: Rect2 = buttons[id].rect
	var kit := Kit.INSTRUMENTS[band.inst]
	var down := _held(id)
	var on := false
	var beat := looper.beat_phase()
	match id:
		"play":
			on = looper.playing
		"mute":
			on = looper.muted[band.inst]
		"metro":
			on = looper.metronome
	var s := Band._numbered(id, "s")
	if s >= 0:
		on = s == looper.section
	if id == "bpm":
		_text(r.get_center() + Vector2(0, -6), str(int(looper.bpm)), 25, CREAM, title_font)
		_text(r.get_center() + Vector2(0, 17), "BPM", 11, Color(BRASS, 0.9))
		return
	var small := id == "bpm-" or id == "bpm+"
	var face := _plate(r.grow(-3.0) if small else r, BRASS if on or small else WOOD, 13.0, down or on)
	var c := face.get_center()
	var ink := INK if on or small else CREAM
	if s >= 0:
		var blink := s == looper.queued and fmod(band.time, 0.4) < 0.2
		_text(c, "ABCD"[s], 24, GOLD if blink else ink, title_font)
		if not looper.section_empty(s):
			draw_circle(Vector2(face.end.x - 9.0, face.position.y + 9.0), 4.0, INK if on else GOLD)
		return
	match id:
		"rec":
			var pulse := 1.0 + (0.16 * pow(1.0 - beat, 2.0) if looper.recording and beat >= 0.0 else 0.0)
			if looper.recording:
				draw_circle(c, 23.0 * pulse, Color(RED, 0.35))
			draw_circle(c, 17.0, Color("3a2416"))
			draw_circle(c, 14.0 * pulse, RED.lightened(0.15) if looper.recording else RED.darkened(0.25))
			draw_circle(c + Vector2(-4.5, -5.0), 4.0, Color(1, 1, 1, 0.55 if looper.recording else 0.3))
		"play":
			if looper.playing or looper.counting:
				_box(Rect2(c - Vector2(11, 11), Vector2(22, 22)), ink, 4.0)
			else:
				draw_colored_polygon([c + Vector2(-9, -13), c + Vector2(14, 0), c + Vector2(-9, 13)], ink)
		"undo":
			var faint := Color(ink, 1.0 if looper.can_undo() else 0.35)
			draw_arc(c + Vector2(1, 3), 11.0, deg_to_rad(-165.0), deg_to_rad(80.0), 16, faint, 3.5, true)
			_arrow(c + Vector2(-11.5, 0.5), Vector2(-0.25, 1.0), 7.5, faint)
		"clear":
			# A dustbin for this instrument's track
			var faint := Color(kit.color, 1.0 if not looper.track(band.inst).is_empty() else 0.35)
			draw_line(c + Vector2(-11, -8), c + Vector2(11, -8), faint, 3.5, true)
			draw_polyline([c + Vector2(-4, -8), c + Vector2(-4, -13), c + Vector2(4, -13), c + Vector2(4, -8)], faint, 2.5, true)
			draw_polyline([c + Vector2(-8, -5), c + Vector2(-6.5, 13), c + Vector2(6.5, 13), c + Vector2(8, -5)], faint, 3.0, true)
			for x: float in [-2.5, 2.5]:
				draw_line(c + Vector2(x, -1), c + Vector2(x, 9), faint, 2.0, true)
		"mute":
			var tone: Color = INK if on else kit.color
			draw_colored_polygon([c + Vector2(-14, -5), c + Vector2(-8, -5), c + Vector2(0, -12), c + Vector2(0, 12),
					c + Vector2(-8, 5), c + Vector2(-14, 5)], tone)
			if looper.muted[band.inst]:
				draw_line(c + Vector2(5, -7), c + Vector2(15, 7), RED.darkened(0.2), 3.5, true)
				draw_line(c + Vector2(15, -7), c + Vector2(5, 7), RED.darkened(0.2), 3.5, true)
			else:
				draw_arc(c + Vector2(1, 0), 7.0, -0.9, 0.9, 8, tone, 2.5, true)
				draw_arc(c + Vector2(1, 0), 13.0, -0.9, 0.9, 10, tone, 2.5, true)
		"metro":
			var body := PackedVector2Array([c + Vector2(-5, -15), c + Vector2(5, -15), c + Vector2(12, 12), c + Vector2(-12, 12)])
			draw_colored_polygon(body, Color(ink, 0.22))
			draw_polyline(body + PackedVector2Array([body[0]]), ink, 2.5, true)
			draw_line(c + Vector2(-13, 13), c + Vector2(13, 13), ink, 4.0, true)
			var swing := sin(looper.pos * PI) * 0.45 if looper.playing else 0.3
			var arm := Vector2(sin(swing), -cos(swing))
			draw_line(c + Vector2(0, 10), c + Vector2(0, 10) + arm * 25.0, ink, 2.5, true)
			draw_circle(c + Vector2(0, 10) + arm * 15.0, 3.6, ink)
		"bpm-":
			draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), ink, 4.0, true)
		"bpm+":
			draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), ink, 4.0, true)
			draw_line(c + Vector2(0, -8), c + Vector2(0, 8), ink, 4.0, true)
		"bars":
			_text(c + Vector2(0, -6), str(looper.bars), 25, ink, title_font)
			_text(c + Vector2(0, 17), "BAR" if looper.bars == 1 else "BARS", 11, Color(BRASS, 0.9))
		"menu":
			for k in 3:
				draw_line(c + Vector2(-12, -8 + k * 8), c + Vector2(12, -8 + k * 8), ink, 3.5, true)


# ---- the buttons that play ----

func _draw_pad(b: int) -> void:
	var r: Rect2 = buttons["n%d" % b].rect
	var c := r.get_center()
	var rad := r.size.x / 2.0
	var on := _held("n%d" % b)
	var col: Color = PAD_COLORS[b]
	draw_circle(c + Vector2(0, 6), rad + 2.0, Color(0, 0, 0, 0.4))
	draw_circle(c, rad + 2.0, WOOD_D)
	draw_circle(c, rad - 1.0, col.darkened(0.4))
	c += Vector2(0, 2.0 if on else -4.0)
	draw_circle(c, rad * 0.9, col.lightened(0.45) if on else col)
	draw_arc(c, rad * 0.9 - 2.0, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 2.0, true)
	_oval(c + Vector2(0, -rad * 0.45), Vector2(rad * 0.56, rad * 0.24), Color(1, 1, 1, 0.3))
	var ink := col.darkened(0.72)
	if Kit.is_drums(band.inst):
		_text(c + Vector2(0, 2), Kit.DRUM_NAMES[Kit.drum(b, band.pad_note(b))], int(rad * 0.44), ink)
	else:
		var label := Kit.note_name(band.pad_note(b))
		_text(c + Vector2(0, 3), label, int(rad * (1.0 if label.length() == 1 else 0.78)), ink)


# The stick, in its well: a grey ridged cap on a stalk, like the one it is copied from
func _draw_stick() -> void:
	var c := stick_at
	draw_circle(c + Vector2(0, 5), stick_reach + 4.0, Color(0, 0, 0, 0.4))
	draw_circle(c, stick_reach + 4.0, WOOD_D)
	draw_arc(c, stick_reach + 1.0, 0.0, TAU, 48, BRASS, 3.0, true)
	draw_circle(c, stick_reach - 4.0, Color("1c1420"))
	# (what each way does)
	var faint := Color(CREAM, 0.55)
	for x: float in [-4.0, 4.0]:
		draw_line(c + Vector2(x, -stick_reach + 9.0), c + Vector2(x, -stick_reach + 23.0), faint, 2.0, true)
	for y: float in [13.0, 19.0]:
		draw_line(c + Vector2(-8, -stick_reach + y + 1.5), c + Vector2(8, -stick_reach + y - 1.5), faint, 2.5, true)
	draw_line(c + Vector2(-4, stick_reach - 25.0), c + Vector2(-4, stick_reach - 9.0), faint, 2.0, true)
	draw_arc(c + Vector2(-1, stick_reach - 13.0), 4.5, -PI / 2.0, PI / 2.0, 8, faint, 2.0, true)
	for side: float in [-1.0, 1.0]:
		var wave := PackedVector2Array()
		for k in 9:
			wave.append(c + Vector2(side * (stick_reach - 16.0) + (k - 4) * 2.2, sin(k * 1.6) * 3.5))
		draw_polyline(wave, faint, 2.0, true)
	var top := c + Vector2(stick_now.x, -stick_now.y) * stick_reach * 0.5
	draw_line(c, top, Color("0c080e"), 22.0, true)
	draw_circle(top + Vector2(0, 4), 37.0, Color(0, 0, 0, 0.45))
	draw_circle(top, 37.0, Color("5e6068"))
	draw_circle(top - Vector2(0, 2), 33.0, Color("a9acb6"))
	for r: float in [24.0, 16.0, 8.0]:
		draw_arc(top - Vector2(0, 2), r, 0.0, TAU, 28, Color("7d808a"), 2.0, true)
	_oval(top + Vector2(-9, -15), Vector2(13, 6), Color(1, 1, 1, 0.28))


func _draw_bender(id: String, c: Vector2, ink: Color) -> void:
	match id:
		"sharp":
			for x: float in [-7.0, 7.0]:
				draw_line(c + Vector2(x, -22), c + Vector2(x, 22), ink, 3.5, true)
			for y: float in [-8.0, 8.0]:
				draw_line(c + Vector2(-15, y + 4), c + Vector2(15, y - 4), ink, 6.0, true)
		"flat":
			draw_line(c + Vector2(-9, -27), c + Vector2(-9, 18), ink, 4.0, true)
			draw_polyline([c + Vector2(-9, 2), c + Vector2(-1, -5), c + Vector2(7, -4), c + Vector2(10, 3),
					c + Vector2(4, 11), c + Vector2(-9, 18)], ink, 4.0, true)
		"up":
			_arrow(c + Vector2(-27, -2), Vector2.UP, 11.0, ink)
			_text(c + Vector2(13, 0), "toys" if Kit.is_drums(band.inst) else "octave", 15, Color(ink, 0.85))
		"down":
			_arrow(c + Vector2(-27, 1), Vector2.DOWN, 11.0, ink)
			_text(c + Vector2(13, 0), "big" if Kit.is_drums(band.inst) else "octave", 15, Color(ink, 0.85))


# A little picture of instrument `i`, about 54 across at scale 1, in `col` with its own shade and shine
func _draw_instrument(i: int, c: Vector2, k: float, col: Color) -> void:
	var dark := col.darkened(0.45)
	var pale := col.lightened(0.5)
	var hole := Color("1c1420")
	match i:
		Kit.PICCOLO:
			var a := Vector2(-25, 11) * k
			var b := Vector2(25, -11) * k
			draw_line(c + a, c + b, dark, 10.0 * k, true)
			draw_line(c + a, c + b, col, 6.5 * k, true)
			for t: float in [0.0, 0.22, 1.0]:
				draw_line(c + a.lerp(b, t) - (b - a).normalized() * 2.0 * k, c + a.lerp(b, t) + (b - a).normalized() * 2.0 * k, pale, 10.0 * k)
			draw_circle(c + a.lerp(b, 0.11), 2.6 * k, hole)
			for t: float in [0.36, 0.48, 0.6, 0.72, 0.84]:
				draw_circle(c + a.lerp(b, t), 2.9 * k, pale)
				draw_circle(c + a.lerp(b, t), 1.4 * k, dark)
		Kit.TRUMPET:
			draw_rect(Rect2(c + Vector2(-18, 3) * k, Vector2(23, 10) * k), dark, false, 3.2 * k)
			draw_line(c + Vector2(-24, 0) * k, c + Vector2(10, 0) * k, col, 5.5 * k, true)
			draw_colored_polygon([c + Vector2(-29, -4) * k, c + Vector2(-23, -2) * k, c + Vector2(-23, 2) * k, c + Vector2(-29, 4) * k], pale)
			draw_colored_polygon([c + Vector2(6, -3) * k, c + Vector2(25, -15) * k, c + Vector2(25, 15) * k, c + Vector2(6, 3) * k], col)
			_oval(c + Vector2(25, 0) * k, Vector2(4, 15) * k, dark)
			_oval(c + Vector2(25.5, 0) * k, Vector2(2, 10.5) * k, hole)
			for x: float in [-14.0, -7.0, 0.0]:
				draw_rect(Rect2(c + Vector2(x - 2.6, -10) * k, Vector2(5.2, 19) * k), dark)
				draw_circle(c + Vector2(x, -12.5) * k, 3.0 * k, pale)
		Kit.ACCORDION:
			draw_rect(Rect2(c + Vector2(-11, -15) * k, Vector2(22, 30) * k), CREAM)
			for x: float in [-7.0, -2.3, 2.3, 7.0]:
				draw_line(c + Vector2(x, -15) * k, c + Vector2(x, 15) * k, hole, 2.0 * k)
			for x: float in [-27.0, 11.0]:
				_box(Rect2(c + Vector2(x, -18) * k, Vector2(16, 36) * k), col, 3.0 * k)
				draw_rect(Rect2(c + Vector2(x, -18) * k, Vector2(16, 4) * k), pale)
				draw_rect(Rect2(c + Vector2(x, 14) * k, Vector2(16, 4) * k), dark)
			draw_rect(Rect2(c + Vector2(-25, -12) * k, Vector2(6, 24) * k), CREAM)
			for y: float in [-9.0, -4.0, 1.0, 6.0]:
				draw_rect(Rect2(c + Vector2(-25, y) * k, Vector2(3.5, 2.6) * k), hole)
			for y: float in [-8.0, 0.0, 8.0]:
				for x: float in [16.0, 22.0]:
					draw_circle(c + Vector2(x, y) * k, 1.9 * k, CREAM)
		Kit.GUITAR:
			var along := Vector2(0.78, -0.62)
			var across := Vector2(0.62, 0.78)
			var o := c + (along * -8.0) * k
			draw_line(o + along * 10.0 * k, o + along * 33.0 * k, dark, 6.0 * k, true)
			draw_colored_polygon([o + (along * 31.0 - across * 4.5) * k, o + (along * 40.0 - across * 5.5) * k,
					o + (along * 40.0 + across * 5.5) * k, o + (along * 31.0 + across * 4.5) * k], dark)
			draw_circle(o - along * 5.0 * k, 16.0 * k, dark)
			draw_circle(o + along * 9.0 * k, 12.0 * k, dark)
			draw_circle(o - along * 5.0 * k, 13.5 * k, col)
			draw_circle(o + along * 9.0 * k, 9.5 * k, col)
			draw_circle(o + along * 2.0 * k, 4.8 * k, hole)
			draw_line(o + (along * -13.0 - across * 5.0) * k, o + (along * -13.0 + across * 5.0) * k, hole, 2.6 * k)
			for off: float in [-1.6, 1.6]:
				draw_line(o + (along * -13.0 + across * off) * k, o + (along * 38.0 + across * off) * k, Color(pale, 0.9), 1.0 * k, true)
		Kit.TUBA:
			draw_arc(c + Vector2(-3, 9) * k, 12.0 * k, 0.0, TAU, 22, dark, 8.5 * k, true)
			draw_arc(c + Vector2(-3, 9) * k, 12.0 * k, 0.0, TAU, 22, col, 5.5 * k, true)
			draw_line(c + Vector2(-15, 4) * k, c + Vector2(-25, -6) * k, col, 3.5 * k, true)
			draw_colored_polygon([c + Vector2(4, 6) * k, c + Vector2(14, 6) * k, c + Vector2(25, -19) * k, c + Vector2(-7, -19) * k], col)
			_oval(c + Vector2(9, -19) * k, Vector2(17, 5.5) * k, pale)
			_oval(c + Vector2(9, -19) * k, Vector2(13, 3.4) * k, hole)
			for x: float in [-8.0, -3.0, 2.0]:
				draw_line(c + Vector2(x, 2) * k, c + Vector2(x, 9) * k, pale, 2.6 * k)
		Kit.BELLS:
			_box(Rect2(c + Vector2(-3.5, -24) * k, Vector2(7, 11) * k), dark, 2.0 * k)
			draw_colored_polygon([c + Vector2(-6, -15) * k, c + Vector2(6, -15) * k, c + Vector2(12, -6) * k, c + Vector2(14, 7) * k,
					c + Vector2(20, 13) * k, c + Vector2(-20, 13) * k, c + Vector2(-14, 7) * k, c + Vector2(-12, -6) * k], col)
			draw_colored_polygon([c + Vector2(-20, 13) * k, c + Vector2(20, 13) * k, c + Vector2(18, 17) * k, c + Vector2(-18, 17) * k], dark)
			draw_line(c + Vector2(-7, -9) * k, c + Vector2(-10, 5) * k, pale, 3.0 * k, true)
			draw_circle(c + Vector2(0, 21) * k, 4.6 * k, dark)
		Kit.ORGAN:
			# A rank of pipes, tall at the ends and short in the middle, over a keyboard
			for j in 7:
				var x := -21.0 + j * 7.0
				var tall := 12.0 + absf(j - 3.0) * 6.0
				_box(Rect2(c + Vector2(x - 2.6, 6.0 - tall) * k, Vector2(5.2, tall) * k), col if j % 2 == 0 else pale, 2.0 * k)
				draw_line(c + Vector2(x - 1.6, 1.5) * k, c + Vector2(x + 1.6, 1.5) * k, hole, 1.6 * k)
			_box(Rect2(c + Vector2(-25, 6) * k, Vector2(50, 13) * k), dark, 3.0 * k)
			_box(Rect2(c + Vector2(-22, 9) * k, Vector2(44, 7) * k), CREAM, 1.5 * k)
			for j in 7:
				draw_line(c + Vector2(-17.0 + j * 5.6, 9) * k, c + Vector2(-17.0 + j * 5.6, 13) * k, hole, 2.0 * k)
		Kit.BASSOON:
			# A long tube stood on a slant, a bell at its top, the crook curling off it and keys down it
			draw_line(c + Vector2(-13, 22) * k, c + Vector2(13, -20) * k, dark, 9.0 * k, true)
			draw_line(c + Vector2(-13, 22) * k, c + Vector2(13, -20) * k, col, 6.0 * k, true)
			draw_line(c + Vector2(-16, 14) * k, c + Vector2(-4, -6) * k, col.darkened(0.2), 5.0 * k, true)
			draw_circle(c + Vector2(14, -22) * k, 5.2 * k, dark)
			draw_circle(c + Vector2(14, -22) * k, 3.6 * k, pale)
			draw_arc(c + Vector2(-12, -9) * k, 9.0 * k, -PI * 0.1, -PI * 1.05, 10, pale, 2.2 * k, true)
			for t: float in [0.3, 0.45, 0.6, 0.75]:
				draw_circle(c + Vector2(-13, 22).lerp(Vector2(13, -20), t) * k, 1.8 * k, pale)
		Kit.CHOIR:
			# Three of the little folk with their mouths open: a satyr's horns, and an imp's straw hat
			for j in 3:
				var at := c + Vector2(-17.0 + j * 17.0, -5.0 if j == 1 else 5.0) * k
				if j == 0:
					draw_line(at + Vector2(-5, -6) * k, at + Vector2(-8, -14) * k, pale, 3.0 * k, true)
					draw_line(at + Vector2(5, -6) * k, at + Vector2(8, -14) * k, pale, 3.0 * k, true)
				draw_circle(at, 9.6 * k, dark)
				draw_circle(at, 8.0 * k, col)
				draw_circle(at + Vector2(0, 3) * k, 3.4 * k, hole)
				draw_circle(at + Vector2(-3.2, -2.4) * k, 1.2 * k, hole)
				draw_circle(at + Vector2(3.2, -2.4) * k, 1.2 * k, hole)
				if j == 2:
					draw_colored_polygon([at + Vector2(-13, -5) * k, at + Vector2(0, -19) * k, at + Vector2(13, -5) * k], pale)
		Kit.THEREMIN:
			_box(Rect2(c + Vector2(-17, 2) * k, Vector2(34, 17) * k), dark, 3.0 * k)
			_box(Rect2(c + Vector2(-15, 4) * k, Vector2(30, 13) * k), col.darkened(0.2), 2.0 * k)
			for x: float in [-6.0, 4.0]:
				draw_circle(c + Vector2(x, 10.5) * k, 3.0 * k, hole)
			draw_line(c + Vector2(13, 3) * k, c + Vector2(13, -24) * k, col, 3.0 * k, true)
			draw_circle(c + Vector2(13, -24) * k, 3.2 * k, col)
			draw_arc(c + Vector2(-20, 8) * k, 7.0 * k, PI * 0.5, PI * 1.5, 10, col, 3.0 * k, true)
			for r: float in [7.0, 12.0]:
				draw_arc(c + Vector2(13, -14) * k, r * k, PI * 0.75, PI * 1.25, 8, Color(col, 0.7), 2.0 * k, true)
		Kit.VIOLA:
			var up := Vector2(0.7, -0.7)
			var o := c + Vector2(-6, 6) * k
			draw_line(o + up * 8.0 * k, o + up * 31.0 * k, dark, 5.0 * k, true)
			draw_circle(o + up * 33.0 * k, 4.0 * k, dark)
			draw_circle(o - up * 5.0 * k, 13.5 * k, dark)
			draw_circle(o + up * 9.0 * k, 10.5 * k, dark)
			draw_circle(o - up * 5.0 * k, 11.5 * k, col)
			draw_circle(o + up * 9.0 * k, 8.5 * k, col)
			for side: float in [-1.0, 1.0]:
				draw_circle(o + (up * 2.0 + Vector2(0.7, 0.7) * 11.0 * side) * k, 3.4 * k, dark)
			draw_line(o - up * 12.0 * k, o + up * 30.0 * k, Color(pale, 0.9), 1.4 * k, true)
			draw_line(c + Vector2(-25, -12) * k, c + Vector2(24, 12) * k, CREAM, 2.4 * k, true)
		Kit.DRUMS:
			draw_rect(Rect2(c + Vector2(-20, -2) * k, Vector2(40, 18) * k), col)
			_oval(c + Vector2(0, 16) * k, Vector2(20, 6.5) * k, col)
			_oval(c + Vector2(0, 16) * k, Vector2(20, 6.5) * k, Color(dark, 0.45))
			for x: float in [-13.0, 0.0, 13.0]:
				draw_line(c + Vector2(x, 5) * k, c + Vector2(x, 20 - absf(x) * 0.12) * k, pale, 2.4 * k)
			_oval(c + Vector2(0, -2) * k, Vector2(21.5, 8) * k, dark)
			_oval(c + Vector2(0, -3) * k, Vector2(18.5, 6) * k, CREAM)
			for side: float in [-1.0, 1.0]:
				draw_line(c + Vector2(24 * side, -24) * k, c + Vector2(5 * side, -6) * k, Color("e9cf9a"), 3.2 * k, true)
				draw_circle(c + Vector2(5 * side, -6) * k, 2.8 * k, Color("e9cf9a"))


# ---- the menu and the help ----

func _sheet(r: Rect2, title: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, size_now), Color(0.05, 0.02, 0.05, 0.62))
	_box(Rect2(r.position + Vector2(0, 6), r.size).grow(5.0), Color(0, 0, 0, 0.4), 24.0)
	_box(r.grow(5.0), WOOD, 24.0, WOOD_D, 2.0)
	_box(r, CREAM, 18.0, PAPER_D, 3.0)
	_text(r.position + Vector2(r.size.x / 2.0, 36.0), title, 30, INK, title_font)
	draw_line(r.position + Vector2(40.0, 58.0), r.position + Vector2(r.size.x - 40.0, 58.0), Color(INK, 0.35), 2.0)


func _draw_menu() -> void:
	var looper := band.looper
	_sheet(menu_rect, "One Man Band")
	var snaps := {0.25: "sixteenths", 0.5: "eighths", 0.0: "off"}
	var words := {
		"tuning": "Tuning: " + Kit.TUNINGS[band.tuning].name,
		"key": "Key: " + Kit.note_name(band.key),
		"snap": "Snap to: " + snaps.get(looper.snap, "off"),
		"chain": "Song mode: " + ("A to D in turn" if looper.chain else "off"),
		"demo": "Load the house band",
		"new": "New song",
		"radio": "Send to the station radio",
		"export": "Save as MIDI file",
		"midi": "MIDI keyboard: " + ("on" if band.midi_open else "off"),
		"sound": "Sound: " + ("on" if band.synth.sound else "off"),
		"songbook": "Song book",
		"help": "How to play",
		"close": "Back",
	}
	for id: String in MENU:
		var last := id == "close"
		var face := _plate(buttons["menu:" + id].rect, BRASS if last else WOOD, 13.0, _held("menu:" + id))
		_text(face.get_center(), words[id], 20, INK if last else CREAM)


func _draw_help() -> void:
	var w := minf(size_now.x - 40.0, 660.0)
	var lines := [
		"The five round buttons are five notes, lowest on the left and highest on the right, each with its name on it. Hold one for as long as you want the note. The stick bends what is sounding: up and down for pitch, sideways for a wobble. Under it are four keys that stay on until you tap them again: flat and sharp move the buttons a half step (so every note can be had), and the two octave keys drop or raise them an octave.",
		"Along the bottom is everything he carries. Tap one and he plays that. The last is the choir: the little folk line up and sing, and he conducts. On the drums the two octave keys change the kit, to the big low drums or the toys.",
		"Press the red lamp, wait for four ticks, and play. It comes round again, and again. Change instrument and play over it. The arrow takes back the last thing you added, the dustbin empties this instrument's track, and A B C D are four loops to move between.",
		"Some tunes do things. They are in the song book, in the menu.",
		"Keys: A S D F G for notes, arrows for the stick, C and V for flat and sharp, Q and E for octaves, 1 to 0, - and = for instruments, Space to play, R to record, Z to take back.",
	]
	var h := 84.0 + 50.0
	for line: String in lines:
		h += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w - 56.0, 18).y + 12.0
	var r := Rect2((size_now.x - w) / 2.0, maxf(10.0, (size_now.y - h) / 2.0), w, h)
	_sheet(r, "One Man Band")
	var y := r.position.y + 88.0
	for line: String in lines:
		draw_multiline_string(font, Vector2(r.position.x + 28.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, w - 56.0, 18, -1, INK)
		y += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w - 56.0, 18).y + 12.0
	_text(Vector2(size_now.x / 2.0, r.end.y - 22.0), "Tap anywhere", 16, Color(INK, 0.55))


# The tunes that do something, each as the buttons to press and what comes of it
func _draw_book() -> void:
	var w := minf(size_now.x - 40.0, 660.0)
	var row := 58.0
	var h := 84.0 + 34.0 + Kit.TUNES.size() * row + 40.0
	var r := Rect2((size_now.x - w) / 2.0, maxf(10.0, (size_now.y - h) / 2.0), w, h)
	_sheet(r, "Song Book")
	var y := r.position.y + 84.0
	_text(Vector2(size_now.x / 2.0, y), "Play one on any instrument but the drums", 17, Color(INK, 0.7))
	y += 44.0
	for tune in Kit.TUNES:
		_text_left(Vector2(r.position.x + 28.0, y - 9.0), tune.name, 19, INK, title_font)
		_text_left(Vector2(r.position.x + 28.0, y + 14.0), tune.hint, 15, Color(INK, 0.65))
		var pads: Array = tune.pads
		for k in pads.size():
			_dot(Vector2(r.end.x - 28.0 - (pads.size() - 1 - k) * 36.0 - 14.0, y), 14.0, pads[k], 1.0, Kit.note_name(band.key + Kit.TUNINGS[band.tuning].steps[pads[k]]))
		y += row
	_text(Vector2(size_now.x / 2.0, r.end.y - 22.0), "Tap anywhere", 16, Color(INK, 0.55))


# ---- the pieces everything is drawn from ----

func _box(r: Rect2, fill: Color, radius: float, edge := Color.TRANSPARENT, width := 0.0) -> void:
	var name := "%s %s %s %s" % [fill.to_html(), radius, edge.to_html(), width]
	if not _boxes.has(name):
		if _boxes.size() > 500:
			_boxes.clear()
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(int(radius))
		box.border_color = edge
		box.set_border_width_all(int(width))
		box.anti_aliasing = true
		_boxes[name] = box
	draw_style_box(_boxes[name], r)


# A button with some thickness to it: a shadow, a dark side, and a face that sinks when `pressed`.
# Returns the face, for whatever goes on it.
func _plate(r: Rect2, base: Color, radius: float, pressed := false) -> Rect2:
	_box(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.38), radius)
	_box(r, base.darkened(0.55), radius)
	var face := Rect2(r.position + Vector2(2.0, 4.0 if pressed else 1.0), r.size - Vector2(4.0, 7.0))
	_box(face, base.darkened(0.12) if pressed else base, radius - 2.0, base.lightened(0.22), 1.5)
	_box(Rect2(face.position + Vector2(4.0, 3.0), Vector2(face.size.x - 8.0, face.size.y * 0.42)), Color(1, 1, 1, 0.1), radius - 5.0)
	return face


func _text(c: Vector2, text: String, px: int, col: Color, face: Font = null) -> void:
	var f := face if face != null else font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(f, Vector2(c.x - w / 2.0, c.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_left(at: Vector2, text: String, px: int, col: Color, face: Font = null) -> void:
	draw_string(face if face != null else font, Vector2(at.x, at.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_right(at: Vector2, text: String, px: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(font, Vector2(at.x - w, at.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _arrow(c: Vector2, dir: Vector2, r: float, col: Color) -> void:
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon([c + d * r, c - d * r * 0.7 + side * r, c - d * r * 0.7 - side * r], col)


func _oval(c: Vector2, r: Vector2, col: Color) -> void:
	var points := PackedVector2Array()
	for k in 18:
		points.append(c + Vector2(cos(TAU * k / 18.0), sin(TAU * k / 18.0)) * r)
	draw_colored_polygon(points, col)
