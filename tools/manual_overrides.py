"""手で決めた能力値を、作り直した generated/ratings/ に当て直す（tools/rebuild_all_ratings.py から呼ぶ）。

tools/manual_overrides.json の files.<年>_<phase>.<選手ID> に、打撃（ミート・パワー・選球眼・走力・弾道）・
投球（総合・スタミナ・K/9・BB/9・HR/9・球速）・成長（growth）の値を持つ。守備力・肩は当てない
（compute_ratings が basement などから出した値のまま）。

    python tools/manual_overrides.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATINGS = ROOT / "generated" / "ratings"
OVERRIDES = Path(__file__).resolve().parent / "manual_overrides.json"
RANKS = [(90, "S"), (80, "A"), (70, "B"), (60, "C"), (50, "D"), (40, "E"), (20, "F"), (0, "G")]


def rank_of(v: int) -> str:
    for low, r in RANKS:
        if v >= low:
            return r
    return "G"


def set_values(ratings: dict, values: dict) -> None:
    for k, v in values.items():
        ratings[k] = {"value": int(v), "rank": rank_of(int(v))}


def main() -> None:
    spec = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    for stem, players in spec["files"].items():
        path = RATINGS / f"{stem}.json"
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        by_id = {p["id"]: p for p in data["players"]}
        done = 0
        for pid, e in players.items():
            p = by_id.get(pid)
            if p is None:
                continue
            if "batting_ratings" in e and isinstance(p.get("batting"), dict):
                set_values(p["batting"]["ratings"], e["batting_ratings"])
                if e.get("trajectory") is not None:
                    p["batting"]["trajectory"] = e["trajectory"]
            if "pitching_ratings" in e and isinstance(p.get("pitching"), dict):
                set_values(p["pitching"]["ratings"], e["pitching_ratings"])
                if e.get("velocity_kmh") is not None:
                    p["pitching"]["velocity"] = {"kmh": int(e["velocity_kmh"]), "source": p["pitching"].get("velocity", {}).get("source", "observed")}
            if "growth" in e:
                p["growth"] = e["growth"]
            done += 1
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
        print(f"[manual] {stem}: {done}人")


if __name__ == "__main__":
    main()
