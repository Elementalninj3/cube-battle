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

const JUMP_V := 11.0
const JUMP_MAX_AIR := 1 # single jump for all characters
var grounded := true
var air_jumps := 0
var idx := 0
var game = null
var foe = null
var keys := {"up": [], "down": [], "left": [], "right": [], "L": [], "H": [], "D": [],
	"S1": [], "S2": [], "S3": [], "JUMP": []}

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
# Ninja kit: faithful 1:1 port of html/ninjasetup.html ("Shadow Block").
# Mapping to this game's slots: D = shadow dash (HTML J), S3 = smoke bomb
# (HTML K), S2 = kunai throw (HTML L), S1 = katana slash (HTML G).
# NOTE: the HTML G is a SINGLE slash (T=0.55, rel=0.14, trail 0.1-0.34),
# not a 3-hit combo; no combo timings exist in the source to port.
# HTML numbers: SPEED 5, DASH 22/0.2/0.7, KUNAI 22/cd 0.25, SMOKE cd 4,
# CLOUD r 3.8/life 5.5/tick 0.5/dmg 12, SLASH dmg 35/cd 0.6/range 2.6.
const NINJA_SPEED := 5.0
const NINJA_DASH_SPEED := 22.0
const NINJA_DASH_TIME := 0.2
const NINJA_DASH_CD := 0.7
# Shadow dash strike: dashing through the foe deals light damage once per
# dash (with the usual stun/knockback, no hitstop). Dashing into a knight's
# open counter is punished like any other melee hit.
const NINJA_DASH_DMG := 8.0
const NINJA_DASH_KB := 6.0
const NINJA_DASH_RANGE := 1.1
# Kunai flight speed: HTML reference is 22 u/s, but at 1v1 ranges (4-9 m)
# that crosses in ~0.25 s and reads as instant. Deliberately reduced to a
# still-fast value so travel, spin and trail stay visible. Cooldown stays 0.25.
const NINJA_KUNAI_REF_SPEED := 22.0
const NINJA_KUNAI_SPEED := 16.0
const NINJA_KUNAI_CD := 0.25
const NINJA_KUNAI_THROWN_SCALE := 1.4
const NINJA_KUNAI_HELD_SCALE := 0.65
const NINJA_SMOKE_CD := 4.0
# M1 katana string (durations / damage / release / wind-up / windows /
# lunges / ranges / continuation 0.4 s / finisher cd 0.4 s as specified).
const NINJA_SLASH1 := {"w": 0.10, "a": 0.24, "r": 0.16, "dmg": 7.0, "kb": 6.0, "range": 2.6, "arc": 0.3, "lunge": 3.0, "lunge0": 0.08, "lunge1": 0.30, "sh": 0.2, "hs": 0.05, "vy": 0.0, "kind": "slash1", "big": false, "radial": false, "cd": 0.0}
const NINJA_SLASH2 := {"w": 0.06, "a": 0.26, "r": 0.18, "dmg": 7.0, "kb": 6.5, "range": 2.8, "arc": 0.3, "lunge": 3.5, "lunge0": 0.06, "lunge1": 0.28, "sh": 0.22, "hs": 0.05, "vy": 0.0, "kind": "slash2", "big": false, "radial": false, "cd": 0.0}
const NINJA_SLASH3 := {"w": 0.38, "a": 0.10, "r": 0.30, "dmg": 13.0, "kb": 9.0, "range": 3.2, "arc": 0.0, "lunge": 6.0, "lunge0": 0.28, "lunge1": 0.40, "sh": 0.35, "hs": 0.09, "vy": 4.0, "kind": "slash3", "big": true, "radial": true, "cd": 0.0}
const NINJA_COMBO_WINDOW := 0.4
const NINJA_FINISH_CD := 0.4
const ATK_KUNAI := {"w": 0.11, "a": 0.05, "r": 0.18, "dmg": 0.0, "kb": 0.0, "speed": NINJA_KUNAI_SPEED, "life": 2.0, "lunge": 0.0, "sh": 0.05, "hs": 0.0, "vy": 0.0, "kind": "kunai", "big": false, "radial": false, "cd": 0.25}
# HTML POSE table (hand wind-up/release/return targets). A/B = throwing-hand
# wind-up/release poses, off = off-hand pose. Mirrors ninjasetup.html.
const NJ_POSE_KUNAI := {"T": 0.34, "rel": 0.11, "wind": 0.07, "A": [0.85, 0.45, -0.5], "B": [0.3, 0.15, 1.05], "off": [0.7, -0.05, -0.25]}
const NJ_POSE_SMOKE := {"T": 0.55, "rel": 0.27, "wind": 0.17, "A": [0.7, 0.8, -0.35], "B": [0.28, 0.3, 1.0], "off": [0.9, 0.35, 0.35]}
const NJ_POSE_SLASH := {"T": 0.55, "rel": 0.14, "wind": 0.1, "A": [0.7, 0.0, 0.0], "B": [0.7, 0.0, 0.0], "off": [0.7, 0.0, 0.0]}
# Sticky-kunai detonation (mirrors html/ninjasetup.html fuse/chain logic).
# NOTE: the reference kills outright on detonation; here the blast deals
# heavy AoE instead so 1v1 rounds stay winnable from any state.
const STICK_FUSE := 0.9
const CHAIN_FUSE := 0.5
const BLAST_R := 2.6
const BLAST_DMG := 16.0
const ATK_SMOKE := {"w": 0.27, "a": 0.05, "r": 0.23, "dmg": 0.0, "kb": 0.0, "range": 2.0, "arc": 0.0, "lunge": 0.0, "sh": 0.15, "hs": 0.0, "vy": 0.0, "kind": "smoke", "big": false, "radial": false, "cd": 4.0}
const NINJA_CLOUD_R := 3.8
const NINJA_CLOUD_LIFE := 5.5
const NINJA_CLOUD_TICK := 0.5
const NINJA_CLOUD_DMG := 3.0
const KUNAI_REST := Vector3(0.05, 0.05, 0.2)
const COUNTER_DMG := 14.0
const COUNTER_KB := 9.0
const SHIELD_REST := Vector3(-0.05, 0.05, 0.22)
static var _prop_scenes := {}


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
var katana_node: Node3D = null
var kunai_node: Node3D = null
var kunai_node_r: Node3D = null
var kunai_hand := true # toggled at throw start (HTML nextHand^=1); first throw = left, like the reference
var bomb_node: Node3D = null # held smoke bomb prop (procedural sphere)
var nj_move := 0.0 # HTML moveAmt: walk-cycle blend for the hands
var nj_dash := 0.0 # HTML dashAmt: dash-pose blend for the hands
var nj_twist := 0.0 # HTML body twist driven by the hand driver
var nj_lean := 0.0 # HTML body lean driven by the hand driver
var nj_stretch := false # dash body stretch (HTML player.scale 0.8,0.8,1.5)
var combo_stage := 0 # M1 katana string stage (0 = idle, 1/2/3 = last hit)
var combo_expire := -9.0 # end of the 0.4 s continuation window
var _nj_arms := false # hand driver wrote the arms this frame; skip generic
var stuck: Array = [] # live sticky kunai bombs {fuse, t, node}
var armed_snap: Array = [] # [mat, albedo, emission] saved while fuse-blinking
var ghost_t := 0.0
var slash_fx_done := false

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
var buf := {"L": -9.0, "H": -9.0, "D": -9.0, "S1": -9.0, "S2": -9.0, "S3": -9.0, "JUMP": -9.0}
var cd := {"S1": 0.0, "S2": 0.0, "S3": 0.0}
var cd_max := {"S1": 4.0, "S2": 6.0, "S3": 8.0}
var spin_a := 0.0
var _dd := Vector3.ZERO
var _tr := 0.0
var dash_hit_done := false
# Half-extent of the square the fighter is clamped to. Arena default 4.7;
# open-world mode raises it (fighter physics otherwise assume flat ground).
var bounds := 4.7
# --- AI input hooks (bb_ai.gd drives these; same rules as human input) ---
# When ai_enabled, movement comes from ai_ix/ai_iy (analog -1..1) instead of
# the keyboard, and attacks are queued via ai_press() into the same buf
# buffer that _input() uses, so cooldowns/recovery/whiffs apply identically.
var ai_enabled := false
var ai_ix := 0.0
var ai_iy := 0.0

