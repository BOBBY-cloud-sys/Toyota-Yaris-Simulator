class_name MainMenu
extends Control
## TYS main menu: old-PC / Garry's Mod-like layout.
## Left: menu + title placeholder. Right: animated Yaris on a small desert-road scene.

const GAME_SCENE := "res://main.tscn"

var _menu_box: PanelContainer
var _resume_button: Button
var _panel_layer: Control
var _menu_root: VBoxContainer
var _menu_3d: Node3D
var _menu_car: Yaris
var _menu_car_base_y := 0.35
var _menu_car_body_base_scale := Vector3.ONE
var _menu_car_time := 0.0
var _road: MeshInstance3D
var _sand: MeshInstance3D
var _menu_bots: Array[Yaris] = []
var _menu_bot_start_z: Array[float] = []
var _menu_bot_time := 0.0

func _ready() -> void:
	theme = RetroUI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_3d_background()
	_build_overlay()
	_build_menu()
	_refresh_resume()
	_focus_first()

func _process(delta: float) -> void:
	_menu_car_time += delta
	_menu_bot_time += delta
	if is_instance_valid(_menu_car):
		# Small idle bounce/sway instead of the full driving physics.
		var bounce := sin(_menu_car_time * 3.2) * 0.055
		var sway := sin(_menu_car_time * 1.6) * 0.025
		_menu_car.position.y = _menu_car_base_y + bounce
		var body := _menu_car.get_node_or_null("Model/Body") as Node3D
		if body:
			body.rotation = Vector3(sin(_menu_car_time * 3.2) * 0.035, PI, sway)
			body.scale = _menu_car_body_base_scale * (1.0 + sin(_menu_car_time * 3.2) * 0.018)
		# Slowly move the road under the car for a cheap animated-road effect.
		if is_instance_valid(_road):
			_road.position.z = fposmod(_menu_car_time * 3.0, 12.0) - 6.0
	if is_instance_valid(_sand):
		_sand.rotation.y = sin(_menu_car_time * 0.04) * 0.002
	for i in _menu_bots.size():
		var bot := _menu_bots[i]
		if not is_instance_valid(bot):
			continue
		# The background racers are purely visual: they rush down the road
		# without consuming gameplay/physics resources.
		bot.position.z = fposmod(_menu_bot_start_z[i] - _menu_bot_time * 16.0 + 52.0, 60.0) - 52.0
		var body := bot.get_node_or_null("Model/Body") as Node3D
		if body:
			body.rotation = Vector3(0.0, PI, sin(_menu_bot_time * 7.0 + float(i)) * 0.018)

func _build_3d_background() -> void:
	_menu_3d = Node3D.new()
	_menu_3d.name = "Menu3D"
	add_child(_menu_3d)
	move_child(_menu_3d, 0)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.13, 0.22, 0.42)
	sky_mat.sky_horizon_color = Color(0.82, 0.62, 0.38)
	sky_mat.ground_bottom_color = Color(0.36, 0.25, 0.15)
	sky_mat.ground_horizon_color = Color(0.68, 0.47, 0.27)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	_menu_3d.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.68)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	_menu_3d.add_child(sun)

	# Large desert floor.
	_sand = MeshInstance3D.new()
	var sand_mesh := PlaneMesh.new()
	sand_mesh.size = Vector2(90.0, 90.0)
	_sand.mesh = sand_mesh
	_sand.material_override = _material(Color(0.62, 0.45, 0.25), 0.98)
	_sand.position = Vector3(5.0, -0.06, -14.0)
	_menu_3d.add_child(_sand)

	# Road on the right side of the screen.
	_road = MeshInstance3D.new()
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(10.0, 0.12, 75.0)
	_road.mesh = road_mesh
	_road.material_override = _material(Color(0.075, 0.068, 0.06), 0.88)
	_road.position = Vector3(5.0, 0.0, -18.0)
	_menu_3d.add_child(_road)

	# Simple road markings.
	for z in range(-52, 25, 9):
		var mark := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.18, 0.025, 4.2)
		mark.mesh = mm
		mark.material_override = _material(Color(0.86, 0.78, 0.48), 0.7)
		mark.position = Vector3(5.0, 0.075, float(z))
		_menu_3d.add_child(mark)

	# A few distant rocks to make the scene feel alive.
	for data in [Vector3(-2.0, 0.0, -18.0), Vector3(13.0, 0.0, -34.0), Vector3(-7.0, 0.0, -42.0), Vector3(16.0, 0.0, -10.0)]:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 7
		sm.rings = 4
		rock.mesh = sm
		rock.material_override = _material(Color(0.38, 0.25, 0.16), 0.95)
		rock.scale = Vector3(1.2, 0.65, 1.0)
		rock.position = data + Vector3(0.0, 0.42, 0.0)
		_menu_3d.add_child(rock)

	_menu_car = preload("res://scenes/yaris.tscn").instantiate() as Yaris
	_menu_car.name = "MenuYaris"
	_menu_car.can_drive = false
	_menu_car.dance_enabled = false
	_menu_car.position = Vector3(5.0, _menu_car_base_y, -1.5)
	_menu_car.heading = 0.0
	_menu_3d.add_child(_menu_car)
	var menu_body := _menu_car.get_node_or_null("Model/Body") as Node3D
	if menu_body:
		_menu_car_body_base_scale = menu_body.scale

	# Background traffic: four/five Yaris racers on the left half of the
	# road, deliberately visible behind the menu car.
	var bot_x := [1.55, 2.65, 3.55, 1.95, 3.05]
	var bot_z := [-7.0, -17.0, -28.0, -39.0, -49.0]
	for i in 5:
		var bot := preload("res://scenes/yaris.tscn").instantiate() as Yaris
		if bot == null:
			continue
		bot.name = "MenuBot_%02d" % (i + 1)
		bot.can_drive = false
		bot.dance_enabled = false
		bot.heading = 0.0
		bot.position = Vector3(float(bot_x[i]), 0.35, float(bot_z[i]))
		_menu_3d.add_child(bot)
		_menu_bots.append(bot)
		_menu_bot_start_z.append(float(bot_z[i]))

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 48.0
	cam.position = Vector3(17.5, 2.45, 7.5)
	_menu_3d.add_child(cam)
	cam.look_at(Vector3(5.0, 0.95, -10.0), Vector3.UP)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _build_overlay() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# CRT scanlines, intentionally subtle.
	for y in range(0, 768, 6):
		var line := ColorRect.new()
		line.color = Color(0.0, 0.0, 0.0, 0.045)
		line.position = Vector2(0, y)
		line.size = Vector2(1024, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)

