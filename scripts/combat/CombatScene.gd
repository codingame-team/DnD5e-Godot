## CombatScene.gd
## Scene de combat tactique 3D au tour par tour.
extends Node3D

const TILE_SIZE := 2.0
const GRID_COLS := 8
const GRID_ROWS := 8

@onready var grid_root: Node3D              = $GridRoot
@onready var combatant_root: Node3D         = $CombatantRoot
@onready var btn_attack: Button             = $UI/ActionPanel/BtnAttack
@onready var btn_spell: Button              = $UI/ActionPanel/BtnSpell
@onready var btn_move: Button               = $UI/ActionPanel/BtnMove
@onready var btn_end_turn: Button           = $UI/ActionPanel/BtnEndTurn
@onready var log_text: RichTextLabel        = $UI/LogPanel/LogScroll/LogText
@onready var turn_label: Label              = $UI/CurrentTurnLabel
@onready var initiative_list: VBoxContainer = $UI/InitiativePanel/InitiativeList

var combat_manager: CombatManager
var heroes:   Array[HeroData]    = []
var monsters: Array[MonsterData] = []
var _pieces:   Dictionary = {}
var _grid_pos: Dictionary = {}
var _occupied: Dictionary = {}
var _move_highlights: Array = []
var _pending_action: String = ""
var _astar: AStarGrid2D
var _is_animating: bool = false

# --------------------------------------------------------------------------
# Ready
# --------------------------------------------------------------------------

func _ready() -> void:
	combat_manager = CombatManager.new()
	add_child(combat_manager)
	combat_manager.attack_resolved.connect(_on_attack_resolved)
	combat_manager.combatant_died.connect(_on_combatant_died)
	_connect_buttons()
	_build_grid()
	_init_astar()
	_load_combatants()
	_start_combat()
	AudioManager.play_combat_music()

func _connect_buttons() -> void:
	btn_attack.pressed.connect(_on_btn_attack)
	btn_spell.pressed.connect(_on_btn_spell)
	btn_move.pressed.connect(_on_btn_move)
	btn_end_turn.pressed.connect(_end_turn)

func _on_btn_attack() -> void:
	_pending_action = "attack"
	_log("[color=yellow]Choisissez une cible a attaquer.[/color]")

func _on_btn_spell() -> void:
	_pending_action = "spell"
	_log("[color=cyan]Choisissez une cible pour le sort.[/color]")

func _on_btn_move() -> void:
	_pending_action = "move"
	_show_move_range()
	_log("[color=lime]Cliquez sur une case bleue pour vous deplacer.[/color]")

# --------------------------------------------------------------------------
# Grid
# --------------------------------------------------------------------------

func _build_grid() -> void:
	var cx := (GRID_COLS - 1) * TILE_SIZE / 2.0
	var cz := (GRID_ROWS - 1) * TILE_SIZE / 2.0
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var inst := MeshInstance3D.new()
			var floor_mesh := BoxMesh.new()
			floor_mesh.size = Vector3(TILE_SIZE - 0.06, 0.15, TILE_SIZE - 0.06)
			inst.mesh = floor_mesh
			var mat := StandardMaterial3D.new()
			if (row + col) % 2 == 0:
				mat.albedo_color = Color(0.72, 0.68, 0.62)
			else:
				mat.albedo_color = Color(0.60, 0.56, 0.50)
			mat.roughness = 0.9
			inst.set_surface_override_material(0, mat)
			inst.position = Vector3(col * TILE_SIZE - cx, 0.0, row * TILE_SIZE - cz)
			inst.set_meta("grid_pos", Vector2i(col, row))
			grid_root.add_child(inst)

func _init_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, GRID_COLS, GRID_ROWS)
	_astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

# --------------------------------------------------------------------------
# Combatants
# --------------------------------------------------------------------------

