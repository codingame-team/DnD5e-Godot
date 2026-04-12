## DungeonScene.gd
## Scène principale d'exploration du donjon (vue isométrique 3D).
## Génère une grille de tuiles 3D et place le héros.
extends Node3D

const TILE_SIZE   := 2.0   # taille d'une case en unités Godot
const GRID_COLS   := 10
const GRID_ROWS   := 10

@onready var tile_root: Node3D          = $TileRoot
@onready var party_label: Label         = $UI/HUD/PartyLabel
@onready var btn_combat: Button         = $UI/BtnCombat

var _floor_mesh: BoxMesh
var _wall_mesh: BoxMesh

func _ready() -> void:
	_build_floor_mesh()
	_generate_grid()
	_update_party_ui()
	btn_combat.pressed.connect(_on_test_combat)

func _build_floor_mesh() -> void:
	_floor_mesh = BoxMesh.new()
	_floor_mesh.size = Vector3(TILE_SIZE - 0.05, 0.2, TILE_SIZE - 0.05)

	_wall_mesh = BoxMesh.new()
	_wall_mesh.size = Vector3(TILE_SIZE - 0.05, 1.5, TILE_SIZE - 0.05)

func _generate_grid() -> void:
	# Grille simple : bords = murs, intérieur = sol
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var is_wall := (row == 0 or row == GRID_ROWS - 1
			                or col == 0 or col == GRID_COLS - 1)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = _wall_mesh if is_wall else _floor_mesh

			var mat := StandardMaterial3D.new()
			if is_wall:
				mat.albedo_color = Color(0.35, 0.30, 0.28)
			else:
				mat.albedo_color = Color(0.45, 0.40, 0.38) if (row + col) % 2 == 0 \
				                   else Color(0.40, 0.35, 0.33)
			mesh_inst.set_surface_override_material(0, mat)

			var pos := Vector3(col * TILE_SIZE, 0.0, row * TILE_SIZE)
			if is_wall:
				pos.y = 0.65
			mesh_inst.position = pos
			tile_root.add_child(mesh_inst)

	# Centrer la caméra
	$Camera3D.position = Vector3(GRID_COLS * TILE_SIZE / 2.0, 12, GRID_ROWS * TILE_SIZE / 2.0 + 8)

func _update_party_ui() -> void:
	var heroes := GameManager.party
	var text := "Groupe :\n"
	for h in heroes:
		text += "• %s (%s) — PV %d\n" % [h.get("name","?"), h.get("class_index","?"), h.get("hp",0)]
	party_label.text = text

func _on_test_combat() -> void:
	# Lance un combat de test avec des gobelins
	var encounter := {
		"index": "test_encounter",
		"enemies": ["goblin", "goblin", "hobgoblin"],
		"origin": "dungeon_test",
	}
	GameManager.start_combat(encounter)
