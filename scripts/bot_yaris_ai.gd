class_name BotYarisAI
extends RefCounted
## VS BOTS path follower.
## The bot does not react to player input or copy player movement. It follows a
## precomputed road waypoints. Each waypoint contains only one command: jump or nothing.

const DIFFICULTY_NAMES: Array[String] = ["DÉBUTANT", "NOVICE", "PILOTE", "EXPERT", "MASTER"]
const WAYPOINT_REACH_DISTANCE := 7.0 # Larger capture radius: missed points are easier to absorb without U-turns.
const RECENTER_RADIUS := 0.55
const STEER_DEBOUNCE := 0.16
const THINK_INTERVAL := 0.05
const HAZARD_SCAN_INTERVAL := 0.10
const AHEAD_SCAN_DISTANCE := 12.0
const POLE_SCAN_DISTANCE := 7.0
const POLE_SIDE_OFFSET := 3.0
# Ramp decisions are made well before the ramp so the bot can leave the road
# smoothly instead of making a last-second zig-zag.
const RAMP_SCAN_INTERVAL := 0.45
const RAMP_MIN_AHEAD := 180.0
const RAMP_MAX_AHEAD := 360.0
const RAMP_COMMIT_AHEAD := 125.0
const RAMP_REJOIN_AFTER := 38.0
const RAMP_MAX_LATERAL := 38.0
const RAMP_STEER_LIMIT := 0.62

var _avoid_side := 0.0
var _avoid_t := 0.0
var _avoid_center_lateral := 0.0

var car: Yaris
var world: DesertWorld
var planner: BotWaypathManager
var level := 0
var bot_index := 0
var path: Array = []
var waypoint_index := 0
var _steer_command := 0.0
var _jump_lock := 0.0
var _path_version := -1
var _last_steer_sign := 0
var _steer_debounce := 0.0
var _think_t := 0.0
var _hazard_scan_t := 0.0
var _cached_hazard: Dictionary = {"jump": false, "pole": false}
var _ramp_scan_t := 0.0
var _ramp_target: Node3D = null
var _ramp_target_progress := 0.0
var _ramp_target_lateral := 0.0
var _ramp_committed := false
var _ramp_roll_cooldown := 0.0
var _ramp_considered_id := 0

func setup(p_car: Yaris, p_world: DesertWorld, p_level: int, p_index: int, p_planner: BotWaypathManager) -> void:
	car = p_car
	world = p_world
	level = clampi(p_level, 0, 4)
	bot_index = p_index
	planner = p_planner
	_ramp_scan_t = 0.0
	_ramp_target = null
	_ramp_target_progress = 0.0
	_ramp_target_lateral = 0.0
	_ramp_committed = false
	_ramp_roll_cooldown = 0.0
	_ramp_considered_id = 0
	_refresh_path()

func tick(delta: float) -> void:
	if car == null or world == null or not is_instance_valid(car):
		return
	_jump_lock = maxf(_jump_lock - delta, 0.0)
	_steer_debounce = maxf(_steer_debounce - delta, 0.0)
	_avoid_t = maxf(_avoid_t - delta, 0.0)
	_think_t -= delta
	_hazard_scan_t -= delta
	_ramp_scan_t -= delta
	_ramp_roll_cooldown = maxf(_ramp_roll_cooldown - delta, 0.0)
	_refresh_path_if_needed()
	_update_ramp_target()
	if _hazard_scan_t <= 0.0:
		_hazard_scan_t = HAZARD_SCAN_INTERVAL
		_cached_hazard = _scan_ahead()
	if _think_t > 0.0:
		return
	_think_t = THINK_INTERVAL
	_follow_path(delta)

func _refresh_path() -> void:
	if planner == null:
		path = []
		return
	path = planner.get_bot_path(car)
	_path_version = planner.get_path_version(car)
	if waypoint_index >= path.size():
		waypoint_index = max(0, path.size() - 1)

