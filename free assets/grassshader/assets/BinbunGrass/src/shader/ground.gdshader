shader_type spatial;
// Opaque ground: the fragment writes no alpha, so the old blend_mix +
// depth_prepass_alpha only forced the transparent pipeline and an extra
// depth prepass for identical pixels. Default opaque keeps every pixel
// the same and skips both.

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));

	ALBEDO = color.rgb;
}

// NOTE: the downloaded demo shader ended with a custom light() that added
// dot(LIGHT, NORMAL) * ATTENUATION to DIFFUSE_LIGHT. Measured in-game (GL
// Compatibility): that line pinned the whole meadow to clipped white at
// every sane sun/ambient setting (sun 0.0-0.9 and ambient 0.16-5.0 all
// rendered identically white), making the lighting rig unbalanceable.
// Default PBR lighting responds to the rig like every other surface, so
// the custom light() is intentionally omitted; blade/ground colors,
// silhouettes and wind are untouched.
