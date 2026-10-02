class_name DesertWorld
extends Node3D
## Endless procedural desert road.
##
## Road and shoulder chunks are built ahead of the player and freed behind them,
## so the drive never ends. The whole layout is a pure function of world_seed:
## the same seed always rebuilds the same road.

@export var world_seed := 20260928
@export var chunk_length := 60.0
@export var road_width := 15.0
@export var road_thickness := 1.4
@export var shoulder_width := 110.0
@export var shoulder_thickness := 3.0
@export var chunks_ahead := 7
@export var chunks_behind := 3
@export var curve_amount := 0.15
@export var hill_height := 3.0
@export var hill_wavelength := 260.0
@export var fall_depth := 70.0

# TERRAIN UPDATE: rare dramatic road events.
# A cliff removes a complete chunk of road and resumes the circuit lower down.
# A mega-hill raises the road for a few chunks before bringing it back down.
const TERRAIN_NONE := 0
const TERRAIN_CLIFF := 1
const TERRAIN_HILL := 2
const TERRAIN_FIRST_EVENT_CHUNK := 6
const TERRAIN_MIN_EVENT_GAP := 4
const CLIFF_CHANCE := 0.055
const HILL_CHANCE := 0.075
const CLIFF_DROP := 18.0
const HILL_EXTRA_HEIGHT := 32.0
const HILL_LENGTH_CHUNKS := 4.0

var _terrain_events: Dictionary = {}
var _terrain_last_special := -999

var _chunks: Dictionary = {}
var _next_index := 0
var _next_pos := Vector3.ZERO
var _next_yaw := 0.0
var _start_pos := Vector3.ZERO
var _start_yaw := 0.0
var _lowest := 0.0
var _phase_h := 0.0
var _phase_c := 0.0
var _mat_road: StandardMaterial3D
var _mat_shoulder: StandardMaterial3D
var _mat_line: StandardMaterial3D
var _mat_edge: StandardMaterial3D
var _rear_safety: StaticBody3D


var _segments: Dictionary = {}
var _spawner: ObstacleSpawner
var _started := false


func _ready() -> void:
	_build_materials()


## Build the road for a seed. start_chunk > 0 resumes a saved route: the path
## up to that chunk is recomputed (cheaply, no meshes) so the layout matches.
func start(p_seed: int, start_chunk := 0) -> void:
	_terrain_events.clear()
	_terrain_last_special = -999
	for c in get_children():
		c.queue_free()
	_chunks.clear()
	_segments.clear()
	world_seed = p_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_phase_h = rng.randf() * TAU
	_phase_c = rng.randf() * TAU
	_spawner = ObstacleSpawner.new(self)
	_spawner.calm_until = maxi(ObstacleSpawner.CALM_CHUNKS, start_chunk + 2)
	_next_pos = Vector3(0.0, _height_at(0.0), 0.0)
	_next_yaw = 0.0
	for i in maxi(start_chunk, 0):
		var end := _next_pos + Vector3(-sin(_next_yaw), 0.0, -cos(_next_yaw)) * chunk_length
		end.y = _height_at(float(i + 1) * chunk_length)
		_next_pos = end
		_next_yaw = wrapf(_next_yaw + _curve_step(i), -PI, PI)
	_start_pos = _next_pos
	_start_yaw = _next_yaw
	_lowest = _start_pos.y
	_build_rear_safety_floor()
	_next_index = maxi(start_chunk, 0)
	for k in chunks_ahead + 1:
		_add_chunk(_next_index)
		_next_index += 1
	_started = true


func _build_rear_safety_floor() -> void:
	if is_instance_valid(_rear_safety):
		_rear_safety.queue_free()
	_rear_safety = StaticBody3D.new()
	_rear_safety.name = "TemporaryRearSafetyFloor"
	add_child(_rear_safety)
	var length := 220.0
	var width := maxf(shoulder_width * 2.0, 260.0)
	# Behind the start, using the reverse of the initial road direction.
	var center := _start_pos + Vector3(sin(_start_yaw), 0.0, cos(_start_yaw)) * (length * 0.5)
	center.y = _start_pos.y - 0.8
	_rear_safety.transform = Transform3D(Basis(Vector3.UP, _start_yaw), center)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 1.6, length)
	mesh.mesh = box
	mesh.material_override = _mat_shoulder
	_rear_safety.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(width, 1.6, length)
	shape.shape = box_shape
	_rear_safety.add_child(shape)


func start_chunk_index() -> int:
	var lowest := -1
	for k in _chunks.keys():
		var ki := int(k)
		if lowest == -1 or ki < lowest:
			lowest = ki
	return maxi(lowest, 0)


func has_road_at(s: float) -> bool:
	return _segments.has(int(floor(s)))


