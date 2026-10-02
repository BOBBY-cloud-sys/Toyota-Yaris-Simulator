class_name BotManager
extends Node
## Spawns and owns the Yaris opponents for VS BOTS.
## The bots are driven by independent generated waypaths, not by player input.

var world: DesertWorld
var player: Yaris
var count := 0
var difficulty := 0
var bots: Array[Yaris] = []
var waypath: BotWaypathManager

func setup(p_world: DesertWorld, p_player: Yaris, p_count: int, p_difficulty: int) -> void:
	world = p_world
	player = p_player
	count = clampi(p_count, 1, 64)
	difficulty = clampi(p_difficulty, 0, 4)
	waypath = BotWaypathManager.new()
	waypath.name = "BotWaypathManager"
	add_child(waypath)
	waypath.setup(world, difficulty)
	_spawn_bots()

func _spawn_bots() -> void:
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	if world == null or player == null:
		return
	var lanes: Array[float] = [-4.25, 0.0, 4.25]
	var player_progress := world.road_progress_near(player.global_position)
	for i in count:
		var bot := preload("res://scenes/yaris.tscn").instantiate() as Yaris
		if bot == null:
			continue
		bot.name = "BotYaris_%02d" % (i + 1)
		bot.dance_enabled = true
		world.add_child(bot)
		var lane := lanes[i % lanes.size()]
		var spawn_progress := player_progress - 12.0 - float(i) * 6.0
		bot.global_transform = world.road_transform_at(spawn_progress / maxf(world.chunk_length, 0.01), lane)
		bot.global_position += Vector3.UP * 0.3
		bot.difficulty = float(difficulty) / 4.0
		bots.append(bot)
		waypath.register_bot(bot, i)
		bot.enable_bot_ai(world, difficulty, i, waypath)

func _process(_delta: float) -> void:
	if world == null:
		return
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		if bot.global_position.y < world.fall_plane() - 10.0:
			bot.reset_to(world.road_transform_near(bot.global_position))
