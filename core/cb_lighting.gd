class_name CBLighting
extends RefCounted
## Cozy Lighting — the single lighting system for every mode (1v1, Grass
## Render, Open World). Replaces the old Baked/Sunset/Atmospheric
## Type+Mode rig.
##
## Design: ONE clean, reusable rig per scene —
##   one WorldEnvironment (sky material + sky-source ambient, ACES tonemap),
##   one shadowed DirectionalLight3D (the sun),
##   restrained depth fog.
## No RimFill, no LightmapGI, no SDFGI/SSAO/SSIL/glow/volumetric fog (GL
## Compatibility has no SDFGI/SSAO/SSIL/glow anyway).
##
## Balance: the sky provides the majority of the soft fill (ambient) and is
## cool-neutral so shaded grass/characters stay visible; the sun is the
## primary DIRECTION and the only strong shadow caster, kept warm-neutral
## and deliberately below the point where highlights clip. Exposure + a
## gentle post-grade shape the final contrast. All values absolute, so
## switching/re-applying a profile never compounds.
##
## Five environment profiles:
##   Cozy Daylight · Golden Afternoon · Overcast Meadow · Twilight · Cave
##
## The Settings UI can override individual parameters PER PROFILE; overrides
## are stored in user://cubebox_settings.cfg and never touch the baselines.
##
## Usage:
##   var rig := CBLighting.build(self, CBLighting.Profile.COZY_DAYLIGHT)
##   CBLighting.apply(rig, CBLighting.Profile.TWILIGHT)   # re-tune live
##   CBLighting.apply_quality_shadows(rig["sun"], quality)

const SETTINGS_PATH := "user://cubebox_settings.cfg"

enum Profile {
	COZY_DAYLIGHT = 0,
	GOLDEN_AFTERNOON = 1,
	OVERCAST_MEADOW = 2,
	TWILIGHT = 3,
	CAVE = 4,
}

const PROFILE_NAMES: PackedStringArray = [
	"Cozy Daylight",
	"Golden Afternoon",
	"Overcast Meadow",
	"Twilight",
	"Cave",
]

## Which mode is asking. Used only to pick a sensible default profile.
enum Mode {
	LOCAL_1V1 = 0,
	GRASS_RENDER = 1,
	OW_BIG = 2,
	OW_GRASS = 3,
}

## Per-mode default profile (used when Settings is on "Auto / Use mode
## default"). All cozy-grass modes open on Cozy Daylight; the big arena
## opens on the warmer Golden Afternoon.
const MODE_DEFAULT_PROFILE := {
	Mode.LOCAL_1V1: Profile.COZY_DAYLIGHT,
	Mode.GRASS_RENDER: Profile.COZY_DAYLIGHT,
	Mode.OW_BIG: Profile.GOLDEN_AFTERNOON,
	Mode.OW_GRASS: Profile.COZY_DAYLIGHT,
}

## Legacy "light_preset" -> new profile, for one-time settings migration.
const LEGACY_PRESET_TO_PROFILE := {
	0: Profile.GOLDEN_AFTERNOON, # Sunset
	1: Profile.COZY_DAYLIGHT,    # Noon
	2: Profile.OVERCAST_MEADOW,  # Overcast
	3: Profile.TWILIGHT,         # Night
	4: Profile.COZY_DAYLIGHT,    # Cozy Daylight
}

