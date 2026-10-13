extends VBoxContainer
## Attack Animator editor: tweak every attack pose per character.
## Lives inside bb_main "anim" screen. Edits bb_fighter.ANIM_OV live,
## saves to user://anim_overrides.json.

const FighterScript = preload("res://bb_fighter.gd")

const KINDS := ["punch", "dash", "upper", "spin", "fan", "rifle", "counter", "bash", "sweep"]
const PHASES := ["Windup", "Active", "Recover"]
const FIELDS := [
	{"id": "lean", "label": "Body Lean X", "min": -1.5, "max": 1.5},
	{"id": "sq", "label": "Body Squash", "min": -0.4, "max": 0.5},
	{"id": "twist", "label": "Body Twist Y", "min": -1.5, "max": 1.5},
	{"id": "e0", "label": "Hand L Extend", "min": -1.5, "max": 2.0},
	{"id": "e1", "label": "Hand R Extend", "min": -1.5, "max": 2.0},
	{"id": "u0", "label": "Hand L Up", "min": -1.5, "max": 2.0},
	{"id": "u1", "label": "Hand R Up", "min": -1.5, "max": 2.0},
	{"id": "arm_scale", "label": "Hands Scale", "min": -0.5, "max": 1.0},
	{"id": "sword_rx", "label": "Weapon Rot X", "min": -3.0, "max": 3.0},
	{"id": "sword_ry", "label": "Weapon Rot Y", "min": -3.0, "max": 3.0},
	{"id": "sword_s", "label": "Weapon Scale", "min": -0.5, "max": 1.5},
	{"id": "shield_x", "label": "Shield Off X", "min": -1.0, "max": 1.0},
	{"id": "shield_y", "label": "Shield Off Y", "min": -1.0, "max": 1.0},
	{"id": "shield_z", "label": "Shield Off Z", "min": -1.0, "max": 1.0},
	{"id": "shield_s", "label": "Shield Scale", "min": -0.5, "max": 1.5},
]

var game = null
var skin_opt: OptionButton = null
var kind_opt: OptionButton = null
var phase_opt: OptionButton = null
var status_lab: Label = null
var sliders := {}
var previewing := false
var _pv_t := 0.0


