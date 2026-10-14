extends RefCounted
## Open-world small helpers shared by the world, enemies and camera.


# Convert a desired world-space XZ move direction into the (ix, iy) pair
# the fighter's iso-baked movement mapping expects:
#   fighter does wx = ix - iy, wz = -ix - iy.
# Solving gives ix = (dx - dz) / 2, iy = -(dx + dz) / 2.
static func iso_for(d: Vector2) -> Vector2:
	if d.length() < 0.001:
		return Vector2.ZERO
	var n := d.normalized()
	return Vector2((n.x - n.y) * 0.5, -(n.x + n.y) * 0.5)


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# Push a ground position out of obstacle circles (trees/rocks). Returns the
# corrected position; y is preserved.
static func push_out(pos: Vector3, obstacles: Array) -> Vector3:
	var out := pos
	for o in obstacles:
		var op: Vector2 = o["p"]
		var dx := out.x - op.x
		var dz := out.z - op.y
		var d := Vector2(dx, dz).length()
		var want := float(o["r"]) + 0.45
		if d < want:
			if d < 0.001:
				dx = 1.0
				dz = 0.0
				d = 1.0
			out.x = op.x + dx / d * want
			out.z = op.y + dz / d * want
	return out
