extends "res://openworld/ow_world.gd"
## Open World 1 — Big 1v1 Arena: everything the exact same as local 1v1
## (checkered grass tiles, dirt base, destructible rocks/trees/flowers,
## sunset lighting + fog + warm sun/cool rim), just on a bigger 40x40 scale.

const OWBigBuilder = preload("res://openworld/ow_big_builder.gd")


func get_builder():
	return OWBigBuilder


func _player_bounds() -> float:
	return bounds_val


func _objective_text() -> String:
	return "Explore the big 1v1 arena — 80x80 open world"