func _load_combatants() -> void:
	var source_party: Array = GameManager.party if not GameManager.party.is_empty() \
							  else [{"class_index": "fighter", "name": "Guerrier", "hp": 0}]
	for h_dict in source_party:
		var cls_data := DataManager.get_class_data(h_dict.get("class_index", "fighter"))
		if cls_data.is_empty():
			continue
		var hero := HeroData.from_class_data(cls_data, h_dict.get("name", "Heros"))
		hero.hp = h_dict.get("hp", hero.max_hp) if h_dict.get("hp", 0) > 0 else hero.max_hp
		heroes.append(hero)
	var enemy_list: Array = GameManager.current_scenario.get("enemies", []) \
						 if not GameManager.current_scenario.is_empty() \
						 else ["goblin", "goblin"]
	for i in enemy_list.size():
		var m_data := DataManager.get_monster(enemy_list[i])
		if not m_data.is_empty():
			var monster := MonsterData.from_data(m_data)
			monster.grid_pos = Vector2i(5 + i % 3, 2 + i / 3)
			monsters.append(monster)
	_spawn_pieces()

func _spawn_pieces() -> void:
	var hero_starts := [Vector2i(2, 5), Vector2i(3, 5), Vector2i(2, 6), Vector2i(3, 6)]
	for i in heroes.size():
		var gpos: Vector2i = hero_starts[i % 4]
		_occupied[gpos] = heroes[i].name
		_grid_pos[heroes[i].name] = gpos
		var piece := _create_combatant_node(heroes[i].name, true)
		_pieces[heroes[i].name] = piece
		piece.position = _grid_to_world(gpos)
		combatant_root.add_child(piece)
	for i in monsters.size():
		var gpos := monsters[i].grid_pos
		_occupied[gpos] = monsters[i].name
		_grid_pos[monsters[i].name] = gpos
		var piece := _create_combatant_node(monsters[i].name, false)
		_pieces[monsters[i].name] = piece
		piece.position = _grid_to_world(gpos)
		combatant_root.add_child(piece)

func _create_combatant_node(cname: String, is_hero: bool) -> Node3D:
	var root := Node3D.new()
	root.name = cname
	root.add_child(_build_procedural_figure(is_hero))
	_add_name_label(root, cname, is_hero)
	return root

func _build_procedural_figure(is_hero: bool) -> Node3D:
	var figure := Node3D.new()
	var color := Color(0.3, 0.55, 1.0) if is_hero else Color(0.85, 0.22, 0.18)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.30
	body_mesh.height = 1.0
	body.mesh = body_mesh
	var mat_body := StandardMaterial3D.new()
	mat_body.albedo_color = color
	mat_body.roughness = 0.6
	mat_body.metallic = 0.2 if is_hero else 0.0
	body.set_surface_override_material(0, mat_body)
	body.position.y = 0.65
	figure.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head.mesh = head_mesh
	var mat_head := StandardMaterial3D.new()
	mat_head.albedo_color = color.lightened(0.2)
	head.set_surface_override_material(0, mat_head)
	head.position.y = 1.35
	figure.add_child(head)
	if is_hero:
		var sword := MeshInstance3D.new()
		var sword_mesh := BoxMesh.new()
		sword_mesh.size = Vector3(0.06, 0.7, 0.06)
		sword.mesh = sword_mesh
		var mat_sword := StandardMaterial3D.new()
		mat_sword.albedo_color = Color(0.8, 0.85, 0.9)
		mat_sword.metallic = 0.9
		mat_sword.roughness = 0.1
		sword.set_surface_override_material(0, mat_sword)
		sword.position = Vector3(0.38, 0.9, 0.0)
		figure.add_child(sword)
	else:
		for side in [-1, 1]:
			var horn := MeshInstance3D.new()
			var horn_mesh := CylinderMesh.new()
			horn_mesh.top_radius = 0.0
			horn_mesh.bottom_radius = 0.07
			horn_mesh.height = 0.28
			horn.mesh = horn_mesh
			var mat_horn := StandardMaterial3D.new()
			mat_horn.albedo_color = Color(0.15, 0.1, 0.05)
			horn.set_surface_override_material(0, mat_horn)
			horn.position = Vector3(side * 0.15, 1.58, 0.0)
			horn.rotation_degrees.z = side * -20.0
			figure.add_child(horn)
	return figure

