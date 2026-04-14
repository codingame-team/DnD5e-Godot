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
                    output: Path = OUTPUT_DIR / "monsters",
                    official_only: bool = True) -> int:
    """Exporte les monstres D&D 5e.

    Args:
        official_only: si True (défaut), n'exporte que les 332 monstres officiels SRD.
                       Mettre False pour inclure les 2200+ monstres extended (lent).
    """
    output.mkdir(parents=True, exist_ok=True)
    sources = [DATA_ROOT / "monsters" / "official"]
    if not official_only:
        sources.append(DATA_ROOT / "monsters" / "extended")

    files: dict[str, Path] = {}
    for src in sources:
        if src.exists():
            for f in src.glob("*.json"):
                files.setdefault(f.stem, f)  # official prioritaire

    if monster_names:
        files = {k: v for k, v in files.items() if k in monster_names}

    exported = 0
    index = []

    items = sorted(files.items())
    total = len(items)
    for i, (stem, fpath) in enumerate(items):
        with open(fpath, encoding="utf-8") as f:
            raw = json.load(f)

        # Ignorer les fichiers qui sont des listes cumulatives (ex: bestiary-sublist-data*)
        if isinstance(raw, list):
            continue

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
            # Compact pour la performance (Godot lit du JSON, pas besoin de pretty-print)
            json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

        index.append({
            "index": out["index"], "name": out["name"],
            "cr": cr, "type": out["type"], "hp": out["hp"], "ac": out["ac"],
        })
        exported += 1
        if exported % 50 == 0:
            print(f"    {exported}/{total}...", end="\r", flush=True)

    print(f"  ✓ {exported} monstres exportés ({total} fichiers traités)")

    with open(output / "_index.json", "w", encoding="utf-8") as f:
        json.dump(sorted(index, key=lambda x: x["cr"]), f, ensure_ascii=False, separators=(",", ":"))

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


_BOOL_MAP = {"false": False, "true": True, "none": None}


def _normalize_ac(ac_dict: dict) -> dict:
    """Normalise armor_class dict : convertit les string 'False'/'True'/'None' en vrais types Python."""
    result = {}
    for k, v in ac_dict.items():
        if isinstance(v, str) and v.lower() in _BOOL_MAP:
            result[k] = _BOOL_MAP[v.lower()]
        else:
            result[k] = v
    return result


def _to_bool(v) -> bool:
    """Convertit une valeur potentiellement stringifiée en bool Python."""
    if isinstance(v, bool):
        return v
    if isinstance(v, str):
        return _BOOL_MAP.get(v.lower(), bool(v))
    return bool(v)


def export_weapons(output: Path = OUTPUT_DIR / "items") -> int:
    """Exporte les armes enrichies via load_weapon() (attack_bonus, is_magic, price…)."""
    output.mkdir(parents=True, exist_ok=True)
    from dnd_5e_core.data.loader import load_weapon
    src = DATA_ROOT / "weapons"
    if not src.exists():
        print("  ⚠ Dossier weapons introuvable")
        return 0

    exported = 0
    for fpath in sorted(src.glob("*.json")):
        idx = fpath.stem
        w = load_weapon(idx)
        if w is None:
            continue

        two_h = w.damage_dice_two_handed
        out = {
            "index":    w.index,
            "name":     w.name,
            "category": "weapons",
            "damage": {
                "damage_dice":           str(w.damage_dice),
                "damage_type":           {"index": str(w.damage_type), "name": str(w.damage_type).capitalize()},
                "damage_dice_two_handed": str(two_h) if two_h else None,
            },
            "range":              str(w.range),
            "throw_range":        str(w.throw_range) if w.throw_range else None,
            "properties":         [str(p) for p in w.properties],
            "special_properties": [str(p) for p in (w.special_properties or [])],
            "attack_bonus":       w.attack_bonus,
            "damage_bonus":       w.damage_bonus,
            "is_magic":           w.is_magic,
            "is_martial":         w.is_martial,
            "is_melee":           w.is_melee,
            "is_ranged":          w.is_ranged,
            "is_simple":          w.is_simple,
            "category_type":      str(w.category_type).split(".")[-1].lower(),
            "category_range":     w.category_range,
            "cost":               str(w.cost),
            "price":              w.price,
            "sell_price":         w.sell_price,
            "weight":             w.weight,
            "desc":               list(w.desc) if w.desc else [],
        }

        dest = output / f"weapons_{idx}.json"
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        exported += 1

    print(f"  ✓ {exported} armes exportées")
    return exported


