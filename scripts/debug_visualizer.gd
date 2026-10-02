class_name TysDebugVisualizer
extends Node3D
## F12 debug renderer: collision shapes, vehicle positions and bot waypaths.

var world: DesertWorld
var player: Yaris
var bot_manager: BotManager
var enabled := false
var refresh_timer := 0.0
var collision_timer := 0.0
var _collision_built := false
var root_3d: Node3D
var collision_root: Node3D
var labels_root: Node3D

var _materials: Dictionary = {}

func setup(p_world: DesertWorld, p_player: Yaris, p_bot_manager: BotManager) -> void:
	world = p_world
	player = p_player
	bot_manager = p_bot_manager
	visible = false
	_clear_drawings()

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if not enabled:
		_clear_drawings()
	else:
		refresh_timer = 0.0
		collision_timer = 0.0
		_collision_built = false
		_rebuild()

func _process(delta: float) -> void:
	if not enabled:
		return
	refresh_timer -= delta
	if refresh_timer <= 0.0:
		refresh_timer = 0.45
		_rebuild()

func _clear_drawings() -> void:
	if root_3d != null and is_instance_valid(root_3d):
		root_3d.queue_free()
	if collision_root != null and is_instance_valid(collision_root):
		collision_root.queue_free()
	if labels_root != null and is_instance_valid(labels_root):
		labels_root.queue_free()
	root_3d = Node3D.new()
	root_3d.name = "DebugDynamic"
	add_child(root_3d)
	collision_root = Node3D.new()
	collision_root.name = "DebugCollisions"
	add_child(collision_root)
	labels_root = Node3D.new()
	labels_root.name = "DebugLabels"
	add_child(labels_root)

func _rebuild() -> void:
	# Collision meshes are expensive to recreate. Build them once per debug session;
	# paths/labels can refresh independently.
	if world == null:
		return
	# Only dynamic drawings are rebuilt. Collision meshes are kept alive for the
	# whole debug session because recreating hundreds of meshes causes the lag spike.
	if root_3d != null and is_instance_valid(root_3d):
		for child in root_3d.get_children():
			child.queue_free()
	if labels_root != null and is_instance_valid(labels_root):
		for child in labels_root.get_children():
			child.queue_free()
	if not _collision_built:
		_draw_collision_shapes()
		_collision_built = true
	_draw_waypaths()
	_draw_vehicle_labels()

func _draw_collision_shapes() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var shapes := scene.find_children("*", "CollisionShape3D", true, false)
	for node in shapes:
		var cs := node as CollisionShape3D
		if cs == null or cs.shape == null or not cs.visible:
			continue
		var mesh := cs.shape.get_debug_mesh()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.global_transform = cs.global_transform
		mi.material_override = _material(_collision_color(cs))
		collision_root.add_child(mi)

func _collision_color(cs: CollisionShape3D) -> Color:
	var n: Node = cs
	while n != null:
		if n is Yaris:
			return Color(0.2, 0.95, 1.0, 0.42) if not (n as Yaris).bot_controlled else Color(0.3, 1.0, 0.35, 0.42)
		if n is TrafficCar:
			return Color(1.0, 0.72, 0.15, 0.42)
		if n is RoadObstacle:
			return Color(1.0, 0.25, 0.25, 0.42)
		n = n.get_parent()
	return Color(1.0, 1.0, 0.35, 0.30)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.wireframe = true
	_materials[key] = mat
	return mat

func _draw_waypaths() -> void:
	if bot_manager == null or bot_manager.waypath == null:
		return
	var planner := bot_manager.waypath
	for bot in bot_manager.bots:
		if not is_instance_valid(bot):
			continue
		var path: Array = planner.get_bot_path(bot)
		if path.is_empty():
			continue
		var mesh := ImmediateMesh.new()
		var color := _bot_color(bot)
		var mat := _line_material(color)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for wp in path:
			mesh.surface_add_vertex(wp.get("position", bot.global_position) + Vector3.UP * 0.18)
		mesh.surface_end()
		var line := MeshInstance3D.new()
		line.mesh = mesh
		root_3d.add_child(line)
		for wp in path:
			_draw_waypoint_marker(wp, color)

func _draw_waypoint_marker(wp: Dictionary, color: Color) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	marker.mesh = sphere
	marker.position = wp.get("position", Vector3.ZERO) + Vector3.UP * 0.18
	var marker_color := color
	if bool(wp.get("jump", false)):
		marker_color = Color(1.0, 0.2, 1.0, 0.9)
	marker.material_override = _material(marker_color)
	root_3d.add_child(marker)

func _line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	return mat

func _bot_color(bot: Yaris) -> Color:
	var idx := bot_manager.bots.find(bot)
	var palette := [
		Color(0.25, 1.0, 0.35), Color(1.0, 0.35, 0.8), Color(0.25, 0.75, 1.0),
		Color(1.0, 0.75, 0.2), Color(0.75, 0.4, 1.0), Color(0.2, 1.0, 0.85)
	]
	return palette[posmod(idx, palette.size())]

func _draw_vehicle_labels() -> void:
	if player != null and is_instance_valid(player):
		_add_vehicle_label(player, "PLAYER", Color(0.3, 0.95, 1.0))
	if bot_manager == null:
		return
	for i in bot_manager.bots.size():
		var bot := bot_manager.bots[i]
		if is_instance_valid(bot):
			_add_vehicle_label(bot, "BOT %02d" % (i + 1), _bot_color(bot))

func _add_vehicle_label(car: Yaris, title: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = "%s\nX %.1f  Y %.1f  Z %.1f\nSPD %.1f" % [title, car.global_position.x, car.global_position.y, car.global_position.z, car.speed]
	label.position = car.global_position + Vector3.UP * 3.2
	label.modulate = color
	label.font_size = 32
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	labels_root.add_child(label)
