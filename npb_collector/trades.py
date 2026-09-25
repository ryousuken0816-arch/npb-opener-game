#!/usr/bin/env python3
"""npb.jp の公示「トレード」（年度別）から、史実のトレードを取得する。

  python trades.py --start 2008 --end 2025

出力: ../data/trades.json
  [{trade_id, season, date, name, pos, number, from_team, to_team, player_id}]
  - season: 公示の年度（例: 2012年度は2012年のシーズン中〜2013年1月の移籍を含む）
  - trade_id: 同じ日付・同じ2球団の間の移籍をまとめた1件のトレード（例: 2013-01-25|オリックス|北海道日本ハム）
  - 金銭トレードは相手側の選手がいない（1人だけの trade_id）
  - player_id は data/<年>/rosters.json の名前＋移籍元球団で突合（見つからなければ null）
用途：CPU球団同士の史実のトレードを、両方の選手がまだその球団にいれば起こす（docs/SPEC.md 参照）
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from bs4 import BeautifulSoup

import collect
from collect import clean, norm_name

DATA = Path(__file__).resolve().parent.parent / "data"


def parse(season: int) -> list[dict]:
    html = collect.fetch(f"https://npb.jp/announcement/{season}/pn_traded.html")
    if not html:
        return []
    out, prev = [], None
    for tr in BeautifulSoup(html, "html.parser").find_all("tr"):
        c = [clean(x.get_text(" ")) for x in tr.find_all(["td", "th"])]
        if len(c) < 7 or c[5] != "→":
            continue
        row = {"date": c[0], "name": c[1], "pos": c[2].replace(" ", ""), "number": c[3],
               "from_team": c[4], "to_team": c[6]}
        if prev:  # 「〃」は上の行と同じ
            for k in ("date", "from_team", "to_team"):
                if row[k] == "〃":
                    row[k] = prev[k]
        prev = row
        y, m, d = (int(x) for x in re.findall(r"\d+", row["date"])[:3])
        row["date"] = f"{y:04d}-{m:02d}-{d:02d}"
        row["season"] = season
        out.append(row)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=int, default=2008)
    ap.add_argument("--end", type=int, default=2025)
    args = ap.parse_args()
    rows = []
    for s in range(args.start, args.end + 1):
        r = parse(s)
        rows += r
        print(f"[trades] {s}年度: {len(r)}人")

    # 選手IDの突合（その年度か翌年の名簿で、名前が一致し移籍元の球団名を含む）
    rosters = {}
    for s in range(args.start, args.end + 2):
        p = DATA / str(s) / "rosters.json"
        rosters[s] = json.loads(p.read_text(encoding="utf-8")) if p.exists() else []
    for r in rows:
        n = norm_name(r["name"])
        cands = {x["player_id"] for yr in (r["season"], r["season"] + 1) for x in rosters.get(yr, [])
                 if norm_name(x["name"]) == n}
        if len(cands) > 1:
            short = norm_name(r["from_team"])
            cands = {x["player_id"] for x in rosters.get(r["season"], [])
                     if norm_name(x["name"]) == n and short[:2] in norm_name(x["team"])} or cands
        r["player_id"] = next(iter(cands)) if len(cands) == 1 else None
        teams = sorted([r["from_team"], r["to_team"]])
        r["trade_id"] = f'{r["date"]}|{teams[0]}|{teams[1]}'
    (DATA / "trades.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    unmatched = [r for r in rows if not r["player_id"]]
    print(f"  -> data/trades.json ({len(rows)}人, {len({r['trade_id'] for r in rows})}件), 選手ID未突合 {len(unmatched)}")
    for r in unmatched[:20]:
        print("   ", r["season"], r["name"], r["from_team"], "→", r["to_team"])


if __name__ == "__main__":
    main()
