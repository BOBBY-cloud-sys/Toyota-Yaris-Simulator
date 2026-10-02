class_name ObstacleSpawner
extends RefCounted
## Fills each road chunk with hazards, deterministically from the world seed.
##
## Safety rules (so there is always a way through):
## - The first chunks are calm (no road hazards).
## - Each chunk keeps one FREE lane; it shifts by at most one lane per chunk.
## - At most one hazard per slot, and the first slot of a chunk never blocks
##   the previous chunk's free lane.
## - Puddles are never placed right before another hazard.
## - The sand shoulders stay drivable, so the road is never fully walled off.

const LANES: Array[float] = [-4.5, 0.0, 4.5]
const SLOTS: Array[float] = [20.0, 0.0, -20.0]  # chunk-local z, +z is the chunk start
const CONE_PATH := "res://assets/library/racing-arcade/race-track-assets-pack-conus-clear.glb"
const CALM_CHUNKS := 3

var world: DesertWorld
var _cone_scene: PackedScene
var _prev_free := 1
var _mats: Dictionary = {}
## Chunks below this index get no road hazards (fresh start or resume point).
var calm_until := CALM_CHUNKS


func _init(p_world: DesertWorld) -> void:
	world = p_world
	if ResourceLoader.exists(CONE_PATH):
		_cone_scene = load(CONE_PATH) as PackedScene


func reset() -> void:
	_prev_free = 1


func difficulty_at(i: int) -> float:
	return clampf(float(i - CALM_CHUNKS) / 100.0, 0.0, 1.0)


func populate(body: Node3D, i: int, length: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(world.world_seed, i))
	var d := difficulty_at(i)
	var half := world.road_half_width()
	_roadside(body, rng, half, length)
	# Terrain events reserve the road space. Mega-hills and cliff gaps never
	# receive an ordinary roadside ramp. A cliff has one rare exception: a
	# single ramp can appear in the middle of the gap, deliberately inviting
	# everyone to commit to the jump.
	var terrain_event: int = world.terrain_event_for_chunk(i)
	if i >= calm_until:
		if terrain_event == DesertWorld.TERRAIN_CLIFF:
			if rng.randf() < 0.22:
				_spawn_cliff_ramp(body, i, length, half)
		elif terrain_event == DesertWorld.TERRAIN_NONE and rng.randf() < 0.18:
			_spawn_ramp(body, i, length, half, rng)
	if i < calm_until:
		return
	# A cliff is intentionally empty: no traffic or road hazards in the
	# missing section. The only gameplay object it may contain is the rare
	# special ramp above.
	if terrain_event == DesertWorld.TERRAIN_CLIFF:
		return
	var free_lane := clampi(_prev_free + rng.randi_range(-1, 1), 0, 2)
	var used: Array[int] = [-1, -1, -1]  # lane index per slot, -1 = empty
	var count := 0
	if rng.randf() < 0.5 + d * 0.45:
		count = mini(1 + rng.randi_range(0, 1 + int(d * 2.0)), 3)
	var slot_order: Array[int] = [0, 1, 2]
	_shuffle(slot_order, rng)
	for k in count:
		var slot := slot_order[k]
		var lanes: Array[int] = []
		for lane in 3:
			if lane == free_lane:
				continue
			if slot == 0 and lane == _prev_free:
				continue
			lanes.append(lane)
		if lanes.is_empty():
			continue
		var lane_i := lanes[rng.randi() % lanes.size()]
		used[slot] = lane_i
		var pos := Vector3(LANES[lane_i], 0.0, SLOTS[slot])
		_spawn_hazard(body, pos, rng, d)
	# Puddle: only where the next slot is empty.
	if rng.randf() < 0.18 + d * 0.3:
		for slot in 3:
			if used[slot] != -1:
				continue
			if slot < 2 and used[slot + 1] != -1:
				continue
			var lane_p := free_lane if slot == 2 else rng.randi_range(0, 2)
			_puddle(body, Vector3(LANES[lane_p], 0.0, SLOTS[slot]), rng)
			break
	_prev_free = free_lane
	# Traffic
	if i >= 6 and rng.randf() < 0.22 + d * 0.32:
		var oncoming := rng.randf() < 0.3 + d * 0.3
		var lane_x := -3.5 if oncoming else 3.5
		var spd := -rng.randf_range(10.0, 17.0) if oncoming else rng.randf_range(12.0, 20.0)
		var car := TrafficCar.new()
		car.setup(world, float(i) + 0.5, lane_x, spd, rng)
		world.add_child(car)
		car.global_transform = world.road_transform_at(float(i) + 0.5, lane_x)