def export_armors(output: Path = OUTPUT_DIR / "items") -> int:
    """Exporte les armures enrichies via load_armor() (armor_bonus, saving_throw_bonus, price…)."""
    output.mkdir(parents=True, exist_ok=True)
    from dnd_5e_core.data.loader import load_armor
    src = DATA_ROOT / "armors"
    if not src.exists():
        print("  ⚠ Dossier armors introuvable")
        return 0

    exported = 0
    for fpath in sorted(src.glob("*.json")):
        idx = fpath.stem
        a = load_armor(idx)
        if a is None:
            continue

        out = {
            "index":               a.index,
            "name":                a.name,
            "category":            "armors",
            "armor_class":         _normalize_ac(a.armor_class),
            "armor_bonus":         a.armor_bonus,
            "str_minimum":         a.str_minimum,
            "stealth_disadvantage": _to_bool(a.stealth_disadvantage),
            "saving_throw_bonus":  a.saving_throw_bonus,
            "damage_immunities":   list(a.damage_immunities),
            "damage_resistances":  list(a.damage_resistances),
            "condition_immunities": list(a.condition_immunities),
            "special_properties":  list(a.special_properties),
            "cost":                str(a.cost),
            "price":               a.price,
            "sell_price":          a.sell_price,
            "weight":              a.weight,
            "desc":                list(a.desc) if a.desc else [],
        }

        dest = output / f"armors_{idx}.json"
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        exported += 1

    print(f"  ✓ {exported} armures exportées")
    return exported


def export_magic_items(output: Path = OUTPUT_DIR / "items") -> int:
    """Exporte les objets magiques enrichis via create_magic_item_from_data() (rarity, ac_bonus…)."""
    output.mkdir(parents=True, exist_ok=True)
    from dnd_5e_core.equipment.magic_item import create_magic_item_from_data
    src = DATA_ROOT / "magic-items"
    if not src.exists():
        print("  ⚠ Dossier magic-items introuvable")
        return 0

    exported = 0
    for fpath in sorted(src.glob("*.json")):
        with open(fpath, encoding="utf-8") as f:
            raw = json.load(f)
        mi = create_magic_item_from_data(raw)
        if mi is None:
            continue

        actions_list = []
        for act in (mi.actions or []):
            actions_list.append({
                "name": getattr(act, "name", str(act)),
                "desc": getattr(act, "desc", ""),
            })

        out = {
            "index":              mi.index,
            "name":               mi.name,
            "category":           "magic-items",
            "item_type":          str(mi.item_type).split(".")[-1].lower() if mi.item_type else "wondrous",
            "rarity":             str(mi.rarity).split(".")[-1].lower() if mi.rarity else "common",
            "requires_attunement": mi.requires_attunement,
            "attuned":            False,
            "ac_bonus":           mi.ac_bonus,
            "saving_throw_bonus": mi.saving_throw_bonus,
            "ability_bonuses":    dict(mi.ability_bonuses) if mi.ability_bonuses else {},
            "actions":            actions_list,
            "effects":            [str(e) for e in (mi.effects or [])],
            "cost":               str(mi.cost),
            "price":              mi.price,
            "sell_price":         mi.sell_price,
            "weight":             mi.weight,
            "desc":               list(mi.desc) if isinstance(mi.desc, list) else ([mi.desc] if mi.desc else []),
        }

        dest = output / f"magic_items_{mi.index}.json"
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        exported += 1

    print(f"  ✓ {exported} objets magiques exportés")
    return exported


def export_items(output: Path = OUTPUT_DIR / "items") -> int:
    """Exporte armes, armures et objets magiques enrichis via le module dnd-5e-core."""
    n_weapons = export_weapons(output)
    n_armors  = export_armors(output)
    n_magic   = export_magic_items(output)
    total = n_weapons + n_armors + n_magic

    # Index global
    index: list[dict] = []
    for f in sorted(output.glob("*.json")):
        if f.name == "_index.json":
            continue
        with open(f, encoding="utf-8") as fh:
            d = json.load(fh)
        index.append({"index": d.get("index",""), "name": d.get("name",""), "category": d.get("category","")})

    with open(output / "_index.json", "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    return total


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
    parser.add_argument("--output",   default=str(OUTPUT_DIR), help="Dossier de sortie")
    parser.add_argument("--all",      action="store_true", help="Exporter tout (SRD officiel)")
    parser.add_argument("--extended", action="store_true", help="Inclure les monstres extended (>2000, lent)")
    parser.add_argument("--classes",  nargs="*", help="Classes à exporter (vide = toutes)")
    parser.add_argument("--monsters", nargs="*", help="Monstres à exporter (vide = tous SRD)")
    parser.add_argument("--spells",   action="store_true", help="Exporter les sorts")
    parser.add_argument("--items",    action="store_true", help="Exporter les objets")
    parser.add_argument("--tokens",   action="store_true", help="Copier les tokens PNG")
    args = parser.parse_args()

    out = Path(args.output)
    official_only = not args.extended
    print(f"\n🎲 DnD Data Exporter → {out}\n")

    if args.all or args.classes is not None:
        names = args.classes if args.classes else None
        n = export_classes(names, out / "classes")
        print(f"  → {n} classes\n")

    if args.all or args.monsters is not None:
        names = args.monsters if args.monsters else None
        n = export_monsters(names, out / "monsters", official_only=official_only)
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
