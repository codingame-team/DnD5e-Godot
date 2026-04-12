## ClassSelection.gd
## Sélection de la classe de héros au démarrage d'une partie.
extends Control

const CLASS_COLORS := {
	"barbarian": Color(0.78, 0.20, 0.20),
	"bard":      Color(0.71, 0.47, 0.78),
	"cleric":    Color(0.86, 0.86, 0.39),
	"druid":     Color(0.31, 0.63, 0.24),
	"fighter":   Color(0.39, 0.51, 0.78),
	"monk":      Color(0.94, 0.71, 0.16),
	"paladin":   Color(0.86, 0.82, 0.51),
	"ranger":    Color(0.31, 0.71, 0.31),
	"rogue":     Color(0.39, 0.39, 0.51),
	"sorcerer":  Color(0.78, 0.31, 0.78),
	"warlock":   Color(0.47, 0.24, 0.63),
	"wizard":    Color(0.31, 0.63, 0.86),
}

@onready var class_grid: GridContainer = $ClassGrid
@onready var btn_start: Button         = $BtnStart

var selected_class: String = ""

func _ready() -> void:
	_build_class_buttons()
	btn_start.pressed.connect(_on_start)
	btn_start.disabled = true

func _build_class_buttons() -> void:
	var classes: Array = DataManager.classes_index
	# Fallback si les données ne sont pas encore exportées
	if classes.is_empty():
		classes = [
			{"index": "fighter", "name": "Guerrier"},
			{"index": "wizard",  "name": "Magicien"},
			{"index": "cleric",  "name": "Clerc"},
			{"index": "rogue",   "name": "Roublard"},
			{"index": "ranger",  "name": "Rôdeur"},
			{"index": "paladin", "name": "Paladin"},
			{"index": "barbarian","name": "Barbare"},
			{"index": "bard",    "name": "Barde"},
			{"index": "druid",   "name": "Druide"},
			{"index": "monk",    "name": "Moine"},
			{"index": "sorcerer","name": "Ensorceleur"},
			{"index": "warlock", "name": "Occultiste"},
		]

	for cls_data in classes:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 90)
		btn.text = cls_data.get("name", cls_data.get("index", "?"))
		var idx: String = cls_data.get("index", "")
		if CLASS_COLORS.has(idx):
			btn.add_theme_color_override("font_color", CLASS_COLORS[idx])
		btn.pressed.connect(_on_class_selected.bind(idx, btn))
		class_grid.add_child(btn)

func _on_class_selected(class_index: String, pressed_btn: Button) -> void:
	selected_class = class_index
	btn_start.disabled = false
	# Mettre en évidence le bouton sélectionné
	for child in class_grid.get_children():
		if child is Button:
			child.button_pressed = (child == pressed_btn)

func _on_start() -> void:
	if selected_class.is_empty():
		return
	var class_data := DataManager.get_class(selected_class)
	var hero       := HeroData.from_class_data(class_data, "", 1)
	GameManager.party.clear()
	GameManager.add_hero(hero.to_dict())
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon_scene.tscn")
