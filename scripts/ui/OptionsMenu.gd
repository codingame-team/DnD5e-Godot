## OptionsMenu.gd
## Ecran Options: audio, camera et raccourcis clavier.
extends Control

const ACTIONS := [
	{"id": "move_forward", "label": "Avancer"},
	{"id": "move_back", "label": "Reculer"},
	{"id": "turn_left", "label": "Tourner gauche"},
	{"id": "turn_right", "label": "Tourner droite"},
	{"id": "cam_cycle_mode", "label": "Changer mode camera"},
	{"id": "cam_rotate_left", "label": "Camera gauche"},
	{"id": "cam_rotate_right", "label": "Camera droite"},
	{"id": "cam_zoom_in", "label": "Zoom +"},
	{"id": "cam_zoom_out", "label": "Zoom -"}
]

@onready var chk_music: CheckBox = $Panel/VBox/ChkMusic
@onready var chk_sfx: CheckBox = $Panel/VBox/ChkSfx
@onready var sld_music: HSlider = $Panel/VBox/MusicRow/SldMusic
@onready var lbl_music: Label = $Panel/VBox/MusicRow/LblMusicValue
@onready var sld_sfx: HSlider = $Panel/VBox/SfxRow/SldSfx
@onready var lbl_sfx: Label = $Panel/VBox/SfxRow/LblSfxValue
@onready var sld_sens: HSlider = $Panel/VBox/SensRow/SldSens
@onready var lbl_sens: Label = $Panel/VBox/SensRow/LblSensValue
@onready var chk_invert_x: CheckBox = $Panel/VBox/ChkInvertX
@onready var opt_preset: OptionButton = $Panel/VBox/PresetRow/OptPreset
@onready var keybind_grid: GridContainer = $Panel/VBox/KeybindScroll/KeybindGrid
@onready var btn_back: Button = $Panel/VBox/Buttons/BtnBack
@onready var btn_apply: Button = $Panel/VBox/Buttons/BtnApply
@onready var btn_reset: Button = $Panel/VBox/Buttons/BtnReset

var _binding_buttons: Dictionary = {}
var _pending_action: String = ""

func _settings_manager() -> Node:
	return get_node("/root/SettingsManager")

func _ready() -> void:
	_settings_manager().load_settings()
	_build_keybind_ui()
	_load_values()
	_connect_signals()

func _build_keybind_ui() -> void:
	for child in keybind_grid.get_children():
		child.queue_free()
	_binding_buttons.clear()

	for item in ACTIONS:
		var action_id: String = item["id"]
		var action_label: String = item["label"]

		var lbl := Label.new()
		lbl.text = action_label
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keybind_grid.add_child(lbl)

		var btn := Button.new()
		btn.text = _key_to_text(_settings_manager().get_keybind(action_id))
		btn.pressed.connect(_on_rebind_pressed.bind(action_id))
		keybind_grid.add_child(btn)
		_binding_buttons[action_id] = btn

func _load_values() -> void:
	chk_music.button_pressed = _settings_manager().get_setting("music_enabled")
	chk_sfx.button_pressed = _settings_manager().get_setting("sfx_enabled")
	sld_music.value = float(_settings_manager().get_setting("music_volume_db"))
	sld_sfx.value = float(_settings_manager().get_setting("sfx_volume_db"))
	sld_sens.value = float(_settings_manager().get_setting("mouse_sensitivity"))
	chk_invert_x.button_pressed = _settings_manager().get_setting("invert_camera_x")
	_update_labels()

func _connect_signals() -> void:
	sld_music.value_changed.connect(_on_music_volume_changed)
	sld_sfx.value_changed.connect(_on_sfx_volume_changed)
	sld_sens.value_changed.connect(_on_slider_changed)
	chk_music.toggled.connect(_on_music_toggled)
	chk_sfx.toggled.connect(_on_sfx_toggled)
	opt_preset.item_selected.connect(_on_preset_selected)
	btn_apply.pressed.connect(_on_apply)
	btn_back.pressed.connect(_on_back)
	btn_reset.pressed.connect(_on_reset)

