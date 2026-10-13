extends Node3D
## Blocky fighter ported from block-brawl-quality.html: floating head cube +
## fist cubes + hat, custom combat state machine (free/atk/dash/stun/ko),
## procedural animation, HTML attack table (light/heavy).

const ATK_L := {"w": 0.1, "a": 0.08, "r": 0.18, "dmg": 6.0, "kb": 4.5,
	"range": 2.0, "arc": 0.32, "lunge": 3.0, "sh": 0.08, "hs": 0.04, "vy": 0.0,
	"kind": "punch", "big": false, "radial": false}
const ATK_H := {"w": 0.38, "a": 0.1, "r": 0.42, "dmg": 15.0, "kb": 10.0,
	"range": 2.6, "arc": 0.12, "lunge": 5.5, "sh": 0.3, "hs": 0.09, "vy": 5.0,
	"kind": "punch", "big": true, "radial": false}
const ATK_S1 := {"w": 0.22, "a": 0.3, "r": 0.3, "dmg": 10.0, "kb": 7.0,
	"range": 2.4, "arc": 0.3, "lunge": 0.0, "sh": 0.2, "hs": 0.06, "vy": 0.0,
	"kind": "dash", "big": false, "radial": false, "cd": 4.0}
const ATK_S2 := {"w": 0.3, "a": 0.15, "r": 0.45, "dmg": 12.0, "kb": 6.0,
	"range": 2.2, "arc": 0.4, "lunge": 2.0, "sh": 0.25, "hs": 0.08, "vy": 9.0,
	"kind": "upper", "big": true, "radial": false, "cd": 6.0}
const ATK_S3 := {"w": 0.3, "a": 0.35, "r": 0.35, "dmg": 9.0, "kb": 8.0,
	"range": 2.6, "arc": 0.0, "lunge": 1.0, "sh": 0.2, "hs": 0.06, "vy": 2.0,
	"kind": "spin", "big": true, "radial": true, "cd": 8.0}
const CD_ORDER := ["S1", "S2", "S3"]

var idx := 0
var game = null
var foe = null
var keys := {"up": [], "down": [], "left": [], "right": [], "L": [], "H": [], "D": [],
	"S1": [], "S2": [], "S3": []}

var body_col := Color(0.86, 0.22, 0.16)
var hat_kind := 1
var visor := true
var skin_name := "cubecowboy"
const SKINS_DIR := "res://skins"
const SKIN_HEIGHT := 1.45
const PROPS_DIR := "res://props"
const RIDE_TIME := 3.5
const HORSE_SPEED := 9.0
const RIDE_DMG := 8.0
const RIDE_KB := 6.0
const RIDE_TICK := 0.5
const RIDE_LIFT := 1.04
const HORSE_SCALE := 1.6
const GALLOP_T := 0.55
const GAL_KEYS := [
	[0.0, 0.18, 0.0, 1.0],
	[0.2, 0.0, 0.12, 1.0],
	[0.4, -0.12, -0.02, 0.94],
	[0.6, -0.05, -0.06, 0.9],
	[0.8, 0.08, 0.04, 0.98],
	[1.0, 0.18, 0.0, 1.0],
]
const ATK_FAN := {"w": 0.25, "a": 0.85, "r": 0.3, "dmg": 4.0, "kb": 2.5, "speed": 22.0, "life": 0.4, "lunge": 0.0, "sh": 0.0, "hs": 0.0, "vy": 2.0, "kind": "fan", "big": false, "radial": false, "cd": 4.0}
const ATK_RIFLE := {"w": 0.35, "a": 0.15, "r": 0.5, "dmg": 24.0, "kb": 12.0, "speed": 38.0, "life": 0.35, "lunge": 0.0, "sh": 0.0, "hs": 0.0, "vy": 6.0, "kind": "rifle", "big": true, "radial": false, "cd": 6.0}
const ATK_COUNTER := {"w": 0.2, "a": 0.5, "r": 0.4, "dmg": 0.0, "kb": 0.0, "lunge": 0.0, "sh": 0.0, "hs": 0.0, "vy": 0.0, "kind": "counter", "big": false, "radial": false, "cd": 5.0}
const ATK_BASH := {"w": 0.3, "a": 0.2, "r": 0.45, "dmg": 12.0, "kb": 10.0, "range": 2.4, "arc": 0.3, "lunge": 0.0, "sh": 0.25, "hs": 0.07, "vy": 5.0, "kind": "bash", "big": true, "radial": false, "cd": 6.0}
const ATK_SWEEP := {"w": 0.35, "a": 0.3, "r": 0.45, "dmg": 16.0, "kb": 9.0, "lunge": 0.0, "sh": 0.2, "hs": 0.06, "vy": 5.0, "kind": "sweep", "big": true, "radial": false, "cd": 7.0}
const COUNTER_DMG := 14.0
const COUNTER_KB := 9.0
const SHIELD_REST := Vector3(-0.05, 0.05, 0.22)
static var _prop_scenes := {}
# Attack Animator overrides: key "skin|kind|phase" (phase 0=windup,1=active,2=recover)
# values are ADDITIVE deltas (0 = no change). Edited in menu Attack Animator.
static var ANIM_OV := {}
const ANIM_SAVE_PATH := "user://anim_overrides.json"
const ANIM_FIELDS := ["lean", "sq", "twist", "e0", "e1", "u0", "u1",
	"arm_scale", "sword_rx", "sword_ry", "sword_s",
	"shield_x", "shield_y", "shield_z", "shield_s"]

const ClipHelper = preload("res://animations/anim_clip.gd")
# Custom keyframe clips from animation_editor (optional).
# res://animations/attack_map.json maps "skin|kind" -> clip json path.
# No entry = fully procedural, so damage/knockback/cooldowns/inputs are untouched.
const ATTACK_MAP_PATH := "res://animations/attack_map.json"
const CUSTOM_PARTS := ["model", "arm_l", "arm_r", "sword", "shield", "hat",
	"skin", "gun", "rifle"]
static var _attack_map := {}
static var _attack_map_mtime := 0
static var _clip_cache := {}


static func _reload_attack_map() -> void:
	if not FileAccess.file_exists(ATTACK_MAP_PATH):
		_attack_map = {}
		return
	var mt := FileAccess.get_modified_time(ATTACK_MAP_PATH)
	if mt == _attack_map_mtime and not _attack_map.is_empty():
		return
	_attack_map_mtime = mt
	var f := FileAccess.open(ATTACK_MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_attack_map = parsed
	else:
		_attack_map = {}


static func custom_clip_for(p_skin: String, p_kind: String) -> Dictionary:
	_reload_attack_map()
	var key := p_skin + "|" + p_kind
	if not _attack_map.has(key):
		return {}
	var path := str(_attack_map[key])
	if _clip_cache.has(path):
		return _clip_cache[path]
	if not FileAccess.file_exists(path):
		return {}
	var cf := FileAccess.open(path, FileAccess.READ)
	if cf == null:
		return {}
	var parsed = JSON.parse_string(cf.get_as_text())
	cf.close()
	if parsed is Dictionary and (parsed as Dictionary).has("tracks"):
		var clean: Dictionary = ClipHelper._sanitize(parsed)
		_clip_cache[path] = clean
		return clean
	return {}


static func anim_key(p_skin: String, p_kind: String, p_phase: int) -> String:
	return p_skin + "|" + p_kind + "|" + str(p_phase)


static func get_anim_ov(p_skin: String, p_kind: String, p_phase: int) -> Dictionary:
	var k := anim_key(p_skin, p_kind, p_phase)
	if ANIM_OV.has(k):
		return ANIM_OV[k]
	return {}


static func set_anim_ov(p_skin: String, p_kind: String, p_phase: int, field: String, val: float) -> void:
	var k := anim_key(p_skin, p_kind, p_phase)
	if not ANIM_OV.has(k):
		ANIM_OV[k] = {}
	(ANIM_OV[k] as Dictionary)[field] = val


static func clear_anim_ov(p_skin: String, p_kind: String, p_phase: int) -> void:
	ANIM_OV.erase(anim_key(p_skin, p_kind, p_phase))


static func save_anim_ovs() -> void:
	var f := FileAccess.open(ANIM_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ANIM_OV))
		f.close()


