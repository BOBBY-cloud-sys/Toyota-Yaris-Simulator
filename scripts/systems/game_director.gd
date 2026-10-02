class_name GameDirector
extends Node
## Owns the run: start/resume, odometer, difficulty ramp, crashes and
## elimination, autosave, and the links between the Yaris, the world, the
## chase camera and the HUD. One authoritative place for run state.

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const AUTOSAVE_EVERY := 10.0

@export var yaris_path: NodePath = ^"../Yaris"
@export var world_path: NodePath = ^"../DesertWorld"
@export var camera_path: NodePath = ^"../Camera3D"
@export var hud_path: NodePath = ^"../HUD"
@export var game_over_path: NodePath = ^"../GameOver"
@export var environment_path: NodePath = ^"../WorldEnvironment"

var yaris: Yaris
var world: DesertWorld
var cam: ChaseCamera
var hud: RetroHud
var game_over: GameOverScreen
var env_node: WorldEnvironment
var bot_manager: BotManager
var _run_seed := 0
var _vs_bots_config: Dictionary = {}

var state := "running"  # running | dead
var odometer := 0.0
var elapsed := 0.0
var top_speed_kmh := 0.0
var debug_visible := false

var _last_pos := Vector3.ZERO
var _difficulty := 0.0
var _autosave_t := 0.0
var _debug_label: Label
var _debug_visualizer: TysDebugVisualizer
var _resumed_from_distance := 0.0


func _ready() -> void:
	yaris = get_node_or_null(yaris_path) as Yaris
	world = get_node_or_null(world_path) as DesertWorld
	cam = get_node_or_null(camera_path) as ChaseCamera
	hud = get_node_or_null(hud_path) as RetroHud
	game_over = get_node_or_null(game_over_path) as GameOverScreen
	env_node = get_node_or_null(environment_path) as WorldEnvironment
	if yaris:
		yaris.landed.connect(_on_landed)
		yaris.crashed.connect(_on_crashed)
		yaris.splashed.connect(_on_splashed)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	call_deferred("_setup_run")


func _setup_run() -> void:
	if yaris == null or world == null:
		return
	var run_seed := Saves.pending_seed
	var chunk := 0
	var resume: Dictionary = Saves.pending_resume
	var resumed := not resume.is_empty()
	if resumed:
		run_seed = int(resume.get("seed", 0))
		chunk = int(resume.get("chunk", 0))
		odometer = float(resume.get("distance", 0.0))
		_resumed_from_distance = odometer
		elapsed = float(resume.get("time", 0.0))
		top_speed_kmh = float(resume.get("top_speed", 0.0))
	if run_seed == 0:
		run_seed = randi_range(1, 999999999)
	var vs_bots: Dictionary = Saves.pending_vs_bots
	_run_seed = run_seed
	_vs_bots_config = vs_bots.duplicate(true)
	Saves.pending_resume = {}
	Saves.pending_seed = 0
	Saves.pending_vs_bots = {}
	world.start(run_seed, chunk)
	yaris.reset_to(world.spawn_transform())
	world.update_streaming(yaris.global_position)
	_last_pos = yaris.global_position
	if cam:
		cam.snap()
	if not resumed and not vs_bots.is_empty():
		bot_manager = BotManager.new()
		bot_manager.name = "VS Bots"
		add_child(bot_manager)
		bot_manager.setup(world, yaris, int(vs_bots.get("count", 1)), int(vs_bots.get("difficulty", 0)))
	if _debug_visualizer == null:
		_debug_visualizer = TysDebugVisualizer.new()
		_debug_visualizer.name = "TYS Debug Visualizer"
		add_child(_debug_visualizer)
	_debug_visualizer.setup(world, yaris, bot_manager)
	if hud:
		if not vs_bots.is_empty():
			hud.flash("VS BOTS  •  %d RIVAUX" % int(vs_bots.get("count", 1)), 2.0)
		else:
			hud.flash("ROUTE REPRISE" if resumed else "EN ROUTE !", 1.6)


func _process(delta: float) -> void:
	if yaris == null or world == null:
		return
	var p: Vector3 = yaris.global_position
	if bot_manager != null:
		var stream_positions: Array[Vector3] = [p]
		for bot in bot_manager.bots:
			if is_instance_valid(bot):
				stream_positions.append(bot.global_position)
		world.update_streaming_for_positions(stream_positions)
	else:
		world.update_streaming(p)
	if state == "running":
		elapsed += delta
		odometer += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
		var kmh: float = yaris.current_kmh()
		top_speed_kmh = maxf(top_speed_kmh, kmh)
		_difficulty = clampf(odometer / 6000.0, 0.0, 1.0)
		yaris.difficulty = _difficulty
		var road_y: float = world.road_transform_near(p).origin.y
		if p.y < road_y - 15.0:
			eliminate("Chute dans le vide")
		_autosave_t += delta
		if _autosave_t >= AUTOSAVE_EVERY:
			_autosave_t = 0.0
			Saves.update_progress(_run_dict())
		if hud:
			hud.set_speed(kmh)
			hud.set_distance(odometer)
	elif p.y < world.fall_plane():
		yaris.set_physics_process(false)
	_last_pos = p
	if debug_visible:
		_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	# F12 is the dedicated debug toggle. The input action is kept as well,
	# but this direct check makes the debug key reliable even if the
	# project input map is regenerated/overwritten.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		toggle_debug()
		return

	if event.is_action_pressed("reset"):
		if state == "running":
			respawn("RÉINITIALISÉ")
		else:
			restart_run()
	elif event.is_action_pressed("debug_overlay"):
		toggle_debug()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and state == "running":
		Saves.update_progress(_run_dict())


