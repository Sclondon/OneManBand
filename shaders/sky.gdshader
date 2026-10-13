shader_type spatial;
// The inside of a big ball: two colours from the horizon up, and stars when it is dark
render_mode unshaded, cull_front;

uniform vec3 top = vec3(0.2, 0.5, 0.9);
uniform vec3 bottom = vec3(0.7, 0.85, 0.95);
uniform float stars = 0.0;

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 c = mix(bottom, top, pow(clamp(d.y * 1.5 + 0.05, 0.0, 1.0), 0.7));
	vec2 g = vec2(atan(d.x, d.z) * 22.0, d.y * 46.0);
	vec2 cell = floor(g);
	float r = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float star = step(0.9, r) * smoothstep(0.32, 0.0, length(fract(g) - 0.5));
	c += stars * star * step(0.03, d.y) * (0.5 + r * 0.5);
	ALBEDO = c;
}
