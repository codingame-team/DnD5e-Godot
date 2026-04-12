## GameManager.gd
## Autoload principal : état global de la partie (phase, héros actif, scène courante).
extends Node

signal game_state_changed(new_state: String)
signal hero_died(hero_data: Dictionary)
signal combat_started(encounter_data: Dictionary)
signal combat_ended(victory: bool)

enum GameState {
	MAIN_MENU,
	WORLD_MAP,
	DUNGEON,
	COMBAT,
	INVENTORY,
	DIALOG,
	GAME_OVER,
}

var current_state: GameState = GameState.MAIN_MENU
var party: Array[Dictionary] = []          # liste des héros du joueur
var current_scenario: Dictionary = {}
var gold: int = 0
var round_number: int = 0

# --------------------------------------------------------------------------
# Gestion des scènes
# --------------------------------------------------------------------------

func change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func start_combat(encounter_data: Dictionary) -> void:
	current_scenario = encounter_data
	current_state = GameState.COMBAT
	game_state_changed.emit("COMBAT")
	change_scene("res://scenes/combat/combat_scene.tscn")

func end_combat(victory: bool) -> void:
	combat_ended.emit(victory)
	current_state = GameState.DUNGEON
	game_state_changed.emit("DUNGEON")

# --------------------------------------------------------------------------
# Gestion du groupe
# --------------------------------------------------------------------------

func add_hero(hero_data: Dictionary) -> void:
	party.append(hero_data)

func get_alive_heroes() -> Array[Dictionary]:
	return party.filter(func(h): return h.get("hp", 0) > 0)

func is_party_wiped() -> bool:
	return get_alive_heroes().is_empty()

# --------------------------------------------------------------------------
# Sauvegarde / chargement (stub)
# --------------------------------------------------------------------------

func save_game(slot: int = 0) -> void:
	var save_data := {
		"party": party,
		"gold": gold,
		"round": round_number,
		"scenario": current_scenario.get("index", ""),
	}
	var file := FileAccess.open("user://save_%d.json" % slot, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))

func load_game(slot: int = 0) -> bool:
	var path := "user://save_%d.json" % slot
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var result := JSON.parse_string(file.get_as_text())
	if result == null:
		return false
	party  = result.get("party", [])
	gold   = result.get("gold", 0)
	round_number = result.get("round", 0)
	return true
