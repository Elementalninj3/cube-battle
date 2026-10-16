extends RefCounted
## Open World — Big 1v1 Arena builder.
##
## Everything the exact same as local 1v1 (bb_arena + bb_main lighting),
## just on a bigger scale: SIZE x SIZE checkered grass tiles on a dirt
## base, same colors/styles, same destructible rocks/trees/flowers.
## Lighting comes from ow_world._build_env (1v1 sunset sky, fog, warm sun
## + cool rim), so this builder only makes ground + props + gameplay data.

const ArenaScript = preload("res://bb_arena.gd")

const SIZE := 80
const HALF := 40.0
const SEED := 4242


static func build(world: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	randomize()
	var arena = ArenaScript.new()
	arena.name = "BigArena"
	world.add_child(arena)
	# vfx does not exist yet at build time (world creates it after);
	# ow_world wires arena.vfx right after. Props still build fine.
	arena.build(null, SIZE)
	# Movement blockers from the solid props (rocks + trees; flowers
	# are walk-through, same feel as the 1v1 arena).
	var obstacles: Array = []
	for p in arena.props:
		var kind := String(p.get("kind", ""))
		if kind == "rock" or kind == "tree":
			var bp: Vector3 = p["pos"]
			obstacles.append({"p": Vector2(bp.x, bp.z), "r": 1.1})
	var camps: Array = [
		{"pos": Vector3(-26, 0, -26), "skins": ["cubeknight", "ninja"]},
		{"pos": Vector3(26, 0, -26), "skins": ["cubecowboy", "ninja"]},
		{"pos": Vector3(0, 0, -4), "skins": ["cubeknight", "cubecowboy"]},
		{"pos": Vector3(-26, 0, 18), "skins": ["ninja", "ninja"]},
		{"pos": Vector3(26, 0, 18), "skins": ["cubeknight", "cubecowboy"]},
	]
	return {
		"obstacles": obstacles,
		"spawn": Vector3(0, 0, 32),
		"camps": camps,
		"plates": [],
		"space": null,
		"cave_lights": [],
		"coins": [],
		"half": HALF + 2.0,
		"bounds": HALF - 1.0,
		"arena": arena,
	}