func _add_name_label(parent: Node3D, cname: String, is_hero: bool) -> void:
	var label3d := Label3D.new()
	label3d.text = cname
	label3d.font_size = 28
	label3d.modulate = Color.DODGER_BLUE if is_hero else Color.ORANGE_RED
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label3d.position.y = 1.85
	label3d.no_depth_test = true
	parent.add_child(label3d)

# --------------------------------------------------------------------------
# Pathfinding
# --------------------------------------------------------------------------

func _get_path(from: Vector2i, to: Vector2i, steps_max: int) -> Array[Vector2i]:
	for gpos in _occupied.keys():
		if gpos != from and gpos != to:
			_astar.set_point_solid(gpos, true)
	var raw_path: Array[Vector2i] = _astar.get_id_path(from, to)
	for gpos in _occupied.keys():
		_astar.set_point_solid(gpos, false)
	if raw_path.is_empty():
		return []
	raw_path.remove_at(0)
	if raw_path.size() > steps_max:
		raw_path.resize(steps_max)
	return raw_path

func _show_move_range() -> void:
	_clear_highlights()
	var hero := _get_current_hero()
	if hero == null:
		return
	var from: Vector2i = _grid_pos.get(hero.name, Vector2i(-1, -1))
	var remaining := (hero.speed - hero.movement_used) / 5
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var gpos := Vector2i(col, row)
			if gpos == from or _occupied.has(gpos):
				continue
			var path := _get_path(from, gpos, remaining)
			if not path.is_empty():
				_highlight_tile(gpos, Color(0.2, 0.5, 1.0, 0.55))

func _highlight_tile(gpos: Vector2i, color: Color) -> void:
	var cx := (GRID_COLS - 1) * TILE_SIZE / 2.0
	var cz := (GRID_ROWS - 1) * TILE_SIZE / 2.0
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TILE_SIZE - 0.1, 0.02, TILE_SIZE - 0.1)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.flags_no_depth_test = true
	marker.set_surface_override_material(0, mat)
	marker.position = Vector3(gpos.x * TILE_SIZE - cx, 0.09, gpos.y * TILE_SIZE - cz)
	grid_root.add_child(marker)
	_move_highlights.append(marker)

func _clear_highlights() -> void:
	for h in _move_highlights:
		if is_instance_valid(h):
			h.queue_free()
	_move_highlights.clear()

func _grid_to_world(gpos: Vector2i) -> Vector3:
	var cx := (GRID_COLS - 1) * TILE_SIZE / 2.0
	var cz := (GRID_ROWS - 1) * TILE_SIZE / 2.0
	return Vector3(gpos.x * TILE_SIZE - cx, 0.075, gpos.y * TILE_SIZE - cz)

func _world_to_grid(world_pos: Vector3) -> Vector2i:
	var cx := (GRID_COLS - 1) * TILE_SIZE / 2.0
	var cz := (GRID_ROWS - 1) * TILE_SIZE / 2.0
	var col := int(round((world_pos.x + cx) / TILE_SIZE))
	var row := int(round((world_pos.z + cz) / TILE_SIZE))
	return Vector2i(clamp(col, 0, GRID_COLS - 1), clamp(row, 0, GRID_ROWS - 1))

# --------------------------------------------------------------------------
# Animations (Tween-based)
# --------------------------------------------------------------------------

func _animate_move(piece: Node3D, path: Array[Vector2i]) -> void:
	if path.is_empty() or not is_instance_valid(piece):
		return
	_is_animating = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	for gpos in path:
		var world_pos := _grid_to_world(gpos)
		tween.tween_property(piece, "position", world_pos, 0.16)
	await tween.finished
	_is_animating = false

func _animate_attack(attacker: Node3D, target: Node3D) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	_is_animating = true
	var origin := attacker.position
	var lunge  := origin.lerp(target.position, 0.38)
	var tween  := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(attacker, "position", lunge, 0.12)
	tween.tween_property(attacker, "position", origin, 0.14)
	await tween.finished
	_is_animating = false

