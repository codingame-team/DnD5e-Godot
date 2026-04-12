#!/usr/bin/env python3
"""
Exporteur de données D&D 5e → JSON pour Godot 4.

Lit les données de dnd-5e-core et génère des fichiers JSON optimisés
pour Godot (DataManager.gd).

Usage :
    python tools/dnd_data_exporter.py [--output data/] [--all]
    python tools/dnd_data_exporter.py --classes fighter wizard cleric
    python tools/dnd_data_exporter.py --monsters goblin orc troll
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

# Chemin vers dnd-5e-core
DND_CORE_PATH = Path("/Users/display/PycharmProjects/dnd-5e-core")
sys.path.insert(0, str(DND_CORE_PATH))

DATA_ROOT  = DND_CORE_PATH / "dnd_5e_core" / "data"
OUTPUT_DIR = Path(__file__).parent.parent / "data"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_cr(cr_value) -> float:
    if isinstance(cr_value, (int, float)):
        return float(cr_value)
    fracs = {"1/8": 0.125, "1/4": 0.25, "1/2": 0.5, "0": 0.0}
    return fracs.get(str(cr_value), 0.0)


def _parse_ac(ac) -> int:
    if isinstance(ac, int):
        return ac
    if isinstance(ac, list) and ac:
        item = ac[0]
        return item.get("value", 10) if isinstance(item, dict) else int(item)
    return 10


def _extract_damage_dice(damage_list: list) -> list[dict]:
    """Extrait la liste [{dice, type}] depuis le format API."""
    result = []
    for d in damage_list:
        dice = d.get("damage_dice", "")
        dtype = ""
        dt = d.get("damage_type")
        if isinstance(dt, dict):
            dtype = dt.get("index", "")
        result.append({"dice": dice, "type": dtype})
    return result


def _parse_actions(actions: list) -> list[dict]:
    """Normalise les actions d'un monstre."""
    result = []
    for a in actions:
        entry = {
            "name": a.get("name", ""),
            "desc": a.get("desc", ""),
            "attack_bonus": a.get("attack_bonus", 0),
            "damage": _extract_damage_dice(a.get("damage", [])),
            "dc": None,
        }
        if "dc" in a:
            dc = a["dc"]
            entry["dc"] = {
                "value": dc.get("dc_value", 10),
                "type": dc.get("dc_type", {}).get("index", ""),
                "success": dc.get("success_type", "none"),
            }
        result.append(entry)
    return result


# ---------------------------------------------------------------------------
# Exporteurs par catégorie
# ---------------------------------------------------------------------------

