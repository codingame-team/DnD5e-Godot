## DungeonScene.gd
## Donjon procedural - camera ISO / 3eme / 1ere personne. Avatars GLTF. AZERTY.
extends Node3D

const DungeonGen = preload("res://scripts/dungeon/DungeonGenerator.gd")

const TILE := 2.0
const DUNGEON_W := 21
const DUNGEON_H := 21
const DIST_ISO := 32.0
const DIST_THIRD := 8.0
const EYE_HEIGHT := 1.55

# Modeles 3D par classe
const CLASS_MODELS := {
	"fighter": "res://assets/models/characters/Warrior.gltf",
	"paladin": "res://assets/models/characters/Warrior.gltf",
	"barbarian": "res://assets/models/characters/Warrior.gltf",
	"wizard": "res://assets/models/characters/Wizard.gltf",
	"sorcerer": "res://assets/models/characters/Wizard.gltf",
	"rogue": "res://assets/models/characters/Rogue.gltf",
	"ranger": "res://assets/models/characters/Ranger.gltf",
	"monk": "res://assets/models/characters/Monk.gltf",
	"cleric": "res://assets/models/characters/Cleric.gltf",
	"druid": "res://assets/models/characters/Cleric.gltf",
}

enum CamMode {ISO, THIRD, FIRST}

@onready var tile_root: Node3D = $TileRoot
@onready var object_root: Node3D = $ObjectRoot
@onready var hero_root: Node3D = $HeroRoot
@onready var camera: Camera3D = $Camera3D
@onready var party_label: Label = $UI/HUD/PartyLabel
@onready var gold_label: Label = $UI/HUD/GoldLabel
@onready var info_label: Label = $UI/HUD/InfoLabel
@onready var cam_label: Label = $UI/HUD/CamLabel
@onready var btn_combat: Button = $UI/BtnCombat

# Donjon
var _dungeon # DungeonGenerator (untyped pour duck-typing)
var _dw: int = DUNGEON_W
var _dh: int = DUNGEON_H
var _cx: float = 0.0
var _cz: float = 0.0
var _hero_pos: Vector2i
var _hero_yaw: float = 0.0 # direction de marche en degrés (Y)
var _objects: Dictionary = {}

# Matériaux
var _mat_wall: StandardMaterial3D
var _mat_wall_ghost: StandardMaterial3D # version semi-transparente pour occlusion
var _mat_floor: StandardMaterial3D
var _mat_floor2: StandardMaterial3D
var _mat_door: StandardMaterial3D
var _mat_chest: StandardMaterial3D
var _mat_gold: StandardMaterial3D
var _mat_exit: StandardMaterial3D
var _mat_barrel: StandardMaterial3D

# Caméra
var _cam_mode: CamMode = CamMode.ISO
var _cam_yaw: float = 0.0 # orbite horizontal (degrés)
var _cam_zoom: float = 1.0 # multiplicateur de distance
var _cam_drag: bool = false
var _cam_drag_last: Vector2
var _mouse_sensitivity: float = 0.4
var _invert_camera_x: bool = false

# Minimap 2D
var _minimap: Node2D = null

# Menu personnage
var _char_menu: Control = null

# Animation héros
var _hero_anim_player: AnimationPlayer = null
var _is_moving: bool = false # verrou anti-spam pendant tween/anim

# --------------------------------------------------------------------------
# Initialisation
# --------------------------------------------------------------------------

func _settings_manager() -> Node:
	return get_node("/root/SettingsManager")

func _process(_delta: float) -> void:
	# Suit le héros en temps réel pendant tout tween de déplacement
	if _is_moving:
		_update_camera()

func _ready() -> void:
	_settings_manager().load_settings()
	_mouse_sensitivity = _settings_manager().get_setting("mouse_sensitivity")
	_invert_camera_x = _settings_manager().get_setting("invert_camera_x")
	_build_materials()
	_dungeon = DungeonGen.new()
	_dungeon.generate(DUNGEON_W, DUNGEON_H)
	_dw = _dungeon.width
	_dh = _dungeon.height
	_cx = (_dw - 1) * TILE / 2.0
	_cz = (_dh - 1) * TILE / 2.0
	_build_dungeon_mesh()
	_place_interactive_objects()
	_spawn_hero()
	_update_ui()
	btn_combat.pressed.connect(_on_test_combat)
	info_label.text = ""
	_setup_minimap()
	_setup_char_menu()
	# Vue initiale : survol du donjon entier
	_overview_camera()

