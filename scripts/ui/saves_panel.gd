class_name SavesPanel
extends PanelContainer
## SAUVEGARDES screen: pick the active slot, see its stats, erase it.

signal closed

var _list: VBoxContainer
var _confirm_delete := -1


func _ready() -> void:
	theme = RetroUI.theme()
	custom_minimum_size = Vector2(700, 520)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(RetroUI.label("SAUVEGARDES", 36))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_list)
	root.add_child(RetroUI.button("< RETOUR", func() -> void: closed.emit()))
	refresh()


func focus_first() -> void:
	var b := find_children("*", "Button", true, false)
	if not b.is_empty():
		(b[0] as Control).grab_focus()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for slot in range(1, Saves.SLOTS + 1):
		_list.add_child(_slot_row(slot))


func _slot_row(slot: int) -> Control:
	var box := VBoxContainer.new()
	var active := slot == Saves.active_slot
	var title := "SAUVEGARDE %d%s" % [slot, "   [ACTIVE]" if active else ""]
	box.add_child(RetroUI.label(title, 24, RetroUI.RED if active else RetroUI.AMBER))
	var info := "   -- vide --"
	if Saves.slot_exists(slot):
		var d := Saves.load_slot(slot)
		info = "   Record %s   |   %d km/h   |   %s   |   %d routes" % [
			RetroUI.format_distance(float(d.get("best_distance", 0.0))),
			int(float(d.get("top_speed", 0.0))),
			RetroUI.format_time(float(d.get("longest_time", 0.0))),
			int(d.get("runs", 0)),
		]
		if Saves.has_resume(slot):
			var r: Dictionary = d.get("resume", {})
			info += "\n   Route en cours : %s" % RetroUI.format_distance(float(r.get("distance", 0.0)))
	box.add_child(RetroUI.label(info, 17, RetroUI.DIM))
	var row := HBoxContainer.new()
	row.add_child(RetroUI.button("> UTILISER", func() -> void: _use(slot), 19))
	if Saves.slot_exists(slot):
		var del_text := "> CONFIRMER L'EFFACEMENT ?" if _confirm_delete == slot else "> EFFACER"
		row.add_child(RetroUI.button(del_text, func() -> void: _delete(slot), 19))
	box.add_child(row)
	return box


func _use(slot: int) -> void:
	Saves.active_slot = slot
	_confirm_delete = -1
	refresh()


func _delete(slot: int) -> void:
	if _confirm_delete == slot:
		Saves.delete_slot(slot)
		_confirm_delete = -1
	else:
		_confirm_delete = slot
	refresh()
