# Architecture DnD5e Godot

## Vue d'ensemble

Le projet suit une separation scene/script/donnees:

- `scenes/` : graphes de scene Godot (UI, dungeon, combat)
- `scripts/` : logique runtime (autoloads, gameplay, UI)
- `data/` : donnees D&D 5e exportees (classes, monstres, objets)
- `assets/` : audio + modeles 3D + captures
- `tools/` : scripts utilitaires d'export/maintenance

## Arborescence principale

- `project.godot` : config moteur + autoloads
- `scenes/main_menu.tscn` : entree de l'application
- `scenes/ui/class_selection.tscn` : selection de classe du hero
- `scenes/ui/options_menu.tscn` : preferences (audio/camera/commandes)
- `scenes/dungeon/dungeon_scene.tscn` : exploration donjon procedural
- `scenes/combat/combat_scene.tscn` : combat tactique

## Autoloads

- `scripts/autoload/GameManager.gd`
  - Etat global partie, transitions de scenes, sauvegarde simple
- `scripts/autoload/DataManager.gd`
  - Chargement des donnees SRD exportees
- `scripts/autoload/TurnManager.gd`
  - Orchestration du tour/initiative et regles d'actions
- `scripts/autoload/AudioManager.gd`
  - Lecture musique/SFX + niveaux audio
- `scripts/autoload/SettingsManager.gd`
  - Preferences persistantes (`user://settings.cfg`)

## Couche UI

- `scripts/ui/MainMenu.gd`
  - Navigation vers nouvelle partie, combat test, options
- `scripts/ui/ClassSelection.gd`
  - Choix de classe et creation hero initial
- `scripts/ui/OptionsMenu.gd`
  - Edition des preferences:
  - audio (on/off + volumes)
  - camera (sensibilite + inversion X)
  - keybinds (deplacement/camera)

## Couche Gameplay

### Exploration

- `scripts/dungeon/DungeonGenerator.gd`
  - Generation de carte donjon
- `scripts/dungeon/DungeonScene.gd`
  - Spawn hero, camera multi-mode, interactions, transition combat

### Combat

- `scripts/combat/CombatScene.gd`
  - Grille, input joueur, rendu des unites, journal
- `scripts/combat/CombatManager.gd`
  - Resolution attaques/degats/etats

### Ressources gameplay

- `scripts/resources/HeroData.gd`
- `scripts/resources/MonsterData.gd`

## Flux runtime

1. `main_menu.tscn`
2. `class_selection.tscn`
3. `dungeon_scene.tscn`
4. `combat_scene.tscn` (selon rencontre)
5. retour exploration via `GameManager`

## Couplage dnd-5e-core

Le projet ne depend pas du package Python a l'execution Godot.

La passerelle se fait hors runtime via `tools/dnd_data_exporter.py`, qui genere des snapshots JSON dans `data/` depuis dnd-5e-core.

## Conventions de maintenance

- Les fichiers exportes (exe/web/wasm/pck) ne sont pas versionnes.
- Les caches Godot `.godot/` sont exclus du suivi git.
- Les assets 3D non utilises sont retires du depot pour limiter la taille du projet.