func _build_materials() -> void:
	_mat_wall = _mat(Color(0.28, 0.24, 0.20), 0.95, 0.1)
	# Version fantome : meme couleur, alpha 0.18, mode transparency activé
	_mat_wall_ghost = _mat(Color(0.28, 0.24, 0.20), 0.95, 0.1)
	_mat_wall_ghost.albedo_color.a = 0.18
	_mat_wall_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_wall_ghost.render_priority = 1 # passe au-dessus des opaques
	_mat_floor = _mat(Color(0.52, 0.46, 0.40), 0.88, 0.0)
	_mat_floor2 = _mat(Color(0.44, 0.38, 0.34), 0.88, 0.0)
	_mat_door = _mat(Color(0.55, 0.35, 0.15), 0.70, 0.0)
	_mat_chest = _mat(Color(0.75, 0.55, 0.10), 0.60, 0.3)
	_mat_gold = _mat(Color(1.00, 0.82, 0.10), 0.20, 0.9)
	_mat_exit = _mat(Color(0.20, 0.80, 0.30), 0.50, 0.0)
	_mat_barrel = _mat(Color(0.45, 0.28, 0.12), 0.80, 0.0)

func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

# Vue initiale : survol du donjon entier depuis le NORD (cote -Z)
func _overview_camera() -> void:
	camera.global_position = Vector3(0.0, DIST_ISO * 1.5, -DIST_ISO * 0.6)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await get_tree().create_timer(2.0).timeout
	_update_camera()

# --------------------------------------------------------------------------
# Grille et objets
# --------------------------------------------------------------------------

func _grid_to_world(gpos: Vector2i) -> Vector3:
	return Vector3(gpos.x * TILE - _cx, 0.0, gpos.y * TILE - _cz)

func _build_dungeon_mesh() -> void:
	# Rendu : dalles sol sur chaque cellule marchable + murs fins sur les bords.
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(TILE, 0.18, TILE)
	for r in _dh:
		for c in _dw:
			var ct: int = _dungeon.get_cell(c, r)
			if ct == DungeonGen.CELL_WALL:
				continue # les murs sont rendus en bandeaux d'arete
			var base := _grid_to_world(Vector2i(c, r))
			# Dalle de sol
			var fi := MeshInstance3D.new()
			fi.mesh = floor_mesh
			if ct == DungeonGen.CELL_EXIT:
				fi.set_surface_override_material(0, _mat_exit)
			elif (r + c) % 2 == 0:
				fi.set_surface_override_material(0, _mat_floor)
			else:
				fi.set_surface_override_material(0, _mat_floor2)
			fi.position = Vector3(base.x, -0.09, base.z) # top du sol a y=0
			tile_root.add_child(fi)
			# Bandeaux de mur sur les 4 aretes adjacentes a un mur
			_add_edge_walls(base, c, r)

# Place un bandeau mur fin sur chaque arete de la cellule (c,r) qui borde une cellule mur.
func _add_edge_walls(base: Vector3, c: int, r: int) -> void:
	var hy: float = 1.2 # centre du mur (sol a y=-0.09, mur de y=-0.09 a y=2.5)
	var th: float = 0.20 # epaisseur du mur
	# Nord
	if _is_wall_cell(c, r - 1):
		_add_wall_strip(Vector3(base.x, hy, base.z - TILE * 0.5), Vector3(TILE, 2.6, th))
	# Sud
	if _is_wall_cell(c, r + 1):
		_add_wall_strip(Vector3(base.x, hy, base.z + TILE * 0.5), Vector3(TILE, 2.6, th))
	# Ouest
	if _is_wall_cell(c - 1, r):
		_add_wall_strip(Vector3(base.x - TILE * 0.5, hy, base.z), Vector3(th, 2.6, TILE))
	# Est
	if _is_wall_cell(c + 1, r):
		_add_wall_strip(Vector3(base.x + TILE * 0.5, hy, base.z), Vector3(th, 2.6, TILE))

