extends Node3D
## Block Brawl port (from html/block-brawl-quality.html): local 1v1 block
## fighter. Menu -> select (color/hat/visor) -> countdown -> fight -> KO
## slow-mo -> winner screen. P1: WASD + J/K/L/O/P/Space. P2: arrows + ,/./Numpad1-5/Shift.

const FighterScript = preload("res://bb_fighter.gd")
const ArenaScript = preload("res://bb_arena.gd")
const VfxScript = preload("res://bb_vfx.gd")
const AudioScript = preload("res://bb_audio.gd")

const NAMES := ["Blue", "Orange", "Red", "Cyan", "Purple", "Gold"]
const HATS := ["none", "cowboy", "crown", "beanie", "helmet"]

var cfg := [{"c": 0, "h": 1, "g": 1}, {"c": 1, "h": 2, "g": 0}]
var state := "menu"
var now := 0.0
var hs := 0.0
var shake := 0.0
var ts := 1.0
var shake_amt := 0.6
var quality := 2
var show_fps := true

var fighters: Array = []
var vfx = null
var audio = null
var arena = null
var cam: Camera3D
var sun: DirectionalLight3D
var cp := Vector3(24, 24, 24)
var look := Vector3.ZERO
var orbit := 0.0
var zD := 27.0
var av := Vector3.ZERO
var cdT := 0.0
var lastN := 0
var koT := 0.0
var winner := 0
var prev := "play"
var from := "menu"
var fight_t := 0.0

var hud: Control
var n0: Label
var n1: Label
var d0: Label
var d1: Label
var b0fill: ColorRect
var b1fill: ColorRect
var cd_l: Array = []
var cd_r: Array = []
const CD_COLS := [Color(1.0, 0.85, 0.2), Color(1.0, 0.5, 0.15), Color(0.75, 0.4, 1.0)]
const CD_ORDER := ["S1", "S2", "S3"]
var cd: Label
var fps: Label
var screens := {}
var sel_panels := []
var win_label: Label


func _col(i: int) -> Color:
	match i:
		0:
			return Color8(0x3b, 0x82, 0xf6)
		1:
			return Color8(0xff, 0x7a, 0x2f)
		2:
			return Color8(0xe8, 0x4a, 0x5f)
		3:
			return Color8(0x22, 0xc7, 0xc7)
		4:
			return Color8(0xa8, 0x55, 0xf7)
		_:
			return Color8(0xf5, 0xc5, 0x18)


func _ready() -> void:
	_build_env()
	arena = ArenaScript.new()
	add_child(arena)
	vfx = VfxScript.new()
	add_child(vfx)
	audio = AudioScript.new()
	add_child(audio)
	arena.build(vfx)
	_make_fighters()
	_build_ui()
	apply_quality()
	to_menu()


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.95, 0.75, 0.58)
	psm.sky_horizon_color = Color(1.0, 0.91, 0.82)
	psm.ground_bottom_color = Color(0.29, 0.45, 0.22)
	psm.ground_horizon_color = Color(0.85, 0.76, 0.66)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.set("tone_mapper", 3) # ACES
	env.set("fog_enabled", true)
	env.set("fog_light_color", Color(0.95, 0.86, 0.75))
	env.set("fog_depth_begin", 50.0)
	env.set("fog_depth_end", 100.0)
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.6, 0)
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.62, 0.82, 1.0)
	rim.light_energy = 0.45
	rim.shadow_enabled = false
	rim.rotation = Vector3(-0.4, -2.4, 0)
	add_child(rim)
	cam = Camera3D.new()
	cam.fov = 28.0
	add_child(cam)
	cam.current = true
	cam.position = cp


func _make_fighters() -> void:
	fighters.clear()
	for i in 2:
		var f = FighterScript.new()
		f.idx = i
		f.game = self
		add_child(f)
		fighters.append(f)
	fighters[0].foe = fighters[1]
	fighters[1].foe = fighters[0]
	fighters[0].keys = {"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"L": [KEY_J], "H": [KEY_K], "D": [KEY_SPACE],
		"S1": [KEY_L], "S2": [KEY_O], "S3": [KEY_P]}
	fighters[1].keys = {"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
		"L": [KEY_KP_1, KEY_COMMA], "H": [KEY_KP_2, KEY_PERIOD], "D": [KEY_SHIFT, KEY_SLASH],
		"S1": [KEY_KP_3], "S2": [KEY_KP_4], "S3": [KEY_KP_5]}
	_pv()


