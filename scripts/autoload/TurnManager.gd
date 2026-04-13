## TurnManager.gd
## Autoload : gestion des tours de combat D&D 5e (initiative, phases, actions).
extends Node

signal turn_started(combatant: Dictionary)
signal turn_ended(combatant: Dictionary)
signal round_started(round_num: int)
signal combat_order_ready(order: Array)

enum TurnPhase {
	INITIATIVE, # lancer d'initiative en début de combat
	HERO_TURN, # tour d'un héros (joueur)
	ENEMY_TURN, # tour d'un monstre (IA)
	BETWEEN, # entre deux tours
}

var current_phase: TurnPhase = TurnPhase.INITIATIVE
var initiative_order: Array[Dictionary] = [] # combinats triés par initiative
var current_index: int = 0
var round_number: int = 0
var _combat_active: bool = false

# Actions disponibles pour le combatant actif
var action_used: bool = false
var bonus_action_used: bool = false
var reaction_used: bool = false
var movement_remaining: int = 0

# --------------------------------------------------------------------------
# Démarrage du combat
# --------------------------------------------------------------------------


func start_combat(heroes: Array, enemies: Array) -> void:
	_combat_active = true
	round_number = 0
	initiative_order.clear()

	for hero in heroes:
		var init_roll := _roll_initiative(hero.get("abilities", {}).get("dex", 10))
		initiative_order.append(hero.merged({"_initiative": init_roll, "_is_hero": true}))

	for enemy in enemies:
		var init_roll := _roll_initiative(enemy.get("abilities", {}).get("dex", 10))
		initiative_order.append(enemy.merged({"_initiative": init_roll, "_is_hero": false}))

	initiative_order.sort_custom(func(a, b): return a["_initiative"] > b["_initiative"])
	combat_order_ready.emit(initiative_order)
	_start_round()


func stop_combat() -> void:
	_combat_active = false
	initiative_order.clear()
	current_index = 0

# --------------------------------------------------------------------------
# Navigation des tours
# --------------------------------------------------------------------------


func _start_round() -> void:
	round_number += 1
	current_index = 0
	GameManager.round_number = round_number
	round_started.emit(round_number)
	_start_current_turn()


func _start_current_turn() -> void:
	if initiative_order.is_empty():
		return
	var combatant := _current_combatant()
	action_used = false
	bonus_action_used = false
	reaction_used = false
	movement_remaining = combatant.get("speed", 30)
	current_phase = TurnPhase.HERO_TURN if combatant.get("_is_hero", false) else TurnPhase.ENEMY_TURN
	turn_started.emit(combatant)


func end_current_turn() -> void:
	if not _combat_active:
		return
	turn_ended.emit(_current_combatant())
	current_index += 1
	# Ignorer les morts
	while current_index < initiative_order.size() and initiative_order[current_index].get("hp", 0) <= 0:
		current_index += 1
	if current_index >= initiative_order.size():
		_start_round()
	else:
		_start_current_turn()


func _current_combatant() -> Dictionary:
	if initiative_order.is_empty() or current_index >= initiative_order.size():
		return {}
	return initiative_order[current_index]


func get_current_combatant() -> Dictionary:
	return _current_combatant()


func is_hero_turn() -> bool:
	return current_phase == TurnPhase.HERO_TURN

# --------------------------------------------------------------------------
# Dés
# --------------------------------------------------------------------------


func _roll_initiative(dex_score: int) -> int:
	var mod := (dex_score - 10) / 2
	return randi_range(1, 20) + mod


func roll_d20(advantage: bool = false, disadvantage: bool = false) -> int:
	var r1 := randi_range(1, 20)
	var r2 := randi_range(1, 20)
	if advantage and not disadvantage:
		return maxi(r1, r2)
	if disadvantage and not advantage:
		return mini(r1, r2)
	return r1


func roll_damage(dice_str: String) -> int:
	"""Résout '2d6+3', '1d8', '1d4-1'."""
	if dice_str.is_empty():
		return 0
	var bonus := 0
	var expr := dice_str.to_lower().replace(" ", "")
	if "+" in expr:
		var parts := expr.split("+", false, 1)
		expr = parts[0]
		bonus = int(parts[1])
	elif "-" in expr and "d" in expr:
		var parts := expr.split("-", false, 1)
		expr = parts[0]
		bonus = - int(parts[1])
	if "d" in expr:
		var parts := expr.split("d")
		var count := int(parts[0]) if parts[0] != "" else 1
		var sides := int(parts[1])
		var total := 0
		for _i in count:
			total += randi_range(1, sides)
		return total + bonus
	return int(expr) + bonus
