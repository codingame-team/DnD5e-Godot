## CharacterMenu.gd
## Menu contextuel de gestion du personnage (touche C ou I).
## Split en deux onglets : Caractéristiques | Inventaire.
## Toute la gestion des items passe par les données HeroData stockées dans GameManager.party[0].
extends Control

signal closed

# --------------------------------------------------------------------------
# Constantes
# --------------------------------------------------------------------------
const EQUIP_COLOR   := Color(0.4, 0.9, 0.4, 1.0)
const EQUIP_TXT     := "Équipé ✓"
const UNEQUIP_TXT   := "Déséquiper"
const DROP_TXT      := "Jeter"

# --------------------------------------------------------------------------
# Nœuds
# --------------------------------------------------------------------------
@onready var _tab_bar: TabBar           = $Panel/VBox/TabBar
@onready var _page_stats: Control       = $Panel/VBox/Pages/Stats
@onready var _page_inv:   Control       = $Panel/VBox/Pages/Inventory
@onready var _stats_text: RichTextLabel = $Panel/VBox/Pages/Stats/StatsLabel
@onready var _inv_list:   VBoxContainer = $Panel/VBox/Pages/Inventory/ScrollInv/InvList
@onready var _btn_close:  Button        = $Panel/VBox/BtnClose
@onready var _item_detail: PanelContainer  = $Panel/VBox/Pages/Inventory/ItemDetail
@onready var _detail_label: RichTextLabel  = $Panel/VBox/Pages/Inventory/ItemDetail/DetailVBox/DetailLabel
@onready var _btn_equip:  Button           = $Panel/VBox/Pages/Inventory/ItemDetail/DetailVBox/BtnEquip
@onready var _btn_drop:   Button           = $Panel/VBox/Pages/Inventory/ItemDetail/DetailVBox/BtnDrop

# --------------------------------------------------------------------------
# État
# --------------------------------------------------------------------------
var _hero: Dictionary = {}
var _selected_item_index: int = -1  # index dans _hero["inventory"] array
var _selected_item: Dictionary = {}

# --------------------------------------------------------------------------
# Initialisation
# --------------------------------------------------------------------------
func _ready() -> void:
	_btn_close.pressed.connect(_close)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_btn_equip.pressed.connect(_on_equip_pressed)
	_btn_drop.pressed.connect(_on_drop_pressed)
	_item_detail.visible = false
	# Touche Escape pour fermer
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE or key == KEY_C or key == KEY_I:
			_close()

func open(hero_dict: Dictionary) -> void:
	_hero = hero_dict
	_refresh_stats()
	_refresh_inventory()
	_tab_bar.current_tab = 0
	_on_tab_changed(0)
	visible = true

func _close() -> void:
	visible = false
	closed.emit()