func _animate_flash(piece: Node3D, flash_color: Color) -> void:
	if not is_instance_valid(piece):
		return
	_set_figure_color(piece, flash_color)
	await get_tree().create_timer(0.18).timeout
	if is_instance_valid(piece):
		_restore_figure_color(piece)

func _animate_death(piece: Node3D) -> void:
	if not is_instance_valid(piece):
		return
	var tween := create_tween()
	tween.tween_property(piece, "rotation_degrees:z", 85.0, 0.35)
	tween.parallel().tween_property(piece, "position:y", -0.3, 0.35)
	await tween.finished
	if is_instance_valid(piece):
		piece.visible = false

# --------------------------------------------------------------------------
# Figure color helpers
# --------------------------------------------------------------------------

func _set_figure_color(piece: Node3D, color: Color) -> void:
	for child in piece.get_children():
		if child is Node3D:
			for sub in child.get_children():
				if sub is MeshInstance3D:
					var mat: Material = sub.get_surface_override_material(0)
					if mat is StandardMaterial3D:
						(mat as StandardMaterial3D).albedo_color = color

func _restore_figure_color(piece: Node3D) -> void:
	var is_hero := false
	for h in heroes:
		if h.name == piece.name:
			is_hero = true
			break
	_set_figure_color(piece, Color(0.3, 0.55, 1.0) if is_hero else Color(0.85, 0.22, 0.18))

func _update_hp_label(cname: String) -> void:
	var piece: Variant = _pieces.get(cname)
	if piece == null:
		return
	var hp_val := 0
	var hp_max := 0
	for h in heroes:
		if h.name == cname:
			hp_val = h.hp; hp_max = h.max_hp; break
	for m in monsters:
		if m.name == cname:
			hp_val = m.hp; hp_max = m.max_hp; break
	if hp_max <= 0:
		return
	for child in (piece as Node3D).get_children():
		if child is Label3D:
			(child as Label3D).text = "%s\n%d/%d" % [cname, hp_val, hp_max]

func _update_all_hp_labels() -> void:
	for h in heroes:
		_update_hp_label(h.name)
	for m in monsters:
		_update_hp_label(m.name)

# --------------------------------------------------------------------------
# Combat start
# --------------------------------------------------------------------------

func _start_combat() -> void:
	var hero_dicts  := heroes.map(func(h: HeroData): return h.to_dict())
	var enemy_dicts := monsters.map(func(m: MonsterData): return {
		"name": m.name, "abilities": {"dex": m.dex_score}, "speed": m.speed, "hp": m.hp})
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.round_started.connect(_on_round_started)
	TurnManager.start_combat(hero_dicts, enemy_dicts)
	_update_initiative_ui()

func _on_turn_started(combatant: Dictionary) -> void:
	var cname: String = combatant.get("name", "?")
	turn_label.text = "Tour de : %s" % cname
	var is_hero: bool = combatant.get("_is_hero", false)
	_update_action_buttons(is_hero)
	_log("[b]%s[/b] commence son tour." % cname)
	_clear_highlights()
	_pending_action = ""
	for hero in heroes:
		if hero.name == cname:
			hero.reset_turn()
	if not is_hero:
		await get_tree().create_timer(0.6).timeout
		_ai_monster_turn(combatant)

func _on_round_started(round_num: int) -> void:
	_log("[color=gold]-- Round %d --[/color]" % round_num)
	if GameManager.round_number > 10:
		_log("[color=red]Limite de rounds atteinte !")
		GameManager.end_combat(false)

# --------------------------------------------------------------------------
# Monster AI
# --------------------------------------------------------------------------

