## CombatScene.gd
## Scène de combat tactique 3D au tour par tour.
## Grille isométrique, initiative D&D 5e, attaques, sorts.
extends Node3D

const TILE_SIZE  := 2.0
const GRID_COLS  := 8
const GRID_ROWS  := 8

@onready var grid_root: Node3D       = $GridRoot
@onready var combatant_root: Node3D  = $CombatantRoot
@onready var btn_attack: Button      = $UI/ActionPanel/BtnAttack
@onready var btn_spell: Button       = $UI/ActionPanel/BtnSpell
@onready var btn_move: Button        = $UI/ActionPanel/BtnMove
@onready var btn_end_turn: Button    = $UI/ActionPanel/BtnEndTurn
@onready var log_text: RichTextLabel = $UI/LogPanel/LogScroll/LogText
@onready var turn_label: Label       = $UI/CurrentTurnLabel
@onready var initiative_list: VBoxContainer = $UI/InitiativePanel/InitiativeList

var combat_manager: CombatManager
var heroes:   Array[HeroData]    = []
var monsters: Array[MonsterData] = []
var _pieces:  Dictionary         = {}  # name → MeshInstance3D
var _pending_action: String      = ""  # "attack", "move", "spell"

func _ready() -> void:
	combat_manager = CombatManager.new()
	add_child(combat_manager)
	combat_manager.attack_resolved.connect(_on_attack_resolved)
	combat_manager.combatant_died.connect(_on_combatant_died)

	_connect_buttons()
	_build_grid()
	_load_combatants()
	_start_combat()
	AudioManager.play_combat_music()

# --------------------------------------------------------------------------
# Initialisation
# --------------------------------------------------------------------------

func _connect_buttons() -> void:
	btn_attack.pressed.connect(func(): _pending_action = "attack"; _log("[color=yellow]Choisissez une cible.[/color]"))
	btn_spell.pressed.connect(func(): _pending_action = "spell";   _log("[color=cyan]Choisissez une cible pour le sort.[/color]"))
	btn_move.pressed.connect(func(): _pending_action = "move";     _log("[color=lime]Cliquez sur une case pour vous déplacer.[/color]"))
	btn_end_turn.pressed.connect(_end_turn)

func _build_grid() -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(TILE_SIZE - 0.06, 0.15, TILE_SIZE - 0.06)

	for row in GRID_ROWS:
		for col in GRID_COLS:
			var inst := MeshInstance3D.new()
			inst.mesh = floor_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.30, 0.25, 0.22) if (row + col) % 2 == 0 \
			                   else Color(0.26, 0.22, 0.19)
			inst.set_surface_override_material(0, mat)
			inst.position = Vector3(col * TILE_SIZE, 0.0, row * TILE_SIZE)
			inst.set_meta("grid_pos", Vector2i(col, row))
			grid_root.add_child(inst)

func _load_combatants() -> void:
	# Charger les héros depuis GameManager
	for h_dict in GameManager.party:
		var cls_data := DataManager.get_class_data(h_dict.get("class_index", "fighter"))
		var hero := HeroData.from_class_data(cls_data, h_dict.get("name","Héros"))
		hero.hp = h_dict.get("hp", hero.max_hp)
		heroes.append(hero)

	# Charger les monstres depuis l'encounter
	var enemy_list: Array = GameManager.current_scenario.get("enemies", ["goblin", "goblin"])
	for i in enemy_list.size():
		var m_data := DataManager.get_monster(enemy_list[i])
		if not m_data.is_empty():
			var monster := MonsterData.from_data(m_data)
			monster.grid_pos = Vector2i(5 + i % 3, 2 + i / 3)
			monsters.append(monster)

	_spawn_pieces()

func _spawn_pieces() -> void:
	var hero_cols := [2, 2, 3, 3]
	var hero_rows := [5, 6, 5, 6]

	for i in heroes.size():
		var hero := heroes[i]
		hero.speed = 30
		var piece := _create_piece(
			Color.DODGER_BLUE, hero.name[0],
			Vector2i(hero_cols[i % 4], hero_rows[i % 4])
		)
		_pieces[hero.name] = piece
		combatant_root.add_child(piece)

	for i in monsters.size():
		var monster := monsters[i]
		var piece := _create_piece(
			Color.ORANGE_RED, monster.name[0],
			monster.grid_pos
		)
		_pieces[monster.name] = piece
		combatant_root.add_child(piece)

