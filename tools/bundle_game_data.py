"""Bundle and minify all game data into godot/data/ for standalone & Web export."""
import glob
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT_DATA = os.path.join(ROOT, "godot", "data")


def write_minified(src_path: str, dst_path: str, strip_rating_detail: bool = False) -> int:
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    with open(src_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if strip_rating_detail and isinstance(data, dict):
        for pl in data.get("players", []) + data.get("mlb_players", []):
            if isinstance(pl.get("batting"), dict):
                pl["batting"].pop("detail", None)
            if isinstance(pl.get("pitching"), dict):
                pl["pitching"].pop("detail", None)
            if isinstance(pl.get("fielding"), dict):
                for pos_d in pl["fielding"].values():
                    if isinstance(pos_d, dict):
                        pos_d.pop("detail", None)

    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(text)
    return len(text.encode("utf-8"))


def main() -> None:
    total_bytes = 0

    # 1. generated/ratings/*.json -> godot/data/ratings/*.json
    for src in sorted(glob.glob(os.path.join(ROOT, "generated", "ratings", "*.json"))):
        fname = os.path.basename(src)
        dst = os.path.join(GODOT_DATA, "ratings", fname)
        total_bytes += write_minified(src, dst, strip_rating_detail=True)

    # 2. generated/*.json -> godot/data/generated/*.json
    for src in sorted(glob.glob(os.path.join(ROOT, "generated", "*.json"))):
        fname = os.path.basename(src)
        dst = os.path.join(GODOT_DATA, "generated", fname)
        total_bytes += write_minified(src, dst)

    # 3. data/<year>/schedule.json -> godot/data/schedule/<year>.json
    for src in sorted(glob.glob(os.path.join(ROOT, "data", "*", "schedule.json"))):
        year_dir = os.path.basename(os.path.dirname(src))
        if not year_dir.isdigit():
            continue
        dst = os.path.join(GODOT_DATA, "schedule", f"{year_dir}.json")
        total_bytes += write_minified(src, dst)

    # 4. data/<year>/{rosters,drafts,awards}.json -> godot/data/<year>/...
    for name in ["rosters.json", "drafts.json", "awards.json"]:
        for src in sorted(glob.glob(os.path.join(ROOT, "data", "*", name))):
            year_dir = os.path.basename(os.path.dirname(src))
            if not year_dir.isdigit():
                continue
            dst = os.path.join(GODOT_DATA, year_dir, name)
            total_bytes += write_minified(src, dst)

    # 5. Root data/*.json and data/amateur/*.json
    root_files = [
        "trades.json",
        "mlb_moves.json",
        "mlb_intent.json",
        "draft_first_round.json",
        "drafts_2001-2007.json",
    ]
    for fname in root_files:
        src = os.path.join(ROOT, "data", fname)
        if os.path.exists(src):
            dst = os.path.join(GODOT_DATA, fname)
            total_bytes += write_minified(src, dst)

    for src in sorted(glob.glob(os.path.join(ROOT, "data", "amateur", "*.json"))):
        fname = os.path.basename(src)
        dst = os.path.join(GODOT_DATA, "amateur", fname)
        total_bytes += write_minified(src, dst)

    # 6. Merge data/<year>/players.json -> godot/data/all_players.json & players_by_year.json
    merged_players = {}
    players_by_year = {}
    for src in sorted(glob.glob(os.path.join(ROOT, "data", "*", "players.json"))):
        year_dir = os.path.basename(os.path.dirname(src))
        if not year_dir.isdigit():
            continue
        with open(src, "r", encoding="utf-8") as f:
            d = json.load(f)
        players_by_year[year_dir] = list(d.keys())
        merged_players.update(d)

    all_players_dst = os.path.join(GODOT_DATA, "all_players.json")
    all_players_text = json.dumps(merged_players, ensure_ascii=False, separators=(",", ":"))
    with open(all_players_dst, "w", encoding="utf-8") as f:
        f.write(all_players_text)
    total_bytes += len(all_players_text.encode("utf-8"))

    by_year_dst = os.path.join(GODOT_DATA, "players_by_year.json")
    by_year_text = json.dumps(players_by_year, ensure_ascii=False, separators=(",", ":"))
    with open(by_year_dst, "w", encoding="utf-8") as f:
        f.write(by_year_text)
    total_bytes += len(by_year_text.encode("utf-8"))

    print(f"Bundled successfully into {GODOT_DATA}")
    print(f"Total bundled size: {total_bytes / 1024 / 1024:.2f} MB")


if __name__ == "__main__":
    main()
