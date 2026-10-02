class_name Yaris
extends CharacterBody3D
## Arcade Toyota Yaris (2000, first generation).
##
## The car drives itself: it always accelerates forward. The player steers,
## brakes, drifts and jumps. Authored forward axis is -Z (Godot convention);
## if an imported model faces another way, rotate the "Model" child only -
## never the physics body.

signal landed(impact: float)
signal jumped()
## Emitted by take_hit(). lethal_reason is empty unless the hit eliminates.
signal crashed(strength: float, lethal_reason: String)
signal splashed()

@export_group("Dance")
## The body squishes on every beat while music is playing.
@export var dance_enabled := true
@export var dance_squash := 0.17
@export var dance_tilt := 0.06
@export var dance_nod := 0.035

@export_group("Puddle")
@export var puddle_time := 1.4
@export var puddle_grip_mult := 0.15

@export_group("Drive")
@export var base_cruise_speed := 32.0
@export var max_speed := 64.0
@export var accel := 7.5
@export var brake_decel := 26.0
@export var coast_decel := 2.5
@export var pedal_bonus := 14.0
@export var difficulty_extra_speed := 14.0

@export_group("Steering")
@export var steer_speed := 1.5
@export var steer_speed_air := 1.15
@export var steer_speed_fast := 0.95
@export var grip := 9.0
@export var grip_drifting := 2.4
@export var drift_steer_bonus := 0.5
@export var drift_speed_loss := 4.0
@export var drift_min_speed := 13.0

@export_group("Air")
@export var jump_power := 15.0
@export var gravity := 26.0
@export var air_pitch_gain := 0.035
@export var air_pitch_limit := 0.45
@export var air_roll_gain := 0.3

@export_group("Visuals")
@export var model_path: NodePath = ^"Model"
@export var wheel_radius := 0.31
@export var wheel_steer_angle := 0.35
@export var body_roll := 0.05

var speed := 0.0
var heading := 0.0
var difficulty := 0.0
var can_drive := true
var bot_controlled := false
var _bot_ai: BotYarisAI
var airborne := false
var drifting := false
var distance_driven := 0.0

var _steer := 0.0
var _brake := false
var _pedal := 0.0
var _squash := 0.0
var _model: Node3D
var _body: Node3D
var _wheels: Array[Node3D] = []
var _steer_pivots: Array[Node3D] = []
var _pre_vy := 0.0
var _pre_vel := Vector3.ZERO
var _puddle_t := 0.0
var _dance := 0.0
var _music: BeatMusic
var _body_base_rotation := Vector3.ZERO
var _body_base_scale := Vector3.ONE
var _body_base_position := Vector3.ZERO
var _ai_steer := 0.0
var _ai_brake := false
var _ai_pedal := 1.0


func _ready() -> void:
	up_direction = Vector3.UP
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(70.0)
	floor_snap_length = 0.6
	slide_on_ceiling = false
	_model = get_node_or_null(model_path) as Node3D
	if _model:
		_body = _model.get_node_or_null("Body") as Node3D
		if _body:
			_body_base_position = _body.position
			_body_base_rotation = _body.rotation
			_body_base_scale = _body.scale
	_collect_wheels()
	heading = yaw_from_basis(global_transform.basis)


func _collect_wheels() -> void:
	var paths: Array[String] = [
		"Model/Wheels/FrontLeft/Tire",
		"Model/Wheels/FrontRight/Tire",
		"Model/Wheels/RearLeft/Tire",
		"Model/Wheels/RearRight/Tire",
	]
	for p in paths:
		var w := get_node_or_null(p) as Node3D
		if w:
			_wheels.append(w)
	var pivot_paths: Array[String] = ["Model/Wheels/FrontLeft", "Model/Wheels/FrontRight"]
	var pivots: Array[Node3D] = []
	for p in pivot_paths:
		var n := get_node_or_null(p) as Node3D
		if n:
			pivots.append(n)
	_steer_pivots = pivots


