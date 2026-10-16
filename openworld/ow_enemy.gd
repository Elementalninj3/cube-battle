extends Node3D
## Open-world enemy: owns one reused arena Fighter (model, procedural
## animation, attacks, HP/stun/knockback all come from bb_fighter.gd) and
## drives it through the same AI hooks the arena CPU uses (ai_ix/ai_iy +
## ai_press), with a small open-world brain: idle / patrol / chase /
## attack / stunned / defeated + respawn. Melee uses the fighter's own
## strike(); ranged uses its real projectiles via the world's facade.

const FighterScript = preload("res://bb_fighter.gd")
const Util = preload("res://openworld/ow_util.gd")

const RESPAWN_TIME := 25.0

var world = null
var body = null
var camp := Vector3.ZERO
var max_hp := 100.0
var alive := true
var atk_cd := 0.0
var splash_cd := 0.0
var think_t := 0.0
var patrol_t := 0.0
var patrol_target := Vector3.ZERO
var respawn_t := 0.0
var detect_r := 14.0

var _bar_bg: MeshInstance3D
var _bar_fg: MeshInstance3D
var _last_frac := -1.0


func setup(p_world, skin: String, camp_pos: Vector3, hp: float) -> void:
	world = p_world
	camp = camp_pos
	max_hp = hp
	body = FighterScript.new()
	body.idx = 1
	body.game = world
	body.keys = {"up": [], "down": [], "left": [], "right": [], "L": [], "H": [], "D": [],
		"S1": [], "S2": [], "S3": []} # AI-driven only; ignores the keyboard
	body.ai_enabled = true
	add_child(body)
	body.setup_skin(skin)
	body.bounds = float(world.bounds_val)
	body.reset_match(camp + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), randf() * TAU)
	body.hp = max_hp
	patrol_target = body.position
	_build_bar()


func _build_bar() -> void:
	# Floating HP bar parented to the body (rides movement/knockback):
	# dark back quad + green front quad, both billboarded.
	_bar_bg = MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(1.0, 0.13)
	_bar_bg.mesh = bgm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bmat.albedo_color = Color(0.1, 0.02, 0.02)
	_bar_bg.material_override = bmat
	_bar_bg.position = Vector3(0, 2.45, 0)
	_bar_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(_bar_bg)
	_bar_fg = MeshInstance3D.new()
	var fgm := QuadMesh.new()
	fgm.size = Vector2(0.94, 0.08)
	_bar_fg.mesh = fgm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.albedo_color = Color(0.3, 0.85, 0.3)
	_bar_fg.material_override = fmat
	_bar_fg.position = Vector3(0, 2.45, 0.01)
	_bar_fg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(_bar_fg)


func _ready() -> void:
	position = Vector3.ZERO # body carries the world position; wrapper stays put


func is_busy() -> bool:
	return body.st == "atk" or body.st == "stun" or body.st == "dash"


func on_defeated() -> void:
	alive = false
	respawn_t = RESPAWN_TIME
	body.ai_ix = 0.0
	body.ai_iy = 0.0


func respawn() -> void:
	body.reset_match(camp + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), randf() * TAU)
	body.hp = max_hp
	alive = true
	atk_cd = 1.0
	patrol_target = body.position
	world.vfx.burst(body.position + Vector3(0, 0.8, 0), body.body_col, 10, 3.0, 0.1, 0.4)


func _move_toward(target: Vector3, strength: float) -> void:
	var d := Vector2(target.x - body.position.x, target.z - body.position.z)
	var iv: Vector2 = Util.iso_for(d) * strength
	body.ai_ix = clampf(iv.x, -1.0, 1.0)
	body.ai_iy = clampf(iv.y, -1.0, 1.0)


func _stop() -> void:
	body.ai_ix = 0.0
	body.ai_iy = 0.0


func _try_press(slot: String, cd: float) -> void:
	if atk_cd <= 0.0 and not is_busy():
		body.ai_press(slot)
		atk_cd = cd