# --- Profile baselines --------------------------------------------------
# Absolute values, all in the keys used by APPLY and by the customizer, so a
# UI override simply replaces one key.
#   sun_energy/sun_color/sun_angle(deg)/sun_pitch/sun_yaw — the one light
#   shadows/shadow_opacity/shadow_bias/shadow_blur
#   sky_top/sky_horizon/sky_ground/sky_energy — visible sky + sky brightness
#   ambient_energy/ambient_color/ambient_sky — fill amount/tint/sky blend
#   fog_enabled/fog_color/fog_start/fog_end/fog_strength/fog_sky — depth fog
#   exposure/contrast/saturation/tint/highlight — final grade
const PROFILES := {
	Profile.COZY_DAYLIGHT: {
		"sun_energy": 0.85, "sun_color": Color(1.0, 0.96, 0.89),
		"sun_angle": 1.0, "sun_pitch": -0.85, "sun_yaw": 0.55,
		"shadows": true, "shadow_opacity": 1.0, "shadow_bias": 0.03, "shadow_blur": 2.0,
		"sky_top": Color(0.30, 0.52, 0.88), "sky_horizon": Color(0.72, 0.84, 0.94),
		"sky_ground": Color(0.52, 0.60, 0.52), "sky_energy": 0.50,
		"ambient_energy": 0.42, "ambient_color": Color(0.66, 0.76, 0.88), "ambient_sky": 0.60,
		"fog_enabled": true, "fog_color": Color(0.70, 0.80, 0.78),
		"fog_start": 60.0, "fog_end": 340.0, "fog_strength": 0.55, "fog_sky": 0.20,
		"exposure": 0.92, "contrast": 1.14, "saturation": 1.14,
		"tint": Color(1, 1, 1), "highlight": 1.0,
	},
	Profile.GOLDEN_AFTERNOON: {
		"sun_energy": 0.90, "sun_color": Color(1.0, 0.90, 0.74),
		"sun_angle": 1.2, "sun_pitch": -0.62, "sun_yaw": 0.50,
		"shadows": true, "shadow_opacity": 1.0, "shadow_bias": 0.03, "shadow_blur": 2.0,
		"sky_top": Color(0.40, 0.56, 0.84), "sky_horizon": Color(0.96, 0.87, 0.72),
		"sky_ground": Color(0.72, 0.66, 0.52), "sky_energy": 0.68,
		"ambient_energy": 0.55, "ambient_color": Color(0.74, 0.80, 0.92), "ambient_sky": 0.55,
		"fog_enabled": true, "fog_color": Color(0.93, 0.86, 0.76),
		"fog_start": 25.0, "fog_end": 260.0, "fog_strength": 0.45, "fog_sky": 0.28,
		"exposure": 1.0, "contrast": 1.08, "saturation": 1.05,
		"tint": Color(1, 1, 1), "highlight": 1.0,
	},
	Profile.OVERCAST_MEADOW: {
		"sun_energy": 0.55, "sun_color": Color(1.0, 0.99, 0.97),
		"sun_angle": 2.0, "sun_pitch": -1.05, "sun_yaw": 0.30,
		"shadows": true, "shadow_opacity": 0.85, "shadow_bias": 0.04, "shadow_blur": 2.5,
		"sky_top": Color(0.58, 0.64, 0.72), "sky_horizon": Color(0.84, 0.86, 0.89),
		"sky_ground": Color(0.68, 0.70, 0.68), "sky_energy": 0.90,
		"ambient_energy": 0.80, "ambient_color": Color(0.80, 0.84, 0.92), "ambient_sky": 0.75,
		"fog_enabled": true, "fog_color": Color(0.82, 0.85, 0.88),
		"fog_start": 12.0, "fog_end": 140.0, "fog_strength": 0.50, "fog_sky": 0.45,
		"exposure": 1.0, "contrast": 1.03, "saturation": 1.02,
		"tint": Color(1, 1, 1), "highlight": 1.0,
	},
	Profile.TWILIGHT: {
		"sun_energy": 0.45, "sun_color": Color(1.0, 0.80, 0.62),
		"sun_angle": 1.5, "sun_pitch": -0.45, "sun_yaw": 0.70,
		"shadows": true, "shadow_opacity": 1.0, "shadow_bias": 0.03, "shadow_blur": 2.0,
		"sky_top": Color(0.16, 0.22, 0.44), "sky_horizon": Color(0.90, 0.62, 0.54),
		"sky_ground": Color(0.34, 0.30, 0.40), "sky_energy": 0.55,
		"ambient_energy": 0.50, "ambient_color": Color(0.55, 0.62, 0.85), "ambient_sky": 0.40,
		"fog_enabled": true, "fog_color": Color(0.38, 0.36, 0.50),
		"fog_start": 20.0, "fog_end": 200.0, "fog_strength": 0.50, "fog_sky": 0.35,
		"exposure": 1.0, "contrast": 1.08, "saturation": 1.05,
		"tint": Color(1, 1, 1), "highlight": 1.0,
	},
	Profile.CAVE: {
		"sun_energy": 0.20, "sun_color": Color(0.72, 0.78, 0.92),
		"sun_angle": 1.0, "sun_pitch": -1.20, "sun_yaw": 0.20,
		"shadows": true, "shadow_opacity": 1.0, "shadow_bias": 0.03, "shadow_blur": 2.0,
		"sky_top": Color(0.05, 0.06, 0.09), "sky_horizon": Color(0.11, 0.12, 0.14),
		"sky_ground": Color(0.09, 0.09, 0.11), "sky_energy": 0.30,
		"ambient_energy": 0.45, "ambient_color": Color(0.60, 0.68, 0.85), "ambient_sky": 0.50,
		"fog_enabled": true, "fog_color": Color(0.09, 0.10, 0.13),
		"fog_start": 4.0, "fog_end": 45.0, "fog_strength": 0.60, "fog_sky": 0.55,
		"exposure": 1.0, "contrast": 1.06, "saturation": 1.00,
		"tint": Color(1, 1, 1), "highlight": 1.0,
	},
}

