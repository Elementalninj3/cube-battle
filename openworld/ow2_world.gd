extends "res://openworld/ow_world.gd"
## Open World 2 — Nature World: shares all gameplay/camera/HUD code with
## the base world; only the environment builder, bounds and label differ.

const OW2Builder = preload("res://openworld/ow2_builder.gd")


func get_builder():
	return OW2Builder


func _player_bounds() -> float:
	return 30.0


func _objective_text() -> String:
	return "Nature world — combat practice"
