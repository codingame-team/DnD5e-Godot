## SettingsManager.gd
## Gestion centralisee des preferences utilisateur (audio, camera, raccourcis).
extends Node

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULT_SETTINGS := {
	"music_enabled": true,
	"sfx_enabled": true,
	"music_volume_db": -10.0,
	"sfx_volume_db": 0.0,
	"mouse_sensitivity": 0.4,
	"invert_camera_x": false,
	"keybinds": {
		"move_forward": KEY_Z,
		"move_back": KEY_S,
		"turn_left": KEY_Q,
		"turn_right": KEY_D,
		"cam_cycle_mode": KEY_V,
		"cam_rotate_left": KEY_A,
		"cam_rotate_right": KEY_E,
		"cam_zoom_in": KEY_EQUAL,
		"cam_zoom_out": KEY_MINUS,
		"jump": KEY_SPACE,
		"roll": KEY_R
	}
}

const PRESET_QWERTY := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"turn_left": KEY_A,
	"turn_right": KEY_D,
	"cam_cycle_mode": KEY_V,
	"cam_rotate_left": KEY_Q,
	"cam_rotate_right": KEY_E,
	"cam_zoom_in": KEY_EQUAL,
	"cam_zoom_out": KEY_MINUS,
	"jump": KEY_SPACE,
	"roll": KEY_R
}

var _settings: Dictionary = {}

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	_settings = _deep_copy(DEFAULT_SETTINGS)
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	for key in DEFAULT_SETTINGS.keys():
		if key == "keybinds":
			continue
		_settings[key] = cfg.get_value("settings", key, DEFAULT_SETTINGS[key])
	for action in DEFAULT_SETTINGS["keybinds"].keys():
		var default_key: int = int(DEFAULT_SETTINGS["keybinds"][action])
		_settings["keybinds"][action] = int(cfg.get_value("keybinds", action, default_key))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _settings.keys():
		if key == "keybinds":
			continue
		cfg.set_value("settings", key, _settings[key])
	for action in _settings["keybinds"].keys():
		cfg.set_value("keybinds", action, _settings["keybinds"][action])
	cfg.save(SETTINGS_PATH)

func get_setting(key: String):
	return _settings.get(key, DEFAULT_SETTINGS.get(key))

func set_setting(key: String, value) -> void:
	if not _settings.has(key):
		return
	_settings[key] = value

func get_keybind(action: String) -> int:
	if not _settings.has("keybinds"):
		return int(DEFAULT_SETTINGS["keybinds"].get(action, KEY_UNKNOWN))
	var fallback: int = int(DEFAULT_SETTINGS["keybinds"].get(action, KEY_UNKNOWN))
	return int(_settings["keybinds"].get(action, fallback))

func set_keybind(action: String, keycode: int) -> void:
	if not _settings.has("keybinds"):
		_settings["keybinds"] = _deep_copy(DEFAULT_SETTINGS["keybinds"])
	_settings["keybinds"][action] = keycode

func reset_defaults() -> void:
	_settings = _deep_copy(DEFAULT_SETTINGS)
	save_settings()

func apply_preset(preset_name: String) -> void:
	var preset: Dictionary
	match preset_name:
		"AZERTY":
			preset = DEFAULT_SETTINGS["keybinds"]
		"QWERTY":
			preset = PRESET_QWERTY
		_:
			return
	if not _settings.has("keybinds"):
		_settings["keybinds"] = {}
	for action in preset.keys():
		_settings["keybinds"][action] = int(preset[action])

func _deep_copy(source: Dictionary) -> Dictionary:
	var output := {}
	for key in source.keys():
		if source[key] is Dictionary:
			output[key] = _deep_copy(source[key])
		else:
			output[key] = source[key]
	return output
