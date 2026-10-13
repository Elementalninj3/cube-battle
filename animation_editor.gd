extends Node3D
## Custom 3D animation + attack editor for CUBE BOX.
## Run as its own scene (animation_editor.tscn), independent of gameplay.
## Layout is Blender-inspired: top header bar, left Outliner (parts),
## right Properties panel, bottom Timeline with a dope sheet (one row per
## part, frame ruler, marker lane), and a status/hints bar at the bottom.
##
## Key facts about the existing characters (see bb_fighter.gd):
## - There is NO Skeleton3D and NO AnimationPlayer. Fighters are procedural:
##   Fighter(model(arm_l, arm_r, hat_root, skin glb), sword/shield on the arms)
##   and bb_fighter.anim() overwrites those Node3D transforms every frame.
## - So this editor manipulates the REAL nodes (arms, body, sword, shield...)
##   directly, stores keyframed pos/rot/scale per part in JSON, and previews by
##   driving a dedicated preview fighter that never runs the combat anim().
## - Clips are saved to res://animations/<skin>/<name>.json plus a real Godot
##   Animation .tres (for AnimationPlayer use). Gameplay can optionally map an
##   attack kind to a clip via attack_map.json; damage/knockback/cooldowns and
##   input mappings are never touched by the editor.

const FighterScript = preload("res://bb_fighter.gd")
const Clip = preload("res://animations/anim_clip.gd")

const SKINS := ["cubeknight", "cubecowboy"]
const ATTACK_KINDS := ["punch", "dash", "upper", "spin", "fan", "rifle",
	"counter", "bash", "sweep"]
const PART_LABELS := {
	"model": "Body", "arm_l": "Arm L", "arm_r": "Arm R",
	"sword": "Sword", "shield": "Shield", "hat": "Hat", "skin": "Skin Mesh",
	"gun": "Revolver", "rifle": "Rifle",
}
const ATTACK_MAP_PATH := "res://animations/attack_map.json"
# What the GAME code does around each attack kind (poses are baked from the
# real procedural animation; damage/VFX/timing always stay in game code).
const KIND_NOTES := {
	"punch": "Game: strike + damage at windup end, forward lunge. Heavy shares this clip with longer timing.",
	"counter": "Game: shield flash on start; counter window = windup+active; riposte on catch.",
	"bash": "Game: forward rush at windup end, shield impact + streaks.",
	"sweep": "Game: crescent VFX trail during active, damage check mid-active.",
	"fan": "Game: 6 projectiles across active, muzzle flash per shot.",
	"rifle": "Game: one heavy projectile at windup end + recoil kick.",
	"dash": "Legacy generic dash attack (no skin triggers it; assign manually to use).",
	"upper": "Legacy generic uppercut (unmapped by default).",
	"spin": "Legacy generic spinning attack (unmapped by default).",
}
const CAM_CFG_PATH := "user://editor_camera.cfg"
# Blender-like theme.
const COL_PANEL := Color(0.16, 0.165, 0.18, 0.95)
const COL_HEADER := Color(0.12, 0.125, 0.14, 0.97)
const COL_ACCENT := Color(0.28, 0.45, 0.7)
const COL_TEXT_DIM := Color(0.62, 0.64, 0.68)
const CHAN_COLS := {"pos": Color(0.45, 0.85, 0.45), "rot": Color(0.95, 0.8, 0.3),
	"scl": Color(0.45, 0.6, 1.0)}

# ---------- state ----------
var skin := "cubeknight"
var clip := {}
var clip_file := "" # full res:// path of the loaded clip, "" = new/unsaved
var base_pose := {} # part -> {pos, rot(deg), scl}
var part_nodes := {} # part -> Node3D
var part_order: Array = []
var selected_part := "arm_r"
var hidden := {} # part -> true (outliner visibility, like Blender's eye)
var cur_time := 0.0
var play_dir := 0 # -1 reverse, 0 stopped, +1 forward (Blender-style transport)
var fps := 30.0 # display/editing framerate (clips store seconds, Blender shows frames)
var snap_on := true # snap new/moved keys to frames
var sel_key_channel := "rot"
var sel_key_time := -1.0
var clipboard := {} # {channel, key:[t,x,y,z]}
var gizmo_mode := "move" # move | rotate
var axis_lock := "free" # free | x | y | z
var show_hitbox := true
var ui_maximized := false # Tab: viewport fills the window (Blender Ctrl+Space)
var _dirty := false
var undo_stack: Array = []
var redo_stack: Array = []
var chan_on := {"pos": true, "rot": true, "scl": true}

# camera rig
var cam: Camera3D
var cam_yaw := 0.7
var cam_pitch := 0.45
var cam_dist := 6.0
var cam_target := Vector3(0, 0.9, 0)
# configurable zoom (Editor Camera settings, persisted when enabled)
var cam_default_dist := 6.0
var cam_sens := 6.0
var cam_min_dist := 1.5
var cam_max_dist := 25.0
var cam_invert := false
var cam_remember := true
var auto_key := true
var _drag_part := false
var _drag_start_pos := Vector3.ZERO
var _drag_start_rot := Vector3.ZERO
var _drag_accum := Vector2.ZERO
var _press_pos := Vector2.ZERO

# scene nodes
var fighter = null
var gizmo_mesh: ImmediateMesh
var gizmo_mi: MeshInstance3D
var overlay_mesh: ImmediateMesh
var overlay_mi: MeshInstance3D
var ground_mi: MeshInstance3D

# ui refs
var ui: CanvasLayer
var skin_opt: OptionButton
var anim_opt: OptionButton
var name_edit: LineEdit
var outliner_box: VBoxContainer
var time_slider: HSlider
var frame_spin: SpinBox
var fps_spin: SpinBox
var snap_check: CheckButton
var frame_label: Label
var key_bar: Control
var key_info: Label
var spin_pos := []
var spin_rot := []
var spin_scl := []
var mode_buttons := []
var axis_buttons := []
var status_label: Label
var title_label: Label
var dur_spin: SpinBox
var speed_spin: SpinBox
var loop_check: CheckButton
var interp_opt: OptionButton
var cat_opt: OptionButton
var windup_spin: SpinBox
var active_spin: SpinBox
var hbon_spin: SpinBox
var hboff_spin: SpinBox
var dmg_spin: SpinBox
var vfx_spin: SpinBox
var atk_speed_spin: SpinBox
var rec_spin: SpinBox
var assign_opt: OptionButton
var map_label: Label
var kind_note_label: Label
var left_pc: PanelContainer
var right_pc: PanelContainer
var timeline_pc: PanelContainer
var saved_badge: Label
var help_dialog: AcceptDialog
var confirm_dialog: ConfirmationDialog
var _pending_confirm := Callable()
# fixed 1152x648-viewport fix: saved project stretch modes, restored on exit
var _saved_scale_mode := -1
var _saved_scale_aspect := -1


class TimelineBar extends Control:
	var ed = null
	func _draw() -> void:
		if ed != null:
			ed.draw_timeline(self)
	func _gui_input(event: InputEvent) -> void:
		if ed != null:
			ed.timeline_input(event)


func _ready() -> void:
	_apply_editor_stretch()
	_load_camera_cfg()
	_build_stage()
	_build_ui()
	_load_attack_map()
	_select_skin("cubeknight", true)


func _exit_tree() -> void:
	if _saved_scale_mode >= 0:
		get_tree().root.set("content_scale_mode", _saved_scale_mode)
	if _saved_scale_aspect >= 0:
		get_tree().root.set("content_scale_aspect", _saved_scale_aspect)


func _apply_editor_stretch() -> void:
	# The project uses canvas_items stretch (game default 1152x648). That mode
	# keeps the root viewport FIXED at the project size and only scales it, so
	# the editor felt "stuck at 1152x648" and overflowed on small windows.
	# The editor needs real pixels, so opt this scene out while it is open.
	# Gameplay scenes are untouched (modes are restored in _exit_tree).
	var root_win := get_tree().root
	_saved_scale_mode = int(root_win.get("content_scale_mode"))
	_saved_scale_aspect = int(root_win.get("content_scale_aspect"))
	root_win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


# ================= STAGE =================

func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.75, 1.0)
	fill.light_energy = 0.4
	fill.rotation = Vector3(-0.3, -2.2, 0.0)
	add_child(fill)
	_build_ground()
	gizmo_mesh = ImmediateMesh.new()
	gizmo_mi = MeshInstance3D.new()
	gizmo_mi.mesh = gizmo_mesh
	gizmo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gizmo_mi.material_override = _line_mat()
	gizmo_mi.extra_cull_margin = 50.0
	add_child(gizmo_mi)
	overlay_mesh = ImmediateMesh.new()
	overlay_mi = MeshInstance3D.new()
	overlay_mi.mesh = overlay_mesh
	overlay_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay_mi.material_override = _line_mat()
	overlay_mi.extra_cull_margin = 50.0
	add_child(overlay_mi)
	_update_camera()


func _line_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground_mi = MeshInstance3D.new()
	ground_mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.25)
	mat.roughness = 0.9
	ground_mi.material_override = mat
	add_child(ground_mi)
	var grid_mesh := ImmediateMesh.new()
	var grid_mi := MeshInstance3D.new()
	grid_mi.mesh = grid_mesh
	grid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	grid_mi.material_override = gm
	grid_mi.position.y = 0.01
	add_child(grid_mi)
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var gc := Color(0.4, 0.42, 0.48)
	for i in range(-10, 11):
		grid_mesh.surface_set_color(gc)
		grid_mesh.surface_add_vertex(Vector3(i, 0, -10))
		grid_mesh.surface_set_color(gc)
		grid_mesh.surface_add_vertex(Vector3(i, 0, 10))
		grid_mesh.surface_set_color(gc)
		grid_mesh.surface_add_vertex(Vector3(-10, 0, i))
		grid_mesh.surface_set_color(gc)
		grid_mesh.surface_add_vertex(Vector3(10, 0, i))
	grid_mesh.surface_end()


func _spawn_fighter() -> void:
	if fighter != null and is_instance_valid(fighter):
		fighter.queue_free()
		fighter = null
	part_nodes.clear()
	part_order.clear()
	base_pose.clear()
	hidden.clear()
	fighter = FighterScript.new()
	add_child(fighter)
	fighter.setup_skin(skin)
	fighter.position = Vector3.ZERO
	fighter.rotation = Vector3.ZERO
	# Map editable parts to live nodes. Anything missing is simply skipped:
	# the game has no skeleton, so parts == these Node3Ds (least disruptive).
	_register_part("model", fighter.model)
	_register_part("arm_l", fighter.arm_l)
	_register_part("arm_r", fighter.arm_r)
	_register_part("hat", fighter.hat_root)
	if fighter.sword_node != null:
		_register_part("sword", fighter.sword_node)
	if fighter.shield_node != null:
		_register_part("shield", fighter.shield_node)
	if fighter.skin_inst != null:
		_register_part("skin", fighter.skin_inst)
	if fighter.get("gun_node") != null and fighter.gun_node != null:
		_register_part("gun", fighter.gun_node)
	if fighter.get("rifle_node") != null and fighter.rifle_node != null:
		_register_part("rifle", fighter.rifle_node)
	if not part_nodes.has(selected_part):
		selected_part = "arm_r" if part_nodes.has("arm_r") else str(part_order[0])
	_apply_rest_pose()
	_apply_vis()