func build(p_game) -> void:
	game = p_game
	FighterScript.load_anim_ovs()
	# top selectors
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)
	skin_opt = OptionButton.new()
	for s in game.SKINS:
		skin_opt.add_item(str(s))
	skin_opt.selected = 0
	skin_opt.item_selected.connect(func(_i: int) -> void: _refresh_sliders(); _restart_preview())
	top.add_child(skin_opt)
	kind_opt = OptionButton.new()
	for k in KINDS:
		kind_opt.add_item(k)
	kind_opt.selected = 0
	kind_opt.item_selected.connect(func(_i: int) -> void: _refresh_sliders(); _restart_preview())
	top.add_child(kind_opt)
	phase_opt = OptionButton.new()
	for p in PHASES:
		phase_opt.add_item(p)
	phase_opt.selected = 1
	phase_opt.item_selected.connect(func(_i: int) -> void: _refresh_sliders())
	top.add_child(phase_opt)
	var pv := Button.new()
	pv.text = "Preview"
	pv.pressed.connect(_restart_preview)
	top.add_child(pv)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(stop_preview)
	top.add_child(stop)
	# sliders grid: label | slider | value
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for f in FIELDS:
		var fd: Dictionary = f
		var lab := Label.new()
		lab.text = str(fd["label"])
		lab.custom_minimum_size = Vector2(130, 0)
		grid.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = float(fd["min"])
		sl.max_value = float(fd["max"])
		sl.step = 0.01
		sl.value = 0.0
		sl.custom_minimum_size = Vector2(260, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(sl)
		var val := Label.new()
		val.text = "0.00"
		val.custom_minimum_size = Vector2(50, 0)
		grid.add_child(val)
		var fid := str(fd["id"])
		sl.value_changed.connect(_on_slider.bind(fid, val))
		sliders[fid] = sl
	# bottom row
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_theme_constant_override("separation", 8)
	add_child(bot)
	var save_b := Button.new()
	save_b.text = "Save"
	save_b.pressed.connect(_on_save)
	bot.add_child(save_b)
	var load_b := Button.new()
	load_b.text = "Load"
	load_b.pressed.connect(_on_load)
	bot.add_child(load_b)
	var rst := Button.new()
	rst.text = "Reset Pose"
	rst.pressed.connect(_on_reset_pose)
	bot.add_child(rst)
	var rst_all := Button.new()
	rst_all.text = "Reset All"
	rst_all.pressed.connect(_on_reset_all)
	bot.add_child(rst_all)
	status_lab = Label.new()
	status_lab.text = "Pick skin + attack + phase, drag sliders, Preview loops it."
	add_child(status_lab)
	_refresh_sliders()


func _cur() -> Array:
	var sk := str(game.SKINS[skin_opt.selected % game.SKINS.size()])
	return [sk, KINDS[kind_opt.selected % KINDS.size()], phase_opt.selected]


func _on_slider(v: float, fid: String, val_lab: Label) -> void:
	var c: Array = _cur()
	val_lab.text = "%.2f" % v
	FighterScript.set_anim_ov(str(c[0]), str(c[1]), int(c[2]), fid, v)


func _refresh_sliders() -> void:
	var c: Array = _cur()
	var ov: Dictionary = FighterScript.get_anim_ov(str(c[0]), str(c[1]), int(c[2]))
	for f in FIELDS:
		var fid := str((f as Dictionary)["id"])
		var sl: HSlider = sliders[fid]
		sl.set_value_no_signal(float(ov.get(fid, 0.0)))
		# update sibling value label
		var grid: GridContainer = sl.get_parent() as GridContainer
		var idx: int = sl.get_index()
		var val_lab: Label = grid.get_child(idx + 1) as Label
		val_lab.text = "%.2f" % sl.value
	status_lab.text = "%s | %s | %s" % [str(c[0]), str(c[1]), str(PHASES[int(c[2])])]


func _preview_atk(kind: String) -> Dictionary:
	var big := kind in ["spin", "bash", "sweep", "rifle", "upper"]
	return {"w": 0.35, "a": 0.45, "r": 0.55, "kind": kind, "big": big,
		"range": 2.4, "arc": 0.3, "radial": kind == "spin"}


func _restart_preview() -> void:
	if game == null or game.fighters.is_empty():
		return
	var c: Array = _cur()
	var f = game.fighters[0]
	f.setup_skin(str(c[0]))
	f.position = Vector3(0, 0, 1.5)
	f.ang = 0.0
	f.face = Vector3(0, 0, 1)
	f.rotation.y = 0.0
	f.st = "atk"
	f.atk = _preview_atk(str(c[1]))
	f.t = 0.0
	previewing = true
	_pv_t = 0.0


func stop_preview() -> void:
	previewing = false
	if game != null and not game.fighters.is_empty():
		var f = game.fighters[0]
		f.st = "free"
		f.atk = null


func _process(dt: float) -> void:
	if not previewing or game == null:
		return
	if String(game.state) != "anim":
		return
	if game.fighters.is_empty():
		return
	var f = game.fighters[0]
	# keep looping the selected attack so sliders apply live
	var want_kind: String = KINDS[kind_opt.selected % KINDS.size()]
	var want_skin := str(game.SKINS[skin_opt.selected % game.SKINS.size()])
	if f.skin_name != want_skin:
		_restart_preview()
		return
	if f.st != "atk" or f.atk == null or String(f.atk.get("kind", "")) != want_kind:
		_restart_preview()
		return
	var atk: Dictionary = f.atk
	var total: float = float(atk.get("w", 0.35)) + float(atk.get("a", 0.45)) + float(atk.get("r", 0.55))
	if float(f.t) >= total:
		f.t = 0.0


func _on_save() -> void:
	FighterScript.save_anim_ovs()
	status_lab.text = "Saved to user://anim_overrides.json"


func _on_load() -> void:
	FighterScript.load_anim_ovs()
	_refresh_sliders()
	status_lab.text = "Loaded from user://anim_overrides.json"


func _on_reset_pose() -> void:
	var c: Array = _cur()
	FighterScript.clear_anim_ov(str(c[0]), str(c[1]), int(c[2]))
	_refresh_sliders()
	status_lab.text = "Pose reset"


func _on_reset_all() -> void:
	FighterScript.ANIM_OV.clear()
	FighterScript.save_anim_ovs()
	_refresh_sliders()
	status_lab.text = "All poses reset"
