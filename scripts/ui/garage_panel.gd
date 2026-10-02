class_name GaragePanel
extends PanelContainer
## Persistent vehicle showroom. Unlocks depend on total kilometres; purchases
## are paid with route credits earned from completed runs.

signal closed

const VEHICLES: Array[Dictionary] = [
	{"id":"clio_ii", "name":"RENAULT CLIO II", "kind":"VOITURE", "scene":"res://assets/traffic/renault_clio_ii.glb", "km":2500.0, "price":25000.0, "scale":1.59, "yaw":0.0},
	{"id":"peugeot_206", "name":"PEUGEOT 206", "kind":"VOITURE", "scene":"res://assets/traffic/peugeot_206.glb", "km":7500.0, "price":65000.0, "scale":0.041, "yaw":0.0},
	{"id":"golf_mk1", "name":"VOLKSWAGEN GOLF MK1", "kind":"VOITURE", "scene":"res://assets/traffic/vw_golf_mk1.glb", "km":15000.0, "price":140000.0, "scale":3.05, "yaw":0.0},
	{"id":"s2000", "name":"HONDA S2000", "kind":"SPORT", "scene":"res://assets/traffic/honda_s2000.glb", "km":30000.0, "price":300000.0, "scale":0.82, "yaw":0.0},
	{"id":"tank", "name":"TANK", "kind":"SPECIAL", "scene":"res://assets/traffic/tank.glb", "km":60000.0, "price":1000000.0, "scale":0.0044, "yaw":PI * 0.5},
]

var _index := 0
var _preview_view: SubViewport
var _preview_root: Node3D
var _preview_model: Node3D
var _name_label: Label
var _stats_label: Label
var _status_label: Label
var _funds_label: Label
var _buy_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(760, 560)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	left.add_child(RetroUI.label("GARAGE", 31, RetroUI.AMBER))
	left.add_child(RetroUI.label("PARC AUTOMOBILE", 14, RetroUI.RED))
	_name_label = RetroUI.label("", 23, RetroUI.AMBER)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_name_label)
	_stats_label = RetroUI.label("", 14, RetroUI.DIM)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_stats_label)
	_funds_label = RetroUI.label("", 15, RetroUI.AMBER)
	left.add_child(_funds_label)
	_status_label = RetroUI.label("", 13, RetroUI.DIM)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	_buy_button = RetroUI.button("> ACHETER", _buy_current, 21)
	left.add_child(_buy_button)
	left.add_child(RetroUI.button("> VOITURE SUIVANTE", _next, 19))
	left.add_child(RetroUI.button("> VOITURE PRÉCÉDENTE", _previous, 19))
	left.add_child(RetroUI.button("> RETOUR", func() -> void: closed.emit(), 19))

	_preview_view = SubViewport.new()
	_preview_view.size = Vector2i(390, 430)
	_preview_view.transparent_bg = false
	_preview_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_view.world_3d = World3D.new()
	var preview_container := SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(390, 430)
	preview_container.stretch = true
	preview_container.add_child(_preview_view)
	root.add_child(preview_container)
	_build_preview_scene()
	_refresh()

func _build_preview_scene() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "GaragePreview"
	_preview_view.add_child(_preview_root)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.02, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.7, 0.55)
	env.ambient_light_energy = 1.0
	env_node.environment = env
	_preview_root.add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 1.5
	_preview_root.add_child(light)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12, 12)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.09, 0.06)
	floor_mat.roughness = 0.95
	floor.material_override = floor_mat
	floor.position.y = -0.03
	_preview_root.add_child(floor)
	var cam := Camera3D.new()
	cam.position = Vector3(6.6, 2.9, 7.0)
	cam.fov = 34.0
	_preview_root.add_child(cam)
	cam.look_at(Vector3(0, 0.8, 0), Vector3.UP)

func _process(delta: float) -> void:
	if is_instance_valid(_preview_model):
		_preview_model.rotation.y += delta * 0.28

func _load_preview() -> void:
	if is_instance_valid(_preview_model):
		_preview_model.queue_free()
		_preview_model = null
	var data: Dictionary = VEHICLES[_index]
	var packed := load(String(data["scene"])) as PackedScene
	if packed == null:
		return
	_preview_model = packed.instantiate() as Node3D
	if _preview_model == null:
		return
	_preview_root.add_child(_preview_model)
	_preview_model.scale = Vector3.ONE * float(data["scale"])
	_preview_model.rotation.y = float(data["yaw"])
	_preview_model.position = Vector3(0, 0.02, 0)

func _refresh() -> void:
	var data: Dictionary = VEHICLES[_index]
	var save_data: Dictionary = Saves.garage_data()
	var total_km: float = float(save_data.get("total_distance", 0.0))
	var credits: float = float(save_data.get("garage_credits", 0.0))
	var purchased: bool = Saves.garage_is_purchased(String(data["id"]))
	var unlocked: bool = total_km >= float(data["km"])
	_name_label.text = String(data["name"])
	# Garage thresholds are stored directly in kilometres.
	_stats_label.text = "%s\n\nDÉBLOCAGE : %.1f KM\nPRIX : %s" % [String(data["kind"]), float(data["km"]), _money(float(data["price"]))]
	_funds_label.text = "FONDS GARAGE : %s\nKILOMÉTRAGE TOTAL : %.1f KM" % [_money(credits), total_km]
	if purchased:
		_status_label.text = "✓ ACHETÉ\nCe véhicule fait maintenant partie de ta collection."
		_buy_button.text = "> ACHETÉ"
		_buy_button.disabled = true
	elif not unlocked:
		_status_label.text = "🔒 Verrouillé — encore %.1f KM à parcourir." % maxf(float(data["km"]) - total_km, 0.0)
		_buy_button.text = "> ACHETER (VERROUILLÉ)"
		_buy_button.disabled = true
	elif credits < float(data["price"]):
		_status_label.text = "Disponible, mais tes fonds sont insuffisants."
		_buy_button.text = "> ACHETER — FONDS INSUFFISANTS"
		_buy_button.disabled = true
	else:
		_status_label.text = "Disponible à l'achat."
		_buy_button.text = "> ACHETER"
		_buy_button.disabled = false
	_load_preview()

func _buy_current() -> void:
	var data: Dictionary = VEHICLES[_index]
	if Saves.garage_buy(String(data["id"]), float(data["price"]), float(data["km"])):
		_refresh()

func _next() -> void:
	_index = (_index + 1) % VEHICLES.size()
	_refresh()

func _previous() -> void:
	_index = posmod(_index - 1, VEHICLES.size())
	_refresh()

func focus_first() -> void:
	if _buy_button:
		_buy_button.grab_focus()

func _money(value: float) -> String:
	return "%d €" % int(value)
