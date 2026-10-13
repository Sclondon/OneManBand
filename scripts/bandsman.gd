class_name Bandsman
extends Node3D
## The man himself (models/bandsman.glb, built by art/make_models.py). His limbs are separate
## rigid pieces and nothing is keyframed: the arms reach for whatever he is holding, and the rest
## bobs along with the beat. Everything he is not holding hangs somewhere on him, and jumps when
## the loop plays it.

const MODEL: PackedScene = preload("res://models/bandsman.glb")
const UPPER := 0.3
const FORE := 0.3
const SHOULDER := Vector3(0.26, 0.42, 0.0)
const INK := Color("3a1c14")

# Where the left hand goes for each instrument, in the torso's space; the right is its mirror
# unless given
const REACH := [
	[Vector3(-0.07, 0.56, 0.22), Vector3(-0.2, 0.555, 0.2)],
	[Vector3(0.04, 0.555, 0.3), Vector3(-0.03, 0.6, 0.37)],
	[Vector3(0.26, 0.14, 0.32), null],
	[Vector3(0.47, 0.25, 0.28), Vector3(-0.1, -0.01, 0.35)],
	[Vector3(0.13, 0.27, 0.23), Vector3(-0.03, 0.44, 0.23)],
	[Vector3(0.34, 0.3, 0.28), null],
	[Vector3(0.18, 0.2, 0.38), null],
]

var stage: Stage
var inst := 0
var holding := false     # a note is being held down right now
var phase := -1.0        # how far through the beat the loop is, or -1 when it is stopped

var body: ShaderMaterial
var skin: ShaderMaterial
var faces := {}
var p := {}              # the pieces of the model by name
var acc: Node3D
var carried: Array[Dictionary] = []
var hand_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var strike: Array[float] = [0.0, 0.0]
var pops := {}
var sizes := {}
var half := 0.1          # half the accordion's bellows
var half_to := 0.1
var lift := 0.0
var energy := 0.0
var stomp := 0.0
var stare := 0.0
var time := 0.0
var turn := 0
var hips_at := Vector3.ZERO


func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	body = N64.mat()
	skin = N64.mat()
	N64.dress(model, body)
	for node in model.find_children("*", "Node3D", true, false):
		p[String(node.name)] = node
	p.face.material_override = skin
	for kind: String in ["grin", "blow", "stare"]:
		faces[kind] = _paint_face(kind)
	skin.set_shader_parameter("face_amount", 1.0)
	skin.set_shader_parameter("face", faces.grin)
	hips_at = p.hips.position

	acc = Node3D.new()
	acc.name = "accordion"
	p.torso.add_child(acc)
	for piece: String in ["acc_L", "acc_R", "acc_bellows"]:
		_give(p[piece], acc)
	p.accordion = acc
	# In the hands: [piece, where it is held, where it hangs otherwise (null to put it away)]
	_carry(Kit.PICCOLO, p.piccolo, Transform3D(Basis(Vector3.BACK, 0.12), Vector3(0.0, 0.575, 0.2)),
			Transform3D(Basis(Vector3.BACK, 1.2), Vector3(0.21, 0.12, 0.12)))
	_carry(Kit.TRUMPET, p.trumpet, Transform3D(Basis(Vector3.UP, -0.5) * Basis(Vector3.RIGHT, 0.28), Vector3(0.0, 0.605, 0.17)),
			Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-0.31, 0.5, -0.17)))
	_carry(Kit.ACCORDION, acc, Transform3D(Basis(), Vector3(0.0, 0.14, 0.32)), null)
	_carry(Kit.GUITAR, p.guitar, Transform3D(Basis(Vector3.BACK, 0.38), Vector3(-0.16, 0.0, 0.26)),
			Transform3D(Basis(Vector3.BACK, -1.15) * Basis(Vector3.UP, PI), Vector3(0.05, 0.3, -0.62)))
	_carry(Kit.TUBA, p.tuba_pipe, p.tuba_pipe.transform, null)
	_carry(Kit.DRUMS, p.snare, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.0, -0.03, 0.42)),
			Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.5, 0.05, -0.36)))
	# Two of each thing that takes a hand apiece
	for piece: String in ["bell_hand", "stick"]:
		var other: Node3D = p[piece].duplicate()
		for side: String in ["L", "R"]:
			var one: Node3D = p[piece] if side == "L" else other
			_give(one, p["hand_" + side])
			one.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0 - (0.7 if piece == "stick" else 0.2)), Vector3(0.0, -0.05, 0.0))
			one.material_override = body
			p[piece + "_" + side] = one
	for node: Node3D in p.values():
		sizes[node] = node.scale
	for h in 2:
		hand_at[h] = _hand_goal(h)
	choose(inst, true)


