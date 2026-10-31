#!/usr/bin/env python3
"""npb.jp の公式戦カレンダーと日ごとの試合結果ページから、史実の年間日程を取得する。

  python schedule.py --start 2008 --end 2026

2008〜2025年は /bis/<年>/calendar/ と /bis/<年>/games/gm<日付>.html、
2026年以降は /games/<年>/schedule_<月>_detail.html（月ごとの一覧。ページ構成が違う）から取る。

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


# 2026年以降の月別一覧は球団名が短い略称（巨人・DeNA など）なので、2025年までの略称にそろえる
SHORT_TEAMS = {
    "巨人": ("読売", "c"), "ヤクルト": ("東京ヤクルト", "c"), "DeNA": ("横浜DeNA", "c"),
    "中日": ("中日", "c"), "阪神": ("阪神", "c"), "広島": ("広島東洋", "c"),
    "日本ハム": ("北海道日本ハム", "p"), "楽天": ("東北楽天", "p"), "西武": ("埼玉西武", "p"),
    "ロッテ": ("千葉ロッテ", "p"), "オリックス": ("オリックス", "p"), "ソフトバンク": ("福岡ソフトバンク", "p"),
}
SHORT_VENUES = {"マツダスタジアム": "マツダ"}


def parse_month_detail(year: int, month: int) -> list[dict]:
    """2026年以降: 月別の一覧（1行1試合。日付の見出しは rowspan、行の id が dateMMDD）。"""
    html = collect.fetch(f"https://npb.jp/games/{year}/schedule_{month:02d}_detail.html")
    if not html:
        return []
    s = BeautifulSoup(html, "html.parser")
    out = []
    for tr in s.select("table tbody tr"):
        m = re.match(r"date(\d{2})(\d{2})", tr.get("id") or "")
        t1, t2 = tr.select_one("div.team1"), tr.select_one("div.team2")
        if not m or not t1 or not t2:
            continue
        if clean(t1.get_text()) not in SHORT_TEAMS or clean(t2.get_text()) not in SHORT_TEAMS:
            continue  # オールスター（セ・リーグ 対 パ・リーグ）など
        home, away = SHORT_TEAMS[clean(t1.get_text())], SHORT_TEAMS[clean(t2.get_text())]
        s1, s2 = tr.select_one("div.score1"), tr.select_one("div.score2")
        h, a = (clean(s1.get_text()) if s1 else ""), (clean(s2.get_text()) if s2 else "")
        played = h.isdigit() and a.isdigit() and not tr.select_one("div.cancel")
        link = tr.select_one('a[href*="/scores/"]')
        no = re.search(r"-(\d+)/?$", link["href"]) if link else None
        place = tr.select_one("div.place")
        venue = re.sub(r"\s+", "", clean(place.get_text())) if place else None
        out.append({
            "date": f"{year}-{m.group(1)}-{m.group(2)}",
            "kind": "interleague" if home[1] != away[1] else ("central" if home[1] == "c" else "pacific"),
            "home": home[0], "away": away[0], "venue": SHORT_VENUES.get(venue, venue),
            "game_no": int(no.group(1)) if no and played else None,
            "status": "played" if played else "canceled",
            "home_score": int(h) if h.isdigit() else None,
            "away_score": int(a) if a.isdigit() else None,
        })
    return out


def drop_postseason(games: list[dict]) -> list[dict]:
    """月別一覧には CS・日本シリーズも同じ形で並ぶ。同じ組み合わせの N回戦 が小さい数に戻ったら
    そこから先はポストシーズンとみなして除く（公式戦の N回戦 は組み合わせごとに増えていく）。"""
    last, post, out = {}, set(), []
    for g in games:
        pair = frozenset((g["home"], g["away"]))
        if g["game_no"] is not None:
            if pair in last and g["game_no"] < last[pair]:
                post.add(pair)
            last[pair] = max(last.get(pair, 0), g["game_no"])
        if pair not in post:
            out.append(g)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=int, default=2008)
    ap.add_argument("--end", type=int, default=2026)
    args = ap.parse_args()
    for y in range(args.start, args.end + 1):
        games = []
        if y >= 2026:
            for m in range(3, 11):
                games += parse_month_detail(y, m)
            games.sort(key=lambda g: g["date"])  # 同じ日の中は一覧の並び（sort は安定）
            games = drop_postseason(games)
            dates = sorted({g["date"] for g in games})
        else:
            dates = game_dates(y)
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
