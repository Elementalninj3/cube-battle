extends Node3D
## Open-World mode: a small explorable stylized-nature area with enemy camps.
##
## Reuses the arena systems instead of reinventing them: the player and every
## enemy is a real bb_fighter.Fighter (models, procedural animation, attacks,
## damage, knockback, VFX), driven through the same hooks the arena CPU uses
## (ai_ix/ai_iy + ai_press). This script acts as the fighter's `game` facade
## (now/state/vfx/audio/shake/ko/fire_bullet/deploy_cloud/...) and ports the
## arena projectile/cloud/stuck-kunai updates, retargeted from "the foe" to
## "player + all enemies". Arena modes are untouched.

const FighterScript = preload("res://bb_fighter.gd")
const VfxScript = preload("res://bb_vfx.gd")
const AudioScript = preload("res://bb_audio.gd")
const Builder = preload("res://openworld/ow_builder.gd")
const EnemyScene = preload("res://openworld/ow_enemy.tscn")
const CamScript = preload("res://openworld/ow_camera.gd")
const Util = preload("res://openworld/ow_util.gd")

# ---- fighter facade surface (mirrors what bb_main provides) ----
var now := 0.0
var state := "play"
var vfx = null
var audio = null
var shake := 0.0
var shake_amt := 0.6
var quality := 2
var hs := 0.0
var ts := 1.0

# ---- world state ----
var obstacles: Array = []
var camps: Array = []
var spawn := Vector3(0, 0, 20)
var player = null
var enemies: Array = []
var cam = null
var kills := 0
var dead_t := -1.0
var victory_t := 0.0

# ---- projectiles (arena logic, retargeted) ----
var bullets: Array = []
var clouds: Array = []
var _bullet_mesh: BoxMesh
var _bullet_mats := {}
const BULLET_R := 0.75

const ENEMY_HP := {"ninja": 95.0, "cubeknight": 130.0, "cubecowboy": 85.0}
const MELEE_KINDS := ["punch", "slash1", "slash2", "slash3", "bash", "sweep", "spin", "upper"]

# ---- HUD ----
var _hp_fill: ColorRect
var _hp_label: Label
var _obj_label: Label
var _info_label: Label


func _ready() -> void:
	_build_env()
	var built: Dictionary = Builder.build(self)
	obstacles = built["obstacles"]
	camps = built["camps"]
	spawn = built["spawn"]
	vfx = VfxScript.new()
	add_child(vfx)
	audio = AudioScript.new()
	add_child(audio)
	_bullet_mesh = BoxMesh.new()
	_bullet_mesh.size = Vector3.ONE
	_spawn_player()
	_spawn_enemies()
	cam = CamScript.new()
	add_child(cam)
	cam.target = player
	_build_hud()
	state = "play"


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.35, 0.62, 0.92)
	psm.sky_horizon_color = Color(0.82, 0.92, 0.95)
	psm.ground_bottom_color = Color(0.2, 0.35, 0.18)
	psm.ground_horizon_color = Color(0.7, 0.8, 0.7)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.set("fog_enabled", true)
	env.set("fog_light_color", Color(0.82, 0.9, 0.9))
	env.set("fog_depth_begin", 70.0)
	env.set("fog_depth_end", 160.0)
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.6, 0)
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.62, 0.82, 1.0)
	rim.light_energy = 0.45
	rim.shadow_enabled = false
	rim.rotation = Vector3(-0.4, -2.4, 0)
	add_child(rim)


func _spawn_player() -> void:
	player = FighterScript.new()
	player.idx = 0
	player.game = self
	# Arena P1 attacks; movement is camera-relative via ai_ix/ai_iy instead.
	player.keys = {"up": [], "down": [], "left": [], "right": [],
		"L": [KEY_J], "H": [KEY_K], "D": [KEY_SPACE],
		"S1": [KEY_O], "S2": [KEY_L], "S3": [KEY_P]}
	player.ai_enabled = true
	add_child(player)
	player.setup_skin("ninja")
	player.bounds = 31.0
	player.reset_match(spawn, PI)
	player.foe = null