func _is_wall_cell(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= _dw or r >= _dh:
		return true
	return _dungeon.get_cell(c, r) == DungeonGen.CELL_WALL

func _add_wall_strip(pos: Vector3, size: Vector3) -> void:
	var wi := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = size
	wi.mesh = wm
	wi.set_surface_override_material(0, _mat_wall)
	wi.position = pos
	tile_root.add_child(wi)
	wi.add_to_group("walls") # groupe pour transparence selective

func _place_interactive_objects() -> void:
	for item in _dungeon.interactables:
		var pos: Vector2i = item["pos"]
		var cell_type: int = item["type"]
		var node := _create_object_node(cell_type, item["data"])
		if node == null:
			continue
		node.position = _grid_to_world(pos)
		object_root.add_child(node)
		_objects[pos] = {"node": node, "data": item["data"], "type": cell_type}

func _create_object_node(cell_type: int, _data: Dictionary) -> Node3D:
	var root := Node3D.new()
	var inst := MeshInstance3D.new()
	match cell_type:
		DungeonGen.CELL_DOOR:
			var m := BoxMesh.new()
			m.size = Vector3(TILE * 0.6, 1.6, 0.15)
			inst.mesh = m
			inst.set_surface_override_material(0, _mat_door)
			inst.position = Vector3(0, 0.7, 0)
		DungeonGen.CELL_CHEST:
			var m := BoxMesh.new()
			m.size = Vector3(0.7, 0.45, 0.5)
			inst.mesh = m
			inst.set_surface_override_material(0, _mat_chest)
			inst.position = Vector3(0, 0.22, 0)
		DungeonGen.CELL_GOLD:
			var m := SphereMesh.new()
			m.radius = 0.14
			m.height = 0.08
			inst.mesh = m
			inst.set_surface_override_material(0, _mat_gold)
			inst.position = Vector3(0, 0.06, 0)
		DungeonGen.CELL_BARREL:
			var m := CylinderMesh.new()
			m.top_radius = 0.22
			m.bottom_radius = 0.22
			m.height = 0.6
			inst.mesh = m
			inst.set_surface_override_material(0, _mat_barrel)
			inst.position = Vector3(0, 0.3, 0)
		_:
			return null
	root.add_child(inst)
	return root

# --------------------------------------------------------------------------
# Héros
# --------------------------------------------------------------------------

func _spawn_hero() -> void:
	_hero_pos = _dungeon.entry_pos
	if _hero_pos.x < 0 or _hero_pos.y < 0:
		_hero_pos = Vector2i(1, 1)
	_initial_facing()
	var root := Node3D.new()
	root.name = "Hero"
	var hero_node: Node3D = _load_hero_model()
	root.add_child(hero_node)
	root.position = _grid_to_world(_hero_pos)
	root.rotation_degrees.y = - _hero_yaw # Ry(-yaw) : yaw=0→sud, yaw=90→ouest, yaw=270→est ✓
	hero_root.add_child(root)
	# Ajustement hauteur differe : AABB des modeles skinnes n'est disponible qu'apres add_child
	call_deferred("_adjust_hero_height")

# Oriente le hero vers le premier couloir ouvert depuis l'entree.
func _initial_facing() -> void:
	# Yaw 0=sud(+Z), 90=ouest(-X), 180=nord(-Z), 270=est(+X)
	var dirs := [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
	var yaws := [0.0, 90.0, 180.0, 270.0]
	for i in dirs.size():
		var check: Vector2i = _hero_pos + dirs[i]
		if _dungeon.is_walkable(check.x, check.y):
			_hero_yaw = yaws[i]
			return

func _adjust_hero_height() -> void:
	var hero := _get_hero()
	if hero == null or hero.get_child_count() == 0:
		return
	var model := hero.get_child(0) as Node3D
	if model == null:
		return
	var aabb := _compute_aabb(model, model.global_transform.affine_inverse())
	if aabb.size.y > 0.01:
		var sf := 1.8 / aabb.size.y
		model.scale = Vector3(sf, sf, sf)
		model.position.y = - aabb.position.y * sf
	# Récupération de l'AnimationPlayer et démarrage idle
	_hero_anim_player = _find_anim_player(model)
	_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand", "stand", "T-Pose"])

## Cherche récursivement un AnimationPlayer dans la sous-arborescence.
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result != null:
			return result
	return null

## Joue la première animation trouvée parmi les noms proposés.
## Essaie "mixamo.com" (nom Mixamo natif) avant le repli sur list[0].
func _play_named_anim(ap: AnimationPlayer, names: Array) -> void:
	if ap == null or not is_instance_valid(ap):
		return
	for anim_name in (names + ["mixamo.com"]):
		if ap.has_animation(anim_name):
			ap.play(anim_name)
			return
	var list := ap.get_animation_list()
	if list.size() > 0:
		ap.play(list[0])

func _load_hero_model() -> Node3D:
	var class_idx := "fighter"
	if not GameManager.party.is_empty():
		class_idx = GameManager.party[0].get("class_index", "fighter")
	var model_path: String = CLASS_MODELS.get(class_idx, CLASS_MODELS["fighter"])
	var packed := load(model_path) as PackedScene
	if packed != null:
		var instance := packed.instantiate() as Node3D
		if instance != null:
			# AnimationPlayer accessible en différé après ajout à la scène
			return instance
	return _make_capsule_hero()

func _compute_aabb(node: Node, ref_inv: Transform3D) -> AABB:
	## Calcule l'AABB dans l'espace local du model root en tenant compte
	## de toute la hiérarchie de transforms (bones, sockets, etc.).
	var result := AABB()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# Transforme l'AABB locale vers l'espace du modèle racine
		var rel := ref_inv * mi.global_transform
		result = rel * mi.get_aabb()
	for child in node.get_children():
		var child_aabb := _compute_aabb(child, ref_inv)
		if result.size == Vector3.ZERO:
			result = child_aabb
		elif child_aabb.size != Vector3.ZERO:
			result = result.merge(child_aabb)
	return result

func _make_capsule_hero() -> Node3D:
	var root := Node3D.new()
	var body_inst := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.26
	body_mesh.height = 1.1
	body_inst.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.30, 0.45, 0.75)
	body_mat.roughness = 0.55
	body_mat.metallic = 0.25
	body_inst.set_surface_override_material(0, body_mat)
	body_inst.position.y = 0.65
	root.add_child(body_inst)
	var head_inst := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_inst.mesh = head_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.85, 0.70, 0.55)
	head_inst.set_surface_override_material(0, head_mat)
	head_inst.position.y = 1.48
	root.add_child(head_inst)
	return root

