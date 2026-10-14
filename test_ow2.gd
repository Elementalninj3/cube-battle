extends SceneTree
## Temporary driver (deleted after use): trace player offense in OW.

var w = null
var stage := 0
var _done := false


func _step(n: int, dt: float = 0.016) -> void:
	for i in n:
		w._physics_process(dt)


func _process(_dt: float) -> bool:
	if _done:
		return true
	if stage == 0:
		w = root.get_child(-1)
		# Isolate the defeat pipeline: soften one raider, land one string.
		w.enemies[0].body.hp = 5.0
		w.player.position = Vector3(9, 0, 6)
		w.player.hp = 100.0
		for h in 4:
			if String(w.player.st) == "ko":
				w.dead_t = 0.01
			w.player.position = Vector3(9, 0, 6)
			w.player.hp = 100.0
			w.player.ai_press("S1")
			for i in 50:
				w._physics_process(0.016)
		print("KILLS=", w.kills, " alive=", w.alive_enemies(), " (want kills>=1)")
		for e in w.enemies:
			if not e.alive:
				e.respawn_t = 0.05
		for i in 30:
			w._physics_process(0.016)
		print("RESPAWN alive=", w.alive_enemies(), " (want 7)")
		print("DONE_O")
		_done = true
	return false
