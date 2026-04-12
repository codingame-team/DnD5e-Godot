## CombatManager.gd
## Logique de résolution de combat D&D 5e (attaque, sorts, déplacement).
## Communique avec TurnManager pour l'ordre des tours.
extends Node

signal attack_resolved(attacker: String, target: String, result: Dictionary)
signal spell_resolved(caster: String, targets: Array, result: Dictionary)
signal combatant_died(name: String, is_hero: bool)
signal movement_updated(combatant: String, new_pos: Vector2i)

# --------------------------------------------------------------------------
# Attaque physique
# --------------------------------------------------------------------------

func resolve_attack(attacker: HeroData, target: MonsterData,
                    advantage: bool = false) -> Dictionary:
	"""Résout une attaque d'arme d'un héros sur un monstre.
	Retourne un dict {hit, roll, total, damage, crit}.
	"""
	if attacker.action_used:
		return {"error": "action déjà utilisée"}

	# Bonus d'attaque : mod STR + maîtrise
	var atk_bonus := attacker.str_mod() + attacker.proficiency_bonus
	var roll      := TurnManager.roll_d20(advantage)
	var crit      := roll == 20
	var total     := roll + atk_bonus
	var hit       := crit or (roll != 1 and total >= target.ac)

	var damage := 0
	var weapon_data := DataManager.get_item("weapon", attacker.weapon_index) if attacker.weapon_index != "" else {}
	var damage_dice: String = weapon_data.get("damage", {}).get("damage_dice", "1d4")

	if hit:
		damage = TurnManager.roll_damage(damage_dice)
		if crit:
			damage += TurnManager.roll_damage(damage_dice)  # dés doublés au critique
		target.take_damage(damage)
		if not target.is_alive():
			combatant_died.emit(target.name, false)

	attacker.action_used = true
	AudioManager.play_sword_hit() if hit else null

	var result := {"hit": hit, "roll": roll, "total": total, "damage": damage,
	               "crit": crit, "target_ac": target.ac}
	attack_resolved.emit(attacker.name, target.name, result)
	return result


func resolve_monster_attack(attacker: MonsterData, target: HeroData) -> Dictionary:
	"""Résout l'attaque d'un monstre sur un héros."""
	var action := attacker.default_action()
	if action.is_empty():
		return {"error": "aucune action"}

	var atk_bonus: int = action.get("attack_bonus", attacker.get_attack_bonus())
	var roll  := TurnManager.roll_d20()
	var total := roll + atk_bonus
	var crit  := roll == 20
	var hit   := crit or (roll != 1 and total >= target.ac)

	var damage := 0
	if hit:
		var dmg_list: Array = action.get("damage", [])
		for dmg_entry in dmg_list:
			damage += TurnManager.roll_damage(dmg_entry.get("dice", "1d6"))
		if crit:
			damage = int(damage * 1.5)
		target.take_damage(damage)
		if not target.is_alive():
			combatant_died.emit(target.name, true)
			AudioManager.play_death()

	var result := {"hit": hit, "roll": roll, "total": total, "damage": damage, "crit": crit}
	attack_resolved.emit(attacker.name, target.name, result)
	return result

# --------------------------------------------------------------------------
# Déplacement sur la grille
# --------------------------------------------------------------------------

func move_hero(hero: HeroData, new_pos: Vector2i, cost: int) -> bool:
	"""Déplace un héros si le mouvement restant le permet."""
	if hero.movement_used + cost > hero.speed:
		return false
	hero.movement_used += cost
	movement_updated.emit(hero.name, new_pos)
	return true

# --------------------------------------------------------------------------
# Sorts (résolution simplifiée)
# --------------------------------------------------------------------------

func resolve_spell(caster: HeroData, spell_index: String,
                   targets: Array) -> Dictionary:
	var spell := DataManager.get_spell(spell_index)
	if spell.is_empty():
		return {"error": "sort introuvable"}
	if caster.action_used:
		return {"error": "action déjà utilisée"}

	var damage_info: Dictionary = spell.get("damage", {})
	var dice_str: String = ""
	if damage_info.has("damage_at_slot_level"):
		var slot_dmg: Dictionary = damage_info["damage_at_slot_level"]
		dice_str = slot_dmg.get("1", slot_dmg.values()[0] if not slot_dmg.is_empty() else "1d6")
	elif damage_info.has("damage_dice"):
		dice_str = damage_info["damage_dice"]

	var results := []
	for target in targets:
		var damage := TurnManager.roll_damage(dice_str) if dice_str != "" else 0
		if target is MonsterData:
			target.take_damage(damage)
			results.append({"target": target.name, "damage": damage})

	caster.action_used = true
	AudioManager.play_spell_cast()

	var result := {"spell": spell.get("name",""), "results": results}
	spell_resolved.emit(caster.name, targets.map(func(t): return t.name), result)
	return result
