extends SceneTree

var _frames := 0
var _scene: Node = null


func _initialize() -> void:
	push_error("MARK_BEFORE_ADD")
	var packed := load("res://block_brawl.tscn") as PackedScene
	_scene = packed.instantiate()
	root.add_child(_scene)
	push_error("MARK_AFTER_ADD")


func _process(_delta: float) -> bool:
	_frames += 1
	push_error("MARK_FRAME_%d" % _frames)
	if _frames == 3:
		push_error("MARK_FREE_BEFORE")
		_scene.free()
		push_error("MARK_FREE_AFTER")
	if _frames >= 6:
		push_error("MARK_BEFORE_QUIT")
		quit()
		return true
	return false
