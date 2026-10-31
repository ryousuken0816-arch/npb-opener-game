#!/usr/bin/env python3
"""史実のデータが無い年（2027年〜）の data/<年>/ を、前の年から写して作る（docs/AUTORUN.md 作業17）。

  python carry_over.py --year 2027

- schedule.json：前の年の公式戦（played のみ）を 364日後（同じ曜日）に写す。スコアは消す（史実ではない）
- rosters.json：前の年の名簿をそのまま（引退・戦力外は入れない。ゲームの中で決まる）。前の年の秋のドラフトの
  新人は npb.jp の選手IDが無いので入れず、能力値は tools/amateur_ratings.py rookies が足す
- teamstats_linked.json・awards.json：空（成績が無い）
- drafts.json は作らない（前の年の秋の指名は npb.jp から collect.py drafts で取る）

どのファイルにも、写したものと分かるよう schedule の各試合に `copied_from`、rosters の行に `carried_from` を付ける。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"
SHIFT_DAYS = 364  # 52週。曜日がそろう


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")


def copy_schedule(src_year: int) -> list[dict]:
    out = []
    for g in load(DATA / str(src_year) / "schedule.json"):
        if g["status"] != "played":
            continue
        d = dt.date.fromisoformat(g["date"]) + dt.timedelta(days=SHIFT_DAYS)
        out.append(dict(g, date=d.isoformat(), home_score=None, away_score=None, copied_from=g["date"]))
    return out


def carry_rosters(year: int) -> list[dict]:
    prev = year - 1
    out, seen = [], set()
    for r in load(DATA / str(prev) / "rosters.json"):
        if r["year"] != prev or r["player_id"] in seen:
            continue
        seen.add(r["player_id"])
        out.append(dict(r, year=year, carried_from=prev))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", type=int, required=True)
    args = ap.parse_args()
    out = DATA / str(args.year)
    out.mkdir(parents=True, exist_ok=True)
    games = copy_schedule(args.year - 1)
    dump(out / "schedule.json", games)
    rosters = carry_rosters(args.year)
    dump(out / "rosters.json", rosters)
    for name in ("teamstats_linked.json", "awards.json"):
        dump(out / name, [])
    print(f"[carry_over] {args.year}: {len(games)} games ({games[0]['date']}〜{games[-1]['date']}), "
          f"{len(rosters)} roster rows")


if __name__ == "__main__":
    main()