func _spawn_enemies() -> void:
	for c in camps:
		for skin in (c as Dictionary)["skins"]:
			var e = EnemyScene.instantiate()
			add_child(e)
			e.setup(self, str(skin), (c as Dictionary)["pos"], float(ENEMY_HP.get(skin, 100.0)))
			e.body.foe = player
			enemies.append(e)


func player_targetable() -> bool:
	return dead_t < 0.0 and player != null and player.visible


func player_attacking() -> bool:
	return player != null and String(player.st) == "atk"


func alive_enemies() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n


func _physics_process(dt: float) -> void:
	now += dt
	if dead_t >= 0.0:
		dead_t -= dt
		if dead_t <= 0.0:
			player.reset_match(spawn, PI)
			player.hp = 100.0
			_info_label.visible = false
	_target_foe()
	_player_move()
	player.upd(dt, true)
	_splash(dt)
	for e in enemies:
		e.tick(dt, player.position, player_targetable())
		e.body.upd(dt, true)
	_separate()
	_push_all()
	_upd_bullets(dt)
	_upd_stuck(dt, true)
	_upd_clouds(dt)
	player.anim(dt, now)
	for e in enemies:
		if e.alive:
			e.body.anim(dt, now)
	if victory_t > 0.0:
		victory_t -= dt
		if victory_t <= 0.0:
			_info_label.visible = false
	_upd_hud()


func _target_foe() -> void:
	var best = null
	var best_d := 7.0
	for e in enemies:
		if not e.alive:
			continue
		var d := Util.flat_dist(player.position, e.body.position)
		if d < best_d:
			best_d = d
			best = e.body
	player.foe = best


func _move_axis() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		y -= 1.0
	return Vector2(x, y)


func _player_move() -> void:
	_player_move_iv(_move_axis())


func _player_move_iv(iv: Vector2) -> void:
	if iv.length() < 0.01 or dead_t >= 0.0:
		player.ai_ix = 0.0
		player.ai_iy = 0.0
		return
	var basis: Dictionary = cam.move_basis()
	var wish: Vector3 = (basis["right"] as Vector3) * iv.x + (basis["fwd"] as Vector3) * iv.y
	var pair: Vector2 = Util.iso_for(Vector2(wish.x, wish.z))
	player.ai_ix = clampf(pair.x, -1.0, 1.0)
	player.ai_iy = clampf(pair.y, -1.0, 1.0)


# Arena strike() only damages the single foe; splash the same attack table
# onto the OTHER enemies in range so crowds don't ignore cleaves. The foe
# itself is skipped (strike already handled it) to avoid double-hits.
func _splash(_dt: float) -> void:
	if dead_t >= 0.0:
		return
	if String(player.st) == "dash":
		_splash_hit(null, FighterScript.NINJA_DASH_DMG, FighterScript.NINJA_DASH_KB, 1.3, true, 3.0, 0.25)
		return
	if String(player.st) != "atk" or player.atk == null:
		return
	var kind := String(player.atk["kind"])
	if not kind in MELEE_KINDS:
		return
	var radial := bool(player.atk.get("radial", false))
	_splash_hit(player.atk, float(player.atk["dmg"]), float(player.atk["kb"]),
		float(player.atk["range"]) + 0.45, radial, float(player.atk.get("vy", 0.0)), 0.3)


func _splash_hit(atk, dmg: float, kb: float, rng: float, radial: bool, vy: float, stun: float) -> void:
	for e in enemies:
		if not e.alive or e.body == player.foe or e.splash_cd > 0.0:
			continue
		var dx: float = e.body.position.x - player.position.x
		var dz: float = e.body.position.z - player.position.z
		var d := Vector2(dx, dz).length()
		if d > rng:
			continue
		if not radial and d > 0.01 and (dx * player.face.x + dz * player.face.z) / d < 0.3:
			continue
		e.splash_cd = 0.3
		_hit_body(e.body, dmg, kb, vy, stun)


