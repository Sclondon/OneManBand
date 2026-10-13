class_name Stage
extends Node3D
## The green and its bandstand (models/stage.glb), the sky over it, the weather, and the little
## notes that float up off whatever is being played.

const MODEL: PackedScene = preload("res://models/stage.glb")
const SKY: Shader = preload("res://shaders/sky.gdshader")
# The top of the bandstand, where he stands
const FLOOR := 0.228
const NOTE_ART := [
	"........##......",
	"........####....",
	"........######..",
	"........##.####.",
	"........##...##.",
	"........##....#.",
	"........##......",
	"........##......",
	"........##......",
	"....######......",
	"..########......",
	".#########......",
	".#########......",
	".########.......",
	"..######........",
	"................",
]

var night := false
var rain := false
var fireflies := false
var dark := 0.0
var wet := 0.0

var sky: ShaderMaterial
var sun: MeshInstance3D
var moon: MeshInstance3D
var drops: CPUParticles3D
var flies: CPUParticles3D
var notes: Array[Dictionary] = []
var next_note := 0


func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	N64.dress(model, N64.mat(1.0), N64.mat(0.0, 1.0))

	var dome := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 70.0
	ball.height = 140.0
	ball.radial_segments = 16
	ball.rings = 8
	dome.mesh = ball
	sky = ShaderMaterial.new()
	sky.shader = SKY
	dome.material_override = sky
	add_child(dome)
	sun = _disc(2.4, Color("fff3b8"))
	moon = _disc(2.0, Color("f4f1dc"))

	drops = CPUParticles3D.new()
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.55)
	var wash := StandardMaterial3D.new()
	wash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wash.albedo_color = Color(0.8, 0.88, 1.0, 0.5)
	streak.material = wash
	drops.mesh = streak
	drops.amount = 260
	drops.lifetime = 0.65
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(9.0, 0.5, 6.0)
	drops.position = Vector3(0.0, 9.0, 1.0)
	drops.direction = Vector3(0.08, -1.0, 0.0)
	drops.spread = 1.5
	drops.gravity = Vector3.ZERO
	drops.initial_velocity_min = 15.0
	drops.initial_velocity_max = 18.0
	drops.emitting = false
	add_child(drops)

	flies = CPUParticles3D.new()
	var mote := SphereMesh.new()
	mote.radius = 0.035
	mote.height = 0.07
	mote.radial_segments = 4
	mote.rings = 2
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color("eaff7a")
	mote.material = shine
	flies.mesh = mote
	flies.amount = 26
	flies.lifetime = 7.0
	flies.preprocess = 3.0
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(4.5, 1.1, 2.5)
	flies.position = Vector3(0.0, 1.6, 0.5)
	flies.spread = 180.0
	flies.gravity = Vector3.ZERO
	flies.initial_velocity_min = 0.1
	flies.initial_velocity_max = 0.45
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.0))
	swell.add_point(Vector2(0.2, 1.0))
	swell.add_point(Vector2(0.8, 1.0))
	swell.add_point(Vector2(1.0, 0.0))
	flies.scale_amount_curve = swell
	flies.emitting = false
	add_child(flies)

	var art := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			art.set_pixel(x, y, Color(1, 1, 1, 1.0 if NOTE_ART[y][x] == "#" else 0.0))
	var picture := ImageTexture.create_from_image(art)
	for i in 16:
		var quad := MeshInstance3D.new()
		var card := QuadMesh.new()
		card.size = Vector2(0.3, 0.3)
		quad.mesh = card
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = picture
		quad.material_override = m
		quad.visible = false
		add_child(quad)
		notes.append({"node": quad, "mat": m, "age": 9.0, "drift": Vector3.ZERO, "color": Color.WHITE})
	_light()


func set_night(on: bool, at_once := false) -> void:
	night = on
	if at_once:
		dark = 1.0 if on else 0.0
		_light()


func set_rain(on: bool) -> void:
	rain = on
	drops.emitting = on


func set_fireflies(on: bool) -> void:
	fireflies = on
	flies.emitting = on


# A note drifting up from `at`
func puff(at: Vector3, color: Color) -> void:
	var note := notes[next_note]
	next_note = (next_note + 1) % notes.size()
	note.node.global_position = at
	note.node.visible = true
	note.age = 0.0
	note.color = color
	note.drift = Vector3(randf_range(-0.35, 0.35), randf_range(0.8, 1.2), randf_range(0.0, 0.3))


func _process(delta: float) -> void:
	dark = move_toward(dark, 1.0 if night else 0.0, delta * 0.7)
	wet = move_toward(wet, 1.0 if rain else 0.0, delta * 0.8)
	_light()
	for note in notes:
		if note.age > 1.0:
			continue
		note.age += delta
		var node: MeshInstance3D = note.node
		if note.age > 1.0:
			node.visible = false
			continue
		node.position += note.drift * delta + Vector3(sin(note.age * 9.0) * 0.4 * delta, 0.0, 0.0)
		node.scale = Vector3.ONE * (0.5 + minf(note.age * 6.0, 1.0) * 0.6)
		var c: Color = note.color
		c.a = clampf((1.0 - note.age) * 2.5, 0.0, 1.0)
		note.mat.albedo_color = c


func _light() -> void:
	var grey := Color("7c8794").lerp(Color("20263a"), dark)
	var top := Color("3d86e0").lerp(Color("080c26"), dark).lerp(grey, wet * 0.75)
	var bottom := Color("c4e8f6").lerp(Color("2b2f63"), dark).lerp(grey.lightened(0.15), wet * 0.75)
	sky.set_shader_parameter("top", N64.vec(top))
	sky.set_shader_parameter("bottom", N64.vec(bottom))
	sky.set_shader_parameter("stars", dark * dark * (1.0 - wet))
	var shade := 1.0 - wet * 0.35
	N64.set_all("sun_dir", Vector3(-0.35, 0.75, 0.55).lerp(Vector3(0.4, 0.8, 0.3), dark).normalized())
	N64.set_all("sun_col", Vector3(0.86, 0.78, 0.62).lerp(Vector3(0.2, 0.26, 0.44), dark) * shade)
	N64.set_all("amb_col", Vector3(0.5, 0.52, 0.6).lerp(Vector3(0.22, 0.26, 0.44), dark) * shade)
	N64.set_all("lamp_col", Vector3(2.2, 1.5, 0.7) * dark)
	N64.set_all("fog_col", N64.vec(bottom))
	N64.set_all("fog_near", lerpf(16.0, 9.0, wet))
	N64.set_all("fog_far", lerpf(70.0, 38.0, wet))
	sun.position = Vector3(-17.0, lerpf(15.0, -9.0, dark), -45.0)
	moon.position = Vector3(14.0, lerpf(-9.0, 21.0, dark), -45.0)
	sun.visible = wet < 0.5
	moon.visible = wet < 0.5


func _disc(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 12
	ball.rings = 6
	mi.mesh = ball
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	add_child(mi)
	return mi