func _register_part(pname: String, n: Node3D) -> void:
	if n == null:
		return
	part_nodes[pname] = n
	part_order.append(pname)
	base_pose[pname] = {
		"pos": n.position,
		"rot": Vector3(rad_to_deg(n.rotation.x), rad_to_deg(n.rotation.y), rad_to_deg(n.rotation.z)),
		"scl": n.scale,
	}


func _part_node(pname: String) -> Node3D:
	return part_nodes.get(pname, null)


func _is_hidden(pname: String) -> bool:
	return bool(hidden.get(pname, false))


func _apply_vis() -> void:
	for p in part_nodes.keys():
		var n := _part_node(str(p))
		if n != null:
			n.visible = not _is_hidden(str(p))


# ================= UI HELPERS =================

func _mk_button(parent: Control, text: String, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _mk_spin(parent: Control, minv: float, maxv: float, step: float, val: float, tip: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.tooltip_text = tip
	s.custom_minimum_size = Vector2(90, 0)
	parent.add_child(s)
	return s


func _mk_label(parent: Control, text: String, size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _hscroll(inner: Control) -> ScrollContainer:
	# Keeps wide toolbars reachable on narrow windows: scrolls only on overflow.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if inner.get_parent() != null:
		inner.get_parent().remove_child(inner)
	sc.add_child(inner)
	return sc


func _panel_box(bg: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	return pc


func _section(vb: VBoxContainer, title: String) -> void:
	var l := Label.new()
	l.text = title.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0))
	vb.add_child(l)
	var sep := HSeparator.new()
	vb.add_child(sep)


var _root_box: HBoxContainer = null


# ================= UI BUILD =================

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var main := VBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_theme_constant_override("separation", 2)
	root.add_child(main)
	main.add_child(_build_header())
	# middle row: outliner | 3D viewport | properties
	_root_box = HBoxContainer.new()
	_root_box.add_theme_constant_override("separation", 2)
	_root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_root_box)
	left_pc = _panel_box(COL_PANEL)
	left_pc.custom_minimum_size = Vector2(236, 0)
	_root_box.add_child(left_pc)
	var lvb := VBoxContainer.new()
	lvb.add_theme_constant_override("separation", 4)
	left_pc.add_child(lvb)
	_build_outliner(lvb)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(60, 0)
	_root_box.add_child(spacer)
	right_pc = _panel_box(COL_PANEL)
	right_pc.custom_minimum_size = Vector2(304, 0)
	_root_box.add_child(right_pc)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pc.add_child(scroll)
	var rvb := VBoxContainer.new()
	rvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rvb.add_theme_constant_override("separation", 4)
	scroll.add_child(rvb)
	_build_props(rvb)
	timeline_pc = _panel_box(COL_HEADER)
	main.add_child(timeline_pc)
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 2)
	timeline_pc.add_child(tvb)
	_build_timeline(tvb)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	main.add_child(status_label)
	var hints := Label.new()
	hints.text = "LMB-drag orbit · wheel zoom · RMB pan · click part to select · Shift+LMB-drag transform | G/R move/rotate · X/Y/Z axis · Esc clear | K add key · Del delete key · Left/Right prev/next key · Up/Down first/last | Space play · F focus · V hide · Tab maximize view · F11 fullscreen"
	hints.add_theme_font_size_override("font_size", 11)
	hints.add_theme_color_override("font_color", COL_TEXT_DIM)
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(hints)
	_build_dialogs()


func _build_dialogs() -> void:
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Unsaved changes"
	confirm_dialog.confirmed.connect(_on_confirm_ok)
	ui.add_child(confirm_dialog)
	help_dialog = AcceptDialog.new()
	help_dialog.title = "Animation Editor Help"
	help_dialog.dialog_text = "WORKFLOW (pose - key - preview - save):\n" \
		+ "1. Pick a Character and an Animation up top.\n" \
		+ "2. Click a part in the Outliner (or click it in 3D).\n" \
		+ "3. Pose it: Shift+LMB-drag in 3D, or type numbers in Transform.\n" \
		+ "4. With Auto-Key ON the pose is keyed automatically, else press Add Key [K].\n" \
		+ "5. Scrub the dope sheet / press Space to preview.\n" \
		+ "6. Save writes the file the GAME loads (mapped kinds play it).\n\n" \
		+ "BAKE FROM GAME (Clip menu) re-records the real procedural attack\n" \
		+ "into this clip, so editor and game can never drift apart.\n\n" \
		+ "Damage, hitboxes and cooldowns live in game code and are never\n" \
		+ "changed by posing. Markers only annotate timing."
	help_dialog.dialog_autowrap = true
	ui.add_child(help_dialog)


func _show_help() -> void:
	help_dialog.popup_centered(Vector2i(560, 430))


func _confirm_or_do(text: String, action: Callable) -> void:
	if _dirty and action.is_valid():
		_pending_confirm = action
		confirm_dialog.dialog_text = text + "\nUnsaved changes will be lost."
		confirm_dialog.popup_centered()
	elif action.is_valid():
		action.call()


func _on_confirm_ok() -> void:
	if _pending_confirm.is_valid():
		var a := _pending_confirm
		_pending_confirm = Callable()
		a.call()


func _on_clip_menu(id: int) -> void:
	match id:
		0:
			_on_new_btn()
		1:
			_on_duplicate()
		2:
			_on_rename()
		3:
			_on_delete_btn()
		4:
			_on_bake_from_game()
		5:
			_on_reload_disk()


func _on_view_menu(id: int) -> void:
	match id:
		0:
			_on_camera_preset("Front")
		1:
			_on_camera_preset("Right")
		2:
			_on_camera_preset("Top")
		3:
			_on_camera_preset("3/4")
		4:
			_on_camera_preset("Iso")
		5:
			_on_focus_part()
		6:
			_reset_view()
		7:
			_reset_zoom()
		8:
			_apply_rest_pose()
			_sync_transform_ui()
			_set_status("Pose reset to the animation start (keys untouched).")


func _on_new_btn() -> void:
	_confirm_or_do("Create a new animation?", Callable(self, "_on_new"))


func _on_back_btn() -> void:
	_confirm_or_do("Leave the editor and return to the game?", Callable(self, "_on_back"))


func _on_delete_btn() -> void:
	if clip_file == "":
		_set_status("Nothing to delete (clip was never saved).", true)
		return
	_pending_confirm = Callable(self, "_do_delete")
	confirm_dialog.dialog_text = "Delete " + clip_file + " from disk?\nThis cannot be undone."
	confirm_dialog.popup_centered()


func _on_rename() -> void:
	var target := name_edit.text.strip_edges().replace(" ", "_").to_lower()
	if target.is_empty():
		_set_status("Type the new name in the Name field first.", true)
		return
	if target == str(clip.get("name", "")):
		_set_status("That is already the clip name.")
		return
	var old_file := clip_file
	var old_name := str(clip.get("name", ""))
	clip["name"] = target
	clip_file = ""
	_on_save(true) # Save-As rules: never silently overwrites
	if old_file != "" and old_file != clip_file:
		if FileAccess.file_exists(old_file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old_file))
		var old_res := Clip.anim_res_path(skin, old_name)
		if FileAccess.file_exists(old_res):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old_res))
	_refresh_anim_list(target)
	_set_status("Renamed to '" + target + "'.")


func _build_header() -> Control:
	var top := _panel_box(COL_HEADER)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	top.add_child(rows)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 5)
	tb.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(_hscroll(tb))
	title_label = Label.new()
	title_label.text = "Anim Editor"
	title_label.add_theme_font_size_override("font_size", 15)
	tb.add_child(title_label)
	saved_badge = Label.new()
	saved_badge.add_theme_font_size_override("font_size", 12)
	tb.add_child(saved_badge)
	tb.add_child(VSeparator.new())
	skin_opt = OptionButton.new()
	skin_opt.tooltip_text = "Character to edit (real game model)"
	for s in SKINS:
		skin_opt.add_item(s)
	skin_opt.item_selected.connect(_on_skin_selected)
	tb.add_child(skin_opt)
	anim_opt = OptionButton.new()
	anim_opt.tooltip_text = "Clip to edit (res://animations/<char>/*.json)"
	anim_opt.item_selected.connect(_on_anim_selected)
	tb.add_child(anim_opt)
	tb.add_child(VSeparator.new())
	var save_b := _mk_button(tb, "Save", "Save into the loaded animation file")
	save_b.pressed.connect(_on_save.bind(false))
	var undo_b := _mk_button(tb, "Undo", "Ctrl+Z")
	undo_b.pressed.connect(_on_undo)
	var redo_b := _mk_button(tb, "Redo", "Ctrl+Y")
	redo_b.pressed.connect(_on_redo)
	var play_b := _mk_button(tb, "Play", "Play / pause (Space)")
	play_b.pressed.connect(_on_transport.bind("play"))
	var stop_b := _mk_button(tb, "Stop", "Stop playback")
	stop_b.pressed.connect(_on_transport.bind("stop"))
	tb.add_child(VSeparator.new())
	var clip_menu := MenuButton.new()
	clip_menu.text = "Clip"
	clip_menu.tooltip_text = "Animation actions: new, duplicate, rename, delete, bake, reload"
	clip_menu.focus_mode = Control.FOCUS_NONE
	tb.add_child(clip_menu)
	var cpop := clip_menu.get_popup()
	cpop.add_item("New", 0)
	cpop.add_item("Duplicate", 1)
	cpop.add_item("Rename...", 2)
	cpop.add_item("Delete...", 3)
	cpop.add_separator()
	cpop.add_item("Bake from Game", 4)
	cpop.add_item("Reload from Disk", 5)
	cpop.id_pressed.connect(_on_clip_menu)
	# (row 2 holds mode/axis/view controls; built at the end of this function)
	var back_b := _mk_button(tb, "Back", "Return to block_brawl.tscn")
	back_b.pressed.connect(_on_back_btn)
	# second slim row: transform mode, axis, view, panel toggles
	var tb2 := HBoxContainer.new()
	tb2.add_theme_constant_override("separation", 5)
	tb2.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(_hscroll(tb2))
	var mv := _mk_button(tb2, "Move [G]", "Transform mode: move (Shift+LMB-drag)")
	mv.toggle_mode = true
	mv.pressed.connect(_set_gizmo_mode.bind("move"))
	var rt := _mk_button(tb2, "Rotate [R]", "Transform mode: rotate (Shift+LMB-drag)")
	rt.toggle_mode = true
	rt.pressed.connect(_set_gizmo_mode.bind("rotate"))
	var mode_group := ButtonGroup.new()
	mv.button_group = mode_group
	rt.button_group = mode_group
	mv.button_pressed = true
	mode_buttons = [mv, rt]
	tb2.add_child(VSeparator.new())
	var axis_group := ButtonGroup.new()
	for a in ["free", "x", "y", "z"]:
		var b := _mk_button(tb2, a.to_upper(), "Axis lock [" + a.to_upper() + "]")
		b.toggle_mode = true
		b.button_group = axis_group
		b.pressed.connect(_set_axis.bind(a))
		axis_buttons.append(b)
		if a == "free":
			b.button_pressed = true
	tb2.add_child(VSeparator.new())
	var view_menu := MenuButton.new()
	view_menu.text = "View"
	view_menu.tooltip_text = "Camera presets, framing, camera reset"
	view_menu.focus_mode = Control.FOCUS_NONE
	tb2.add_child(view_menu)
	var vpop := view_menu.get_popup()
	vpop.add_item("Front", 0)
	vpop.add_item("Right", 1)
	vpop.add_item("Top", 2)
	vpop.add_item("3/4", 3)
	vpop.add_item("Iso (game camera)", 4)
	vpop.add_separator()
	vpop.add_item("Frame Character", 5)
	vpop.add_item("Reset View", 6)
	vpop.add_item("Reset Camera Zoom", 7)
	vpop.add_item("Reset Pose", 8)
	vpop.id_pressed.connect(_on_view_menu)
	var parts_b := _mk_button(tb2, "Parts", "Show/hide the Character Parts panel")
	parts_b.toggle_mode = true
	parts_b.button_pressed = true
	parts_b.focus_mode = Control.FOCUS_NONE
	parts_b.toggled.connect(func(on: bool) -> void: left_pc.visible = on)
	var props_b := _mk_button(tb2, "Props", "Show/hide the Transform panel")
	props_b.toggle_mode = true
	props_b.button_pressed = true
	props_b.focus_mode = Control.FOCUS_NONE
	props_b.toggled.connect(func(on: bool) -> void: right_pc.visible = on)
	var max_b := _mk_button(tb2, "Max [Tab]", "Maximize the 3D viewport (hide panels)")
	max_b.pressed.connect(_toggle_maximize)
	var full_b := _mk_button(tb2, "Full [F11]", "Toggle fullscreen window")
	full_b.pressed.connect(_toggle_fullscreen)
	var help_b := _mk_button(tb2, "?", "How to use the animation editor")
	help_b.pressed.connect(_show_help)
	return top


