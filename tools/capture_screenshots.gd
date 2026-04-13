extends SceneTree

const TARGETS := [
	{"scene": "res://scenes/main_menu.tscn", "out": "res://assets/screenshots/main_menu.png"},
	{"scene": "res://scenes/ui/class_selection.tscn", "out": "res://assets/screenshots/class_selection.png"},
	{"scene": "res://scenes/dungeon/dungeon_scene.tscn", "out": "res://assets/screenshots/dungeon.png"},
	{"scene": "res://scenes/combat/combat_scene.tscn", "out": "res://assets/screenshots/combat.png"}
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for item in TARGETS:
		await _capture_scene(item["scene"], item["out"])
	quit()

func _capture_scene(scene_path: String, out_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(out_path))
	inst.queue_free()
	await process_frame