## UI schema: four collapsible sections of controls. `step` doubles as the
## numeric readout precision. Keys match PROFILES.
const CONTROLS := [
	{"section": "Directional Light", "params": [
		{"key": "sun_energy", "label": "Energy", "kind": "float", "min": 0.0, "max": 3.0, "step": 0.01},
		{"key": "sun_color", "label": "Color", "kind": "color"},
		{"key": "sun_angle", "label": "Angular Size", "kind": "float", "min": 0.0, "max": 8.0, "step": 0.1},
		{"key": "shadows", "label": "Shadows", "kind": "bool"},
		{"key": "shadow_opacity", "label": "Shadow Darkness", "kind": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": "shadow_bias", "label": "Shadow Bias", "kind": "float", "min": 0.0, "max": 0.2, "step": 0.005},
		{"key": "shadow_blur", "label": "Shadow Softness", "kind": "float", "min": 0.0, "max": 4.0, "step": 0.1},
	]},
	{"section": "Sky & Ambient Light", "params": [
		{"key": "sky_top", "label": "Sky Top", "kind": "color"},
		{"key": "sky_horizon", "label": "Sky Horizon", "kind": "color"},
		{"key": "sky_ground", "label": "Sky Ground", "kind": "color"},
		{"key": "sky_energy", "label": "Sky Brightness", "kind": "float", "min": 0.0, "max": 2.0, "step": 0.01},
		{"key": "ambient_energy", "label": "Ambient Energy", "kind": "float", "min": 0.0, "max": 2.0, "step": 0.01},
		{"key": "ambient_color", "label": "Ambient Color", "kind": "color"},
		{"key": "ambient_sky", "label": "Sky Contribution", "kind": "float", "min": 0.0, "max": 1.0, "step": 0.01},
	]},
	{"section": "Atmosphere & Fog", "params": [
		{"key": "fog_enabled", "label": "Fog", "kind": "bool"},
		{"key": "fog_color", "label": "Fog Color", "kind": "color"},
		{"key": "fog_start", "label": "Fog Start", "kind": "float", "min": 0.0, "max": 200.0, "step": 1.0},
		{"key": "fog_end", "label": "Fog End", "kind": "float", "min": 10.0, "max": 600.0, "step": 1.0},
		{"key": "fog_strength", "label": "Fog Strength", "kind": "float", "min": 0.0, "max": 1.0, "step": 0.01},
	]},
	{"section": "Color Grading", "params": [
		{"key": "exposure", "label": "Exposure", "kind": "float", "min": 0.4, "max": 2.0, "step": 0.01},
		{"key": "contrast", "label": "Contrast", "kind": "float", "min": 0.5, "max": 2.0, "step": 0.01},
		{"key": "saturation", "label": "Saturation", "kind": "float", "min": 0.0, "max": 2.0, "step": 0.01},
		{"key": "tint", "label": "Color Tint", "kind": "color"},
		{"key": "highlight", "label": "Highlight White", "kind": "float", "min": 1.0, "max": 8.0, "step": 0.1},
	]},
]

# --- Per-profile overrides (customizer) --------------------------------
static var _overrides: Dictionary = {}
static var _overrides_loaded := false
static var _tint_tex: GradientTexture1D = null
static var _tint_src: Color = Color(-1, -1, -1)


static func baseline(profile: int) -> Dictionary:
	return PROFILES.get(clampi(profile, 0, PROFILE_NAMES.size() - 1),
		PROFILES[Profile.COZY_DAYLIGHT])


## Baseline merged with any saved overrides for that profile (a fresh dict,
## so callers can read it freely).
static func effective(profile: int) -> Dictionary:
	var out: Dictionary = baseline(profile).duplicate()
	var p := clampi(profile, 0, PROFILE_NAMES.size() - 1)
	if _overrides.has(p):
		var o: Dictionary = _overrides[p]
		for k in o:
			out[k] = o[k]
	return out


static func get_value(profile: int, key: String) -> Variant:
	return effective(profile).get(key)


static func has_override(profile: int, key: String) -> bool:
	var p := clampi(profile, 0, PROFILE_NAMES.size() - 1)
	return _overrides.has(p) and (_overrides[p] as Dictionary).has(key)


static func set_override(profile: int, key: String, value: Variant) -> void:
	var p := clampi(profile, 0, PROFILE_NAMES.size() - 1)
	if not _overrides.has(p):
		_overrides[p] = {}
	(_overrides[p] as Dictionary)[key] = value


static func clear_override(profile: int, key: String) -> void:
	var p := clampi(profile, 0, PROFILE_NAMES.size() - 1)
	if _overrides.has(p):
		(_overrides[p] as Dictionary).erase(key)
		if (_overrides[p] as Dictionary).is_empty():
			_overrides.erase(p)


static func clear_profile_overrides(profile: int) -> void:
	_overrides.erase(clampi(profile, 0, PROFILE_NAMES.size() - 1))


static func clear_all_overrides() -> void:
	_overrides.clear()


static func overrides_for(profile: int) -> Dictionary:
	var p := clampi(profile, 0, PROFILE_NAMES.size() - 1)
	return (_overrides[p] as Dictionary).duplicate() if _overrides.has(p) else {}


static func _ensure_overrides_loaded() -> void:
	if _overrides_loaded:
		return
	_overrides_loaded = true
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) == OK:
		load_overrides(c)


