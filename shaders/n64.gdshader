shader_type spatial;
// Everything solid: colour painted on the corners, light worked out at the corners and smoothed
// across the face, a soft smear of texture, and fog. No per-pixel lighting at all.
render_mode unshaded, cull_disabled;

uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform vec3 sun_col = vec3(0.8);
uniform vec3 amb_col = vec3(0.5);
uniform vec3 lamp_pos = vec3(0.0, 3.2, 1.6);
uniform vec3 lamp_col = vec3(0.0);
uniform vec3 fog_col = vec3(0.7, 0.85, 0.95);
uniform float fog_near = 14.0;
uniform float fog_far = 60.0;
uniform vec3 tint = vec3(1.0);
uniform float glow = 0.0;
uniform float grain_amount = 0.0;
uniform sampler2D grain : filter_linear, repeat_enable;
uniform float face_amount = 0.0;
uniform sampler2D face : filter_linear, repeat_disable;

varying vec3 lit;
varying float fog;
varying vec3 at;

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_lamp = lamp_pos - at;
	float reach = 1.0 / (1.0 + dot(to_lamp, to_lamp) * 0.12);
	vec3 light = amb_col + sun_col * max(dot(n, sun_dir), 0.0)
			+ lamp_col * reach * (0.35 + 0.65 * max(dot(n, normalize(to_lamp)), 0.0));
	lit = mix(light, vec3(1.0), glow);
	float depth = -(VIEW_MATRIX * vec4(at, 1.0)).z;
	fog = clamp((depth - fog_near) / (fog_far - fog_near), 0.0, 1.0) * (1.0 - glow * 0.6);
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	if (face_amount > 0.5) {
		vec4 f = texture(face, UV);
		c = mix(c, f.rgb, f.a);
	}
	if (grain_amount > 0.0) {
		float g = texture(grain, at.xz * 0.3 + at.y * 0.21).r;
		c *= mix(1.0, 0.72 + 0.56 * g, grain_amount);
	}
	ALBEDO = mix(c * lit, fog_col, fog);
}
