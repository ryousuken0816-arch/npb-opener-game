#!/usr/bin/env python3
"""npb.jp の公式戦カレンダーと日ごとの試合結果ページから、史実の年間日程を取得する。

  python schedule.py --start 2008 --end 2025

出力: ../data/<年>/schedule.json
  [{date, kind, home, away, venue, game_no, status, home_score, away_score}]
  - kind: central / pacific / interleague（CS・日本シリーズ・オールスター等は含めない）
  - home/away は npb.jp の球団略称（例: 東京ヤクルト, 阪神）。先に書かれている方がホーム
  - status: "played"（試合成立） / "canceled"（中止。振替は別の日付に played として出る）
  - スコアは参考（ゲームでは使わず、試合はシミュレーションする）
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from bs4 import BeautifulSoup

import collect
from collect import clean

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"


def game_dates(year: int) -> list[str]:
    """カレンダー(3・4月〜10月)のリンクから試合のある日付を集める。"""
    dates = set()
    for m in range(4, 12):
        html = collect.fetch(f"https://npb.jp/bis/{year}/calendar/index_{m:02d}.html")
        if not html:
            continue
        dates |= set(re.findall(rf"/bis/{year}/games/gm({year}\d{{4}})\.html", html))
        dates |= set(re.findall(rf"/bis/{year}/games/s({year}\d{{4}})\d+\.html", html))
    return sorted(dates)


def section_kind(header: str) -> str | None:
    """列見出し → 公式戦の種別。公式戦以外（CS・日本シリーズ・オールスター等）は None。"""
    h = re.sub(r"\s+", "", header)
    if "交流戦" in h:
        return "interleague"
    if "クライマックス" in h or "シリーズ" in h or "オールスター" in h or "アジア" in h:
        return None
    if "セントラル" in h:
        return "central"
    if "パシフィック" in h:
        return "pacific"
    return None


def parse_games(tbl, ymd: str, kind: str) -> list[dict]:
    """1つの表に 試合行（ホーム 点 - 点 ビジター）＋情報行（N回戦|中止, 球場）が繰り返し並ぶ。"""
    rows = tbl.find_all("tr", recursive=False)
    out = []
    for r, nxt in zip(rows, rows[1:] + [None]):
        c = [x.get_text(" ", strip=True) for x in r.find_all("td", recursive=False)]
        if len(c) != 7 or c[3] != "-":
            continue
        info = [x.get_text(" ", strip=True) for x in nxt.find_all("td", recursive=False)] if nxt else []
        label = info[0] if info else ""
        no = re.search(r"(\d+)回戦", label)
        played = c[2].isdigit() and c[4].isdigit() and "中止" not in label and "ノーゲーム" not in label
        out.append({
            "date": f"{ymd[:4]}-{ymd[4:6]}-{ymd[6:]}", "kind": kind,
            "home": re.sub(r"\s+", "", clean(c[1])), "away": re.sub(r"\s+", "", clean(c[5])),
            "venue": re.sub(r"\s+", "", clean(info[1])) if len(info) > 1 else None,
            "game_no": int(no.group(1)) if no else None,
            "status": "played" if played else "canceled",
            "home_score": int(c[2]) if c[2].isdigit() else None,
            "away_score": int(c[4]) if c[4].isdigit() else None,
        })
    return out


def parse_day(year: int, ymd: str) -> list[dict]:
    html = collect.fetch(f"https://npb.jp/bis/{year}/games/gm{ymd}.html")
    if not html:
        return []
    s = BeautifulSoup(html, "html.parser")
    games = []
    # 列ごとに見出し（1行目）と、その列に並ぶ試合（2行目以降）
    for block in s.select("div.gmdivsublist > table"):
        rows = block.find_all("tr", recursive=False)
        if not rows:
            continue
        headers = [td.get_text(" ", strip=True) for td in rows[0].find_all("td", recursive=False)]
        for tr in rows[1:]:
            for i, td in enumerate(tr.find_all("td", recursive=False)):
                # 交流戦の日は見出しが1つで全列にまたがる
                kind = section_kind(headers[i] if i < len(headers) else headers[-1]) if headers else None
                if not kind:
                    continue
                for gt in td.select("div.contentsgame > table"):
                    games += parse_games(gt, ymd, kind)
    return games


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=int, default=2008)
    ap.add_argument("--end", type=int, default=2025)
    args = ap.parse_args()
    for y in range(args.start, args.end + 1):
        dates = game_dates(y)
        games = []
        for d in dates:
            games += parse_day(y, d)
        out = DATA / str(y)
        out.mkdir(parents=True, exist_ok=True)
        (out / "schedule.json").write_text(json.dumps(games, ensure_ascii=False, indent=1), encoding="utf-8")
        played = [g for g in games if g["status"] == "played"]
        teams = sorted({g["home"] for g in played} | {g["away"] for g in played})
        print(f"[schedule] {y}: {len(dates)} days, {len(played)} played, "
              f"{len(games) - len(played)} canceled, {len(teams)} teams")


if __name__ == "__main__":
    main()
