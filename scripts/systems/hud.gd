class_name RetroHud
extends CanvasLayer
## Minimal retro HUD: speed, distance, a controls line and one flash message.
## Everything is built in code so the scene file stays small.

const AMBER := Color(1.0, 0.79, 0.33)
const DIM := Color(0.78, 0.63, 0.36)
const HOT := Color(1.0, 0.45, 0.25)

var speed_label: Label
var distance_label: Label
var hint_label: Label
var message_label: Label

var _target_kmh := 0.0
var _shown_kmh := 0.0
var _msg_t := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	speed_label = _make_label(58, AMBER, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	speed_label.offset_right = -28
	speed_label.offset_bottom = -22
	speed_label.text = "0 KM/H"

	distance_label = _make_label(30, AMBER, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	distance_label.offset_left = 28
	distance_label.offset_top = 20
	distance_label.text = "0 M"

	message_label = _make_label(56, HOT, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	message_label.offset_top = -120
	message_label.modulate.a = 0.0

	hint_label = _make_label(17, DIM, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_BOTTOM)
	hint_label.offset_bottom = -22
	hint_label.text = _hint_text()


func _make_label(size: int, color: Color, halign: int, valign: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0))
	l.add_theme_constant_override("outline_size", maxi(3, int(size / 6.0)))
	l.horizontal_alignment = halign
	l.vertical_alignment = valign
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l


func _process(delta: float) -> void:
	_shown_kmh = lerpf(_shown_kmh, _target_kmh, 1.0 - exp(-6.0 * delta))
	speed_label.text = "%d KM/H" % roundi(_shown_kmh)
	speed_label.add_theme_color_override("font_color", HOT if _shown_kmh > 190.0 else AMBER)
	if _msg_t > 0.0:
		_msg_t -= delta
		message_label.modulate.a = clampf(_msg_t * 1.6, 0.0, 1.0)
	else:
		message_label.modulate.a = 0.0


func set_speed(kmh: float) -> void:
	_target_kmh = maxf(kmh, 0.0)


func set_distance(meters: float) -> void:
	if meters < 1000.0:
		distance_label.text = "%d M" % int(meters)
	else:
		distance_label.text = "%.2f KM" % (meters / 1000.0)


func flash(text: String, seconds := 1.3) -> void:
	message_label.text = text
	_msg_t = seconds


func _hint_text() -> String:
	var left := _key_label(KEY_A, "A")
	var right := _key_label(KEY_D, "D")
	var pedal := _key_label(KEY_W, "W")
	var brake := _key_label(KEY_S, "S")
	var jump := _key_label(KEY_SPACE, "SPACE")
	var reset := _key_label(KEY_R, "R")
	return "%s / %s  STEER     %s  PEDAL     %s  BRAKE     %s  JUMP     %s  RESET" % [
		left, right, pedal, brake, jump, reset,
	]


func _key_label(physical: int, fallback: String) -> String:
	if DisplayServer.has_method("keyboard_get_label_from_physical"):
		var label := str(DisplayServer.call("keyboard_get_label_from_physical", physical))
		if label != "":
			return label.to_upper()
	return fallback
