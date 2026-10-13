class_name Hud
extends Control
## Every control on the screen, drawn by hand and pressed by any number of fingers at once: the
## staff along the top, the loop station under it, the instruments, and the five note buttons
## with their four benders.
##
## There are no Button nodes. Each control is a rectangle in `buttons`; a finger going down on
## one calls Band.press(id), and coming up, Band.release(id). Keys stand in for fingers.

const PANEL := Color(0.17, 0.05, 0.08, 0.84)
const PAPER := Color("efdfae")
const A_BLUE := Color("3d7dff")
const C_YELLOW := Color("f8ca22")
const REC_RED := Color("ea3a2c")
const KEY := Color(0.09, 0.07, 0.13, 0.8)
const KEY_ON := Color(0.38, 0.31, 0.55, 0.96)
const TRANSPORT := ["rec", "play", "undo", "clear", "mute", "metro", "bpm-", "bpm", "bpm+", "bars", "s0", "s1", "s2", "s3", "menu"]
const MENU := ["tuning", "key", "snap", "chain", "demo", "new", "export", "midi", "sound", "help", "close"]
const ARROWS := [Vector2.ZERO, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT, Vector2.UP]

var band: Band
var font: Font
var buttons := {}
var fingers := {}
var lit := {}
var wide := true
var size_now := Vector2(1280, 720)
var staff := Rect2()
var free_rect := Rect2(0, 0, 1280, 720)
var menu_rect := Rect2()
var menu_open := false
var help_open := false
var toast_text := ""
var toast_left := 0.0
var by_hand: Array = []        # the last notes played, for the staff when nothing is looping: [button, seconds since]
var lane_glow: Array[float] = []
var _boxes := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	for i in Kit.INSTRUMENTS.size():
		lane_glow.append(0.0)


func layout(s: Vector2) -> void:
	size_now = s
	buttons.clear()
	wide = s.x >= s.y * 1.15
	var m := 12.0
	var sw := minf(s.x - 2.0 * m, 880.0)
	staff = Rect2((s.x - sw) / 2.0, m, sw, 150.0)
	var y := staff.end.y + 8.0
	if wide:
		y = _row(TRANSPORT, y, 54.0, minf(s.x - 2.0 * m, 980.0))
	else:
		y = _row(TRANSPORT.slice(0, 6) + ["menu"], y, 56.0, s.x - 2.0 * m)
		y = _row(TRANSPORT.slice(6, 14), y, 56.0, s.x - 2.0 * m)

	var cc := Vector2(s.x - 150.0, s.y - 215.0)
	for b in range(1, 5):
		buttons["n%d" % b] = {"rect": _around(cc + ARROWS[b] * Vector2(84, 84), 46.0), "round": true}
	buttons["n0"] = {"rect": _around(cc + Vector2(-190.0, 100.0), 58.0), "round": true}
	var mods := ["flat", "sharp", "down", "up"]
	for k in 4:
		buttons[mods[k]] = {"rect": Rect2(m + 4.0 + (k % 2) * 108.0, s.y - m - 210.0 + (k / 2) * 108.0, 98.0, 98.0)}

	var count := Kit.INSTRUMENTS.size()
	var x0 := m
	var x1 := s.x - m
	var top := s.y - 345.0 - 14.0
	if wide:
		x0 = m + 4.0 + 206.0 + 14.0
		x1 = cc.x - 190.0 - 58.0 - 14.0
		top = s.y - m
	var side := clampf((x1 - x0 - (count - 1) * 8.0) / count, 40.0, 92.0)
	var start := (x0 + x1 - count * side - (count - 1) * 8.0) / 2.0
	for i in count:
		buttons["i%d" % i] = {"rect": Rect2(start + i * (side + 8.0), top - side, side, side)}
	free_rect = Rect2(x0, staff.end.y + 4.0, x1 - x0, top - side - 12.0 - staff.end.y) if wide else Rect2(0.0, y, s.x, top - side - 8.0 - y)

	var cell := Vector2(minf(300.0, (s.x - 60.0) / 2.0), 58.0)
	menu_rect = Rect2((s.x - cell.x * 2.0 - 36.0) / 2.0, (s.y - 6.0 * (cell.y + 8.0) - 80.0) / 2.0,
			cell.x * 2.0 + 36.0, 6.0 * (cell.y + 8.0) + 80.0)
	for k in MENU.size():
		var at := menu_rect.position + Vector2(12.0 + (k % 2) * (cell.x + 12.0), 60.0 + (k / 2) * (cell.y + 8.0))
		buttons["menu:" + MENU[k]] = {"rect": Rect2(at, cell if k < 10 else Vector2(cell.x * 2.0 + 12.0, cell.y))}


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