func _refresh_path_if_needed() -> void:
	if planner == null:
		return
	var latest_version := planner.get_path_version(car)
	if latest_version != _path_version:
		var latest: Array = planner.get_bot_path(car)
		if not latest.is_empty():
			var old_progress := _current_progress()
			path = latest
			_path_version = latest_version
			waypoint_index = _nearest_waypoint_index(old_progress)

func _follow_path(delta: float) -> void:
	if path.is_empty():
		car.set_ai_input(0.0, false, 1.0)
		return

	# A waypoint is considered valid when the car reaches its larger capture
	# radius. More importantly, a waypoint that is already behind the car is
	# simply skipped. The bot must NEVER turn around just to touch a missed point.
	# This is especially important after a jump, ramp launch, collision or a
	# temporary avoidance manoeuvre.
	var car_progress: float = world.road_progress_near(car.global_position)
	while waypoint_index < path.size() - 1:
		var wp: Dictionary = path[waypoint_index]
		var wp_progress: float = float(wp.get("progress", car_progress))
		var pos: Vector3 = wp.get("position", car.global_position)
		var passed: bool = car_progress >= wp_progress + 2.5
		var touched: bool = car.global_position.distance_to(pos) <= WAYPOINT_REACH_DISTANCE
		if touched or passed:
			waypoint_index += 1
		else:
			break

	var current: Dictionary = path[waypoint_index]
	var target: Vector3 = current.get("position", car.global_position)
	var target_flat := target
	target_flat.y = car.global_position.y
	var to_target := target_flat - car.global_position
	var distance_to_target := to_target.length()

	var heading_error := 0.0
	if distance_to_target > 0.05:
		heading_error = _signed_angle(car._flat_forward(), to_target.normalized())

	# Pure waypoint steering: the point itself is the target. A small dead zone
	# around the centre prevents left/right chatter when the car is aligned.
	var steer := clampf(-heading_error * 2.15, -1.0, 1.0)
	if absf(heading_error) < 0.035 and distance_to_target < 1.35:
		steer = 0.0

	# Debounce rapid sign changes. If the bot starts alternating sides of the
	# waypoint, briefly keep the previous direction, then recentre to zero.
	var steer_sign := signi(steer)
	if steer_sign != 0 and _last_steer_sign != 0 and steer_sign != _last_steer_sign and _steer_debounce <= 0.0:
		_steer_debounce = STEER_DEBOUNCE
		steer *= 0.35
	if _steer_debounce > 0.0:
		steer *= 0.35
	if distance_to_target < RECENTER_RADIUS and absf(heading_error) < 0.12:
		steer = 0.0
	if absf(steer) > 0.05:
		_last_steer_sign = signi(steer)
	else:
		_last_steer_sign = 0

	if level == 0:
		steer = clampf(steer, -0.42, 0.42)
	elif level == 1:
		steer = clampf(steer, -0.62, 0.62)

	var steer_rate := lerpf(4.5, 9.0, float(level) / 4.0)
	_steer_command = move_toward(_steer_command, steer, steer_rate * delta)

	# Waypoints remain authoritative, but hazards are scanned live between them.
	var live_hazard: Dictionary = _cached_hazard
	var live_jump := bool(live_hazard.get("jump", false))
	var pole := bool(live_hazard.get("pole", false))

	# A waypoint has only JUMP or NOTHING. A live obstacle/slow Yaris may also
	# request a jump; Beginner remains the no-jump difficulty.
	var jump := bool(current.get("jump", false)) or live_jump
	if level == 0:
		jump = false
	if jump and car.is_on_floor() and _jump_lock <= 0.0:
		_jump_lock = 0.8
		car.try_jump()

	# Poles/cacti are treated differently: very short detection and a small
	# controlled S-shaped dodge, followed by a return to the waypoint line.
	if pole and _avoid_t <= 0.0:
		var pole_tf := world.road_transform_near(car.global_position)
		_avoid_side = -1.0 if ((bot_index + waypoint_index) % 2 == 0) else 1.0
		_avoid_center_lateral = (car.global_position - pole_tf.origin).dot(pole_tf.basis.x)
		_avoid_t = 0.95

	if _avoid_t > 0.0:
		var avoid_tf := world.road_transform_near(car.global_position)
		var road_right := avoid_tf.basis.x.normalized()
		var target_lateral := _avoid_center_lateral
		if _avoid_t > 0.62:
			target_lateral += _avoid_side * POLE_SIDE_OFFSET
		elif _avoid_t > 0.43:
			target_lateral += _avoid_side * POLE_SIDE_OFFSET * 0.35
		var lateral_target := avoid_tf.origin + road_right * target_lateral
		lateral_target.y = car.global_position.y
		var avoid_dir := lateral_target - car.global_position
		if avoid_dir.length_squared() > 0.01:
			var avoid_angle := _signed_angle(car._flat_forward(), avoid_dir.normalized())
			steer = clampf(-avoid_angle * 2.2, -0.72, 0.72)

	# A committed ramp target temporarily becomes the steering target. The
	# decision is made 125–235 m ahead, so the lateral move is gradual and does
	# not fight the road waypoints at the last second. Once the ramp is passed,
	# normal waypath following automatically takes over again.
	if _ramp_target != null and is_instance_valid(_ramp_target):
		var ramp_progress := world.road_progress_near(_ramp_target.global_position)
		var progress_delta := ramp_progress - world.road_progress_near(car.global_position)
		if progress_delta < -12.0 or progress_delta > RAMP_MAX_AHEAD + 70.0:
			_ramp_target = null
			_ramp_committed = false
		else:
			var ramp_target_pos := _ramp_target.global_position
			var ramp_tf := world.road_transform_near(ramp_target_pos)
			# Aim at a point slightly before the ramp when still far away. This
			# gives the bot time to drift outward without snapping toward it.
			var lead := clampf(progress_delta * 0.22, 0.0, 28.0)
			var lead_pos := ramp_target_pos - (-ramp_tf.basis.z).normalized() * lead
			lead_pos.y = car.global_position.y
			var ramp_dir := lead_pos - car.global_position
			if ramp_dir.length_squared() > 0.01:
				var ramp_angle := _signed_angle(car._flat_forward(), ramp_dir.normalized())
				var ramp_steer := clampf(-ramp_angle * 1.65, -RAMP_STEER_LIMIT, RAMP_STEER_LIMIT)
				# While committed, ramp steering wins over tiny waypoint corrections.
				_steer_command = move_toward(_steer_command, ramp_steer, 5.0 * delta)

	# No waypoint-specific drift/speed commands.
	car.set_ai_input(_steer_command, false, 1.0)