func choose(which: int, at_once := false) -> void:
	inst = which
	for side: String in ["L", "R"]:
		p["bell_hand_" + side].visible = inst == Kit.BELLS
		p["stick_" + side].visible = inst == Kit.DRUMS
	for item in carried:
		var mine: bool = item.inst == inst
		item.node.visible = mine or item.stow != null
		if at_once:
			item.node.transform = item.hold if mine else (item.stow if item.stow != null else item.hold)


# A note has sounded: his own playing (`live`) moves his hands, and either way the thing that
# made it jumps and lets a note go
func on_note(which: int, b: int, live: bool) -> void:
	energy = minf(1.0, energy + (0.4 if live else 0.12))
	var from: Node3D = _piece(which, b)
	_pop(from)
	if stage != null:
		stage.puff(from.global_position + Vector3(randf_range(-0.35, 0.35), 0.3, 0.15), Kit.INSTRUMENTS[which].color)
	if which == Kit.DRUMS and b == 0:
		stomp = 1.0
	if which != inst:
		return
	match which:
		Kit.ACCORDION:
			half_to = 0.2 if half_to < 0.14 else 0.08
		Kit.GUITAR:
			strike[1] = 1.0
		Kit.BELLS:
			strike[turn] = 1.0
			turn = 1 - turn
		Kit.DRUMS:
			match b:
				1:
					strike[turn] = 1.0
					turn = 1 - turn
				2:
					strike[1] = 1.0
				3:
					strike[0] = 1.0
				4:
					strike[0] = 1.0
					strike[1] = 1.0
		_:
			lift = 1.0


# The wide-eyed look, for when one of the tunes in the book is played
func startle() -> void:
	stare = 2.4


func _process(delta: float) -> void:
	time += delta
	energy = maxf(0.0, energy - delta * 0.6)
	stomp = maxf(0.0, stomp - delta * 5.0)
	stare = maxf(0.0, stare - delta)
	lift = maxf(1.0 if holding and _blown() else 0.0, lift - delta * 2.5)
	half = lerpf(half, half_to, 1.0 - exp(-9.0 * delta))
	for h in 2:
		strike[h] = maxf(0.0, strike[h] - delta * 7.0)

	# How hard the beat lands, sharpest on the beat itself
	var dip := pow(1.0 - phase, 3.0) if phase >= 0.0 else 0.0
	var tap := 0.5 - 0.5 * cos(TAU * phase) if phase >= 0.0 else 0.0
	var still := 0.25 if _blown() else 1.0
	rotation.y = 0.2 * sin(time * 0.35)
	p.hips.position = hips_at + Vector3(0.0, -0.04 * dip - 0.008 * sin(time * 1.7) - 0.02 * stomp, 0.0)
	p.torso.rotation = Vector3(0.09 + 0.03 * sin(time * 1.3) + 0.06 * energy - 0.12 * lift * (1.0 - still + 0.25),
			0.0, 0.05 * sin(time * 0.9) * still)
	p.head.rotation = Vector3(-0.06 + 0.07 * dip - 0.1 * lift, 0.14 * sin(time * 0.6) * still,
			(0.13 * sin(time * 0.8 + 1.0) + 0.05) * still)
	p.foot_R.rotation.x = -0.5 * tap
	p.thigh_L.rotation.x = -0.55 * stomp
	p.shin_L.rotation.x = 0.9 * stomp

	var look := "stare" if stare > 0.0 else ("blow" if lift > 0.3 and _blown() else "grin")
	skin.set_shader_parameter("face", faces[look])

	var ease := 1.0 - exp(-14.0 * delta)
	for item in carried:
		var mine: bool = item.inst == inst
		var goal: Transform3D = item.hold if mine else (item.stow if item.stow != null else item.hold)
		if mine and item.inst == Kit.TRUMPET:
			goal = goal * Transform3D(Basis(Vector3.RIGHT, -0.2 * lift), Vector3.ZERO)
		var node: Node3D = item.node
		var size: Vector3 = node.scale
		node.scale = Vector3.ONE
		node.transform = node.transform.interpolate_with(goal, ease)
		node.scale = size
	if inst == Kit.BELLS:
		# Handbells stay upright whatever the arm is doing, and tip as they ring
		for h in 2:
			var bell: Node3D = p["bell_hand_" + ("L" if h == 0 else "R")]
			bell.global_basis = global_basis * Basis(Vector3.RIGHT, -PI / 2.0 + 0.25 + 0.9 * strike[h])
	p.acc_L.position.x = half
	p.acc_R.position.x = -half
	p.acc_bellows.scale.x = half * 2.0

	for h in 2:
		hand_at[h] = hand_at[h].lerp(_hand_goal(h), 1.0 - exp(-22.0 * delta))
		var side := "L" if h == 0 else "R"
		var mirror := 1.0 if h == 0 else -1.0
		_reach(p["upper_" + side], p["fore_" + side], SHOULDER * Vector3(mirror, 1, 1), hand_at[h],
				Vector3(mirror, -0.9, -0.35))

	for node: Node3D in pops.keys():
		pops[node] = maxf(0.0, pops[node] - delta * 5.0)
		var k: float = pops[node]
		if node == p.cym_crash:
			node.rotation.x = 0.45 * k * sin(time * 34.0)
		elif node == p.cym_top:
			node.position.y = 1.085 - 0.03 * k
		elif node == p.pack_bells:
			node.rotation.x = 0.6 * k * sin(time * 22.0)
		else:
			node.scale = sizes[node] * (1.0 + 0.2 * k)
		if k <= 0.0:
			pops.erase(node)