func _physics_process(delta: float) -> void:
	if can_drive:
		if bot_controlled and _bot_ai != null:
			_bot_ai.tick(delta)
			_steer = _ai_steer
			_brake = _ai_brake
			_pedal = _ai_pedal
		else:
			_read_input(delta)
	else:
		_steer = 0.0
		_brake = false
	_update_speed(delta)
	_update_heading(delta)
	_pre_vy = velocity.y
	_update_velocity(delta)
	_pre_vel = velocity
	var was_airborne := airborne
	move_and_slide()
	_report_hits()
	airborne = not is_on_floor()
	_puddle_t = maxf(_puddle_t - delta, 0.0)
	if was_airborne and not airborne:
		_touch_down(-_pre_vy)
	if not airborne and velocity.y < 0.0:
		velocity.y = -1.5
	_update_visuals(delta)
	speed = maxf(speed, 0.0)
	distance_driven += Vector2(velocity.x, velocity.z).length() * delta


func set_ai_input(steer: float, brake: bool, pedal: float) -> void:
	_ai_steer = clampf(steer, -1.0, 1.0)
	_ai_brake = brake
	_ai_pedal = clampf(pedal, 0.0, 1.0)

func enable_bot_ai(world: DesertWorld, level: int, index: int, planner: BotWaypathManager = null) -> void:
	bot_controlled = true
	can_drive = true
	_bot_ai = BotYarisAI.new()
	_bot_ai.setup(self, world, level, index, planner)

func _read_input(delta: float) -> void:
	_steer = clampf(Input.get_axis("steer_left", "steer_right") * Settings.steer_sensitivity, -1.5, 1.5)
	_brake = Input.is_action_pressed("brake")
	if Input.is_action_pressed("accelerate"):
		_pedal = move_toward(_pedal, 1.0, 3.0 * delta)
	else:
		_pedal = move_toward(_pedal, 0.0, 2.0 * delta)
	if Input.is_action_just_pressed("jump"):
		try_jump()


func _update_speed(delta: float) -> void:
	var target := base_cruise_speed + difficulty * difficulty_extra_speed + _pedal * pedal_bonus
	if _brake:
		target = minf(target, base_cruise_speed * 0.25)
	var slope := -global_transform.basis.z.y
	target = clampf(target - slope * 20.0, 0.0, max_speed)
	if not can_drive:
		target = 0.0
	var rate := accel
	if target < speed:
		rate = brake_decel if (_brake or not can_drive) else coast_decel
	speed = move_toward(speed, target, rate * delta)
	if drifting:
		speed = move_toward(speed, 0.0, drift_speed_loss * delta)


func _update_heading(delta: float) -> void:
	drifting = false
	if airborne:
		heading = wrapf(heading - _steer * steer_speed_air * delta, -PI, PI)
		return
	if absf(_steer) > 0.15 and speed > drift_min_speed and not _brake:
		drifting = true
	var rate := steer_speed
	if speed > 26.0:
		rate = lerpf(steer_speed, steer_speed_fast, clampf((speed - 26.0) / 24.0, 0.0, 1.0))
	if drifting:
		rate += drift_steer_bonus
	heading = wrapf(heading - _steer * rate * delta, -PI, PI)


func _update_velocity(delta: float) -> void:
	var desired := _flat_forward() * speed
	if airborne:
		velocity.y -= gravity * delta
		var fa := 1.0 - exp(-0.5 * delta)
		velocity.x = lerpf(velocity.x, desired.x, fa)
		velocity.z = lerpf(velocity.z, desired.z, fa)
		return
	var g := grip_drifting if drifting else grip
	if _puddle_t > 0.0:
		g *= puddle_grip_mult
	var f := 1.0 - exp(-g * delta)
	velocity.x = lerpf(velocity.x, desired.x, f)
	velocity.z = lerpf(velocity.z, desired.z, f)


func _update_visuals(delta: float) -> void:
	var up := Vector3.UP
	if not airborne:
		up = Vector3.UP.lerp(get_floor_normal(), 0.6)
		if up.length_squared() < 0.01:
			up = Vector3.UP
		up = up.normalized()
	var fwd := _flat_forward()
	fwd -= up * fwd.dot(up)
	if fwd.length_squared() < 0.001:
		fwd = _flat_forward()
	fwd = fwd.normalized()
	var zb := -fwd
	var xb := up.cross(zb).normalized()
	var yb := zb.cross(xb).normalized()
	var target := Basis(xb, yb, zb)
	if airborne:
		target = target * Basis(Vector3.RIGHT, clampf(velocity.y * air_pitch_gain, -air_pitch_limit, air_pitch_limit))
		target = target * Basis(Vector3.BACK, -_steer * air_roll_gain)
	else:
		target = target * Basis(Vector3.BACK, _steer * body_roll * clampf(speed / 40.0, 0.0, 1.0))
	var q := Quaternion(global_transform.basis).slerp(Quaternion(target), 1.0 - exp(-12.0 * delta))
	global_transform = Transform3D(Basis(q).orthonormalized(), global_position)
	_spin_wheels(delta)
	_update_body(delta)