## Road-top transform at road position s (in chunk units), offset sideways.
func road_transform_at(s: float, lateral: float) -> Transform3D:
	var i := int(floor(s))
	if not _segments.has(i):
		return spawn_transform()
	var seg: Array = _segments[i]
	var a: Vector3 = seg[0]
	var b: Vector3 = seg[1]
	var p := a.lerp(b, s - float(i))
	var f := (b - a).normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u: Vector3 = r.cross(f).normalized()
	return Transform3D(Basis(r, u, -f), p + r * lateral)


## Build chunks ahead of the player and free the ones far behind them.
func update_streaming(pos: Vector3) -> void:
	var ci := nearest_index(pos)
	if ci < 0:
		return
	while _next_index <= ci + chunks_ahead:
		_add_chunk(_next_index)
		_next_index += 1
	var doomed: Array = []
	for k in _chunks.keys():
		if int(k) < ci - chunks_behind:
			doomed.append(k)
	for k in doomed:
		var n: Node = _chunks[k]
		_chunks.erase(k)
		_segments.erase(k)
		if is_instance_valid(n):
			n.queue_free()

## Streaming variant used by VS BOTS. The road is generated ahead of the
## fastest racer but its rear edge follows the slowest active racer, so a bot
## can actually react to the collapsing world instead of losing its road under
## its wheels in a single frame.
func update_streaming_for_positions(positions: Array[Vector3]) -> void:
	if positions.is_empty():
		return
	var min_ci := INF
	var max_ci := -INF
	for pos in positions:
		var ci := nearest_index(pos)
		if ci < 0:
			continue
		min_ci = minf(float(min_ci), float(ci))
		max_ci = maxf(float(max_ci), float(ci))
	if max_ci == -INF:
		return
	while _next_index <= int(max_ci) + chunks_ahead:
		_add_chunk(_next_index)
		_next_index += 1
	var doomed: Array = []
	for k in _chunks.keys():
		if int(k) < int(min_ci) - chunks_behind:
			doomed.append(k)
	for k in doomed:
		var n: Node = _chunks[k]
		_chunks.erase(k)
		_segments.erase(k)
		if is_instance_valid(n):
			n.queue_free()


func nearest_index(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for k in _chunks.keys():
		var n := _chunks[k] as Node3D
		if n == null:
			continue
		var d := n.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = int(k)
	return best


## Grid position for a fresh run, on the road, facing down the road.
func spawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _start_yaw), _start_pos + Vector3.UP * 0.3)


