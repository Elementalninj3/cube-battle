extends RefCounted
## Shared single-player character pick: the 1v1-style solo select screen in
## bb_main writes the chosen skin here before changing scene, and the solo
## modes (open-world, grass render) read it when spawning the player.
## Static storage survives scene changes.
## Falls back to "ninja" when nothing was picked yet.

static var solo_skin := "ninja"


static func set_skin(sname: String) -> void:
	if sname != "":
		solo_skin = sname


static func get_skin() -> String:
	if solo_skin == "":
		return "ninja"
	return solo_skin
