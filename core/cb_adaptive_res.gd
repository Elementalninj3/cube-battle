class_name CBAdaptiveRes
extends Node
## Adaptive 3D resolution: the 60 FPS guarantee.
##
## Autoload (see project.godot as "AdaptiveRes"), so ONE instance drives the
## root window viewport for every scene (1v1, open world, grass render).
## It scales ONLY the 3D render resolution (Viewport.scaling_3d_scale); the
## UI lives on CanvasLayers that render at full resolution, so text and
## menus stay perfectly sharp.
## Opt-in: min_scale defaults to 1.0 so every scene renders at full
## resolution unless the Settings UI explicitly lowers the floor.
##
## Ballistics: drop fast (0.06 per 0.5 s) on any dip below target - 3 FPS,
## recover slowly (0.03 per ~3 s of stable >= target - 1 FPS) so it never
## oscillates. Base scale (set by the graphics quality) is the ceiling and
## min_scale the floor.

@export var enabled := true
@export var target_fps := 60.0
@export var min_scale := 1.0
@export var base_scale := 1.0

var _scale := 1.0
var _t := 0.0
var _frames := 0
var _good := 0


func _ready() -> void:
	_scale = base_scale
	_apply()


## Graphics quality sets the ceiling (Low renders at a lower base). Clamped
## to the adaptive floor so the two settings can never fight.
func set_base_scale(s: float) -> void:
	base_scale = clampf(s, min_scale, 1.0)
	_scale = minf(_scale, base_scale)
	_apply()


func _apply() -> void:
	if not enabled:
		return
	var vp := get_viewport()
	if vp == null:
		return
	# 3D-only scaling; UI (canvas items) is unaffected. Guarded so a
	# renderer without 3D scaling support cannot crash startup.
	if "scaling_3d_mode" in vp:
		vp.set("scaling_3d_mode", Viewport.SCALING_3D_MODE_BILINEAR)
		vp.set("scaling_3d_scale", _scale)


func _process(dt: float) -> void:
	if not enabled or base_scale <= min_scale:
		return
	_t += dt
	_frames += 1
	if _t < 0.5:
		return
	var fps := float(_frames) / _t
	_t = 0.0
	_frames = 0
	if fps < target_fps - 3.0:
		_scale -= 0.06
		_good = 0
	elif fps >= target_fps - 1.0:
		_good += 1
		if _good >= 6: # ~3 s stable before trying higher
			_scale += 0.03
			_good = 0
	_scale = clampf(_scale, min_scale, base_scale)
	var vp := get_viewport()
	if vp != null and absf(float(vp.get("scaling_3d_scale")) - _scale) > 0.0005:
		vp.set("scaling_3d_scale", _scale)