func _get_hero() -> Node3D:
	return hero_root.get_child(0) if hero_root.get_child_count() > 0 else null

func _hero_world() -> Vector3:
	var h := _get_hero()
	return h.position if h else Vector3.ZERO

# --------------------------------------------------------------------------
# Système de caméra
# --------------------------------------------------------------------------

func _update_camera() -> void:
	var wp := _hero_world()
	var hero := _get_hero()
	# Cacher le heros en vue 1ere personne (evite clipping)
	if hero:
		hero.visible = (_cam_mode != CamMode.FIRST)
	# Le monde reste fixe: evite les effets visuels de demi-tour en 3eme personne.
	tile_root.rotation_degrees.y = 0.0
	object_root.rotation_degrees.y = 0.0
	match _cam_mode:
		CamMode.ISO:
			camera.near = 0.05
			var dist := DIST_ISO * _cam_zoom
			var d45 := dist * 0.70711
			# Caméra au NORD (-Z) du heros pour que Z=avancer soit loin de camera
			var offset := Basis(Vector3.UP, deg_to_rad(_cam_yaw)) * Vector3(0.0, d45, -d45)
			camera.global_position = wp + offset
			camera.look_at(wp + Vector3(0, 0.9, 0), Vector3.UP)
		CamMode.THIRD:
			camera.near = 0.05
			var dist := DIST_THIRD * _cam_zoom
			# Orbite autour du héros : _cam_yaw décale la caméra en azimut
			var view_yaw_3rd := _hero_yaw + _cam_yaw
			var fwd := Vector3(
				- sin(deg_to_rad(view_yaw_3rd)), 0.0,
				cos(deg_to_rad(view_yaw_3rd)))
			var pivot := wp + Vector3(0, 1.1, 0)
			var raw_cam := pivot - fwd * dist + Vector3(0, dist * 0.35, 0)
			camera.global_position = _push_cam_from_wall(pivot, raw_cam)
			camera.look_at(wp + Vector3(0, 0.9, 0), Vector3.UP)
		CamMode.FIRST:
			camera.near = 0.03
			var view_yaw := _hero_yaw + _cam_yaw
			# fwd = direction vers laquelle le heros regarde (yaw 0=+Z=sud)
			var fwd := Vector3(-sin(deg_to_rad(view_yaw)), 0.0, cos(deg_to_rad(view_yaw)))
			var eye_pos := wp + Vector3(0, EYE_HEIGHT, 0) + fwd * 0.35
			camera.global_position = eye_pos
			camera.look_at(eye_pos + fwd, Vector3.UP)
	_update_wall_transparency()

	_update_minimap()

# Rend transparents les murs qui se trouvent entre le heros et la camera.
func _update_wall_transparency() -> void:
	var hero_wp := _hero_world() + Vector3(0, 1.0, 0)
	var cam_wp := camera.global_position
	var to_cam := cam_wp - hero_wp
	var cam_dist := to_cam.length()
	var to_cam_n := to_cam / cam_dist if cam_dist > 0.01 else Vector3.ZERO
	for mi: MeshInstance3D in get_tree().get_nodes_in_group("walls"):
		var to_w := mi.global_position - hero_wp
		var proj := to_w.dot(to_cam_n)
		var perp := (to_w - to_cam_n * proj).length()
		var blocking := proj > 0.2 and proj < cam_dist - 0.3 and perp < TILE * 1.0
		mi.set_surface_override_material(0, _mat_wall_ghost if blocking else _mat_wall)

# Rapproche lineairement cam_pos vers player_pos jusqu'a quitter les murs.
func _push_cam_from_wall(player_pos: Vector3, cam_pos: Vector3) -> Vector3:
	var steps := 12
	for i in steps:
		var t: float = float(i) / float(steps)
		var test: Vector3 = cam_pos.lerp(player_pos, t)
		if not _is_wall_cell(_world_to_grid(test).x, _world_to_grid(test).y):
			return test
	return player_pos

# Convertit une position monde en coordonnees de grille.
func _world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		roundi((world_pos.x + _cx) / TILE),
		roundi((world_pos.z + _cz) / TILE)
	)

