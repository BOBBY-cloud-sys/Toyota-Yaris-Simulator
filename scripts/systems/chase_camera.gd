class_name ChaseCamera
extends Camera3D
## Third-person chase camera. Every frame the desired position is derived from
## the vehicle's own transform, never from world-space constants, so the camera
## always stays behind the car through turns, jumps and drifts.

@export var target_path: NodePath = ^"../Yaris"
@export var distance := 9.5
@export var height := 3.2
@export var look_ahead := 13.0
@export var look_height := 1.5
@export var follow_smoothing := 5.0
@export var height_smoothing := 3.2
@export var turn_smoothing := 7.0
@export var base_fov := 70.0
@export var fov_per_speed := 0.35
@export var max_fov := 100.0
@export var shake_scale := 1.0
@export var shake_decay := 2.2
@export var speed_rumble := 0.06

var target: Node3D

var _look := Vector3.ZERO
var _shake := 0.0
var _fov := 70.0
var _init := false
var _time := 0.0


func _ready() -> void:
	_fov = base_fov
	fov = _fov
	if target == null:
		target = get_node_or_null(target_path) as Node3D


## Forget the current pose so the next update snaps straight behind the car.
func snap() -> void:
	_init = false


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount * shake_scale, 2.5)


func _physics_process(delta: float) -> void:
	_time += delta
	if target == null:
		target = get_node_or_null(target_path) as Node3D
		if target == null:
			return
	var flat := _flat_forward(target)
	var desired := target.global_position - flat * distance + Vector3.UP * height
	if not _init:
		global_position = desired
		_look = target.global_position + Vector3.UP * look_height + flat * look_ahead
		_init = true
	else:
		var p := global_position.lerp(desired, 1.0 - exp(-follow_smoothing * delta))
		p.y = lerpf(global_position.y, desired.y, 1.0 - exp(-height_smoothing * delta))
		global_position = p
		var want := target.global_position + flat * look_ahead + Vector3.UP * look_height
		_look = _look.lerp(want, 1.0 - exp(-turn_smoothing * delta))
	if global_position.distance_squared_to(_look) > 0.01:
		look_at(_look, Vector3.UP)
	_shake = maxf(_shake - shake_decay * delta, 0.0)
	var wobble := _shake + clampf(_speed_of(target) / 60.0, 0.0, 1.0) * speed_rumble * shake_scale
	if wobble > 0.001:
		global_position += Vector3(sin(_time * 41.0), sin(_time * 57.0 + 1.3), sin(_time * 33.0 + 2.1)) * wobble * 0.45
	var want_fov := clampf(base_fov + _speed_of(target) * fov_per_speed + _shake * 3.0, base_fov, max_fov)
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-3.0 * delta))
	fov = _fov


func _flat_forward(node: Node3D) -> Vector3:
	var f := -node.global_transform.basis.z
	var flat := Vector3(f.x, 0.0, f.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return flat.normalized()


func _speed_of(node: Node3D) -> float:
	if node is Yaris:
		return absf((node as Yaris).speed)
	return 0.0
