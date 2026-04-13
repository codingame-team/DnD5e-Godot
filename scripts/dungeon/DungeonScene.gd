## DungeonScene.gd
## Donjon procedural - camera ISO / 3eme / 1ere personne. Avatars GLTF. AZERTY.
extends Node3D

const DungeonGen = preload("res://scripts/dungeon/DungeonGenerator.gd")

const TILE        := 2.0
const DUNGEON_W   := 21
const DUNGEON_H   := 21
const DIST_ISO    := 32.0
const DIST_THIRD  := 8.0
const EYE_HEIGHT  := 1.55

# Modeles 3D par classe
const CLASS_MODELS := {
	"fighter":   "res://assets/models/characters/Warrior.gltf",
	"paladin":   "res://assets/models/characters/Warrior.gltf",
	"barbarian": "res://assets/models/characters/Warrior.gltf",
	"wizard":    "res://assets/models/characters/Wizard.gltf",
	"sorcerer":  "res://assets/models/characters/Wizard.gltf",
	"rogue":     "res://assets/models/characters/Rogue.gltf",
	"ranger":    "res://assets/models/characters/Ranger.gltf",
	"monk":      "res://assets/models/characters/Monk.gltf",
	"cleric":    "res://assets/models/characters/Cleric.gltf",
	"druid":     "res://assets/models/characters/Cleric.gltf",
}

enum CamMode { ISO, THIRD, FIRST }

@onready var tile_root:    Node3D = $TileRoot
@onready var object_root:  Node3D = $ObjectRoot
@onready var hero_root:    Node3D = $HeroRoot
@onready var camera:       Camera3D = $Camera3D
@onready var party_label:  Label  = $UI/HUD/PartyLabel
@onready var gold_label:   Label  = $UI/HUD/GoldLabel
@onready var info_label:   Label  = $UI/HUD/InfoLabel
@onready var cam_label:    Label  = $UI/HUD/CamLabel
@onready var btn_combat:   Button = $UI/BtnCombat

# Donjon
var _dungeon                        # DungeonGenerator (untyped pour duck-typing)
var _dw:    int = DUNGEON_W
var _dh:    int = DUNGEON_H
var _cx:    float = 0.0
var _cz:    float = 0.0
var _hero_pos:    Vector2i
var _hero_yaw:    float = 0.0      # direction de marche en degrés (Y)
var _objects:     Dictionary = {}

# Matériaux
var _mat_wall:       StandardMaterial3D
var _mat_wall_ghost: StandardMaterial3D  # version semi-transparente pour occlusion
var _mat_floor:  StandardMaterial3D
var _mat_floor2: StandardMaterial3D
var _mat_door:   StandardMaterial3D
var _mat_chest:  StandardMaterial3D
var _mat_gold:   StandardMaterial3D
var _mat_exit:   StandardMaterial3D
var _mat_barrel: StandardMaterial3D

# Caméra
var _cam_mode:   CamMode = CamMode.ISO
var _cam_yaw:    float   = 0.0     # orbite horizontal (degrés)
var _cam_zoom:   float   = 1.0     # multiplicateur de distance
var _cam_drag:   bool    = false
var _cam_drag_last: Vector2
var _mouse_sensitivity: float = 0.4
var _invert_camera_x: bool = false

# --------------------------------------------------------------------------
# Initialisation
# --------------------------------------------------------------------------

func _settings_manager() -> Node:
	return get_node("/root/SettingsManager")

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
	# Vue initiale : survol du donjon entier
	_overview_camera()