# --------------------------------------------------------------------------
# Minimap
# --------------------------------------------------------------------------

func _setup_minimap() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var container := Control.new()
	container.name = "MinimapContainer"
	container.position = Vector2(vp_size.x - 190.0, 10.0)
	container.size = Vector2(180.0, 180.0)
	container.clip_contents = true
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.03, 0.02, 0.80)
	container.add_child(bg)
	_minimap = load("res://scripts/dungeon/MinimapDraw.gd").new()
	_minimap.name = "MinimapDraw"
	_minimap.position = Vector2(90.0, 90.0)
	_minimap.set("dungeon", _dungeon)
	_minimap.set("hero_pos", _hero_pos)
	_minimap.set("hero_yaw", _hero_yaw)
	container.add_child(_minimap)
	$UI.add_child(container)

func _update_minimap() -> void:
	if _minimap == null:
		return
	_minimap.set("hero_pos", _hero_pos)
	_minimap.set("hero_yaw", _hero_yaw)
	# La carte reste toujours orientée nord en haut.
	# Seul le curseur héros (dessiné dans MinimapDraw._draw) tourne via hero_yaw.
	_minimap.rotation = 0.0
	_minimap.queue_redraw()

# --------------------------------------------------------------------------
# Menu personnage
# --------------------------------------------------------------------------

func _setup_char_menu() -> void:
	var script := load("res://scripts/dungeon/CharacterMenu.gd") as Script
	if script == null:
		push_warning("CharacterMenu.gd introuvable")
		return
	_char_menu = script.new() as Control
	_char_menu.name = "CharacterMenu"
	_char_menu.visible = false
	_char_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_char_menu.closed.connect(_on_char_menu_closed)
	# Construire le sous-arbre AVANT add_child afin que @onready se résolve correctement.
	_build_char_menu_ui(_char_menu)
	$UI.add_child(_char_menu)

func _build_char_menu_ui(root: Control) -> void:
	# ── Fond sombre semi-transparent sur toute la fenêtre ──────────────────
	var bg := ColorRect.new()
	bg.name = "BgDim"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.60)
	root.add_child(bg)

	# ── Panneau principal centré ────────────────────────────────────────────
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(620.0, 540.0)
	panel.position = (vp - Vector2(620.0, 540.0)) * 0.5
	root.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.name = "VBox"
	outer_vbox.add_theme_constant_override("separation", 6)
	panel.add_child(outer_vbox)

	# ── TabBar ──────────────────────────────────────────────────────────────
	var tab_bar := TabBar.new()
	tab_bar.name = "TabBar"
	tab_bar.add_tab("Personnage")
	tab_bar.add_tab("Inventaire")
	outer_vbox.add_child(tab_bar)

	# ── Pages ───────────────────────────────────────────────────────────────
	var pages := Control.new()
	pages.name = "Pages"
	pages.custom_minimum_size = Vector2(614.0, 460.0)
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(pages)

	# Page Stats
	var pg_stats := MarginContainer.new()
	pg_stats.name = "Stats"
	pg_stats.set_anchors_preset(Control.PRESET_FULL_RECT)
	pages.add_child(pg_stats)
	var stats_lbl := RichTextLabel.new()
	stats_lbl.name = "StatsLabel"
	stats_lbl.bbcode_enabled = true
	stats_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pg_stats.add_child(stats_lbl)

	# Page Inventaire
	var pg_inv := HBoxContainer.new()
	pg_inv.name = "Inventory"
	pg_inv.set_anchors_preset(Control.PRESET_FULL_RECT)
	pages.add_child(pg_inv)

	# Liste scrollable
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollInv"
	scroll.custom_minimum_size = Vector2(260.0, 440.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pg_inv.add_child(scroll)
	var inv_list := VBoxContainer.new()
	inv_list.name = "InvList"
	inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inv_list)

	# Détail d'item (panneau droit)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "ItemDetail"
	detail_panel.custom_minimum_size = Vector2(300.0, 440.0)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.visible = false
	pg_inv.add_child(detail_panel)
	var detail_vbox := VBoxContainer.new()
	detail_vbox.name = "DetailVBox"
	detail_panel.add_child(detail_vbox)
	var detail_lbl := RichTextLabel.new()
	detail_lbl.name = "DetailLabel"
	detail_lbl.bbcode_enabled = true
	detail_lbl.custom_minimum_size.y = 280
	detail_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_vbox.add_child(detail_lbl)
	var btn_equip := Button.new()
	btn_equip.name = "BtnEquip"
	btn_equip.text = "Équiper"
	detail_vbox.add_child(btn_equip)
	var btn_drop := Button.new()
	btn_drop.name = "BtnDrop"
	btn_drop.text = "Jeter"
	detail_vbox.add_child(btn_drop)

	# ── Bouton Fermer ───────────────────────────────────────────────────────
	var btn_close := Button.new()
	btn_close.name = "BtnClose"
	btn_close.text = "Fermer  [C]"
	outer_vbox.add_child(btn_close)