func _pv() -> void:
	_setup_fighters()
	for f in fighters:
		f.v = Vector3.ZERO


func _setup_fighters() -> void:
	for i in 2:
		var c: Dictionary = cfg[i]
		fighters[i].setup(_col(int(c["c"])), int(c["h"]), int(c["g"]) == 1)


func start_match() -> void:
	_setup_fighters()
	fighters[0].reset_match(Vector3(-2.0, 0, 2.0), atan2(4.0, -4.0))
	fighters[1].reset_match(Vector3(2.0, 0, -2.0), atan2(-4.0, 4.0))
	vfx.clear_all()
	ts = 1.0
	hs = 0.0
	shake = 0.0
	state = "count"
	cdT = 3.2
	lastN = 0
	n0.text = NAMES[int(cfg[0]["c"])]
	n1.text = NAMES[int(cfg[1]["c"])]
	b0fill.color = _col(int(cfg[0]["c"]))
	b1fill.color = _col(int(cfg[1]["c"]))
	show_screen(null)


func damage_props(pos: Vector3, radius: float, dmg: float) -> int:
	if arena == null:
		return 0
	return arena.damage_props(pos, radius, dmg)


func ko(f) -> void:
	if String(f.st) == "ko":
		return
	f.st = "ko"
	f.hp = 0.0
	f.visible = false
	var p: Vector3 = Vector3(f.position.x, maxf(0.6, f.position.y), f.position.z)
	vfx.burst(p, f.body_col, 34, 8.0, 0.2, 0.9)
	vfx.burst(p, Color.WHITE, 8, 5.0, 0.1, 0.5)
	vfx.flash(p, 1.4, f.body_col)
	audio.play("ko")
	shake = maxf(shake, 0.45 * shake_amt)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e := event as InputEventKey
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			toggle_pause()


func toggle_pause() -> void:
	if state == "play" or state == "count":
		prev = state
		state = "pause"
		show_screen("pause")
	elif state == "pause":
		state = prev
		show_screen(null)


func _physics_process(dt: float) -> void:
	if state == "pause" or state == "settings":
		return
	now += dt
	var sd := dt
	if hs > 0.0:
		hs -= dt
		sd = dt * 0.05
	else:
		sd = dt * ts
	vfx.dt_scale = sd / maxf(dt, 0.00001)
	if state == "count" or state == "play" or state == "ko" or state == "over":
		if state == "count":
			cdT -= dt
			var n := int(ceil(cdT))
			if cdT > 0.0:
				cd.text = str(n)
				if n != lastN:
					lastN = n
					audio.play("beep_lo")
			elif cdT > -0.6:
				cd.text = "FIGHT!"
			if cdT <= 0.0 and state == "count":
				state = "play"
				audio.play("beep_hi")
		else:
			cdT -= dt
			if cdT < -0.6:
				cd.text = ""
		var a = fighters[0]
		var b = fighters[1]
		a.upd(sd, state == "play")
		b.upd(sd, state == "play")
		if String(a.st) != "dash" and String(b.st) != "dash" and String(a.st) != "ko" and String(b.st) != "ko":
			var dx: float = b.position.x - a.position.x
			var dz: float = b.position.z - a.position.z
			var d: float = Vector2(dx, dz).length()
			if d < 0.9 and d > 0.001:
				var pu := (0.9 - d) * 0.5
				a.position.x -= dx / d * pu
				a.position.z -= dz / d * pu
				b.position.x += dx / d * pu
				b.position.z += dz / d * pu
		if state == "play" and (float(a.hp) <= 0.0 or float(b.hp) <= 0.0):
			if float(a.hp) <= 0.0:
				ko(a)
			if float(b.hp) <= 0.0:
				ko(b)
			state = "ko"
			koT = 0.0
			ts = 0.3
			if float(a.hp) <= 0.0 and float(b.hp) <= 0.0:
				winner = 0 if float(a.dmg) < float(b.dmg) else 1
			else:
				winner = 1 if float(a.hp) <= 0.0 else 0
		if state == "ko":
			koT += dt
			if koT > 1.1:
				state = "over"
				ts = 1.0
				win_label.text = NAMES[int(cfg[winner]["c"])] + " wins!"
				win_label.add_theme_color_override("font_color", _col(int(cfg[winner]["c"])))
				audio.play("win")
				show_screen("over")
		a.anim(sd, now)
		b.anim(sd, now)
	else:
		for f in fighters:
			f.t += dt
			f.anim(dt, now)