func _build_outliner(vb: VBoxContainer) -> void:
	_section(vb, "Outliner")
	_mk_label(vb, "Parts of the real model. Eye = visibility.", 11).add_theme_color_override("font_color", COL_TEXT_DIM)
	outliner_box = VBoxContainer.new()
	outliner_box.add_theme_constant_override("separation", 2)
	vb.add_child(outliner_box)


func _build_props(rvb: VBoxContainer) -> void:
	_section(rvb, "Transform (selected part)")
	var ak := CheckButton.new()
	ak.text = "Auto-Key (pose edits create keys)"
	ak.tooltip_text = "ON: every pose change is keyed at the current frame. OFF: use Add Key [K]."
	ak.button_pressed = true
	rvb.add_child(ak)
	ak.toggled.connect(func(on: bool) -> void: auto_key = on)
	spin_pos = _spin_row(rvb, -5.0, 5.0, 0.01, _on_pos_edited, "Location")
	spin_rot = _spin_row(rvb, -180.0, 180.0, 0.5, _on_rot_edited, "Rotation (deg)")
	spin_scl = _spin_row(rvb, 0.05, 5.0, 0.01, _on_scl_edited, "Scale")
	var trow := HBoxContainer.new()
	rvb.add_child(trow)
	var rst := _mk_button(trow, "Reset Part", "Restore this part's original pose")
	rst.pressed.connect(_on_reset_part)
	var rest := _mk_button(trow, "Rest Pose", "Return whole character to original pose")
	rest.pressed.connect(func() -> void: _apply_rest_pose(); _sync_transform_ui())
	var foc := _mk_button(trow, "Focus [F]", "Move camera target to selected part")
	foc.pressed.connect(_on_focus_part)
	_section(rvb, "Clip")
	_mk_label(rvb, "Name:")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "clip_name"
	rvb.add_child(name_edit)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	rvb.add_child(grid)
	_mk_label(grid, "Duration (s)")
	dur_spin = _mk_spin(grid, 0.1, 10.0, 0.05, 1.0, "Animation length in seconds")
	dur_spin.value_changed.connect(_on_duration_changed)
	_mk_label(grid, "Preview speed")
	speed_spin = _mk_spin(grid, 0.1, 3.0, 0.05, 1.0, "Editor playback speed multiplier")
	speed_spin.value_changed.connect(_on_clip_field.bind("speed"))
	_mk_label(grid, "Attack speed")
	atk_speed_spin = _mk_spin(grid, 0.1, 3.0, 0.05, 1.0, "Gameplay playback speed for this attack")
	atk_speed_spin.value_changed.connect(_on_clip_field.bind("playback_speed"))
	_mk_label(grid, "Recovery (s)")
	rec_spin = _mk_spin(grid, 0.0, 3.0, 0.05, 0.3, "Extra recovery time after the attack")
	rec_spin.value_changed.connect(_on_clip_field.bind("recovery"))
	_mk_label(grid, "Category")
	cat_opt = OptionButton.new()
	for c in Clip.CATEGORIES:
		cat_opt.add_item(c)
	cat_opt.item_selected.connect(_on_category_selected)
	grid.add_child(cat_opt)
	_mk_label(grid, "Interpolation")
	interp_opt = OptionButton.new()
	for c in Clip.INTERPS:
		interp_opt.add_item(c)
	interp_opt.item_selected.connect(_on_interp_selected)
	grid.add_child(interp_opt)
	loop_check = CheckButton.new()
	loop_check.text = "Loop playback"
	grid.add_child(loop_check)
	loop_check.toggled.connect(_on_loop_toggled)
	var hb := CheckButton.new()
	hb.text = "Hitbox overlay"
	hb.button_pressed = true
	grid.add_child(hb)
	hb.toggled.connect(func(on: bool) -> void: show_hitbox = on)
	_section(rvb, "Attack phases / markers (s, -1 = none)")
	var grid2 := GridContainer.new()
	grid2.columns = 2
	grid2.add_theme_constant_override("h_separation", 6)
	rvb.add_child(grid2)
	_mk_label(grid2, "Windup end")
	windup_spin = _mk_spin(grid2, 0.0, 10.0, 0.05, 0.3)
	windup_spin.value_changed.connect(_on_clip_field.bind("windup_end"))
	_mk_label(grid2, "Active end")
	active_spin = _mk_spin(grid2, 0.0, 10.0, 0.05, 0.65)
	active_spin.value_changed.connect(_on_clip_field.bind("active_end"))
	_mk_label(grid2, "Hitbox on")
	hbon_spin = _mk_spin(grid2, 0.0, 10.0, 0.05, 0.3)
	hbon_spin.value_changed.connect(_on_clip_field.bind("hitbox_on"))
	_mk_label(grid2, "Hitbox off")
	hboff_spin = _mk_spin(grid2, 0.0, 10.0, 0.05, 0.65)
	hboff_spin.value_changed.connect(_on_clip_field.bind("hitbox_off"))
	_mk_label(grid2, "Damage event")
	dmg_spin = _mk_spin(grid2, -1.0, 10.0, 0.05, -1.0, "-1 = no damage marker")
	dmg_spin.value_changed.connect(_on_clip_field.bind("damage_time"))
	_mk_label(grid2, "VFX marker")
	vfx_spin = _mk_spin(grid2, -1.0, 10.0, 0.05, -1.0, "-1 = no VFX marker")
	vfx_spin.value_changed.connect(_on_clip_field.bind("vfx_time"))
	_section(rvb, "Editor Camera (this editor only)")
	_mk_label(rvb, "Wheel zoom. Never affects the gameplay camera.", 11).add_theme_color_override("font_color", COL_TEXT_DIM)
	var cgrid := GridContainer.new()
	cgrid.columns = 2
	cgrid.add_theme_constant_override("h_separation", 6)
	rvb.add_child(cgrid)
	_mk_label(cgrid, "Default zoom")
	var def_spin := _mk_spin(cgrid, 1.5, 25.0, 0.5, cam_default_dist, "Distance used when the editor opens or resets")
	def_spin.value_changed.connect(func(v: float) -> void: cam_default_dist = v; _save_camera_cfg())
	_mk_label(cgrid, "Zoom speed")
	var sens_spin := _mk_spin(cgrid, 1.0, 10.0, 0.5, cam_sens, "Mouse-wheel zoom sensitivity")
	sens_spin.value_changed.connect(func(v: float) -> void: cam_sens = v; _save_camera_cfg())
	_mk_label(cgrid, "Min zoom")
	var min_spin := _mk_spin(cgrid, 0.8, 10.0, 0.1, cam_min_dist, "Closest allowed camera distance")
	min_spin.value_changed.connect(func(v: float) -> void: cam_min_dist = minf(v, cam_max_dist); _save_camera_cfg())
	_mk_label(cgrid, "Max zoom")
	var max_spin := _mk_spin(cgrid, 5.0, 60.0, 1.0, cam_max_dist, "Furthest allowed camera distance")
	max_spin.value_changed.connect(func(v: float) -> void: cam_max_dist = maxf(v, cam_min_dist); _save_camera_cfg())
	var inv := CheckButton.new()
	inv.text = "Invert wheel"
	inv.button_pressed = cam_invert
	cgrid.add_child(inv)
	inv.toggled.connect(func(on: bool) -> void: cam_invert = on; _save_camera_cfg())
	var rem := CheckButton.new()
	rem.text = "Remember zoom"
	rem.tooltip_text = "Keep your zoom between sessions (user://editor_camera.cfg)"
	rem.button_pressed = cam_remember
	cgrid.add_child(rem)
	rem.toggled.connect(_on_remember_toggled)
	var zrow := HBoxContainer.new()
	rvb.add_child(zrow)
	var zrst := _mk_button(zrow, "Reset Camera Zoom", "Restore default zoom (pose untouched)")
	zrst.pressed.connect(_reset_zoom)
	_section(rvb, "Use in game (optional)")
	_mk_label(rvb, "Never changes damage. Empty map = procedural.", 11).add_theme_color_override("font_color", COL_TEXT_DIM)
	var assign_row := HBoxContainer.new()
	rvb.add_child(assign_row)
	assign_opt = OptionButton.new()
	for k in ATTACK_KINDS:
		assign_opt.add_item(k)
	assign_row.add_child(assign_opt)
	assign_opt.item_selected.connect(func(_i: int) -> void: _update_kind_note())
	var asg := _mk_button(assign_row, "Assign", "Play this clip for the attack kind in gameplay")
	asg.pressed.connect(_on_assign)
	var clr := _mk_button(assign_row, "Unassign", "Remove the gameplay mapping")
	clr.pressed.connect(_on_unassign)
	map_label = Label.new()
	map_label.add_theme_font_size_override("font_size", 12)
	map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rvb.add_child(map_label)
	var brow := HBoxContainer.new()
	rvb.add_child(brow)
	var bake_b := _mk_button(brow, "Bake from Game", "Re-record the REAL procedural attack into this clip (game -> editor)")
	bake_b.pressed.connect(_on_bake_from_game)
	var rel_b := _mk_button(brow, "Reload", "Reload this clip from disk")
	rel_b.pressed.connect(_on_reload_disk)
	kind_note_label = Label.new()
	kind_note_label.add_theme_font_size_override("font_size", 12)
	kind_note_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	kind_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rvb.add_child(kind_note_label)