var model: Node3D
var head_mi: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var hat_root: Node3D
var mats: Array = []
var _box: BoxMesh
var _flash_on := false # tracks whether the hit-flash emission is applied


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	# Crash fix: null base material derefs in GLES3 on old Intel drivers.
	var _fb := StandardMaterial3D.new()
	_fb.roughness = 0.55
	_box.material = _fb
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
	if _is_ninja():
		cd_max = {"S1": NINJA_FINISH_CD, "S2": NINJA_KUNAI_CD, "S3": NINJA_SMOKE_CD}
	else:
		cd_max = {"S1": 4.0, "S2": 6.0, "S3": 8.0}
	rebuild()


func _skin_color(sname: String) -> Color:
	match sname:
		"cubecowboy":
			return Color(0.86, 0.22, 0.16)
		"cubeknight":
			return Color(0.55, 0.62, 0.72)
		"ninja":
			return Color(0.2, 0.2, 0.28)
		_:
			return Color(0.23, 0.51, 0.96)


func _is_cowboy() -> bool:
	return skin_name == "cubecowboy"


func _is_knight() -> bool:
	return skin_name == "cubeknight"


func _is_ninja() -> bool:
	return skin_name == "ninja"


func top_y() -> float:
	return 3.0 if st == "ride" else 1.9


func counter_open() -> bool:
	return st == "atk" and atk != null and String(atk["kind"]) == "counter" and not counter_done and t >= float(atk["w"]) and t <= float(atk["w"]) + float(atk["a"])


func reset_match(pos: Vector3, p_ang: float) -> void:
	position = pos
	v = Vector3.ZERO
	ai_ix = 0.0
	ai_iy = 0.0
	for key in buf:
		buf[key] = -9.0
	clear_stuck()
	kunai_hand = true
	ghost_t = 0.0
	slash_fx_done = false
	nj_move = 0.0
	nj_dash = 0.0
	nj_twist = 0.0
	nj_lean = 0.0
	nj_stretch = false
	combo_stage = 0
	combo_expire = -9.0
	vy = 0.0
	grounded = true
	air_jumps = 0
	ang = p_ang
	face = Vector3(sin(ang), 0, cos(ang))
	hp = 100.0
	dmg = 0.0
	st = "free"
	t = 0.0
	atk = null
	dash_hit_done = false
	dash_cd = 0.0
	inv = 0.0
	flash = 0.0
	rec = 0.0
	spin_a = 0.0
	for key in cd:
		cd[key] = 0.0
	visible = true
	_flash_on = false
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
	katana_node = null
	kunai_node = null
	kunai_node_r = null
	bomb_node = null
	stuck.clear()
	armed_snap.clear()
	if _build_skin():
		head_mi = null
		if _is_cowboy():
			_build_cowboy_gear()
		elif _is_knight():
			_build_knight_gear()
		elif _is_ninja():
			_build_ninja_gear()
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
			elif sm == null:
				# Crash fix: GLB surfaces with null material deref in the
				# GLES3 shadow pass on old Intel drivers. Give them a solid
				# fallback in the body color so they render instead of crash.
				var fb := StandardMaterial3D.new()
				fb.albedo_color = body_col
				fb.roughness = 0.55
				fb.emission_enabled = true
				fb.emission = Color(0.05, 0.05, 0.05)
				mi.set_surface_override_material(s, fb)
				mats.append(fb)
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


static var _prop_fallback: StandardMaterial3D = null


func _prop_instance(pname: String) -> Node3D:
	if not _prop_scenes.has(pname):
		var packed := load(PROPS_DIR + "/" + pname + ".glb") as PackedScene
		if packed == null:
			return null
		_prop_scenes[pname] = packed
	var inst := (_prop_scenes[pname] as PackedScene).instantiate() as Node3D
	_sweep_prop_materials(inst)
	return inst


func _sweep_prop_materials(n: Node) -> void:
	# Crash fix: prop GLBs may carry null-material surfaces, which deref in
	# the GLES3 shadow pass on old Intel drivers. Patch per-instance
	# overrides (shared mesh resources stay untouched).
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				if mi.mesh.surface_get_material(s) == null and mi.get_surface_override_material(s) == null:
					if _prop_fallback == null:
						_prop_fallback = StandardMaterial3D.new()
						_prop_fallback.albedo_color = Color(0.45, 0.42, 0.4)
						_prop_fallback.roughness = 0.6
					mi.set_surface_override_material(s, _prop_fallback)
	for c in n.get_children():
		_sweep_prop_materials(c)


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


static func _octa_mesh(r: float) -> ArrayMesh:
	# Small octahedron for the katana handle decorations (HTML OctahedronGeometry).
	var v := [Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(r, 0, 0),
		Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
	var tris := [[0, 4, 2], [0, 2, 5], [0, 5, 3], [0, 3, 4],
		[1, 2, 4], [1, 5, 2], [1, 3, 5], [1, 4, 3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tr in tris:
		for vi in tr:
			st.add_vertex(v[int(vi)])
	st.generate_normals()
	return st.commit()


static func _pmat(col: Color, metal: float, rough: float, emis: Color = Color(0, 0, 0), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = energy
	return m


# Procedural katana from HTML makeSword(): curved dark blade (parabola
# c(x) = 0.16*(x/L)^2, L = 1.4) with a narrow green strip, layered
# dark/green guard discs, dark handle with 24 green octahedra, dark+green
# pommel. Blade runs along +Z from the guard; the pivot IS this node.
static func make_katana_node() -> Node3D:
	var root := Node3D.new()
	root.name = "Katana"
	var dark := _pmat(Color(0.19, 0.20, 0.23), 0.5, 0.45)
	var green := _pmat(Color(0.56, 0.88, 0.23), 0.0, 0.4, Color(0.29, 0.63, 0.06), 0.8)
	var hdark := _pmat(Color(0.10, 0.11, 0.13), 0.0, 0.6)
	var blade := Node3D.new()
	blade.name = "Blade"
	root.add_child(blade)
	var detail := Node3D.new()
	detail.name = "GreenBladeDetail"
	root.add_child(detail)
	var L := 1.4
	var segs := 4
	for si in segs:
		var x0 := L * float(si) / float(segs)
		var x1 := L * float(si + 1) / float(segs)
		var xm := (x0 + x1) * 0.5
		var slope := 0.32 * xm / (L * L)
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.095 * (1.0 - 0.35 * xm / L), 0.03, (x1 - x0) * 1.02)
		seg.mesh = bm
		seg.material_override = dark
		seg.position = Vector3(0, 0.16 * xm * xm / (L * L), 0.21 + xm)
		seg.rotation.x = -atan(slope)
		blade.add_child(seg)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.03, 0.036, (x1 - x0) * 1.02)
		strip.mesh = sm
		strip.material_override = green
		strip.position = Vector3(0.035, 0.16 * xm * xm / (L * L) + 0.012, 0.21 + xm)
		strip.rotation.x = -atan(slope)
		detail.add_child(strip)
	var guard := Node3D.new()
	guard.name = "Guard"
	root.add_child(guard)
	var gr := [0.125, 0.09, 0.07]
	var gh := [0.035, 0.04, 0.046]
	for gi in 3:
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = gr[gi]
		cm.bottom_radius = gr[gi]
		cm.height = gh[gi]
		cm.radial_segments = 16
		disc.mesh = cm
		disc.material_override = hdark if gi != 1 else green
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(0, 0, 0.19)
		guard.add_child(disc)
	var handle := Node3D.new()
	handle.name = "Handle"
	root.add_child(handle)
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.042
	gm.bottom_radius = 0.042
	gm.height = 0.34
	gm.radial_segments = 10
	grip.mesh = gm
	grip.material_override = hdark
	grip.rotation.x = PI * 0.5
	handle.add_child(grip)
	var deco := Node3D.new()
	deco.name = "HandleDecorations"
	root.add_child(deco)
	var om := _octa_mesh(0.032)
	var sides := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)]
	for fi in 4:
		for oi in 6:
			var d := MeshInstance3D.new()
			d.mesh = om
			d.material_override = green
			var f: Vector3 = sides[fi]
			d.position = Vector3(f.x * 0.044, f.y * 0.044, -0.14 + float(oi) * 0.056 + float(fi % 2) * 0.028)
			deco.add_child(d)
	var pommel := Node3D.new()
	pommel.name = "Pommel"
	root.add_child(pommel)
	var pd := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.056
	pm.bottom_radius = 0.056
	pm.height = 0.05
	pm.radial_segments = 10
	pd.mesh = pm
	pd.material_override = hdark
	pd.rotation.x = PI * 0.5
	pd.position = Vector3(0, 0, -0.2)
	pommel.add_child(pd)
	var pg := MeshInstance3D.new()
	var qm := CylinderMesh.new()
	qm.top_radius = 0.036
	qm.bottom_radius = 0.036
	qm.height = 0.056
	qm.radial_segments = 10
	pg.mesh = qm
	pg.material_override = green
	pg.rotation.x = PI * 0.5
	pg.position = Vector3(0, 0, -0.2)
	pommel.add_child(pg)
	return root


