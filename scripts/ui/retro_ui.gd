class_name RetroUI
extends RefCounted
## Shared retro PC look for every menu: monospace font, amber on near-black,
## flat buttons that invert on hover. One theme, reused everywhere.

const AMBER := Color(1.0, 0.79, 0.33)
const DIM := Color(0.62, 0.52, 0.34)
const RED := Color(1.0, 0.36, 0.25)
const INK := Color(0.06, 0.045, 0.02)
const BG := Color(0.04, 0.035, 0.03, 0.93)

static var _font: Font
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Lucida Console", "Courier New", "Consolas", "Monospace"])
		_font = f
	return _font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	_pad(normal, 10, 4)
	var hover := StyleBoxFlat.new()
	hover.bg_color = AMBER
	_pad(hover, 10, 4)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = AMBER
	focus.set_border_width_all(1)
	_pad(focus, 10, 4)
	for cls in ["Button", "CheckBox"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, hover)
		t.set_stylebox("hover_pressed", cls, hover)
		t.set_stylebox("disabled", cls, normal)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, AMBER)
		t.set_color("font_hover_color", cls, INK)
		t.set_color("font_pressed_color", cls, INK)
		t.set_color("font_hover_pressed_color", cls, INK)
		t.set_color("font_focus_color", cls, AMBER)
		t.set_color("font_disabled_color", cls, DIM)
	t.set_color("font_color", "Label", AMBER)

	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_color = DIM
	panel.set_border_width_all(2)
	_pad(panel, 22, 18)
	t.set_stylebox("panel", "PanelContainer", panel)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.25, 0.2, 0.12)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	_theme = t
	return t


static func _pad(sb: StyleBoxFlat, h: float, v: float) -> void:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v


static func button(text: String, cb: Callable, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	return b


static func label(text: String, size := 22, color := AMBER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


static func format_distance(meters: float) -> String:
	if meters < 1000.0:
		return "%d m" % int(meters)
	return "%.2f km" % (meters / 1000.0)