func _spin_row(vb: VBoxContainer, minv: float, maxv: float, step: float, cb: Callable, tip: String) -> Array:
	_mk_label(vb, tip, 11).add_theme_color_override("font_color", COL_TEXT_DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	vb.add_child(row)
	var out: Array = []
	for i in range(3):
		var s := SpinBox.new()
		s.min_value = minv
		s.max_value = maxv
		s.step = step
		s.custom_minimum_size = Vector2(0, 0)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.focus_mode = Control.FOCUS_ALL
		row.add_child(s)
		s.focus_entered.connect(_push_undo)
		s.value_changed.connect(cb.bind(i))
		out.append(s)
	return out


func _build_timeline(vb: VBoxContainer) -> void:
	# transport row (Blender timeline header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["|<<", "First frame (Up)", "_on_transport", "first"],
			["<K", "Previous keyframe (Left)", "_on_transport", "prevkey"],
			["Rev", "Play reverse", "_on_transport", "rev"],
			["Play", "Play / pause (Space)", "_on_transport", "play"],
			["Stop", "Stop", "_on_transport", "stop"],
			["K>", "Next keyframe (Right)", "_on_transport", "nextkey"],
			[">>|", "Last frame (Down)", "_on_transport", "last"]]:
		var b := _mk_button(row, str(spec[0]), str(spec[1]))
		b.pressed.connect(Callable(self, str(spec[2])).bind(str(spec[3])))
	frame_label = Label.new()
	frame_label.text = "F 1/1"
	row.add_child(frame_label)
	_mk_label(row, "Frame:")
	frame_spin = SpinBox.new()
	frame_spin.min_value = 1
	frame_spin.max_value = 1
	frame_spin.step = 1
	frame_spin.custom_minimum_size = Vector2(70, 0)
	frame_spin.tooltip_text = "Current frame (Blender-style)"
	row.add_child(frame_spin)
	frame_spin.value_changed.connect(_on_frame_changed)
	_mk_label(row, "FPS:")
	fps_spin = _mk_spin(row, 1.0, 120.0, 1.0, 30.0, "Timeline framerate (display + key snapping only)")
	fps_spin.custom_minimum_size = Vector2(60, 0)
	fps_spin.value_changed.connect(_on_fps_changed)
	snap_check = CheckButton.new()
	snap_check.text = "Snap"
	snap_check.tooltip_text = "Snap new/moved keys to frames"
	snap_check.button_pressed = true
	row.add_child(snap_check)
	snap_check.toggled.connect(func(on: bool) -> void: snap_on = on)
	vb.add_child(_hscroll(row))
	# key editing row
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	var add_b := _mk_button(row2, "Add Key [K]", "Keyframe selected part at current frame")
	add_b.pressed.connect(_on_add_key)
	var del_b := _mk_button(row2, "Del Key", "Delete selected keyframe (Del)")
	del_b.pressed.connect(_on_delete_key)
	var copy_b := _mk_button(row2, "Copy", "Copy selected keyframe")
	copy_b.pressed.connect(_on_copy_key)
	var paste_b := _mk_button(row2, "Paste", "Paste at current frame")
	paste_b.pressed.connect(_on_paste_key)
	var move_b := _mk_button(row2, "Move Here", "Move selected key to current frame")
	move_b.pressed.connect(_on_move_key_here)
	_mk_label(row2, "Channels:")
	for ch in ["pos", "rot", "scl"]:
		var cb := CheckButton.new()
		cb.text = ch
		cb.button_pressed = true
		cb.tooltip_text = "Key/show the " + ch + " channel"
		cb.toggled.connect(_on_channel_toggled.bind(ch))
		row2.add_child(cb)
	vb.add_child(_hscroll(row2))
	time_slider = HSlider.new()
	time_slider.min_value = 0.0
	time_slider.step = 0.001
	time_slider.value_changed.connect(_on_scrub)
	vb.add_child(time_slider)
	key_bar = TimelineBar.new()
	(key_bar as TimelineBar).ed = self
	vb.add_child(key_bar)
	key_info = Label.new()
	key_info.add_theme_font_size_override("font_size", 12)
	key_info.add_theme_color_override("font_color", COL_TEXT_DIM)
	vb.add_child(key_info)


# ================= CLIP I/O =================

func _ensure_defaults(p_skin: String) -> void:
	if not Clip.list_clips(p_skin).is_empty():
		return
	for c in Clip.default_clips(p_skin):
		Clip.save_json(Clip.clip_path(p_skin, str(c["name"])), c)


func _refresh_anim_list(select_name: String = "") -> void:
	anim_opt.clear()
	var names := Clip.list_clips(skin)
	for n in names:
		anim_opt.add_item(str(n))
	if names.is_empty():
		return
	var idx := names.find(select_name)
	if idx < 0:
		idx = names.find(str(clip.get("name", "")))
	if idx < 0:
		idx = 0
	anim_opt.selected = idx


func _load_clip(skin_name: String, clip_name: String, keep_undo := false) -> void:
	var path := Clip.clip_path(skin_name, clip_name)
	var loaded := Clip.load_json(path)
	if loaded.is_empty():
		_set_status("Could not load " + path, true)
		return
	if keep_undo:
		_push_undo()
	clip = loaded
	clip_file = path
	cur_time = 0.0
	play_dir = 0
	sel_key_time = -1.0
	undo_stack.clear()
	redo_stack.clear()
	_dirty = false
	_sync_clip_ui()
	_apply_at(cur_time)
	_set_status("Loaded " + path + " (editing a copy until you Save).")


func _current_names() -> Array:
	return Clip.list_clips(skin)


func _on_reload_disk() -> void:
	if clip_file == "":
		_set_status("Nothing to reload (clip was never saved).", true)
		return
	var fname := clip_file.get_file().get_basename()
	_confirm_or_do("Reload '" + fname + "' from disk?", _load_clip.bind(skin, fname, true))


func _on_save(save_as: bool) -> void:
	var target_name := name_edit.text.strip_edges()
	if target_name.is_empty():
		target_name = str(clip.get("name", "untitled"))
	target_name = target_name.replace(" ", "_").to_lower()
	clip["name"] = target_name
	clip["skin"] = skin
	var path := Clip.clip_path(skin, target_name)
	if not save_as and clip_file != "" and clip_file != path:
		path = clip_file # plain Save keeps editing the loaded file
		target_name = str(clip.get("name", target_name))
	if FileAccess.file_exists(path) and (save_as or path != clip_file):
		# Never silently overwrite: Save As to an existing name appends a suffix.
		var i := 2
		while FileAccess.file_exists(Clip.clip_path(skin, target_name + "_" + str(i))):
			i += 1
		target_name = target_name + "_" + str(i)
		clip["name"] = target_name
		path = Clip.clip_path(skin, target_name)
	var err := Clip.save_json(path, clip)
	if err != OK:
		_set_status("Save failed: " + path + " (" + error_string(err) + ")", true)
		return
	# Godot-compatible Animation resource alongside the JSON.
	var anim := Clip.to_animation(clip)
	var rerr := ResourceSaver.save(anim, Clip.anim_res_path(skin, target_name))
	clip_file = path
	_dirty = false
	_refresh_anim_list(target_name)
	_sync_clip_ui()
	if rerr == OK:
		_set_status("Saved " + path + " + .tres Animation.")
	else:
		_set_status("Saved " + path + " (JSON ok, .tres warn: " + error_string(rerr) + ").")


func _on_new() -> void:
	_push_undo()
	clip = Clip.new_clip("new_attack", skin, 1.0)
	clip_file = ""
	cur_time = 0.0
	play_dir = 0
	sel_key_time = -1.0
	_dirty = true
	_sync_clip_ui()
	_apply_at(0.0)
	_set_status("New unsaved clip. Type a Name, then Save As.")


func _on_duplicate() -> void:
	_push_undo()
	var src: String = str(clip.get("name", "clip"))
	clip = JSON.parse_string(JSON.stringify(clip))
	clip["name"] = src + "_copy"
	clip_file = ""
	_dirty = true
	_sync_clip_ui()
	_set_status("Duplicated as unsaved '" + str(clip["name"]) + "'. Save As to keep it.")


func _do_delete() -> void:
	if clip_file == "":
		_set_status("Nothing to delete (clip was never saved).", true)
		return
	var path := clip_file
	var res_path := Clip.anim_res_path(skin, str(clip.get("name", "")))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(res_path) or ResourceLoader.exists(res_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(res_path))
	clip_file = ""
	_dirty = true
	_refresh_anim_list()
	if anim_opt.item_count > 0:
		_load_clip(skin, anim_opt.get_item_text(0))
	else:
		_on_new()
	_set_status("Deleted " + path)


# ================= UNDO =================

func _snapshot() -> String:
	return JSON.stringify(clip)


func _push_undo() -> void:
	undo_stack.append(_snapshot())
	if undo_stack.size() > 60:
		undo_stack.pop_front()
	redo_stack.clear()


func _restore(snapshot: String) -> void:
	var parsed = JSON.parse_string(snapshot)
	if parsed is Dictionary:
		clip = Clip._sanitize(parsed)
		_dirty = true
		_sync_clip_ui()
		_apply_at(cur_time)


func _on_undo() -> void:
	if undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	redo_stack.append(_snapshot())
	_restore(str(undo_stack.pop_back()))
	_set_status("Undo.")


func _on_redo() -> void:
	if redo_stack.is_empty():
		_set_status("Nothing to redo.")
		return
	undo_stack.append(_snapshot())
	_restore(str(redo_stack.pop_back()))
	_set_status("Redo.")


# ================= FRAMES =================

func _clip_len() -> float:
	return maxf(float(clip.get("length", 1.0)), 0.01)


func _total_frames() -> int:
	return maxi(1, roundi(_clip_len() * fps))


func _t_to_f(t: float) -> int:
	return clampi(int(round(t * fps)) + 1, 1, _total_frames())


func _f_to_t(fr: int) -> float:
	return clampf(float(clampi(fr, 1, _total_frames()) - 1) / fps, 0.0, _clip_len())


func _snap_t(t: float) -> float:
	var c := clampf(t, 0.0, _clip_len())
	if snap_on:
		c = snappedf(roundf(c * fps) / fps, 0.0001)
	return c


func _on_frame_changed(fr: float) -> void:
	play_dir = 0
	_seek(_f_to_t(int(fr)))


func _on_fps_changed(v: float) -> void:
	fps = clampf(v, 1.0, 120.0)
	_apply_at(cur_time)


# ================= SELECTION / POSE =================

func _on_outliner_selected(pname: String) -> void:
	_select_part_by_name(pname)


func _select_part_by_name(pname: String) -> void:
	if not part_nodes.has(pname):
		return
	selected_part = pname
	sel_key_time = -1.0
	_sync_outliner_sel()
	_sync_transform_ui()
	key_bar.queue_redraw()
	_update_key_info()


