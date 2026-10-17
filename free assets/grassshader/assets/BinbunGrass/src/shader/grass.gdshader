shader_type spatial;
// Opaque cutout: the dithered alpha below is step(0/1) — every surviving
// fragment is fully opaque — so blend_mix + depth_prepass_alpha produced
// identical pixels at the cost of the transparent queue, a depth prepass,
// no depth write and no early-Z rejection across ~100k overlapping
// billboards. Opaque + discard keeps the exact same coverage/colors and
// lets the depth buffer cull hidden blade fragments before shading.
render_mode depth_draw_opaque, cull_disabled;

uniform bool billboard = false;

uniform sampler2D shape_texture;
uniform sampler2D shape_atlas;
uniform bool use_atlas = false;

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;
uniform float random_variation : hint_range(0.0, 1.0, 0.001) = 0.002;

group_uniforms Wind;
uniform sampler2D wind_texture;
uniform vec2 wind_velocity;

group_uniforms Transparency;
uniform float alpha_cut_start : hint_range(0.0, 1.0, 0.05) = 0.1;
uniform float alpha_cut_end : hint_range(0.0, 1.0, 0.05) = 0.9;
uniform int alpha_mode : hint_enum("Smooth", "Dithered", "Cut") = 0;

varying flat int id;
varying flat vec2 atlas_off;
varying vec3 world_pos;

#include "util/dither.gdshaderinc"

float randomf(int index, int seed){
	float value = sin(float(index + seed)) * 0.5 + 0.5;
	return value;
}

float wind_noise(){
	float value = texture(wind_texture, (world_pos.xz*0.03) - (vec2(TIME * 0.01) * wind_velocity)).r;
	return value;
}

vec3 wind(vec2 uv){
	float wind_noise = wind_noise();
	// Same curve as pow(1.0 - uv.y, 2.0) with one multiply.
	float wuv = 1.0 - uv.y;
	float wind_affect = wuv * wuv;
	vec3 value = vec3(
		wind_noise * (wind_velocity.x),
		0.0,
		wind_noise * (wind_velocity.y)) * 0.25;
	value *= wind_affect;
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	id = INSTANCE_ID;
	// Atlas tile offset is constant for the whole blade: compute once per
	// vertex here instead of per-fragment with integer div/mod. Bit-identical
	// to atlas_uv(UV, id, 2) = UV * 0.5 + vec2(x, y) * 0.5.
	atlas_off = vec2(0.0);
	if(use_atlas){
		int ai = id % 4;
		atlas_off = vec2(float(ai % 2), float(ai / 2)) * 0.5;
	}

	if(billboard){
		mat4 billboard_matrix = mat4(
				MAIN_CAM_INV_VIEW_MATRIX[0],
				MAIN_CAM_INV_VIEW_MATRIX[1],
				MAIN_CAM_INV_VIEW_MATRIX[2],
				MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard_matrix;

		VERTEX += (VIEW_MATRIX * vec4(wind(UV), 0.0)).xyz;
	} else {
		VERTEX += wind(UV);
	}
	NORMAL = vec3(0.0,1.0,0.0);
}

void fragment() {
	// Production uses the atlas: sample it directly. The standalone shape
	// texture is only a fallback when use_atlas is off (previously both were
	// sampled and the first result thrown away).
	float shape_value;
	if(use_atlas){
		shape_value = texture(shape_atlas, UV * vec2(0.5) + atlas_off).r;
	} else {
		shape_value = texture(shape_texture, UV).r;
	}

	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	// Production sets random_variation = 0.0, making randomf(id,1) < 0.0
	// always false; skip the sin() entirely in that case (identical pixels).
	if(random_variation > 0.0 && randomf(id,1) < random_variation) noise_value += 0.4;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));

	ALBEDO = color.rgb;

	float alpha = shape_value;
	if(alpha_mode == 0){
		ALPHA = alpha;
	} else {
		alpha = clamp((shape_value - alpha_cut_start) / (alpha_cut_end - alpha_cut_start), 0.0, 1.0);
		if(alpha_mode == 1){
			alpha = step(bayer4(FRAGCOORD.xy) + 0.01, alpha);
		}
		if(alpha < 0.1) discard;
	}

}

// NOTE: the downloaded demo shader ended with a custom light() that added
// dot(LIGHT, NORMAL) * ATTENUATION to DIFFUSE_LIGHT. Measured in-game (GL
// Compatibility, isolated A/B: identical bg/ambient/fog, light() present
// vs removed): it pinned the whole meadow to clipped white and swallowed
// every sun/ambient adjustment. Default PBR lighting responds to the rig
// like every other surface, so the custom light() is intentionally
// omitted; blade shape atlas, color variation, wind, billboarding and
// dithered alpha are untouched.
