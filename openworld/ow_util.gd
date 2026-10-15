extends RefCounted
## Open-world small helpers shared by the world, enemies and camera.


# Convert a desired world-space XZ move direction into the (ix, iy) pair
# the fighter's iso-baked movement mapping expects:
#   fighter does wx = ix - iy, wz = -ix - iy.
# Solving gives ix = (dx - dz) / 2, iy = -(dx + dz) / 2.
static func iso_for(d: Vector2) -> Vector2:
	var len_sq := d.x * d.x + d.y * d.y
	if len_sq < 0.000001:
		return Vector2.ZERO
	var inv := 1.0 / sqrt(len_sq)
	var nx := d.x * inv
	var ny := d.y * inv
	return Vector2((nx - ny) * 0.5, -(nx + ny) * 0.5)


static func flat_dist(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


# Push a ground position out of obstacle circles (trees/rocks). Returns the
# corrected position; y is preserved.
static func push_out(pos: Vector3, obstacles: Array) -> Vector3:
	if obstacles.is_empty():
		return pos
	var out := pos
	for o in obstacles:
		var op: Vector2 = o["p"]
		var dx := out.x - op.x
		var dz := out.z - op.y
		var want := float(o["r"]) + 0.45
		var d_sq := dx * dx + dz * dz
		if d_sq >= want * want:
			continue
		var d := sqrt(maxf(d_sq, 0.000001))
		if d < 0.001:
			dx = 1.0
			dz = 0.0
			d = 1.0
		out.x = op.x + dx / d * want
		out.z = op.y + dz / d * want
	return out