func _sync_part_list() -> void:
	for c in outliner_box.get_children():
		c.queue_free()
	for p in part_order:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		outliner_box.add_child(row)
		var b := Button.new()
		b.text = str(PART_LABELS.get(p, p))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Select " + str(PART_LABELS.get(p, p)) + " (or click it in 3D)"
		b.pressed.connect(_on_outliner_selected.bind(p))
		b.set_meta("part", p)
		row.add_child(b)
		var eye := CheckButton.new()
		eye.button_pressed = not _is_hidden(p)
		eye.tooltip_text = "Visible in viewport"
		eye.focus_mode = Control.FOCUS_NONE
		eye.toggled.connect(_on_vis_toggled.bind(p))
		row.add_child(eye)
	key_bar.custom_minimum_size = Vector2(0, 34 + 16 * part_order.size())
	_select_part_by_name(selected_part)


func _sync_outliner_sel() -> void:
	for row in outliner_box.get_children():
		var b := (row as HBoxContainer).get_child(0) as Button
		b.set_pressed_no_signal(str(b.get_meta("part")) == selected_part)


func _on_vis_toggled(on: bool, pname: String) -> void:
	if on:
		hidden.erase(pname)
	else:
		hidden[pname] = true
	_apply_vis()


func _toggle_vis_selected() -> void:
	var pname := selected_part
	if _is_hidden(pname):
		hidden.erase(pname)
	else:
		hidden[pname] = true
	_apply_vis()
	_sync_part_list()
	_set_status(("Shown: " if _is_hidden(pname) == false else "Hidden: ") + pname)


func _sync_transform_ui() -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	_set_spins(spin_pos, n.position)
	_set_spins(spin_rot, Vector3(rad_to_deg(n.rotation.x), rad_to_deg(n.rotation.y), rad_to_deg(n.rotation.z)))
	_set_spins(spin_scl, n.scale)


func _set_spins(spins: Array, v: Vector3) -> void:
	var vals := [v.x, v.y, v.z]
	for i in range(3):
		(spins[i] as SpinBox).set_value_no_signal(vals[i])


func _on_pos_edited(val: float, axis: int) -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	var p := n.position
	if axis == 0:
		p.x = val
	elif axis == 1:
		p.y = val
	else:
		p.z = val
	n.position = p
	_dirty = true
	_preview_key_hint()
	_auto_key()


func _on_rot_edited(val: float, axis: int) -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	var e := Vector3(rad_to_deg(n.rotation.x), rad_to_deg(n.rotation.y), rad_to_deg(n.rotation.z))
	if axis == 0:
		e.x = val
	elif axis == 1:
		e.y = val
	else:
		e.z = val
	n.rotation = Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))
	_dirty = true
	_preview_key_hint()
	_auto_key()


func _on_scl_edited(val: float, axis: int) -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	var s := n.scale
	if axis == 0:
		s.x = val
	elif axis == 1:
		s.y = val
	else:
		s.z = val
	n.scale = s
	_dirty = true
	_preview_key_hint()
	_auto_key()


func _preview_key_hint() -> void:
	key_info.text = "Pose edited (not yet keyed). Press Add Key [K] to store frame %d." % _t_to_f(cur_time)


func _on_reset_part() -> void:
	_push_undo()
	var n := _part_node(selected_part)
	var b: Dictionary = base_pose.get(selected_part, {})
	if n == null or b.is_empty():
		return
	n.position = b["pos"]
	var r: Vector3 = b["rot"]
	n.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
	n.scale = b["scl"]
	_sync_transform_ui()
	_set_status("Part '" + selected_part + "' restored to original pose (keys untouched).")


func _on_focus_part() -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	cam_target = n.global_transform.origin
	cam_target.y = clampf(cam_target.y, 0.2, 2.5)
	_update_camera()
	_set_status("Camera focused on " + selected_part + ".")


func _apply_rest_pose() -> void:
	for p in part_nodes.keys():
		var n: Node3D = part_nodes[p]
		var b: Dictionary = base_pose.get(p, {})
		if n == null or b.is_empty():
			continue
		n.position = b["pos"]
		var r: Vector3 = b["rot"]
		n.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		n.scale = b["scl"]


func _apply_at(t: float) -> void:
	_apply_rest_pose()
	_sync_transform_ui()
	var pose := Clip.sample_pose(clip, t, base_pose)
	for p in pose.keys():
		var n := _part_node(str(p))
		if n == null:
			continue
		var d: Dictionary = pose[p]
		n.position = d["pos"]
		var r: Vector3 = d["rot"]
		n.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		n.scale = d["scl"]
	_sync_transform_ui()
	var total := _total_frames()
	frame_label.text = "%sF %d/%d - %.2fs/%.2fs" % ["|> " if play_dir > 0 else ("<| " if play_dir < 0 else ""), _t_to_f(t), total, t, _clip_len()]
	time_slider.max_value = _clip_len()
	time_slider.set_value_no_signal(t)
	frame_spin.max_value = total
	frame_spin.set_value_no_signal(_t_to_f(t))
	key_bar.queue_redraw()
	_update_key_info()


# ================= KEYFRAMES =================

func _part_tracks() -> Dictionary:
	if not (clip.get("tracks", {}) as Dictionary).has(selected_part):
		(clip["tracks"] as Dictionary)[selected_part] = {"pos": [], "rot": [], "scl": []}
	return (clip["tracks"] as Dictionary)[selected_part]


func _on_add_key() -> void:
	_push_undo()
	_key_current_pose()
	var t := _snap_t(cur_time)
	_set_status("Keyed '" + selected_part + "' at frame %d (t=%.3f)." % [_t_to_f(t), t])


func _auto_key() -> void:
	# Pose edits (gizmo drags, numeric fields) become keys automatically.
	if auto_key:
		_key_current_pose()


func _key_current_pose() -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	var tr := _part_tracks()
	var t := _snap_t(cur_time)
	if bool(chan_on["pos"]):
		_set_key(tr["pos"], t, n.position)
	if bool(chan_on["rot"]):
		_set_key(tr["rot"], t, Vector3(rad_to_deg(n.rotation.x), rad_to_deg(n.rotation.y), rad_to_deg(n.rotation.z)))
	if bool(chan_on["scl"]):
		_set_key(tr["scl"], t, n.scale)
	sel_key_time = t
	_dirty = true
	_apply_at(cur_time)


func _set_key(keys: Array, t: float, v: Vector3) -> void:
	for k in keys:
		if absf(float(k[0]) - t) < 0.004:
			k[1] = v.x
			k[2] = v.y
			k[3] = v.z
			return
	keys.append([t, v.x, v.y, v.z])
	keys.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


func _find_key(keys: Array, t: float) -> int:
	for i in range(keys.size()):
		if absf(float(keys[i][0]) - t) < 0.004:
			return i
	return -1


func _on_delete_key() -> void:
	if sel_key_time < 0.0:
		_set_status("No keyframe selected. Click a diamond in the dope sheet.", true)
		return
	_push_undo()
	var tr := _part_tracks()
	var ch: Array = tr.get(sel_key_channel, [])
	var idx := _find_key(ch, sel_key_time)
	if idx < 0:
		_set_status("Selected key not found in channel " + sel_key_channel + ".", true)
		return
	ch.remove_at(idx)
	sel_key_time = -1.0
	_dirty = true
	_apply_at(cur_time)
	_set_status("Keyframe deleted.")


func _on_copy_key() -> void:
	var tr := _part_tracks()
	var ch: Array = tr.get(sel_key_channel, [])
	var idx := _find_key(ch, sel_key_time)
	if idx < 0:
		_set_status("Select a keyframe first.", true)
		return
	clipboard = {"channel": sel_key_channel, "key": (ch[idx] as Array).duplicate()}
	_set_status("Copied " + sel_key_channel + " key at frame %d." % _t_to_f(sel_key_time))


func _on_paste_key() -> void:
	if clipboard.is_empty():
		_set_status("Clipboard empty.", true)
		return
	_push_undo()
	var tr := _part_tracks()
	var ch: String = str(clipboard["channel"])
	var k: Array = (clipboard["key"] as Array).duplicate()
	k[0] = _snap_t(cur_time)
	_set_key(tr[ch], float(k[0]), Vector3(float(k[1]), float(k[2]), float(k[3])))
	sel_key_channel = ch
	sel_key_time = float(k[0])
	_dirty = true
	_apply_at(cur_time)
	_set_status("Pasted at frame %d." % _t_to_f(cur_time))


func _on_move_key_here() -> void:
	var tr := _part_tracks()
	var ch: Array = tr.get(sel_key_channel, [])
	var idx := _find_key(ch, sel_key_time)
	if idx < 0:
		_set_status("Select a keyframe first.", true)
		return
	_push_undo()
	ch[idx][0] = _snap_t(cur_time)
	ch.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	sel_key_time = _snap_t(cur_time)
	_dirty = true
	_apply_at(cur_time)
	_set_status("Key moved to frame %d." % _t_to_f(cur_time))


func _step_key(dir: int) -> void:
	var times := _all_key_times()
	if times.is_empty():
		return
	if dir < 0:
		var best := -1.0
		for t in times:
			if t < cur_time - 0.004 and t > best:
				best = t
		if best >= 0.0:
			play_dir = 0
			_seek(best)
	else:
		for t in times:
			if t > cur_time + 0.004:
				play_dir = 0
				_seek(t)
				return


func _all_key_times() -> Array:
	# Across ALL parts (Blender-style global stepping).
	var out: Array = []
	var tracks: Dictionary = clip.get("tracks", {})
	for part in tracks.keys():
		var tr: Dictionary = tracks[part]
		for ch in ["pos", "rot", "scl"]:
			for k in (tr.get(ch, []) as Array):
				var t := float(k[0])
				var found := false
				for e in out:
					if absf(float(e) - t) < 0.004:
						found = true
						break
				if not found:
					out.append(t)
	out.sort()
	return out


func _seek(t: float) -> void:
	cur_time = clampf(t, 0.0, _clip_len())
	_apply_at(cur_time)


func _on_scrub(v: float) -> void:
	play_dir = 0
	_seek(v)


func _update_key_info() -> void:
	var tr: Dictionary = (clip.get("tracks", {}) as Dictionary).get(selected_part, {})
	var counts := []
	for ch in ["pos", "rot", "scl"]:
		counts.append(ch + ":" + str((tr.get(ch, []) as Array).size()))
	var sel := "none"
	if sel_key_time >= 0.0:
		var ch: Array = tr.get(sel_key_channel, [])
		var idx := _find_key(ch, sel_key_time)
		if idx >= 0:
			var k: Array = ch[idx]
			sel = "%s @ F%d = [t=%.3f, %.3f, %.3f, %.3f]" % [sel_key_channel,
				_t_to_f(sel_key_time), float(k[0]), float(k[1]), float(k[2]), float(k[3])]
		else:
			sel = "%s @ F%d" % [sel_key_channel, _t_to_f(sel_key_time)]
	key_info.text = "Part '%s' [%s]  selected key: %s" % [selected_part, ", ".join(counts), sel]


