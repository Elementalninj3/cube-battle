extends SceneTree
## Temporary driver (deleted after use): full open-world verification.

var w = null
var stage := 0
var _done := false


func _step(n: int, dt: float = 0.016) -> void:
	for i in n:
		w._physics_process(dt)


func _count(root: Node, pred: String) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur.name == pred:
			n += 1
		for c in cur.get_children():
			stack.append(c)
	return n


func _process(_dt: float) -> bool:
	if _done:
		return true
	if stage == 0:
		w = root.get_child(-1) # OW scene booted via command line
		print("OW player=", w.player != null, " skin=", w.player.skin_name,
			" enemies=", w.enemies.size(), " obstacles=", w.obstacles.size(),
			" grass=", w.get_node_or_null("GrassField") != null)
		var mmi := w.get_node_or_null("GrassField") as MultiMeshInstance3D
		if mmi != null:
			print("OW grass_instances=", mmi.multimesh.visible_instance_count)
		print("OW enemy Boca=", w.enemies[0].body.get_surface_override_material_count() if false else "n/a")
		stage = 1
	elif stage == 1:
		# Camera-relative movement: drive the mapping directly (bypasses the
		# live keyboard read) and confirm the fighter walks camera-forward.
		w.cam.t_yaw = 0.0
		w.cam.yaw = 0.0
		var p0: Vector3 = w.player.position
		for i in 30:
			w._player_move_iv(Vector2(0, 1))
			w.player.upd(0.016, true)
		var moved: Vector3 = w.player.position - p0
		# t_yaw=0 -> fwd=(0,0,-1): forward must be -Z.
		print("OW cam_move moved=", moved, " (want z negative, x ~0)")
		# And the 90-degree case: yaw=PI/2 -> fwd=(-1,0,0): forward is -X.
		w.cam.t_yaw = PI * 0.5
		w.cam.yaw = PI * 0.5
		p0 = w.player.position
		for i in 30:
			w._player_move_iv(Vector2(0, 1))
			w.player.upd(0.016, true)
		moved = w.player.position - p0
		print("OW cam_move90 moved=", moved, " (want x negative, z ~0)")
		w.cam.reset_view()
		stage = 2
	elif stage == 2:
		# Drag the player next to camp A and let the ninjas engage.
		w.player.position = Vector3(9, 0, 8)
		w.player.hp = 100.0
		var e0hp: float = w.enemies[0].body.hp
		_step(240)
		var d: float = w.enemies[0].body.position.distance_to(w.player.position)
		print("OW engage e0dist=", snappedf(d, 0.01), " e0hp=", w.enemies[0].body.hp,
			" playerhp=", w.player.hp, " (want dist small, e0hp<", e0hp, " or playerhp<100)")
		stage = 3
	elif stage == 3:
		# Player cleaves camp A down with the katana string (god-mode the
		# player so the test measures offense, not survival).
		w.player.position = Vector3(9, 0, 6)
		for h in 10:
			w.player.hp = 100.0
			if String(w.player.st) == "ko":
				w.player.reset_match(Vector3(9, 0, 6), PI)
			w.player.ai_press("S1")
			_step(50)
		print("OW cleave kills=", w.kills, " alive=", w.alive_enemies(), " (want kills>=1)")
		stage = 4
	elif stage == 4:
		# Force-respawn check + player death flow.
		for e in w.enemies:
			if not e.alive:
				e.respawn_t = 0.05
		_step(30)
		print("OW respawn alive=", w.alive_enemies(), " (want 7)")
		w.player.hp = 1.0
		w.player.hp = 0.0
		w.ko(w.player)
		_step(10)
		print("OW death overlay=", w._info_label.visible, " dead_t=", snappedf(w.dead_t, 0.01))
		stage = 5
	elif stage == 5:
		_step(250)
		print("OW rebirth hp=", w.player.hp, " visible=", w.player.visible, " overlay=", w._info_label.visible,
			" (want 100 true false)")
		print("DONE_OW")
		_done = true
	return false
