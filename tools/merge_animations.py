"""tools/merge_animations.py
=============================================================================
Script Blender pour fusionner plusieurs FBX/GLTF Mixamo en un seul fichier.
Utile pour réduire le nombre d'assets et simplifier le chargement Godot.

USAGE
-----
1. Ouvrir Blender (3.6+ ou 4.x)
2. Menu "Scripting" → coller ce script dans l'éditeur de texte
3. Adapter les variables dans la section CONFIG ci-dessous
4. Cliquer "Run Script"

Le fichier de sortie contiendra le mesh + toutes les animations nommées
(Attack, AttackH, Walk, Death, ...) dans un seul fichier exporté.

FONCTIONNE POUR
---------------
- Goblin (FBX → FBX fusionné)
- Héros (FBX Mixamo → GLTF fusionné, si les fichiers GLTF actuels
  n'ont pas encore d'animations)

NOTE sur Godot
--------------
- FBX fusionné : Godot nommera les clips avec les noms Blender (Action names)
- GLTF fusionné : Godot nommera les clips selon "animations[].name" du GLTF
  → Format GLTF (.glb) recommandé pour les héros (plus compact, natif Godot 4)
=============================================================================
"""

import os

import bpy  # noqa: F401 – disponible dans l'interpréteur Blender

# =============================================================================
# CONFIG — adapter selon le personnage à fusionner
# =============================================================================

# Répertoire contenant les FBX sources
SOURCE_DIR = "/Users/display/GodotProjects/DnD-Tactics/assets/monsters/Goblin"

# Fichier de sortie — GLB recommandé pour Godot 4 :
#   ✓ noms d'animations propres (pas de 'Armature|Walk')
#   ✓ textures intégrées
#   ✓ NLA strips exportées correctement
OUTPUT_FILE = "/Users/display/GodotProjects/DnD-Tactics/assets/monsters/Goblin/Goblin_Merged.glb"

# Animations à importer : {nom_dans_Godot: fichier.fbx}
# Le PREMIER fichier fournit le mesh + rig de référence.
ANIMATIONS = {
    "Attack":  "Standing Melee Attack Downward.fbx",
    "AttackH": "Standing Melee Attack Horizontal.fbx",
    "Walk":    "Dwarf Walk.fbx",
    "Death":   "Dying.fbx",
}

# Pour les héros (FBX Mixamo vers GLTF), remplacer OUTPUT_FILE par .glb et
# décommenter la section EXPORT GLB ci-dessous.

# =============================================================================
# Helpers
# =============================================================================

def clear_scene() -> None:
    """Supprime tous les objets et données sans casser le contexte Blender (Blender 4.x)."""
    # Ne PAS utiliser read_factory_settings : casse le contexte viewport
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=True)
    # Purge les actions (critique : évite que les actions d'un run précédent
    # faussent le snapshot actions_before du prochain run)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    # Purge les données orphelines
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    for arm in list(bpy.data.armatures):
        bpy.data.armatures.remove(arm, do_unlink=True)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat, do_unlink=True)


def find_armature(objects: list) -> "bpy.types.Object | None":
    """Retourne le premier armature dans la liste d'objets sélectionnés."""
    for obj in objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def _get_view3d_context() -> "dict | None":
    """Retourne un dict de surcharge de contexte avec un zone VIEW_3D valide.

    Requis pour bpy.ops.import_scene.fbx dans Blender 4.x.
    """
    win = bpy.context.window
    for area in win.screen.areas:
        if area.type == "VIEW_3D":
            for region in area.regions:
                if region.type == "WINDOW":
                    return {"window": win, "area": area, "region": region}
    return None


def import_fbx(filepath: str) -> list:
    """Importe un FBX et retourne les objets sélectionnés après import."""
    bpy.ops.object.select_all(action="DESELECT")
    ctx = _get_view3d_context()
    fbx_kwargs = dict(
        filepath=filepath,
        ignore_leaf_bones=False,
        automatic_bone_orientation=False,
        use_custom_normals=True,
    )
    if ctx is not None:
        with bpy.context.temp_override(**ctx):
            bpy.ops.import_scene.fbx(**fbx_kwargs)
    else:
        # Dernier recours (peut échouer sur un contexte headless)
        bpy.ops.import_scene.fbx(**fbx_kwargs)
    bpy.context.view_layer.update()
    return list(bpy.context.selected_objects)


