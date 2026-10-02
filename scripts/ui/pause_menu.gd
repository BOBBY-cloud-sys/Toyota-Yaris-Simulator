class_name PauseMenu
extends CanvasLayer
## ESC pause menu. Stops the simulation (SceneTree.paused) and keeps running
## itself so its buttons still work.

@export var director_path: NodePath = ^"../Game"

var director: GameDirector
var _root: Control
var _menu: PanelContainer
var _options: OptionsPanel


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	director = get_node_or_null(director_path) as GameDirector
	_root = Control.new()
	_root.theme = RetroUI.theme()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_menu = PanelContainer.new()
	_menu.custom_minimum_size = Vector2(420, 0)
	center.add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_menu.add_child(box)
	box.add_child(RetroUI.label("PAUSE", 52))
	box.add_child(RetroUI.button("> Reprendre", resume))
	box.add_child(RetroUI.button("> Options", _show_options))
	box.add_child(RetroUI.button("> Recommencer", func() -> void:
		if director:
			director.restart_run()))
	box.add_child(RetroUI.button("> Menu principal", func() -> void:
		if director:
			director.quit_to_menu()))

	_options = OptionsPanel.new()
	_options.visible = false
	center.add_child(_options)
	_options.closed.connect(_hide_options)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if _root.visible:
		if _options.visible:
			_hide_options()
		else:
			resume()
	elif director == null or director.can_pause():
		open()


func open() -> void:
	get_tree().paused = true
	_root.visible = true
	_hide_options()


func resume() -> void:
	_root.visible = false
	get_tree().paused = false


func _show_options() -> void:
	_menu.visible = false
	_options.visible = true
	_options.focus_first()


func _hide_options() -> void:
	_options.visible = false
	_menu.visible = true
	var first := _menu.find_children("*", "Button", true, false)
	if not first.is_empty():
		(first[0] as Control).grab_focus()
