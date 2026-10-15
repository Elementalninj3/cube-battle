extends Node3D
## Grass Render mode: a faithful recreation of the BinbunGrass demo
## (free assets/.../BinbunGrass/main.tscn) as a selectable game mode, with
## the playable ninja on the field.
##
## The demo's .tres materials reference the author's own res://assets/ paths,
## so they cannot load here; the materials are rebuilt in code with the
## demo's exact parameters via ow_builder (same shaders, palette, atlas,
## dithered alpha, wind). Layout matches main.tscn: 20x20 ground plane,
## hidden blade template, 10000 instanced billboard quads, 2-split shadow
## sun, white/ambient-color environment.
## (The demo sun transform points upward, an obvious authoring slip that
## would kill all direct light and shadows, so it aims 45 degrees down.)
##
## Player: the existing ninja fighter (movement, camera-relative controls,
## attacks, abilities) driven like open-world mode. Kunai/smoke fly as
## visuals only — nothing to hit out here. Esc returns to the menu.

const Builder = preload("res://openworld/ow_builder.gd")
const FighterScript = preload("res://bb_fighter.gd")
const VfxScript = preload("res://bb_vfx.gd")
const AudioScript = preload("res://bb_audio.gd")
const CamScript = preload("res://openworld/ow_camera.gd")
const Util = preload("res://openworld/ow_util.gd")

# ---- fighter facade surface (mirrors open-world mode) ----
var now := 0.0
var state := "play"
var vfx = null
var audio = null
var shake := 0.0
var shake_amt := 0.6
var hs := 0.0
var ts := 1.0

var spawn := Vector3(0, 0, 6)
var player = null
var cam = null
var bullets: Array = []
var clouds: Array = []
var _bullet_mesh: BoxMesh
var _bullet_mats := {}
const BULLET_R := 0.75
var _tracer_pool: Array = []
var _cloud_mesh: SphereMesh = null
var _cloud_mat: StandardMaterial3D = null

var _fps_label: Label
var _hp_label: Label
var _fps_t := 0.0
var _last_hp := ""


func _ready() -> void:
	_build_env()
	_build_ground()
	_build_grass()
	vfx = VfxScript.new()
	add_child(vfx)
	audio = AudioScript.new()
	add_child(audio)
	_bullet_mesh = BoxMesh.new()
	_bullet_mesh.size = Vector3.ONE
	var _bm := StandardMaterial3D.new()
	_bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bullet_mesh.material = _bm
	_spawn_player()
	cam = CamScript.new()
	add_child(cam)
	cam.target = player
	cam.t_dist = 18.0
	cam.dist = 18.0
	_build_hud()
	state = "play"


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 1, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.695381, 0.644979, 0.598817)
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-PI / 4.0, 0, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 1
	sun.directional_shadow_split_1 = 0.01
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var gp := PlaneMesh.new()
	gp.size = Vector2(20, 20)
	ground.mesh = gp
	ground.material_override = Builder.make_ground_material()
	add_child(ground)


func _build_grass() -> void:
	# Hidden template blade, like the demo's invisible GrassBlade node.
	var template := MeshInstance3D.new()
	template.name = "GrassBlade"
	template.visible = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.subdivide_width = 2
	quad.subdivide_depth = 2
	quad.center_offset = Vector3(0, 0.2, 0)
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.roughness = 0.9
	quad.material = qm
	template.mesh = quad
	add_child(template)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 10000
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10000:
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		mm.set_instance_transform(i, Transform3D(basis,
			Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10))))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.material_override = Builder.make_grass_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _spawn_player() -> void:
	player = FighterScript.new()
	player.idx = 0
	player.game = self
	player.keys = {"up": [], "down": [], "left": [], "right": [],
		"L": [KEY_J], "H": [KEY_K], "D": [KEY_SPACE],
		"S1": [KEY_O], "S2": [KEY_L], "S3": [KEY_P]}
	player.ai_enabled = true
	add_child(player)
	player.setup_skin("ninja")
	player.bounds = 9.0
	player.reset_match(spawn, PI)
	player.foe = null


