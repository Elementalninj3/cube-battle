extends Camera3D
## Open-world orbit camera: default isometric view, optional rotation.
##
## Controls: hold middle mouse + move = orbit (yaw + pitch), wheel =
## zoom, Q / E = keyboard orbit, R = smooth reset to the isometric default.
## Movement stays camera-relative (the world maps input through move_basis).

const YAW0 := PI * 0.25 # offset dir (1, *, 1): classic isometric angle
const PITCH0 := 0.59
const DIST0 := 26.0
const DIST_MIN := 9.0
const DIST_MAX := 42.0
const PITCH_MIN := 0.12
const PITCH_MAX := 1.25

var target: Node3D = null
var yaw := YAW0
var pitch := PITCH0
var dist := DIST0
var t_yaw := YAW0
var t_pitch := PITCH0
var t_dist := DIST0


func _ready() -> void:
	fov = 50.0
	current = true


func reset_view() -> void:
	t_yaw = YAW0
	t_pitch = PITCH0
	t_dist = DIST0


# Horizontal camera-relative movement basis for the player controller.
func move_basis() -> Dictionary:
	var fwd := Vector3(-sin(t_yaw), 0, -cos(t_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	return {"fwd": fwd, "right": right}


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			t_yaw -= mm.relative.x * 0.005
			t_pitch = clampf(t_pitch + mm.relative.y * 0.004, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and not mb.echo:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				t_dist = clampf(t_dist / 1.12, DIST_MIN, DIST_MAX)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				t_dist = clampf(t_dist * 1.12, DIST_MIN, DIST_MAX)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_R:
			reset_view()


func _process(dt: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		t_yaw += 1.8 * dt
	if Input.is_key_pressed(KEY_E):
		t_yaw -= 1.8 * dt
	var s := 1.0 - exp(-8.0 * dt)
	yaw += (t_yaw - yaw) * s
	pitch += (t_pitch - pitch) * s
	dist += (t_dist - dist) * s
	if target == null or not is_instance_valid(target):
		return
	var focus := target.position + Vector3(0, 1.2, 0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var want := focus + dir * dist
	# Slide in front of trees/rocks instead of clipping through them.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(focus, want)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var hd := focus.distance_to(hit["position"])
		want = focus + dir * maxf(2.5, hd - 0.6)
	position = want
	look_at(focus)