## Exact road transform near a world position. The old implementation used the
## chunk origin, which is not the point of the road nearest to the car. Bots
## therefore steered toward chunk starts and could leave the road.
func road_transform_near(pos: Vector3) -> Transform3D:
	var centre := nearest_index(pos)
	if centre < 0:
		return spawn_transform()
	var best_d := INF
	var best_p := Vector3.ZERO
	var best_f := Vector3(0.0, 0.0, -1.0)
	for i in range(centre - 1, centre + 2):
		if not _segments.has(i):
			continue
		var seg: Array = _segments[i]
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var ab := b - a
		var ab_len_sq := ab.length_squared()
		if ab_len_sq < 0.0001:
			continue
		var t := clampf((pos - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var p := a.lerp(b, t)
		var d := p.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_p = p
			best_f = ab.normalized()
	var r := best_f.cross(Vector3.UP).normalized()
	var u := r.cross(best_f).normalized()
	best_p.y += road_thickness * 0.5 + 0.3
	return Transform3D(Basis(r, u, -best_f), best_p)

func road_progress_near(pos: Vector3) -> float:
	var centre := nearest_index(pos)
	if centre < 0:
		return 0.0
	var best_d := INF
	var best_progress := float(centre)
	for i in range(centre - 1, centre + 2):
		if not _segments.has(i):
			continue
		var seg: Array = _segments[i]
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.0001:
			continue
		var t := clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
		var p := a.lerp(b, t)
		var d := p.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_progress = float(i) + t
	return best_progress * chunk_length

## Signed lateral distance from the road centre line at the nearest chunk.
func road_lateral_near(pos: Vector3) -> float:
	var tf := road_transform_near(pos)
	return (pos - tf.origin).dot(tf.basis.x)

## Road tangent direction at the nearest point.
func road_forward_near(pos: Vector3) -> Vector3:
	return -road_transform_near(pos).basis.z


func fall_plane() -> float:
	return _lowest - fall_depth


func road_half_width() -> float:
	return road_width * 0.5


# ------------------------------------------------------------------ building

func _add_chunk(i: int) -> void:
	var chunk_start := _next_pos
	var yaw := _next_yaw
	var s0 := float(i) * chunk_length
	var s1 := float(i + 1) * chunk_length
	var end := chunk_start + Vector3(-sin(yaw), 0.0, -cos(yaw)) * chunk_length
	end.y = _height_at(s1)
	_next_pos = end
	_next_yaw = wrapf(yaw + _curve_step(i), -PI, PI)
	var seg: Vector3 = end - chunk_start
	var length: float = seg.length()
	if length < 0.01:
		return
	var f: Vector3 = seg / length
	var r: Vector3 = f.cross(Vector3.UP)
	if r.length_squared() < 0.0001:
		r = Vector3.RIGHT
	r = r.normalized()
	var u: Vector3 = r.cross(f).normalized()
	var body := StaticBody3D.new()
	body.name = "Chunk%d" % i
	add_child(body)
	body.transform = Transform3D(Basis(r, u, -f), (chunk_start + end) * 0.5)

	var terrain_event: int = _terrain_event_for_chunk(i)
	if terrain_event == TERRAIN_CLIFF:
		# The road itself disappears for this entire chunk. The next chunk starts
		# 18 m lower, creating the visible fall and the lower continuation.
		_build_cliff_chunk(body, chunk_start, end, length)
	else:
		_add_box(body, "Road", Vector3(road_width, road_thickness, length), Vector3(0.0, -road_thickness * 0.5, 0.0), _mat_road)
		_add_shape(body, Vector3(road_width, road_thickness, length), Vector3(0.0, -road_thickness * 0.5, 0.0))
		var side := shoulder_width * 0.5
		for side_sign in [-1.0, 1.0]:
			var pos := Vector3(side_sign * (road_width * 0.5 + side), -shoulder_thickness * 0.5, 0.0)
			var sand := _add_box(body, "Shoulder", Vector3(shoulder_width, shoulder_thickness, length), pos, _mat_shoulder)
			_add_shape(body, Vector3(shoulder_width, shoulder_thickness, length), sand.position)
			var stripe := _add_box(body, "EdgeStripe", Vector3(0.4, 0.06, length), Vector3(side_sign * (road_width * 0.5 - 0.35), 0.01, 0.0), _mat_edge)
			stripe.material_override = _mat_edge
		var dash_count := int(maxf(1.0, floor(length / 12.0)))
		var dash: float = length / float(dash_count)
		for d in dash_count:
			var dz: float = -length * 0.5 + dash * (float(d) + 0.5)
			_add_box(body, "CenterDash", Vector3(0.35, 0.06, dash * 0.5), Vector3(0.0, 0.01, dz), _mat_line)

	if terrain_event == TERRAIN_HILL:
		# Visual side markers make the exceptional elevation obvious without
		# adding expensive terrain meshes.
		_add_hill_markers(body, length)

	_chunks[i] = body
	_segments[i] = [chunk_start, end]
	_lowest = minf(_lowest, minf(chunk_start.y, end.y) - shoulder_thickness)
	if _spawner:
		_spawner.populate(body, i, length)


func _build_cliff_chunk(body: StaticBody3D, chunk_start: Vector3, end: Vector3, length: float) -> void:
	# The road disappears here, but the cliff is NOT bottomless: a wide sand
	# floor sits at the elevation of the lower continuation, so the car can fall
	# onto the lower desert instead of falling into the world void.
	var lower_ground := StaticBody3D.new()
	lower_ground.name = "CliffLowerGround"
	lower_ground.top_level = true
	body.add_child(lower_ground)
	var flat_forward := (end - chunk_start)
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.001:
		flat_forward = Vector3(0.0, 0.0, -1.0)
	flat_forward = flat_forward.normalized()
	var flat_right := flat_forward.cross(Vector3.UP).normalized()
	var lower_center := (end + chunk_start) * 0.5
	lower_center.y = end.y - 1.0
	lower_ground.global_transform = Transform3D(
		Basis(flat_right, Vector3.UP, -flat_forward),
		lower_center
	)
	var ground_mesh := MeshInstance3D.new()
	var ground_box := BoxMesh.new()
	ground_box.size = Vector3(road_width + shoulder_width * 2.0 + 24.0, 2.0, length + 8.0)
	ground_mesh.mesh = ground_box
	ground_mesh.material_override = _mat_shoulder
	lower_ground.add_child(ground_mesh)
	var ground_shape := CollisionShape3D.new()
	var ground_box_shape := BoxShape3D.new()
	ground_box_shape.size = ground_box.size
	ground_shape.shape = ground_box_shape
	lower_ground.add_child(ground_shape)

	# Rock faces at the entrance make the missing road read as a genuine cliff.
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.28, 0.20, 0.15)
	rock_mat.roughness = 1.0
	for side_sign in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.8, 12.0, 3.5)
		wall.mesh = box
		wall.material_override = rock_mat
		wall.position = Vector3(side_sign * (road_width * 0.5 + 1.5), -6.0, -length * 0.47)
		body.add_child(wall)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.8, 12.0, 3.5)
		shape.shape = bs
		shape.position = wall.position
		body.add_child(shape)