static func load_overrides(c: ConfigFile) -> void:
	_overrides_loaded = true
	_overrides.clear()
	for p in PROFILE_NAMES.size():
		var sec := "light_profile_%d" % p
		if not c.has_section(sec):
			continue
		var d = c.get_value(sec, "overrides", null)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var clean: Dictionary = {}
		var base: Dictionary = baseline(p)
		for k in (d as Dictionary):
			var key := String(k)
			if not base.has(key):
				continue
			clean[key] = _sanitise(key, d[key])
		if not clean.is_empty():
			_overrides[p] = clean


static func save_overrides(c: ConfigFile) -> void:
	for p in PROFILE_NAMES.size():
		var sec := "light_profile_%d" % p
		if _overrides.has(p) and not (_overrides[p] as Dictionary).is_empty():
			c.set_value(sec, "overrides", _overrides[p])
		elif c.has_section(sec):
			c.erase_section(sec)


## Clamps/validates a stored override to its baseline type.
static func _sanitise(key: String, v: Variant) -> Variant:
	var t: Variant = baseline(Profile.COZY_DAYLIGHT).get(key)
	match typeof(t):
		TYPE_BOOL:
			return bool(v)
		TYPE_COLOR:
			return v if typeof(v) == TYPE_COLOR else t
		TYPE_FLOAT, TYPE_INT:
			return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else t
	return v


# --- Settings resolution ------------------------------------------------

## Profile chosen for a given mode: the global Settings override when set
## (>= 0), otherwise the mode's own default.
static func resolve_profile(c: ConfigFile, mode: int) -> int:
	var v := int(c.get_value("game", "lighting_profile", -1))
	if v >= 0:
		return clampi(v, 0, PROFILE_NAMES.size() - 1)
	return int(MODE_DEFAULT_PROFILE.get(mode, Profile.COZY_DAYLIGHT))


## Reads the user's profile choice from a config, migrating the legacy
## light_preset key once (then the caller can drop the old key).
static func profile_from_config(c: ConfigFile, mode: int) -> int:
	if c.has_section_key("game", "lighting_profile"):
		return resolve_profile(c, mode)
	if c.has_section_key("game", "light_preset"):
		return int(LEGACY_PRESET_TO_PROFILE.get(
			clampi(int(c.get_value("game", "light_preset", 0)), 0, 4),
			Profile.COZY_DAYLIGHT))
	return int(MODE_DEFAULT_PROFILE.get(mode, Profile.COZY_DAYLIGHT))