def extract_mixamo_action(actions_before: set, semantic_name: str) -> "bpy.types.Action | None":
    """Parmi les actions ajoutées depuis l'import, retourne l'animation réelle.

    Stratégie : sélectionner l'action avec la **plage de frames la plus longue**.
    'Take 001' Mixamo est souvent une pose statique (0–1 frame) tandis que
    l'animation réelle ('mixamo.com' ou autre nom) a des dizaines de frames.
    Cette approche est indépendante du nommage Blender/Mixamo.
    """
    new_actions = [
        a for a in bpy.data.actions
        if a.name not in actions_before
    ]
    if not new_actions:
        return None

    def _frame_count(a: "bpy.types.Action") -> float:
        """Nombre de frames de l'action (0 si aucune f-curve)."""
        if not a.fcurves:
            return 0.0
        return float(a.frame_range[1] - a.frame_range[0])

    # Prendre l'action avec la durée maximale = l'animation réelle
    target = max(new_actions, key=_frame_count)

    duration = _frame_count(target)
    if duration == 0:
        print(f"  ATTENTION : toutes les nouvelles actions ont 0 frame pour '{semantic_name}'.")

    # Supprimer les autres actions créées lors de cet import
    discarded = [a.name for a in new_actions if a is not target]
    for a in new_actions:
        if a is not target:
            bpy.data.actions.remove(a)

    if discarded:
        print(f"  Ignorée(s) : {discarded} — retenue : '{target.name}' ({int(duration)} frames)")
    target.name = semantic_name
    target.use_fake_user = True
    return target


def remove_objects(objects: list) -> None:
    """Supprime une liste d'objets de la scène (conserve les actions dans bpy.data)."""
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)

# =============================================================================
# Main
# =============================================================================

