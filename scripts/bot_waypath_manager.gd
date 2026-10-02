class_name BotWaypathManager
extends Node
## Deterministic race-line planner for VS BOTS.
## Each bot owns a path. Paths are generated with awareness of the other bots'
## paths so two cars do not deliberately reserve the same piece of road.

const LANES: Array[float] = [-4.25, 0.0, 4.25]
const WAYPOINT_SPACING := 18.0
const WAYPOINT_COUNT := 32
const REPLAN_INTERVAL := 4.0
const SAFE_LATERAL_GAP := 3.55

var world: DesertWorld
var difficulty := 0
var bots: Array[Yaris] = []
var paths: Dictionary = {}
var rngs: Dictionary = {}
var _replan_t := 0.0
var _path_version := 0

func setup(p_world: DesertWorld, p_difficulty: int) -> void:
	world = p_world
	difficulty = clampi(p_difficulty, 0, 4)
	bots.clear()
	paths.clear()
	rngs.clear()
	_replan_t = 0.0
	_path_version = 0

func register_bot(bot: Yaris, index: int) -> void:
	if bot == null:
		return
	bots.append(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(world.world_seed + 1703, index * 7919 + difficulty * 313))
	rngs[bot.get_instance_id()] = rng
	paths[bot.get_instance_id()] = []

func _process(delta: float) -> void:
	if world == null or bots.is_empty():
		return
	_replan_t -= delta
	if _replan_t <= 0.0:
		_replan_t = REPLAN_INTERVAL
		_rebuild_all()

func _rebuild_all() -> void:
	# Generate in a stable order. Every rebuild gets a new version so followers
	# can adopt the new road-safe reservation set without copying player motion.
	_path_version += 1
	# Generate in a stable order. Earlier paths become reservations for later bots.
	paths.clear()
	for i in bots.size():
		var bot := bots[i]
		if is_instance_valid(bot):
			paths[bot.get_instance_id()] = {"version": _path_version, "points": _build_path(bot, i)}

func _build_path(bot: Yaris, index: int) -> Array:
	var rng: RandomNumberGenerator = rngs.get(bot.get_instance_id())
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(world.world_seed + 1703, index * 7919 + difficulty * 313))
		rngs[bot.get_instance_id()] = rng

	var start_progress := world.road_progress_near(bot.global_position) + 55.0
	var current_lane := index % LANES.size()
	var result: Array = []
	var previous_lane := current_lane

	for k in WAYPOINT_COUNT:
		var progress := start_progress + float(k) * WAYPOINT_SPACING
		var candidates := [0, 1, 2]
		var best_lane := previous_lane
		var best_score := -INF

		var previous_score := _lane_score(index, progress, previous_lane, previous_lane)
		for lane_index in candidates:
			var score := _lane_score(index, progress, lane_index, previous_lane)
			# Staying in the same lane is strongly preferred. A lane change is
			# only accepted when it is meaningfully safer than the current lane.
			if lane_index != previous_lane:
				score -= 0.85
			if lane_index == (index % LANES.size()):
				score += 0.15
			if difficulty >= 3 and rng.randf() < 0.08:
				score += rng.randf_range(0.0, 0.20)
			if score > best_score:
				best_score = score
				best_lane = lane_index
		if best_lane != previous_lane and best_score < previous_score + 1.0:
			best_lane = previous_lane

		previous_lane = best_lane
		var tf := world.road_transform_at(progress / maxf(world.chunk_length, 0.01), LANES[best_lane])
		# Waypoint commands are deliberately cheap: live hazards are detected by
		# each bot while travelling, so path generation does not raycast dozens of
		# times for every bot on every rebuild. Keep only rare MASTER stunt jumps.
		var jump := false
		if difficulty == 4 and k > 2 and rng.randf() < 0.025:
			jump = true

		# A waypoint has exactly one gameplay instruction: jump or do nothing.
		# Lane/progress are geometry used to place the point on the road, not
		# additional commands for the bot.
		result.append({
			"progress": progress,
			"position": tf.origin + Vector3.UP * 0.25,
			"lane": best_lane,
			"lateral": LANES[best_lane],
			"jump": jump,
		})
	return result

func _lane_score(bot_index: int, progress: float, lane: int, previous_lane: int) -> float:
	var score := 2.0 - absf(float(lane - previous_lane)) * 0.65
	for other in bots:
		if not is_instance_valid(other):
			continue
		if other.get_instance_id() == _bot_id_from_index(bot_index):
			continue
		var other_entry: Variant = paths.get(other.get_instance_id(), [])
		var other_path: Array = other_entry.get("points", []) if other_entry is Dictionary else other_entry
		for wp in other_path:
			var dp: float = absf(float(wp.get("progress", 0.0)) - progress)
			if dp > 13.0:
				continue
			var dl: float = absf(float(wp.get("lateral", 0.0)) - LANES[lane])
			if dl < SAFE_LATERAL_GAP:
				score -= (SAFE_LATERAL_GAP - dl) * (1.0 - minf(dp / 13.0, 1.0)) * 2.4
	return score

func _bot_id_from_index(index: int) -> int:
	if index >= 0 and index < bots.size() and is_instance_valid(bots[index]):
		return bots[index].get_instance_id()
	return -1

func _should_jump(position: Vector3, progress: float, k: int, rng: RandomNumberGenerator) -> bool:
	if difficulty < 2:
		return false
	# First ask the world for an actual obstacle in front of this waypoint.
	var from := position + Vector3.UP * 0.8
	var forward := world.road_forward_near(position).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 7.0)
	query.collision_mask = 1
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider is RoadObstacle or collider is TrafficCar:
			return difficulty >= 2
	# MASTER occasionally reserves a stunt jump even on a clear stretch.
	return difficulty == 4 and k > 2 and rng.randf() < 0.035

func get_bot_path(bot: Yaris) -> Array:
	if bot == null:
		return []
	var entry: Variant = paths.get(bot.get_instance_id(), {})
	if entry is Dictionary:
		return entry.get("points", [])
	return entry if entry is Array else []

func get_path_version(bot: Yaris) -> int:
	if bot == null:
		return -1
	var entry: Variant = paths.get(bot.get_instance_id(), {})
	return int(entry.get("version", -1)) if entry is Dictionary else 0