# Procedural kunai: faithful 1:1 port of html/ninjasetup.html makeKunai().
# HTML source (lines 306-336):
#   kBladeGeo  = ConeGeometry(0.1, 0.45, 4, 1) -> rotateX(PI/2),
#                scale(1, 0.25, 1), translate(0, 0, -0.225)
#   kGuardGeo  = BoxGeometry(0.17, 0.05, 0.05) -> translate(0, 0, -0.46)
#   kHandleGeo = CylinderGeometry(0.035, 0.035, 0.28, 8) -> rotateX(PI/2),
#                translate(0, 0, -0.62)
#   kRingGeo   = TorusGeometry(0.075, 0.02, 6, 14) -> rotateX(PI/2),
#                translate(0, 0, -0.83)
#   kBladeMat  = Standard(color 0xd5deee, metalness 0.85, roughness 0.28,
#                emissive 0x2a3a58, intensity 0.6)
#   kDarkMat   = Standard(color 0x1b1e2c, roughness 0.7)
# Origin at the TIP, tip faces +Z (blade body extends toward -Z).
# Total length ~0.93 (tip 0 -> ring outer -0.925). Spacing/gaps match the
# source: guard spans -0.435..-0.485, grip spans -0.48..-0.76,
# ring centered -0.83.
# One design feeds held props (NINJA_KUNAI_HELD_SCALE) and flying
# projectiles (NINJA_KUNAI_THROWN_SCALE, spun around local Z in flight).
static func make_kunai_node() -> Node3D:
	var root := Node3D.new()
	root.name = "Kunai"
	var blade_mat := _pmat(Color(0.84, 0.87, 0.93), 0.85, 0.28, Color(0.16, 0.23, 0.35), 0.6)
	var dark_mat := _pmat(Color(0.11, 0.12, 0.17), 0.0, 0.7)
	# Blade: 4-sided cone (diamond cross-section), tip (radius 0) at +Y,
	# base (radius 0.1) at -Y. rotateX(PI/2) lays the axis along Z with the
	# tip toward +Z; node scale (1, 1, 0.25) flattens the local Z, which the
	# X-rotation turns into world -Y, reproducing the HTML scale(1,0.25,1)
	# vertical flatten. Positioned so the tip sits exactly at the origin.
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.1
	cm.height = 0.45
	cm.radial_segments = 4
	blade.mesh = cm
	blade.material_override = blade_mat
	blade.rotation.x = PI * 0.5
	blade.scale = Vector3(1, 1, 0.25)
	blade.position = Vector3(0, 0, -0.225)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(blade)
	# Guard: wide thin box across X, exactly as the source.
	var guard := MeshInstance3D.new()
	guard.name = "Guard"
	var gb := BoxMesh.new()
	gb.size = Vector3(0.17, 0.05, 0.05)
	guard.mesh = gb
	guard.material_override = dark_mat
	guard.position = Vector3(0, 0, -0.46)
	guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(guard)
	# Handle: grip cylinder along Z, 8 radial segments like the source.
	var grip := MeshInstance3D.new()
	grip.name = "Handle"
	var gm := CylinderMesh.new()
	gm.top_radius = 0.035
	gm.bottom_radius = 0.035
	gm.height = 0.28
	gm.radial_segments = 8
	grip.mesh = gm
	grip.material_override = dark_mat
	grip.rotation.x = PI * 0.5
	grip.position = Vector3(0, 0, -0.62)
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(grip)
	# Ring: torus radius 0.075, tube 0.02 (outer 0.095, inner 0.055),
	# 6 x 14 segments like TorusGeometry(0.075, 0.02, 6, 14).
	# Godot TorusMesh already lies flat in XZ (hole along Y), which is
	# exactly the HTML TorusGeometry after its rotateX(PI/2), so no extra
	# rotation is applied here.
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.055
	tm.outer_radius = 0.095
	tm.rings = 14
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = blade_mat
	ring.position = Vector3(0, 0, -0.83)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(ring)
	return root


func _build_ninja_gear() -> void:
	# Procedural katana in the right fist (visible only while slashing);
	# one held procedural kunai per fist, throws alternate like the source.
	katana_node = make_katana_node()
	katana_node.position = Vector3(0, 0.25, 0.1)
	katana_node.scale = Vector3.ONE * 0.7
	katana_node.visible = false
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0, 0.16, 1.61)
	katana_node.add_child(tip)
	arm_r.add_child(katana_node)
	for side in 2:
		var kn := make_kunai_node()
		kn.position = KUNAI_REST
		kn.scale = Vector3.ONE * NINJA_KUNAI_HELD_SCALE
		var tip2 := Node3D.new()
		tip2.name = "Tip"
		tip2.position = Vector3(0, 0, 0.3)
		kn.add_child(tip2)
		kn.visible = false
		if side == 0:
			kunai_node = kn
			arm_l.add_child(kn)
		else:
			kunai_node_r = kn
			arm_r.add_child(kn)
	# Held smoke bomb: dark procedural sphere shown in the right fist
	# during the throw wind-up (HTML heldB at (0, 0.22, 0.02)).
	if bomb_node == null:
		bomb_node = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.17
		sm.height = 0.34
		(bomb_node as MeshInstance3D).mesh = sm
		(bomb_node as MeshInstance3D).material_override = _pmat(Color(0.10, 0.06, 0.19), 0.0, 0.5, Color(0.33, 0.33, 0.38), 0.6)
		bomb_node.position = Vector3(0, 0.22, 0.02)
		bomb_node.visible = false
		arm_r.add_child(bomb_node)