func _on_char_menu_closed() -> void:
	_update_ui()

func _open_char_menu() -> void:
	if _char_menu == null:
		return
	if GameManager.party.is_empty():
		return
	_char_menu.open(GameManager.party[0])

func _cycle_cam_mode() -> void:
	_cam_mode = ((_cam_mode + 1) % 3) as CamMode
	# En 1ere personne : absorber _cam_yaw dans _hero_yaw pour aligner
	# la direction visuelle (view_yaw) et la direction de deplacement (_hero_yaw).
	if _cam_mode == CamMode.FIRST:
		_hero_yaw = fmod(_hero_yaw + _cam_yaw + 360.0, 360.0)
		_cam_yaw = 0.0
		var first_hero := _get_hero()
		if first_hero:
			first_hero.rotation_degrees.y = - _hero_yaw
	var names := [
		"Vue isometrique  [PgPrec/PgSuiv:zoom]",
		"3eme personne  [PgPrec/PgSuiv:zoom]",
		"1ere personne  [Q/D:tourner]"
	]
	cam_label.text = "[V] " + names[_cam_mode]
	_update_camera()

# --------------------------------------------------------------------------
# Input : caméra (souris) + clavier
# --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Molette classique OU défilement souris/trackpad → zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = maxf(0.3, _cam_zoom - 0.1)
			_update_camera()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = minf(3.0, _cam_zoom + 0.1)
			_update_camera()
			return
		elif (event.button_index == MOUSE_BUTTON_MIDDLE
				or event.button_index == MOUSE_BUTTON_RIGHT):
			_cam_drag = event.pressed
			_cam_drag_last = event.position
	# Geste de défilement (souris sans molette classique, trackpad, IntelliMouse)
	elif event is InputEventPanGesture:
		_cam_zoom = clampf(_cam_zoom + event.delta.y * 0.05, 0.3, 3.0)
		_update_camera()
		return
	# Geste de pincement (trackpad macOS)
	elif event is InputEventMagnifyGesture:
		_cam_zoom = clampf(_cam_zoom / event.factor, 0.3, 3.0)
		_update_camera()
		return
	# Orbite : bouton milieu ou droit (ISO + 3ème personne, pas 1ère)
	if event is InputEventMouseMotion and _cam_drag and _cam_mode != CamMode.FIRST:
		var delta: float = event.relative.x
		var direction_sign := -1.0 if _invert_camera_x else 1.0
		_cam_yaw = fmod(_cam_yaw + delta * _mouse_sensitivity * direction_sign, 360.0)
		_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key_event := event as InputEventKey
	var keycode: Key = key_event.keycode
	# C / I : menu personnage
	if keycode == KEY_C or keycode == KEY_I:
		if _char_menu != null:
			if _char_menu.visible:
				_char_menu.visible = false
			else:
				_open_char_menu()
		return
	# V : changer mode camera
	if keycode == _settings_manager().get_keybind("cam_cycle_mode"):
		_cycle_cam_mode()
		return
	# A / E : orbite clavier (AZERTY : A=touche A, E=touche E)
	# Disponible uniquement en ISO (en THIRD la camera reste de dos au heros)
	if keycode == _settings_manager().get_keybind("cam_rotate_left") and _cam_mode == CamMode.ISO:
		_cam_yaw = fmod(_cam_yaw - 15.0, 360.0)
		_update_camera()
		return
	if keycode == _settings_manager().get_keybind("cam_rotate_right") \
			and _cam_mode == CamMode.ISO:
		_cam_yaw = fmod(_cam_yaw + 15.0, 360.0)
		_update_camera()
		return
	# Zoom clavier : Pg.Prec/Pg.Suiv ou +/- (pour souris sans molette)
	if keycode == _settings_manager().get_keybind("cam_zoom_in") \
			or keycode == KEY_KP_ADD or keycode == KEY_PAGEUP:
		_cam_zoom = maxf(0.25, _cam_zoom - 0.15)
		_update_camera()
		return
	if keycode == _settings_manager().get_keybind("cam_zoom_out") \
			or keycode == KEY_KP_SUBTRACT or keycode == KEY_PAGEDOWN:
		_cam_zoom = minf(3.5, _cam_zoom + 0.15)
		_update_camera()
		return
	# Deplacement AZERTY :
	#   Z/Fleche haut  : avancer (dans la direction du regard)
	#   S/Fleche bas   : reculer
	#   Q/Fleche gauche: rotation -90 deg
	#   D/Fleche droite: rotation +90 deg
	if keycode == _settings_manager().get_keybind("move_forward") or keycode == KEY_UP:
			_try_move_forward(1)
	elif keycode == _settings_manager().get_keybind("move_back") or keycode == KEY_DOWN:
			_try_move_forward(-1)
	elif keycode == _settings_manager().get_keybind("turn_left") or keycode == KEY_LEFT:
			_rotate_hero(-90.0)
	elif keycode == _settings_manager().get_keybind("turn_right") or keycode == KEY_RIGHT:
			_rotate_hero(90.0)
	elif keycode == _settings_manager().get_keybind("jump") or keycode == KEY_SPACE:
		await _jump_hero()
	elif keycode == _settings_manager().get_keybind("roll") or keycode == KEY_R:
		await _roll_hero()

