## HeroData.gd
## Resource typée représentant un héros D&D 5e en jeu.
class_name HeroData
extends Resource

@export var class_index: String = "fighter"
@export var name: String = "Héros"
@export var level: int = 1
@export var hit_die: int = 10

# Caractéristiques D&D 5e
@export var str_score: int = 15
@export var dex_score: int = 13
@export var con_score: int = 14
@export var int_score: int = 10
@export var wis_score: int = 12
@export var cha_score: int = 8

# Combat
@export var max_hp: int = 10
@export var hp: int = 10
@export var ac: int = 16
@export var speed: int = 30
@export var proficiency_bonus: int = 2

# Actions D&D 5e
@export var action_used: bool = false
@export var bonus_action_used: bool = false
@export var reaction_used: bool = false
@export var movement_used: int = 0

# Équipement (index des items)
@export var weapon_index: String = ""
@export var armor_index: String = ""

# Portrait / modèle 3D
@export var portrait_path: String = ""
@export var model_path: String = ""

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func ability_modifier(score: int) -> int:
	return (score - 10) / 2

func str_mod() -> int: return ability_modifier(str_score)
func dex_mod() -> int: return ability_modifier(dex_score)
func con_mod() -> int: return ability_modifier(con_score)
func int_mod() -> int: return ability_modifier(int_score)
func wis_mod() -> int: return ability_modifier(wis_score)
func cha_mod() -> int: return ability_modifier(cha_score)

@warning_ignore("shadowed_variable")
func is_alive() -> bool:
	return hp > 0

func hp_percent() -> float:
	if max_hp <= 0: return 0.0
	return float(hp) / float(max_hp)

func reset_turn() -> void:
	action_used = false
	bonus_action_used = false
	reaction_used = false
	movement_used = 0

func take_damage(amount: int) -> int:
	var actual := mini(amount, hp)
	hp -= actual
	return actual

func heal(amount: int) -> int:
	var actual := mini(amount, max_hp - hp)
	hp += actual
	return actual

func to_dict() -> Dictionary:
	return {
		"class_index": class_index, "name": name, "level": level,
		"hit_die": hit_die, "max_hp": max_hp, "hp": hp, "ac": ac,
		"speed": speed, "proficiency_bonus": proficiency_bonus,
		"abilities": {"str": str_score, "dex": dex_score, "con": con_score,
		              "int": int_score, "wis": wis_score, "cha": cha_score},
		"weapon_index": weapon_index, "armor_index": armor_index,
	}

static func from_class_data(class_data: Dictionary, hero_name: String = "", lvl: int = 1) -> HeroData:
	"""Instancie un HeroData depuis les données brutes de DataManager."""
	var h := HeroData.new()
	h.class_index = class_data.get("index", "fighter")
	h.name = hero_name if hero_name != "" else class_data.get("name", "Héros")
	h.level = lvl
	h.hit_die = class_data.get("hit_die", 10)
	# HP de base niveau 1 : max du dé de vie + mod CON
	h.max_hp = h.hit_die + h.con_mod()
	h.hp = h.max_hp
	h.proficiency_bonus = (lvl - 1) / 4 + 2
	return h