func _nj_eo(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _nj_ei(x: float) -> float:
	return x * x


func _nj_eio(x: float) -> float:
	if x < 0.5:
		return 2.0 * x * x
	return 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0


# HTML hand animation port (basePose / actPose / updateHands /
# slashPose from ninjasetup.html). HTML hands[0] (sx=+1) maps to arm_r,
# hands[1] (sx=-1) maps to arm_l. Positions convert from the HTML
# ground-origin group space to the model by +0.55 y (head-center offset).
func _nj_drive_hands(dt: float, tnow: float, moving: bool) -> void:
	_nj_arms = true
	nj_move += ((1.0 if moving else 0.0) - nj_move) * minf(1.0, dt * 12.0)
	nj_dash += ((1.0 if st == "dash" else 0.0) - nj_dash) * minf(1.0, dt * 20.0)
	nj_stretch = st == "dash"
	var tp := [Vector3.ZERO, Vector3.ZERO]
	var tr := [0.0, 0.0]
	var ts := [1.0, 1.0]
	for hi in 2:
		var sx := 1.0 if hi == 0 else -1.0
		var swing := sin(tnow * 12.0 + float(hi) * PI)
		var p := Vector3(sx * 0.66, -0.08 + sin(tnow * 2.4 + float(hi) * 1.7) * 0.035, 0.08)
		p.x = lerpf(p.x, sx * 0.7, nj_move)
		p.y = lerpf(p.y, -0.08 + maxf(0.0, swing) * 0.14, nj_move)
		p.z = lerpf(p.z, 0.08 + swing * 0.34, nj_move)
		p.x = lerpf(p.x, sx * 0.6, nj_dash)
		p.y = lerpf(p.y, 0.05, nj_dash)
		p.z = lerpf(p.z, -0.85, nj_dash)
		tp[hi] = p
		tr[hi] = sin(tnow * 12.0 + float(hi) * PI) * nj_move * 0.6 - nj_dash * 0.9
		ts[hi] = 1.0 + nj_dash * 0.8
	var akind := ""
	if st == "atk" and atk != null:
		akind = String(atk["kind"])
	var uu := 0.0
	var ssg := 1.0
	if akind == "kunai" or akind == "smoke" or akind == "slash1" or akind == "slash2" or akind == "slash3":
		var pose: Dictionary = NJ_POSE_KUNAI if akind == "kunai" else (NJ_POSE_SMOKE if akind == "smoke" else NJ_POSE_SLASH)
		var wind: float = float(pose["wind"])
		var rel: float = float(pose["rel"])
		var TT: float = float(pose["T"])
		var hand := 0 if (kunai_hand or akind != "kunai") else 1
		ssg = 1.0 if hand == 0 else -1.0
		var A: Array = pose["A"]
		var B: Array = pose["B"]
		var off: Array = pose["off"]
		for hj in 2:
			if akind != "kunai" and akind != "smoke" and akind != "slash1":
				break
			var mine := hj == hand
			var hsx := 1.0 if hj == 0 else -1.0
			var bs: Vector3 = tp[hj]
			var ax := Vector3(float(A[0]) * hsx, float(A[1]), float(A[2]))
			var bx := Vector3(float(B[0]) * hsx, float(B[1]), float(B[2]))
			var q: Vector3 = tp[hj]
			var rq: float = tr[hj]
			if akind != "slash1":
				if t < wind:
					var k1 := _nj_eo(t / wind)
					q = bs.lerp(ax, k1)
					if mine:
						rq = -0.7 * (t / wind)
				elif t < rel:
					var k2 := _nj_ei((t - wind) / maxf(rel - wind, 0.001))
					q = ax.lerp(bx, k2)
					if mine:
						ts[hj] = 1.6
						rq = 0.5
				else:
					var k3 := _nj_eio(minf(1.0, (t - rel) / maxf(TT - rel, 0.001)))
					q = bx.lerp(bs, k3)
			tp[hj] = q
			tr[hj] = rq
		if akind == "slash1":
			# HTML slashPose: both hands ride the sword circle; twist/lean
			# still use the slash POSE clock (rel 0.14, T 0.55).
			var phi := 0.9
			if t < 0.1:
				phi = lerpf(0.9, 2.2, _nj_eo(t / 0.1))
			else:
				phi = lerpf(2.2, -1.8, _nj_eio(minf(1.0, (t - 0.1) / 0.22)))
			tp[0] = Vector3(sin(phi) * 0.8, 0.05, cos(phi) * 0.8)
			tp[1] = Vector3(sin(phi) * 0.58, 0.0, cos(phi) * 0.58)
			tr[0] = 0.0
			tr[1] = 0.0
			ts[0] = 1.0
			ts[1] = 1.0
		if t < rel:
			uu = -minf(1.0, t / maxf(wind, 0.001))
		else:
			uu = 1.0 - _nj_eio(minf(1.0, (t - rel) / maxf(TT - rel, 0.001)))
		if akind == "slash2" or akind == "slash3":
			# Extension (no source data beyond the single slashPose): both
			# hands ride the stage's sword motion with the same
			# circle relationship as hit 1 (backhand), or the overhead
			# grip sliding down into the slam (finisher).
			if akind == "slash2":
				var phi2 := -1.8
				if t < 0.06:
					phi2 = lerpf(-1.8, -2.4, _nj_eo(t / 0.06))
				else:
					phi2 = lerpf(-2.4, 1.8, _nj_eio(minf(1.0, (t - 0.06) / 0.24)))
				tp[0] = Vector3(sin(phi2) * 0.8, 0.15, cos(phi2) * 0.8)
				tp[1] = Vector3(sin(phi2) * 0.58, 0.1, cos(phi2) * 0.58)
				tr[0] = 0.0
				tr[1] = 0.0
				ts[0] = 1.0
				ts[1] = 1.0
				uu = 1.0 - _nj_eio(minf(1.0, maxf(0.0, t - 0.06) / 0.44))
			else:
				var grip := Vector3(0.15, 1.0, 0.25)
				var chop := Vector3(0.15, 0.05, 0.75)
				var q0: Vector3 = tp[0]
				var q1: Vector3 = tp[1]
				if t < 0.22:
					var e := _nj_eo(t / 0.22)
					q0 = (tp[0] as Vector3).lerp(grip, e)
					q1 = (tp[1] as Vector3).lerp(Vector3(-grip.x, grip.y - 0.08, grip.z), e)
				elif t < 0.38:
					var e2 := _nj_eio((t - 0.22) / 0.16)
					q0 = grip.lerp(chop, e2)
					q1 = Vector3(-grip.x, grip.y - 0.08, grip.z).lerp(Vector3(-chop.x, chop.y, chop.z), e2)
				else:
					var e3 := _nj_eio(minf(1.0, (t - 0.38) / 0.4))
					q0 = chop.lerp(tp[0] as Vector3, e3)
					q1 = Vector3(-chop.x, chop.y, chop.z).lerp(tp[1] as Vector3, e3)
				tp[0] = q0
				tp[1] = q1
				uu = 1.0 - _nj_eio(minf(1.0, maxf(0.0, t - 0.22) / 0.56))
	nj_twist = uu * 0.35 * ssg
	nj_lean = nj_move * 0.12 - nj_dash * 0.25
	if akind == "smoke":
		nj_lean += uu * 0.22
	var ksm := 1.0 - exp(-dt * (50.0 if (akind == "kunai" or akind == "smoke" or akind == "slash1" or akind == "slash2" or akind == "slash3") else 24.0))
	for hk in 2:
		var arm: Node3D = arm_r if hk == 0 else arm_l
		var want := Vector3((tp[hk] as Vector3).x, 0.55 + (tp[hk] as Vector3).y, (tp[hk] as Vector3).z)
		arm.position = (arm.position as Vector3).lerp(want, ksm)
		arm.rotation.x += (float(tr[hk]) - arm.rotation.x) * ksm
		arm.scale = Vector3(1.0, 1.0, lerpf(arm.scale.z, float(ts[hk]), ksm))


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
	elif k in (keys.get("JUMP", []) as Array) or kc in (keys.get("JUMP", []) as Array):
		buf["JUMP"] = game.now


func _has(n: String) -> bool:
	return game.now - float(buf[n]) < 0.2


func _eat(n: String) -> void:
	buf[n] = -9.0


func ai_press(n: String) -> void:
	if game != null and buf.has(n):
		buf[n] = game.now


func _key_down(codes: Array) -> bool:
	for c in codes:
		if Input.is_physical_key_pressed(c):
			return true
	return false


func upd(dt: float, play: bool) -> void:
	t += dt
	dash_cd = maxf(0.0, dash_cd - dt)
	inv = maxf(0.0, inv - dt)
	flash = maxf(0.0, flash - dt)
	rec = maxf(0.0, rec - dt)
	for key in cd:
		cd[key] = maxf(0.0, float(cd[key]) - dt)
	if st == "ko":
		return
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	var ix := 0.0
	var iy := 0.0
	if play:
		if ai_enabled:
			ix = clampf(ai_ix, -1.0, 1.0)
			iy = clampf(ai_iy, -1.0, 1.0)
		else:
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
		# Universal jump (all characters, all modes): grounded hop that
		# preserves horizontal momentum. Checked before dash/attacks so
		# Space never gets eaten by another action on solo maps.
		if play and _has("JUMP") and grounded:
			_eat("JUMP")
			do_jump()
		if play and rec <= 0.0:
			if _has("D") and dash_cd <= 0.0:
				_eat("D")
				start_dash(Vector3(wx, 0, wz) if wl > 0.01 else face)
			elif _has("H"):
				_eat("H")
				start_atk("H")
			elif _has("L"):
				# Ninja J (L-slot) is the katana light string, not a punch.
				if _is_ninja():
					_ninja_s1()
				else:
					_eat("L")
					start_atk("L")
			elif _has("S1") and float(cd["S1"]) <= 0.0:
				if _is_ninja():
					_ninja_s1()
				else:
					_eat("S1")
					start_atk("S1")
			elif _has("S2") and float(cd["S2"]) <= 0.0:
				_eat("S2")
				start_atk("S2")
			elif _has("S3") and float(cd["S3"]) <= 0.0:
				_eat("S3")
				start_atk("S3")
		if st == "free":
			var top := NINJA_SPEED if _is_ninja() else 6.4
			var e := 1.0 - exp(-(16.0 if wl > 0.01 else 11.0) * dt)
			v.x += (wx * top - v.x) * e
			v.z += (wz * top - v.z) * e
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
		# M1 katana string. Hit 1: horizontal sweep, lunge 3.0 over
		# 0.08-0.30 s, trail + hit at 0.10 (window 0.10-0.34).
		if atk != null and String(atk["kind"]) == "slash1":
			spin_a = 0.0
			if t >= 0.08 and t <= 0.30:
				v.x = face.x * 3.0
				v.z = face.z * 3.0
			if not slash_fx_done and t >= 0.10:
				slash_fx_done = true
				game.vfx.slash_ninja(position, ang, Color(0.71, 1.0, 0.29))
				_slash_hit_foe(1)
		# Hit 2: rising backhand, lunge 3.5 over 0.06-0.28 s, reverse
		# trail + hit at 0.06 (window 0.06-0.30).
		if atk != null and String(atk["kind"]) == "slash2":
			spin_a = 0.0
			if t >= 0.06 and t <= 0.28:
				v.x = face.x * 3.5
				v.z = face.z * 3.5
			if not slash_fx_done and t >= 0.06:
				slash_fx_done = true
				game.vfx.slash_ninja(position, ang + 0.5, Color(0.71, 1.0, 0.29))
				_slash_hit_foe(2)
		# Hit 3: overhead slam, lunge 6.0 over 0.28-0.40 s, separate
		# finisher check at release 0.38 (radial, with shockwave).
		if atk != null and String(atk["kind"]) == "slash3":
			spin_a = 0.0
			if t >= 0.28 and t <= 0.40:
				v.x = face.x * 6.0
				v.z = face.z * 6.0
			if not slash_fx_done and t >= 0.38:
				slash_fx_done = true
				cd["S1"] = NINJA_FINISH_CD
				cd_max["S1"] = NINJA_FINISH_CD
				_slash_hit_foe(3)
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
		elif atk != null and String(atk["kind"]) == "kunai":
			spin_a = 0.0
			if not hit_done and t >= float(atk["w"]):
				hit_done = true
				_fire_kunai()
		elif atk != null and String(atk["kind"]) == "smoke":
			spin_a = 0.0
			if not hit_done and t >= float(atk["w"]):
				hit_done = true
				_deploy_smoke()
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
		elif atk != null and String(atk["kind"]) in ["slash1", "slash2", "slash3"]:
			spin_a = 0.0
		else:
			if atk != null and String(atk["kind"]) == "spin":
				spin_a += dt * 18.0
			else:
				spin_a = 0.0
			if not hit_done and t >= float(atk["w"]):
				hit_done = true
				strike()
		# Jump-cancel out of recovery so platforming never feels stuck.
		if play and _has("JUMP") and grounded and t > float(atk["w"]) + float(atk["a"]):
			_eat("JUMP")
			st = "free"
			atk = null
			do_jump()
		elif t > float(atk["w"]) + float(atk["a"]) and play and _has("D") and dash_cd <= 0.0:
			_eat("D")
			start_dash(Vector3(wx, 0, wz) if wl > 0.01 else face)
		elif t >= float(atk["w"]) + float(atk["a"]) + float(atk["r"]):
			var kkind := String(atk["kind"])
			# M1 buffering: a buffered S1 chains straight into the next
			# hit; otherwise hits 1-2 leave a 0.4 s continuation window.
			if (kkind == "slash1" or kkind == "slash2") and play and (_has("S1") or _has("L")):
				_eat("S1")
				_eat("L")
				combo_stage = 2 if kkind == "slash1" else 3
				_start_slash(NINJA_SLASH2 if kkind == "slash1" else NINJA_SLASH3)
			else:
				if kkind == "slash1" or kkind == "slash2":
					combo_stage = 1 if kkind == "slash1" else 2
					combo_expire = game.now + NINJA_COMBO_WINDOW
				elif kkind == "slash3":
					combo_stage = 0
				st = "free"
				atk = null
	elif st == "dash":
		# HTML shadow dash: DASH_SPEED 22, DASH_TIME 0.2, ghost every 0.025 s
		# (life 0.35 dark 0x1a0a2e) + purple smoke 0x2a1250, 8 at start,
		# ~0.8/frame during, 6 at end, stretched pose (0.8,0.8,1.5).
		v = _dd * (NINJA_DASH_SPEED if _is_ninja() else 18.0)
		_tr -= dt
		if _is_ninja():
			ghost_t -= dt
			if ghost_t <= 0.0:
				ghost_t = 0.025
				game.vfx.ghost(position + Vector3(0, 0.6, 0), ang, Vector3(0.8, 0.8, 1.5))
			if randf() < 0.8:
				game.vfx.puff(position + Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)),
					Color(0.16, 0.07, 0.31), randf_range(0.18, 0.4), 0.5, randf_range(1.0, 2.5))
			_dash_hit_check()
		elif _tr <= 0.0:
			_tr = 0.04
			game.vfx.streak(position, atan2(_dd.x, _dd.z), body_col)
			game.vfx.emit(position + Vector3(0, 0.1, 0),
				Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)),
				Color(0.91, 0.89, 0.78), 0.1, 0.3, 6.0)
		var dash_len := NINJA_DASH_TIME if _is_ninja() else 0.17
		if t > dash_len:
			st = "free"
			rec = 0.08
			v *= 0.3
			if _is_ninja():
				for i in 6:
					game.vfx.puff(position + Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)),
						Color(0.16, 0.07, 0.31), randf_range(0.18, 0.4), 0.5, randf_range(1.0, 2.5))
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
				game.vfx.damage_number(foe.position + Vector3(0, 2.0, 0), str(int(RIDE_DMG)), Color(0.85, 0.75, 1.0), false)
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
	# Ground height. Arena/grass modes have no surface_height hook and keep
	# the original flat y=0 floor; the open worlds raise it for stairs,
	# ramps, bridge decks and plateaus.
	var gh := 0.0
	if game != null and game.has_method("surface_height"):
		gh = maxf(0.0, float(game.surface_height(position.x, position.z, position.y)))
	if position.y <= gh + 0.02 and vy <= 0.0:
		position.y = gh
		vy = 0.0
		grounded = true
		air_jumps = 0
	else:
		grounded = false
		vy -= 30.0 * dt
		vy = maxf(vy, -22.0)
		position.y += vy * dt
	if position.y < -6.0 or hp <= 0.0:
		game.ko(self)