func _hit_body(f, dmg: float, kb: float, vy: float, stun: float) -> void:
	if float(f.inv) > 0.0:
		vfx.burst(f.position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	f.hp = maxf(0.0, float(f.hp) - dmg)
	f.dmg += dmg
	var away: Vector3 = f.position - player.position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -player.face
	var kk := kb * 0.55 / float(f.mass)
	f.v = Vector3(away.x * kk, 0, away.z * kk)
	f.vy = vy
	f.st = "stun"
	f.t = 0.0
	f.stun = stun
	f.flash = 0.14
	f.atk = null
	var chest: Vector3 = f.position + Vector3(0, 0.9, 0)
	vfx.flash(chest, 0.7, Color.WHITE)
	vfx.burst(chest, player.body_col, 8, 4.5, 0.1, 0.45)
	vfx.damage_number(f.position + Vector3(0, 2.0, 0), str(int(dmg)), Color(0.85, 0.75, 1.0), false)
	audio.play("hitL")
	shake = maxf(shake, 0.12 * shake_amt)


func _separate() -> void:
	var bodies: Array = []
	if player.visible:
		bodies.append(player)
	for e in enemies:
		if e.alive:
			bodies.append(e.body)
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			var a: Vector3 = bodies[i].position
			var b: Vector3 = bodies[j].position
			var dx := b.x - a.x
			var dz := b.z - a.z
			var d := Vector2(dx, dz).length()
			if d < 0.9 and d > 0.001:
				var push := (0.9 - d) * 0.5
				var nx := dx / d
				var nz := dz / d
				if bodies[i] == player:
					bodies[j].position.x += nx * push * 2.0
					bodies[j].position.z += nz * push * 2.0
				elif bodies[j] == player:
					bodies[i].position.x -= nx * push * 2.0
					bodies[i].position.z -= nz * push * 2.0
				else:
					bodies[i].position.x -= nx * push
					bodies[i].position.z -= nz * push
					bodies[j].position.x += nx * push
					bodies[j].position.z += nz * push


func _push_all() -> void:
	player.position = Util.push_out(player.position, obstacles)
	for e in enemies:
		if e.alive:
			e.body.position = Util.push_out(e.body.position, obstacles)


# ---- fighter facade: damage props (none here), defeat handling ----
func damage_props(_pos: Vector3, _radius: float, _dmg: float) -> int:
	return 0


func ko(f) -> void:
	if String(f.st) == "ko":
		return
	f.st = "ko"
	f.hp = 0.0
	f.visible = false
	f.clear_stuck()
	var p: Vector3 = Vector3(f.position.x, maxf(0.6, f.position.y), f.position.z)
	vfx.burst(p, f.body_col, 34, 8.0, 0.2, 0.9)
	vfx.burst(p, Color.WHITE, 8, 5.0, 0.1, 0.5)
	vfx.flash(p, 1.4, f.body_col)
	audio.play("ko")
	shake = maxf(shake, 0.45 * shake_amt)
	if f == player:
		dead_t = 3.0
		_info_label.text = "You fell! Respawning..."
		_info_label.visible = true
	else:
		for e in enemies:
			if e.body == f:
				e.on_defeated()
				break
		kills += 1
		if alive_enemies() == 0:
			_info_label.text = "Area cleared!"
			_info_label.visible = true
			victory_t = 5.0


func respawn_enemy(e) -> void:
	e.respawn()


# ---- projectiles: arena logic retargeted at player + enemies ----
func _live_bodies(except = null) -> Array:
	var out: Array = []
	if player.visible and player != except:
		out.append(player)
	for e in enemies:
		if e.alive and e.body != except:
			out.append(e.body)
	return out


func _bullet_mat(big: bool, bc: Color) -> StandardMaterial3D:
	var key := ("big" if big else "small") + bc.to_html()
	if not _bullet_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = bc
		m.emission_enabled = true
		m.emission = bc
		_bullet_mats[key] = m
	return _bullet_mats[key]


func fire_bullet(owner: Node3D, mpos: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	var mi: Node3D = null
	var sp: float = float(cfg.get("speed", 22.0))
	var bc: Color = cfg.get("col", Color(1.0, 0.8, 0.35))
	if bool(cfg.get("kunai", false)):
		mi = FighterScript.make_kunai_node()
		mi.scale = Vector3.ONE * FighterScript.NINJA_KUNAI_THROWN_SCALE
		mi.rotation.y = atan2(dir.x, dir.z)
		for ch in (mi as Node).get_children():
			if ch is GeometryInstance3D:
				(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var bx := MeshInstance3D.new()
		bx.mesh = _bullet_mesh
		bx.scale = Vector3(0.09, 0.09, 0.28 + sp * 0.012)
		bx.rotation.y = atan2(dir.x, dir.z)
		bx.material_override = _bullet_mat(bool(cfg.get("big", false)), bc)
		bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi = bx
	add_child(mi)
	mi.position = mpos
	bullets.append({"node": mi, "p": mpos, "v": dir.normalized() * sp,
		"life": float(cfg.get("life", 0.45)), "dmg": float(cfg.get("dmg", 4.0)),
		"kb": float(cfg.get("kb", 2.5)), "vy": float(cfg.get("vy", 2.0)),
		"stun": float(cfg.get("stun", 0.18)), "big": bool(cfg.get("big", false)),
		"kunai": bool(cfg.get("kunai", false)),
		"owner": owner, "col": bc, "trail": 0.0})


func _seg_point(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return a.distance_to(p)
	var u := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return (a + ab * u).distance_to(p)


func _upd_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b["life"] = float(b["life"]) - dt
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		var np := p + v * dt
		if float(b["life"]) <= 0.0 or absf(np.x) > 40.0 or absf(np.z) > 40.0 or np.y < -0.5 or np.y > 10.0:
			_kill_bullet(i, false)
			continue
		var hit := false
		for f in _live_bodies(b["owner"]):
			var chest: Vector3 = (f as Node3D).position + Vector3(0, 0.9, 0)
			if _seg_point(p, np, chest) < BULLET_R:
				_bullet_hit(i, b, f)
				hit = true
				break
		if hit:
			continue
		b["p"] = np
		(b["node"] as Node3D).position = np
		# Kunai hold their spawn aim: straight, tip-first flight.
		b["trail"] = float(b["trail"]) - dt
		if float(b["trail"]) <= 0.0:
			b["trail"] = 0.02 if bool(b.get("kunai", false)) else 0.07
			if bool(b.get("kunai", false)):
				vfx.emit(np, Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), Color(0.75, 0.89, 1.0), 0.05, 0.18, 0.0)
			else:
				vfx.burst(np, b["col"], 1, 0.3, 0.05, 0.2)


func _bullet_hit(i: int, b: Dictionary, f) -> void:
	var big := bool(b["big"])
	var own = b["owner"]
	if f.counter_open():
		f._do_counter(own)
		_kill_bullet(i, false)
		return
	if float(f.inv) > 0.0:
		_kill_bullet(i, false)
		vfx.burst((f as Node3D).position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	if bool(b.get("kunai", false)):
		_stick_kunai(i, f)
		return
	var dmg: float = float(b["dmg"])
	f.hp = maxf(0.0, float(f.hp) - dmg)
	f.dmg += dmg
	var kk := float(b["kb"]) * 0.55 / float(f.mass)
	var flat: Vector3 = b["v"]
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, 1)
	f.v = Vector3(flat.x * kk, 0, flat.z * kk)
	f.vy = float(b["vy"])
	f.st = "stun"
	f.t = 0.0
	f.stun = float(b["stun"])
	f.flash = 0.14
	f.atk = null
	var hp_pos: Vector3 = (f as Node3D).position + Vector3(0, 0.9, 0)
	vfx.damage_number((f as Node3D).position + Vector3(0, 2.0, 0), str(int(dmg)),
		Color.WHITE if big else Color(0.85, 0.75, 1.0), big)
	vfx.flash(hp_pos, 0.9 if big else 0.55, Color.WHITE)
	vfx.burst(hp_pos, own.body_col, 16 if big else 7, 7.0 if big else 4.5, 0.1, 0.45)
	hs = maxf(hs, 0.1 if big else 0.03)
	shake = maxf(shake, (0.35 if big else 0.12) * shake_amt)
	audio.play("hitH" if big else "hitL")
	_kill_bullet(i, true)


func _stick_kunai(i: int, f) -> void:
	var b: Dictionary = bullets[i]
	var node := b["node"] as Node3D
	var at: Vector3 = b["p"]
	bullets.remove_at(i)
	f.attach_stuck(node)
	vfx.burst(at, b["col"], 4, 3.0, 0.07, 0.3)
	var chest: Vector3 = (f as Node3D).position + Vector3(0, 0.9, 0)
	for s in 10:
		var sc := Color.WHITE if s % 2 == 0 else Color(1.0, 0.83, 0.48)
		vfx.emit(chest, Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 5.0), randf_range(-2.5, 2.5)), sc, 0.06, randf_range(0.3, 0.5), 10.0)
	audio.play("hitL")
	shake = maxf(shake, 0.15 * shake_amt)


func _upd_stuck(dt: float, play: bool) -> void:
	if not play:
		return
	for f in _live_bodies():
		if String(f.st) == "ko" or not (f as Node3D).visible:
			f.clear_stuck()
			continue
		for i in range(f.stuck.size() - 1, -1, -1):
			var s: Dictionary = f.stuck[i]
			s["t"] = float(s["t"]) + dt
			var fuse := maxf(float(s["fuse"]), 0.01)
			f.flash = maxf(float(f.flash), 0.05)
			if float(s["t"]) >= fuse:
				# The expired kunai's own mesh goes with the blast too.
				f.stuck.remove_at(i)
				var expired: Node3D = s.get("node", null)
				if expired != null and is_instance_valid(expired):
					expired.queue_free()
				_detonate(f)


func _detonate(victim) -> void:
	var at: Vector3 = (victim as Node3D).position
	var bp := Vector3(at.x, maxf(at.y, 0.0) + 0.6, at.z)
	vfx.blast_flash(bp, 3.4, Color(1.0, 0.95, 0.69), Color(1.0, 0.29, 0.07), 0.35, false)
	vfx.blast_flash(bp, 1.8, Color.WHITE, Color.WHITE, 0.16, true)
	vfx.light_pop(bp, Color(1.0, 0.6, 0.3), 3.0, 0.25)
	vfx.ring(Vector3(at.x, 0.05, at.z), Color(1.0, 0.54, 0.24), 0.5, 5.5, 0.45, 0.8, true)
	for j in 16:
		var da := randf() * TAU
		var dsp := 3.0 + randf() * 5.0
		vfx.emit(bp, Vector3(cos(da) * dsp, 3.0 + randf() * 5.0, sin(da) * dsp),
			Color(1.0, 0.54, 0.24) if randf() < 0.5 else Color(1.0, 0.82, 0.48),
			0.1 + randf() * 0.15, 0.7, 20.0)
	for k in 7:
		var sa := randf() * TAU
		var ssp := 0.8 + randf() * 2.2
		vfx.puff(bp + Vector3(randf_range(-0.25, 0.25), randf() * 0.4, randf_range(-0.25, 0.25)),
			Color(0.42, 0.23, 0.11), 0.5 + randf() * 0.4, 1.2 + randf() * 0.7, 0.0,
			2.2, 0.6, Color(0.17, 0.17, 0.2),
			Vector3(cos(sa) * ssp, 1.5 + randf() * 2.5, sin(sa) * ssp))
	for n in 5:
		var na := (float(n) / 5.0) * TAU + randf() * 0.4
		var nsp := 4.0 + randf() * 3.0
		vfx.puff(Vector3(at.x, 0.15, at.z), Color(0.72, 0.65, 0.54),
			0.3 + randf() * 0.25, 0.7 + randf() * 0.3, 0.0,
			2.5, 0.5, Color(0.43, 0.42, 0.46),
			Vector3(cos(na) * nsp, 0.3, sin(na) * nsp))
	for q in 30:
		var qa := randf() * TAU
		var qsp := 6.0 + randf() * 6.0
		vfx.emit(bp, Vector3(cos(qa) * qsp, 2.0 + randf() * 7.0, sin(qa) * qsp),
			Color(1.0, 0.76, 0.3) if randf() < 0.5 else Color(1.0, 0.48, 0.16),
			0.06 + randf() * 0.07, 0.4 + randf() * 0.5, 10.0)
	vfx.scorch(Vector3(at.x, 0.0, at.z), 3.0, 1.5)
	audio.play("boom")
	shake = maxf(shake, 0.5 * shake_amt)
	hs = maxf(hs, 0.09)
	for s in victim.stuck:
		var sn: Node3D = s.get("node", null)
		if sn != null and is_instance_valid(sn):
			sn.queue_free()
	victim.stuck.clear()
	for f in _live_bodies():
		var dx: float = (f as Node3D).position.x - at.x
		var dz: float = (f as Node3D).position.z - at.z
		var d := Vector2(dx, dz).length()
		if d > FighterScript.BLAST_R:
			continue
		if f != victim and float(f.inv) > 0.0:
			vfx.burst((f as Node3D).position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
			continue
		f.hp = maxf(0.0, float(f.hp) - FighterScript.BLAST_DMG)
		f.dmg += FighterScript.BLAST_DMG
		vfx.damage_number((f as Node3D).position + Vector3(0, 2.0, 0), str(int(FighterScript.BLAST_DMG)), Color.WHITE, true)
		var kk := 10.0 * 0.55 / float(f.mass)
		var dir := Vector3(dx / maxf(d, 0.01), 0, dz / maxf(d, 0.01))
		f.v = Vector3(dir.x * kk, 0, dir.z * kk)
		f.vy = 6.0
		f.st = "stun"
		f.t = 0.0
		f.stun = 0.4
		f.flash = 0.14
		f.atk = null
		vfx.flash((f as Node3D).position + Vector3(0, 0.9, 0), 0.9, Color.WHITE)
		# The blast consumes embedded kunai it catches: nothing stays stuck.
		for s in f.stuck:
			var sn2: Node3D = s.get("node", null)
			if sn2 != null and is_instance_valid(sn2):
				sn2.queue_free()
		f.stuck.clear()


func _kill_bullet(i: int, impacted: bool) -> void:
	var b: Dictionary = bullets[i]
	if impacted:
		vfx.burst(b["p"], b["col"], 6, 3.0, 0.07, 0.3)
	(b["node"] as Node3D).queue_free()
	bullets.remove_at(i)


# ---- smoke clouds: tick-damage zones, same rules as the arena ----
func deploy_cloud(owner: Node3D, pos: Vector3, radius: float, life: float,
		tick: float, dmg: float, col: Color) -> void:
	var from := (owner as Node3D).position + Vector3(0, 0.8, 0)
	clouds.append({"owner": owner, "from": from, "p": pos, "r": radius,
		"life": life, "delay": 0.55, "landed": false, "bomb": null,
		"tick": tick, "tick_t": 0.3, "ticks": 0, "puff_t": 0.0, "dmg": dmg, "col": col})


func _cloud_bomb() -> MeshInstance3D:
	var bm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	bm.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.06, 0.19)
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = Color(0.33, 0.33, 0.38)
	m.emission_energy_multiplier = 0.6
	bm.material_override = m
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bm


func _upd_clouds(dt: float) -> void:
	for i in range(clouds.size() - 1, -1, -1):
		var c: Dictionary = clouds[i]
		var p: Vector3 = c["p"]
		var r: float = c["r"]
		if not bool(c["landed"]):
			c["delay"] = float(c["delay"]) - dt
			var u := clampf(1.0 - float(c["delay"]) / 0.55, 0.0, 1.0)
			var bp: Vector3 = (c["from"] as Vector3).lerp(p, u) + Vector3(0, 6.0 * u * (1.0 - u), 0)
			if c["bomb"] == null or not is_instance_valid(c["bomb"]):
				c["bomb"] = _cloud_bomb()
				add_child(c["bomb"])
			(c["bomb"] as Node3D).position = bp
			(c["bomb"] as Node3D).rotation.x += 14.0 * dt
			(c["bomb"] as Node3D).rotation.z += 9.0 * dt
			vfx.puff(bp, Color(0.71, 0.71, 0.74), 0.14, 0.5, 0.3)
			if randf() < 0.6:
				vfx.emit(bp, Vector3(0, 0.5, 0), Color(0.78, 0.78, 0.82), 0.05, 0.25, 0.0)
			var early := false
			for f in _live_bodies(c["owner"]):
				var fdx: float = (f as Node3D).position.x - bp.x
				var fdz: float = (f as Node3D).position.z - bp.z
				if Vector2(fdx, fdz).length() < 1.2 and bp.y < 2.0:
					c["p"] = Vector3((f as Node3D).position.x, 0, (f as Node3D).position.z)
					p = c["p"]
					early = true
					break
			if float(c["delay"]) <= 0.0 or early:
				c["landed"] = true
				if c["bomb"] != null and is_instance_valid(c["bomb"]):
					(c["bomb"] as Node).queue_free()
				c["bomb"] = null
				vfx.flash(p + Vector3(0, 0.5, 0), 1.3, Color.WHITE)
				vfx.ring(Vector3(p.x, 0.05, p.z), Color(0.78, 0.78, 0.82), 0.3, 9.0, 0.55, 0.2)
				for j in 16:
					var a := randf() * TAU
					var sp := randf_range(2.0, 5.0)
					vfx.puff(p + Vector3(0, 0.3, 0), Color(0.71, 0.71, 0.74), randf_range(0.45, 0.7), randf_range(1.0, 1.6), 1.0, 0.0, 0.55)
					vfx.emit(p + Vector3(0, 0.3, 0), Vector3(cos(a) * sp, randf_range(0.5, 1.5), sin(a) * sp), Color(0.71, 0.71, 0.74), 0.1, 0.8, 2.0)
				for k in 26:
					var a2 := randf() * TAU
					var sp2 := randf_range(4.0, 8.0)
					vfx.emit(p + Vector3(0, 0.5, 0), Vector3(cos(a2) * sp2, randf_range(2.0, 7.0), sin(a2) * sp2), Color(0.83, 0.83, 0.85), 0.07, 0.5, 10.0)
				audio.play("hitH")
				shake = maxf(shake, 0.3 * shake_amt)
			continue
		c["life"] = float(c["life"]) - dt
		if float(c["life"]) <= 0.0:
			clouds.remove_at(i)
			continue
		c["puff_t"] = float(c["puff_t"]) - dt
		if float(c["puff_t"]) <= 0.0:
			c["puff_t"] = 0.13
			var a := randf() * TAU
			var rr := sqrt(randf()) * r * 0.95
			var fade := clampf(float(c["life"]) / 0.8, 0.0, 1.0)
			if fade <= 0.0:
				fade = 1.0
			vfx.puff(p + Vector3(cos(a) * rr, randf_range(0.1, 0.6), sin(a) * rr),
				Color(0.71, 0.71, 0.74), randf_range(0.6, 1.05), randf_range(1.6, 2.6), randf_range(0.35, 0.85), 0.0, 0.45)
			if randf() < 0.35 * fade:
				vfx.emit(p + Vector3(cos(a) * rr, 0.2, sin(a) * rr), Vector3(0, randf_range(0.8, 1.4), 0), Color(0.61, 1.0, 0.69), 0.05, 1.2, 0.0)
		c["tick_t"] = float(c["tick_t"]) - dt
		if float(c["tick_t"]) > 0.0:
			continue
		c["tick_t"] = float(c["tick"])
		c["ticks"] = int(c["ticks"]) + 1
		if int(c["ticks"]) % 2 == 0:
			vfx.ring(Vector3(p.x, 0.06, p.z), c["col"], 0.3, r, 0.4, 0.3)
		vfx.burst(p + Vector3(0, 0.5, 0), Color(0.61, 1.0, 0.69), 4, 2.0, 0.06, 0.4)
		for f in _live_bodies(c["owner"]):
			if float(f.inv) > 0.0:
				continue
			var dx: float = (f as Node3D).position.x - p.x
			var dz: float = (f as Node3D).position.z - p.z
			if Vector2(dx, dz).length() > r:
				continue
			var dmg: float = float(c["dmg"])
			f.hp = maxf(0.0, float(f.hp) - dmg)
			f.dmg += dmg
			f.flash = 0.1
			vfx.damage_number((f as Node3D).position + Vector3(0, 2.0, 0), str(int(dmg)), Color(0.61, 1.0, 0.69), false)
			vfx.burst((f as Node3D).position + Vector3(0, 0.9, 0), c["col"], 4, 2.5, 0.08, 0.3)


# ---- HUD ----
func _hud_label(text: String, size: int, pos: Vector2, anchor: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(anchor)
	l.position = pos
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.03, 0.03, 0.05, 0.85)
	hp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp_bg.position = Vector2(16, 14)
	hp_bg.size = Vector2(264, 26)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.3, 0.8, 0.3)
	_hp_fill.position = Vector2(19, 17)
	_hp_fill.size = Vector2(258, 20)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hp_fill)
	_hp_label = _hud_label("100", 16, Vector2(19, 15), Control.PRESET_TOP_LEFT)
	_hp_label.size = Vector2(258, 26)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hp_label)
	_obj_label = _hud_label("Defeat the camp raiders!", 22, Vector2(-320, 12), Control.PRESET_CENTER_TOP)
	_obj_label.size = Vector2(640, 30)
	_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_obj_label)
	var hint := _hud_label("WASD move · J/K attacks · L kunai · P smoke · Space dash   |   MMB-drag orbit · wheel zoom · Q/E turn · R reset cam · Esc menu",
		14, Vector2(-560, -30), Control.PRESET_CENTER_BOTTOM)
	hint.size = Vector2(1120, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	layer.add_child(hint)
	_info_label = _hud_label("", 44, Vector2(-400, -140), Control.PRESET_CENTER)
	_info_label.size = Vector2(800, 70)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.visible = false
	layer.add_child(_info_label)
	var menu_b := Button.new()
	menu_b.text = "Menu"
	menu_b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_b.position = Vector2(-96, 14)
	menu_b.custom_minimum_size = Vector2(80, 32)
	menu_b.pressed.connect(_on_menu)
	layer.add_child(menu_b)


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://block_brawl.tscn")


func _upd_hud() -> void:
	var frac := clampf(player.hp / 100.0, 0.0, 1.0)
	_hp_fill.size = Vector2(258.0 * frac, 20.0)
	if frac > 0.6:
		_hp_fill.color = Color(0.3, 0.8, 0.3)
	elif frac > 0.3:
		_hp_fill.color = Color(0.95, 0.8, 0.25)
	else:
		_hp_fill.color = Color(0.9, 0.3, 0.25)
	_hp_label.text = str(int(ceil(player.hp)))
	_obj_label.text = "Defeat the camp raiders!   Raiders left: %d   Defeated: %d" % [alive_enemies(), kills]
	# Camera shake (translation only, keeps the orbit rig intact).
	if shake > 0.0:
		cam.position.x += randf_range(-0.5, 0.5) * shake
		cam.position.y += randf_range(-0.5, 0.5) * shake
		shake = maxf(0.0, shake - get_physics_process_delta_time() * 1.2)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e := event as InputEventKey
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_menu()


func _process(_dt: float) -> void:
	# Camera follows the player node directly; nothing per-frame here besides HUD.
	pass