# ------------------------------------------------------------------ run flow

func can_pause() -> bool:
	return state == "running"


func respawn(reason := "RÉINITIALISÉ") -> void:
	if yaris == null or world == null:
		return
	yaris.reset_to(world.road_transform_near(yaris.global_position))
	_last_pos = yaris.global_position
	if hud:
		hud.flash(reason, 1.2)


func eliminate(reason: String) -> void:
	if state != "running":
		return
	state = "dead"
	yaris.can_drive = false
	if cam:
		cam.add_shake(0.9)
	if hud:
		hud.set_speed(0.0)
	Saves.finish_run(_run_dict())
	await get_tree().create_timer(1.4).timeout
	if game_over:
		game_over.show_result(reason, odometer, top_speed_kmh, elapsed)


func restart_run() -> void:
	if state == "running":
		Saves.finish_run(_run_dict())
	state = "dead"
	get_tree().paused = false
	Saves.pending_resume = {}
	# A bot race restarts as the same race configuration, not as a solo run.
	# Reuse the same seed so the road/obstacles remain the same course.
	Saves.pending_seed = _run_seed
	Saves.pending_vs_bots = _vs_bots_config.duplicate(true)
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	if state == "running":
		Saves.update_progress(_run_dict())
	state = "dead"
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _run_dict() -> Dictionary:
	var chunk := 0
	if world and yaris:
		chunk = maxi(world.nearest_index(yaris.global_position), 0)
	return {
		"seed": world.world_seed if world else 0,
		"chunk": chunk,
		"distance": odometer,
		"time": elapsed,
		"top_speed": top_speed_kmh,
		"resumed_from": _resumed_from_distance,
	}


# ------------------------------------------------------------------ feedback

func _on_crashed(strength: float, lethal_reason: String) -> void:
	if cam:
		cam.add_shake(clampf(strength * 0.035, 0.1, 1.2))
	if lethal_reason != "":
		eliminate(lethal_reason)
	elif hud and strength > 18.0:
		hud.flash("BOUM !", 0.8)


func _on_splashed() -> void:
	if hud:
		hud.flash("SPLASH !", 0.7)


func _on_landed(impact: float) -> void:
	if cam:
		cam.add_shake(clampf(impact * 0.06, 0.0, 0.8))
	if hud and impact > 16.0:
		hud.flash("GROS SAUT !", 1.0)


func _apply_settings() -> void:
	if cam:
		cam.shake_scale = Settings.shake_amount()
		cam.follow_smoothing = 5.0 / Settings.camera_smoothing
		cam.height_smoothing = 3.2 / Settings.camera_smoothing
		cam.turn_smoothing = 7.0 * Settings.camera_sensitivity
	if env_node:
		Settings.apply_environment(env_node.environment)


# ------------------------------------------------------------------ debug

func toggle_debug() -> void:
	debug_visible = not debug_visible
	if _debug_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		_debug_label = Label.new()
		_debug_label.add_theme_font_size_override("font_size", 16)
		_debug_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_debug_label.add_theme_constant_override("outline_size", 4)
		_debug_label.position = Vector2(28, 70)
		layer.add_child(_debug_label)
	_debug_label.visible = debug_visible
	if _debug_visualizer != null:
		_debug_visualizer.set_enabled(debug_visible)


func _update_debug() -> void:
	if _debug_label == null or yaris == null:
		return
	var p: Vector3 = yaris.global_position
	_debug_label.text = "FPS %d\nPOS %.1f / %.1f / %.1f\nSPEED %.1f M/S\nVEL %.1f / %.1f / %.1f\nCHUNK %d\nDIST %.0f M\nDIFF %.2f\nSEED %d\nFLOOR %s" % [
		Engine.get_frames_per_second(), p.x, p.y, p.z, yaris.speed,
		yaris.velocity.x, yaris.velocity.y, yaris.velocity.z,
		world.nearest_index(p) if world else -1, odometer, _difficulty,
		world.world_seed if world else 0, str(yaris.is_on_floor()),
	]
