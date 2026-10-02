class_name Puddle
extends Area3D
## Slick water on the road: the Yaris loses grip for a moment and slides.

var _used_by: Array[Node] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var car := body as Yaris
	if car == null or car.airborne:
		return
	car.hit_puddle()
	_splash(car.global_position)


func _splash(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 48
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 11.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var drop := SphereMesh.new()
	drop.radius = 0.12
	drop.height = 0.24
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.75, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = mat
	p.mesh = drop
	get_tree().current_scene.add_child(p)
	p.global_position = at + Vector3.UP * 0.3
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
