class_name RoadObstacle
extends RigidBody3D
## Pole, rock, debris or cone. Frozen (acts static) until the Yaris hits it,
## then real physics takes over and it goes flying. Rocks never move.

enum Kind { POLE, ROCK, DEBRIS, CONE }

@export var kind: Kind = Kind.POLE
## Head-on impact speed (m/s) above which the hit eliminates the player.
@export var lethal_impact := 36.0

var _hit := false
var _cooldown := 0.0


func _ready() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func on_car_hit(car: Yaris, car_vel: Vector3, normal: Vector3, impact: float) -> void:
	if _hit or _cooldown > 0.0:
		return
	var flat_n := Vector3(normal.x, 0.0, normal.z)
	if flat_n.length_squared() < 0.001:
		return
	flat_n = flat_n.normalized()
	if kind == Kind.ROCK:
		if impact < 4.0:
			return
		_cooldown = 0.5
		var reason := "Écrasé contre un rocher" if impact > lethal_impact + 6.0 else ""
		car.take_hit(impact, flat_n * impact * 0.45 + Vector3.UP * 3.5, 0.5, reason)
		return
	_hit = true
	add_collision_exception_with(car)
	car.add_collision_exception_with(self)
	freeze = false
	var lift := 5.0 + impact * 0.3
	apply_central_impulse((car_vel * 0.95 + Vector3.UP * lift) * mass)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	apply_torque_impulse(spin * mass * 6.0)
	match kind:
		Kind.POLE:
			var reason := "Collision avec un poteau" if impact > lethal_impact else ""
			car.take_hit(impact, flat_n * impact * 0.3 + Vector3.UP * 2.0, 0.55, reason)
		_:
			car.take_hit(impact * 0.3, Vector3.UP * 1.5, 0.94, "")
	get_tree().create_timer(6.0).timeout.connect(queue_free)
