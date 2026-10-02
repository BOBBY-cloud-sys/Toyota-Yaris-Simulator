class_name DesertRamp
extends Area3D

@export var launch_power := 20.0
@export var forward_boost := 10.0
@export var cooldown := 0.9

var world: DesertWorld
var _last_hit: Dictionary = {}

func setup(p_world: DesertWorld) -> void:
    world = p_world
    monitoring = true
    monitorable = true
    collision_layer = 4
    collision_mask = 1
    add_to_group("desert_ramps")
    body_entered.connect(_on_body_entered)
    _build_visual()

func _build_visual() -> void:
    var wood := StandardMaterial3D.new()
    wood.albedo_color = Color(0.48, 0.28, 0.12)
    wood.roughness = 0.92

    var deck := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(5.2, 0.32, 7.0)
    deck.mesh = box
    deck.material_override = wood
    deck.rotation.x = deg_to_rad(14.0)
    deck.position.y = 0.32
    add_child(deck)

    for x in [-1.9, 0.0, 1.9]:
        var beam := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.28, 0.7, 6.0)
        beam.mesh = bm
        beam.material_override = wood
        beam.position = Vector3(x, -0.05, 0.25)
        beam.rotation.x = deg_to_rad(14.0)
        add_child(beam)

    var shape := CollisionShape3D.new()
    var cs := BoxShape3D.new()
    cs.size = Vector3(5.4, 1.1, 7.2)
    shape.shape = cs
    add_child(shape)

func _on_body_entered(body: Node3D) -> void:
    if not body is Yaris:
        return
    var car := body as Yaris
    if car == null or not car.can_drive:
        return
    var id := car.get_instance_id()
    var now := Time.get_ticks_msec() * 0.001
    if _last_hit.has(id) and now - float(_last_hit[id]) < cooldown:
        return
    _last_hit[id] = now

    var forward := -global_transform.basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.001:
        forward = Vector3(0.0, 0.0, -1.0)
    forward = forward.normalized()
    car.velocity += forward * forward_boost
    car.velocity.y = maxf(car.velocity.y, launch_power)
    car.airborne = true
    car.jumped.emit()