func _add_hill_markers(body: StaticBody3D, length: float) -> void:
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.66, 0.50, 0.30)
	marker_mat.roughness = 1.0
	for side_sign in [-1.0, 1.0]:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 0.35, length * 0.72)
		marker.mesh = box
		marker.material_override = marker_mat
		marker.position = Vector3(side_sign * (road_width * 0.5 + shoulder_width * 0.82), 0.0, 0.0)
		body.add_child(marker)


func _add_box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_shape(parent: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)


func _build_materials() -> void:
	_mat_road = StandardMaterial3D.new()
	_mat_road.albedo_color = Color(0.22, 0.22, 0.24)
	_mat_road.roughness = 0.95
	_mat_shoulder = StandardMaterial3D.new()
	_mat_shoulder.albedo_color = Color(0.78, 0.62, 0.37)
	_mat_shoulder.roughness = 1.0
	_mat_line = StandardMaterial3D.new()
	_mat_line.albedo_color = Color(0.92, 0.9, 0.82)
	_mat_line.roughness = 0.8
	_mat_edge = StandardMaterial3D.new()
	_mat_edge.albedo_color = Color(0.85, 0.83, 0.76)
	_mat_edge.roughness = 0.8


# ------------------------------------------------------------ path functions

func _height_at(s: float) -> float:
	var a := sin(s / hill_wavelength * TAU + _phase_h) * hill_height
	var b := sin(s / (hill_wavelength * 0.45) * TAU + _phase_h * 1.7) * hill_height * 0.5
	var c := sin(s / (hill_wavelength * 0.15) * TAU + _phase_c) * hill_height * 0.12
	var extra := _terrain_height_offset(s)
	return a + b + c + extra


func terrain_event_for_chunk(i: int) -> int:
	return _terrain_event_for_chunk(i)


func _terrain_event_for_chunk(i: int) -> int:
	if i < TERRAIN_FIRST_EVENT_CHUNK:
		return TERRAIN_NONE
	_ensure_terrain_events(i)
	return int(_terrain_events.get(i, TERRAIN_NONE))


func _ensure_terrain_events(until_chunk: int) -> void:
	if until_chunk < 0:
		return
	for i in range(0, until_chunk + 1):
		if _terrain_events.has(i):
			continue
		var event := TERRAIN_NONE
		if i >= TERRAIN_FIRST_EVENT_CHUNK and i - _terrain_last_special >= TERRAIN_MIN_EVENT_GAP:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector2i(world_seed + 918273, i * 104729 + 37))
			var roll: float = rng.randf()
			if roll < CLIFF_CHANCE:
				event = TERRAIN_CLIFF
				_terrain_last_special = i
			elif roll < CLIFF_CHANCE + HILL_CHANCE:
				event = TERRAIN_HILL
				_terrain_last_special = i
		_terrain_events[i] = event


func _terrain_height_offset(s: float) -> float:
	var chunk := int(floor(maxf(s, 0.0) / chunk_length))
	_ensure_terrain_events(chunk + 1)
	var result := 0.0

	# Every cliff drops the continuation permanently. This means the road seen
	# after the fall is genuinely lower instead of merely hiding the same road.
	for i in range(TERRAIN_FIRST_EVENT_CHUNK, chunk + 1):
		if int(_terrain_events.get(i, TERRAIN_NONE)) == TERRAIN_CLIFF and i < chunk:
			result -= CLIFF_DROP

	# A mega-hill is a smooth three-chunk bump. Events are spaced far enough apart
	# that two major terrain events do not overlap.
	var check_from := maxi(TERRAIN_FIRST_EVENT_CHUNK, chunk - 3)
	var check_to := chunk
	for i in range(check_from, check_to + 1):
		if int(_terrain_events.get(i, TERRAIN_NONE)) != TERRAIN_HILL:
			continue
		var start_s := float(i) * chunk_length
		var t := clampf((s - start_s) / (chunk_length * HILL_LENGTH_CHUNKS), 0.0, 1.0)
		if t > 0.0 and t < 1.0:
			result += sin(t * PI) * HILL_EXTRA_HEIGHT
	return result


func _curve_step(i: int) -> float:
	var fi := float(i)
	var a := sin(fi * 0.63 + _phase_c) * 0.65
	var b := sin(fi * 0.21 + _phase_c * 1.7) * 0.35
	return curve_amount * (a + b)
