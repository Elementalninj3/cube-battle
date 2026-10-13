class_name AnimClip
extends RefCounted
## Keyframe clip format for the custom animation editor.
## Stored as JSON in res://animations/<skin>/<name>.json so it stays
## human-readable and loadable without the editor. A real Godot
## Animation resource (.tres) is generated alongside on every save via
## to_animation() for AnimationPlayer compatibility.
##
## Data layout (all plain types, JSON-safe):
## { "name": String, "skin": String, "length": float, "speed": float,
##   "loop": bool, "category": String, "interp": String ("smooth"/"linear"/"stepped"),
##   "windup_end": float, "active_end": float,
##   "hitbox_on": float, "hitbox_off": float,
##   "damage_time": float (-1 = none), "vfx_time": float (-1 = none),
##   "playback_speed": float, "recovery": float,
##   "tracks": { part: { "pos": [[t,x,y,z]...], "rot": [[t,rx,ry,rz]...deg],
##                        "scl": [[t,x,y,z]...] } } }
## Rotations are euler degrees (XYZ order) for readability.
## Missing parts / empty channels fall back to the base pose passed by the caller.

const CATEGORIES := ["idle", "movement", "attack", "defense", "hit_reaction",
	"jump", "landing", "custom"]
const INTERPS := ["smooth", "linear", "stepped"]
const EDITABLE_PARTS := ["model", "arm_l", "arm_r", "sword", "shield", "hat", "skin", "gun", "rifle"]


static func new_clip(p_name: String, p_skin: String, length: float = 1.0) -> Dictionary:
	return {
		"name": p_name, "skin": p_skin, "length": maxf(0.1, length),
		"speed": 1.0, "loop": true, "category": "attack", "interp": "smooth",
		"windup_end": length * 0.3, "active_end": length * 0.65,
		"hitbox_on": length * 0.3, "hitbox_off": length * 0.65,
		"damage_time": -1.0, "vfx_time": -1.0,
		"playback_speed": 1.0, "recovery": 0.3,
		"tracks": {},
	}


static func default_clips(skin: String) -> Array:
	var idle := new_clip("idle", skin, 1.6)
	idle["category"] = "idle"
	idle["loop"] = true
	idle["tracks"] = {
		"model": {"pos": [[0.0, 0, 0, 0], [0.8, 0, 0.03, 0], [1.6, 0, 0, 0]],
			"rot": [], "scl": []},
	}
	var sweep := new_clip("sword_sweep", skin, 1.1)
	sweep["category"] = "attack"
	sweep["loop"] = false
	sweep["hitbox_on"] = 0.35
	sweep["hitbox_off"] = 0.8
	sweep["damage_time"] = 0.55
	sweep["vfx_time"] = 0.4
	sweep["windup_end"] = 0.35
	sweep["active_end"] = 0.8
	sweep["tracks"] = {
		# Upright blade: slash with pitch (x) + lateral tilt (z), not spin (y).
		"sword": {
			"pos": [],
			"rot": [[0.0, 10, 0, -48], [0.35, 14, 0, -52], [0.65, -16, 0, 42], [1.1, 10, 0, -30]],
			"scl": []},
		"arm_r": {
			"pos": [[0.0, 0.62, 0.55, 0.0], [0.35, 0.62, 0.62, 0.3], [0.65, 0.3, 0.9, 1.2], [1.1, 0.62, 0.55, 0.0]],
			"rot": [], "scl": []},
		"model": {
			"pos": [],
			"rot": [[0.0, -5, -14, 0], [0.35, -5, -16, 0], [0.65, 11, 15, 0], [1.1, 0, 0, 0]],
			"scl": []},
	}
	var bash := new_clip("shield_bash", skin, 1.0)
	bash["category"] = "attack"
	bash["loop"] = false
	bash["hitbox_on"] = 0.3
	bash["hitbox_off"] = 0.6
	bash["damage_time"] = 0.35
	bash["vfx_time"] = 0.3
	bash["windup_end"] = 0.3
	bash["active_end"] = 0.6
	bash["tracks"] = {
		"shield": {
			"pos": [[0.0, -0.05, 0.05, 0.22], [0.3, -0.05, 0.1, 0.32], [0.5, -0.05, 0.1, 0.62], [1.0, -0.05, 0.05, 0.22]],
			"rot": [], "scl": []},
		"model": {
			"pos": [],
			"rot": [[0.0, -11, 0, 0], [0.3, -11, 0, 0], [0.5, 29, 0, 0], [1.0, 0, 0, 0]],
			"scl": []},
	}
	return [idle, sweep, bash]


static func clip_dir(skin: String) -> String:
	# Friendly folder names: cubeknight -> res://animations/knight/,
	# cubecowboy -> res://animations/cowboy/.
	match skin:
		"cubeknight":
			return "res://animations/knight"
		"cubecowboy":
			return "res://animations/cowboy"
	return "res://animations/" + skin


static func clip_path(skin: String, clip_name: String) -> String:
	return clip_dir(skin) + "/" + clip_name + ".json"


static func anim_res_path(skin: String, clip_name: String) -> String:
	return clip_dir(skin) + "/" + clip_name + ".tres"