func do_jump() -> void:
	# Single universal hop. Works for every skin
	# because it only touches vy/grounded, never the attack state machine.
	if st == "ko":
		return
	vy = JUMP_V
	grounded = false
	air_jumps += 1
	if game != null and game.get("vfx") != null:
		game.vfx.burst(position + Vector3(0, 0.1, 0), Color(0.91, 0.89, 0.78), 5, 1.6, 0.07, 0.3)
	if game != null and game.get("audio") != null:
		game.audio.play("dash")


func ai_jump() -> void:
	if game != null:
		buf["JUMP"] = game.now


func _start_slash(stage_atk: Dictionary) -> void:
	atk = stage_atk.duplicate()
	st = "atk"
	t = 0.0
	hit_done = false
	slash_fx_done = false
	combo_expire = -9.0
	if foe != null and String(foe.st) != "ko":
		var dx: float = foe.position.x - position.x
		var dz: float = foe.position.z - position.z
		if Vector2(dx, dz).length() < 5.0:
			ang = atan2(dx, dz)
	face = Vector3(sin(ang), 0, cos(ang))
	game.audio.play("dash")


func _ninja_s1() -> void:
	# M1 string entry (J/L-slot and S1 both feed it): continue the open
	# combo window, else restart.
	_eat("S1")
	_eat("L")
	if combo_stage == 1 and game.now <= combo_expire:
		combo_stage = 2
		_start_slash(NINJA_SLASH2)
	elif combo_stage == 2 and game.now <= combo_expire:
		combo_stage = 3
		_start_slash(NINJA_SLASH3)
	else:
		combo_stage = 1
		_start_slash(NINJA_SLASH1)