func toast(text: String) -> void:
	toast_text = text
	toast_left = 4.0


func played_by_hand(b: int) -> void:
	by_hand.append([b, 0.0])
	if by_hand.size() > 10:
		by_hand.pop_front()
	lane_glow[band.inst] = 1.0


func played_by_loop(i: int) -> void:
	lane_glow[i] = 1.0


# A key that stands for button `id`
func key(id: String, down: bool) -> void:
	var finger := "key:" + id
	if down and not fingers.has(finger):
		if help_open or (menu_open and id != "close"):
			help_open = false
			return
		fingers[finger] = id
		_down(id)
	elif not down and fingers.has(finger):
		_up(fingers[finger])
		fingers.erase(finger)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if help_open:
				help_open = false
				return
			var id := _hit(event.position)
			if menu_open and id == "":
				menu_open = menu_rect.has_point(event.position)
				return
			if id != "":
				fingers[event.index] = id
				_down(id)
		elif fingers.has(event.index):
			_up(fingers[event.index])
			fingers.erase(event.index)
	elif event is InputEventScreenDrag and fingers.has(event.index):
		# Sliding from one note button onto another plays it
		var now: String = fingers[event.index]
		if Band._numbered(now, "n") >= 0:
			var id := _hit(event.position)
			if id != now and Band._numbered(id, "n") >= 0:
				_up(now)
				fingers[event.index] = id
				_down(id)


func _hit(at: Vector2) -> String:
	for id: String in buttons:
		if id.begins_with("menu:") != menu_open or id == "bpm":
			continue
		var r: Rect2 = buttons[id].rect
		if buttons[id].has("round"):
			if at.distance_to(r.get_center()) <= r.size.x * 0.5 * 1.12:
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


func _process(delta: float) -> void:
	toast_left = maxf(0.0, toast_left - delta)
	for note: Array in by_hand:
		note[1] += delta
	for i in lane_glow.size():
		lane_glow[i] = maxf(0.0, lane_glow[i] - delta * 4.0)
	queue_redraw()


