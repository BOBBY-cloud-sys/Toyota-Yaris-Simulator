extends Node3D
## Canonical Summer library level setup - collision + spawn.
## Written by the harness. Attach to the scene root, set the exports,
## DO NOT rewrite the logic: it handles off-origin maps, sky domes,
## tree crowns and missed rays.

@export var level_path: NodePath
@export var player_path: NodePath
## Fallback only - the real foot offset is measured from the player's own
## collision shape so the capsule never spawns embedded in the ground.
@export var player_ground_offset: float = 0.95
@export var skip_substrings: Array[String] = ["sky", "dome", "cloud", "atmosphere", "tree", "leaf", "leaves", "branch", "bush", "crown", "foliage"]

func _ready() -> void:
	var level := get_node_or_null(level_path)
	if level == null:
		push_warning("[library_setup] level_path not set")
		return
	var count := 0
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or _skip(mi, true):
			continue
		mi.create_trimesh_collision()
		_harden_collision(mi)
		count += 1
	print("[library_setup] collision on %d meshes" % count)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn(level)

func _skip(mi: MeshInstance3D, for_collision: bool) -> bool:
	var n := str(mi.name).to_lower()
	for s in skip_substrings:
		# Trees DO get collision (you should not walk through trunks),
		# but they are never spawn ground. Sky-like shells get neither.
		var sky_like := s in ["sky", "dome", "cloud", "atmosphere"]
		if _name_matches(n, s) and (sky_like or not for_collision):
			return true
	if for_collision:
		var size: Vector3 = (mi.global_transform.basis.get_scale().abs() * mi.mesh.get_aabb().size)
		var mx := maxf(size.x, maxf(size.y, size.z))
		var mn := minf(size.x, minf(size.y, size.z))
		if mx > 80.0 and mn > mx * 0.6:
			return true
		# Tiny clutter (cups, shards, pebbles) never blocks movement but its
		# trimesh crevices constantly snag the capsule - skip it.
		if mx < 0.35:
			return true
	return false

func _name_matches(n: String, s: String) -> bool:
	# Token-boundary match, not substring: "street" must NOT match "tree",
	# while "pinetree", "tree_01" and "TreeLarge" must. Tokens are the
	# delimiter-separated pieces of the name; a hit is a token that equals,
	# starts or ends with the keyword (compound words like "pinetree").
	var cleaned := ""
	for i in n.length():
		var ch := n[i]
		var code := ch.unicode_at(0)
		var alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		cleaned += ch if alnum else " "
	for token in cleaned.split(" ", false):
		if token == s or token.begins_with(s) or token.ends_with(s):
			return true
	return false

func _harden_collision(mi: MeshInstance3D) -> void:
	# PS1-era assets often ship flipped normals: a backface lets the player
	# clip inside a wall and the frontfaces then trap them there. Two-sided
	# collision closes that hole.
	for child in mi.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		for shape_node in body.get_children():
			var col := shape_node as CollisionShape3D
			if col == null:
				continue
			var concave := col.shape as ConcavePolygonShape3D
			if concave != null:
				concave.backface_collision = true

func _spawn(level: Node) -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return
	var merged := AABB()
	var first := true
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or _skip(mi, false):
			continue
		var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		merged = aabb if first else merged.merge(aabb)
		first = false
	if first:
		push_warning("[library_setup] no ground meshes for spawn")
		return
	var c := merged.get_center()
	var top := merged.position.y + merged.size.y + 5.0
	var best := Vector3.INF
	# Typed array: many generated projects elevate inference warnings to
	# errors, and an untyped literal here makes "off" a Variant, which kills
	# the whole script with a parse error.
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(merged.size.x * 0.15, 0, 0), Vector3(-merged.size.x * 0.15, 0, 0), Vector3(0, 0, merged.size.z * 0.15), Vector3(0, 0, -merged.size.z * 0.15), Vector3(merged.size.x * 0.3, 0, merged.size.z * 0.3)]
	for off in offsets:
		var from := Vector3(c.x, top, c.z) + off
		var hit := _ray_down(from, player)
		# lowest hit wins: crowns and roofs sit above the real ground
		if hit != Vector3.INF and (best == Vector3.INF or hit.y < best.y):
			best = hit
	if best == Vector3.INF:
		push_warning("[library_setup] all spawn rays missed")
		return
	# Feet just above the hit, never embedded: measured from the player's own
	# collider, with clearance. A wider safe margin also stops trimesh cracks
	# from wedging the capsule while walking.
	player.safe_margin = maxf(player.safe_margin, 0.02)
	player.global_position = best + Vector3(0, _foot_offset(player) + 0.2, 0)
	player.velocity = Vector3.ZERO
	print("[library_setup] spawn at %s" % str(player.global_position))

func _foot_offset(p: CharacterBody3D) -> float:
	# Distance from the body origin down to the lowest point of its collider.
	var lowest := INF
	for cs_node in p.find_children("*", "CollisionShape3D", true, false):
		var cs := cs_node as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var half := 0.0
		if cs.shape is CapsuleShape3D:
			half = (cs.shape as CapsuleShape3D).height * 0.5
		elif cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size.y * 0.5
		elif cs.shape is SphereShape3D:
			half = (cs.shape as SphereShape3D).radius
		elif cs.shape is CylinderShape3D:
			half = (cs.shape as CylinderShape3D).height * 0.5
		else:
			continue
		var bottom := cs.global_position.y - p.global_position.y - half
		if bottom < lowest:
			lowest = bottom
	if lowest == INF:
		return player_ground_offset
	return -lowest

func _ray_down(from: Vector3, exclude_body: PhysicsBody3D) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -500, 0))
	q.exclude = [exclude_body.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return Vector3.INF
	var pos: Vector3 = r["position"]
	return pos
