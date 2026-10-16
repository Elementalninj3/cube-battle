shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Cheap stylized ground: world-space checker + height tint, no noise
// textures per-pixel. Matches the Binbun palette without the overdraw.

uniform vec4 col_a : source_color = vec4(0.66, 0.79, 0.35, 1.0);
uniform vec4 col_b : source_color = vec4(0.46, 0.65, 0.26, 1.0);
uniform vec4 dirt : source_color = vec4(0.42, 0.30, 0.20, 1.0);
uniform float checker_scale = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Integer checker without fract() precision issues on mobile.
	vec2 cell = floor(v_world.xz * checker_scale);
	float check = mod(cell.x + cell.y, 2.0);
	vec3 grass = mix(col_a.rgb, col_b.rgb, check);
	// Cheap distance darkening: x*x instead of pow / smoothstep chain.
	float d = length(v_world.xz) / 40.0;
	float dark = clamp(1.0 - d * d * 0.35, 0.65, 1.0);
	ALBEDO = grass * dark;
	ROUGHNESS = 0.95;
}
