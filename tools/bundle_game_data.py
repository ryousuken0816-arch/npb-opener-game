"""Bundle and minify all game data into godot/data/ for standalone & Web export."""
import glob
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT_DATA = os.path.join(ROOT, "godot", "data")


## 選手ページを分けるファイルの数と分け方（godot/autoload/game_data.gd の PLAYER_SHARDS・shard_of と同じ）
PLAYER_SHARDS = 32


def shard_of(pid: str) -> int:
    return sum(ord(c) for c in pid) % PLAYER_SHARDS


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

    # 6. Merge data/<year>/players.json -> godot/data/players/<NN>.json & players_by_year.json
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

    # 選手IDで PLAYER_SHARDS 個のファイルに分ける（docs/AUTORUN.md 作業74）。1つにまとめると Web 版で読んだとき
    # 約90MB（読む瞬間は120MB）になり、iPhone で落ちた。ゲームは要る選手のファイルだけ読む（GameData.shard_of と同じ分け方）
    shards = [dict() for _ in range(PLAYER_SHARDS)]
    for pid, page in merged_players.items():
        shards[shard_of(pid)][pid] = page
    shard_dir = os.path.join(GODOT_DATA, "players")
    os.makedirs(shard_dir, exist_ok=True)
    for i, shard in enumerate(shards):
        text = json.dumps(shard, ensure_ascii=False, separators=(",", ":"))
        with open(os.path.join(shard_dir, "%02d.json" % i), "w", encoding="utf-8") as f:
            f.write(text)
        total_bytes += len(text.encode("utf-8"))
    # 選手ID → 1軍初出場の年（ページの年度別成績の最小。育成の判定 GameData.page_debut_years が Web 版で使う）
    debut = {}
    for pid, page in merged_players.items():
        years = [int(r["年度"]) for part in ("batting", "pitching") for r in (page.get(part) or [])
                 if isinstance(r, dict) and isinstance(r.get("年度"), (int, float)) and int(r["年度"]) > 0]
        if years:
            debut[pid] = min(years)
    debut_text = json.dumps(debut, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(GODOT_DATA, "player_debut.json"), "w", encoding="utf-8") as f:
        f.write(debut_text)
    total_bytes += len(debut_text.encode("utf-8"))
    old_all = os.path.join(GODOT_DATA, "all_players.json")
    if os.path.exists(old_all):
        os.remove(old_all)

    by_year_dst = os.path.join(GODOT_DATA, "players_by_year.json")
    by_year_text = json.dumps(players_by_year, ensure_ascii=False, separators=(",", ":"))
    with open(by_year_dst, "w", encoding="utf-8") as f:
        f.write(by_year_text)
    total_bytes += len(by_year_text.encode("utf-8"))

    print(f"Bundled successfully into {GODOT_DATA}")
    print(f"Total bundled size: {total_bytes / 1024 / 1024:.2f} MB")


if __name__ == "__main__":
    main()