func _ai_monster_turn(combatant: Dictionary) -> void:
	var cname: String = combatant.get("name", "")
	var monster := _get_monster_by_name(cname)
	if monster == null or not monster.is_alive():
		TurnManager.end_current_turn()
		return
	var alive_heroes: Array = heroes.filter(func(h: HeroData): return h.is_alive())
	if alive_heroes.is_empty():
		TurnManager.end_current_turn()
		return
	var target: HeroData = alive_heroes.reduce(
		func(best: HeroData, h: HeroData): return h if h.hp < best.hp else best)
	var m_pos: Vector2i = _grid_pos.get(cname, Vector2i(-1, -1))
	var h_pos: Vector2i = _grid_pos.get(target.name, Vector2i(-1, -1))
	var steps := monster.speed / 5
	var dest := _best_adjacent(m_pos, h_pos, steps)
	if dest != m_pos:
		var path := _get_path(m_pos, dest, steps)
		if not path.is_empty():
			var final_pos := path[path.size() - 1]
			var m_piece: Variant = _pieces.get(cname)
			_occupied.erase(m_pos)
			_occupied[final_pos] = cname
			_grid_pos[cname] = final_pos
			if m_piece != null:
				await _animate_move(m_piece as Node3D, path)
	var cur_pos: Vector2i = _grid_pos.get(cname, m_pos)
	if _is_adjacent(cur_pos, h_pos):
		var result := combat_manager.resolve_monster_attack(monster, target)
		var m_piece: Variant = _pieces.get(cname)
		var h_piece: Variant = _pieces.get(target.name)
		if m_piece != null and h_piece != null:
			await _animate_attack(m_piece as Node3D, h_piece as Node3D)
		if result.get("hit", false):
			_log("[color=tomato][b]%s frappe %s : %d degats![/b][/color]" % [cname, target.name, result.get("damage", 0)])
			if h_piece != null:
				await _animate_flash(h_piece as Node3D, Color(1.0, 0.15, 0.15))
			_update_hp_label(target.name)
		else:
			_log("%s attaque %s et rate (d20=%d)." % [cname, target.name, result.get("roll", 0)])
	else:
		_log("[color=gray]%s se repositionne.[/color]" % cname)
	TurnManager.end_current_turn()

func _best_adjacent(from: Vector2i, target: Vector2i, max_steps: int) -> Vector2i:
	var neighbors := [
		target + Vector2i(1, 0), target + Vector2i(-1, 0),
		target + Vector2i(0, 1), target + Vector2i(0, -1),
	]
	var best := from
	var best_len := 9999
	for nb in neighbors:
		if not _is_in_grid(nb) or (_occupied.has(nb) and nb != from):
			continue
		var path := _get_path(from, nb, max_steps)
		if not path.is_empty() and path.size() < best_len:
			best = path[path.size() - 1]
			best_len = path.size()
	return best

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var d := (a - b).abs()
	return d.x + d.y == 1

func _is_in_grid(gpos: Vector2i) -> bool:
	return gpos.x >= 0 and gpos.x < GRID_COLS and gpos.y >= 0 and gpos.y < GRID_ROWS

# --------------------------------------------------------------------------
# End turn / victory
# --------------------------------------------------------------------------

func _end_turn() -> void:
	_pending_action = ""
	_clear_highlights()
	TurnManager.end_current_turn()
	_check_victory()

func _check_victory() -> void:
	var alive_m: Array = monsters.filter(func(m: MonsterData): return m.is_alive())
	var alive_h: Array = heroes.filter(func(h: HeroData): return h.is_alive())
	if alive_m.is_empty():
		_log("[color=lime][b]Victoire ! Tous les ennemis sont vaincus.[/b][/color]")
		await get_tree().create_timer(2.0).timeout
		GameManager.end_combat(true)
	elif alive_h.is_empty():
		_log("[color=red][b]Defaite...[/b][/color]")
		await get_tree().create_timer(2.0).timeout
		GameManager.end_combat(false)

# --------------------------------------------------------------------------
# Callbacks
# --------------------------------------------------------------------------

func _on_attack_resolved(_attacker: String, _target: String, _result: Dictionary) -> void:
	_update_all_hp_labels()
	_check_victory()

func _on_combatant_died(cname: String, _is_hero: bool) -> void:
	_log("[color=gray][i]%s est elimine.[/i][/color]" % cname)
	var piece: Variant = _pieces.get(cname)
	if piece != null:
		_animate_death(piece as Node3D)
	if _grid_pos.has(cname):
		_occupied.erase(_grid_pos[cname])

# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _is_animating:
		return
	if not (event is InputEventMouseButton and event.pressed and
			event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _pending_action == "attack":
		_try_attack_at_mouse()
	elif _pending_action == "move":
		_try_move_at_mouse(event.position)

func _try_attack_at_mouse() -> void:
	var hero := _get_current_hero()
	var alive_m: Array = monsters.filter(func(m: MonsterData): return m.is_alive())
	var monster: MonsterData = alive_m[0] if not alive_m.is_empty() else null
	if hero == null or monster == null:
		_pending_action = ""
		return
	var result := combat_manager.resolve_attack(hero, monster)
	if result.has("error"):
		_log("[color=orange]%s[/color]" % result["error"])
	elif result.get("hit", false):
		_log("[color=yellow]%s touche %s : %d degats! (d20=%d)[/color]" % [hero.name, monster.name, result.get("damage", 0), result.get("roll", 0)])
		var h_piece: Variant = _pieces.get(hero.name)
		var m_piece: Variant = _pieces.get(monster.name)
		if h_piece != null and m_piece != null:
			_animate_attack(h_piece as Node3D, m_piece as Node3D)
			_animate_flash(m_piece as Node3D, Color(1.0, 0.3, 0.1))
		_update_hp_label(monster.name)
	else:
		_log("%s rate son attaque (d20=%d)." % [hero.name, result.get("roll", 0)])
	_pending_action = ""
	_clear_highlights()

func _try_move_at_mouse(mouse_pos: Vector2) -> void:
	var hero := _get_current_hero()
	if hero == null:
		_pending_action = ""
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_from := camera.project_ray_origin(mouse_pos)
	var ray_dir  := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		return
	var t := -ray_from.y / ray_dir.y
	var hit_world := ray_from + ray_dir * t
	var target_gpos := _world_to_grid(hit_world)
	if _occupied.has(target_gpos):
		_log("[color=orange]Case occupee.[/color]")
		return
	var from_gpos: Vector2i = _grid_pos.get(hero.name, Vector2i(-1, -1))
	var remaining := (hero.speed - hero.movement_used) / 5
	var path := _get_path(from_gpos, target_gpos, remaining)
	if path.is_empty():
		_log("[color=orange]Hors de portee (%d cases max).[/color]" % remaining)
		_pending_action = ""
		_clear_highlights()
		return
	var final_pos := path[path.size() - 1]
	hero.movement_used += path.size() * 5
	_occupied.erase(from_gpos)
	_occupied[final_pos] = hero.name
	_grid_pos[hero.name] = final_pos
	var piece: Variant = _pieces.get(hero.name)
	if piece != null:
		_animate_move(piece as Node3D, path)
	_log("[color=lime]%s se deplace (%d cases).[/color]" % [hero.name, path.size()])
	_pending_action = ""
	_clear_highlights()

# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------

func _update_action_buttons(is_hero: bool) -> void:
	btn_attack.disabled  = not is_hero
	btn_spell.disabled   = not is_hero
	btn_move.disabled    = not is_hero
	btn_end_turn.visible = is_hero

func _update_initiative_ui() -> void:
	for child in initiative_list.get_children():
		child.queue_free()
	for combatant in TurnManager.initiative_order:
		var lbl := Label.new()
		lbl.text = "%s [%d]" % [combatant.get("name", "?"), combatant.get("_initiative", 0)]
		lbl.add_theme_font_size_override("font_size", 13)
		initiative_list.add_child(lbl)

func _log(msg: String) -> void:
	log_text.append_text(msg + "\n")

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _get_current_hero() -> HeroData:
	var current := TurnManager.get_current_combatant()
	if current.is_empty() or not current.get("_is_hero", false):
		return null
	var cname: String = current.get("name", "")
	for hero in heroes:
		if hero.name == cname:
			return hero
	return null

func _get_monster_by_name(cname: String) -> MonsterData:
	for m in monsters:
		if m.name == cname:
			return m
	return null