func _spawn_ramp(body: Node3D, i: int, length: float, half: float, rng: RandomNumberGenerator) -> void:
	var ramp := DesertRamp.new()
	ramp.name = "WoodenRamp_%d" % i
	ramp.setup(world)
	body.add_child(ramp)

	# Keep the whole ramp far outside the asphalt. It is a roadside stunt
	# object, aligned with the circuit rather than pointing back at the road.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var lateral := side * (half + rng.randf_range(15.0, 25.0))
	var z := rng.randf_range(-length * 0.34, length * 0.34)
	ramp.position = Vector3(lateral, 0.0, z)

	# Local -Z is the ramp's launch direction. Keep it aligned with the
	# circuit's forward direction so the ramp never points sideways toward
	# the road. The ramp stays well away from the asphalt.
	ramp.rotation.y = 0.0


func _spawn_cliff_ramp(body: Node3D, i: int, length: float, half: float) -> void:
	var ramp := DesertRamp.new()
	ramp.name = "CliffJumpRamp_%d" % i
	ramp.setup(world)
	body.add_child(ramp)
	# Put the special ramp at the START of the cliff, not at its lower end.
	# Local +Z is the entrance side because local -Z is the circuit direction.
	# The jump therefore happens immediately when the road disappears.
	ramp.position = Vector3(0.0, 0.0, length * 0.43)
	ramp.rotation.y = 0.0


func _spawn_hazard(body: Node3D, pos: Vector3, rng: RandomNumberGenerator, d: float) -> void:
	var roll := rng.randf()
	if roll < 0.3:
		_rock(body, pos, rng)
	elif roll < 0.55 + d * 0.1:
		_pole(body, pos, 5.0, 0.22, false)
	elif roll < 0.8:
		_debris(body, pos, rng)
	else:
		_cones(body, pos, rng)


# ------------------------------------------------------------------ builders

func _roadside(body: Node3D, rng: RandomNumberGenerator, half: float, length: float) -> void:
	# The desert outside the asphalt should feel considerably more cluttered
	# than the drivable road: rocks, debris, poles and cacti live on the sand.
	for sgn in [-1.0, 1.0]:
		if rng.randf() < 0.8:
			var z := rng.randf_range(-length * 0.48, length * 0.48)
			_pole(body, Vector3(sgn * (half + rng.randf_range(2.5, 4.0)), 0.0, z), 7.0, 0.2, true)
		if rng.randf() < 0.65:
			var cz := rng.randf_range(-length * 0.48, length * 0.48)
			_cactus(body, Vector3(sgn * rng.randf_range(half + 8.0, half + 40.0), 0.0, cz), rng)

		# 2–4 extra sand hazards per side. This deliberately puts more scenery
		# outside the road than the 0–3 gameplay hazards on the asphalt.
		var extra := rng.randi_range(2, 4)
		for k in extra:
			var side_x: float = float(sgn) * rng.randf_range(half + 5.0, half + 42.0)
			var side_z := rng.randf_range(-length * 0.48, length * 0.48)
			var roll := rng.randf()
			if roll < 0.55:
				_rock(body, Vector3(side_x, 0.0, side_z), rng)
			elif roll < 0.78:
				_debris(body, Vector3(side_x, 0.0, side_z), rng)
			else:
				_cactus(body, Vector3(side_x, 0.0, side_z), rng)


func _pole(parent: Node3D, pos: Vector3, h: float, r: float, roadside: bool) -> void:
	var o := RoadObstacle.new()
	o.kind = RoadObstacle.Kind.POLE
	o.mass = 60.0
	parent.add_child(o)
	o.position = pos
	var mat := _mat("wood", Color(0.42, 0.28, 0.16)) if roadside else _mat("warn", Color(0.85, 0.12, 0.1))
	_cyl(o, r, h, Vector3(0.0, h * 0.5, 0.0), mat)
	if roadside:
		_box(o, Vector3(1.8, 0.14, 0.14), Vector3(0.0, h - 0.6, 0.0), mat)
	else:
		for b in 3:
			_cyl(o, r + 0.01, 0.35, Vector3(0.0, 1.0 + b * 1.3, 0.0), _mat("white", Color(0.95, 0.95, 0.9)))
	_cyl_shape(o, r + 0.08, h, Vector3(0.0, h * 0.5, 0.0))