def main() -> None:
    """Point d'entrée : fusionne les animations selon la config et exporte."""
    clear_scene()

    anim_names = list(ANIMATIONS.keys())
    anim_files = list(ANIMATIONS.values())

    # ------------------------------------------------------------------
    # Étape 1 — Import du FBX de base (premier de la liste → fournit le mesh)
    # ------------------------------------------------------------------
    first_path = os.path.join(SOURCE_DIR, anim_files[0])
    print(f"[1/N] Import base mesh : {first_path}")
    actions_before = {a.name for a in bpy.data.actions}
    base_objects = import_fbx(first_path)
    base_arm = find_armature(base_objects)

    if base_arm is None:
        print("ERREUR : aucun armature trouvé dans le premier FBX.")
        return

    # Extraction explicite de 'mixamo.com' parmi les nouvelles actions
    base_action = extract_mixamo_action(actions_before, anim_names[0])
    if base_action is None:
        print(f"  ATTENTION : aucune action trouvée pour '{anim_names[0]}'")
    else:
        print(f"  Action extraite et renommée → '{base_action.name}'")
        if base_arm.animation_data is None:
            base_arm.animation_data_create()
        base_arm.animation_data.action = base_action

    # ------------------------------------------------------------------
    # Étape 2 — Import des animations supplémentaires
    # ------------------------------------------------------------------
    for i in range(1, len(anim_files)):
        path = os.path.join(SOURCE_DIR, anim_files[i])
        print(f"[{i + 1}/N] Import animation '{anim_names[i]}' : {path}")
        actions_before_i = {a.name for a in bpy.data.actions}
        new_objects = import_fbx(path)
        new_arm = find_armature(new_objects)

        if new_arm is None:
            print(f"  ATTENTION : pas d'armature dans {anim_files[i]}, ignoré.")
            remove_objects(new_objects)
            continue

        action = extract_mixamo_action(actions_before_i, anim_names[i])
        if action is None:
            print(f"  ATTENTION : aucune action 'mixamo.com' trouvée dans {anim_files[i]}")
        else:
            print(f"  Action extraite et renommée → '{action.name}'")

        # Suppression des objets importés (action préservée via use_fake_user)
        remove_objects(new_objects)

    # ------------------------------------------------------------------
    # Étape 3 — Restaurer l'action de base sur l'armature principale
    # ------------------------------------------------------------------
    base_action_restored = bpy.data.actions.get(anim_names[0])
    if base_action_restored and base_arm.animation_data:
        base_arm.animation_data.action = base_action_restored

    # ------------------------------------------------------------------
    # Étape 4 — Inscrire toutes les actions dans les NLA strips de l'armature
    # Nécessaire pour que bake_anim_use_all_actions fonctionne correctement
    # ------------------------------------------------------------------
    if base_arm.animation_data is None:
        base_arm.animation_data_create()
    # Placer chaque action dans un NLA track dédié, NON muté
    # (les tracks mutés sont ignorés par l'exporteur GLTF)
    for action in bpy.data.actions:
        if action.use_fake_user and len(action.fcurves) > 0:
            track = base_arm.animation_data.nla_tracks.new()
            track.name = action.name
            track.mute = False
            start = int(action.frame_range[0])
            strip = track.strips.new(action.name, start, action)
            strip.name = action.name
    # Désactiver l'action active : on veut exporter via les NLA strips uniquement
    # (sinon l'action active est exportée en doublon sous un nom générique)
    base_arm.animation_data.action = None
    # ------------------------------------------------------------------
    # Étape 5 — Export
    # ------------------------------------------------------------------
    bpy.ops.object.select_all(action="SELECT")
    ctx = _get_view3d_context()

    ext = os.path.splitext(OUTPUT_FILE)[1].lower()

    if ext in (".glb", ".gltf"):
        # Export GLTF/GLB (recommandé pour les héros)
        export_kwargs = dict(
            filepath=OUTPUT_FILE,
            use_selection=True,
            export_animations=True,
            export_nla_strips=True,
            export_frame_range=False,
            # Ne pas optimiser : évite la suppression de frames identiques
            # qui peut réduire certaines animations à 1 seule frame
            export_optimize_animation_size=False,
        )
        if ctx:
            with bpy.context.temp_override(**ctx):
                bpy.ops.export_scene.gltf(**export_kwargs)
        else:
            bpy.ops.export_scene.gltf(**export_kwargs)
    else:
        # Export FBX (goblin, compatibilité)
        export_kwargs = dict(
            filepath=OUTPUT_FILE,
            use_selection=True,
            bake_anim=True,
            bake_anim_use_all_actions=True,
            bake_anim_force_startend_keying=True,
            add_leaf_bones=False,
            path_mode="COPY",
            embed_textures=False,
            mesh_smooth_type="FACE",
        )
        if ctx:
            with bpy.context.temp_override(**ctx):
                bpy.ops.export_scene.fbx(**export_kwargs)
        else:
            bpy.ops.export_scene.fbx(**export_kwargs)

    print("\n✓ Export terminé :", OUTPUT_FILE)
    print("  Animations incluses :", ", ".join(anim_names))
    print("\nPour Godot 4 :")
    print("  - Placer le fichier fusionné dans assets/monsters/ (ou characters/)")
    print("  - Godot importera automatiquement toutes les animations")
    print("  - Mettre à jour MONSTER_MODELS / CLASS_MODELS dans CombatScene.gd")
    print("  - Pour le goblin : remplacer GOBLIN_ANIM_FILES par le chemin du fichier fusionné")


# =============================================================================
# HÉROS — Configuration alternative (décommenter pour les personnages)
# =============================================================================
# Pour créer un Warrior.glb avec animations Mixamo :
#
# SOURCE_DIR  = "/chemin/vers/fbx_sources/Warrior/"
# OUTPUT_FILE = "/Users/display/GodotProjects/DnD-Tactics/assets/models/characters/Warrior_Merged.glb"
# ANIMATIONS  = {
#     "Idle":   "Idle.fbx",
#     "Walk":   "Walking.fbx",
#     "Attack": "Standing Melee Attack Downward.fbx",
#     "Death":  "Dying.fbx",
# }

main()
main()