func _update_ramp_target() -> void:
	if level <= 0 or car == null or world == null:
		_ramp_target = null
		_ramp_committed = false
		return

	var current_progress: float = world.road_progress_near(car.global_position)
	if _ramp_target != null and is_instance_valid(_ramp_target):
		var existing_progress: float = world.road_progress_near(_ramp_target.global_position)
		var existing_delta: float = existing_progress - current_progress
		if existing_delta > 0.0:
			_ramp_target_progress = existing_progress
			_ramp_target_lateral = world.road_lateral_near(_ramp_target.global_position)
			_ramp_committed = existing_delta <= RAMP_COMMIT_AHEAD
			return
		# Once the ramp is behind us, abandon the detour and immediately resume
		# the normal generated waypath.
		_ramp_target = null
		_ramp_committed = false

	if _ramp_scan_t > 0.0 or _ramp_roll_cooldown > 0.0:
		return
	_ramp_scan_t = RAMP_SCAN_INTERVAL

	var best: Node3D = null
	var best_score: float = INF
	var best_progress: float = 0.0
	var best_lateral: float = 0.0
	var ramps: Array[Node] = world.get_tree().get_nodes_in_group("desert_ramps")
	for node in ramps:
		var ramp := node as Node3D
		if ramp == null or not is_instance_valid(ramp):
			continue
		var progress: float = world.road_progress_near(ramp.global_position)
		var ahead: float = progress - current_progress
		if ahead < RAMP_MIN_AHEAD or ahead > RAMP_MAX_AHEAD:
			continue
		var lateral: float = absf(world.road_lateral_near(ramp.global_position))
		if lateral > RAMP_MAX_LATERAL:
			continue
		# Prefer a ramp around 185 m ahead: this gives the bot a long, smooth
		# approach instead of a sudden sideways correction.
		var score: float = absf(ahead - 270.0) + lateral * 0.35
		if score < best_score:
			best_score = score
			best = ramp
			best_progress = progress
			best_lateral = lateral

	if best == null:
		return

	var best_id: int = best.get_instance_id()
	if best_id == _ramp_considered_id:
		return
	_ramp_considered_id = best_id

	# The decision is made once per individual ramp, not once every scan. This
	# prevents a 50% MASTER chance from becoming effectively 100% after several
	# scans of the same ramp.
	var take_chance: float = [0.0, 0.08, 0.18, 0.32, 0.50][level]
	if randf() > take_chance:
		_ramp_roll_cooldown = 2.0
		return

	_ramp_target = best
	_ramp_target_progress = best_progress
	_ramp_target_lateral = best_lateral
	_ramp_committed = false
	_ramp_roll_cooldown = 8.0

