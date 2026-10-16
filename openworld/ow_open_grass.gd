extends "res://openworld/ow_world.gd"
## Open World 2 — Grass: the same Big 1v1 Arena look and lighting, with
## Binbun grass blades across the floor.

const OWGrassBuilder = preload("res://openworld/ow_grass_builder.gd")


func get_builder():
	return OWGrassBuilder


func _lighting_mode() -> int:
	return CBLighting.Mode.OW_GRASS


func _player_bounds() -> float:
	return bounds_val


func _objective_text() -> String:
	return "Explore the grassy arena — 1v1 look with grass"
