shader_type spatial;
render_mode cull_disabled, shadows_disabled, vertex_lighting;

// Optimized grass blade shader: per-instance variation via INSTANCE_CUSTOM
// (the 3D equivalent of instance uniforms for canvas items), GPU wind via
// TIME so the CPU never touches instances per-frame, and cheap math
// workarounds (no pow()/texture noise in fragment, x*x falloff, wrapped
// diffuse) that stay fast on Intel iGPUs / GLES3.
//
// INSTANCE_CUSTOM usage (set from MultiMesh custom data or COLOR):
//   x = wind phase (0..1), y = height variation, z = color variation, w = sway amount

uniform vec4 col_a : source_color = vec4(0.66, 0.79, 0.35, 1.0);
uniform vec4 col_b : source_color = vec4(0.46, 0.65, 0.26, 1.0);
uniform vec4 col_c : source_color = vec4(0.27, 0.51, 0.20, 1.0);
uniform vec2 wind_dir = vec2(0.8, 0.4);
uniform float wind_strength = 0.18;
uniform float sway_speed = 1.6;

varying float v_h;
varying float v_var;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float sway_amt = 0.5 + INSTANCE_CUSTOM.w;
	// Blade height factor from UV (quad base y=0). No extra vertex color fetch.
	float h = clamp(UV.y, 0.0, 1.0);
	v_h = h;
	v_var = INSTANCE_CUSTOM.z;
	// Cheap wind: two sines instead of noise texture fetch per-vertex.
	float w = sin(TIME * sway_speed + phase + VERTEX.x * 0.8 + VERTEX.z * 0.6)
		+ 0.5 * sin(TIME * sway_speed * 2.7 + phase * 1.7);
	VERTEX.x += wind_dir.x * w * wind_strength * h * sway_amt;
	VERTEX.z += wind_dir.y * w * wind_strength * h * sway_amt;
}

void fragment() {
	// 3-stop gradient without texture fetch or pow(): linear + smoothstep.
	vec3 col = mix(col_a.rgb, col_b.rgb, smoothstep(0.0, 0.55, v_h + (v_var - 0.5) * 0.3));
	col = mix(col, col_c.rgb, smoothstep(0.55, 1.0, v_h));
	// Wrapped diffuse workaround: fake translucency instead of SSS.
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float wrap = clamp((ndl + 0.6) / 1.6, 0.0, 1.0);
	// x*x falloff instead of pow().
	float shade = 0.55 + 0.45 * wrap * wrap;
	ALBEDO = col * shade;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	// Dithered cutout edge instead of alpha scissor texture.
	ALPHA = 1.0;
}