# ================= DOPE SHEET =================

const DOPE_GUTTER := 110.0
const DOPE_MARK_H := 14.0
const DOPE_RULER_H := 18.0
const DOPE_ROW_H := 16.0


func _dope_top() -> float:
	return DOPE_MARK_H + DOPE_RULER_H


func _time_to_x(bar: Control, t: float) -> float:
	var w := maxf(bar.size.x - DOPE_GUTTER, 10.0)
	return DOPE_GUTTER + clampf(t / _clip_len(), 0.0, 1.0) * w


func _x_to_time(bar: Control, x: float) -> float:
	var w := maxf(bar.size.x - DOPE_GUTTER, 10.0)
	return clampf((x - DOPE_GUTTER) / w, 0.0, 1.0) * _clip_len()


func draw_timeline(bar: Control) -> void:
	var w := bar.size.x
	var len := _clip_len()
	var font := bar.get_theme_default_font()
	var fs := 12
	bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(0.14, 0.145, 0.16))
	# phase bands across the whole sheet
	var wend := clampf(float(clip.get("windup_end", 0.3)) / len, 0.0, 1.0)
	var aend := clampf(float(clip.get("active_end", 0.65)) / len, 0.0, 1.0)
	var span := maxf(w - DOPE_GUTTER, 10.0)
	bar.draw_rect(Rect2(DOPE_GUTTER, 0, span * wend, bar.size.y), Color(1.0, 0.85, 0.2, 0.08))
	bar.draw_rect(Rect2(DOPE_GUTTER + span * wend, 0, span * (aend - wend), bar.size.y), Color(1.0, 0.15, 0.15, 0.12))
	bar.draw_rect(Rect2(DOPE_GUTTER + span * aend, 0, span * (1.0 - aend), bar.size.y), Color(1.0, 0.55, 0.15, 0.07))
	# marker lane: damage + vfx flags
	_draw_flag(bar, float(clip.get("damage_time", -1.0)), Color(1, 0.3, 0.3), "D", font, fs)
	_draw_flag(bar, float(clip.get("vfx_time", -1.0)), Color(0.4, 0.8, 1.0), "V", font, fs)
	bar.draw_string(font, Vector2(4, DOPE_MARK_H - 3), "markers", HORIZONTAL_ALIGNMENT_LEFT, DOPE_GUTTER - 8, fs, COL_TEXT_DIM)
	# frame ruler
	var total := _total_frames()
	var step := maxi(1, total / 12)
	for fr in range(1, total + 1):
		var t := _f_to_t(fr)
		var x := _time_to_x(bar, t)
		var major := (fr - 1) % step == 0
		bar.draw_line(Vector2(x, DOPE_MARK_H), Vector2(x, _dope_top() + bar.size.y), Color(1, 1, 1, 0.16 if major else 0.05))
		if major:
			bar.draw_string(font, Vector2(x + 2, DOPE_MARK_H + DOPE_RULER_H - 4), str(fr), HORIZONTAL_ALIGNMENT_LEFT, 40, fs, COL_TEXT_DIM)
	# hitbox window
	var hon := _time_to_x(bar, float(clip.get("hitbox_on", 0.0)))
	var hoff := _time_to_x(bar, float(clip.get("hitbox_off", 0.0)))
	bar.draw_line(Vector2(hon, _dope_top()), Vector2(hon, bar.size.y), Color.WHITE * 0.9, 2.0)
	bar.draw_line(Vector2(hoff, _dope_top()), Vector2(hoff, bar.size.y), Color.WHITE * 0.9, 2.0)
	# one row per part (Blender dope-sheet channels)
	var tracks: Dictionary = clip.get("tracks", {})
	var lane_dy := {"pos": 4.0, "rot": 8.0, "scl": 12.0}
	for ri in range(part_order.size()):
		var pname := str(part_order[ri])
		var ry := _dope_top() + ri * DOPE_ROW_H
		if pname == selected_part:
			bar.draw_rect(Rect2(0, ry, w, DOPE_ROW_H), Color(0.28, 0.45, 0.7, 0.25))
		bar.draw_line(Vector2(0, ry + DOPE_ROW_H), Vector2(w, ry + DOPE_ROW_H), Color(1, 1, 1, 0.07))
		bar.draw_string(font, Vector2(4, ry + DOPE_ROW_H - 3), str(PART_LABELS.get(pname, pname)), HORIZONTAL_ALIGNMENT_LEFT, DOPE_GUTTER - 8, fs,
			Color.WHITE if pname == selected_part else COL_TEXT_DIM)
		var tr: Dictionary = tracks.get(pname, {})
		for ch in ["pos", "rot", "scl"]:
			if not bool(chan_on[ch]):
				continue
			for k in (tr.get(ch, []) as Array):
				var x := _time_to_x(bar, float(k[0]))
				var y := ry + float(lane_dy[ch])
				var is_sel: bool = pname == selected_part and sel_key_channel == ch and absf(float(k[0]) - sel_key_time) < 0.005
				_draw_diamond(bar, Vector2(x, y), 5.0 if is_sel else 3.5,
					Color.WHITE if is_sel else (CHAN_COLS[ch] as Color))
	# playhead
	var px := _time_to_x(bar, cur_time)
	bar.draw_line(Vector2(px, 0), Vector2(px, bar.size.y), Color(0.4, 0.8, 1.0), 2.0)


func _draw_diamond(bar: Control, c: Vector2, s: float, col: Color) -> void:
	bar.draw_colored_polygon([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)], col)


func _draw_flag(bar: Control, t: float, col: Color, tag: String, font: Font, fs: int) -> void:
	if t < 0.0:
		return
	var x := _time_to_x(bar, t)
	bar.draw_line(Vector2(x, 1), Vector2(x, DOPE_MARK_H - 1), col, 2.0)
	bar.draw_string(font, Vector2(x + 3, DOPE_MARK_H - 3), tag, HORIZONTAL_ALIGNMENT_LEFT, 20, fs, col)


func timeline_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.position.y < _dope_top() or mb.position.x < DOPE_GUTTER:
				# ruler / gutter: seek, or select the row's part
				if mb.position.x < DOPE_GUTTER and mb.position.y >= _dope_top():
					var ri := int((mb.position.y - _dope_top()) / DOPE_ROW_H)
					if ri >= 0 and ri < part_order.size():
						_select_part_by_name(str(part_order[ri]))
					return
				play_dir = 0
				_seek(_x_to_time(key_bar, mb.position.x))
				return
			# diamonds first
			var tracks: Dictionary = clip.get("tracks", {})
			var best_part := ""
			var best_ch := ""
			var best_t := -1.0
			var best_d := 9.0
			for ri in range(part_order.size()):
				var pname := str(part_order[ri])
				var ry := _dope_top() + ri * DOPE_ROW_H
				var tr: Dictionary = tracks.get(pname, {})
				for ch in ["pos", "rot", "scl"]:
					var lane := {"pos": 4.0, "rot": 8.0, "scl": 12.0}
					var y: float = ry + float(lane[ch])
					for k in (tr.get(ch, []) as Array):
						var d := Vector2(_time_to_x(key_bar, float(k[0])), y).distance_to(mb.position)
						if d < best_d:
							best_d = d
							best_part = pname
							best_ch = ch
							best_t = float(k[0])
			if best_t >= 0.0:
				_select_part_by_name(best_part)
				sel_key_channel = best_ch
				sel_key_time = best_t
				_update_key_info()
				key_bar.queue_redraw()
			else:
				play_dir = 0
				_seek(_x_to_time(key_bar, mb.position.x))
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) and sel_key_time >= 0.0:
			var tr: Dictionary = (clip.get("tracks", {}) as Dictionary).get(selected_part, {})
			var ch: Array = tr.get(sel_key_channel, [])
			var idx := _find_key(ch, sel_key_time)
			if idx >= 0:
				if not _key_dragging:
					_push_undo()
					_key_dragging = true
				var nt := _snap_t(_x_to_time(key_bar, mm.position.x))
				ch[idx][0] = nt
				ch.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
				sel_key_time = nt
				_dirty = true
				_apply_at(cur_time)
		if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_key_dragging = false


var _key_dragging := false


# ================= TRANSPORT =================

func _on_transport(which: String) -> void:
	match which:
		"first":
			play_dir = 0
			_seek(0.0)
		"prevkey":
			_step_key(-1)
		"rev":
			play_dir = -1
			_apply_at(cur_time)
		"play":
			play_dir = 1 if play_dir != 1 else 0
			if play_dir == 1 and cur_time >= _clip_len() - 0.0001:
				_seek(0.0)
			_apply_at(cur_time)
		"stop":
			play_dir = 0
			_apply_at(cur_time)
		"nextkey":
			_step_key(1)
		"last":
			play_dir = 0
			_seek(_clip_len())


func _process(dt: float) -> void:
	_update_camera()
	if play_dir != 0:
		var len := _clip_len()
		cur_time += dt * float(clip.get("speed", 1.0)) * float(play_dir)
		if bool(clip.get("loop", true)):
			cur_time = fposmod(cur_time, len)
		elif cur_time >= len:
			cur_time = len
			play_dir = 0
		elif cur_time <= 0.0:
			cur_time = 0.0
			play_dir = 0
		_apply_at(cur_time)
	_draw_gizmo()
	_draw_overlay()


