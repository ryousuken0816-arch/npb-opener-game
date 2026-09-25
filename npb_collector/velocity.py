#!/usr/bin/env python3
"""baseballdata.jp の「最速」一覧（1軍投手のその年の最速球速）を取得し、npb.jp の選手IDに突合する。

  python velocity.py --start 2011 --end 2026

出力: ../data/velocity.json  [{year, league, name, team, max_kmh, games, player_id}]
2010年以前はサイトにページが無い。キャッシュは collect.py と共通(cache/)。
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

from bs4 import BeautifulSoup

import collect
from collect import clean, norm_name, surname_keys

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"
CURRENT_YEAR = 2026  # 当年はサイト直下(cmxq.html)、過去年は /<年>/cmxq.html

# baseballdata.jp の球団略称 → npb.jp の正式名に含まれる語
TEAM_KEYS = {
    "巨人": "読売", "阪神": "阪神", "中日": "中日", "広島": "広島", "ヤクルト": "ヤクルト",
    "DeNA": "横浜", "横浜": "横浜", "ソフトバンク": "ソフトバンク", "日本ハム": "日本ハム",
    "オリックス": "オリックス", "楽天": "楽天", "西武": "西武", "ロッテ": "ロッテ",
    # 2011年ページの1文字略称
    "巨": "読売", "神": "阪神", "中": "中日", "広": "広島", "ヤ": "ヤクルト", "横": "横浜",
    "ソ": "ソフトバンク", "日": "日本ハム", "オ": "オリックス", "楽": "楽天", "西": "西武", "ロ": "ロッテ",
}


def page_url(year: int, league: str) -> str:
    name = f"{league}mxq.html"
    return f"https://baseballdata.jp/{name}" if year == CURRENT_YEAR else f"https://baseballdata.jp/{year}/{name}"


def parse(year: int, league: str) -> list[dict]:
    html = collect.fetch(page_url(year, league))
    if not html:
        return []
    table = BeautifulSoup(html, "html.parser").find("table")
    rows = table.find_all("tr")
    header = [c.get_text(strip=True) for c in rows[0].find_all(["th", "td"])]
    idx = {h: i for i, h in enumerate(header)}
    # 年によって列名が違う（古いページ: 最高球速・試合数）
    for new, old in (("最速", "最高球速"), ("試合", "試合数")):
        if new not in idx and old in idx:
            idx[new] = idx[old]
    out = []
    for tr in rows[1:]:
        c = [x.get_text(" ", strip=True) for x in tr.find_all(["th", "td"])]
        if len(c) < len(header) or not c[idx["最速"]].isdigit():
            continue
        out.append({
            "year": year, "league": "セ" if league == "c" else "パ",
            "name": clean(c[idx["選手名"]]), "team": c[idx["球団"]],
            "max_kmh": int(c[idx["最速"]]),
            "games": int(c[idx["試合"]]) if c[idx["試合"]].isdigit() else None,
        })
    return out


def load_rosters(year: int) -> list[dict]:
    p = DATA / str(year) / "rosters.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else []


def match(rec: dict, rosters: list[dict]) -> str | None:
    key = TEAM_KEYS.get(rec["team"], rec["team"])
    team_rows = [r for r in rosters if key in r["team"]]
    n = norm_name(rec["name"])
    exact = {r["player_id"] for r in team_rows if norm_name(r["name"]) == n}
    if len(exact) == 1:
        return exact.pop()
    # 同姓がいる場合の略記（例: 小林正 = 小林 正人）
    prefix = {r["player_id"] for r in team_rows if norm_name(r["name"]).startswith(n)}
    if len(prefix) == 1:
        return prefix.pop()
    # 外国人: 片方が姓のみ・片方がフルネーム
    rec_keys = surname_keys(rec["name"]) | {n}
    sur = {r["player_id"] for r in team_rows
           if rec_keys & (surname_keys(r["name"]) | {norm_name(r["name"])})}
    if len(sur) == 1:
        return sur.pop()
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=int, default=2011)
    ap.add_argument("--end", type=int, default=CURRENT_YEAR)
    args = ap.parse_args()
    overrides_path = ROOT / "velocity_overrides.json"
    overrides = json.loads(overrides_path.read_text(encoding="utf-8")) if overrides_path.exists() else {}

    result, unmatched = [], []
    for y in range(args.start, args.end + 1):
        rosters = load_rosters(y)
        recs = parse(y, "c") + parse(y, "p")
        for r in recs:
            k = f'{y}|{r["team"]}|{r["name"]}'
            r["player_id"] = overrides.get(k) or match(r, rosters)
            if not r["player_id"]:
                unmatched.append(k)
        result += recs
        print(f"[velocity] {y}: {len(recs)} pitchers, unmatched {sum(1 for r in recs if not r['player_id'])}")
    (DATA / "velocity.json").write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    (ROOT / "out").mkdir(exist_ok=True)
    (ROOT / "out" / "velocity_unmatched.json").write_text(json.dumps(unmatched, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  -> data/velocity.json ({len(result)} rows), unmatched {len(unmatched)}")


if __name__ == "__main__":
    main()
