extends "res://openworld/ow_world.gd"
## Open World 1 — Performance Field: shares all gameplay/camera/HUD code
## with the base world; only the environment builder and label differ.

const OW1Builder = preload("res://openworld/ow1_builder.gd")


func get_builder():
	return OW1Builder


# OW1-only lighting: same Grass Render setup as the base world, plus a
# slightly lifted neutral ambient (no green tint) and softened shadows.
# Both are free environment state: no new lights, no GI, no volumetrics,
# no post-processing, MSAA untouched.
func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 1, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.695381, 0.644979, 0.598817)
	env.ambient_light_energy = 1.1
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-PI / 4.0, 0, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 1
	sun.directional_shadow_split_1 = 0.01
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_opacity = 0.85
	add_child(sun)


func _player_bounds() -> float:
	return 30.0


func _objective_text() -> String:
	return "Clear the camp & encounter — grab all 14 coins"