def export_classes(class_names: list[str] | None = None,
                   output: Path = OUTPUT_DIR / "classes") -> int:
    """Exporte les classes D&D 5e."""
    output.mkdir(parents=True, exist_ok=True)
    src = DATA_ROOT / "classes"
    files = list(src.glob("*.json"))
    if class_names:
        files = [f for f in files if f.stem in class_names]

    exported = 0
    index = []

    for fpath in sorted(files):
        with open(fpath, encoding="utf-8") as f:
            raw = json.load(f)

        # Niveaux : récupérer les features
        levels_path = DATA_ROOT / "class_levels" / fpath.name
        levels_data = []
        if levels_path.exists():
            with open(levels_path, encoding="utf-8") as f:
                levels_raw = json.load(f)
            if isinstance(levels_raw, list):
                for lvl in levels_raw:
                    levels_data.append({
                        "level": lvl.get("level", 1),
                        "prof_bonus": lvl.get("prof_bonus", 2),
                        "features": [feat.get("name","") for feat in lvl.get("features", [])],
                        "class_specific": lvl.get("class_specific", {}),
                        "spellcasting": lvl.get("spellcasting", {}),
                    })

        out = {
            "index":       raw["index"],
            "name":        raw["name"],
            "hit_die":     raw["hit_die"],
            "saving_throws": [s.get("index", s.get("name","")) for s in raw.get("saving_throws", [])],
            "proficiencies": [p.get("index", p.get("name","")) for p in raw.get("proficiencies", [])],
            "spellcasting": raw.get("spellcasting", None),
            "levels": levels_data,
        }

        dest = output / fpath.name
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)

        index.append({"index": raw["index"], "name": raw["name"], "hit_die": raw["hit_die"]})
        exported += 1
        print(f"  ✓ Classe : {raw['name']}")

    with open(output / "_index.json", "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    return exported


def export_monsters(monster_names: list[str] | None = None,
                    output: Path = OUTPUT_DIR / "monsters") -> int:
    """Exporte les monstres D&D 5e (official + extended)."""
    output.mkdir(parents=True, exist_ok=True)
    sources = [
        DATA_ROOT / "monsters" / "official",
        DATA_ROOT / "monsters" / "extended",
    ]
    files: dict[str, Path] = {}
    for src in sources:
        if src.exists():
            for f in src.glob("*.json"):
                files.setdefault(f.stem, f)  # official prioritaire

    if monster_names:
        files = {k: v for k, v in files.items() if k in monster_names}

    exported = 0
    index = []

    for stem, fpath in sorted(files.items()):
        with open(fpath, encoding="utf-8") as f:
            raw = json.load(f)

        cr = _parse_cr(raw.get("challenge_rating", 0))
        hp_raw = raw.get("hit_points_roll", "")
        if not hp_raw:
            hp_raw = f"{raw.get('hit_points', 4)}d{raw.get('hit_dice', 8)}" \
                     if raw.get("hit_dice") else str(raw.get("hit_points", 4))

        out = {
            "index":  raw.get("index", stem),
            "name":   raw.get("name", stem),
            "size":   raw.get("size", "Medium"),
            "type":   raw.get("type", "beast"),
            "cr":     cr,
            "xp":     raw.get("xp", max(10, int(cr * 100))),
            "hp":     raw.get("hit_points", 4),
            "hp_roll": hp_raw,
            "ac":     _parse_ac(raw.get("armor_class", 10)),
            "speed":  raw.get("speed", {}).get("walk", 30) if isinstance(raw.get("speed"), dict) else 30,
            "abilities": {
                "str": raw.get("strength", 10),
                "dex": raw.get("dexterity", 10),
                "con": raw.get("constitution", 10),
                "int": raw.get("intelligence", 10),
                "wis": raw.get("wisdom", 10),
                "cha": raw.get("charisma", 10),
            },
            "actions":     _parse_actions(raw.get("actions", [])),
            "reactions":   _parse_actions(raw.get("reactions", [])),
            "legendary_actions": _parse_actions(raw.get("legendary_actions", [])),
            "traits":      [{"name": t.get("name",""), "desc": t.get("desc","")}
                            for t in raw.get("special_abilities", [])],
            "senses":      raw.get("senses", {}),
            "languages":   raw.get("languages", ""),
            "proficiencies": raw.get("proficiencies", []),
        }

        dest = output / f"{stem}.json"
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)

        index.append({
            "index": out["index"], "name": out["name"],
            "cr": cr, "type": out["type"], "hp": out["hp"], "ac": out["ac"],
        })
        exported += 1

    print(f"  ✓ {exported} monstres exportés")

    with open(output / "_index.json", "w", encoding="utf-8") as f:
        json.dump(sorted(index, key=lambda x: x["cr"]), f, ensure_ascii=False, indent=2)

    return exported


def export_spells(output: Path = OUTPUT_DIR / "spells") -> int:
    """Exporte tous les sorts."""
    output.mkdir(parents=True, exist_ok=True)
    src = DATA_ROOT / "spells"
    if not src.exists():
        print("  ⚠ Dossier sorts introuvable")
        return 0

    files = list(src.glob("*.json"))
    exported = 0
    index = []

    for fpath in sorted(files):
        with open(fpath, encoding="utf-8") as f:
            raw = json.load(f)

        out = {
            "index":       raw.get("index", fpath.stem),
            "name":        raw.get("name", ""),
            "level":       raw.get("level", 0),
            "school":      raw.get("school", {}).get("name", "") if isinstance(raw.get("school"), dict) else "",
            "casting_time": raw.get("casting_time", "1 action"),
            "range":       raw.get("range", "Self"),
            "duration":    raw.get("duration", "Instantaneous"),
            "concentration": raw.get("concentration", False),
            "ritual":      raw.get("ritual", False),
            "components":  raw.get("components", []),
            "desc":        " ".join(raw.get("desc", [])) if isinstance(raw.get("desc"), list) else raw.get("desc", ""),
            "damage":      raw.get("damage", {}),
            "dc":          raw.get("dc", {}),
            "classes":     [c.get("index","") for c in raw.get("classes", [])],
        }

        dest = output / fpath.name
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)

        index.append({
            "index": out["index"], "name": out["name"],
            "level": out["level"], "school": out["school"],
            "classes": out["classes"],
        })
        exported += 1

    print(f"  ✓ {exported} sorts exportés")
    with open(output / "_index.json", "w", encoding="utf-8") as f:
        json.dump(sorted(index, key=lambda x: (x["level"], x["name"])),
                  f, ensure_ascii=False, indent=2)

    return exported