func _physics_process(dt: float) -> void:
	now += dt
	_player_move()
	player.upd(dt, true)
	_upd_bullets(dt)
	_upd_clouds(dt)
	player.anim(dt, now)
	_upd_hud()


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
	var iv := _move_axis()
	if iv.length() < 0.01:
		player.ai_ix = 0.0
		player.ai_iy = 0.0
		return
	var basis: Dictionary = cam.move_basis()
	var wish: Vector3 = (basis["right"] as Vector3) * iv.x + (basis["fwd"] as Vector3) * iv.y
	var pair: Vector2 = Util.iso_for(Vector2(wish.x, wish.z))
	player.ai_ix = clampf(pair.x, -1.0, 1.0)
	player.ai_iy = clampf(pair.y, -1.0, 1.0)


# ---- fighter facade: no props out here, solo defeat handling ----
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
	audio.play("ko")
	player.reset_match(spawn, PI)
	player.hp = 100.0


# ---- solo projectiles: fly + expire as visuals only (nothing to hit) ----
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


func _obtain_tracer() -> MeshInstance3D:
	if _tracer_pool.is_empty():
		var bx := MeshInstance3D.new()
		bx.mesh = _bullet_mesh
		bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bx)
		return bx
	var bx2 := _tracer_pool.pop_back() as MeshInstance3D
	bx2.visible = true
	return bx2


