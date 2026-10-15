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

const YAW0 := PI * 0.25 # offset dir (1, *, 1): classic isometric angle
const PITCH0 := 0.59 # locked isometric tilt (arena-like)
const FOV0 := 28.0 # arena camera fov
const DIST0 := 27.0
const DIST_MIN := 12.0
const DIST_MAX := 40.0
const TURN_SPEED := 7.0 # smoothing rate for quarter-turns and zoom

var target: Node3D = null
var yaw_step := 0 # settled 0..3 quarter-turn index
var pending := 0 # queued extra steps pressed mid-turn
var yaw := YAW0 # animated yaw (snaps exactly on arrival)
var dist := DIST0
var t_dist := DIST0


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