func _build_materials() -> void:
	_mat_wall   = _mat(Color(0.28, 0.24, 0.20), 0.95, 0.1)
	# Version fantome : meme couleur, alpha 0.18, mode transparency activé
	_mat_wall_ghost = _mat(Color(0.28, 0.24, 0.20), 0.95, 0.1)
	_mat_wall_ghost.albedo_color.a  = 0.18
	_mat_wall_ghost.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_wall_ghost.render_priority = 1  # passe au-dessus des opaques
	_mat_floor  = _mat(Color(0.52, 0.46, 0.40), 0.88, 0.0)
	_mat_floor2 = _mat(Color(0.44, 0.38, 0.34), 0.88, 0.0)
	_mat_door   = _mat(Color(0.55, 0.35, 0.15), 0.70, 0.0)
	_mat_chest  = _mat(Color(0.75, 0.55, 0.10), 0.60, 0.3)
	_mat_gold   = _mat(Color(1.00, 0.82, 0.10), 0.20, 0.9)
	_mat_exit   = _mat(Color(0.20, 0.80, 0.30), 0.50, 0.0)
	_mat_barrel = _mat(Color(0.45, 0.28, 0.12), 0.80, 0.0)

func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness    = roughness
	m.metallic     = metallic
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
				continue  # les murs sont rendus en bandeaux d'arete
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
			fi.position = Vector3(base.x, -0.09, base.z)  # top du sol a y=0
			tile_root.add_child(fi)
			# Bandeaux de mur sur les 4 aretes adjacentes a un mur
			_add_edge_walls(base, c, r)

# Place un bandeau mur fin sur chaque arete de la cellule (c,r) qui borde une cellule mur.
func _add_edge_walls(base: Vector3, c: int, r: int) -> void:
	var hy: float = 1.2   # centre du mur (sol a y=-0.09, mur de y=-0.09 a y=2.5)
	var th: float = 0.20  # epaisseur du mur
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
	wi.add_to_group("walls")  # groupe pour transparence selective

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
			m.top_radius    = 0.22
			m.bottom_radius = 0.22
			m.height        = 0.6
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
	root.rotation_degrees.y = -_hero_yaw   # Ry(-yaw) : yaw=0→sud, yaw=90→ouest, yaw=270→est ✓
	hero_root.add_child(root)
	# Ajustement hauteur differe : AABB des modeles skinnes n'est disponible qu'apres add_child
	call_deferred("_adjust_hero_height")

# Oriente le hero vers le premier couloir ouvert depuis l'entree.
func _initial_facing() -> void:
	# Yaw 0=sud(+Z), 90=ouest, 180=nord, 270=est
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
	var aabb := _compute_aabb(model)
	if aabb.size.y > 0.01:
		var sf := 1.8 / aabb.size.y
		model.scale = Vector3(sf, sf, sf)
		model.position.y = -aabb.position.y * sf

func _load_hero_model() -> Node3D:
	var class_idx := "fighter"
	if not GameManager.party.is_empty():
		class_idx = GameManager.party[0].get("class_index", "fighter")
	var model_path: String = CLASS_MODELS.get(class_idx, CLASS_MODELS["fighter"])
	var gltf_doc   := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(model_path, gltf_state)
	if err == OK:
		var scene_node: Node = gltf_doc.generate_scene(gltf_state)
		var n3d := Node3D.new()
		n3d.add_child(scene_node)
		# La normalisation de hauteur est faite en differe (_adjust_hero_height)
		# car l'AABB des maillages skinnes n'est disponible qu'apres ajout a la scene.
		return n3d
	return _make_capsule_hero()

