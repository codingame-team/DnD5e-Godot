## MonsterData.gd
## Resource typée représentant un monstre D&D 5e.
class_name MonsterData
extends Resource

@export var index: String = "goblin"
@export var name: String = "Goblin"
@export var monster_type: String = "humanoid"
@export var size: String = "Small"
@export var cr: float = 0.25

@export var max_hp: int = 7
@export var hp: int = 7
@export var ac: int = 15
@export var speed: int = 30

@export var str_score: int = 8
@export var dex_score: int = 14
@export var con_score: int = 10
@export var int_score: int = 10
@export var wis_score: int = 8
@export var cha_score: int = 8

@export var xp: int = 50
@export var actions: Array = []   # Array[Dictionary] depuis JSON
@export var traits: Array = []

@export var model_path: String = ""
@export var token_path: String = ""

# --------------------------------------------------------------------------
# Runtime (non exporté)
# --------------------------------------------------------------------------

var position_3d: Vector3 = Vector3.ZERO
var grid_pos: Vector2i = Vector2i.ZERO
var is_active: bool = true

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func ability_modifier(score: int) -> int:
	return (score - 10) / 2

func is_alive() -> bool:
	return hp > 0

func hp_percent() -> float:
	if max_hp <= 0: return 0.0
	return float(hp) / float(max_hp)

func take_damage(amount: int) -> int:
	var actual := mini(amount, hp)
	hp -= actual
	return actual

func get_attack_bonus() -> int:
	return ability_modifier(str_score) + maxi(2, ceili(cr / 2.0))

func default_action() -> Dictionary:
	return actions[0] if not actions.is_empty() else {}

static func from_data(data: Dictionary) -> MonsterData:
	"""Instancie depuis les données brutes de DataManager."""
	var m := MonsterData.new()
	m.index        = data.get("index", "unknown")
	m.name         = data.get("name", "Monstre")
	m.monster_type = data.get("type", "beast")
	m.size         = data.get("size", "Medium")
	m.cr           = float(data.get("cr", 0))
	m.max_hp       = data.get("hp", 4)
	m.hp           = m.max_hp
	m.ac           = data.get("ac", 10)
	m.speed        = data.get("speed", 30)
	m.xp           = data.get("xp", 0)
	var ab: Dictionary = data.get("abilities", {})
	m.str_score = ab.get("str", 10)
	m.dex_score = ab.get("dex", 10)
	m.con_score = ab.get("con", 10)
	m.int_score = ab.get("int", 10)
	m.wis_score = ab.get("wis", 10)
	m.cha_score = ab.get("cha", 10)
	m.actions   = data.get("actions", [])
	m.traits    = data.get("traits", [])
	return m
