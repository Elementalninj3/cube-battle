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
## Compatibility has no SDFGI/SSAO/SSIL/glow anyway). Contrast comes from
## the light relationship (warm sun vs cool-neutral ambient), not from
## expensive post effects; the only grade is a tiny, cheap tonemap
## contrast/saturation trim.
##
## Five environment profiles, each a set of ABSOLUTE values, so switching
## or re-applying never compounds and never touches unrelated quality
## settings:
##   Cozy Daylight · Golden Afternoon · Overcast Meadow · Twilight · Cave
##
## Usage:
##   var rig := CBLighting.build(self, CBLighting.Profile.COZY_DAYLIGHT)
##   CBLighting.apply(rig, CBLighting.Profile.TWILIGHT)   # re-tune live
##   CBLighting.apply_quality_shadows(rig["sun"], quality)

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
## default"). Matches the agreed art direction: every cozy-grass mode opens
## on Cozy Daylight; the big arena opens on the warmer Golden Afternoon.
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

# --- Profile data -------------------------------------------------------
# Every value here is absolute. `sky_energy` scales the sky's contribution
# (background_energy_multiplier); `ambient` is ambient_light_energy.
# Sun pitch/yaw are radians (pitch negative = pointing down). Keep the
# ambient COOL-NEUTRAL against a WARM sun so lit vs shaded reads clearly.
const PROFILES := {
	Profile.COZY_DAYLIGHT: {
		"sky_top": Color(0.36, 0.58, 0.90),
		"sky_horizon": Color(0.83, 0.90, 0.98),
		"ground_bottom": Color(0.24, 0.28, 0.22),
		"ground_horizon": Color(0.68, 0.74, 0.66),
		"sky_energy": 0.60,
		"ambient": 0.38,
		"fog_color": Color(0.86, 0.91, 0.96),
		"fog_density": 0.0015,
		"fog_sky": 0.20,
		"sun_color": Color(1.0, 0.96, 0.89),
		"sun_energy": 1.10,
		"sun_pitch": -0.85,
		"sun_yaw": 0.55,
		"contrast": 1.12,
		"saturation": 1.08,
	},
	Profile.GOLDEN_AFTERNOON: {
		"sky_top": Color(0.40, 0.56, 0.84),
		"sky_horizon": Color(0.96, 0.87, 0.72),
		"ground_bottom": Color(0.26, 0.28, 0.20),
		"ground_horizon": Color(0.80, 0.73, 0.58),
		"sky_energy": 0.80,
		"ambient": 0.50,
		"fog_color": Color(0.95, 0.88, 0.78),
		"fog_density": 0.0020,
		"fog_sky": 0.28,
		"sun_color": Color(1.0, 0.90, 0.72),
		"sun_energy": 1.30,
		"sun_pitch": -0.62,
		"sun_yaw": 0.50,
		"contrast": 1.10,
		"saturation": 1.06,
	},
	Profile.OVERCAST_MEADOW: {
		"sky_top": Color(0.60, 0.66, 0.74),
		"sky_horizon": Color(0.86, 0.88, 0.91),
		"ground_bottom": Color(0.28, 0.30, 0.28),
		"ground_horizon": Color(0.72, 0.74, 0.72),
		"sky_energy": 0.95,
		"ambient": 0.75,
		"fog_color": Color(0.82, 0.85, 0.88),
		"fog_density": 0.0060,
		"fog_sky": 0.45,
		"sun_color": Color(1.0, 0.99, 0.97),
		"sun_energy": 0.75,
		"sun_pitch": -1.05,
		"sun_yaw": 0.30,
		"contrast": 1.03,
		"saturation": 1.02,
	},
	Profile.TWILIGHT: {
		"sky_top": Color(0.16, 0.22, 0.44),
		"sky_horizon": Color(0.90, 0.62, 0.54),
		"ground_bottom": Color(0.10, 0.12, 0.18),
		"ground_horizon": Color(0.34, 0.30, 0.40),
		"sky_energy": 0.60,
		"ambient": 0.45,
		"fog_color": Color(0.38, 0.36, 0.50),
		"fog_density": 0.0035,
		"fog_sky": 0.35,
		"sun_color": Color(1.0, 0.80, 0.62),
		"sun_energy": 0.60,
		"sun_pitch": -0.45,
		"sun_yaw": 0.70,
		"contrast": 1.08,
		"saturation": 1.05,
	},
	Profile.CAVE: {
		"sky_top": Color(0.05, 0.06, 0.09),
		"sky_horizon": Color(0.11, 0.12, 0.14),
		"ground_bottom": Color(0.04, 0.04, 0.05),
		"ground_horizon": Color(0.09, 0.09, 0.11),
		"sky_energy": 0.30,
		"ambient": 0.40,
		"fog_color": Color(0.09, 0.10, 0.13),
		"fog_density": 0.020,
		"fog_sky": 0.55,
		"sun_color": Color(0.72, 0.78, 0.92),
		"sun_energy": 0.25,
		"sun_pitch": -1.20,
		"sun_yaw": 0.20,
		"contrast": 1.06,
		"saturation": 1.00,
	},
}


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
		var v := int(c.get_value("game", "lighting_profile", -1))
		if v >= 0:
			return clampi(v, 0, PROFILE_NAMES.size() - 1)
		return int(MODE_DEFAULT_PROFILE.get(mode, Profile.COZY_DAYLIGHT))
	if c.has_section_key("game", "light_preset"):
		return int(LEGACY_PRESET_TO_PROFILE.get(
			clampi(int(c.get_value("game", "light_preset", 0)), 0, 4),
			Profile.COZY_DAYLIGHT))
	return int(MODE_DEFAULT_PROFILE.get(mode, Profile.COZY_DAYLIGHT))