# ================= 3D INPUT =================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.physical_keycode == KEY_Z:
			_on_undo()
			return
		if k.ctrl_pressed and k.physical_keycode == KEY_Y:
			_on_redo()
			return
		match k.physical_keycode:
			KEY_SPACE:
				_on_transport("play")
			KEY_G:
				_set_gizmo_mode("move")
			KEY_R:
				_set_gizmo_mode("rotate")
			KEY_X:
				_set_axis("x")
			KEY_Y:
				_set_axis("y")
			KEY_Z:
				_set_axis("z")
			KEY_ESCAPE:
				_cancel_drag()
				_set_axis("free")
				play_dir = 0
				_apply_at(cur_time)
			KEY_K:
				_on_add_key()
			KEY_DELETE, KEY_BACKSPACE:
				_on_delete_key()
			KEY_LEFT:
				_step_key(-1)
			KEY_RIGHT:
				_step_key(1)
			KEY_UP:
				play_dir = 0
				_seek(0.0)
			KEY_DOWN:
				play_dir = 0
				_seek(_clip_len())
			KEY_F:
				_on_focus_part()
			KEY_V:
				_toggle_vis_selected()
			KEY_TAB:
				_toggle_maximize()
			KEY_F11:
				_toggle_fullscreen()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_cam(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_cam(1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.shift_pressed:
				_begin_drag(mb.position)
			elif mb.pressed:
				_press_pos = mb.position
			elif not mb.pressed:
				if _drag_part:
					_drag_part = false
					_dirty = true
					_sync_transform_ui()
					_auto_key()
				elif mb.position.distance_to(_press_pos) < 8.0:
					_pick_part(mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			pass # orbit handled via motion mask below
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_part:
			_drag_transform(mm)
		elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE \
				or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT and not mm.shift_pressed):
			cam_yaw -= mm.relative.x * 0.008
			cam_pitch = clampf(cam_pitch + mm.relative.y * 0.006, -0.2, 1.45)
		elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var s := cam_dist * 0.0016
			var right := cam.global_transform.basis.x
			var up := cam.global_transform.basis.y
			right.y = 0.0
			right = right.normalized()
			cam_target -= right * mm.relative.x * s
			cam_target += up * mm.relative.y * s * -1.0
			cam_target.y = clampf(cam_target.y, 0.0, 3.0)


func _begin_drag(_mouse: Vector2) -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	_drag_part = true
	_drag_accum = Vector2.ZERO
	_drag_start_pos = n.position
	_drag_start_rot = n.rotation
	_push_undo()


func _cancel_drag() -> void:
	if not _drag_part:
		return
	_drag_part = false
	var n := _part_node(selected_part)
	if n != null:
		n.position = _drag_start_pos
		n.rotation = _drag_start_rot
	if not undo_stack.is_empty():
		undo_stack.pop_back() # drop the entry pushed for this drag
	_sync_transform_ui()


func _pick_part(mouse: Vector2) -> void:
	var best := ""
	var best_d := 48.0
	for p in part_order:
		if _is_hidden(p):
			continue
		var n := _part_node(p)
		if n == null or not n.visible:
			continue
		if cam.is_position_behind(n.global_transform.origin):
			continue
		var sp := cam.unproject_position(n.global_transform.origin)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = p
	if best != "":
		_select_part_by_name(best)
		_set_status("Selected " + str(PART_LABELS.get(best, best)) + ".")


func _drag_transform(mm: InputEventMouseMotion) -> void:
	var n := _part_node(selected_part)
	if n == null:
		return
	_drag_accum += mm.relative
	if gizmo_mode == "move":
		# Convert the camera-plane drag into the parent's local space so
		# children (sword/shield on rotated arms) move where you drag them.
		var wpp := cam_dist * 0.0016
		var right := cam.global_transform.basis.x
		var up := cam.global_transform.basis.y
		var world := (right * mm.relative.x + up * -mm.relative.y) * wpp
		var par := n.get_parent() as Node3D
		var local := world
		if par != null:
			local = par.global_transform.basis.inverse() * world
		if axis_lock == "free":
			n.position = _drag_start_pos + _accum_local(par, mm, wpp)
		else:
			var ax := _axis_vec(axis_lock)
			n.position = _drag_start_pos + ax * local.dot(ax)
	else:
		if axis_lock == "free":
			n.rotation.y = _drag_start_rot.y + deg_to_rad(_drag_accum.x * 0.4)
			n.rotation.x = _drag_start_rot.x + deg_to_rad(_drag_accum.y * 0.4)
		else:
			var e := _drag_start_rot
			var d := deg_to_rad((_drag_accum.x - _drag_accum.y) * 0.4)
			if axis_lock == "x":
				n.rotation.x = e.x + d
			elif axis_lock == "y":
				n.rotation.y = e.y + d
			else:
				n.rotation.z = e.z + d
	_sync_transform_ui()


func _accum_local(par: Node3D, mm: InputEventMouseMotion, wpp: float) -> Vector3:
	# Total drag offset in the node's local space (accumulated, not per-event,
	# so fast drags don't drift from the grab point).
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var world := (right * _drag_accum.x + up * -_drag_accum.y) * wpp
	if par != null:
		return par.global_transform.basis.inverse() * world
	return world


func _axis_vec(a: String) -> Vector3:
	if a == "x":
		return Vector3.RIGHT
	if a == "y":
		return Vector3.UP
	return Vector3.BACK


func _set_gizmo_mode(m: String) -> void:
	gizmo_mode = m
	for b in mode_buttons:
		(b as Button).set_pressed_no_signal((b as Button).text.begins_with("Move") == (m == "move"))
	_set_status("Transform mode: " + m + " (Shift+LMB-drag in 3D).")


func _set_axis(a: String) -> void:
	axis_lock = a
	for b in axis_buttons:
		(b as Button).set_pressed_no_signal(str((b as Button).text).to_lower() == a)


# ================= FULLSCREEN / MAXIMIZE =================

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _toggle_maximize() -> void:
	ui_maximized = not ui_maximized
	left_pc.visible = not ui_maximized
	right_pc.visible = not ui_maximized
	timeline_pc.visible = not ui_maximized
	_set_status("Viewport " + ("maximized (Tab to restore)." if ui_maximized else "restored."))


func _zoom_cam(dir: int) -> void:
	# dir -1 = zoom in (wheel up), +1 = zoom out. Smooth, clamped, and never
	# touches the gameplay camera (this is the editor's own Camera3D).
	var f := 1.0 + clampf(cam_sens, 1.0, 10.0) * 0.015
	var inward := dir < 0
	if cam_invert:
		inward = not inward
	if inward:
		cam_dist = clampf(cam_dist / f, cam_min_dist, cam_max_dist)
	else:
		cam_dist = clampf(cam_dist * f, cam_min_dist, cam_max_dist)


func _reset_view() -> void:
	# Camera only: never touches the character pose or animation.
	cam_yaw = 0.7
	cam_pitch = 0.45
	cam_dist = cam_default_dist
	cam_target = Vector3(0, 0.9, 0)
	cam.fov = 40.0
	_update_camera()
	_set_status("Camera reset (pose untouched).")


func _reset_zoom() -> void:
	cam_dist = cam_default_dist
	_update_camera()
	_set_status("Camera zoom reset to %.1f (pose untouched)." % cam_default_dist)


func _on_remember_toggled(on: bool) -> void:
	cam_remember = on
	if on:
		_save_camera_cfg()
	else:
		if FileAccess.file_exists(CAM_CFG_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CAM_CFG_PATH))


func _load_camera_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CAM_CFG_PATH) != OK:
		return
	cam_default_dist = float(cfg.get_value("camera", "default_dist", 6.0))
	cam_sens = float(cfg.get_value("camera", "sensitivity", 6.0))
	cam_min_dist = float(cfg.get_value("camera", "min_dist", 1.5))
	cam_max_dist = float(cfg.get_value("camera", "max_dist", 25.0))
	cam_invert = bool(cfg.get_value("camera", "invert", false))
	cam_remember = bool(cfg.get_value("camera", "remember", true))
	if cam_remember:
		cam_dist = clampf(float(cfg.get_value("camera", "dist", cam_default_dist)),
			cam_min_dist, cam_max_dist)
	else:
		cam_dist = cam_default_dist


func _save_camera_cfg() -> void:
	if not cam_remember:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("camera", "default_dist", cam_default_dist)
	cfg.set_value("camera", "sensitivity", cam_sens)
	cfg.set_value("camera", "min_dist", cam_min_dist)
	cfg.set_value("camera", "max_dist", cam_max_dist)
	cfg.set_value("camera", "invert", cam_invert)
	cfg.set_value("camera", "remember", cam_remember)
	cfg.set_value("camera", "dist", cam_dist)
	cfg.save(CAM_CFG_PATH)


# ================= GIZMO + OVERLAY =================

func _draw_gizmo() -> void:
	gizmo_mesh.clear_surfaces()
	var n := _part_node(selected_part)
	if n == null or _is_hidden(selected_part):
		return
	var o := n.global_transform.origin
	var L := 0.55
	gizmo_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line(o, o + Vector3.RIGHT * L, Color(1, 0.25, 0.25))
	_line(o, o + Vector3.UP * L, Color(0.3, 1, 0.3))
	_line(o, o + Vector3.BACK * L, Color(0.35, 0.55, 1))
	var fp: Vector3 = fighter.position if fighter != null else Vector3.ZERO
	_circle(Vector3(fp.x, 0.02, fp.z), 0.8, Color(1, 1, 1, 0.5), gizmo_mesh)
	gizmo_mesh.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	gizmo_mesh.surface_set_color(c)
	gizmo_mesh.surface_add_vertex(a)
	gizmo_mesh.surface_set_color(c)
	gizmo_mesh.surface_add_vertex(b)


func _circle(c: Vector3, r: float, col: Color, mesh: ImmediateMesh, segs: int = 40) -> void:
	var prev := c + Vector3(r, 0, 0)
	for i in range(1, segs + 1):
		var a := TAU * float(i) / float(segs)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		mesh.surface_set_color(col)
		mesh.surface_add_vertex(prev)
		mesh.surface_set_color(col)
		mesh.surface_add_vertex(p)
		prev = p


func _draw_overlay() -> void:
	overlay_mesh.clear_surfaces()
	if not show_hitbox or fighter == null:
		return
	overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var fp: Vector3 = fighter.position
	var col := Color(1, 1, 1, 0.4)
	if cur_time < float(clip.get("windup_end", 0.3)):
		col = Color(1.0, 0.9, 0.2, 0.9)
	elif cur_time < float(clip.get("active_end", 0.65)):
		col = Color(1.0, 0.15, 0.15, 1.0)
	else:
		col = Color(1.0, 0.55, 0.15, 0.9)
	_circle(Vector3(fp.x, 0.05, fp.z), 2.4, col, overlay_mesh, 48)
	if cur_time >= float(clip.get("hitbox_on", 0.0)) and cur_time <= float(clip.get("hitbox_off", 0.0)):
		_circle(Vector3(fp.x, 0.9, fp.z), 0.75, Color(1, 0.2, 0.2), overlay_mesh, 24)
	_circle(Vector3(fp.x, 0.05, fp.z), 0.45, Color(0.2, 1, 0.35, 0.8), overlay_mesh, 20)
	if float(clip.get("damage_time", -1.0)) >= 0.0 and absf(cur_time - float(clip.get("damage_time", 0.0))) < 0.05:
		_circle(Vector3(fp.x, 1.2, fp.z), 0.5, Color(1, 0.3, 0.3), overlay_mesh, 20)
	overlay_mesh.surface_end()


func _on_camera_preset(preset: String) -> void:
	match preset:
		"Front":
			cam_yaw = 0.0
			cam_pitch = 0.15
			cam_dist = 5.5
			cam.fov = 40.0
		"Right":
			cam_yaw = PI * 0.5
			cam_pitch = 0.15
			cam_dist = 5.5
			cam.fov = 40.0
		"Top":
			cam_yaw = 0.0
			cam_pitch = 1.45
			cam_dist = 7.0
			cam.fov = 40.0
		"3/4":
			cam_yaw = 0.7
			cam_pitch = 0.45
			cam_dist = 5.5
			cam.fov = 40.0
		"Iso":
			# same angle as the game's isometric fight camera
			cam_yaw = PI * 0.25
			cam_pitch = 0.62
			cam_dist = 11.0
			cam.fov = 28.0
	_update_camera()


func _update_camera() -> void:
	if cam == null:
		return
	var dir := Vector3(cos(cam_pitch) * sin(cam_yaw), sin(cam_pitch), cos(cam_pitch) * cos(cam_yaw))
	cam.position = cam_target + dir * cam_dist
	cam.look_at(cam_target)


# ================= CLIP FIELD SYNC =================

