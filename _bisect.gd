extends SceneTree
const SCENE := ""
func _initialize() -> void:
	_run()
func _run() -> void:
	var n := (load(SCENE) as PackedScene).instantiate()
	root.add_child(n)
	for i in 8:
		await process_frame
	quit()
