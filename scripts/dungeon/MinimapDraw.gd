## MinimapDraw.gd — Rendu 2D de la carte du donjon, centre sur le heros.
## Positionnee au centre du conteneur (hero en local (0,0)).
## En vue 1ere personne : la rotation parente aligne la direction de regard vers le haut.
extends Node2D

const CELL_SIZE := 7

## Couleurs indexees par type de cellule (DungeonGenerator constantes 0-7).
const CELL_COLORS := [
	Color(0.13, 0.11, 0.09), # 0 WALL
	Color(0.48, 0.42, 0.36), # 1 FLOOR
	Color(0.58, 0.38, 0.14), # 2 DOOR
	Color(0.75, 0.55, 0.10), # 3 CHEST
	Color(1.00, 0.82, 0.10), # 4 GOLD
	Color(0.40, 0.75, 0.25), # 5 ENTRY
	Color(0.20, 0.80, 0.30), # 6 EXIT
	Color(0.45, 0.28, 0.12), # 7 BARREL
]

var dungeon = null
var hero_pos: Vector2i = Vector2i.ZERO
var hero_yaw: float = 0.0

func _draw() -> void:
	if dungeon == null:
		return
	var w: int = dungeon.width
	var h: int = dungeon.height
	for r in h:
		for c in w:
			var ct: int = dungeon.get_cell(c, r)
			var col: Color = CELL_COLORS[clampi(ct, 0, CELL_COLORS.size() - 1)]
			var px := float(c - hero_pos.x) * CELL_SIZE
			var py := float(r - hero_pos.y) * CELL_SIZE
			draw_rect(Rect2(px, py, CELL_SIZE - 1, CELL_SIZE - 1), col)
	# Indicateur heros : triangle tournant selon hero_yaw.
	# yaw=0=sud(+row), donc on ajuste rotation = -hero_yaw pour aligner avec la vue.
	var s := float(CELL_SIZE) * 1.1
	var angle := deg_to_rad(-hero_yaw + 180.0)
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	# Triangle de base pointant vers +Y local (nord dans la grille)
	var pts := PackedVector2Array([
		Vector2(0.0, -s * 1.3),
		Vector2(-s * 0.9, s * 0.7),
		Vector2(s * 0.9, s * 0.7),
	])
	# Rotation autour de (0,0)
	var rotated := PackedVector2Array()
	for pt in pts:
		var rx = pt.x * cos_a - pt.y * sin_a
		var ry = pt.x * sin_a + pt.y * cos_a
		rotated.append(Vector2(rx, ry))
	draw_colored_polygon(rotated, Color(0.25, 0.65, 1.0, 1.0))
	rotated.append(rotated[0]) # fermer la polyline
	draw_polyline(rotated, Color(1.0, 1.0, 1.0, 0.85), 1.0)