func start_atk(kind: String) -> void:
	if kind == "L":
		# Ninja J (L-slot) is the katana light string, not a punch.
		if _is_ninja():
			_ninja_s1()
			return
		atk = ATK_L.duplicate()
	elif kind == "H":
		atk = ATK_H.duplicate()
	elif kind == "S1":
		if _is_cowboy():
			atk = ATK_FAN.duplicate()
		elif _is_knight():
			atk = ATK_COUNTER.duplicate()
		elif _is_ninja():
			atk = NINJA_SLASH1.duplicate()
			combo_stage = 1
		else:
			atk = ATK_S1.duplicate()
	elif kind == "S2":
		if _is_cowboy():
			atk = ATK_RIFLE.duplicate()
		elif _is_knight():
			atk = ATK_BASH.duplicate()
		elif _is_ninja():
			atk = ATK_KUNAI.duplicate()
		else:
			atk = ATK_S2.duplicate()
	else:
		if _is_cowboy():
			start_ride()
			return
		elif _is_knight():
			atk = ATK_SWEEP.duplicate()
		elif _is_ninja():
			atk = ATK_SMOKE.duplicate()
		else:
			atk = ATK_S3.duplicate()
		kind = "S3"
	if atk.has("cd"):
		cd[kind] = float(atk["cd"])
		cd_max[kind] = float(atk["cd"])
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
	if String(atk["kind"]) == "kunai":
		kunai_hand = not kunai_hand
	if String(atk["kind"]) in ["slash1", "slash2", "slash3"]:
		slash_fx_done = false
	# HTML smoke throw has no burst at press; the flash/ring/puffs happen
	# at release-detonation (see deploy_cloud burst).
	if String(atk["kind"]) == "smoke":
		game.audio.play("dash")
	if foe != null and String(foe.st) != "ko":
		var dx: float = foe.position.x - position.x
		var dz: float = foe.position.z - position.z
		# Shooters snap-aim at longer range so offset fists still threaten.
		var aim_range := 5.0
		if atk != null and String(atk.get("kind", "")) in ["kunai", "rifle", "fan"]:
			aim_range = 8.0
		if Vector2(dx, dz).length() < aim_range:
			ang = atan2(dx, dz)
	face = Vector3(sin(ang), 0, cos(ang))
	if kind == "S1":
		game.audio.play("dash")
	elif kind == "L":
		game.audio.play("light")
	else:
		game.audio.play("heavy")


func start_dash(d: Vector3) -> void:
	st = "dash"
	t = 0.0
	dash_hit_done = false
	_dd = Vector3(d.x, 0, d.z)
	if _dd.length() < 0.01:
		_dd = face
	_dd = _dd.normalized()
	inv = 0.22
	# HTML DASH_COOLDOWN 0.7 for ninja; others keep 0.75.
	dash_cd = NINJA_DASH_CD if _is_ninja() else 0.75
	_tr = 0.0
	ghost_t = 0.0
	game.audio.play("dash")
	if _is_ninja():
		for i in 8:
			game.vfx.puff(position + Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)),
				Color(0.16, 0.07, 0.31), randf_range(0.18, 0.4), 0.5, randf_range(1.0, 2.5))
	else:
		game.vfx.burst(position + Vector3(0, 0.1, 0), Color(0.91, 0.89, 0.78), 6, 2.0, 0.1, 0.35, 0.3)