def export_items(output: Path = OUTPUT_DIR / "items") -> int:
    """Exporte les équipements (armes, armures, objets magiques)."""
    output.mkdir(parents=True, exist_ok=True)
    categories = ["weapons", "armors", "magic-items"]
    exported = 0
    index = []

    for cat in categories:
        src = DATA_ROOT / cat
        if not src.exists():
            continue
        for fpath in sorted(src.glob("*.json")):
            with open(fpath, encoding="utf-8") as f:
                raw = json.load(f)

            out = {
                "index":    raw.get("index", fpath.stem),
                "name":     raw.get("name", ""),
                "category": cat.rstrip("s"),
                "cost":     raw.get("cost", {}),
                "weight":   raw.get("weight", 0),
                "desc":     raw.get("desc", []),
                "damage":   raw.get("damage", {}),
                "armor_class": raw.get("armor_class", {}),
                "properties": [p.get("index","") for p in raw.get("properties", [])],
                "weapon_range": raw.get("weapon_range", ""),
                "str_minimum": raw.get("str_minimum", 0),
                "stealth_disadvantage": raw.get("stealth_disadvantage", False),
            }

            dest = output / f"{cat.replace('-','_')}_{fpath.name}"
            with open(dest, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False, indent=2)

            index.append({"index": out["index"], "name": out["name"], "category": cat})
            exported += 1

    print(f"  ✓ {exported} objets exportés")
    with open(output / "_index.json", "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
    return exported


def copy_tokens(output: Path = OUTPUT_DIR.parent / "assets" / "tokens") -> int:
    """Copie les portraits (tokens PNG) vers assets/tokens/."""
    src = DATA_ROOT / "tokens"
    if not src.exists():
        print("  ⚠ Dossier tokens introuvable")
        return 0
    output.mkdir(parents=True, exist_ok=True)
    count = 0
    for f in src.glob("*.png"):
        shutil.copy2(f, output / f.name)
        count += 1
    print(f"  ✓ {count} tokens copiés vers assets/tokens/")
    return count


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Exporte les données D&D 5e → Godot JSON")
    parser.add_argument("--output", default=str(OUTPUT_DIR), help="Dossier de sortie")
    parser.add_argument("--all",      action="store_true", help="Exporter tout")
    parser.add_argument("--classes",  nargs="*", help="Classes à exporter (vide = toutes)")
    parser.add_argument("--monsters", nargs="*", help="Monstres à exporter (vide = tous)")
    parser.add_argument("--spells",   action="store_true", help="Exporter les sorts")
    parser.add_argument("--items",    action="store_true", help="Exporter les objets")
    parser.add_argument("--tokens",   action="store_true", help="Copier les tokens PNG")
    args = parser.parse_args()

    out = Path(args.output)
    print(f"\n🎲 DnD Data Exporter → {out}\n")

    if args.all or args.classes is not None:
        names = args.classes if args.classes else None
        n = export_classes(names, out / "classes")
        print(f"  → {n} classes\n")

    if args.all or args.monsters is not None:
        names = args.monsters if args.monsters else None
        n = export_monsters(names, out / "monsters")
        print(f"  → {n} monstres\n")

    if args.all or args.spells:
        n = export_spells(out / "spells")
        print(f"  → {n} sorts\n")

    if args.all or args.items:
        n = export_items(out / "items")
        print(f"  → {n} objets\n")

    if args.all or args.tokens:
        copy_tokens(out.parent / "assets" / "tokens")

    print("✅ Export terminé\n")


if __name__ == "__main__":
    main()
