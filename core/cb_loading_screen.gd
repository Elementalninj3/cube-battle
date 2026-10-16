class_name CBLoadingScreen
extends CanvasLayer
## Loading screen shown while shaders precompile + worlds batch.
## Usage:
##   var ls := CBLoadingScreen.show_new(self, "Open World")
##   CBPerf.preload_shaders()
##   await ls.step(0.3, "Shaders...")
##   ... build world ...
##   await ls.step(1.0, "Done")
##   ls.dismiss()

var _bar: ProgressBar
var _label: Label


static func show_new(parent: Node, title: String = "Loading") -> CBLoadingScreen:
	var ls := CBLoadingScreen.new()
	ls.layer = 100
	ls.name = "CBLoading"
	parent.add_child(ls)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ls.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ls.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(t)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(420, 22)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.02
	bar.show_percentage = false
	vb.add_child(bar)
	var lab := Label.new()
	lab.text = "Preloading shaders..."
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 15)
	lab.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	vb.add_child(lab)
	ls._bar = bar
	ls._label = lab
	return ls


func step(frac: float, text: String) -> void:
	_bar.value = clampf(frac, 0.0, 1.0)
	_label.text = text
	await get_tree().process_frame
	await get_tree().process_frame


func dismiss() -> void:
	queue_free()