# --- Rig build / apply --------------------------------------------------

## Builds the WorldEnvironment + sun under `parent` and applies `profile`.
## Returns {"we", "env", "sky_mat", "sun"}. Safe to call once per scene.
static func build(parent: Node3D, profile: int = Profile.COZY_DAYLIGHT) -> Dictionary:
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
	env.fog_enabled = true
	# Thin fog that only reads at distance; sky stays clear for the
	# cozy "blue above, warm horizon" band.
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
	sun.shadow_opacity = 1.0
	parent.add_child(sun)

	var rig: Dictionary = {"we": we, "env": env, "sky_mat": psm, "sun": sun}
	apply(rig, profile)
	return rig


## Writes every profile value as an ABSOLUTE setter. Re-running with a new
## profile is idempotent and never compounds. Only lighting/environment
## properties are touched — quality (MSAA, shadow quality/size, resolution
## scale) is owned elsewhere and left alone.
static func apply(rig: Dictionary, profile: int) -> void:
	if rig.is_empty():
		return
	var env := rig.get("env") as Environment
	var sun := rig.get("sun") as DirectionalLight3D
	var psm := rig.get("sky_mat") as ProceduralSkyMaterial
	var d: Dictionary = PROFILES.get(
		clampi(profile, 0, PROFILE_NAMES.size() - 1),
		PROFILES[Profile.COZY_DAYLIGHT])
	if env == null or sun == null or psm == null:
		return

	psm.sky_top_color = d["sky_top"]
	psm.sky_horizon_color = d["sky_horizon"]
	psm.ground_bottom_color = d["ground_bottom"]
	psm.ground_horizon_color = d["ground_horizon"]
	psm.sun_angle_max = 12.0
	psm.sun_curve = 0.06

	env.background_energy_multiplier = d["sky_energy"]
	env.ambient_light_energy = d["ambient"]
	env.fog_light_color = d["fog_color"]
	env.fog_density = d["fog_density"]
	env.fog_sky_affect = d["fog_sky"]
	if "adjustment_enabled" in env:
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = d["contrast"]
		env.adjustment_saturation = d["saturation"]

	sun.light_color = d["sun_color"]
	sun.light_energy = d["sun_energy"]
	sun.rotation = Vector3(d["sun_pitch"], d["sun_yaw"], 0.0)


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
