extends Camera3D
## Open-world snap camera: arena-style isometric view with 90-degree
## horizontal step rotation.
##
## Controls: middle-mouse CLICK or E = rotate +90°, Q = rotate -90°,
## wheel = zoom, R = smooth reset to the isometric default.
## Pitch stays locked at the isometric tilt; only the horizontal orbit
## steps. Movement stays camera-relative (the world maps input through
## move_basis, which reads the settled step angle, so movement never
## drifts mid-turn).
##
## Camera obstruction fading: each frame a few cheap rays are cast from the
## camera toward the player, against the dedicated occlusion layer only
## (mask 4). Any object hit fades smoothly toward a partial alpha so the
## player stays visible, then restores. Only occluders actually on the
## camera->player path are touched; the player, UI and gameplay collision are
## never involved.

const YAW0 := PI * 0.25 # offset dir (1, *, 1): classic isometric angle
const PITCH0 := 0.59 # locked isometric tilt (arena-like)
const FOV0 := 28.0 # arena camera fov
const DIST0 := 27.0
const DIST_MIN := 12.0
const DIST_MAX := 40.0
const TURN_SPEED := 7.0 # smoothing rate for quarter-turns and zoom

const OCCLUDER_MASK := 4
const FADE_TARGET := 1.0

var target: Node3D = null
var yaw_step := 0 # settled 0..3 quarter-turn index
var pending := 0 # queued extra steps pressed mid-turn
var yaw := YAW0 # animated yaw (snaps exactly on arrival)
var dist := DIST0
var t_dist := DIST0

# id -> ow_occluder node currently being faded.
var _occluders: Dictionary = {}
var _occ_frame := 0
var _occ_idx := 0


func _ready() -> void:
	fov = FOV0
	current = true


func reset_view() -> void:
	yaw_step = 0
	pending = 0
	t_dist = DIST0


# Exact destination yaw for a step index: no float accumulation, ever.
func _step_yaw(s: int) -> float:
	return YAW0 + float(posmod(s, 4)) * PI * 0.5


func _request_turn(dir: int) -> void:
	if absf(_ang_diff(_step_yaw(yaw_step + pending + dir), yaw)) > 0.001:
		# Still turning: queue at most one extra step either way.
		pending = clampi(pending + dir, -1, 1)
	else:
		yaw_step = posmod(yaw_step + dir, 4)
		yaw = _step_yaw(yaw_step)


func _ang_diff(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


# Horizontal camera-relative movement basis. Reads the SETTLED step angle
# (not the animated mid-turn yaw) so controls stay consistent and never
# drift while the camera is turning.
func move_basis() -> Dictionary:
	var y := _step_yaw(yaw_step + pending)
	var fwd := Vector3(-sin(y), 0, -cos(y))
	var right := Vector3(-fwd.z, 0, fwd.x)
	return {"fwd": fwd, "right": right}


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# NOTE: InputEventMouseButton has no `echo` property (that is
		# InputEventKey-only); touching it errors on every click.
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				_request_turn(1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				t_dist = clampf(t_dist / 1.12, DIST_MIN, DIST_MAX)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				t_dist = clampf(t_dist * 1.12, DIST_MIN, DIST_MAX)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_R:
				reset_view()
			elif k.keycode == KEY_E:
				_request_turn(1)
			elif k.keycode == KEY_Q:
				_request_turn(-1)


func _process(dt: float) -> void:
	var want_yaw := _step_yaw(yaw_step + pending)
	var d := _ang_diff(want_yaw, yaw)
	var s := 1.0 - exp(-TURN_SPEED * dt)
	yaw += d * s
	if absf(d) < 0.002:
		# Arrived exactly: settle queued steps without teleporting.
		yaw = want_yaw
		if pending != 0:
			yaw_step = posmod(yaw_step + pending, 4)
			pending = 0
	dist += (t_dist - dist) * s
	if target == null or not is_instance_valid(target):
		return
	var focus := target.position + Vector3(0, 1.2, 0)
	var dir := Vector3(sin(yaw) * cos(PITCH0), sin(PITCH0), cos(yaw) * cos(PITCH0))
	position = focus + dir * dist
	look_at(focus)
	_update_occlusion(dt)


# --- camera obstruction fading -------------------------------------------

func _update_occlusion(dt: float) -> void:
	# No occluders in any shipped map (nothing on layer 4): skip the
	# raycasts entirely. Occluders register in group "occluder" when built.
	if _occluders.is_empty() and get_tree().get_nodes_in_group("occluder").is_empty():
		return
	_occ_frame += 1
	var space := get_world_3d().direct_space_state
	for id in _occluders.keys():
		(_occluders[id] as Node).occlude(0.0)
	if space != null:
		var focus := target.position
		# 1 ray per frame, rotating through body sample points (was 3/frame).
		var offs := [Vector3(0, 1.9, 0), Vector3(0, 1.0, 0), Vector3(0, 0.25, 0)]
		_occ_idx = (_occ_idx + 1) % offs.size()
		var to: Vector3 = focus + offs[_occ_idx]
		var q := PhysicsRayQueryParameters3D.create(position, to)
		q.collision_mask = OCCLUDER_MASK
		q.collide_with_areas = false
		q.hit_from_inside = false
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var col = hit.get("collider")
			if col != null and col.has_method("occlude"):
				var oid := (col as Object).get_instance_id()
				if not _occluders.has(oid):
					_occluders[oid] = col
				(col as Node).occlude(FADE_TARGET)
	# Advance every tracked occluder (also restores ones no longer hit).
	for id in _occluders.keys():
		var o := _occluders[id] as Node
		if not is_instance_valid(o):
			_occluders.erase(id)
			continue
		if o.advance(dt) <= 0.0005 and o.is_settled():
			_occluders.erase(id)
