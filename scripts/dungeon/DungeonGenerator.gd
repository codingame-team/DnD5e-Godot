## DungeonGenerator.gd
## Générateur de donjon procédural : labyrinthe par recursive backtracking.
## Produit une grille 2D avec murs, couloirs, pièces, portes, coffres, or.
class_name DungeonGenerator
extends RefCounted

const CELL_WALL := 0
const CELL_FLOOR := 1
const CELL_DOOR := 2
const CELL_CHEST := 3
const CELL_GOLD := 4
const CELL_ENTRY := 5
const CELL_EXIT := 6
const CELL_BARREL := 7

var width: int = 21 # doit tre impair
var height: int = 21
var grid: Array = [] # grid[row][col] = type de cellule
var entry_pos: Vector2i = Vector2i(1, 1)
var exit_pos: Vector2i = Vector2i(-1, -1)
var interactables: Array[Dictionary] = [] # [{pos, type, data}]

# --------------------------------------------------------------------------
# Gnration principale
# --------------------------------------------------------------------------

func generate(w: int = 21, h: int = 21, rng_seed: int = -1) -> void:
	width = w | 1 # force odd
	height = h | 1
	if rng_seed >= 0:
		seed(rng_seed)
	_init_grid()
	_carve_maze(1, 1)
	_place_rooms()
	_place_entry_exit()
	_place_objects()

func _init_grid() -> void:
	grid.clear()
	for _r in height:
		var row: Array = []
		for _c in width:
			row.append(CELL_WALL)
		grid.append(row)

# Recursive  creuse les couloirs Backtracking partir de (cx,cy)
func _carve_maze(cx: int, cy: int) -> void:
	grid[cy][cx] = CELL_FLOOR
	var dirs: Array[Vector2i] = [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]
	dirs.shuffle()
	for d: Vector2i in dirs:
		var nx: int = cx + d.x
		var ny: int = cy + d.y
		if nx > 0 and nx < width - 1 and ny > 0 and ny < height - 1:
			if grid[ny][nx] == CELL_WALL:
				grid[cy + d.y / 2][cx + d.x / 2] = CELL_FLOOR
				_carve_maze(nx, ny)

# Cre 3-5 pices rectangulaires (3x3  5x5) dans le labyrinthe
func _place_rooms() -> void:
	var num_rooms := randi_range(3, 6)
	for _i in num_rooms:
		var rw := randi_range(3, 5)
		var rh := randi_range(3, 5)
		var rx := randi_range(1, width - rw - 1)
		var ry := randi_range(1, height - rh - 1)
		for r in rh:
			for c in rw:
				grid[ry + r][rx + c] = CELL_FLOOR

func _place_entry_exit() -> void:
	# Entrée : première case de sol libre (scan depuis le haut-gauche)
	entry_pos = Vector2i(-1, -1)
	for r in height:
		for c in width:
			if grid[r][c] == CELL_FLOOR:
				entry_pos = Vector2i(c, r)
				grid[r][c] = CELL_ENTRY
				break
		if entry_pos.x != -1:
			break
	# Sortie : première case de sol libre depuis le bas-droit
	exit_pos = Vector2i(-1, -1)
	for r in range(height - 1, -1, -1):
		for c in range(width - 1, -1, -1):
			if grid[r][c] == CELL_FLOOR:
				exit_pos = Vector2i(c, r)
				grid[r][c] = CELL_EXIT
				return

# Place portes, coffres, or et tonneaux sur les cases de sol libres
func _place_objects() -> void:
	interactables.clear()
	var floor_cells: Array[Vector2i] = get_floor_cells()
	floor_cells.shuffle()
	var placed := 0
	var targets := {
		CELL_DOOR: randi_range(2, 5),
		CELL_CHEST: randi_range(2, 4),
		CELL_GOLD: randi_range(4, 8),
		CELL_BARREL: randi_range(2, 4),
	}
	var counts: Dictionary = {}
	for cell in floor_cells:
		if placed >= floor_cells.size() / 4:
			break
		# Ne pas bloquer entre/sortie ni leurs voisins immdiats
		if cell.distance_to(entry_pos) < 2.5 or cell.distance_to(exit_pos) < 2.5:
			continue
		for cell_type in targets.keys():
			var max_count: int = targets[cell_type]
			if counts.get(cell_type, 0) < max_count:
				grid[cell.y][cell.x] = cell_type
				var item_data := _generate_item_data(cell_type)
				interactables.append({"pos": cell, "type": cell_type, "data": item_data})
				counts[cell_type] = counts.get(cell_type, 0) + 1
				placed += 1
				break

func _generate_item_data(cell_type: int) -> Dictionary:
	match cell_type:
		CELL_CHEST:
			var loot := ["pe longue", "Arc court", "Dague +1", "Anneau de protection", "Cape d'invisibilit"]
			return {"loot": loot[randi() % loot.size()], "gold": randi_range(10, 50)}
		CELL_GOLD:
			return {"gold": randi_range(5, 25)}
		CELL_DOOR:
			return {"locked": randf() < 0.3, "open": false}
		_:
			return {}

# --------------------------------------------------------------------------
# Accesseurs
# --------------------------------------------------------------------------

func get_cell(col: int, row: int) -> int:
	if row < 0 or row >= height or col < 0 or col >= width:
		return CELL_WALL
	return grid[row][col]

func is_walkable(col: int, row: int) -> bool:
	var c := get_cell(col, row)
	return c != CELL_WALL and c != CELL_BARREL

func get_floor_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for r in height:
		for c in width:
			if grid[r][c] == CELL_FLOOR:
				result.append(Vector2i(c, r))
	return result
