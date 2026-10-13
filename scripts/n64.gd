class_name N64
## The one material everything solid wears (shaders/n64.gdshader), and the light it is all under.

const SHADER: Shader = preload("res://shaders/n64.gdshader")
# The 3D picture is this many pixels on its short side, blown up soft the way the console did
const LINES := 300.0

static var made: Array[ShaderMaterial] = []
static var _grain: ImageTexture


# `grain` smears a blurry texture over it (0 to 1); `glow` is how far it ignores the light
static func mat(grain := 0.0, glow := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("grain_amount", grain)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("grain", _grain_texture())
	made.append(m)
	return m


# Puts the one material on every mesh under `node`, or `glowing` on those whose names start "glow"
static func dress(node: Node, plain: ShaderMaterial, glowing: ShaderMaterial = null) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = glowing if glowing != null and String(mesh.name).begins_with("glow") else plain


static func set_all(setting: String, value: Variant) -> void:
	for m in made:
		m.set_shader_parameter(setting, value)


static func vec(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


# A small cloudy square, the same every time
static func _grain_texture() -> ImageTexture:
	if _grain == null:
		var noise := FastNoiseLite.new()
		noise.seed = 64
		noise.frequency = 0.09
		var img := Image.create(32, 32, false, Image.FORMAT_L8)
		for y in 32:
			for x in 32:
				# Wrapped round so the edges of the square meet
				var a := TAU * x / 32.0
				var b := TAU * y / 32.0
				var v := noise.get_noise_3d(cos(a) * 5.0 + cos(b) * 5.0, sin(a) * 5.0, sin(b) * 5.0)
				img.set_pixel(x, y, Color(v * 0.9 + 0.5, 0, 0))
		_grain = ImageTexture.create_from_image(img)
	return _grain
