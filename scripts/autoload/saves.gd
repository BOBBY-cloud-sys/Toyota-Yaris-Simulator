extends Node
## Save slots in user://saves/slot_N.json (survives restarts, not a cache dir).
## Each slot keeps statistics plus an optional resumable route.

const SLOTS := 3
const DIR := "user://saves"
const GARAGE_CREDITS_PER_KM := 10.0

var active_slot := 1
## Filled by the main menu before loading the game scene.
var pending_resume: Dictionary = {}
var pending_seed := 0
var pending_vs_bots: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func default_data() -> Dictionary:
	return {
		"version": 1,
		"best_distance": 0.0,
		"top_speed": 0.0,
		"longest_time": 0.0,
		"total_distance": 0.0,
		"runs": 0,
		"refuels": 0,
		"updated": 0,
		"garage_credits": 0.0,
		"garage_purchased": [],
		"resume": {},
	}


func load_slot(slot: int) -> Dictionary:
	var data := default_data()
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return data
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return data
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var d: Dictionary = {}
	if parsed is Dictionary:
		d = parsed
		for k in d.keys():
			data[k] = d[k]
	# Older TYS saves had no garage wallet. Give them the value represented by
	# their already completed mileage once, then keep the stored wallet persistent.
	if not d.has("garage_credits"):
		data["garage_credits"] = float(data.get("total_distance", 0.0)) / 1000.0 * GARAGE_CREDITS_PER_KM
	if not d.has("garage_purchased"):
		data["garage_purchased"] = []
	return data


func write_slot(slot: int, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	data["updated"] = int(Time.get_unix_time_from_system())
	var p := slot_path(slot)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[saves] cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	DirAccess.rename_absolute(tmp, p)


func delete_slot(slot: int) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(slot_path(slot))


func has_resume(slot: int) -> bool:
	var r: Variant = load_slot(slot).get("resume", {})
	return r is Dictionary and not (r as Dictionary).is_empty()


## Most recently updated slot that holds a resumable route, or -1.
func latest_resumable_slot() -> int:
	var best := -1
	var best_t := -1
	for s in range(1, SLOTS + 1):
		if not has_resume(s):
			continue
		var t := int(load_slot(s).get("updated", 0))
		if t > best_t:
			best_t = t
			best = s
	return best


func _merge_bests(data: Dictionary, run: Dictionary) -> void:
	data["best_distance"] = maxf(float(data["best_distance"]), float(run.get("distance", 0.0)))
	data["top_speed"] = maxf(float(data["top_speed"]), float(run.get("top_speed", 0.0)))
	data["longest_time"] = maxf(float(data["longest_time"]), float(run.get("time", 0.0)))


## Autosave during a run: bests + resumable position.
func update_progress(run: Dictionary) -> void:
	var data := load_slot(active_slot)
	_merge_bests(data, run)
	data["resume"] = run
	write_slot(active_slot, data)


## Run is over (eliminated / restarted): bests, totals, no resume point.
func finish_run(run: Dictionary) -> void:
	var data := load_slot(active_slot)
	_merge_bests(data, run)
	data["runs"] = int(data["runs"]) + 1
	var gained_distance: float = maxf(float(run.get("distance", 0.0)) - float(run.get("resumed_from", 0.0)), 0.0)
	data["total_distance"] = float(data["total_distance"]) + gained_distance
	data["garage_credits"] = float(data.get("garage_credits", 0.0)) + gained_distance / 1000.0 * GARAGE_CREDITS_PER_KM
	data["resume"] = {}
	write_slot(active_slot, data)

func garage_data() -> Dictionary:
	return load_slot(active_slot)

func garage_can_buy(price: float, required_km: float) -> bool:
	var data := load_slot(active_slot)
	return float(data.get("total_distance", 0.0)) >= required_km and float(data.get("garage_credits", 0.0)) >= price

func garage_is_purchased(vehicle_id: String) -> bool:
	var data := load_slot(active_slot)
	var purchased: Array = data.get("garage_purchased", [])
	return vehicle_id in purchased

func garage_buy(vehicle_id: String, price: float, required_km: float) -> bool:
	var data := load_slot(active_slot)
	var purchased: Array = data.get("garage_purchased", [])
	if vehicle_id in purchased:
		return true
	if float(data.get("total_distance", 0.0)) < required_km:
		return false
	if float(data.get("garage_credits", 0.0)) < price:
		return false
	data["garage_credits"] = float(data.get("garage_credits", 0.0)) - price
	purchased.append(vehicle_id)
	data["garage_purchased"] = purchased
	write_slot(active_slot, data)
	return true