# One brain step. Far enemies think less often (cheap LOD); close ones
# react every frame. Called by the world every physics tick.
func tick(dt: float, player_pos: Vector3, player_targetable: bool) -> void:
	_bar_fg.visible = alive and body.hp < max_hp
	_bar_bg.visible = _bar_fg.visible
	if _bar_fg.visible:
		# Center-scaled (stays aligned under the body's yaw). Material and
		# scale update only when hp actually moved (avoids per-tick
		# shader-param writes for every visible enemy).
		var frac := clampf(body.hp / max_hp, 0.0, 1.0)
		if absf(frac - _last_frac) > 0.002:
			_last_frac = frac
			_bar_fg.scale.x = maxf(frac, 0.001)
			(_bar_fg.material_override as StandardMaterial3D).albedo_color = Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.85, 0.3), frac)
	else:
		_last_frac = -1.0
	if not alive:
		respawn_t -= dt
		if respawn_t <= 0.0:
			world.respawn_enemy(self)
		return
	atk_cd = maxf(0.0, atk_cd - dt)
	splash_cd = maxf(0.0, splash_cd - dt)
	if body.st == "ko" or body.st == "stun":
		return
	var to_player := Util.flat_dist(body.position, player_pos)
	var far := to_player > 26.0
	if far:
		think_t -= dt
		if think_t > 0.0:
			return
		think_t = 0.25
	var skin: String = body.skin_name
	if not player_targetable or to_player > detect_r:
		# Leash home: drift back to camp and idle/patrol there.
		if Util.flat_dist(body.position, camp) > 3.0:
			_move_toward(camp, 0.55)
		else:
			_patrol(dt)
		return
	if skin == "cubecowboy":
		_ranged(dt, player_pos, to_player)
	elif skin == "ninja":
		_skirmish(dt, player_pos, to_player)
	else:
		_melee(dt, player_pos, to_player)


func _patrol(dt: float) -> void:
	patrol_t -= dt
	if patrol_t <= 0.0 or Util.flat_dist(body.position, patrol_target) < 0.6:
		patrol_t = randf_range(3.0, 6.0)
		patrol_target = camp + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	_move_toward(patrol_target, 0.35)


func _melee(_dt: float, player_pos: Vector3, d: float) -> void:
	# Knight: walk in, heavy/light melee, occasional shield bash or counter.
	if d > 2.1:
		_move_toward(player_pos, 1.0)
		return
	_stop()
	var r := randf()
	if r < 0.12:
		_try_press("S2", 2.2) # shield bash
	elif r < 0.2 and world.player_attacking() and d < 2.5:
		_try_press("S1", 2.5) # counter stance
	elif r < 0.62:
		_try_press("H", 1.6)
	else:
		_try_press("L", 1.2)


func _ranged(_dt: float, player_pos: Vector3, d: float) -> void:
	# Cowboy: hold 5-9 m, rifle/fan-fire, punch if rushed.
	if d < 2.0:
		_stop()
		_try_press("L", 1.2)
	elif d < 4.5:
		var away: Vector3 = body.position + (body.position - player_pos)
		_move_toward(away, 0.8)
	elif d > 9.0:
		_move_toward(player_pos, 0.9)
	else:
		_stop()
		if randf() < 0.6:
			_try_press("S2", 2.4) # rifle
		else:
			_try_press("S1", 2.8) # fan-fire


func _skirmish(_dt: float, player_pos: Vector3, d: float) -> void:
	# Ninja: kunai at mid range, katana string up close, dash to engage.
	if d > 9.0:
		_move_toward(player_pos, 1.0)
	elif d > 3.0:
		_stop()
		var r := randf()
		if r < 0.55:
			_try_press("S2", 1.8) # kunai
		elif r < 0.65:
			_try_press("S3", 3.5) # smoke
		elif r < 0.75:
			_try_press("D", 1.5) # dash in
		else:
			_move_toward(player_pos, 0.7)
	elif d > 2.6:
		_move_toward(player_pos, 1.0)
	else:
		_stop()
		if body.combo_stage > 0:
			_try_press("S1", 0.1) # continue the katana string
		else:
			_try_press("S1", 1.4)