func _build_menu() -> void:
	var left := MarginContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.anchor_right = 0.47
	left.offset_left = 28.0
	left.offset_top = 28.0
	left.offset_right = -20.0
	left.offset_bottom = -28.0
	add_child(left)

	_menu_box = PanelContainer.new()
	_menu_box.custom_minimum_size = Vector2(390, 0)
	left.add_child(_menu_box)

	_menu_root = VBoxContainer.new()
	_menu_root.add_theme_constant_override("separation", 3)
	_menu_box.add_child(_menu_root)

	# Actual game logo. The PNG is kept in assets so it can be replaced
	# without touching the menu code.
	if ResourceLoader.exists("res://assets/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/logo.png") as Texture2D
		logo.custom_minimum_size = Vector2(0.0, 220.0)
		logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_root.add_child(logo)
	else:
		var title := RetroUI.label("DANCING TOYOTA\\nYARIS SIMULATOR", 31, RetroUI.AMBER)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu_root.add_child(title)
		_menu_root.add_child(RetroUI.label("[ LOGO — PLACEHOLDER ]", 13, RetroUI.DIM))
	_menu_root.add_child(RetroUI.label("", 7))
	_menu_root.add_child(RetroUI.label("MAIN ROUTE TERMINAL", 14, RetroUI.RED))
	_menu_root.add_child(RetroUI.label("--------------------------------", 13, RetroUI.DIM))

	_menu_root.add_child(RetroUI.button("> COMMENCER MA ROUTE", _new_route, 23))
	_resume_button = RetroUI.button("> REPRENDRE MA ROUTE", _resume_route, 23)
	_menu_root.add_child(_resume_button)
	_menu_root.add_child(RetroUI.button("> GARAGE", _show_garage, 23))
	_menu_root.add_child(RetroUI.button("> VS BOTS", _show_vs_bots, 23))
	_menu_root.add_child(RetroUI.button("> SAUVEGARDES", _show_saves, 23))
	_menu_root.add_child(RetroUI.button("> OPTIONS", _show_options, 23))
	_menu_root.add_child(RetroUI.button("> QUITTER", _quit, 23))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_root.add_child(spacer)
	_menu_root.add_child(RetroUI.label("4:3  /  COMPATIBILITY RENDERER", 12, RetroUI.DIM))
	_menu_root.add_child(RetroUI.label("ZQSD / WASD / FLÈCHES   •   ESPACE : SAUT", 12, RetroUI.DIM))

	_panel_layer = Control.new()
	_panel_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_layer.visible = false
	add_child(_panel_layer)

