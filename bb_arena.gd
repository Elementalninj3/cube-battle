extends Node3D
## Arena builder ported from block-brawl-quality.html: 14x14 checkered grass
## platform on a dirt base, with rocks, trees and flowers. All boxes share
## one BoxMesh; materials are cached per color.

var _box: BoxMesh
var _mats := {}


func build() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_box.material = null
	# dirt base, 4 layers
	for k in 4:
		_tile(Vector3(0, -1.3125 - k * 0.625, 0), Vector3(14, 0.625, 14),
			Color.from_hsv(0.07, 0.4, 0.36 - k * 0.05))
	# grass platform
	for x in 14:
		for z in 14:
			var e := maxf(absf(x - 6.5), absf(z - 6.5))
			var v := 0.44 + randf() * 0.05 + float((x + z) % 2) * 0.025
			var c := Color.from_hsv(0.29 + randf() * 0.02, 0.5, v)
			if e > 4.5:
				c = c * (1.0 - (e - 4.5) * 0.08)
			_tile(Vector3(x - 6.5, -0.5, z - 6.5), Vector3(0.985, 1, 0.985), c)
	# rocks
	for spot in [Vector3(-6, 0, 5.8), Vector3(6.1, 0, -5.4), Vector3(5.8, 0, 6.0)]:
		_tile(spot + Vector3(0.1, 0.01, 0.1), Vector3(1.3, 0.02, 1.3), Color(0x1f4a24ff))
		_tile(spot + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), Color(0x9aa3adff))
		_tile(spot + Vector3(0.5, 0.15, 0.2), Vector3(0.3, 0.3, 0.3), Color(0x80898fff))
	# trees
	for spot in [Vector3(-6, 0, -6), Vector3(6, 0, 3.5)]:
		_tile(spot + Vector3(0.3, 0.01, 0.3), Vector3(2.4, 0.02, 2.4), Color(0x1f4a24ff))
		_tile(spot + Vector3(0, 0.6, 0), Vector3(0.4, 1.2, 0.4), Color(0x7a4b2aff))
		_tile(spot + Vector3(0, 1.6, 0), Vector3(1.5, 1.1, 1.5), Color(0x2f9a3dff))
		_tile(spot + Vector3(0, 2.4, 0), Vector3(0.9, 0.8, 0.9), Color(0x3fb04cff))
	# flowers
	var tops := [Color(0xff5d8fff), Color(0xffd23fff), Color(0xffffffff)]
	var spots := [Vector3(-4, 0, 6), Vector3(0, 0, 6.3), Vector3(4.4, 0, -6.2),
		Vector3(-6.3, 0, 0), Vector3(6.3, 0, 0.5), Vector3(-2, 0, -6.3), Vector3(1.8, 0, 6.2)]
	for i in spots.size():
		var s: Vector3 = spots[i]
		_tile(s + Vector3(0, 0.15, 0), Vector3(0.06, 0.3, 0.06), Color(0x2a7a35ff))
		_tile(s + Vector3(0, 0.38, 0), Vector3(0.2, 0.2, 0.2), tops[i % 3])


func _tile(pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box
	mi.position = pos
	mi.scale = size
	mi.material_override = _mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]