# Where hand h (0 left, 1 right) wants to be this instant, in the torso's space
func _hand_goal(h: int) -> Vector3:
	var pair: Array = REACH[inst]
	var at: Vector3 = pair[0]
	if h == 1:
		at = pair[1] if pair[1] != null else at * Vector3(-1, 1, 1)
	match inst:
		Kit.ACCORDION:
			at.x = (half + 0.16) * (1.0 if h == 0 else -1.0)
		Kit.GUITAR:
			if h == 1:
				at.y += 0.09 * sin(strike[1] * PI) - 0.02
		Kit.BELLS:
			at += Vector3(0.0, -0.12, 0.05) * strike[h] + Vector3(0.0, 0.02 * sin(time * 2.0 + h), 0.0)
		Kit.DRUMS:
			at += Vector3(0.0, 0.07 - 0.1 * strike[h], 0.0)
		Kit.TRUMPET:
			# Wherever the trumpet is: one hand under it, one on the valves
			at = p.trumpet.transform * (Vector3(0.03, -0.045, 0.13) if h == 0 else Vector3(-0.025, 0.0, 0.23))
		Kit.PICCOLO:
			# Along the pipe, out to his right
			at = p.piccolo.transform * (Vector3(-0.1, -0.03, 0.02) if h == 0 else Vector3(-0.27, -0.03, 0.02))
	return at


func _blown() -> bool:
	return inst == Kit.PICCOLO or inst == Kit.TRUMPET or inst == Kit.TUBA


# The part of him that instrument `which` sounds from
func _piece(which: int, b: int) -> Node3D:
	match which:
		Kit.PICCOLO:
			return p.piccolo
		Kit.TRUMPET:
			return p.trumpet
		Kit.ACCORDION:
			return acc if inst == which else p.torso
		Kit.GUITAR:
			return p.guitar
		Kit.TUBA:
			return p.tuba
		Kit.BELLS:
			return p.pack_bells
	return [p.pack_drum, p.snare, p.cym_top, p.pack_tom, p.cym_crash][posmod(b, 5)]


func _pop(node: Node3D) -> void:
	if node != p.torso:
		pops[node] = 1.0


func _carry(which: int, node: Node3D, hold: Transform3D, stow: Variant) -> void:
	if node.get_parent() != p.torso:
		_give(node, p.torso)
	carried.append({"inst": which, "node": node, "hold": hold, "stow": stow})


func _give(node: Node3D, to: Node3D) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	to.add_child(node)
	node.transform = Transform3D.IDENTITY


# Bends an arm of two pieces so that its hand is at `to`, the elbow leaning toward `pole`
func _reach(upper: Node3D, fore: Node3D, shoulder: Vector3, to: Vector3, pole: Vector3) -> void:
	var d := to - shoulder
	var far := clampf(d.length(), 0.08, UPPER + FORE - 0.002)
	var dir := d.normalized()
	var along := (UPPER * UPPER - FORE * FORE + far * far) / (2.0 * far)
	var out := sqrt(maxf(UPPER * UPPER - along * along, 0.0))
	var side := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * along + side * out
	var first := _down(elbow - shoulder)
	upper.basis = first
	fore.basis = first.inverse() * _down(shoulder + dir * far - elbow)


