extends Node
## Persistent player settings (user://settings.cfg).
## The one authoritative settings store - every screen reads/writes here.

signal changed

const PATH := "user://settings.cfg"
const KEYS: Array[String] = [
	"master_volume", "music_volume", "sfx_volume",
	"steer_sensitivity",
	"camera_sensitivity", "camera_smoothing", "camera_shake",
	"brightness", "contrast", "saturation",
	"reduce_flashing",
]

var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.8
var steer_sensitivity := 1.0
var camera_sensitivity := 1.0
var camera_smoothing := 1.0
var camera_shake := 1.0
var brightness := 1.0
var contrast := 1.0
var saturation := 1.0
var reduce_flashing := false


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply()


func _ensure_buses() -> void:
	var names: Array[String] = ["Music", "SFX"]
	for bus_name in names:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in KEYS:
		set(k, cfg.get_value("settings", k, get(k)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in KEYS:
		cfg.set_value("settings", k, get(k))
	cfg.save(PATH)


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save_settings()


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	changed.emit()


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


## Effective shake multiplier (0 = disabled). Reduced when flashing is reduced.
func shake_amount() -> float:
	return camera_shake * (0.35 if reduce_flashing else 1.0)


func apply_environment(env: Environment) -> void:
	if env == null:
		return
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness
	env.adjustment_contrast = contrast
	env.adjustment_saturation = saturation


## Label printed on the key at a physical position, for the active layout.
func key_label(physical: Key) -> String:
	var k: Key = DisplayServer.keyboard_get_label_from_physical(physical)
	var s := OS.get_keycode_string(k)
	if s == "":
		s = OS.get_keycode_string(physical)
	return s.to_upper()


func layout_name() -> String:
	return "AZERTY" if key_label(KEY_Q) == "A" else "QWERTY"