# --------------------------------------------------------------------------
# Onglet Stats
# --------------------------------------------------------------------------
func _refresh_stats() -> void:
	if not is_instance_valid(_stats_text):
		return
	var h := _hero
	var abilities: Dictionary = h.get("abilities", {})
	var class_name_str: String = h.get("class_index", "?").capitalize()
	var race_str: String = h.get("race", "Humain").capitalize()
	var name_str: String = h.get("name", "Héros")
	var level: int = h.get("level", 1)
	var hp: int = h.get("hp", 0)
	var max_hp: int = h.get("max_hp", 1)
	var ac: int = h.get("ac", 10)
	var speed: int = h.get("speed", 30)
	var pb: int = h.get("proficiency_bonus", 2)

	var txt := "[b]%s[/b]   Niv. %d\n" % [name_str, level]
	txt += "[color=gray]%s — %s[/color]\n\n" % [race_str, class_name_str]
	txt += "[b]PV :[/b] %d / %d   [b]CA :[/b] %d   [b]Vitesse :[/b] %d pi   [b]Bonus de maîtrise :[/b] +%d\n\n" % [hp, max_hp, ac, speed, pb]
	txt += "[b]─── Caractéristiques ───[/b]\n"
	for key in ["str", "dex", "con", "int", "wis", "cha"]:
		var label_map := {"str": "FOR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "SAG", "cha": "CHA"}
		var score: int = abilities.get(key, 10)
		txt += "  [b]%s[/b] %d (%s)\n" % [label_map[key], score, _ability_mod_str(score)]

	# Équipement actuel
	txt += "\n[b]─── Équipement ───[/b]\n"
	var wpn: String = h.get("weapon_index", "")
	var arm: String = h.get("armor_index", "")
	txt += "  Arme    : %s\n" % (wpn if wpn != "" else "Aucune")
	txt += "  Armure  : %s\n" % (arm if arm != "" else "Aucune")
	txt += "  Potions : %d\n" % h.get("potions", 0)

	_stats_text.bbcode_text = txt

# --------------------------------------------------------------------------
# Onglet Inventaire
# --------------------------------------------------------------------------
func _refresh_inventory() -> void:
	if not is_instance_valid(_inv_list):
		return
	# Vider la liste
	for child in _inv_list.get_children():
		child.queue_free()
	await get_tree().process_frame

	var inv: Array = _hero.get("inventory", [])
	if inv.is_empty():
		# Construire un inventaire par défaut depuis weapon/armor actuels
		inv = _build_default_inventory()

	_selected_item_index = -1
	_item_detail.visible = false

	for i in inv.size():
		var item: Dictionary = inv[i]
		if item.is_empty():
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var item_name: String = item.get("name", item.get("index", "?"))
		var equipped: bool = _is_equipped(item)
		lbl.text = ("✓ " if equipped else "  ") + item_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.modulate = EQUIP_COLOR if equipped else Color.WHITE
		var btn := Button.new()
		btn.text = "Sélectionner"
		btn.custom_minimum_size.x = 110
		btn.pressed.connect(_on_item_selected.bind(i, item))
		row.add_child(lbl)
		row.add_child(btn)
		_inv_list.add_child(row)

func _build_default_inventory() -> Array:
	"""Construit un inventaire minimal depuis weapon_index / armor_index actuels."""
	var items: Array = []
	var wpn_idx: String = _hero.get("weapon_index", "")
	if wpn_idx != "":
		var d := DataManager.get_item("weapons", wpn_idx)
		if not d.is_empty():
			items.append(d)
	var arm_idx: String = _hero.get("armor_index", "")
	if arm_idx != "":
		var d := DataManager.get_item("armors", arm_idx)
		if not d.is_empty():
			items.append(d)
	# Potions
	var potions: int = _hero.get("potions", 0)
	for _p in range(potions):
		items.append({"index": "healing-potion", "name": "Potion de Soin", "category": "potions"})
	# Stocker dans hero pour les prochaines ouvertures
	_hero["inventory"] = items
	# Synchroniser dans GameManager.party
	_sync_hero_back()
	return items

func _is_equipped(item: Dictionary) -> bool:
	var idx: String = item.get("index", "")
	var cat: String = item.get("category", "")
	if cat == "weapons":
		return _hero.get("weapon_index", "") == idx
	if cat in ["armors", "armor"]:
		return _hero.get("armor_index", "") == idx
	return false

# --------------------------------------------------------------------------
# Sélection d'un item
# --------------------------------------------------------------------------
func _on_item_selected(inv_idx: int, item: Dictionary) -> void:
	_selected_item_index = inv_idx
	_selected_item = item
	_show_item_detail(item)

func _show_item_detail(item: Dictionary) -> void:
	_item_detail.visible = true
	var cat: String = item.get("category", "")
	var name_str: String = item.get("name", item.get("index", "?"))
	var equipped: bool = _is_equipped(item)

	var txt := "[b]%s[/b]\n" % name_str
	if cat == "weapons":
		var dmg: Dictionary = item.get("damage", {})
		txt += "Type : Arme\n"
		txt += "Dégâts : %s %s\n" % [dmg.get("damage_dice", "?"), dmg.get("damage_type", {}).get("name", "")]
		var rng: String = item.get("weapon_range", "")
		if rng != "":
			txt += "Portée : %s\n" % rng
	elif cat in ["armors", "armor"]:
		var ac_data: Dictionary = item.get("armor_class", {})
		txt += "Type : Armure\n"
		txt += "CA de base : %s\n" % ac_data.get("base", "?")
		var str_min: int = item.get("str_minimum", 0)
		if str_min > 0:
			txt += "FOR minimum : %d\n" % str_min
		if item.get("stealth_disadvantage", "False") == "True":
			txt += "[color=orange]Désavantage en Discrétion[/color]\n"
	elif cat == "potions":
		txt += "Soin : 2d4+2 PV\n"
	elif cat == "magic-items":
		var descs: Array = item.get("desc", [])
		if not descs.is_empty():
			txt += descs[0] + "\n"

	_detail_label.bbcode_text = txt
	if cat == "potions":
		_btn_equip.text = "Utiliser"
	elif equipped:
		_btn_equip.text = UNEQUIP_TXT
	else:
		_btn_equip.text = "Équiper"
	_btn_drop.text = DROP_TXT

# --------------------------------------------------------------------------
# Actions équipement
# --------------------------------------------------------------------------
func _on_equip_pressed() -> void:
	if _selected_item.is_empty():
		return
	var item := _selected_item
	var cat: String = item.get("category", "")
	var idx: String = item.get("index", "")
	var equipped: bool = _is_equipped(item)

	if cat == "potions":
		_use_potion()
		return

	if cat == "weapons":
		if equipped:
			_hero["weapon_index"] = ""
		else:
			_hero["weapon_index"] = idx
	elif cat in ["armors", "armor"]:
		if equipped:
			_hero["armor_index"] = ""
			_hero["ac"] = 10 + _ability_mod(_hero.get("abilities", {}).get("dex", 10))
		else:
			_hero["armor_index"] = idx
			# Calculer la nouvelle CA depuis les données de l'armure
			var ac_raw: Variant = item.get("armor_class", {}).get("base", 10)
			var new_ac: int = int(ac_raw)
			var dex_bonus: Variant = item.get("armor_class", {}).get("dex_bonus", "False")
			if str(dex_bonus) == "True":
				var max_b: Variant = item.get("armor_class", {}).get("max_bonus", "None")
				var dex_mod := _ability_mod(_hero.get("abilities", {}).get("dex", 10))
				if str(max_b) != "None":
					dex_mod = mini(dex_mod, int(max_b))
				new_ac += dex_mod
			_hero["ac"] = new_ac

	_sync_hero_back()
	_refresh_stats()
	_refresh_inventory()
	_show_item_detail(item)

func _use_potion() -> void:
	var potions: int = _hero.get("potions", 0)
	if potions <= 0:
		return
	var heal_amount := 2 + randi_range(1, 4) + randi_range(1, 4)
	var hp: int = _hero.get("hp", 0)
	var max_hp: int = _hero.get("max_hp", 1)
	_hero["hp"] = mini(hp + heal_amount, max_hp)
	_hero["potions"] = potions - 1
	# Retirer la potion de l'inventaire
	var inv: Array = _hero.get("inventory", [])
	for i in inv.size():
		if inv[i].get("category", "") == "potions":
			inv.remove_at(i)
			break
	_hero["inventory"] = inv
	_sync_hero_back()
	_refresh_stats()
	_refresh_inventory()
	_item_detail.visible = false

func _on_drop_pressed() -> void:
	if _selected_item.is_empty():
		return
	var item := _selected_item
	# Déséquiper si équipé
	var cat: String = item.get("category", "")
	if cat == "weapons" and _is_equipped(item):
		_hero["weapon_index"] = ""
	elif cat in ["armors", "armor"] and _is_equipped(item):
		_hero["armor_index"] = ""
		_hero["ac"] = 10 + _ability_mod(_hero.get("abilities", {}).get("dex", 10))
	# Retirer de l'inventaire
	var inv: Array = _hero.get("inventory", [])
	if _selected_item_index >= 0 and _selected_item_index < inv.size():
		inv.remove_at(_selected_item_index)
	_hero["inventory"] = inv
	_selected_item = {}
	_selected_item_index = -1
	_sync_hero_back()
	_refresh_stats()
	_refresh_inventory()
	_item_detail.visible = false

# --------------------------------------------------------------------------
# Synchronisation GameManager
# --------------------------------------------------------------------------
func _sync_hero_back() -> void:
	"""Écrit les modifications de _hero dans GameManager.party[0]."""
	if GameManager.party.is_empty():
		return
	GameManager.party[0] = _hero

# --------------------------------------------------------------------------
# Onglet actif
# --------------------------------------------------------------------------
func _on_tab_changed(tab: int) -> void:
	_page_stats.visible = (tab == 0)
	_page_inv.visible   = (tab == 1)

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
func _ability_mod(score: int) -> int:
	return (score - 10) / 2

func _ability_mod_str(score: int) -> String:
	var m := (score - 10) / 2
	return ("+%d" % m) if m >= 0 else ("%d" % m)
