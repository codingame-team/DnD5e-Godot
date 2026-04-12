## DataManager.gd
## Autoload : charge et met en cache les données D&D 5e exportées (JSON).
extends Node

const DATA_BASE := "res://data/"

var _cache: Dictionary = {}  # { "monsters/goblin" : {...} }

# Index pré-chargés au démarrage
var monsters_index: Array = []
var classes_index:  Array = []
var spells_index:   Array = []
var items_index:    Array = []

func _ready() -> void:
	_load_index("monsters")
	_load_index("classes")
	_load_index("spells")
	_load_index("items")

# --------------------------------------------------------------------------
# Chargement d'index
# --------------------------------------------------------------------------

func _load_index(category: String) -> void:
	var path := DATA_BASE + category + "/_index.json"
	var data: Variant = _read_json(path)
	if data == null:
		push_warning("DataManager: index manquant pour '%s'" % category)
		return
	match category:
		"monsters": monsters_index = data
		"classes":  classes_index  = data
		"spells":   spells_index   = data
		"items":    items_index    = data

# --------------------------------------------------------------------------
# API publique
# --------------------------------------------------------------------------

func get_monster(index: String) -> Dictionary:
	return _get_cached("monsters/" + index)

func get_class_data(index: String) -> Dictionary:
	return _get_cached("classes/" + index)

func get_spell(index: String) -> Dictionary:
	return _get_cached("spells/" + index)

func get_item(category: String, index: String) -> Dictionary:
	return _get_cached("items/%s_%s" % [category, index])

func get_monsters_by_cr(cr_min: float, cr_max: float) -> Array:
	return monsters_index.filter(func(m): return m.get("cr", 0.0) >= cr_min and m.get("cr", 0.0) <= cr_max)

func get_spells_for_class(class_index: String, max_level: int = 9) -> Array:
	return spells_index.filter(func(s):
		return class_index in s.get("classes", []) and s.get("level", 0) <= max_level
	)

# --------------------------------------------------------------------------
# Helpers internes
# --------------------------------------------------------------------------

func _get_cached(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var data: Variant = _read_json(DATA_BASE + key + ".json")
	if data == null or not data is Dictionary:
		return {}
	_cache[key] = data
	return data

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var result: Variant = JSON.parse_string(file.get_as_text())
	return result
