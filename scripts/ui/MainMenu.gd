## MainMenu.gd
## Contrôleur du menu principal.
extends Control

@onready var btn_new_game: Button = $VBox/BtnNewGame
@onready var btn_load_game: Button = $VBox/BtnLoadGame
@onready var btn_test_combat: Button = $VBox/BtnTestCombat
@onready var btn_settings: Button = $VBox/BtnSettings
@onready var btn_quit: Button = $VBox/BtnQuit

func _ready() -> void:
	btn_new_game.pressed.connect(_on_new_game)
	btn_load_game.pressed.connect(_on_load_game)
	btn_test_combat.pressed.connect(_on_test_combat)
	btn_settings.pressed.connect(_on_settings)
	btn_quit.pressed.connect(_on_quit)

	btn_load_game.disabled = not FileAccess.file_exists("user://save_0.json")

	AudioManager.play_main_menu_music()

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/class_selection.tscn")

func _on_load_game() -> void:
	if GameManager.load_game(0):
		get_tree().change_scene_to_file("res://scenes/dungeon/dungeon_scene.tscn")

func _on_test_combat() -> void:
	# Lance directement un combat test (Fighter vs 2 Goblins)
	GameManager.party.clear()
	GameManager.current_scenario = {"enemies": ["goblin", "goblin"]}
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")

func _on_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/options_menu.tscn")

func _on_quit() -> void:
	get_tree().quit()