# Avance de 1 case dans la direction du regard (direction=1) ou en arriere (-1).
func _try_move_forward(direction: int) -> void:
	if _is_moving:
		return
	var step: Vector2i = _yaw_to_dir(_hero_yaw) * direction
	var new_pos := _hero_pos + step
	if not _dungeon.is_walkable(new_pos.x, new_pos.y):
		if _dungeon.get_cell(new_pos.x, new_pos.y) == DungeonGen.CELL_DOOR:
			_open_door(new_pos)
		return
	_hero_pos = new_pos
	await _move_hero()
	_check_pickup()
	_check_exit()

# Rotation du heros de +/- 90 degrees (sans deplacement).
func _rotate_hero(degrees: float) -> void:
	if _is_moving:
		return
	_hero_yaw = fmod(_hero_yaw + degrees + 360.0, 360.0)
	var hero := _get_hero()
	if hero:
		hero.rotation_degrees.y = - _hero_yaw
	_update_camera()

## Saute une case (ou passe par-dessus un baril vers la case suivante).
func _jump_hero() -> void:
	if _is_moving:
		return
	var step := _yaw_to_dir(_hero_yaw)
	var next1 := _hero_pos + step
	var next2 := _hero_pos + step * 2
	var barrel_at_next1: bool = _dungeon.get_cell(next1.x, next1.y) == DungeonGen.CELL_BARREL
	# Saut par-dessus un baril : case suivante = baril, case d'après = libre
	var over_barrel: bool = barrel_at_next1 and _dungeon.is_walkable(next2.x, next2.y)
	# Saut sur le baril : baril dans un coin (rien de franchissable derrière) → renverser le baril
	var onto_barrel: bool = barrel_at_next1 and not over_barrel
	var target_pos: Vector2i
	if over_barrel:
		target_pos = next2
	elif onto_barrel:
		target_pos = next1
	elif _dungeon.is_walkable(next1.x, next1.y):
		target_pos = next1
	else:
		# Infranchissable : animation sur place
		_play_named_anim(_hero_anim_player, ["Jump", "jump", "Roll", "roll"])
		await get_tree().create_timer(0.5).timeout
		_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand"])
		return
	_is_moving = true
	# Renverser le baril avant de s'y poser
	if onto_barrel:
		_dungeon.grid[next1.y][next1.x] = DungeonGen.CELL_FLOOR
		if _objects.has(next1):
			_objects[next1]["node"].queue_free()
			_objects.erase(next1)
	_hero_pos = target_pos
	var hero := _get_hero()
	if hero == null:
		_is_moving = false
		return
	hero.rotation_degrees.y = - _hero_yaw
	var world_target := _grid_to_world(target_pos)
	_play_named_anim(_hero_anim_player, ["Jump", "jump", "Roll", "roll"])
	var duration := 0.50 if over_barrel else 0.35
	var tween := create_tween()
	tween.tween_property(hero, "position", world_target, duration).set_trans(Tween.TRANS_SPRING)
	await tween.finished
	_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand"])
	_is_moving = false
	_update_camera()
	_check_pickup()
	_check_exit()

## Esquive latérale (priorité gauche puis droite) avec animation Roll.
func _roll_hero() -> void:
	if _is_moving:
		return
	var left_yaw := fmod(_hero_yaw - 90.0 + 360.0, 360.0)
	var right_yaw := fmod(_hero_yaw + 90.0, 360.0)
	var step := _yaw_to_dir(left_yaw)
	var new_pos := _hero_pos + step
	if not _dungeon.is_walkable(new_pos.x, new_pos.y):
		step = _yaw_to_dir(right_yaw)
		new_pos = _hero_pos + step
	if not _dungeon.is_walkable(new_pos.x, new_pos.y):
		# Pas de place : anime en place
		_play_named_anim(_hero_anim_player, ["Roll", "roll"])
		await get_tree().create_timer(0.6).timeout
		_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand"])
		return
	_is_moving = true
	_hero_pos = new_pos
	var hero := _get_hero()
	if hero == null:
		_is_moving = false
		return
	var world_target := _grid_to_world(new_pos)
	_play_named_anim(_hero_anim_player, ["Roll", "roll"])
	var tween := create_tween()
	tween.tween_property(hero, "position", world_target, 0.30).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand"])
	_is_moving = false
	_update_camera()
	_check_exit()

