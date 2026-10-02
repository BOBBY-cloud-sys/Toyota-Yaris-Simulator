class_name TrafficCar
extends RigidBody3D
## Traffic vehicles use complete GLB models. No wheel.glb is required.
## All visual models are preloaded once; only the visual scene changes.

const MODEL_SCENES: Array[PackedScene] = [
	preload("res://assets/traffic/renault_clio_ii.glb"),
	preload("res://assets/traffic/peugeot_206.glb"),
	preload("res://assets/traffic/vw_golf_mk1.glb"),
	preload("res://assets/traffic/honda_s2000.glb"),
	preload("res://assets/traffic/tank.glb"),
]

# These source models are already longitudinal on local Z except the tank.
# Gameplay forward is -Z.
const MODEL_YAW := {
	"renault_clio_ii.glb": 0.0,
	"peugeot_206.glb": 0.0,
	"vw_golf_mk1.glb": 0.0,
	"honda_s2000.glb": 0.0,
	"tank.glb": PI * 0.5,
}

# Normalise the downloaded models to believable road-vehicle dimensions.
const MODEL_SCALE := {
	"renault_clio_ii.glb": 1.59,
	"peugeot_206.glb": 0.041,
	"vw_golf_mk1.glb": 3.05,
	"honda_s2000.glb": 0.82,
	"tank.glb": 0.0044,
}

const MODEL_Y_OFFSET := {
	"renault_clio_ii.glb": 0.02,
	"peugeot_206.glb": 0.89,
	"vw_golf_mk1.glb": 0.01,
	"honda_s2000.glb": 0.02,
	"tank.glb": 0.02,
}

const MODEL_COLLISION := {
	"renault_clio_ii.glb": Vector3(1.72, 1.55, 4.05),
	"peugeot_206.glb": Vector3(1.72, 1.55, 4.05),
	"vw_golf_mk1.glb": Vector3(1.72, 1.55, 4.05),
	"honda_s2000.glb": Vector3(1.82, 1.42, 4.35),
	"tank.glb": Vector3(3.05, 1.75, 5.25),
}

var world: DesertWorld
var s := 0.0
var lane := 3.5
var travel_speed := 16.0
var _hit := false
var _visual: Node3D

func setup(p_world: DesertWorld, p_s: float, p_lane: float, p_speed: float, rng: RandomNumberGenerator) -> void:
	world = p_world
	s = p_s
	lane = p_lane
	travel_speed = p_speed
	mass = 900.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_build(rng)

func _build(rng: RandomNumberGenerator) -> void:
	var scene: PackedScene = null
	if not MODEL_SCENES.is_empty():
		scene = MODEL_SCENES[rng.randi_range(0, MODEL_SCENES.size() - 1)]
	if scene == null:
		_build_fallback()
		return
	_visual = scene.instantiate() as Node3D
	if _visual == null:
		_build_fallback()
		return
	add_child(_visual)
	var model_name: String = scene.resource_path.get_file()
	_visual.rotation.y = float(MODEL_YAW.get(model_name, 0.0))
	_visual.scale = Vector3.ONE * float(MODEL_SCALE.get(model_name, 1.0))
	_visual.position = Vector3(0.0, float(MODEL_Y_OFFSET.get(model_name, 0.0)), 0.0)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var collision_size: Vector3 = MODEL_COLLISION.get(model_name, Vector3(1.8, 1.65, 4.4))
	shape.size = collision_size
	cs.shape = shape
	cs.position = Vector3(0.0, shape.size.y * 0.5, 0.0)
	add_child(cs)

func _build_fallback() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.75, 0.75, 0.72)
	paint.roughness = 0.5
	_box(Vector3(1.8, 1.4, 4.2), Vector3(0, 1.0, 0), paint)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.65, 4.4)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.82, 0.0)
	add_child(cs)

func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _physics_process(delta: float) -> void:
	if _hit or world == null:
		return
	s += travel_speed * delta / world.chunk_length
	if not world.has_road_at(s):
		queue_free()
		return
	var tf := world.road_transform_at(s, lane)
	if travel_speed < 0.0:
		tf.basis = tf.basis.rotated(tf.basis.y.normalized(), PI)
	global_transform = tf

func on_car_hit(car: Yaris, car_vel: Vector3, normal: Vector3, _impact: float) -> void:
	if _hit:
		return
	_hit = true
	var fwd := -global_transform.basis.z
	var own_vel := fwd * absf(travel_speed)
	add_collision_exception_with(car)
	car.add_collision_exception_with(self)
	freeze = false
	linear_velocity = own_vel
	var rel := car_vel - own_vel
	var power := rel.length()
	apply_central_impulse((rel * 1.2 + Vector3.UP * (10.0 + power * 0.45)) * mass)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	apply_torque_impulse(spin * mass * 9.0)
	var flat_n := Vector3(normal.x, 0.0, normal.z).normalized()
	var reason := "Collision frontale" if power > 62.0 else ""
	car.take_hit(power, flat_n * power * 0.22 + Vector3.UP * 4.0, 0.72, reason)
	get_tree().create_timer(8.0).timeout.connect(queue_free)