func _process(dt: float) -> void:
	_cam_upd(dt)
	if fighters.size() == 2:
		var a = fighters[0]
		var b = fighters[1]
		b0fill.anchor_right = clampf(float(a.hp) / 100.0, 0.0, 1.0)
		b1fill.anchor_left = 1.0 - clampf(float(b.hp) / 100.0, 0.0, 1.0)
		d0.text = str(int(ceil(float(a.hp))))
		d1.text = str(int(ceil(float(b.hp))))
		for j in 3:
			var n: String = CD_ORDER[j]
			var fl: float = 1.0 - clampf(float(a.cd[n]) / float(a.cd_max[n]), 0.0, 1.0)
			(cd_l[j] as ColorRect).anchor_right = fl
			var fr: float = 1.0 - clampf(float(b.cd[n]) / float(b.cd_max[n]), 0.0, 1.0)
			(cd_r[j] as ColorRect).anchor_left = 1.0 - fr
	if show_fps:
		fight_t += dt
		if fight_t >= 0.5:
			fight_t = 0.0
			fps.text = str(Engine.get_frames_per_second()) + " FPS"


func _cam_upd(dt: float) -> void:
	var in_fight := state == "play" or state == "count" or state == "ko" or state == "pause" or state == "over"
	var tg := Vector3(0, 0.5, 0)
	var D := 30.0
	var dir := Vector3.ZERO
	if in_fight and fighters.size() == 2:
		var p0: Vector3 = fighters[0].position
		var p1: Vector3 = fighters[1].position
		var v0: Vector3 = fighters[0].v
		var v1: Vector3 = fighters[1].v
		var sep := Vector2(p0.x - p1.x, p0.z - p1.z).length()
		av = av.lerp((v0 + v1) * 0.5, 1.0 - exp(-3.0 * dt))
		tg = Vector3((p0.x + p1.x) * 0.5, 0.5, (p0.z + p1.z) * 0.5) + av * 0.35
		var vp := get_viewport().get_visible_rect().size
		D = minf(30.0, 20.0 + sep * 0.9) * maxf(1.0, 1.3 / maxf(vp.x / maxf(vp.y, 1.0), 0.1))
		dir = Vector3(1, 0.95, 1).normalized()
	else:
		orbit += dt * 0.12
		av = av.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * dt))
		D = 24.0 if state == "select" else 30.0
		dir = Vector3(cos(orbit + 0.8), 0.9, sin(orbit + 0.8)).normalized()
	zD = lerpf(zD, D, 1.0 - exp(-3.0 * dt))
	var goal := tg + dir * zD
	cp = cp.lerp(goal, 1.0 - exp(-4.0 * dt))
	look = look.lerp(tg, 1.0 - exp(-5.0 * dt))
	cam.position = cp
	if shake > 0.0:
		cam.position.x += randf_range(-0.5, 0.5) * shake
		cam.position.y += randf_range(-0.5, 0.5) * shake
		shake = maxf(0.0, shake - dt * 1.2)
	cam.look_at(look)


# ---------- UI ----------