# --- Rig build / apply --------------------------------------------------

## Builds the WorldEnvironment + sun under `parent` and applies `profile`.
## Returns {"we", "env", "sky_mat", "sun"}. Safe to call once per scene.
static func build(parent: Node3D, profile: int = Profile.COZY_DAYLIGHT) -> Dictionary:
	_ensure_overrides_loaded()
	var we := WorldEnvironment.new()
	we.name = "CBLightingEnv"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Depth fog so the fog Start/End controls are real; exponential is
	# cheaper but not range-addressable. Both are inexpensive in GL
	# Compatibility.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_aerial_perspective = 0.0
	env.fog_height = 0.0
	env.fog_height_density = 0.0
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_blend_splits = true
	parent.add_child(sun)

	var rig: Dictionary = {"we": we, "env": env, "sky_mat": psm, "sun": sun}
	apply(rig, profile)
	return rig


## Generates (and caches) the colour-correction LUT for the Tint control:
## a black→tint ramp maps every colour through the tint. White = identity.
static func _tint_texture(c: Color) -> GradientTexture1D:
	if _tint_tex != null and _tint_src == c:
		return _tint_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0), c])
	var t := GradientTexture1D.new()
	t.gradient = g
	_tint_tex = t
	_tint_src = c
	return t


## Writes every effective value as an ABSOLUTE setter. Re-running with a new
## profile is idempotent and never compounds. Only lighting/environment
## properties are touched — quality (MSAA, shadow size, resolution scale) is
## owned elsewhere and left alone.
static func apply(rig: Dictionary, profile: int) -> void:
	if rig.is_empty():
		return
	var env := rig.get("env") as Environment
	var sun := rig.get("sun") as DirectionalLight3D
	var psm := rig.get("sky_mat") as ProceduralSkyMaterial
	if env == null or sun == null or psm == null:
		return
	var d: Dictionary = effective(profile)

	# --- Sky (visible) ---
	psm.sky_top_color = d["sky_top"]
	psm.sky_horizon_color = d["sky_horizon"]
	psm.ground_horizon_color = d["sky_ground"]
	# Derived darker base band so the sky's lower hemisphere still reads.
	psm.ground_bottom_color = (d["sky_ground"] as Color).darkened(0.25)
	psm.sun_angle_max = 12.0
	psm.sun_curve = 0.06

	# --- Ambient fill (independent of the visible sky) ---
	env.background_energy_multiplier = d["sky_energy"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = d["ambient_sky"]
	env.ambient_light_color = d["ambient_color"]
	env.ambient_light_energy = d["ambient_energy"]

	# --- Fog (depth) ---
	env.fog_enabled = bool(d["fog_enabled"])
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = d["fog_color"]
	env.fog_depth_begin = float(d["fog_start"])
	env.fog_depth_end = maxf(float(d["fog_end"]), float(d["fog_start"]) + 1.0)
	env.fog_depth_curve = float(d["fog_strength"])
	env.fog_sky_affect = d["fog_sky"]

	# --- Grade ---
	env.tonemap_exposure = float(d["exposure"])
	env.tonemap_white = float(d["highlight"])
	if "adjustment_enabled" in env:
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = float(d["contrast"])
		env.adjustment_saturation = float(d["saturation"])
		env.adjustment_color_correction = _tint_texture(d["tint"])

	# --- Sun ---
	sun.light_color = d["sun_color"]
	sun.light_energy = float(d["sun_energy"])
	sun.light_angular_distance = float(d["sun_angle"])
	sun.rotation = Vector3(d["sun_pitch"], d["sun_yaw"], 0.0)
	sun.shadow_enabled = bool(d["shadows"])
	sun.shadow_opacity = float(d["shadow_opacity"])
	sun.shadow_bias = float(d["shadow_bias"])
	sun.shadow_blur = float(d["shadow_blur"])


## Shadow cost controlled by Graphics quality (Low/Medium/High/Ultra). This
## only changes split count + range; the sun's colour/angle/energy are the
## profile's, so the look stays consistent across tiers.
static func apply_quality_shadows(sun: DirectionalLight3D, quality: int) -> void:
	if sun == null:
		return
	match clampi(quality, 0, 3):
		0:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 60.0
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 90.0
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 120.0
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 160.0