func _sync_clip_ui() -> void:
	name_edit.text = str(clip.get("name", ""))
	dur_spin.set_value_no_signal(float(clip.get("length", 1.0)))
	speed_spin.set_value_no_signal(float(clip.get("speed", 1.0)))
	atk_speed_spin.set_value_no_signal(float(clip.get("playback_speed", 1.0)))
	rec_spin.set_value_no_signal(float(clip.get("recovery", 0.3)))
	windup_spin.set_value_no_signal(float(clip.get("windup_end", 0.3)))
	active_spin.set_value_no_signal(float(clip.get("active_end", 0.65)))
	hbon_spin.set_value_no_signal(float(clip.get("hitbox_on", 0.3)))
	hboff_spin.set_value_no_signal(float(clip.get("hitbox_off", 0.65)))
	dmg_spin.set_value_no_signal(float(clip.get("damage_time", -1.0)))
	vfx_spin.set_value_no_signal(float(clip.get("vfx_time", -1.0)))
	cat_opt.selected = Clip.CATEGORIES.find(str(clip.get("category", "attack")))
	interp_opt.selected = Clip.INTERPS.find(str(clip.get("interp", "smooth")))
	if cat_opt.selected < 0:
		cat_opt.selected = 2
	if interp_opt.selected < 0:
		interp_opt.selected = 0
	loop_check.set_pressed_no_signal(bool(clip.get("loop", true)))
	_refresh_anim_list(str(clip.get("name", "")))
	_update_map_label()
	_update_title()
	_update_key_info()
	key_bar.queue_redraw()


func _update_title() -> void:
	var src := clip_file if clip_file != "" else "(unsaved)"
	title_label.text = "Anim Editor  %s  [%s]" % [str(clip.get("name", "")), src]
	if _dirty:
		saved_badge.text = "Unsaved *"
		saved_badge.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	else:
		saved_badge.text = "Saved"
		saved_badge.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))


func _on_clip_field(v: float, field: String) -> void:
	clip[field] = v
	_dirty = true
	_update_title()
	key_bar.queue_redraw()


func _on_duration_changed(v: float) -> void:
	clip["length"] = maxf(0.1, v)
	_dirty = true
	_update_title()
	_apply_at(minf(cur_time, _clip_len()))


func _on_category_selected(i: int) -> void:
	clip["category"] = Clip.CATEGORIES[i]
	_dirty = true
	_update_title()


func _on_interp_selected(i: int) -> void:
	clip["interp"] = Clip.INTERPS[i]
	_dirty = true
	_apply_at(cur_time)


func _on_loop_toggled(on: bool) -> void:
	clip["loop"] = on
	_dirty = true
	_update_title()


func _on_skin_selected(i: int) -> void:
	var want: String = SKINS[i]
	if want == skin:
		return
	_confirm_or_do("Switch character to " + want + "?", _do_select_skin.bind(want))


func _do_select_skin(sname: String) -> void:
	_select_skin(sname, false)


func _select_skin(sname: String, first: bool) -> void:
	skin = sname
	skin_opt.selected = SKINS.find(sname)
	_ensure_defaults(skin)
	_spawn_fighter()
	_sync_part_list()
	_refresh_anim_list()
	var names := _current_names()
	if names.is_empty():
		clip = Clip.new_clip("new_attack", skin, 1.0)
		clip_file = ""
		_sync_clip_ui()
		_apply_at(0.0)
	else:
		_load_clip(skin, str(names[0]))
	if not first:
		_set_status("Character: " + skin + " (procedural parts, no skeleton - pick in Outliner).")


func _on_anim_selected(i: int) -> void:
	_confirm_or_do("Switch animation?", _do_select_anim.bind(i))


func _do_select_anim(i: int) -> void:
	_load_clip(skin, anim_opt.get_item_text(i))


func _on_channel_toggled(on: bool, ch: String) -> void:
	chan_on[ch] = on
	key_bar.queue_redraw()


# ================= GAME SYNC (bake procedural -> clip) =================

## Re-record the REAL gameplay animation for an attack kind by running the
## actual fighter anim() code frame by frame. This is the game-to-editor
## direction of synchronization: what you see is what the game computes.
func _gameplay_atk(skin_name: String, kind: String) -> Dictionary:
	# Mirrors bb_fighter.start_atk() timings with the real attack constants.
	# (The cowboy's S3 horse ride is locomotion, not a keyframable attack.)
	match kind:
		"punch":
			return (FighterScript.ATK_L as Dictionary).duplicate()
		"dash":
			return (FighterScript.ATK_S1 as Dictionary).duplicate()
		"upper":
			return (FighterScript.ATK_S2 as Dictionary).duplicate()
		"spin":
			return (FighterScript.ATK_S3 as Dictionary).duplicate()
		"fan":
			return (FighterScript.ATK_FAN as Dictionary).duplicate()
		"rifle":
			return (FighterScript.ATK_RIFLE as Dictionary).duplicate()
		"counter":
			return (FighterScript.ATK_COUNTER as Dictionary).duplicate()
		"bash":
			return (FighterScript.ATK_BASH as Dictionary).duplicate()
		"sweep":
			return (FighterScript.ATK_SWEEP as Dictionary).duplicate()
	return {}


func _bake_procedural(skin_name: String, kind: String) -> Dictionary:
	# Samples the real fighter anim() at 30 Hz into a clip (game-to-editor).
	# cur_bake_t carries the current sample time to _record_bake_frame.
	var atk := _gameplay_atk(skin_name, kind)
	if atk.is_empty():
		return {}
	var dur: float = float(atk["w"]) + float(atk["a"]) + float(atk["r"])
	var f = FighterScript.new()
	add_child(f)
	f.setup_skin(skin_name)
	f.position = Vector3.ZERO
	f.rotation = Vector3.ZERO
	f.st = "atk"
	f.atk = atk
	var tracks := {}
	var steps := maxi(1, roundi(dur * 30.0))
	for i in range(steps + 1):
		cur_bake_t = minf(float(i) / 30.0, dur)
		f.t = cur_bake_t
		if kind == "spin":
			f.spin_a = cur_bake_t * 18.0 # spin advance normally done in upd()
		if kind == "fan":
			f.fan_kick = 0.0 # baseline aim pose (kicks decay in upd())
		f.anim(0.016, cur_bake_t)
		_record_bake_frame(tracks, f)
	f.queue_free()
	var baked := Clip.new_clip(kind, skin_name, dur)
	baked["category"] = "attack"
	baked["loop"] = false
	baked["windup_end"] = float(atk["w"])
	baked["active_end"] = float(atk["w"]) + float(atk["a"])
	baked["hitbox_on"] = float(atk["w"])
	baked["hitbox_off"] = float(atk["w"]) + float(atk["a"])
	baked["damage_time"] = float(atk["w"])
	baked["vfx_time"] = float(atk["w"])
	baked["tracks"] = tracks
	return baked


func _record_bake_frame(tracks: Dictionary, f) -> void:
	var nodes := {
		"model": f.model, "arm_l": f.arm_l, "arm_r": f.arm_r,
		"hat": f.hat_root, "sword": f.sword_node, "shield": f.shield_node,
		"skin": f.skin_inst, "gun": f.gun_node, "rifle": f.rifle_node,
	}
	for p in nodes.keys():
		var n: Node3D = nodes[p]
		if n == null:
			continue
		if not tracks.has(p):
			tracks[p] = {"pos": [], "rot": [], "scl": []}
		_add_bake_key(tracks[p]["pos"], cur_bake_t, n.position, 0.002)
		_add_bake_key(tracks[p]["rot"], cur_bake_t,
			Vector3(rad_to_deg(n.rotation.x), rad_to_deg(n.rotation.y), rad_to_deg(n.rotation.z)), 0.05)
		_add_bake_key(tracks[p]["scl"], cur_bake_t, n.scale, 0.002)


var cur_bake_t := 0.0


func _add_bake_key(keys: Array, t: float, v: Vector3, eps: float) -> void:
	if keys.is_empty():
		keys.append([t, v.x, v.y, v.z])
		return
	var l: Array = keys[keys.size() - 1]
	if Vector3(float(l[1]), float(l[2]), float(l[3])).distance_to(v) > eps:
		keys.append([t, v.x, v.y, v.z])
	else:
		l[0] = t # extend the flat span instead of storing redundant keys


func _on_bake_from_game() -> void:
	var kind: String = ATTACK_KINDS[assign_opt.selected]
	_push_undo()
	var baked := _bake_procedural(skin, kind)
	if baked.is_empty():
		_set_status("Cannot bake '" + kind + "' for " + skin + ".", true)
		return
	for k in ["length", "windup_end", "active_end", "hitbox_on", "hitbox_off",
			"damage_time", "vfx_time", "tracks"]:
		clip[k] = baked[k]
	clip["category"] = "attack"
	clip["loop"] = false
	_dirty = true
	cur_time = 0.0
	sel_key_time = -1.0
	_sync_clip_ui()
	_apply_at(0.0)
	_set_status("Baked the REAL gameplay '" + kind + "' (" + skin + ") into this clip. Save to use it in game.")


# ================= ATTACK MAP =================

var attack_map := {}

func _load_attack_map() -> void:
	attack_map = {}
	if FileAccess.file_exists(ATTACK_MAP_PATH):
		var f := FileAccess.open(ATTACK_MAP_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				attack_map = parsed
	_update_map_label()


func _save_attack_map() -> void:
	var f := FileAccess.open(ATTACK_MAP_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(attack_map, "\t"))
		f.close()


func _on_assign() -> void:
	if clip_file == "":
		_set_status("Save the clip first, then Assign.", true)
		return
	var kind: String = ATTACK_KINDS[assign_opt.selected]
	attack_map[skin + "|" + kind] = clip_file
	_save_attack_map()
	_update_map_label()
	_set_status("Gameplay: '" + kind + "' (" + skin + ") now plays " + clip_file + ". Damage and timing unchanged.")


func _on_unassign() -> void:
	var kind: String = ATTACK_KINDS[assign_opt.selected]
	if attack_map.erase(skin + "|" + kind):
		_save_attack_map()
		_update_map_label()
		_set_status("Unassigned '" + kind + "' (" + skin + "). Game uses procedural animation again.")
	else:
		_set_status("No mapping for '" + kind + "' (" + skin + ").")


func _update_map_label() -> void:
	if map_label == null:
		return
	var mine := []
	for k in attack_map.keys():
		if str(k).begins_with(skin + "|"):
			mine.append(str(k).split("|")[1] + " -> " + str(attack_map[k]).get_file())
	map_label.text = "Mapped: " + (", ".join(mine) if not mine.is_empty() else "none (procedural)")
	_update_kind_note()


func _update_kind_note() -> void:
	if kind_note_label == null or assign_opt == null:
		return
	var kind: String = ATTACK_KINDS[assign_opt.selected % ATTACK_KINDS.size()]
	kind_note_label.text = str(KIND_NOTES.get(kind, ""))


# ================= MISC =================

func _on_back() -> void:
	get_tree().change_scene_to_file("res://block_brawl.tscn")


func _set_status(msg: String, warn: bool = false) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.45) if warn else Color(0.85, 0.9, 0.85))
	_update_title()