func _style(bg: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _btn(parent: Control, text: String, action: String, green: bool = false, i: int = -1, v: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	var sb := _style(Color(0.25, 0.68, 0.3) if green else Color(1.0, 0.54, 0.24))
	b.add_theme_stylebox_override("normal", sb)
	b.set_meta("action", action)
	b.set_meta("i", i)
	b.set_meta("v", v)
	b.pressed.connect(_on_action.bind(b))
	parent.add_child(b)
	return b


func _panel() -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	return vb


func _screen(sname: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	add_child(c)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(cc)
	var pc := PanelContainer.new()
	var sb := _style(Color(1.0, 0.98, 0.93, 0.93), 18)
	sb.shadow_size = 8
	pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var vb := _panel()
	pc.add_child(vb)
	screens[sname] = {"root": c, "box": vb}
	return c


func _title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.16, 0.48, 0.21))
	l.add_theme_constant_override("outline_size", maxi(2, size / 12))
	return l


func _build_ui() -> void:
	# HUD
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	n0 = _hud_label(Vector2(18, 14), HORIZONTAL_ALIGNMENT_LEFT)
	n1 = _hud_label(Vector2(-398, 14), HORIZONTAL_ALIGNMENT_RIGHT, true)
	d0 = _hud_num(Vector2(18, 40), HORIZONTAL_ALIGNMENT_LEFT)
	d1 = _hud_num(Vector2(-398, 40), HORIZONTAL_ALIGNMENT_RIGHT, true)
	_bar(false)
	_bar(true)
	_cd_pips(false)
	_cd_pips(true)
	cd = Label.new()
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.add_theme_font_size_override("font_size", 120)
	cd.add_theme_color_override("font_color", Color.WHITE)
	cd.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	cd.add_theme_constant_override("outline_size", 10)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cd)
	fps = Label.new()
	fps.text = "-- FPS"
	fps.add_theme_font_size_override("font_size", 15)
	fps.add_theme_color_override("font_color", Color.WHITE)
	var fbg := _style(Color(0, 0, 0, 0.4), 8)
	fps.add_theme_stylebox_override("normal", fbg)
	fps.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fps.position = Vector2(-110, -40)
	hud.add_child(fps)
	# menu
	_screen("menu")
	var mb: VBoxContainer = screens["menu"]["box"]
	mb.add_child(_title_label("BLOCK BRAWL", 96))
	_btn(mb, "Play local 1v1", "play", true)
	_btn(mb, "Settings", "set")
	# select
	_screen("select")
	var sb2: VBoxContainer = screens["select"]["box"]
	sb2.add_child(_title_label("SELECT", 48))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	sb2.add_child(row)
	sel_panels.clear()
	for i in 2:
		var vb := _panel()
		row.add_child(vb)
		sel_panels.append(vb)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	sb2.add_child(row2)
	_btn(row2, "Start match", "start", true)
	_btn(row2, "Back", "menu")
	var hint := Label.new()
	hint.text = "P1: WASD move, J light, K heavy, L dash-atk, O uppercut, P spin, Space dash. P2: arrows, ,/. attacks, Numpad3/4/5 specials, Shift or / dash. Esc pauses. Cooldowns: yellow=L, orange=O, purple=P."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	sb2.add_child(hint)
	# pause
	_screen("pause")
	var pb: VBoxContainer = screens["pause"]["box"]
	pb.add_child(_title_label("Paused", 40))
	_btn(pb, "Resume", "resume", true)
	_btn(pb, "Restart", "restart")
	_btn(pb, "Settings", "set")
	_btn(pb, "Main menu", "menu")
	# over
	_screen("over")
	var ob: VBoxContainer = screens["over"]["box"]
	win_label = _title_label("", 44)
	ob.add_child(win_label)
	_btn(ob, "Rematch", "restart", true)
	_btn(ob, "Main menu", "menu")
	# settings
	_screen("settings")
	var stb: VBoxContainer = screens["settings"]["box"]
	stb.add_child(_title_label("Settings", 40))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	stb.add_child(grid)
	var sv := _slider(grid, "Sound volume", 60)
	sv.value_changed.connect(func(_v: float) -> void: audio.vol = sv.value / 100.0)
	var ss := _slider(grid, "Screen shake", 60)
	ss.value_changed.connect(func(_v: float) -> void: shake_amt = ss.value / 100.0)
	_opt(grid)
	var sf := CheckBox.new()
	sf.text = "Show FPS"
	sf.button_pressed = true
	var sl := Label.new()
	sl.text = "Show FPS"
	grid.add_child(sl)
	grid.add_child(sf)
	sf.toggled.connect(func(on: bool) -> void: show_fps = on; fps.visible = on)
	_btn(stb, "Back", "back", true)