func _refresh_resume() -> void:
	if _resume_button == null:
		return
	var slot := Saves.latest_resumable_slot()
	_resume_button.disabled = slot < 0
	_resume_button.text = "> REPRENDRE MA ROUTE" if slot >= 0 else "> REPRENDRE MA ROUTE   [AUCUNE]"

func _new_route() -> void:
	Saves.pending_resume = {}
	Saves.pending_seed = randi_range(1, 999999999)
	Saves.pending_vs_bots = {}
	get_tree().change_scene_to_file(GAME_SCENE)

func _resume_route() -> void:
	var slot := Saves.latest_resumable_slot()
	if slot < 0:
		return
	Saves.active_slot = slot
	var data := Saves.load_slot(slot)
	Saves.pending_resume = data.get("resume", {})
	Saves.pending_seed = 0
	Saves.pending_vs_bots = {}
	get_tree().change_scene_to_file(GAME_SCENE)

func _show_garage() -> void:
	_open_panel(GaragePanel.new())

func _show_vs_bots() -> void:
	var panel := _build_vs_bots_panel()
	_open_panel(panel)

func _build_vs_bots_panel() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(470, 360)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	box.add_child(root)

	root.add_child(RetroUI.label("VS BOTS", 31, RetroUI.AMBER))
	root.add_child(RetroUI.label("COURSE CONTRE DES YARIS IA", 14, RetroUI.RED))
	root.add_child(RetroUI.label("Nombre de bots", 16, RetroUI.DIM))
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 64
	count.step = 1
	count.value = 7
	count.allow_greater = false
	count.custom_minimum_size = Vector2(180, 34)
	root.add_child(count)

	root.add_child(RetroUI.label("Difficulté", 16, RetroUI.DIM))
	var difficulty := OptionButton.new()
	difficulty.add_item("DÉBUTANT  —  ne saute jamais")
	difficulty.add_item("NOVICE  —  premières esquives")
	difficulty.add_item("PILOTE  —  sauts et trajectoires")
	difficulty.add_item("EXPERT  —  drifts et réactions rapides")
	difficulty.add_item("MASTER  —  précision extrême + cascades")
	difficulty.select(2)
	difficulty.custom_minimum_size = Vector2(430, 36)
	root.add_child(difficulty)

	var info := RetroUI.label("MASTER peut drifter, sauter avec précision, éviter presque\nparfaitement les obstacles et tenter occasionnellement\nde retomber sur les voitures de trafic.", 12, RetroUI.DIM)
	root.add_child(info)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	root.add_child(RetroUI.button("> LANCER LA COURSE", func() -> void:
		_start_vs_bots(int(count.value), difficulty.selected)
		, 22))
	root.add_child(RetroUI.button("> ANNULER", func() -> void:
		_close_current_panel()
		, 20))
	return box

func _start_vs_bots(bot_count: int, difficulty: int) -> void:
	Saves.pending_resume = {}
	Saves.pending_seed = randi_range(1, 999999999)
	Saves.pending_vs_bots = {"count": clampi(bot_count, 1, 64), "difficulty": clampi(difficulty, 0, 4)}
	get_tree().change_scene_to_file(GAME_SCENE)

func _close_current_panel() -> void:
	for child in _panel_layer.get_children():
		child.queue_free()
	_panel_layer.visible = false
	_menu_box.visible = true
	_refresh_resume()
	_focus_first()

func _show_saves() -> void:
	_open_panel(SavesPanel.new())

func _show_options() -> void:
	_open_panel(OptionsPanel.new())

func _open_panel(panel: Control) -> void:
	_menu_box.visible = false
	_panel_layer.visible = true
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_layer.add_child(center)
	center.add_child(panel)
	if panel is SavesPanel:
		(panel as SavesPanel).closed.connect(func() -> void: _close_panel(panel, center))
	elif panel is GaragePanel:
		(panel as GaragePanel).closed.connect(func() -> void: _close_panel(panel, center))
	elif panel is OptionsPanel:
		(panel as OptionsPanel).closed.connect(func() -> void: _close_panel(panel, center))
	if panel.has_method("focus_first"):
		panel.call("focus_first")

func _close_panel(panel: Control, center: CenterContainer) -> void:
	if is_instance_valid(center):
		center.queue_free()
	elif is_instance_valid(panel):
		panel.queue_free()
	_panel_layer.visible = false
	_menu_box.visible = true
	_refresh_resume()
	_focus_first()

func _focus_first() -> void:
	if _menu_root == null:
		return
	var buttons := _menu_root.find_children("*", "Button", true, false)
	if not buttons.is_empty():
		(buttons[0] as Control).grab_focus()

func _quit() -> void:
	get_tree().quit()
