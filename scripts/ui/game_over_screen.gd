class_name GameOverScreen
extends CanvasLayer
## "VOUS AVEZ ÉTÉ ÉLIMINÉ" screen with the run's statistics.

@export var director_path: NodePath = ^"../Game"

var director: GameDirector
var _root: Control
var _stats: Label
var _reason: Label
var _first: Button


func _ready() -> void:
	layer = 15
	director = get_node_or_null(director_path) as GameDirector
	_root = Control.new()
	_root.theme = RetroUI.theme()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.0, 0.0, 0.7)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(RetroUI.label("VOUS AVEZ ÉTÉ ÉLIMINÉ", 40, RetroUI.RED))
	_reason = RetroUI.label("", 22)
	box.add_child(_reason)
	_stats = RetroUI.label("", 22, RetroUI.AMBER)
	box.add_child(_stats)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)
	_first = RetroUI.button("> RECOMMENCER", func() -> void:
		if director:
			director.restart_run())
	box.add_child(_first)
	box.add_child(RetroUI.button("> MENU PRINCIPAL", func() -> void:
		if director:
			director.quit_to_menu()))


func show_result(reason: String, distance: float, top_kmh: float, time_s: float) -> void:
	_reason.text = "Cause : %s" % reason
	_stats.text = "Distance parcourue : %s\nVitesse max : %d km/h\nTemps survécu : %s" % [
		RetroUI.format_distance(distance), int(top_kmh), RetroUI.format_time(time_s),
	]
	_root.visible = true
	_first.grab_focus()


func is_open() -> bool:
	return _root.visible
