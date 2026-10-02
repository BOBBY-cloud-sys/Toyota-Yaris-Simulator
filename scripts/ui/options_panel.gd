class_name OptionsPanel
extends PanelContainer
## Options screen, shared by the main menu and the pause menu.
## Every control writes straight into the Settings autoload (auto-saved).

signal closed

var _test_player: AudioStreamPlayer


func _ready() -> void:
	theme = RetroUI.theme()
	custom_minimum_size = Vector2(700, 600)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(RetroUI.label("OPTIONS", 36))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	_section(box, "AUDIO")
	_slider(box, "Volume général", "master_volume", 0.0, 1.0, 0.05, true)
	_slider(box, "Musique", "music_volume", 0.0, 1.0, 0.05, true)
	_slider(box, "Effets", "sfx_volume", 0.0, 1.0, 0.05, true)
	box.add_child(RetroUI.button("> TESTER LE SON", _test_sound, 20))

	_section(box, "CONTRÔLES")
	var lay := Settings.layout_name()
	box.add_child(RetroUI.label("Clavier détecté : %s" % lay, 18))
	box.add_child(RetroUI.label("AZERTY : Q / D diriger   Z accélérer   S freiner", 17, RetroUI.AMBER if lay == "AZERTY" else RetroUI.DIM))
	box.add_child(RetroUI.label("QWERTY : A / D diriger   W accélérer   S freiner", 17, RetroUI.AMBER if lay == "QWERTY" else RetroUI.DIM))
	box.add_child(RetroUI.label("ESPACE sauter   R réinitialiser   ÉCHAP pause   (flèches aussi)", 17, RetroUI.DIM))
	_slider(box, "Sensibilité direction", "steer_sensitivity", 0.5, 1.5, 0.05, false)

	_section(box, "CAMÉRA")
	_slider(box, "Sensibilité caméra", "camera_sensitivity", 0.5, 2.0, 0.05, false)
	_slider(box, "Lissage caméra", "camera_smoothing", 0.5, 2.0, 0.05, false)
	_slider(box, "Tremblements (0 = off)", "camera_shake", 0.0, 1.5, 0.05, true)

	_section(box, "VISUEL")
	_slider(box, "Luminosité", "brightness", 0.6, 1.4, 0.02, false)
	_slider(box, "Contraste", "contrast", 0.6, 1.4, 0.02, false)
	_slider(box, "Saturation", "saturation", 0.0, 1.6, 0.02, false)

	_section(box, "ACCESSIBILITÉ")
	var cb := CheckBox.new()
	cb.text = "Réduire flashs et effets intenses (épilepsie)"
	cb.add_theme_font_size_override("font_size", 18)
	cb.button_pressed = Settings.reduce_flashing
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value("reduce_flashing", on))
	box.add_child(cb)

	root.add_child(RetroUI.button("< RETOUR", func() -> void: closed.emit()))

	_test_player = AudioStreamPlayer.new()
	_test_player.bus = &"SFX"
	_test_player.stream = _beep()
	add_child(_test_player)


func focus_first() -> void:
	var b := find_children("*", "Button", true, false)
	if not b.is_empty():
		(b[0] as Control).grab_focus()


func _section(parent: Control, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	parent.add_child(spacer)
	parent.add_child(RetroUI.label("== %s ==" % title, 22, RetroUI.RED))


func _slider(parent: Control, text: String, key: String, mn: float, mx: float, step: float, percent: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := RetroUI.label(text, 18)
	l.custom_minimum_size = Vector2(290, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 22)
	row.add_child(s)
	var v := RetroUI.label(_fmt(s.value, percent), 18)
	v.custom_minimum_size = Vector2(70, 0)
	row.add_child(v)
	s.value_changed.connect(func(val: float) -> void:
		Settings.set_value(key, val)
		v.text = _fmt(val, percent))
	parent.add_child(row)


func _fmt(val: float, percent: bool) -> String:
	if percent:
		return "%d%%" % roundi(val * 100.0)
	return "x%.2f" % val


func _test_sound() -> void:
	_test_player.play()


func _beep() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.36)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var f := 660.0 if t < 0.18 else 990.0
		var v := sin(TAU * f * t) * 0.45 * (1.0 - t / 0.36)
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