# Turned so that what hangs down points along `v`
static func _down(v: Vector3) -> Basis:
	var y := -v.normalized()
	var hint := Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT
	var z := (hint - y * hint.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


# His face, painted fresh: a wide closed-eyed grin, lips pursed to blow, or the eyes open
func _paint_face(kind: String) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var puff := 1.3 if kind == "blow" else 1.0
	for x: float in [12.0, 52.0]:
		_blob(img, Vector2(x, 40.0), Vector2(6.0, 4.0) * puff, Color(0.96, 0.45, 0.42, 0.5))
	for x: float in [21.0, 43.0]:
		var out := signf(x - 32.0)
		if kind == "stare":
			_blob(img, Vector2(x, 28.5), Vector2(7.0, 5.6), INK)
			_blob(img, Vector2(x, 28.5), Vector2(5.6, 4.2), Color("fffdf2"))
			_blob(img, Vector2(x, 28.5), Vector2(2.7, 2.7), Color("b8301c"))
			_blob(img, Vector2(x, 28.5), Vector2(1.1, 1.1), INK)
			_stroke(img, Vector2(x + out * 8.0, 18.5), Vector2(x - out * 6.0, 22.0), 1.5, INK)
		else:
			_arc(img, Vector2(x, 31.0), 6.5, 1.7, INK)
			_stroke(img, Vector2(x + out * 8.0, 20.5), Vector2(x - out * 5.0, 19.0), 1.2, INK)
	if kind == "blow":
		_blob(img, Vector2(32.0, 48.5), Vector2(4.2, 4.8), INK)
		_blob(img, Vector2(32.0, 48.5), Vector2(2.3, 2.9), Color("7c2a22"))
	else:
		# The grin: teeth between a shallow curve and a deep one
		for y in range(38, 58):
			for x in range(14, 51):
				var u := (x - 32.0) / 16.5
				if absf(u) >= 1.0:
					continue
				var arc := sqrt(1.0 - u * u)
				var top := 43.0 + 2.5 * arc
				var low := 43.0 + 10.5 * arc
				if y < top - 1.2 or y > low + 1.2:
					continue
				var edge := minf(y - top, low - y)
				var c := INK if edge < 0.9 or (x % 5 == 2 and edge < 6.0) else Color("fffdf2")
				_dab(img, x, y, c, clampf(edge + 1.2, 0.0, 1.0))
	return ImageTexture.create_from_image(img)


static func _dab(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 1 or y < 1 or x > 62 or y > 62 or a <= 0.0:
		return
	var under := img.get_pixel(x, y)
	var over := a * c.a
	var alpha := over + under.a * (1.0 - over)
	var mixed := (Color(c.r, c.g, c.b) * over + Color(under.r, under.g, under.b) * under.a * (1.0 - over)) / alpha
	img.set_pixel(x, y, Color(mixed.r, mixed.g, mixed.b, alpha))


static func _blob(img: Image, at: Vector2, r: Vector2, c: Color) -> void:
	for y in range(int(at.y - r.y - 2.0), int(at.y + r.y + 3.0)):
		for x in range(int(at.x - r.x - 2.0), int(at.x + r.x + 3.0)):
			var d := ((Vector2(x, y) - at) / r).length()
			_dab(img, x, y, c, clampf((1.0 - d) * minf(r.x, r.y) + 0.5, 0.0, 1.0))


static func _stroke(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var lo := a.min(b) - Vector2(w + 1.0, w + 1.0)
	var hi := a.max(b) + Vector2(w + 2.0, w + 2.0)
	for y in range(int(lo.y), int(hi.y)):
		for x in range(int(lo.x), int(hi.x)):
			var q := Vector2(x, y)
			var t := clampf((q - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			_dab(img, x, y, c, clampf(w - q.distance_to(a.lerp(b, t)) + 0.5, 0.0, 1.0))


# The top half of a ring: an eye shut in a smile
static func _arc(img: Image, at: Vector2, r: float, w: float, c: Color) -> void:
	for y in range(int(at.y - r - w - 1.0), int(at.y + 2.0)):
		for x in range(int(at.x - r - w - 1.0), int(at.x + r + w + 2.0)):
			var q := Vector2(x, y) - at
			if q.y > 0.5:
				continue
			_dab(img, x, y, c, clampf(w * 0.5 - absf(q.length() - r) + 0.5, 0.0, 1.0))