static func load_anim_ovs() -> void:
	if not FileAccess.file_exists(ANIM_SAVE_PATH):
		return
	var f := FileAccess.open(ANIM_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		ANIM_OV = parsed


func _custom_node(pname: String) -> Node3D:
	match pname:
		"model":
			return model
		"arm_l":
			return arm_l
		"arm_r":
			return arm_r
		"hat":
			return hat_root
		"sword":
			return sword_node
		"shield":
			return shield_node
		"skin":
			return skin_inst
		"gun":
			return gun_node
		"rifle":
			return rifle_node
	return null


func _maybe_start_custom() -> void:
	custom_clip = {}
	custom_t = 0.0
	_clip_cache.clear()
	if atk == null:
		return
	custom_clip = custom_clip_for(skin_name, String(atk.get("kind", "")))


func _apply_custom_clip() -> void:
	if custom_clip.is_empty() or st != "atk" or atk == null:
		return
	# Unkeyed parts fall back to the CURRENT procedural pose, so only the
	# keyed parts of the custom clip override the procedural animation.
	var fb := {}
	for p in CUSTOM_PARTS:
		var n := _custom_node(p)
		if n != null:
			fb[p] = {"pos": n.position,
				"rot": Vector3(rad_to_deg(n.rotation.x), rad_to_deg(n.rotation.y), rad_to_deg(n.rotation.z)),
				"scl": n.scale}
	var spd := float(custom_clip.get("playback_speed", 1.0))
	var pose := ClipHelper.sample_pose(custom_clip, custom_t * spd, fb)
	for p in pose.keys():
		var n2 := _custom_node(str(p))
		if n2 == null:
			continue
		var d: Dictionary = pose[p]
		n2.position = d["pos"]
		var r: Vector3 = d["rot"]
		n2.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		n2.scale = d["scl"]
var fan_left := 0
var fan_t := 0.0
var fan_kick := 0.0
var ride_tick := 0.0
var counter_done := false
var bash_fx_done := false
var bash_streak_t := 0.0
var sweep_fx_t := 0.0
var sweep_core_done := false
var sword_node: Node3D = null
var shield_node: Node3D = null
var skin_inst: Node3D = null
var skin_base_y := 0.0
var gun_node: Node3D = null
var rifle_node: Node3D = null
var horse_root: Node3D = null

var v := Vector3.ZERO
var vy := 0.0
var ang := 0.0
var face := Vector3(0, 0, 1)
var hp := 100.0
var dmg := 0.0
var st := "free"
var t := 0.0
var atk = null
var hit_done := false
var dash_cd := 0.0
var inv := 0.0
var flash := 0.0
var rec := 0.0
var stun := 0.0
var ph := 0.0
var mass := 1.0
var buf := {"L": -9.0, "H": -9.0, "D": -9.0, "S1": -9.0, "S2": -9.0, "S3": -9.0}
var cd := {"S1": 0.0, "S2": 0.0, "S3": 0.0}
var cd_max := {"S1": 4.0, "S2": 6.0, "S3": 8.0}
var spin_a := 0.0
var custom_clip: Dictionary = {}
var custom_t := 0.0
var _dd := Vector3.ZERO
var _tr := 0.0

var model: Node3D
var head_mi: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var hat_root: Node3D
var mats: Array = []
var _box: BoxMesh


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	model = Node3D.new()
	add_child(model)
	arm_l = Node3D.new()
	arm_r = Node3D.new()
	model.add_child(arm_l)
	model.add_child(arm_r)
	hat_root = Node3D.new()
	model.add_child(hat_root)
	rebuild()


func setup(_p_col: Color, _p_hat: int, _p_visor: bool) -> void:
	setup_skin("cubecowboy")


func setup_skin(p_skin: String) -> void:
	skin_name = p_skin
	body_col = _skin_color(p_skin)
	rebuild()


func _skin_color(sname: String) -> Color:
	match sname:
		"cubecowboy":
			return Color(0.86, 0.22, 0.16)
		"cubeknight":
			return Color(0.55, 0.62, 0.72)
		_:
			return Color(0.23, 0.51, 0.96)


func _is_cowboy() -> bool:
	return skin_name == "cubecowboy"


func _is_knight() -> bool:
	return skin_name == "cubeknight"


func top_y() -> float:
	return 3.0 if st == "ride" else 1.9


func counter_open() -> bool:
	return st == "atk" and atk != null and String(atk["kind"]) == "counter" and not counter_done and t >= float(atk["w"]) and t <= float(atk["w"]) + float(atk["a"])


func reset_match(pos: Vector3, p_ang: float) -> void:
	position = pos
	v = Vector3.ZERO
	vy = 0.0
	ang = p_ang
	face = Vector3(sin(ang), 0, cos(ang))
	hp = 100.0
	dmg = 0.0
	st = "free"
	t = 0.0
	atk = null
	custom_clip = {}
	custom_t = 0.0
	dash_cd = 0.0
	inv = 0.0
	flash = 0.0
	rec = 0.0
	spin_a = 0.0
	for key in cd:
		cd[key] = 0.0
	visible = true
	rotation.y = ang


func _mat(col: Color, rough: float = 0.55, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = Color(0.05, 0.05, 0.05)
	mats.append(m)
	return m


func _bx(w: float, h: float, d: float, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box
	mi.scale = Vector3(w, h, d)
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func rebuild() -> void:
	if model == null:
		return
	for c in model.get_children():
		if c != arm_l and c != arm_r and c != hat_root:
			c.queue_free()
	for c in hat_root.get_children():
		c.queue_free()
	for a in [arm_l, arm_r]:
		for c in a.get_children():
			c.queue_free()
	mats.clear()
	var body := _mat(body_col)
	var fist := body
	if _is_knight():
		fist = _mat(Color(0.25, 0.5, 0.95))
	# arms attached at head sides (fists overlap head edge)
	arm_l.position = Vector3(-0.62, 0.55, 0)
	arm_r.position = Vector3(0.62, 0.55, 0)
	_bx(0.36, 0.36, 0.36, fist, Vector3.ZERO, arm_l)
	_bx(0.36, 0.36, 0.36, fist, Vector3.ZERO, arm_r)
	skin_inst = null
	gun_node = null
	rifle_node = null
	horse_root = null
	sword_node = null
	shield_node = null
	if _build_skin():
		head_mi = null
		if _is_cowboy():
			_build_cowboy_gear()
		elif _is_knight():
			_build_knight_gear()
		return
	# fallback: simple floating block (skin file missing)
	var dk := _mat(Color(body_col.r * 0.6, body_col.g * 0.6, body_col.b * 0.6))
	var blk := _mat(Color(0.08, 0.08, 0.08), 0.4)
	var shirt := _mat(Color(0.93, 0.93, 0.93), 0.8)
	head_mi = _bx(1.0, 1.0, 1.0, body, Vector3(0, 0.55, 0), model)
	# block attire: white shirt band + dark tie
	_bx(1.08, 0.32, 1.08, shirt, Vector3(0, 0.22, 0), model)
	_bx(0.18, 0.34, 0.05, dk, Vector3(0, 0.24, 0.55), model)
	if visor:
		_bx(0.6, 0.16, 0.06, _mat(Color(0.1, 0.16, 0.33), 0.2, 0.5), Vector3(0, 0.6, 0.51), model)
	else:
		_bx(0.12, 0.14, 0.05, blk, Vector3(-0.15, 0.6, 0.51), model)
		_bx(0.12, 0.14, 0.05, blk, Vector3(0.15, 0.6, 0.51), model)
	_build_hat(body)


func _collect_skin_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_skin_meshes(c, out)


func _skin_aabb(n: Node3D, parent_t: Transform3D, acc: Array) -> void:
	var lt := parent_t * n.transform
	if n is MeshInstance3D:
		var w := lt * (n as MeshInstance3D).get_aabb()
		if acc[0]:
			acc[1] = w
			acc[0] = false
		else:
			acc[1] = (acc[1] as AABB).merge(w)
	for c in n.get_children():
		if c is Node3D:
			_skin_aabb(c, lt, acc)


func _gallop(u: float) -> Vector3:
	var uu := clampf(u, 0.0, 1.0)
	var i := 0
	while i < GAL_KEYS.size() - 2 and uu > float(GAL_KEYS[i + 1][0]):
		i += 1
	var a: Array = GAL_KEYS[i]
	var b: Array = GAL_KEYS[i + 1]
	var f := clampf((uu - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	return Vector3(lerpf(float(a[1]), float(b[1]), f), lerpf(float(a[2]), float(b[2]), f), lerpf(float(a[3]), float(b[3]), f))


func _build_skin() -> bool:
	var path := SKINS_DIR + "/" + skin_name + ".glb"
	if not ResourceLoader.exists(path):
		path = SKINS_DIR + "/" + skin_name + ".gltf"
		if not ResourceLoader.exists(path):
			return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return false
	model.add_child(inst)
	var meshes: Array = []
	_collect_skin_meshes(inst, meshes)
	if meshes.is_empty():
		inst.queue_free()
		return false
	for m in meshes:
		var mi := m as MeshInstance3D
		var mesh_res := mi.mesh
		if mesh_res == null:
			continue
		for s in range(mesh_res.get_surface_count()):
			var sm := mesh_res.surface_get_material(s)
			if sm != null and sm is StandardMaterial3D:
				var dup := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.emission_enabled = true
				dup.emission = Color(0.05, 0.05, 0.05)
				mi.set_surface_override_material(s, dup)
				mats.append(dup)
	var acc := [true, AABB()]
	_skin_aabb(inst, Transform3D.IDENTITY, acc)
	var box_all := acc[1] as AABB
	var s := SKIN_HEIGHT / maxf(box_all.size.y, 0.001)
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(
		-(box_all.position.x + box_all.size.x * 0.5) * s,
		0.05 - box_all.position.y * s,
		-(box_all.position.z + box_all.size.z * 0.5) * s)
	skin_inst = inst
	skin_base_y = inst.position.y
	return true


func _prop_instance(pname: String) -> Node3D:
	if not _prop_scenes.has(pname):
		var packed := load(PROPS_DIR + "/" + pname + ".glb") as PackedScene
		if packed == null:
			return null
		_prop_scenes[pname] = packed
	return (_prop_scenes[pname] as PackedScene).instantiate() as Node3D


func _gear_wrap(pname: String, parent: Node3D, pos: Vector3, scl: float, tip_z: float) -> Node3D:
	var inst := _prop_instance(pname)
	if inst == null:
		return null
	var wrap := Node3D.new()
	wrap.position = pos
	wrap.scale = Vector3.ONE * scl
	wrap.add_child(inst)
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0, 0, tip_z)
	wrap.add_child(tip)
	wrap.visible = false
	parent.add_child(wrap)
	return wrap


func _build_knight_gear() -> void:
	var sw := _prop_instance("sword")
	if sw != null:
		# Grip correction (visual only): the sword mesh is modeled diagonal
		# and centered on the grip, so bare rotations flail a diagonal slab
		# around the fist. Stand the blade up (+Y, out of the fist) and seat
		# the hilt at the node origin so swings pivot around the hand.
		sw.rotation.z = 0.6412
		sw.position = Vector3(0.0, 0.6, 0.0)
		sword_node = Node3D.new()
		sword_node.position = Vector3(0, 0.3, 0.08)
		sword_node.scale = Vector3.ONE * 0.7
		sword_node.add_child(sw)
		var tip := Node3D.new()
		tip.name = "Tip"
		tip.position = Vector3(0, 0.9, 0)
		sword_node.add_child(tip)
		arm_r.add_child(sword_node)
	var sh := _prop_instance("shield")
	if sh != null:
		shield_node = Node3D.new()
		shield_node.position = SHIELD_REST
		shield_node.scale = Vector3.ONE * 0.6
		shield_node.add_child(sh)
		var tip2 := Node3D.new()
		tip2.name = "Tip"
		tip2.position = Vector3(0, 0.1, 0.25)
		shield_node.add_child(tip2)
		arm_l.add_child(shield_node)


func _sword_tip() -> Vector3:
	if sword_node != null:
		var tip := sword_node.get_node_or_null("Tip") as Node3D
		if tip != null:
			return tip.global_transform.origin
	return global_transform.origin + face + Vector3(0, 0.8, 0)


func _shield_tip() -> Vector3:
	if shield_node != null:
		var tip := shield_node.get_node_or_null("Tip") as Node3D
		if tip != null:
			return tip.global_transform.origin
	return global_transform.origin + face + Vector3(0, 0.6, 0)


func _build_cowboy_gear() -> void:
	gun_node = _gear_wrap("revolver", arm_r, Vector3(0, -0.02, 0.15), 0.55, 0.357)
	rifle_node = _gear_wrap("rifle", arm_r, Vector3(0, 0.0, 0.2), 0.75, 0.449)
	var horse := _prop_instance("horse")
	if horse != null:
		horse_root = Node3D.new()
		horse.scale = Vector3.ONE * HORSE_SCALE
		horse_root.add_child(horse)
		horse_root.visible = false
		model.add_child(horse_root)


func _build_hat(body: Material) -> void:
	if hat_kind == 1: # cowboy
		var b := _mat(Color(0.54, 0.35, 0.17), 0.7)
		_bx(1.05, 0.06, 1.05, b, Vector3(0, 1.08, 0), hat_root)
		_bx(0.5, 0.3, 0.5, b, Vector3(0, 1.25, 0), hat_root)
	elif hat_kind == 2: # crown
		var y := _mat(Color(1.0, 0.79, 0.24), 0.3, 0.7)
		_bx(0.68, 0.16, 0.68, y, Vector3(0, 1.12, 0), hat_root)
		for sx in [-0.27, 0.27]:
			for sz in [-0.27, 0.27]:
				_bx(0.14, 0.16, 0.14, y, Vector3(sx, 1.26, sz), hat_root)
	elif hat_kind == 3: # beanie
		_bx(0.72, 0.24, 0.72, _mat(Color(0.95, 0.95, 0.95)), Vector3(0, 1.16, 0), hat_root)
		_bx(0.72, 0.1, 0.72, body, Vector3(0, 1.07, 0), hat_root)
		_bx(0.16, 0.16, 0.16, body, Vector3(0, 1.36, 0), hat_root)
	elif hat_kind == 4: # helmet
		var s := _mat(Color(0.6, 0.64, 0.7), 0.35, 0.6)
		_bx(0.76, 0.3, 0.76, s, Vector3(0, 1.16, 0), hat_root)
		_bx(0.12, 0.3, 0.8, body, Vector3(0, 1.2, 0), hat_root)


func _input(event: InputEvent) -> void:
	if game == null:
		return
	if not (event is InputEventKey):
		return
	var e := event as InputEventKey
	if not e.pressed or e.echo:
		return
	if not (String(game.state) == "play" or String(game.state) == "count"):
		return
	var k := e.physical_keycode
	var kc := e.keycode
	if k in (keys["L"] as Array) or kc in (keys["L"] as Array):
		buf["L"] = game.now
	elif k in (keys["H"] as Array) or kc in (keys["H"] as Array):
		buf["H"] = game.now
	elif k in (keys["D"] as Array) or kc in (keys["D"] as Array):
		buf["D"] = game.now
	elif k in (keys["S1"] as Array) or kc in (keys["S1"] as Array):
		buf["S1"] = game.now
	elif k in (keys["S2"] as Array) or kc in (keys["S2"] as Array):
		buf["S2"] = game.now
	elif k in (keys["S3"] as Array) or kc in (keys["S3"] as Array):
		buf["S3"] = game.now


func _has(n: String) -> bool:
	return game.now - float(buf[n]) < 0.2


func _eat(n: String) -> void:
	buf[n] = -9.0


func _key_down(codes: Array) -> bool:
	for c in codes:
		if Input.is_physical_key_pressed(c):
			return true
	return false


func upd(dt: float, play: bool) -> void:
	t += dt
	if st != "atk" and not custom_clip.is_empty():
		custom_clip = {}
	elif st == "atk" and not custom_clip.is_empty():
		custom_t += dt
	dash_cd = maxf(0.0, dash_cd - dt)
	inv = maxf(0.0, inv - dt)
	flash = maxf(0.0, flash - dt)
	rec = maxf(0.0, rec - dt)
	for key in cd:
		cd[key] = maxf(0.0, float(cd[key]) - dt)
	if st == "ko":
		return
	position.x = clampf(position.x, -4.7, 4.7)
	position.z = clampf(position.z, -4.7, 4.7)
	var ix := 0.0
	var iy := 0.0
	if play:
		ix = (1.0 if _key_down(keys["right"]) else 0.0) - (1.0 if _key_down(keys["left"]) else 0.0)
		iy = (1.0 if _key_down(keys["up"]) else 0.0) - (1.0 if _key_down(keys["down"]) else 0.0)
	var wx := ix - iy
	var wz := -ix - iy
	var wl := Vector2(wx, wz).length()
	if wl > 0.01:
		wx /= wl
		wz /= wl
	else:
		wx = 0.0
		wz = 0.0
	var ta = null
	if st == "free":
		if play and rec <= 0.0:
			if _has("D") and dash_cd <= 0.0:
				_eat("D")
				start_dash(Vector3(wx, 0, wz) if wl > 0.01 else face)
			elif _has("H"):
				_eat("H")
				start_atk("H")
			elif _has("L"):
				_eat("L")
				start_atk("L")
			elif _has("S1") and float(cd["S1"]) <= 0.0:
				_eat("S1")
				start_atk("S1")
			elif _has("S2") and float(cd["S2"]) <= 0.0:
				_eat("S2")
				start_atk("S2")
			elif _has("S3") and float(cd["S3"]) <= 0.0:
				_eat("S3")
				start_atk("S3")
		if st == "free":
			var e := 1.0 - exp(-(16.0 if wl > 0.01 else 11.0) * dt)
			v.x += (wx * 6.4 - v.x) * e
			v.z += (wz * 6.4 - v.z) * e
			if wl > 0.01:
				ta = atan2(wx, wz)
			elif foe != null and String(foe.st) != "ko":
				ta = atan2(foe.position.x - position.x, foe.position.z - position.z)
	elif st == "atk":
		var e2 := exp(-7.0 * dt)
		v.x *= e2
		v.z *= e2
		if atk != null and String(atk["kind"]) == "dash" and foe != null and String(foe.st) != "ko":
			var ddx: float = foe.position.x - position.x
			var ddz: float = foe.position.z - position.z
			var dl := Vector2(ddx, ddz).length()
			if dl > 0.05:
				v.x = ddx / dl * 14.0
				v.z = ddz / dl * 14.0
				ang = atan2(ddx, ddz)
				face = Vector3(sin(ang), 0, cos(ang))
		if atk != null and String(atk["kind"]) == "fan":
			spin_a = 0.0
			fan_t -= dt
			fan_kick = maxf(0.0, fan_kick - dt * 7.0)
			if fan_left > 0 and t >= float(atk["w"]) and fan_t <= 0.0:
				fan_left -= 1
				fan_t = 0.13
				fan_kick = 1.0
				_fire_gun(false)
		elif atk != null and String(atk["kind"]) == "rifle":
			spin_a = 0.0
			if not hit_done and t >= float(atk["w"]):
				hit_done = true
				_fire_gun(true)
		elif atk != null and String(atk["kind"]) == "bash":
			spin_a = 0.0
			var bw: float = float(atk["w"])
			if t >= bw - 0.1 and t < bw + 0.3:
				v.x = face.x * 10.0
				v.z = face.z * 10.0
				bash_streak_t -= dt
				if bash_streak_t <= 0.0:
					bash_streak_t = 0.05
					game.vfx.streak(position + Vector3(0, 0.6, 0), atan2(face.x, face.z), Color(0.5, 0.75, 1.0))
			if not bash_fx_done and t >= bw:
				bash_fx_done = true
				_bash_hit()
		elif atk != null and String(atk["kind"]) == "sweep":
			spin_a = 0.0
			sweep_fx_t -= dt
			var sw: float = float(atk["w"])
			var sa: float = float(atk["a"])
			if t >= sw and t <= sw + sa:
				# Frame 2 trail: light-blue crescent like reference image.
				if sweep_fx_t <= 0.0:
					sweep_fx_t = 0.05
					game.vfx.flash(_sword_tip(), 0.45, Color(0.55, 0.85, 1.0))
				if not sweep_core_done and t >= sw + sa * 0.4:
					sweep_core_done = true
					game.vfx.flash(_sword_tip(), 0.8, Color(0.75, 0.93, 1.0))
					game.vfx.slash(position, ang, false, Color(0.55, 0.85, 1.0))
				_sweep_check()
		elif atk != null and String(atk["kind"]) == "counter":
			spin_a = 0.0
		else:
			if atk != null and String(atk["kind"]) == "spin":
				spin_a += dt * 18.0
			else:
				spin_a = 0.0
			if not hit_done and t >= float(atk["w"]):
				hit_done = true
				strike()
		if t > float(atk["w"]) + float(atk["a"]) and play and _has("D") and dash_cd <= 0.0:
			_eat("D")
			start_dash(Vector3(wx, 0, wz) if wl > 0.01 else face)
		elif t >= float(atk["w"]) + float(atk["a"]) + float(atk["r"]):
			st = "free"
			atk = null
	elif st == "dash":
		v = _dd * 18.0
		_tr -= dt
		if _tr <= 0.0:
			_tr = 0.04
			game.vfx.streak(position, atan2(_dd.x, _dd.z), body_col)
			game.vfx.emit(position + Vector3(0, 0.1, 0),
				Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)),
				Color(0.91, 0.89, 0.78), 0.1, 0.3, 6.0)
		if t > 0.17:
			st = "free"
			rec = 0.08
			v *= 0.3
	elif st == "ride":
		ride_tick = maxf(0.0, ride_tick - dt)
		var rd := face
		if foe != null and String(foe.st) != "ko":
			var dx: float = foe.position.x - position.x
			var dz: float = foe.position.z - position.z
			var dl := Vector2(dx, dz).length()
			if dl > 0.6:
				rd = Vector3(dx / dl, 0, dz / dl)
		var ta2 := atan2(rd.x, rd.z)
		var da2 := ta2 - ang
		da2 = atan2(sin(da2), cos(da2))
		ang += da2 * minf(1.0, 6.0 * dt)
		face = Vector3(sin(ang), 0, cos(ang))
		v.x = face.x * HORSE_SPEED
		v.z = face.z * HORSE_SPEED
		if int(t * 10.0) != int((t - dt) * 10.0):
			game.vfx.burst(position + Vector3(0, 0.1, 0), Color(0.75, 0.68, 0.55), 2, 1.5, 0.08, 0.3)
		if foe != null and String(foe.st) != "ko" and ride_tick <= 0.0:
			var hx: float = foe.position.x - position.x
			var hz: float = foe.position.z - position.z
			var hd := Vector2(hx, hz).length()
			if hd < 1.4:
				ride_tick = RIDE_TICK
				foe.hp = maxf(0.0, float(foe.hp) - RIDE_DMG)
				foe.dmg += RIDE_DMG
				var kl := RIDE_KB * 0.55 / float(foe.mass)
				var hv := Vector3(hx / maxf(hd, 0.01), 0, hz / maxf(hd, 0.01))
				foe.v = Vector3(hv.x * kl, 0, hv.z * kl)
				foe.vy = 4.0
				foe.st = "stun"
				foe.t = 0.0
				foe.stun = 0.3
				foe.flash = 0.14
				foe.atk = null
				var hp2: Vector3 = foe.position + Vector3(0, 0.9 + foe.position.y, 0)
				game.vfx.flash(hp2, 0.7, Color.WHITE)
				game.vfx.burst(hp2, body_col, 10, 5.0, 0.1, 0.4)
				game.audio.play("hitL")
		if t >= RIDE_TIME:
			_end_ride()
	elif st == "stun":
		var e3 := exp(-3.0 * dt)
		v.x *= e3
		v.z *= e3
		if t >= stun:
			st = "free"
	if ta != null:
		var da := float(ta) - ang
		da = atan2(sin(da), cos(da))
		ang += da * minf(1.0, 18.0 * dt)
		face = Vector3(sin(ang), 0, cos(ang))
	position.x += v.x * dt
	position.z += v.z * dt
	if position.y <= 0.0 and vy <= 0.0:
		position.y = 0.0
		vy = 0.0
	else:
		vy -= 30.0 * dt
		position.y += vy * dt
	if position.y < -6.0 or hp <= 0.0:
		game.ko(self)


func start_atk(kind: String) -> void:
	if kind == "L":
		atk = ATK_L.duplicate()
	elif kind == "H":
		atk = ATK_H.duplicate()
	elif kind == "S1":
		if _is_cowboy():
			atk = ATK_FAN.duplicate()
		elif _is_knight():
			atk = ATK_COUNTER.duplicate()
		else:
			atk = ATK_S1.duplicate()
	elif kind == "S2":
		if _is_cowboy():
			atk = ATK_RIFLE.duplicate()
		elif _is_knight():
			atk = ATK_BASH.duplicate()
		else:
			atk = ATK_S2.duplicate()
	else:
		if _is_cowboy():
			start_ride()
			return
		elif _is_knight():
			atk = ATK_SWEEP.duplicate()
		else:
			atk = ATK_S3.duplicate()
		kind = "S3"
	if atk.has("cd"):
		cd[kind] = float(atk["cd"])
	st = "atk"
	t = 0.0
	hit_done = false
	if String(atk["kind"]) == "fan":
		fan_left = 6
		fan_t = 0.0
	if String(atk["kind"]) == "counter":
		counter_done = false
		if shield_node != null:
			var sp: Vector3 = shield_node.global_transform.origin
			game.vfx.flash(sp, 0.7, Color(0.4, 0.7, 1.0))
			game.vfx.ring(Vector3(sp.x, 0, sp.z), Color(0.4, 0.7, 1.0), 0.3, 1.6, 0.3)
			game.audio.play("dash")
	if String(atk["kind"]) == "sweep":
		sweep_fx_t = 0.0
		sweep_core_done = false
	if String(atk["kind"]) == "bash":
		bash_fx_done = false
		bash_streak_t = 0.0
	if foe != null and String(foe.st) != "ko":
		var dx: float = foe.position.x - position.x
		var dz: float = foe.position.z - position.z
		if Vector2(dx, dz).length() < 5.0:
			ang = atan2(dx, dz)
	face = Vector3(sin(ang), 0, cos(ang))
	_maybe_start_custom()
	if kind == "S1":
		game.audio.play("dash")
	elif kind == "L":
		game.audio.play("light")
	else:
		game.audio.play("heavy")


func start_dash(d: Vector3) -> void:
	st = "dash"
	t = 0.0
	_dd = Vector3(d.x, 0, d.z)
	if _dd.length() < 0.01:
		_dd = face
	_dd = _dd.normalized()
	inv = 0.22
	dash_cd = 0.75
	_tr = 0.0
	game.audio.play("dash")
	game.vfx.burst(position + Vector3(0, 0.1, 0), Color(0.91, 0.89, 0.78), 6, 2.0, 0.1, 0.35, 0.3)


func start_ride() -> void:
	cd["S3"] = 8.0
	st = "ride"
	t = 0.0
	atk = null
	ride_tick = 0.0
	game.audio.play("dash")
	game.vfx.burst(position + Vector3(0, 0.2, 0), Color(0.8, 0.7, 0.55), 8, 3.0, 0.1, 0.4)


func _end_ride() -> void:
	st = "free"
	atk = null
	rec = 0.3
	v *= 0.3


func _fire_gun(big: bool) -> void:
	# Spawns a real travelling projectile at the barrel tip. No damage is
	# applied here: the bullet damages only on physical intersection.
	var root: Node3D = rifle_node if big else gun_node
	var mpos := global_transform.origin + face * 1.0 + Vector3(0, 0.8, 0)
	if root != null:
		var tip := root.get_node_or_null("Tip") as Node3D
		if tip != null:
			mpos = tip.global_transform.origin
	var spread := 0.0 if big else 0.07
	var dir := (face + Vector3(randf_range(-spread, spread), randf_range(-0.02, 0.03), randf_range(-spread, spread))).normalized()
	var col := Color(1.0, 0.85, 0.4)
	game.vfx.flash(mpos, 0.9 if big else 0.5, col)
	game.vfx.burst(mpos, col, 5 if big else 3, 2.5, 0.05, 0.2)
	if big:
		game.vfx.ring(Vector3(mpos.x, 0.05, mpos.z), col, 0.2, 1.6, 0.25)
		game.shake = maxf(game.shake, 0.25 * game.shake_amt)
		game.audio.play("boom")
	else:
		game.audio.play("shot")
	var src := ATK_RIFLE if big else ATK_FAN
	var cfg := {"speed": float(src["speed"]), "life": float(src["life"]),
		"dmg": float(src["dmg"]), "kb": float(src["kb"]), "vy": float(src["vy"]),
		"stun": 0.35 if big else 0.18, "big": big,
		"col": Color(1.0, 0.9, 0.55) if big else Color(1.0, 0.8, 0.35)}
	game.fire_bullet(self, mpos, dir, cfg)


func _do_counter(other) -> void:
	if counter_done:
		return
	counter_done = true
	other.hp = maxf(0.0, float(other.hp) - COUNTER_DMG)
	other.dmg += COUNTER_DMG
	var kk := COUNTER_KB * 0.55 / float(other.mass)
	var away: Vector3 = (other.position - position)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -face
	other.v = Vector3(away.x * kk, 0, away.z * kk)
	other.vy = 4.0
	other.st = "stun"
	other.t = 0.0
	other.stun = 0.35
	other.flash = 0.14
	other.atk = null
	var hitp: Vector3 = other.position + Vector3(0, 0.9, 0)
	game.vfx.flash(hitp, 1.2, Color(0.6, 0.85, 1.0))
	game.vfx.ring(position + Vector3(0, 0.7, 0), Color(0.4, 0.7, 1.0), 0.3, 3.0, 0.4)
	game.vfx.burst(hitp, Color(0.7, 0.9, 1.0), 14, 6.0, 0.09, 0.4)
	game.vfx.burst(position + face * 0.8 + Vector3(0, 0.7, 0), Color(0.5, 0.8, 1.0), 8, 4.0, 0.08, 0.35)
	game.audio.play("parry")
	game.shake = maxf(game.shake, 0.3 * game.shake_amt)


func _bash_hit() -> void:
	var tip := _shield_tip()
	game.vfx.burst(Vector3(tip.x, 0.15, tip.z), Color(0.7, 0.75, 0.8), 6, 2.0, 0.08, 0.3)
	if foe == null or String(foe.st) == "ko":
		return
	var chest: Vector3 = foe.position + Vector3(0, 0.9, 0)
	if tip.distance_to(chest) > 1.4:
		return
	var to: Vector3 = foe.position - position
	to.y = 0.0
	if to.length() > 0.05 and face.dot(to.normalized()) < 0.2:
		return
	if float(foe.inv) > 0.0:
		game.vfx.burst(chest, Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	foe.hp = maxf(0.0, float(foe.hp) - float(ATK_BASH["dmg"]))
	foe.dmg += float(ATK_BASH["dmg"])
	var kk := float(ATK_BASH["kb"]) * 0.55 / float(foe.mass)
	foe.v = Vector3(face.x * kk, 0, face.z * kk)
	foe.vy = float(ATK_BASH["vy"])
	foe.st = "stun"
	foe.t = 0.0
	foe.stun = 0.3
	foe.flash = 0.14
	foe.atk = null
	game.vfx.flash(chest, 0.9, Color(0.6, 0.8, 1.0))
	game.vfx.burst(chest, Color(0.55, 0.75, 1.0), 12, 5.0, 0.09, 0.4)
	game.vfx.ring(Vector3(tip.x, 0, tip.z), Color(0.5, 0.75, 1.0), 0.3, 2.6, 0.35)
	game.audio.play("bash")
	game.hs = maxf(game.hs, float(ATK_BASH["hs"]))
	game.shake = maxf(game.shake, float(ATK_BASH["sh"]) * game.shake_amt)
	game.damage_props(position, float(ATK_BASH["range"]) + 0.6, float(ATK_BASH["dmg"]))


func _sweep_check() -> void:
	if hit_done or foe == null or String(foe.st) == "ko":
		return
	var tp := _sword_tip()
	var chest: Vector3 = foe.position + Vector3(0, 0.9, 0)
	if tp.distance_to(chest) > 1.3:
		return
	var to: Vector3 = foe.position - position
	to.y = 0.0
	if to.length() > 0.05 and face.dot(to.normalized()) < -0.3:
		return
	hit_done = true
	if float(foe.inv) > 0.0:
		game.vfx.burst(chest, Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	foe.hp = maxf(0.0, float(foe.hp) - float(ATK_SWEEP["dmg"]))
	foe.dmg += float(ATK_SWEEP["dmg"])
	var kk := float(ATK_SWEEP["kb"]) * 0.55 / float(foe.mass)
	var flat := Vector3(to.x, 0, to.z)
	flat = flat.normalized() if flat.length() > 0.01 else face
	foe.v = Vector3(flat.x * kk, 0, flat.z * kk)
	foe.vy = float(ATK_SWEEP["vy"])
	foe.st = "stun"
	foe.t = 0.0
	foe.stun = 0.3
	foe.flash = 0.14
	foe.atk = null
	game.vfx.flash(chest, 0.9, Color(0.65, 0.85, 1.0))
	game.vfx.burst(chest, Color(0.55, 0.75, 1.0), 12, 6.0, 0.09, 0.4)
	game.vfx.slash(position, ang, false, Color(0.55, 0.85, 1.0))
	game.audio.play("hitH")
	game.hs = maxf(game.hs, float(ATK_SWEEP["hs"]))
	game.shake = maxf(game.shake, float(ATK_SWEEP["sh"]) * game.shake_amt)
	game.damage_props(position, 3.2, float(ATK_SWEEP["dmg"]))


func strike() -> void:
	var tk := ""
	if foe.atk != null:
		tk = String(foe.atk["kind"])
	if String(foe.st) == "atk" and tk == "counter" and foe.counter_open():
		foe._do_counter(self)
		return
	var heavy := bool(atk["big"])
	game.vfx.slash(position, ang, heavy, body_col)
	v += face * float(atk["lunge"])
	game.damage_props(position, float(atk["range"]) + 0.6, float(atk["dmg"]))
	if foe == null:
		return
	var dx: float = foe.position.x - position.x
	var dz: float = foe.position.z - position.z
	var d: float = Vector2(dx, dz).length()
	if String(foe.st) == "ko" or d > float(atk["range"]) + 0.45:
		return
	if not bool(atk["radial"]) and d > 0.01 and (dx * face.x + dz * face.z) / d < float(atk["arc"]):
		return
	if float(foe.inv) > 0.0:
		game.vfx.burst(foe.position + Vector3(0, 0.8, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	foe.hp = maxf(0.0, float(foe.hp) - float(atk["dmg"]))
	foe.dmg += float(atk["dmg"])
	var k := float(atk["kb"]) * 0.55 / float(foe.mass)
	foe.v = Vector3(dx / maxf(d, 0.01) * k, 0, dz / maxf(d, 0.01) * k)
	foe.vy = float(atk["vy"])
	foe.st = "stun"
	foe.t = 0.0
	foe.stun = minf(0.45, 0.12 + k * 0.02)
	foe.flash = 0.14
	foe.atk = null
	var hp_pos: Vector3 = foe.position + Vector3(0, 0.9 + foe.position.y, 0)
	game.vfx.flash(hp_pos, 0.9 if heavy else 0.55, Color.WHITE)
	game.vfx.burst(hp_pos, body_col, 16 if heavy else 7, 7.0 if heavy else 4.5, 0.1, 0.45)
	if heavy:
		game.vfx.ring(foe.position, body_col, 0.3, 3.4, 0.35)
		if int(game.quality) > 0:
			game.vfx.burst(hp_pos, Color.WHITE, 5, 5.0, 0.07, 0.3)
	game.hs = maxf(game.hs, float(atk["hs"]))
	game.shake = maxf(game.shake, float(atk["sh"]) * game.shake_amt)
	if heavy:
		game.audio.play("hitH")
	else:
		game.audio.play("hitL")


func anim(dt: float, tnow: float) -> void:
	var sp := Vector2(v.x, v.z).length()
	ph += dt * sp * 2.4
	var w := minf(1.0, sp / 4.5)
	var la := sin(ph) * 0.9 * w
	var lean := 0.0
	var sq := 1.0
	var tw := sin(ph) * 0.08 * w
	var twist := 0.0
	if sword_node != null:
		sword_node.rotation = Vector3.ZERO
	if shield_node != null:
		shield_node.position = SHIELD_REST
	if st == "free" and sp < 0.5:
		sq = 1.0 + sin(tnow * 3.0 + float(idx)) * 0.015
	var E := [0.0, 0.0]
	var U := [0.0, 0.0]
	if st == "atk" and atk != null:
		var kind := String(atk["kind"])
		var W: float = float(atk["w"])
		var A: float = float(atk["a"])
		var R: float = float(atk["r"])
		var u := t
		if kind == "dash":
			lean = 0.8
			sq = 1.08
			E[0] = 1.2
			E[1] = 1.2
			U[0] = 0.0
			U[1] = 0.0
		elif kind == "upper":
			if u < W:
				var e := u / maxf(W, 0.001)
				lean = -0.35 * e
				sq = 1.0 - 0.18 * e
				E[0] = -0.4 * e
				E[1] = -0.4 * e
			elif u < W + A:
				lean = -0.55
				sq = 1.12
				E[0] = 0.5
				E[1] = 0.5
				U[0] = 1.2
				U[1] = 1.2
			else:
				var e4u := (u - W - A) / maxf(R, 0.001)
				lean = 0.2 * (1.0 - e4u)
				sq = 1.0
				E[0] = 0.6 * (1.0 - e4u)
				E[1] = 0.6 * (1.0 - e4u)
				U[0] = 0.4 * (1.0 - e4u)
				U[1] = 0.4 * (1.0 - e4u)
		elif kind == "spin":
			lean = 0.15
			sq = 1.0
			E[0] = 1.0
			E[1] = 1.0
			U[0] = 0.1
			U[1] = 0.1
		elif kind == "fan":
			# 1 AIM raise, 2 FIRE kicks, 3 RECOVER lowers
			var aim_u := clampf(t / 0.25, 0.0, 1.0)
			var rec_u := clampf((t - 0.9) / 0.5, 0.0, 1.0)
			var raise := aim_u * (1.0 - rec_u)
			lean = 0.1 + fan_kick * 0.12 - rec_u * 0.05
			sq = 1.0
			E[0] = 0.2 + 0.3 * raise
			E[1] = 0.3 + 0.9 * raise + fan_kick * 0.1
			U[0] = 0.1 + 0.1 * raise
			U[1] = 0.1 + 0.25 * raise
		elif kind == "rifle":
			# 1 AIM, 2 FIRE, 3 RECOIL kick-up, 4 RESET ease back
			var a_u := clampf(t / 0.35, 0.0, 1.0)
			var rk := 0.0
			if t >= 0.35:
				rk = sin(clampf((t - 0.35) / 0.65, 0.0, 1.0) * PI)
			lean = 0.15 - rk * 0.35
			sq = 1.0
			E[0] = 0.3 + 0.4 * a_u + rk * 0.1
			E[1] = 0.4 + 0.8 * a_u + rk * 0.15
			U[0] = 0.15 + 0.1 * a_u + rk * 0.15
			U[1] = 0.2 + 0.2 * a_u + rk * 0.25
		elif kind == "counter":
			var brace := clampf(t / 0.2, 0.0, 1.0) * (1.0 - clampf((t - 0.7) / 0.4, 0.0, 1.0))
			lean = -0.12 * brace
			sq = 1.0 - 0.08 * brace
			E[0] = 0.2 + 0.8 * brace
			E[1] = 0.2
			U[0] = 0.3 + 0.3 * brace
			U[1] = 0.1
			if shield_node != null:
				shield_node.position = SHIELD_REST + Vector3(0, brace * 0.1, brace * 0.25)
		elif kind == "bash":
			var wu := clampf(t / 0.3, 0.0, 1.0)
			var im := 0.0
			if t >= 0.3:
				im = sin(clampf((t - 0.3) / 0.65, 0.0, 1.0) * PI)
			lean = -0.2 + wu * 0.2 + im * 0.5
			sq = 1.0 - 0.05 * (1.0 - wu) + im * 0.05
			E[0] = 0.2 + 0.3 * wu + 0.8 * im
			E[1] = 0.2
			U[0] = 0.2 + 0.3 * im
			U[1] = 0.1
			if shield_node != null:
				shield_node.position = SHIELD_REST + Vector3(0, im * 0.05, 0.1 * wu + 0.3 * im)
		elif kind == "sweep":
			# Reference Image 1 - 3-frame sword slash:
			# Pose 1 (windup, t<W): sword low right, arm down.
			# Pose 2 (active, W<=t<W+A): sword raised up-left + blue crescent trail.
			# Pose 3 (recover, t>=W+A): sword back low right.
			var wsa: float = float(atk["w"])
			var saa: float = float(atk["a"])
			var sra: float = float(atk["r"])
			var sw := -1.3
			var lift := 0.25 # sword pitch: + = low, - = raised
			if t < wsa:
				var wu := clampf(t / maxf(wsa, 0.001), 0.0, 1.0)
				sw = -1.3
				lift = lerpf(0.25, 0.35, wu)
				lean = -0.08 * wu
				sq = 1.0 - 0.05 * wu
				E[0] = 0.2
				E[1] = lerpf(0.2, 0.4, wu)
				U[0] = 0.15
				U[1] = lerpf(0.1, 0.2, wu)
				twist = sw * 0.22
			elif t < wsa + saa:
				var eu := clampf((t - wsa) / maxf(saa, 0.001), 0.0, 1.0)
				var e2 := eu * eu * (3.0 - 2.0 * eu)
				sw = lerpf(-1.3, 1.3, e2)
				# Raise blade mid-swing like frame 2 (up), settle at end.
				lift = lerpf(0.35, -0.55, sin(eu * PI))
				lean = 0.2 + 0.1 * sin(eu * PI)
				sq = 1.0 + 0.04 * sin(eu * PI)
				E[0] = 0.2
				E[1] = 0.4 + 0.9 * minf(eu * 1.2, 1.0)
				U[0] = 0.15
				U[1] = 0.2 + 0.35 * sin(eu * PI)
				twist = sw * 0.22
			else:
				var ru := clampf((t - wsa - saa) / maxf(sra, 0.001), 0.0, 1.0)
				sw = lerpf(1.3, -0.6, ru * ru * (3.0 - 2.0 * ru) * 0.5)
				lift = lerpf(-0.2, 0.25, ru)
				lean = lerpf(0.2, 0.0, ru)
				sq = 1.0
				E[0] = 0.2
				E[1] = lerpf(1.3, 0.2, ru)
				U[0] = 0.15
				U[1] = lerpf(0.4, 0.1, ru)
				twist = sw * 0.22
			if sword_node != null:
				# Upright blade: lateral tilt reads as a side slash
				# (Y would just spin it around its own long axis).
				sword_node.rotation.z = sw
				sword_node.rotation.x = lift
		else:
			var hv: bool = bool(atk["big"])
			var rc := 1.7 if hv else 1.4
			var hu := 0.9 if hv else 0.25
			var ex := 0.0
			var uy := 0.0
			if u < W:
				var e := u / W
				ex = -0.5 * e
				uy = hu * e
				lean = -0.25 * e
			elif u < W + A:
				var e2 := (u - W) / A
				ex = -0.5 + (rc + 0.5) * e2
				uy = hu * (1.0 - e2)
				lean = 0.45
			else:
				var e3 := (u - W - A) / maxf(R, 0.001)
				ex = rc * (1.0 - e3 * 0.9)
				uy = 0.0
				lean = 0.3
			E[1] = ex
			U[1] = uy
			if hv:
				E[0] = ex
				U[0] = uy
			else:
				E[0] = -0.25
			if _is_knight() and sword_node != null:
				var total := maxf(W + A + R, 0.001)
				var chop := 0.0
				if u < W:
					chop = -0.45 * (u / maxf(W, 0.001))
				elif u < W + A:
					chop = lerpf(-0.45, 0.65, (u - W) / maxf(A, 0.001))
				else:
					chop = lerpf(0.65, 0.0, (u - W - A) / maxf(R, 0.001))
				sword_node.rotation.x = chop
	elif st == "stun":
		lean = -0.5
		tw = sin(tnow * 40.0) * 0.06
		sq = 0.95
		E[0] = -0.3
		E[1] = -0.3
		U[0] = 0.35
		U[1] = 0.35
	elif st == "dash":
		lean = 0.7
		sq = 0.9
		E[0] = -0.5
		E[1] = -0.5
	elif st == "ride":
		# 5-frame gallop: extend -> mid-air -> land -> compress -> return
		var g := _gallop(fmod(t, GALLOP_T) / GALLOP_T)
		lean = 0.3 + g.x * 0.4
		sq = 1.0
		E[0] = 0.8
		E[1] = 0.8
		U[0] = 0.3 + g.y * 0.8
		U[1] = 0.3 + g.y * 0.8
		tw = sin(tnow * 12.0) * 0.05
		if horse_root != null:
			horse_root.rotation.x = g.x
			horse_root.position.y = g.y
			horse_root.scale = Vector3(1.0 / sqrt(maxf(g.z, 0.05)), g.z, 1.0 + (1.0 - g.z) * 0.6)
	# Attack Animator overrides (menu editor, additive deltas).
	var _ov := {}
	var _ov_arm := 0.0
	var _ov_srx := 0.0
	var _ov_sry := 0.0
	var _ov_ss := 0.0
	var _ov_shx := 0.0
	var _ov_shy := 0.0
	var _ov_shz := 0.0
	var _ov_shs := 0.0
	if st == "atk" and atk != null:
		var _kind2 := String(atk["kind"])
		var _W2: float = float(atk.get("w", 0.3))
		var _A2: float = float(atk.get("a", 0.3))
		var _ph := 0
		if t >= _W2 + _A2:
			_ph = 2
		elif t >= _W2:
			_ph = 1
		_ov = get_anim_ov(skin_name, _kind2, _ph)
		if not _ov.is_empty():
			lean += float(_ov.get("lean", 0.0))
			sq += float(_ov.get("sq", 0.0))
			twist += float(_ov.get("twist", 0.0))
			E[0] = float(E[0]) + float(_ov.get("e0", 0.0))
			E[1] = float(E[1]) + float(_ov.get("e1", 0.0))
			U[0] = float(U[0]) + float(_ov.get("u0", 0.0))
			U[1] = float(U[1]) + float(_ov.get("u1", 0.0))
			_ov_arm = float(_ov.get("arm_scale", 0.0))
			_ov_srx = float(_ov.get("sword_rx", 0.0))
			_ov_sry = float(_ov.get("sword_ry", 0.0))
			_ov_ss = float(_ov.get("sword_s", 0.0))
			_ov_shx = float(_ov.get("shield_x", 0.0))
			_ov_shy = float(_ov.get("shield_y", 0.0))
			_ov_shz = float(_ov.get("shield_z", 0.0))
			_ov_shs = float(_ov.get("shield_s", 0.0))
	for k in 2:
		var s := 1.0 if k == 1 else -1.0
		var arm: Node3D = arm_r if k == 1 else arm_l
		var x := clampf(float(E[k]), 0.0, 1.0)
		var sw := (la if k == 1 else -la) * 0.35
		var hv2 := atk != null and bool(atk["big"])
		arm.position = Vector3(s * (0.62 - 0.3 * x),
			0.55 + float(U[k]) + (0.2 * x if st == "atk" else 0.0) + (RIDE_LIFT if st == "ride" else 0.0),
			float(E[k]) + sw)
		arm.scale = Vector3.ONE * (1.0 + 0.45 * x * (1.0 if hv2 else 0.4)) * (1.0 + _ov_arm)
	model.rotation.x = lean
	model.rotation.z = tw
	if st == "atk" and atk != null and String(atk["kind"]) == "spin":
		model.rotation.y = spin_a + twist
	else:
		model.rotation.y = twist
	model.scale = Vector3(1.0 / sqrt(maxf(sq, 0.05)), maxf(sq, 0.05), 1.0 / sqrt(maxf(sq, 0.05)))
	if sword_node != null and (_ov_srx != 0.0 or _ov_sry != 0.0 or _ov_ss != 0.0):
		sword_node.rotation.x += _ov_srx
		sword_node.rotation.y += _ov_sry
		sword_node.scale *= (1.0 + _ov_ss)
	if shield_node != null and (_ov_shx != 0.0 or _ov_shy != 0.0 or _ov_shz != 0.0 or _ov_shs != 0.0):
		shield_node.position += Vector3(_ov_shx, _ov_shy, _ov_shz)
		shield_node.scale *= (1.0 + _ov_shs)
	_apply_custom_clip()
	model.position.y = absf(sin(ph)) * 0.06 * w
	if skin_inst != null and is_instance_valid(skin_inst):
		var lift := 0.0
		if st == "ride":
			lift = RIDE_LIFT - _gallop(fmod(t, GALLOP_T) / GALLOP_T).y * 0.4
		skin_inst.position.y = skin_base_y + lift
	if gun_node != null:
		var firing := st == "atk" and atk != null and String(atk["kind"]) == "fan"
		gun_node.visible = firing
		if firing:
			var rec_u := clampf((t - 0.9) / 0.5, 0.0, 1.0)
			gun_node.rotation.x = -fan_kick * 0.35 - rec_u * 0.25
		else:
			gun_node.rotation.x = 0.0
	if rifle_node != null:
		var aiming := st == "atk" and atk != null and String(atk["kind"]) == "rifle"
		rifle_node.visible = aiming
		if aiming and t >= 0.35:
			rifle_node.rotation.x = -sin(clampf((t - 0.35) / 0.65, 0.0, 1.0) * PI) * 0.55
		else:
			rifle_node.rotation.x = 0.0
	if horse_root != null:
		horse_root.visible = st == "ride"
	rotation.y = ang
	var e4 := 0.8 if flash > 0.0 else 0.05
	for m in mats:
		(m as StandardMaterial3D).emission = Color(e4, e4, e4)