func _on_slider_changed(_value: float) -> void:
	_update_labels()

func _on_music_volume_changed(value: float) -> void:
	_update_labels()
	AudioManager.set_music_volume(value)

func _on_sfx_volume_changed(value: float) -> void:
	_update_labels()
	AudioManager.set_sfx_volume(value)

func _on_music_toggled(pressed: bool) -> void:
	AudioManager.music_enabled = pressed

func _on_sfx_toggled(pressed: bool) -> void:
	AudioManager.sfx_enabled = pressed

func _on_preset_selected(index: int) -> void:
	var preset_name := "AZERTY" if index == 0 else "QWERTY"
	_settings_manager().apply_preset(preset_name)
	_build_keybind_ui()

func _update_labels() -> void:
	lbl_music.text = "%d dB" % int(round(sld_music.value))
	lbl_sfx.text = "%d dB" % int(round(sld_sfx.value))
	lbl_sens.text = "%.2f" % sld_sens.value

func _on_rebind_pressed(action_id: String) -> void:
	_pending_action = action_id
	for key in _binding_buttons.keys():
		var b: Button = _binding_buttons[key]
		b.disabled = true
	var btn: Button = _binding_buttons[action_id]
	btn.disabled = false
	btn.text = "Appuyez sur une touche..."

func _find_action_with_keycode(keycode: int) -> String:
	for item in ACTIONS:
		var action_id: String = item["id"]
		if _settings_manager().get_keybind(action_id) == keycode:
			return action_id
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if _pending_action.is_empty():
		return
	if not (event is InputEventKey and event.pressed):
		return
	var key_event := event as InputEventKey
	var keycode := key_event.keycode
	if keycode == KEY_ESCAPE:
		_cancel_rebind()
		return
	var conflicting := _find_action_with_keycode(keycode)
	if conflicting != "" and conflicting != _pending_action:
		var old_key: int = _settings_manager().get_keybind(_pending_action)
		_settings_manager().set_keybind(conflicting, old_key)
		var conflict_btn: Button = _binding_buttons[conflicting]
		conflict_btn.text = _key_to_text(old_key)
	_settings_manager().set_keybind(_pending_action, keycode)
	var btn: Button = _binding_buttons[_pending_action]
	btn.text = _key_to_text(keycode)
	_pending_action = ""
	for key in _binding_buttons.keys():
		var b: Button = _binding_buttons[key]
		b.disabled = false
	get_viewport().set_input_as_handled()

func _cancel_rebind() -> void:
	if _pending_action.is_empty():
		return
	var previous: int = _settings_manager().get_keybind(_pending_action)
	var btn: Button = _binding_buttons[_pending_action]
	btn.text = _key_to_text(previous)
	_pending_action = ""
	for key in _binding_buttons.keys():
		var b: Button = _binding_buttons[key]
		b.disabled = false

func _on_apply() -> void:
	_apply_settings()

func _on_back() -> void:
	_apply_settings()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_reset() -> void:
	_settings_manager().reset_defaults()
	_load_values()
	_build_keybind_ui()
	_apply_audio_preview()

func _apply_settings() -> void:
	_settings_manager().set_setting("music_enabled", chk_music.button_pressed)
	_settings_manager().set_setting("sfx_enabled", chk_sfx.button_pressed)
	_settings_manager().set_setting("music_volume_db", sld_music.value)
	_settings_manager().set_setting("sfx_volume_db", sld_sfx.value)
	_settings_manager().set_setting("mouse_sensitivity", sld_sens.value)
	_settings_manager().set_setting("invert_camera_x", chk_invert_x.button_pressed)
	_settings_manager().save_settings()
	_apply_audio_preview()

func _apply_audio_preview() -> void:
	AudioManager.music_enabled = chk_music.button_pressed
	AudioManager.sfx_enabled = chk_sfx.button_pressed
	AudioManager.set_music_volume(sld_music.value)
	AudioManager.set_sfx_volume(sld_sfx.value)

func _key_to_text(keycode: int) -> String:
	if keycode == KEY_UNKNOWN:
		return "(non defini)"
	return OS.get_keycode_string(keycode)