func _compute_aabb(node: Node) -> AABB:
	var result := AABB()
	if node is MeshInstance3D:
		result = (node as MeshInstance3D).get_aabb()
	for child in node.get_children():
		var child_aabb := _compute_aabb(child)
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
	body_mat.roughness    = 0.55
	body_mat.metallic     = 0.25
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
	match _cam_mode:
		CamMode.ISO:
			camera.near = 0.05
			var dist := DIST_ISO * _cam_zoom
			var d45  := dist * 0.70711
			# Caméra au NORD (-Z) du heros pour que Z=avancer soit loin de camera
			var offset := Basis(Vector3.UP, deg_to_rad(_cam_yaw)) * Vector3(0.0, d45, -d45)
			camera.global_position = wp + offset
			camera.look_at(wp + Vector3(0, 0.9, 0), Vector3.UP)
		CamMode.THIRD:
			camera.near = 0.05
			var dist      := DIST_THIRD * _cam_zoom
			var total_yaw := _cam_yaw + _hero_yaw
			# Offset (0, d, -d) = nord du heros quand total_yaw=0 (hero face sud)
			var offset := Basis(Vector3.UP, deg_to_rad(total_yaw)) \
				* Vector3(0.0, dist * 0.35, -dist)
			var pivot      := wp + Vector3(0, 1.1, 0)
			var raw_cam    := pivot + offset
			camera.global_position = _push_cam_from_wall(pivot, raw_cam)
			camera.look_at(wp + Vector3(0, 0.9, 0), Vector3.UP)
		CamMode.FIRST:
			camera.near = 0.03
			var view_yaw := _hero_yaw + _cam_yaw
			# fwd = direction vers laquelle le heros regarde (yaw 0=+Z=sud)
			var fwd      := Vector3(-sin(deg_to_rad(view_yaw)), 0.0, cos(deg_to_rad(view_yaw)))
			var eye_pos  := wp + Vector3(0, EYE_HEIGHT, 0) + fwd * 0.35
			camera.global_position = eye_pos
			camera.look_at(eye_pos + fwd, Vector3.UP)
	_update_wall_transparency()

# Rend transparents les murs qui se trouvent entre le heros et la camera.
func _update_wall_transparency() -> void:
	var hero_wp  := _hero_world() + Vector3(0, 1.0, 0)
	var cam_wp   := camera.global_position
	var to_cam   := cam_wp - hero_wp
	var cam_dist := to_cam.length()
	var to_cam_n := to_cam / cam_dist if cam_dist > 0.01 else Vector3.ZERO
	for mi: MeshInstance3D in get_tree().get_nodes_in_group("walls"):
		var to_w   := mi.global_position - hero_wp
		var proj   := to_w.dot(to_cam_n)
		var perp   := (to_w - to_cam_n * proj).length()
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

func _cycle_cam_mode() -> void:
	_cam_mode = ((_cam_mode + 1) % 3) as CamMode
	var names := [
		"Vue isometrique  [+/-:zoom]",
		"3eme personne  [+/-:zoom]",
		"1ere personne  [Q/D:tourner]"
	]
	cam_label.text = "[V] " + names[_cam_mode]
	_update_camera()

# --------------------------------------------------------------------------
# Input : caméra (souris) + clavier
# --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Molette : zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = maxf(0.3, _cam_zoom - 0.1)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = minf(3.0, _cam_zoom + 0.1)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_drag = event.pressed
			_cam_drag_last = event.position
	# Orbite : glisser bouton milieu (ISO + 3ème personne uniquement)
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
	# V : changer mode camera
	if keycode == _settings_manager().get_keybind("cam_cycle_mode"):
		_cycle_cam_mode()
		return
	# A / E : orbite clavier (AZERTY : A=touche A, E=touche E)
	# Disponible uniquement en ISO et 3eme personne
	if keycode == _settings_manager().get_keybind("cam_rotate_left") and _cam_mode != CamMode.FIRST:
		_cam_yaw = fmod(_cam_yaw - 15.0, 360.0)
		_update_camera()
		return
	if keycode == _settings_manager().get_keybind("cam_rotate_right") \
			and _cam_mode != CamMode.FIRST:
		_cam_yaw = fmod(_cam_yaw + 15.0, 360.0)
		_update_camera()
		return
	# Zoom clavier : + / - (pour ceux sans molette)
	if keycode == _settings_manager().get_keybind("cam_zoom_in") or keycode == KEY_KP_ADD:
		_cam_zoom = maxf(0.25, _cam_zoom - 0.15)
		_update_camera()
		return
	if keycode == _settings_manager().get_keybind("cam_zoom_out") or keycode == KEY_KP_SUBTRACT:
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