func _scan_ahead() -> Dictionary:
	var result: Dictionary = {"jump": false, "pole": false}
	if car == null or world == null:
		return result
	var space := car.get_world_3d().direct_space_state
	var forward := car._flat_forward().normalized()
	var from := car.global_position + Vector3.UP * 0.85 + forward * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * AHEAD_SCAN_DISTANCE)
	query.collision_mask = 1
	query.exclude = [car.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return result
	var collider: Object = hit.get("collider")
	if collider is TrafficCar:
		result["jump"] = true
	elif collider is Yaris:
		var other := collider as Yaris
		if other != null and other.speed + 5.0 < car.speed:
			result["jump"] = true
	elif collider is RoadObstacle:
		var obstacle := collider as RoadObstacle
		if obstacle != null and obstacle.kind == RoadObstacle.Kind.POLE:
			# Confirm with the deliberately short pole field.
			var pole_from := car.global_position + Vector3.UP * 0.8 + forward * 0.8
			var pole_query := PhysicsRayQueryParameters3D.create(pole_from, pole_from + forward * POLE_SCAN_DISTANCE)
			pole_query.collision_mask = 1
			pole_query.exclude = [car.get_rid()]
			var pole_hit := space.intersect_ray(pole_query)
			if not pole_hit.is_empty() and pole_hit.get("collider") == obstacle:
				result["pole"] = true
		else:
			result["jump"] = true
	return result

func _current_progress() -> float:
	if world == null or car == null:
		return 0.0
	return world.road_progress_near(car.global_position)

func _nearest_waypoint_index(progress: float) -> int:
	if path.is_empty():
		return 0
	# Never select a waypoint that is already meaningfully behind the car.
	# Replans can otherwise resurrect an old point and make the bot U-turn.
	var fallback := path.size() - 1
	for i in path.size():
		var wp: Dictionary = path[i]
		var wp_progress: float = float(wp.get("progress", 0.0))
		if wp_progress >= progress - 2.5:
			return i
	return fallback

func _signed_angle(a: Vector3, b: Vector3) -> float:
	a.y = 0.0
	b.y = 0.0
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return 0.0
	a = a.normalized()
	b = b.normalized()
	return atan2(a.cross(b).y, a.dot(b))