static func list_clips(skin: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(clip_dir(skin))
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json") and f != "attack_map.json":
			out.append(f.get_basename())
	out.sort()
	return out


static func save_json(path: String, clip: Dictionary) -> int:
	# Ensure folder exists (works for res:// when running from editor/game).
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)) \
			and not DirAccess.dir_exists_absolute(folder):
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		if err != OK:
			DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(clip, "\t"))
	f.close()
	return OK


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and (parsed as Dictionary).has("tracks"):
		return _sanitize(parsed)
	return {}


static func _sanitize(clip: Dictionary) -> Dictionary:
	var base := new_clip(str(clip.get("name", "untitled")), str(clip.get("skin", "cubeknight")),
		float(clip.get("length", 1.0)))
	for k in base.keys():
		if clip.has(k):
			base[k] = clip[k]
	if clip.has("tracks") and clip["tracks"] is Dictionary:
		var clean := {}
		for part in (clip["tracks"] as Dictionary).keys():
			if part in EDITABLE_PARTS:
				var ch: Dictionary = (clip["tracks"] as Dictionary)[part]
				clean[part] = {
					"pos": _clean_keys(ch.get("pos", []), 3),
					"rot": _clean_keys(ch.get("rot", []), 3),
					"scl": _clean_keys(ch.get("scl", []), 3),
				}
		base["tracks"] = clean
	base["length"] = maxf(0.1, float(base["length"]))
	return base


static func _clean_keys(keys: Array, dims: int) -> Array:
	var out: Array = []
	for k in keys:
		if k is Array and k.size() == dims + 1:
			var row: Array = [clampf(float(k[0]), 0.0, 60.0)]
			for i in range(dims):
				row.append(float(k[i + 1]))
			out.append(row)
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out


# ---------- sampling ----------

static func _chan_at(keys: Array, t: float, interp: String, fallback: Vector3) -> Vector3:
	if keys.is_empty():
		return fallback
	if keys.size() == 1 or t <= float(keys[0][0]):
		return Vector3(float(keys[0][1]), float(keys[0][2]), float(keys[0][3]))
	var last: Array = keys[keys.size() - 1]
	if t >= float(last[0]):
		return Vector3(float(last[1]), float(last[2]), float(last[3]))
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var span := maxf(float(b[0]) - float(a[0]), 0.0001)
			var u := clampf((t - float(a[0])) / span, 0.0, 1.0)
			if interp == "stepped":
				u = 0.0
			elif interp == "smooth":
				u = u * u * (3.0 - 2.0 * u)
			var va := Vector3(float(a[1]), float(a[2]), float(a[3]))
			var vb := Vector3(float(b[1]), float(b[2]), float(b[3]))
			return va.lerp(vb, u)
	return fallback


## Returns { part: {"pos": Vector3, "rot": Vector3 (deg), "scl": Vector3} }
## for every part present in tracks; base provides fallbacks.
static func sample_pose(clip: Dictionary, t: float, base: Dictionary) -> Dictionary:
	var interp := str(clip.get("interp", "smooth"))
	var pose := {}
	var tracks: Dictionary = clip.get("tracks", {})
	for part in tracks.keys():
		var ch: Dictionary = tracks[part]
		var b: Dictionary = base.get(part, {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scl": Vector3.ONE})
		pose[part] = {
			"pos": _chan_at(ch.get("pos", []), t, interp, b["pos"]),
			"rot": _chan_at(ch.get("rot", []), t, interp, b["rot"]),
			"scl": _chan_at(ch.get("scl", []), t, interp, b["scl"]),
		}
	return pose


## Convert to a real Godot Animation (Node3D pos/rot/scale tracks) so clips
## also work with AnimationPlayer. Node paths match the editor preview names.
static func to_animation(clip: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = float(clip.get("length", 1.0))
	a.loop_mode = Animation.LOOP_LINEAR if bool(clip.get("loop", true)) else Animation.LOOP_NONE
	a.step = 1.0 / 60.0
	var tracks: Dictionary = clip.get("tracks", {})
	for part in tracks.keys():
		var ch: Dictionary = tracks[part]
		_add_vec_track(a, str(part) + ":position", ch.get("pos", []), a.length)
		var rot_keys: Array = ch.get("rot", [])
		if not rot_keys.is_empty():
			var idx := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(idx, NodePath(str(part) + ":rotation"))
			for k in rot_keys:
				var e := Vector3(deg_to_rad(float(k[1])), deg_to_rad(float(k[2])), deg_to_rad(float(k[3])))
				a.rotation_track_insert_key(idx, clampf(float(k[0]), 0.0, a.length), Quaternion.from_euler(e))
		_add_vec_track(a, str(part) + ":scale", ch.get("scl", []), a.length)
	return a


static func _add_vec_track(a: Animation, path: String, keys: Array, length: float) -> void:
	if keys.is_empty():
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath(path))
	for k in keys:
		a.track_insert_key(idx, clampf(float(k[0]), 0.0, length),
			Vector3(float(k[1]), float(k[2]), float(k[3])))