func _cactus(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var o := RoadObstacle.new()
	o.kind = RoadObstacle.Kind.POLE
	o.lethal_impact = 999.0
	o.mass = 120.0
	parent.add_child(o)
	o.position = pos
	var h := rng.randf_range(3.0, 5.5)
	var green := _mat("cactus", Color(0.25, 0.5, 0.22))
	_cyl(o, 0.4, h, Vector3(0.0, h * 0.5, 0.0), green)
	_cyl(o, 0.25, 1.4, Vector3(0.75, h * 0.6, 0.0), green)
	_cyl(o, 0.25, 1.2, Vector3(-0.75, h * 0.45, 0.0), green)
	_box(o, Vector3(1.5, 0.35, 0.35), Vector3(0.0, h * 0.45, 0.0), green)
	_cyl_shape(o, 0.5, h, Vector3(0.0, h * 0.5, 0.0))


func _rock(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var o := RoadObstacle.new()
	o.kind = RoadObstacle.Kind.ROCK
	o.mass = 3000.0
	parent.add_child(o)
	o.position = pos
	var sc := Vector3(rng.randf_range(1.1, 1.6), rng.randf_range(0.7, 1.1), rng.randf_range(1.0, 1.5))
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 7
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _mat("rock", Color(0.6, 0.38, 0.24))
	mi.scale = sc
	mi.rotation.y = rng.randf() * TAU
	mi.position = Vector3(0.0, sc.y * 0.55, 0.0)
	o.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sc.x * 1.7, sc.y * 1.6, sc.z * 1.7)
	cs.shape = bs
	cs.position = Vector3(0.0, sc.y * 0.55, 0.0)
	o.add_child(cs)


func _debris(parent: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(3, 5)
	for k in n:
		var o := RoadObstacle.new()
		o.kind = RoadObstacle.Kind.DEBRIS
		o.mass = 15.0
		parent.add_child(o)
		o.position = center + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-2.5, 2.5))
		o.rotation.y = rng.randf() * TAU
		if rng.randf() < 0.5:
			_box(o, Vector3(0.9, 0.9, 0.9), Vector3(0.0, 0.45, 0.0), _mat("crate", Color(0.62, 0.45, 0.25)))
			_box_shape(o, Vector3(0.9, 0.9, 0.9), Vector3(0.0, 0.45, 0.0))
		else:
			_cyl(o, 0.35, 0.95, Vector3(0.0, 0.475, 0.0), _mat("barrel", Color(0.2, 0.35, 0.6)))
			_cyl_shape(o, 0.35, 0.95, Vector3(0.0, 0.475, 0.0))


func _cones(parent: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	var dir := -1.0 if rng.randf() < 0.5 else 1.0
	for k in 5:
		var o := RoadObstacle.new()
		o.kind = RoadObstacle.Kind.CONE
		o.mass = 3.0
		parent.add_child(o)
		o.position = center + Vector3(dir * (float(k) - 2.0) * 0.9, 0.0, (float(k) - 2.0) * 1.8)
		if _cone_scene:
			var vis := _cone_scene.instantiate() as Node3D
			vis.scale = Vector3.ONE * 1.5
			o.add_child(vis)
		else:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.33
			cm.height = 0.9
			cm.radial_segments = 8
			mi.mesh = cm
			mi.material_override = _mat("cone", Color(1.0, 0.45, 0.1))
			mi.position = Vector3(0.0, 0.45, 0.0)
			o.add_child(mi)
		_cyl_shape(o, 0.3, 0.9, Vector3(0.0, 0.45, 0.0))


func _puddle(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var p := Puddle.new()
	parent.add_child(p)
	p.position = pos
	var rx := rng.randf_range(2.2, 3.2)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.04
	cm.radial_segments = 12
	mi.mesh = cm
	var m := _mat("water", Color(0.3, 0.5, 0.75, 0.75))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.6
	m.roughness = 0.05
	mi.material_override = m
	mi.scale = Vector3(rx, 1.0, rx * rng.randf_range(1.2, 1.8))
	mi.position = Vector3(0.0, 0.03, 0.0)
	p.add_child(mi)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = rx
	cyl.height = 1.0
	cs.shape = cyl
	cs.position = Vector3(0.0, 0.5, 0.0)
	p.add_child(cs)


# ------------------------------------------------------------------ helpers

func _mat(key: String, color: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _cyl_shape(parent: Node3D, r: float, h: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)


func _box_shape(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)


func _shuffle(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for k in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp := arr[k]
		arr[k] = arr[j]
		arr[j] = tmp