func _draw() -> void:
	var looper := band.looper
	_draw_staff()
	for id: String in TRANSPORT:
		_draw_transport(id)
	for i in Kit.INSTRUMENTS.size():
		var r: Rect2 = buttons["i%d" % i].rect
		var kit := Kit.INSTRUMENTS[i]
		var mine := i == band.inst
		_box(r, KEY_ON if mine else KEY, 14.0, kit.color if mine else Color(kit.color, 0.25 + 0.6 * lane_glow[i]), 3.0 if mine else 2.0)
		_draw_instrument(i, r.get_center(), r.size.x / 80.0 * (1.0 + 0.12 * lane_glow[i]), kit.color)
		if looper.has_notes(looper.section, i):
			draw_circle(r.position + Vector2(11.0, 11.0), 4.5, kit.color)
		if looper.muted[i]:
			draw_line(r.position + Vector2(8, 8), r.end - Vector2(8, 8), REC_RED, 3.0, true)
	var glyphs := {"flat": "flat", "sharp": "sharp", "down": "down", "up": "up"}
	for id: String in glyphs:
		var r: Rect2 = buttons[id].rect
		var on: bool = band.mods[id]
		_box(r, Color(0.62, 0.64, 0.7, 0.95) if on else Color(0.36, 0.38, 0.44, 0.86), 18.0, Color(0, 0, 0, 0.35), 2.0)
		_draw_bender(id, r.get_center(), Color("1c1826") if on else Color("f2f2f6"))
	for b in 5:
		_draw_pad(b)
	if toast_left > 0.0:
		var a := minf(toast_left * 2.0, 1.0)
		var w := font.get_string_size(toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 40.0
		var r := Rect2((size_now.x - w) / 2.0, free_rect.position.y + 6.0, w, 42.0)
		_box(r, Color(PANEL, 0.9 * a), 21.0, Color(PAPER, 0.6 * a), 2.0)
		_text(r.get_center(), toast_text, 22, Color(PAPER, a))
	if menu_open:
		_draw_menu()
	if help_open:
		_draw_help()


# ---- the staff ----

func _draw_staff() -> void:
	var looper := band.looper
	var kit := Kit.INSTRUMENTS[band.inst]
	var live := looper.recording
	_box(staff, PANEL, 16.0, REC_RED if live else Color(PAPER, 0.35), 3.0 if live else 2.0)
	var inner := Rect2(staff.position + Vector2(64.0, 30.0), staff.size - Vector2(84.0, 68.0))
	var row := inner.size.y / 5.0
	for i in 5:
		var y := inner.end.y - (i + 0.5) * row
		draw_line(Vector2(inner.position.x - 8.0, y), Vector2(inner.end.x + 8.0, y), Color(PAPER, 0.55), 1.5)
	_draw_instrument(band.inst, Vector2(staff.position.x + 32.0, inner.get_center().y), 0.62, kit.color)
	_text_left(staff.position + Vector2(18.0, 20.0), kit.name, 17, kit.color)
	var tune: String = Kit.note_name(band.key) + " " + Kit.TUNINGS[band.tuning].name
	var about := "%s   %d bar%s   %d bpm   %s" % ["ABCD"[looper.section], looper.bars, "" if looper.bars == 1 else "s", int(looper.bpm), tune]
	_text_right(Vector2(staff.end.x - 18.0, staff.position.y + 20.0), about, 15, Color(PAPER, 0.8))

	var notes := looper.track(band.inst)
	var span := looper.length()
	if notes.is_empty() and not looper.playing and not looper.counting:
		# Nothing looping: the last few notes played, in a row, the way the ocarina showed them
		for k in by_hand.size():
			var b: int = by_hand[k][0]
			var age: float = by_hand[k][1]
			var x := inner.position.x + (k + 0.5) * inner.size.x / 10.0
			_dot(Vector2(x, inner.end.y - (maxi(b, 0) + 0.5) * row), 12.0, b, clampf(1.6 - age * 0.25, 0.25, 1.0))
	else:
		for k in looper.bars * Looper.BEATS + 1:
			var x := inner.position.x + inner.size.x * k / (looper.bars * Looper.BEATS)
			var bar := k % Looper.BEATS == 0
			draw_line(Vector2(x, inner.position.y + (0.0 if bar else row * 2.0)), Vector2(x, inner.end.y - (0.0 if bar else row * 2.0)),
					Color(PAPER, 0.5 if bar else 0.18), 2.0 if bar else 1.0)
		for note: Dictionary in notes:
			if note.t >= span:
				continue
			var b: int = note.b if note.b >= 0 else 2
			var at := Vector2(inner.position.x + inner.size.x * note.t / span, inner.end.y - (b + 0.5) * row)
			if kit.held:
				var w: float = minf(inner.size.x * note.d / span, inner.end.x - at.x)
				draw_rect(Rect2(at.x, at.y - 3.5, w, 7.0), Color(A_BLUE if b == 0 else C_YELLOW, 0.5))
			_dot(at, 10.0, note.b, 1.0)
		if looper.playing:
			var x := inner.position.x + inner.size.x * looper.pos / span
			draw_line(Vector2(x, inner.position.y - 4.0), Vector2(x, inner.end.y + 4.0), Color.WHITE, 2.5)
	if looper.counting:
		_text(inner.get_center(), str(Looper.BEATS - looper._counted + 1), 64, Color(1, 1, 1, 0.9))

	# Under the staff, a thin lane for each instrument's track
	var lanes := Rect2(inner.position.x, inner.end.y + 10.0, inner.size.x, 26.0)
	var lane := lanes.size.y / Kit.INSTRUMENTS.size()
	for i in Kit.INSTRUMENTS.size():
		var c: Color = Kit.INSTRUMENTS[i].color
		var y := lanes.position.y + i * lane
		if i == band.inst:
			draw_rect(Rect2(lanes.position.x - 8.0, y, lanes.size.x + 16.0, lane), Color(c, 0.2))
		var a := (0.25 if looper.muted[i] else 0.75) + 0.25 * lane_glow[i]
		for note: Dictionary in looper.sections[looper.section][i]:
			if note.t < span:
				draw_rect(Rect2(lanes.position.x + lanes.size.x * note.t / span, y + 0.5,
						maxf(3.0, lanes.size.x * minf(note.d, 0.5) / span * 0.6), lane - 1.0), Color(c, a))


# A note on the staff: a small copy of the button that played it
func _dot(at: Vector2, r: float, b: int, alpha: float) -> void:
	var c := A_BLUE if b == 0 else (C_YELLOW if b > 0 else PAPER)
	draw_circle(at, r + 1.5, Color(0, 0, 0, 0.5 * alpha))
	draw_circle(at, r, Color(c, alpha))
	if b == 0:
		_text(at, "A", int(r * 1.3), Color(1, 1, 1, alpha))
	elif b > 0:
		_arrow(at, ARROWS[b], r * 0.55, Color(0.35, 0.25, 0.0, alpha))


# ---- the loop station ----

func _draw_transport(id: String) -> void:
	var looper := band.looper
	var r: Rect2 = buttons[id].rect
	var c := r.get_center()
	var kit := Kit.INSTRUMENTS[band.inst]
	var on: bool = lit.get(id, 0) > 0
	var beat := looper.beat_phase()
	match id:
		"rec":
			on = on or looper.recording
		"play":
			on = on or looper.playing
		"mute":
			on = on or looper.muted[band.inst]
		"metro":
			on = on or looper.metronome
	var s := Band._numbered(id, "s")
	if s >= 0:
		on = on or s == looper.section
	if id != "bpm":
		_box(r, KEY_ON if on else KEY, 12.0, Color(PAPER, 0.18), 1.5)
	if s >= 0:
		var blink := s == looper.queued and fmod(band.time, 0.4) < 0.2
		_text(c, "ABCD"[s], 24, C_YELLOW if blink else (PAPER if s == looper.section else Color(PAPER, 0.6)))
		if not looper.section_empty(s):
			draw_circle(Vector2(r.end.x - 10.0, r.position.y + 10.0), 3.5, C_YELLOW)
		return
	match id:
		"rec":
			var pulse := 1.0 + (0.18 * pow(1.0 - beat, 2.0) if looper.recording and beat >= 0.0 else 0.0)
			draw_circle(c, 14.0 * pulse, REC_RED if looper.recording else Color(REC_RED, 0.75))
			if looper.recording:
				draw_arc(c, 19.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 2.0, true)
		"play":
			if looper.playing or looper.counting:
				draw_rect(Rect2(c - Vector2(11, 11), Vector2(22, 22)), PAPER)
			else:
				draw_colored_polygon([c + Vector2(-9, -13), c + Vector2(13, 0), c + Vector2(-9, 13)], PAPER)
		"undo":
			var ink := Color(PAPER, 1.0 if looper.can_undo() else 0.3)
			draw_arc(c + Vector2(0, 2), 11.0, deg_to_rad(-170.0), deg_to_rad(70.0), 14, ink, 3.0, true)
			_arrow(c + Vector2(-11, -1), Vector2(-0.3, 1.0), 7.0, ink)
		"clear":
			var ink := Color(kit.color, 1.0 if not looper.track(band.inst).is_empty() else 0.3)
			draw_line(c + Vector2(-10, -10), c + Vector2(10, 10), ink, 4.0, true)
			draw_line(c + Vector2(10, -10), c + Vector2(-10, 10), ink, 4.0, true)
		"mute":
			var ink: Color = kit.color
			draw_colored_polygon([c + Vector2(-14, -5), c + Vector2(-8, -5), c + Vector2(0, -12), c + Vector2(0, 12),
					c + Vector2(-8, 5), c + Vector2(-14, 5)], ink)
			if looper.muted[band.inst]:
				draw_line(c + Vector2(5, -7), c + Vector2(15, 7), REC_RED, 3.0, true)
				draw_line(c + Vector2(15, -7), c + Vector2(5, 7), REC_RED, 3.0, true)
			else:
				draw_arc(c, 8.0, -0.9, 0.9, 8, ink, 2.5, true)
				draw_arc(c, 14.0, -0.9, 0.9, 10, ink, 2.5, true)
		"metro":
			var ink := PAPER if looper.metronome else Color(PAPER, 0.5)
			draw_polyline([c + Vector2(-6, -14), c + Vector2(6, -14), c + Vector2(12, 14), c + Vector2(-12, 14), c + Vector2(-6, -14)], ink, 2.5, true)
			var swing := sin(looper.pos * PI) * 0.5 if looper.playing else 0.35
			draw_line(c + Vector2(0, 12), c + Vector2(0, 12) + Vector2(sin(swing), -cos(swing)) * 24.0, ink, 2.5, true)
		"bpm-":
			draw_line(c + Vector2(-9, 0), c + Vector2(9, 0), PAPER, 4.0)
		"bpm+":
			draw_line(c + Vector2(-9, 0), c + Vector2(9, 0), PAPER, 4.0)
			draw_line(c + Vector2(0, -9), c + Vector2(0, 9), PAPER, 4.0)
		"bpm":
			_text(c + Vector2(0, -6), str(int(looper.bpm)), 26, PAPER)
			_text(c + Vector2(0, 16), "BPM", 12, Color(PAPER, 0.6))
		"bars":
			_text(c + Vector2(0, -6), str(looper.bars), 26, PAPER)
			_text(c + Vector2(0, 16), "BAR" if looper.bars == 1 else "BARS", 12, Color(PAPER, 0.6))
		"menu":
			for k in 3:
				draw_line(c + Vector2(-12, -8 + k * 8), c + Vector2(12, -8 + k * 8), PAPER, 3.0)


# ---- the buttons that play ----

func _draw_pad(b: int) -> void:
	var r: Rect2 = buttons["n%d" % b].rect
	var c := r.get_center()
	var rad := r.size.x / 2.0
	var on: bool = lit.get("n%d" % b, 0) > 0
	var col := A_BLUE if b == 0 else C_YELLOW
	draw_circle(c + Vector2(0, 4), rad + 3.0, Color(0, 0, 0, 0.45))
	draw_circle(c, rad, col.darkened(0.35))
	draw_circle(c + Vector2(0, 2.0 if on else -3.0), rad * 0.92, col.lightened(0.5) if on else col)
	var ink := Color.WHITE if b == 0 else Color("6b4c00")
	var drums := Kit.is_drums(band.inst)
	var label: String = Kit.DRUM_NAMES[b] if drums else Kit.note_name(band.pad_note(b))
	if b == 0:
		_text(c + Vector2(0, -10), "A", int(rad * 0.75), ink)
	else:
		_arrow(c + Vector2(0, -10), ARROWS[b], rad * 0.36, ink)
	_text(c + Vector2(0, rad * 0.52), label, int(rad * (0.3 if drums else 0.38)), Color(ink, 0.85))


func _draw_bender(id: String, c: Vector2, ink: Color) -> void:
	match id:
		"sharp":
			for x: float in [-7.0, 7.0]:
				draw_line(c + Vector2(x, -22), c + Vector2(x, 22), ink, 3.0, true)
			for y: float in [-8.0, 8.0]:
				draw_line(c + Vector2(-15, y + 4), c + Vector2(15, y - 4), ink, 5.0, true)
		"flat":
			draw_line(c + Vector2(-8, -26), c + Vector2(-8, 18), ink, 3.5, true)
			draw_polyline([c + Vector2(-8, 2), c + Vector2(0, -5), c + Vector2(8, -3), c + Vector2(10, 4),
					c + Vector2(4, 12), c + Vector2(-8, 18)], ink, 3.5, true)
		"up":
			_arrow(c + Vector2(0, -8), Vector2.UP, 16.0, ink)
			_text(c + Vector2(0, 22), "8va", 18, ink)
		"down":
			_arrow(c + Vector2(0, 10), Vector2.DOWN, 16.0, ink)
			_text(c + Vector2(0, -20), "8vb", 18, ink)


# A little picture of instrument `i`, about 50 across at scale 1
func _draw_instrument(i: int, c: Vector2, k: float, col: Color) -> void:
	var dark := Color("1c1420")
	match i:
		Kit.OCARINA:
			_oval(c, Vector2(24, 13) * k, col)
			draw_colored_polygon([c + Vector2(2, -8) * k, c + Vector2(14, -8) * k, c + Vector2(13, -24) * k, c + Vector2(5, -24) * k], col)
			for x: float in [-13.0, -4.0, 6.0, 15.0]:
				draw_circle(c + Vector2(x, 2 if absf(x) > 8.0 else 4) * k, 2.8 * k, dark)
		Kit.TRUMPET:
			draw_line(c + Vector2(-26, 0) * k, c + Vector2(12, 0) * k, col, 5.0 * k, true)
			draw_colored_polygon([c + Vector2(8, -3) * k, c + Vector2(26, -14) * k, c + Vector2(26, 14) * k, c + Vector2(8, 3) * k], col)
			draw_rect(Rect2(c + Vector2(-18, 3) * k, Vector2(22, 9) * k), col, false, 3.0 * k)
			for x: float in [-14.0, -7.0, 0.0]:
				draw_line(c + Vector2(x, -12) * k, c + Vector2(x, 2) * k, col, 4.0 * k)
		Kit.ACCORDION:
			draw_rect(Rect2(c + Vector2(-26, -17) * k, Vector2(13, 34) * k), col)
			draw_rect(Rect2(c + Vector2(13, -17) * k, Vector2(13, 34) * k), col)
			for x: float in [-9.0, -3.0, 3.0, 9.0]:
				draw_line(c + Vector2(x, -15) * k, c + Vector2(x, 15) * k, Color(PAPER, 0.9), 3.0 * k)
			for y: float in [-10.0, -3.0, 4.0, 11.0]:
				draw_circle(c + Vector2(19.5, y) * k, 2.2 * k, dark)
		Kit.GUITAR:
			draw_line(c + Vector2(0, 2) * k, c + Vector2(24, -22) * k, col.darkened(0.3), 5.0 * k, true)
			draw_circle(c + Vector2(-9, 9) * k, 15.0 * k, col)
			draw_circle(c + Vector2(3, -3) * k, 10.0 * k, col)
			draw_circle(c + Vector2(-5, 5) * k, 4.5 * k, dark)
		Kit.TUBA:
			draw_arc(c + Vector2(-2, 8) * k, 13.0 * k, 0.0, TAU, 18, col, 6.0 * k, true)
			draw_colored_polygon([c + Vector2(4, 2) * k, c + Vector2(14, 2) * k, c + Vector2(26, -24) * k, c + Vector2(-4, -24) * k], col)
			_oval(c + Vector2(11, -24) * k, Vector2(15, 4) * k, col.lightened(0.3))
		Kit.BELLS:
			draw_colored_polygon([c + Vector2(-5, -14) * k, c + Vector2(5, -14) * k, c + Vector2(13, 6) * k, c + Vector2(19, 13) * k,
					c + Vector2(-19, 13) * k, c + Vector2(-13, 6) * k], col)
			draw_circle(c + Vector2(0, -17) * k, 4.5 * k, col)
			draw_circle(c + Vector2(0, 18) * k, 5.0 * k, col)
		Kit.DRUMS:
			draw_rect(Rect2(c + Vector2(-20, -4) * k, Vector2(40, 20) * k), col.darkened(0.25))
			_oval(c + Vector2(0, 16) * k, Vector2(20, 6) * k, col.darkened(0.25))
			_oval(c + Vector2(0, -4) * k, Vector2(20, 7) * k, col.lightened(0.35))
			draw_line(c + Vector2(-22, -22) * k, c + Vector2(-2, -6) * k, PAPER, 3.0 * k, true)
			draw_line(c + Vector2(22, -22) * k, c + Vector2(4, -6) * k, PAPER, 3.0 * k, true)


# ---- the menu and the help ----

func _draw_menu() -> void:
	var looper := band.looper
	draw_rect(Rect2(Vector2.ZERO, size_now), Color(0, 0, 0, 0.55))
	_box(menu_rect, Color(PANEL, 0.97), 20.0, Color(PAPER, 0.5), 2.0)
	_text(menu_rect.position + Vector2(menu_rect.size.x / 2.0, 30.0), "ONE MAN BAND", 26, PAPER)
	var snaps := {0.25: "sixteenths", 0.5: "eighths", 0.0: "off"}
	var words := {
		"tuning": "Tuning: " + Kit.TUNINGS[band.tuning].name,
		"key": "Key: " + Kit.note_name(band.key),
		"snap": "Snap to: " + snaps.get(looper.snap, "off"),
		"chain": "Song mode: " + ("A to D in turn" if looper.chain else "off"),
		"demo": "Load the house band",
		"new": "New song",
		"export": "Save as MIDI file",
		"midi": "MIDI keyboard: " + ("on" if band.midi_open else "off"),
		"sound": "Sound: " + ("on" if band.synth.sound else "off"),
		"help": "How to play",
		"close": "Back to the band",
	}
	for id: String in MENU:
		var r: Rect2 = buttons["menu:" + id].rect
		_box(r, KEY_ON if lit.get("menu:" + id, 0) > 0 or id == "close" else KEY, 12.0, Color(PAPER, 0.2), 1.5)
		_text(r.get_center(), words[id], 20, PAPER)


func _draw_help() -> void:
	draw_rect(Rect2(Vector2.ZERO, size_now), Color(0, 0, 0, 0.6))
	var w := minf(size_now.x - 32.0, 640.0)
	var lines := [
		"The five round buttons are five notes, lowest on the blue A and highest on the top yellow one. The grey buttons bend whatever you play while you hold them: flat, sharp, an octave down, an octave up.",
		"Along the bottom is everything he carries. Tap one and he plays that.",
		"Press the red dot, wait for four ticks, and play. It comes round again, and again. Change instrument and play over it. The arrow takes back the last thing you added, the cross empties this instrument's track, and A B C D are four loops to move between.",
		"Keys: A S D F G for notes, arrows to bend, 1 to 7 for instruments, Space to play, R to record, Z to take back.",
	]
	var h := 96.0 + Kit.TUNES.size() * 44.0 + 60.0
	for line: String in lines:
		h += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 18).y + 14.0
	var r := Rect2((size_now.x - w) / 2.0, maxf(8.0, (size_now.y - h) / 2.0), w, h)
	_box(r, Color(PANEL, 0.97), 20.0, Color(PAPER, 0.5), 2.0)
	_text(r.position + Vector2(w / 2.0, 34.0), "ONE MAN BAND", 28, PAPER)
	var y := r.position.y + 78.0
	for line: String in lines:
		draw_multiline_string(font, Vector2(r.position.x + 24.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 18, -1, PAPER)
		y += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 18).y + 14.0
	_text_left(Vector2(r.position.x + 24.0, y + 6.0), "The tune book (any instrument but the drums):", 18, C_YELLOW)
	y += 40.0
	for tune in Kit.TUNES:
		_text_left(Vector2(r.position.x + 24.0, y), tune.name, 18, PAPER)
		var pads: Array = tune.pads
		for k in pads.size():
			_dot(Vector2(r.position.x + 190.0 + k * 34.0, y), 13.0, pads[k], 1.0)
		y += 44.0
	_text(Vector2(size_now.x / 2.0, r.end.y - 24.0), "Tap anywhere", 16, Color(PAPER, 0.6))


# ---- the pieces everything is drawn from ----

func _box(r: Rect2, fill: Color, radius: float, edge := Color.TRANSPARENT, width := 0.0) -> void:
	var name := "%s %s %s %s" % [fill.to_html(), radius, edge.to_html(), width]
	if not _boxes.has(name):
		if _boxes.size() > 400:
			_boxes.clear()
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(int(radius))
		box.border_color = edge
		box.set_border_width_all(int(width))
		box.anti_aliasing = true
		_boxes[name] = box
	draw_style_box(_boxes[name], r)


func _text(c: Vector2, text: String, px: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(font, Vector2(c.x - w / 2.0, c.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_left(at: Vector2, text: String, px: int, col: Color) -> void:
	draw_string(font, Vector2(at.x, at.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


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