# Yaw 0=sud(+Z), 90=ouest(-X), 180=nord(-Z), 270=est(+X)
func _yaw_to_dir(yaw: float) -> Vector2i:
	var snapped_dir := int(fmod(yaw + 45.0, 360.0) / 90.0) * 90
	match snapped_dir:
		0: return Vector2i(0, 1) # sud
		90: return Vector2i(-1, 0) # ouest
		180: return Vector2i(0, -1) # nord
		270: return Vector2i(1, 0) # est
	return Vector2i(0, 1)

func _move_hero() -> void:
	var hero := _get_hero()
	if hero == null:
		return
	_is_moving = true
	hero.rotation_degrees.y = - _hero_yaw
	var target := _grid_to_world(_hero_pos)
	# Run est plus dynamique que Walk pour un déplacement case à case
	_play_named_anim(_hero_anim_player, ["Run", "Run_Weapon", "Walk", "walk", "Walking"])
	var tween := create_tween()
	tween.tween_property(hero, "position", target, 0.28).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand", "stand", "T-Pose"])
	_update_camera()
	_is_moving = false

# --------------------------------------------------------------------------
# Interactions
# --------------------------------------------------------------------------

func _open_door(pos: Vector2i) -> void:
	_dungeon.grid[pos.y][pos.x] = DungeonGen.CELL_FLOOR
	if _objects.has(pos):
		var node: Node3D = _objects[pos]["node"]
		var tween := create_tween()
		tween.tween_property(node, "rotation_degrees:y", 90.0, 0.3)
		_objects[pos]["data"]["open"] = true
	info_label.text = "Porte ouverte !"
	await get_tree().create_timer(1.5).timeout
	info_label.text = ""

func _check_pickup() -> void:
	if not _objects.has(_hero_pos):
		return
	var obj: Dictionary = _objects[_hero_pos]
	var cell_type: int = obj["type"]
	var data: Dictionary = obj["data"]
	match cell_type:
		DungeonGen.CELL_GOLD:
			_play_named_anim(_hero_anim_player, ["PickUp", "Pickup", "pickup"])
			var amount: int = data.get("gold", 5)
			GameManager.gold += amount
			info_label.text = "+%d or ! Total : %d" % [amount, GameManager.gold]
			obj["node"].queue_free()
			_objects.erase(_hero_pos)
			_dungeon.grid[_hero_pos.y][_hero_pos.x] = DungeonGen.CELL_FLOOR
			_update_ui()
		DungeonGen.CELL_CHEST:
			_play_named_anim(_hero_anim_player, ["PickUp", "Pickup", "pickup"])
			var loot: String = data.get("loot", "Parchemin")
			var gold: int = data.get("gold", 20)
			GameManager.gold += gold
			info_label.text = "Coffre : %s + %d or !" % [loot, gold]
			obj["node"].queue_free()
			_objects.erase(_hero_pos)
			_dungeon.grid[_hero_pos.y][_hero_pos.x] = DungeonGen.CELL_FLOOR
			_update_ui()
		_: return
	await get_tree().create_timer(2.5).timeout
	_play_named_anim(_hero_anim_player, ["Idle", "idle", "IDLE", "Stand"])
	info_label.text = ""

func _check_exit() -> void:
	if _hero_pos == _dungeon.exit_pos:
		info_label.text = "Vous quittez le donjon !"
		await get_tree().create_timer(1.5).timeout
		_dungeon.generate(DUNGEON_W, DUNGEON_H)
		_dw = _dungeon.width
		_dh = _dungeon.height
		_rebuild()

func _rebuild() -> void:
	for child in tile_root.get_children():
		child.queue_free()
	for child in object_root.get_children():
		child.queue_free()
	for child in hero_root.get_children():
		child.queue_free()
	_objects.clear()
	_cx = (_dw - 1) * TILE / 2.0
	_cz = (_dh - 1) * TILE / 2.0
	_build_dungeon_mesh()
	_place_interactive_objects()
	_spawn_hero()
	info_label.text = "Nouveau niveau !"
	await get_tree().create_timer(1.5).timeout
	info_label.text = ""

# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------

func _update_ui() -> void:
	gold_label.text = "Or : %d" % GameManager.gold
	var heroes := GameManager.party
	if heroes.is_empty():
		party_label.text = "Groupe : (vide)"
		return
	var text := "Groupe :\n"
	for h in heroes:
		text += "• %s — PV %d\n" % [h.get("name", "?"), h.get("hp", 0)]
	party_label.text = text

func _on_test_combat() -> void:
	var encounter := {"index": "dungeon_encounter", "enemies": ["goblin", "goblin"]}
	GameManager.start_combat(encounter)