func _spin_wheels(delta: float) -> void:
	var spin := (speed * delta) / maxf(wheel_radius, 0.05)
	if spin > 0.0001:
		var axis := global_transform.basis.x
		for w in _wheels:
			w.global_rotate(axis, -spin)
	for i in _steer_pivots.size():
		_steer_pivots[i].rotation.y = -_steer * wheel_steer_angle


func _update_body(delta: float) -> void:
	if _body == null:
		return
	_squash = maxf(_squash - delta * 2.4, 0.0)
	# Constant dance while music plays: a hard squish on every beat that
	# springs back before the next one, plus a side-to-side sway.
	var pulse := 0.0
	var sway := 0.0
	var m := _get_music()
	if dance_enabled and m != null and m.playing:
		var bf := m.beat_float()
		pulse = pow(1.0 - fposmod(bf, 1.0), 3.0)
		sway = sin(bf * PI)
	_dance = lerpf(_dance, pulse, 1.0 - exp(-35.0 * delta))
	var sq := minf(_squash * 0.5 + _dance * dance_squash, 0.6)
	var dance_scale := Vector3(1.0 + sq * 0.55, 1.0 - sq, 1.0 + sq * 0.55)
	_body.position = _body_base_position
	_body.scale = _body_base_scale * dance_scale
	_body.rotation = _body_base_rotation + Vector3(-_dance * dance_nod, 0.0, sway * dance_tilt)


func _get_music() -> BeatMusic:
	if _music == null or not is_instance_valid(_music):
		_music = get_tree().get_first_node_in_group("beat_music") as BeatMusic
	return _music


func _report_hits() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other != null and other.has_method("on_car_hit"):
			var n := col.get_normal()
			var impact := maxf(-_pre_vel.dot(n), 0.0)
			other.call("on_car_hit", self, _pre_vel, n, impact)


## Called by obstacles. push is added to velocity, speed_keep scales speed.
func take_hit(strength: float, push: Vector3, speed_keep: float, lethal_reason := "") -> void:
	speed *= clampf(speed_keep, 0.0, 1.0)
	velocity += push
	heading = wrapf(heading + randf_range(-0.4, 0.4) * clampf(strength / 30.0, 0.0, 1.0), -PI, PI)
	_squash = clampf(strength * 0.02, 0.15, 0.6)
	crashed.emit(strength, lethal_reason)


## Puddle: grip drops for a moment and the car kicks sideways.
func hit_puddle() -> void:
	if airborne:
		return
	_puddle_t = puddle_time
	var right := global_transform.basis.x
	velocity += right * randf_range(-6.0, 6.0)
	splashed.emit()


func _touch_down(impact: float) -> void:
	if impact > 3.0:
		_squash = clampf(impact * 0.022, 0.0, 0.5)
	if impact > 5.0:
		landed.emit(impact)
	if impact > 14.0:
		speed *= 0.88


func try_jump() -> bool:
	if airborne or not can_drive:
		return false
	velocity.y = jump_power
	airborne = true
	speed = maxf(speed, 12.0)
	jumped.emit()
	return true


func reset_to(tf: Transform3D) -> void:
	var reset_basis := tf.basis.orthonormalized()
	if reset_basis.determinant() < 0.0:
		reset_basis = Basis(Vector3.UP, 0.0)
	global_transform = Transform3D(reset_basis, tf.origin)
	velocity = Vector3.ZERO
	speed = 0.0
	_pedal = 0.0
	_squash = 0.0
	airborne = false
	drifting = false
	heading = yaw_from_basis(reset_basis)


func current_kmh() -> float:
	return absf(speed) * 3.6


func _flat_forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


static func yaw_from_basis(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)