func _create_piece(color: Color, letter: String, grid_pos: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.position = _grid_to_world(grid_pos)

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.2
	body.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	body.set_surface_override_material(0, mat)
	body.position.y = 0.7
	root.add_child(body)

	root.set_meta("grid_pos", grid_pos)
	return root

# --------------------------------------------------------------------------
# Combat
# --------------------------------------------------------------------------

func _start_combat() -> void:
	var hero_dicts  := heroes.map(func(h): return h.to_dict())
	var enemy_dicts := monsters.map(func(m): return {"name": m.name, "abilities": {"dex": m.dex_score}, "speed": m.speed, "hp": m.hp})
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.round_started.connect(_on_round_started)
	TurnManager.start_combat(hero_dicts, enemy_dicts)
	_update_initiative_ui()

func _on_turn_started(combatant: Dictionary) -> void:
	var name: String = combatant.get("name", "?")
	turn_label.text  = "Tour de : %s" % name
	_update_action_buttons(combatant.get("_is_hero", false))
	_log("[b]%s[/b] commence son tour." % name)

	# IA basique pour les monstres
	if not combatant.get("_is_hero", false):
		await get_tree().create_timer(0.8).timeout
		_ai_monster_turn(combatant)

func _on_round_started(round_num: int) -> void:
	_log("[color=gold]═══ Round %d ═══[/color]" % round_num)
	if GameManager.round_number > 10:
		_log("[color=red]Limite de rounds atteinte !")
		GameManager.end_combat(false)

func _ai_monster_turn(combatant: Dictionary) -> void:
	var cname: String = combatant.get("name", "")
	var monster: MonsterData = _get_monster_by_name(cname)
	if monster == null or heroes.is_empty():
		TurnManager.end_current_turn()
		return
	# Cibler le héros vivant le plus faible
	var alive: Array = heroes.filter(func(h: HeroData): return h.is_alive())
	if alive.is_empty():
		TurnManager.end_current_turn()
		return
	var target: HeroData = alive.reduce(
		func(best: HeroData, h: HeroData): return h if h.hp < best.hp else best)
	if target != null and target.is_alive():
		var result: Dictionary = combat_manager.resolve_monster_attack(monster, target)
		if result.get("hit", false):
			_log("[color=red]%s touche %s : %d dégâts ![/color]" % [cname, target.name, result.get("damage",0)])
		else:
			_log("%s attaque %s et rate (roll %d)." % [cname, target.name, result.get("roll",0)])
	TurnManager.end_current_turn()

func _end_turn() -> void:
	_pending_action = ""
	TurnManager.end_current_turn()
	_check_victory()

func _check_victory() -> void:
	var alive_monsters: Array = monsters.filter(func(m: MonsterData): return m.is_alive())
	var alive_heroes: Array   = heroes.filter(func(h: HeroData): return h.is_alive())
	if alive_monsters.is_empty():
		_log("[color=lime][b]Victoire ! Tous les ennemis sont vaincus.[/b][/color]")
		await get_tree().create_timer(2.0).timeout
		GameManager.end_combat(true)
	elif alive_heroes.is_empty():
		_log("[color=red][b]Défaite... Le groupe est anéanti.[/b][/color]")
		await get_tree().create_timer(2.0).timeout
		GameManager.end_combat(false)

# --------------------------------------------------------------------------
# Callbacks
# --------------------------------------------------------------------------

func _on_attack_resolved(_attacker: String, _target: String, _result: Dictionary) -> void:
	_update_piece_colors()
	_check_victory()

func _on_combatant_died(name: String, is_hero: bool) -> void:
	_log("[color=gray]%s est éliminé.[/color]" % name)
	if _pieces.has(name):
		_pieces[name].visible = false

# --------------------------------------------------------------------------
# Gestion des clics (sélection cible)
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pending_action == "attack":
			_try_attack_at_mouse()
		elif _pending_action == "move":
			_try_move_at_mouse()

func _try_attack_at_mouse() -> void:
	if heroes.is_empty() or monsters.is_empty():
		return
	var hero: HeroData = _get_current_hero()
	var alive_m: Array = monsters.filter(func(m: MonsterData): return m.is_alive())
	var monster: MonsterData = alive_m[0] if not alive_m.is_empty() else null
	if hero == null or monster == null:
		return
	var result: Dictionary = combat_manager.resolve_attack(hero, monster)
	if result.has("error"):
		_log("[color=orange]%s[/color]" % result["error"])
	_pending_action = ""

func _try_move_at_mouse() -> void:
	_pending_action = ""
	_log("Déplacement (à implémenter avec pathfinding)")

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
		lbl.text = "%s [%d]" % [combatant.get("name","?"), combatant.get("_initiative",0)]
		lbl.add_theme_font_size_override("font_size", 13)
		initiative_list.add_child(lbl)

func _update_piece_colors() -> void:
	pass  # À enrichir avec des effets de couleur selon PV

func _log(msg: String) -> void:
	log_text.append_text(msg + "\n")

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _grid_to_world(gpos: Vector2i) -> Vector3:
	return Vector3(gpos.x * TILE_SIZE, 0.0, gpos.y * TILE_SIZE)

func _get_current_hero() -> HeroData:
	var alive := heroes.filter(func(h): return h.is_alive())
	return alive[0] if not alive.is_empty() else null

func _get_monster_by_name(name: String) -> MonsterData:
	for m in monsters:
		if m.name == name:
			return m
	return null