func _hud_label(off: Vector2, align: HorizontalAlignment, right: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(380, 26)
	if right:
		l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		l.position = Vector2(off.x, off.y)
	else:
		l.position = off
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l


func _hud_num(off: Vector2, align: HorizontalAlignment, right: bool = false) -> Label:
	var l := _hud_label(off, align, right)
	l.add_theme_font_size_override("font_size", 26)
	return l


func _bar(right: bool) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.custom_minimum_size = Vector2(380, 22)
	if right:
		bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bg.position = Vector2(-398, 72)
	else:
		bg.position = Vector2(18, 72)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color.BLUE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	if right:
		b1fill = fill
	else:
		b0fill = fill


func _cd_pips(right: bool) -> void:
	for j in 3:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.45)
		bg.custom_minimum_size = Vector2(120, 10)
		if right:
			bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			bg.position = Vector2(-398 + j * 128, 100)
		else:
			bg.position = Vector2(18 + j * 128, 100)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(bg)
		var fill := ColorRect.new()
		fill.color = CD_COLS[j]
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		if right:
			cd_r.append(fill)
		else:
			cd_l.append(fill)


func _slider(grid: GridContainer, text: String, val: int) -> HSlider:
	var l := Label.new()
	l.text = text
	grid.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.value = val
	s.custom_minimum_size = Vector2(160, 0)
	grid.add_child(s)
	return s


func _opt(grid: GridContainer) -> void:
	var l := Label.new()
	l.text = "Graphics"
	grid.add_child(l)
	var o := OptionButton.new()
	o.add_item("Low", 0)
	o.add_item("Medium", 1)
	o.add_item("High", 2)
	o.selected = 2
	grid.add_child(o)
	o.item_selected.connect(func(idx: int) -> void: quality = idx; apply_quality())


func apply_quality() -> void:
	vfx.set_cap([60, 100, 100][clampi(quality, 0, 2)])
	sun.shadow_enabled = quality > 0
	var sc: float = [0.85, 1.0, 1.0][clampi(quality, 0, 2)]
	get_viewport().set("scaling_3d_scale", sc)


func show_screen(sname) -> void:
	for k in screens:
		(screens[k]["root"] as Control).visible = k == sname
	hud.visible = state == "play" or state == "count" or state == "ko" or state == "pause" or state == "over"


func to_menu() -> void:
	state = "menu"
	_pv()
	show_screen("menu")


func rs() -> void:
	for i in 2:
		var vb: VBoxContainer = sel_panels[i]
		for ch in vb.get_children():
			ch.queue_free()
		var c: Dictionary = cfg[i]
		var t := Label.new()
		t.text = "Player " + str(i + 1)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", 22)
		vb.add_child(t)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(row)
		for j in 6:
			var b := Button.new()
			b.custom_minimum_size = Vector2(34, 34)
			var sb := _style(_col(j), 8)
			if int(c["c"]) == j:
				sb.border_width_left = 3
				sb.border_width_right = 3
				sb.border_width_top = 3
				sb.border_width_bottom = 3
				sb.border_color = Color.WHITE
			b.add_theme_stylebox_override("normal", sb)
			b.set_meta("action", "col")
			b.set_meta("i", i)
			b.set_meta("v", str(j))
			b.pressed.connect(_on_action.bind(b))
			row.add_child(b)
		_btn(vb, "Hat: " + HATS[int(c["h"])], "hat", false, i)
		_btn(vb, "Visor: " + ("on" if int(c["g"]) == 1 else "off"), "gl", false, i)


func _on_action(b: Button) -> void:
	var a := String(b.get_meta("action"))
	var i := int(b.get_meta("i"))
	if a == "play":
		state = "select"
		rs()
		_pv()
		show_screen("select")
	elif a == "col":
		var v := int(b.get_meta("v"))
		cfg[i]["c"] = v
		while int(cfg[1 - i]["c"]) == int(cfg[i]["c"]):
			cfg[1 - i]["c"] = (int(cfg[1 - i]["c"]) + 1) % 6
		rs()
		_pv()
	elif a == "hat":
		cfg[i]["h"] = (int(cfg[i]["h"]) + 1) % HATS.size()
		rs()
		_pv()
	elif a == "gl":
		cfg[i]["g"] = 1 - int(cfg[i]["g"])
		rs()
		_pv()
	elif a == "start" or a == "restart":
		start_match()
	elif a == "menu":
		to_menu()
	elif a == "resume":
		toggle_pause()
	elif a == "set":
		from = "pause" if state == "pause" else "menu"
		show_screen("settings")
	elif a == "back":
		show_screen(from)