# Avance de 1 case dans la direction du regard (direction=1) ou en arriere (-1).
func _try_move_forward(direction: int) -> void:
	# _yaw_to_dir pointe vers la visual "face" du modele GLTF (+Z = avant modele).
	# On neglige la convention Godot (-Z) et on utilise la direction telle quelle.
	var step: Vector2i = _yaw_to_dir(_hero_yaw) * direction
	var new_pos := _hero_pos + step
	if not _dungeon.is_walkable(new_pos.x, new_pos.y):
		if _dungeon.get_cell(new_pos.x, new_pos.y) == DungeonGen.CELL_DOOR:
			_open_door(new_pos)
		return
	_hero_pos = new_pos
	_move_hero()
	_check_pickup()
	_check_exit()

# Rotation du heros de +/- 90 degrees (sans deplacement).
func _rotate_hero(degrees: float) -> void:
	_hero_yaw = fmod(_hero_yaw + degrees + 360.0, 360.0)
	# En vue 3eme personne : compenser cam_yaw pour que la camera reste fixe en espace monde
	# (le heros tourne a l'ecran sans que la camera orbite).
	# En ISO et 1ere personne : ne pas toucher cam_yaw (evite la rotation de la carte).
	if _cam_mode == CamMode.THIRD:
		_cam_yaw = fmod(_cam_yaw - degrees + 360.0, 360.0)
	var hero := _get_hero()
	if hero:
		hero.rotation_degrees.y = -_hero_yaw
	_update_camera()

# Yaw 0=sud(+Z), 90=ouest(-X), 180=nord(-Z), 270=est(+X)
func _yaw_to_dir(yaw: float) -> Vector2i:
	var snapped_dir := int(fmod(yaw + 45.0, 360.0) / 90.0) * 90
	match snapped_dir:
		0:   return Vector2i(0,  1)   # sud
		90:  return Vector2i(-1, 0)   # ouest
		180: return Vector2i(0, -1)   # nord
		270: return Vector2i( 1, 0)   # est
	return Vector2i(0, 1)

func _move_hero() -> void:
	var hero := _get_hero()
	if hero == null:
		return
	hero.rotation_degrees.y = -_hero_yaw
	var target := _grid_to_world(_hero_pos)
	var tween  := create_tween()
	tween.tween_property(hero, "position", target, 0.14).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	_update_camera()

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
	var cell_type: int   = obj["type"]
	var data: Dictionary = obj["data"]
	match cell_type:
		DungeonGen.CELL_GOLD:
			var amount: int = data.get("gold", 5)
			GameManager.gold += amount
			info_label.text = "+%d or ! Total : %d" % [amount, GameManager.gold]
			obj["node"].queue_free()
			_objects.erase(_hero_pos)
			_dungeon.grid[_hero_pos.y][_hero_pos.x] = DungeonGen.CELL_FLOOR
			_update_ui()
		DungeonGen.CELL_CHEST:
			var loot: String = data.get("loot", "Parchemin")
			var gold: int    = data.get("gold", 20)
			GameManager.gold += gold
			info_label.text = "Coffre : %s + %d or !" % [loot, gold]
			obj["node"].queue_free()
			_objects.erase(_hero_pos)
			_dungeon.grid[_hero_pos.y][_hero_pos.x] = DungeonGen.CELL_FLOOR
			_update_ui()
		_: return
	await get_tree().create_timer(2.5).timeout
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
		text += "• %s — PV %d\n" % [h.get("name","?"), h.get("hp",0)]
	party_label.text = text

func _on_test_combat() -> void:
	var encounter := {"index": "dungeon_encounter", "enemies": ["goblin", "goblin"]}
	GameManager.start_combat(encounter)