func _dash_hit_check() -> void:
	# Ninja shadow-dash strike: one damage tick if the dash carries us into
	# the foe. Same rules as other hits (counter punishes, i-frames block).
	if dash_hit_done or foe == null or String(foe.st) == "ko" or not (foe as Node3D).visible:
		return
	var dx: float = foe.position.x - position.x
	var dz: float = foe.position.z - position.z
	if Vector2(dx, dz).length() > NINJA_DASH_RANGE:
		return
	if foe.counter_open():
		dash_hit_done = true
		foe._do_counter(self)
		return
	if float(foe.inv) > 0.0:
		game.vfx.burst(foe.position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	dash_hit_done = true
	foe.hp = maxf(0.0, float(foe.hp) - NINJA_DASH_DMG)
	foe.dmg += NINJA_DASH_DMG
	var kk := NINJA_DASH_KB * 0.55 / float(foe.mass)
	foe.v = Vector3(_dd.x * kk, 0, _dd.z * kk)
	foe.vy = 3.0
	foe.st = "stun"
	foe.t = 0.0
	foe.stun = 0.25
	foe.flash = 0.14
	foe.atk = null
	var chest: Vector3 = foe.position + Vector3(0, 0.9, 0)
	game.vfx.flash(chest, 0.7, Color(0.75, 0.55, 1.0))
	game.vfx.burst(chest, Color(0.5, 0.35, 0.8), 8, 4.0, 0.08, 0.35)
	game.vfx.damage_number(foe.position + Vector3(0, 2.0, 0), str(int(NINJA_DASH_DMG)), Color(0.75, 0.55, 1.0), false)
	game.audio.play("hitL")
	game.shake = maxf(game.shake, 0.15 * game.shake_amt)


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


func _slash_hit_foe(stage: int) -> void:
	# M1 hit resolution from the stage table (dmg/range in atk).
	# Hits 1-2 use the ordinary arc window; hit 3 is the separate
	# radial finisher check with ground shockwave + heavy feedback.
	if foe == null or String(foe.st) == "ko":
		return
	var dmg: float = float(atk["dmg"])
	var rng: float = float(atk["range"])
	var dx: float = foe.position.x - position.x
	var dz: float = foe.position.z - position.z
	if Vector2(dx, dz).length() > rng + 0.45:
		return
	if stage < 3:
		var d0 := maxf(Vector2(dx, dz).length(), 0.01)
		if d0 > 0.01 and (dx * face.x + dz * face.z) / d0 < float(atk["arc"]):
			return
	if float(foe.inv) > 0.0:
		game.vfx.burst(foe.position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	foe.hp = maxf(0.0, float(foe.hp) - dmg)
	foe.dmg += dmg
	var d := maxf(Vector2(dx, dz).length(), 0.01)
	var kk := float(atk["kb"]) * 0.55 / float(foe.mass)
	var flat := Vector3(dx / d, 0, dz / d)
	foe.v = Vector3(flat.x * kk, 0, flat.z * kk)
	foe.vy = float(atk["vy"])
	foe.st = "stun"
	foe.t = 0.0
	foe.stun = 0.4 if stage == 3 else 0.3
	foe.flash = 0.14
	foe.atk = null
	var chest: Vector3 = foe.position + Vector3(0, 0.9, 0)
	if stage < 3:
		for i in 12:
			var sc := Color(0.71, 1.0, 0.29) if i % 2 == 0 else Color.WHITE
			game.vfx.emit(chest, Vector3(randf_range(-4, 4), randf_range(1, 5), randf_range(-4, 4)), sc, 0.07, 0.35, 10.0)
		game.vfx.flash(chest, 0.9, Color.WHITE)
		game.audio.play("hitH")
		game.shake = maxf(game.shake, float(atk["sh"]) * game.shake_amt)
	else:
		# Finisher: white-hot core + violet flash, ground shockwave +
		# soft outer ring, sparks, dust, debris, light pop, shake.
		var gp: Vector3 = foe.position
		game.vfx.flash(chest, 1.2, Color.WHITE)
		game.vfx.flash(Vector3(gp.x, 0.6, gp.z), 1.6, Color(0.75, 0.55, 1.0))
		game.vfx.light_pop(Vector3(gp.x, 0.6, gp.z), Color(0.7, 0.55, 1.0), 2.5, 0.25)
		game.vfx.ring(gp, Color(0.71, 1.0, 0.29), 0.3, 3.4, 0.45)
		game.vfx.ring(gp, Color(0.71, 1.0, 0.29), 0.5, 5.2, 0.6, 0.3)
		for j in 16:
			var sjc := Color(0.71, 1.0, 0.29) if j % 2 == 0 else Color.WHITE
			game.vfx.emit(chest, Vector3(randf_range(-5, 5), randf_range(1, 6), randf_range(-5, 5)), sjc, 0.08, 0.45, 10.0)
		for k in 10:
			var ka := (float(k) / 10.0) * TAU + randf_range(-0.2, 0.2)
			game.vfx.emit(Vector3(gp.x, 0.15, gp.z), Vector3(cos(ka) * 5.0, 0.5, sin(ka) * 5.0), Color(0.72, 0.65, 0.54), 0.12, 0.7, 2.0)
		game.vfx.burst(chest, Color(0.5, 0.48, 0.52), 8, 3.0, 0.12, 0.7)
		game.audio.play("hitH")
		game.hs = maxf(game.hs, float(atk["hs"]))
		game.shake = maxf(game.shake, float(atk["sh"]) * game.shake_amt)
	game.vfx.damage_number(foe.position + Vector3(0, 2.0, 0), str(int(dmg)),
		Color.WHITE if stage == 3 else Color(0.71, 1.0, 0.29), stage == 3)
	game.damage_props(position, rng + 0.6, dmg)


func _fire_kunai() -> void:
	# Thrown (not hitscan) from alternating fists like the reference: the
	# kunai sticks into whoever it hits and detonates after a fuse instead
	# of dealing its damage up front. (Hand toggled in start_atk so the
	# windup pose already uses the throwing arm.)
	var hand_node: Node3D = kunai_node_r if kunai_hand else kunai_node
	var mpos := global_transform.origin + face * 1.0 + Vector3(0, 0.8, 0)
	if hand_node != null:
		var tip := hand_node.get_node_or_null("Tip") as Node3D
		if tip != null:
			mpos = tip.global_transform.origin
	# Straight level flight along facing from the hand at y 0.65: constant
	# velocity, no homing, no spread, so the travel reads as a straight line.
	mpos.y = 0.65
	var dir := face
	var col := Color(0.75, 0.89, 1.0)
	# HTML releaseKunai(): 6 launch sparks 0xbfe3ff + shake 0.05.
	game.vfx.flash(mpos, 0.5, col)
	for i in 6:
		game.vfx.emit(mpos, Vector3(dir.x * 3.0 + randf_range(-1, 1), randf() * 2.0, dir.z * 3.0 + randf_range(-1, 1)), col, 0.06, 0.25, 0.0)
	game.audio.play("shot")
	game.shake = maxf(game.shake, 0.05 * game.shake_amt)
	var cfg := {"speed": float(ATK_KUNAI["speed"]), "life": float(ATK_KUNAI["life"]),
		"dmg": float(ATK_KUNAI["dmg"]), "kb": float(ATK_KUNAI["kb"]), "vy": float(ATK_KUNAI["vy"]),
		"stun": 0.25, "big": false, "kunai": true, "col": col}
	game.fire_bullet(self, mpos, dir, cfg)


func attach_stuck(node: Node3D = null) -> void:
	# Embed the real thrown kunai in this fighter: reparent it under `model`
	# keeping its world transform, so it visibly sticks out of the impact
	# point and follows every movement, knockback and animation until the
	# detonation frees it. Falls back to a fresh procedural kunai if the
	# projectile node is already gone.
	var entry := {"fuse": STICK_FUSE, "t": 0.0, "node": null}
	stuck.append(entry)
	var inst := node
	if inst == null or not is_instance_valid(inst):
		inst = make_kunai_node()
		model.add_child(inst)
		inst.position = Vector3(randf_range(-0.25, 0.25), randf_range(0.7, 1.1), randf_range(-0.2, 0.2))
		inst.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
	else:
		var gt := (inst as Node3D).global_transform
		(inst as Node3D).get_parent().remove_child(inst)
		model.add_child(inst)
		(inst as Node3D).global_transform = gt
	entry["node"] = inst


func clear_stuck() -> void:
	for s in stuck:
		var n: Node3D = s.get("node", null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	stuck.clear()
	_restore_armed_mats()


func _snapshot_armed_mats() -> void:
	if not armed_snap.is_empty():
		return
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm != null:
			armed_snap.append([sm, sm.albedo_color, sm.emission])


func _restore_armed_mats() -> void:
	for e in armed_snap:
		var sm: StandardMaterial3D = e[0]
		if is_instance_valid(sm):
			sm.albedo_color = e[1]
			sm.emission = e[2]
	armed_snap.clear()


func _deploy_smoke() -> void:
	# Thrown bomb (HTML releaseBomb): lands facing*4.2, clamped to arena,
	# bursts into tick-damage cloud r 3.8 / life 5.5 / tick 0.5 / dmg 3.
	var land := position + face * 4.2
	land.x = clampf(land.x, -4.4, 4.4)
	land.z = clampf(land.z, -4.4, 4.4)
	land.y = 0.0
	game.deploy_cloud(self, land, NINJA_CLOUD_R, NINJA_CLOUD_LIFE, NINJA_CLOUD_TICK, NINJA_CLOUD_DMG, Color(0.4, 0.38, 0.45))


func _do_counter(other) -> void:
	if counter_done:
		return
	counter_done = true
	other.hp = maxf(0.0, float(other.hp) - COUNTER_DMG)
	other.dmg += COUNTER_DMG
	game.vfx.damage_number(other.position + Vector3(0, 2.0, 0), str(int(COUNTER_DMG)), Color(0.85, 0.75, 1.0), false)
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
	game.vfx.damage_number(foe.position + Vector3(0, 2.0, 0), str(int(float(ATK_BASH["dmg"]))), Color(0.85, 0.75, 1.0), false)
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
	game.vfx.damage_number(foe.position + Vector3(0, 2.0, 0), str(int(float(ATK_SWEEP["dmg"]))), Color(0.85, 0.75, 1.0), false)
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
	if foe == null:
		# No foe (open-world roam): swing whiffs through the air, no target.
		game.vfx.slash(position, ang, bool(atk["big"]), body_col)
		v += face * float(atk["lunge"])
		game.damage_props(position, float(atk["range"]) + 0.6, float(atk["dmg"]))
		return
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
	game.vfx.damage_number(foe.position + Vector3(0, 2.0, 0), str(int(float(atk["dmg"]))),
		Color.WHITE if heavy else Color(0.85, 0.75, 1.0), heavy)
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
	_nj_arms = false
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
	if katana_node != null:
		katana_node.rotation = Vector3.ZERO
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
		elif kind == "slash1" or kind == "slash2" or kind == "slash3":
			# Katana pivot animation per M1 stage (hands are driven by
			# _nj_drive_hands). Hit 1 = HTML slashPose sweep.
			lean = 0.45
			sq = 1.08
			E[0] = 1.2
			E[1] = 1.2
			U[0] = 0.0
			U[1] = 0.0
			if katana_node != null:
				if kind == "slash1":
					var phi := 0.9
					var tilt := -0.5 * clampf(t / 0.1, 0.0, 1.0)
					if t < 0.1:
						phi = lerpf(0.9, 2.2, _nj_eo(t / 0.1))
					else:
						phi = lerpf(2.2, -1.8, _nj_eio(minf(1.0, (t - 0.1) / 0.22)))
						tilt = lerpf(-0.5, 0.15, clampf((t - 0.1) / 0.22, 0.0, 1.0))
					katana_node.rotation = Vector3(tilt, phi, 0.0)
				elif kind == "slash2":
					# Rising backhand: coil further back, reverse sweep with
					# the blade lifting upward + an early sword roll.
					var phi2 := -1.8
					if t < 0.06:
						phi2 = lerpf(-1.8, -2.4, _nj_eo(t / 0.06))
					else:
						phi2 = lerpf(-2.4, 1.8, _nj_eio(minf(1.0, (t - 0.06) / 0.24)))
					var lift := -0.2 - 0.7 * sin(PI * clampf((t - 0.06) / 0.24, 0.0, 1.0)) if t >= 0.06 else -0.2 * (t / 0.06)
					var roll := 0.8 * sin(PI * clampf(t / 0.12, 0.0, 1.0))
					katana_node.rotation = Vector3(lift, phi2, roll)
				else:
					# Overhead slam: raise behind the head, chop down.
					var rx := 0.2
					if t < 0.22:
						rx = lerpf(0.2, -2.3, _nj_eo(t / 0.22))
					elif t < 0.38:
						rx = lerpf(-2.3, 0.9, _nj_eio((t - 0.22) / 0.16))
					else:
						rx = lerpf(0.9, 0.2, _nj_eio(minf(1.0, (t - 0.38) / 0.4)))
					katana_node.rotation = Vector3(rx, 0.0, 0.0)
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
		elif kind == "kunai":
			# Overhand throw (HTML POSE kunai: wind 0.07, rel 0.11, T 0.34).
			var k_u := clampf(t / 0.11, 0.0, 1.0)
			var snap := 0.0
			if t >= 0.11:
				snap = sin(clampf((t - 0.11) / 0.23, 0.0, 1.0) * PI)
			lean = 0.12 - snap * 0.25
			sq = 1.0
			var tr := 1 if kunai_hand else 0
			var hr := 1 - tr
			E[hr] = 0.25 + 0.2 * k_u
			E[tr] = 0.2
			U[hr] = 0.1 + 0.1 * k_u
			U[tr] = -0.6 * k_u + 1.3 * snap
			var kn_pos := KUNAI_REST + Vector3(0, snap * 0.15, 0.15 * k_u)
			if kunai_node != null:
				kunai_node.position = kn_pos
			if kunai_node_r != null:
				kunai_node_r.position = kn_pos
		elif kind == "smoke":
			# Crouch-drop the bomb: sink, arms sweep down, then rise.
			var s_u := clampf(t / 0.55, 0.0, 1.0)
			var drop := sin(clampf(s_u, 0.0, 1.0) * PI)
			lean = 0.3 * drop
			sq = 1.0 - 0.12 * drop
			E[0] = 0.3 + 0.5 * drop
			E[1] = 0.3 + 0.5 * drop
			U[0] = 0.2 + 0.4 * drop
			U[1] = 0.2 + 0.4 * drop
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
	# Ninja procedural hands (HTML basePose/actPose/slashPose): drive the
	# arms directly and let the HTML lean/twist win over the generic ones.
	if _is_ninja() and (st == "free" or st == "dash" or (st == "atk" and atk != null and String(atk["kind"]) in ["kunai", "smoke", "slash1", "slash2", "slash3"])):
		_nj_drive_hands(dt, tnow, sp > 0.5)
		lean = nj_lean
		twist = nj_twist
		if st == "atk" and atk != null and String(atk["kind"]) == "slash3":
			if t < 0.22:
				lean = 0.2
			elif t < 0.48:
				lean = 0.55
			else:
				lean = lerpf(0.55, 0.0, clampf((t - 0.48) / 0.3, 0.0, 1.0))
	else:
		nj_stretch = false
	if not _nj_arms:
		for k in 2:
			var s := 1.0 if k == 1 else -1.0
			var arm: Node3D = arm_r if k == 1 else arm_l
			var x := clampf(float(E[k]), 0.0, 1.0)
			var sw := (la if k == 1 else -la) * 0.35
			var hv2 := atk != null and bool(atk["big"])
			arm.position = Vector3(s * (0.62 - 0.3 * x),
				0.55 + float(U[k]) + (0.2 * x if st == "atk" else 0.0) + (RIDE_LIFT if st == "ride" else 0.0),
				float(E[k]) + sw)
			arm.scale = Vector3.ONE * (1.0 + 0.45 * x * (1.0 if hv2 else 0.4))
	model.rotation.x = lean
	model.rotation.z = tw
	if st == "atk" and atk != null and String(atk["kind"]) == "spin":
		model.rotation.y = spin_a + twist
	else:
		model.rotation.y = twist
	# Airborne readability: stretch slightly + tuck arms while jumping.
	if not grounded and st == "free":
		sq = 1.12 if vy > 1.0 else 0.92
		lean = -0.18 if vy > 1.0 else 0.25
	model.scale = Vector3(1.0 / sqrt(maxf(sq, 0.05)), maxf(sq, 0.05), 1.0 / sqrt(maxf(sq, 0.05)))
	if nj_stretch and _is_ninja():
		model.scale = Vector3(0.8, 0.8, 1.5)
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
	# HTML katana visibility: swordPivot.visible only during the slash.
	if katana_node != null and _is_ninja():
		katana_node.visible = st == "atk" and atk != null and String(atk["kind"]) in ["slash1", "slash2", "slash3"]
	# Held bomb visible in the right fist during the smoke wind-up only
	# (HTML heldB, released at rel).
	if bomb_node != null:
		bomb_node.visible = _is_ninja() and st == "atk" and atk != null and String(atk["kind"]) == "smoke" and t < float(atk["w"])
	var throwing := st == "atk" and atk != null and String(atk["kind"]) == "kunai"
	if kunai_node != null:
		kunai_node.visible = throwing and not kunai_hand
		if not throwing:
			kunai_node.position = KUNAI_REST
	if kunai_node_r != null:
		kunai_node_r.visible = throwing and kunai_hand
		if not throwing:
			kunai_node_r.position = KUNAI_REST
	if horse_root != null:
		horse_root.visible = st == "ride"
	rotation.y = ang
	# Hit-flash emission: only touch shared skin materials on transitions.
	# The old code rewrote every material's emission every frame for every
	# fighter, even at rest.
	var want_flash := flash > 0.0
	if stuck.is_empty():
		_restore_armed_mats()
		if want_flash != _flash_on:
			_flash_on = want_flash
			var e4 := 0.8 if want_flash else 0.05
			for m in mats:
				(m as StandardMaterial3D).emission = Color(e4, e4, e4)
	else:
		# Armed fuse blink (html/ninjasetup.html): body albedo pulses
		# toward hot red with accelerating frequency as the fuse runs down,
		# overriding the normal hit flash until detonation.
		_snapshot_armed_mats()
		var k := 0.0
		for s in stuck:
			k = maxf(k, clampf(float(s["t"]) / maxf(float(s["fuse"]), 0.01), 0.0, 1.0))
		var pulse := sin(tnow * (14.0 + k * 50.0)) * 0.5 + 0.5
		for m in mats:
			var sm := m as StandardMaterial3D
			if sm == null:
				continue
			var orig: Array = _armed_orig(sm)
			sm.albedo_color = (orig[0] as Color).lerp(Color(1.0, 0.16, 0.16), pulse)
			sm.emission = Color(pulse, 0.0, 0.0)


func _armed_orig(sm: StandardMaterial3D) -> Array:
	for e in armed_snap:
		if e[0] == sm:
			return [e[1], e[2]]
	return [sm.albedo_color, sm.emission]