func fire_bullet(owner: Node3D, mpos: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	var mi: Node3D = null
	var sp: float = float(cfg.get("speed", 22.0))
	var bc: Color = cfg.get("col", Color(1.0, 0.8, 0.35))
	var is_kunai := bool(cfg.get("kunai", false))
	if is_kunai:
		mi = FighterScript.make_kunai_node()
		mi.scale = Vector3.ONE * FighterScript.NINJA_KUNAI_THROWN_SCALE
		mi.rotation.y = atan2(dir.x, dir.z)
		for ch in (mi as Node).get_children():
			if ch is GeometryInstance3D:
				(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		var bx := _obtain_tracer()
		bx.mesh = _bullet_mesh
		bx.scale = Vector3(0.09, 0.09, 0.28 + sp * 0.012)
		bx.rotation.y = atan2(dir.x, dir.z)
		bx.material_override = _bullet_mat(bool(cfg.get("big", false)), bc)
		mi = bx
	mi.position = mpos
	bullets.append({"node": mi, "p": mpos, "v": dir.normalized() * sp,
		"life": float(cfg.get("life", 0.45)), "col": bc,
		"kunai": is_kunai, "trail": 0.0})


func _upd_bullets(dt: float) -> void:
	if bullets.is_empty():
		return
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b["life"] = float(b["life"]) - dt
		var np: Vector3 = (b["p"] as Vector3) + (b["v"] as Vector3) * dt
		if float(b["life"]) <= 0.0 or absf(np.x) > 14.0 or absf(np.z) > 14.0 or np.y < -0.5 or np.y > 10.0:
			var nd := b["node"] as Node3D
			if bool(b.get("kunai", false)):
				nd.queue_free()
			else:
				(nd as MeshInstance3D).visible = false
				if _tracer_pool.size() < 32:
					_tracer_pool.append(nd)
				else:
					nd.queue_free()
			bullets.remove_at(i)
			continue
		b["p"] = np
		(b["node"] as Node3D).position = np
		b["trail"] = float(b["trail"]) - dt
		if float(b["trail"]) <= 0.0:
			b["trail"] = 0.02 if bool(b.get("kunai", false)) else 0.07
			if bool(b.get("kunai", false)):
				vfx.emit(np, Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), Color(0.75, 0.89, 1.0), 0.05, 0.18, 0.0)
			else:
				vfx.burst(np, b["col"], 1, 0.3, 0.05, 0.2)


# ---- solo smoke: bomb arc + landing burst as visuals only ----
func deploy_cloud(owner: Node3D, pos: Vector3, _radius: float, _life: float,
		_tick: float, _dmg: float, _col: Color) -> void:
	var from := (owner as Node3D).position + Vector3(0, 0.8, 0)
	clouds.append({"from": from, "p": pos, "delay": 0.55, "bomb": null})


func _cloud_bomb() -> MeshInstance3D:
	if _cloud_mesh == null:
		_cloud_mesh = SphereMesh.new()
		_cloud_mesh.radius = 0.17
		_cloud_mesh.height = 0.34
	if _cloud_mat == null:
		_cloud_mat = StandardMaterial3D.new()
		_cloud_mat.albedo_color = Color(0.10, 0.06, 0.19)
		_cloud_mat.roughness = 0.5
		_cloud_mat.emission_enabled = true
		_cloud_mat.emission = Color(0.33, 0.33, 0.38)
		_cloud_mat.emission_energy_multiplier = 0.6
	var bm := MeshInstance3D.new()
	bm.mesh = _cloud_mesh
	bm.material_override = _cloud_mat
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bm


func _upd_clouds(dt: float) -> void:
	if clouds.is_empty():
		return
	for i in range(clouds.size() - 1, -1, -1):
		var c: Dictionary = clouds[i]
		c["delay"] = float(c["delay"]) - dt
		var u := clampf(1.0 - float(c["delay"]) / 0.55, 0.0, 1.0)
		var bp: Vector3 = (c["from"] as Vector3).lerp(c["p"], u) + Vector3(0, 6.0 * u * (1.0 - u), 0)
		if c["bomb"] == null or not is_instance_valid(c["bomb"]):
			c["bomb"] = _cloud_bomb()
			add_child(c["bomb"])
		(c["bomb"] as Node3D).position = bp
		(c["bomb"] as Node3D).rotation.x += 14.0 * dt
		(c["bomb"] as Node3D).rotation.z += 9.0 * dt
		vfx.puff(bp, Color(0.71, 0.71, 0.74), 0.14, 0.5, 0.3)
		if float(c["delay"]) <= 0.0:
			if c["bomb"] != null and is_instance_valid(c["bomb"]):
				(c["bomb"] as Node).queue_free()
			var p: Vector3 = c["p"]
			vfx.flash(p + Vector3(0, 0.5, 0), 1.3, Color.WHITE)
			vfx.ring(Vector3(p.x, 0.05, p.z), Color(0.78, 0.78, 0.82), 0.3, 9.0, 0.55, 0.2)
			audio.play("hitH")
			clouds.remove_at(i)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hp_label = Label.new()
	_hp_label.text = "100"
	_hp_label.add_theme_font_size_override("font_size", 16)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_hp_label.add_theme_constant_override("outline_size", 6)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hp_label.position = Vector2(16, 14)
	layer.add_child(_hp_label)
	_fps_label = Label.new()
	_fps_label.text = "-- FPS"
	_fps_label.add_theme_font_size_override("font_size", 15)
	_fps_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 0.8))
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.position = Vector2(-110, -40)
	layer.add_child(_fps_label)
	var hint := Label.new()
	hint.text = "BinbunGrass demo + ninja   |   WASD move · J/K/L/O/P/Space · MMB-click/E rotate · Q reverse · wheel zoom · R reset · Esc menu"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 0.8))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-560, -30)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)


func _upd_hud() -> void:
	var ht := str(int(ceil(player.hp)))
	if ht != _last_hp:
		_last_hp = ht
		_hp_label.text = ht
	_fps_t += get_process_delta_time()
	if _fps_t >= 0.5:
		_fps_t = 0.0
		_fps_label.text = str(Engine.get_frames_per_second()) + " FPS"
	if shake > 0.0:
		cam.position.x += randf_range(-0.5, 0.5) * shake
		cam.position.y += randf_range(-0.5, 0.5) * shake
		shake = maxf(0.0, shake - get_physics_process_delta_time() * 1.2)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e := event as InputEventKey
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://block_brawl.tscn")
