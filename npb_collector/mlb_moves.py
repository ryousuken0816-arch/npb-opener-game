#!/usr/bin/env python3
"""NPB→MLB 移籍（ポスティング・海外FA等）と、その選手のMLB成績を作る。

  python mlb_moves.py

手順:
  1. MLB公式 statsapi の各年の選手一覧から、日本出身の選手（MLB ID・英語名・生年月日）を集める
  2. data/<年>/players.json の生年月日と突き合わせて npb.jp の選手IDに結び付ける
  3. NPB の1軍出場年と MLB の出場年から「何年のオフに出て行き、何年に戻ったか」を割り出す
  4. ウィキペディア「ポスティングシステム」の成立一覧に載っていれば route=posting、なければ other（海外FA・自由契約など）
  5. MLB の年度別成績（打撃・投手）を保存する

出力:
  ../data/mlb_moves.json  [{player_id, name, mlb_id, mlb_name, birth, npb_team_before, left_after, route,
                             mlb_first, mlb_last, returned, npb_team_after}]
     - left_after: この年のシーズン後に NPB を離れた（翌年から MLB）
     - returned: NPB に戻った最初の年（戻っていなければ null）
  ../data/mlb_stats.json  {mlb_id: {"hitting": [年度別...], "pitching": [年度別...]}}
MLB のデータは statsapi.mlb.com（個人・非商用の利用に限る旨の著作権表示あり）。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import collect
from collect import norm_name

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"
MLB_SEASONS = range(2000, 2026)
# 生年月日が同じ別人がいて自動で決められない選手（MLB ID → npb.jp 選手ID）
MANUAL_MLB_TO_NPB = {547874: "01105111"}  # 岩隈久志（新里賢と同じ生年月日）
# MLBの試合に出ずマイナーだけで戻った選手（MLB一覧に載らない）
MANUAL_MOVES = [
    {"player_id": "01005113", "left_after": 2012, "route": "other"},  # 中島宏之：海外FAでアスレチックス→2015年オリックス
]
POSTING_PAGE = "https://ja.wikipedia.org/w/index.php?title=%E3%83%9D%E3%82%B9%E3%83%86%E3%82%A3%E3%83%B3%E3%82%B0%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0&action=raw"


def load_json(url: str):
    text = collect.fetch(url)
    return json.loads(text) if text else None


def npb_players() -> dict:
    """全年の players.json を統合（新しい年のページほど通算成績が長いので後勝ち）。"""
    out = {}
    for d in sorted(DATA.glob("20[0-9][0-9]")):
        p = d / "players.json"
        if p.exists():
            out.update(json.loads(p.read_text(encoding="utf-8")))
    return out


def npb_seasons(p: dict) -> dict[int, str]:
    """1軍に出場した年 → 所属球団（選手ページの年度別成績から）。"""
    seasons = {}
    for row in p.get("batting", []) + p.get("pitching", []):
        y = row.get("年度")
        if isinstance(y, int):
            seasons.setdefault(y, row.get("所属球団") or "")
    return seasons


def posting_success() -> set[tuple[int, str]]:
    """ウィキペディアのポスティング成立一覧 → {(年, 正規化名)}。「非成立」の表は除く。
    表の1行（"|-" 区切り）ごとに、年度のセル（rowspan で省略されることがある）と最初のリンク＝選手名を読む。"""
    raw = collect.fetch(POSTING_PAGE) or ""
    out, skip = set(), True
    for section in re.split(r"\n(?==)", raw):
        head = section.split("\n", 1)[0]
        if head.startswith("="):
            skip = "非成立" in head
        if skip or "{|" not in section:
            continue
        year = None
        for row in section.split("\n|-"):
            y = re.search(r"(?:^|\|)\s*(?:nowrap\||rowspan=\"\d+\"\|)*\s*(\d{4})年", row)
            if y:
                year = int(y.group(1))
            link = re.search(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]", row)
            if year and link:
                label = re.sub(r"\s*\(.*?\)", "", link.group(2) or link.group(1))
                out.add((year, norm_name(label)))
    return out


def main():
    # 1. MLB の日本出身選手
    mlb = {}
    for y in MLB_SEASONS:
        d = load_json(f"https://statsapi.mlb.com/api/v1/sports/1/players?season={y}")
        for p in (d or {}).get("people", []):
            if p.get("birthCountry") == "Japan" and p.get("birthDate"):
                mlb[p["id"]] = {"mlb_id": p["id"], "mlb_name": p["fullName"], "birth": p["birthDate"]}
    print(f"[mlb] 日本出身のMLB選手: {len(mlb)}")

    # 2. NPB 選手と生年月日で突き合わせ
    npb = npb_players()
    by_birth = {}
    for pid, p in npb.items():
        if p.get("birth"):
            by_birth.setdefault(p["birth"], []).append(pid)
    posted = posting_success()

    moves, stats = [], {}
    for m in mlb.values():
        cands = by_birth.get(m["birth"], [])
        if not cands:
            continue
        hit = load_json(f"https://statsapi.mlb.com/api/v1/people/{m['mlb_id']}/stats?stats=yearByYear&group=hitting")
        pit = load_json(f"https://statsapi.mlb.com/api/v1/people/{m['mlb_id']}/stats?stats=yearByYear&group=pitching")
        def splits(d):
            return [s for st in (d or {}).get("stats", []) for s in st.get("splits", [])
                    if s.get("sport", {}).get("id", 1) == 1 and "team" in s]
        h, pt = splits(hit), splits(pit)
        mlb_years = sorted({int(s["season"]) for s in h + pt})
        if not mlb_years:
            continue
        if m["mlb_id"] in MANUAL_MLB_TO_NPB:
            cands = [MANUAL_MLB_TO_NPB[m["mlb_id"]]]
        if len(cands) > 1:
            # 生年月日が同じ別人：MLBに行く前にNPBに出ていて、MLBの年にはNPBに出ていない人を選ぶ
            fit = [c for c in cands
                   if any(y < mlb_years[0] for y in npb_seasons(npb[c]))
                   and not any(mlb_years[0] <= y <= mlb_years[-1] for y in npb_seasons(npb[c]))]
            if len(fit) != 1:
                print(f"  ? 生年月日が重複して決められない: {m['mlb_name']} {m['birth']} {cands}")
                continue
            cands = fit
        pid = cands[0]
        p = npb[pid]
        seasons = npb_seasons(p)
        before = [y for y in seasons if y < mlb_years[0]]
        if not before:
            continue  # NPB を経ずに MLB へ（対象外）
        left = max(before)
        after = [y for y in seasons if y > mlb_years[-1]]
        returned = min(after) if after else None
        if left < 2006 and (returned is None or returned < 2008):
            continue  # ゲーム期間（2008〜）に関係しない
        route = "posting" if (left, norm_name(p["name"])) in posted else "other"
        moves.append({
            "player_id": pid, "name": p["name"], **m,
            "npb_team_before": seasons.get(left), "left_after": left, "route": route,
            "mlb_first": mlb_years[0], "mlb_last": mlb_years[-1],
            "returned": returned, "npb_team_after": seasons.get(returned) if returned else None,
        })
        stats[str(m["mlb_id"])] = {
            "hitting": [{"season": int(s["season"]), "team": s["team"]["name"], **s["stat"]} for s in h],
            "pitching": [{"season": int(s["season"]), "team": s["team"]["name"], **s["stat"]} for s in pt],
        }
    # MLB出場がまだ無いポスティング組（例: 2025年オフ）を、成立一覧から補う
    known = {m["player_id"] for m in moves}
    by_name = {}
    for pid, p in npb.items():
        by_name.setdefault(norm_name(p["name"]), []).append(pid)
    for year, name in sorted(posted):
        pids = [pid for pid in by_name.get(name, []) if pid not in known and year in npb_seasons(npb[pid])]
        if len(pids) == 1 and year >= 2008:
            p = npb[pids[0]]
            moves.append({
                "player_id": pids[0], "name": p["name"], "mlb_id": None, "mlb_name": None, "birth": p.get("birth"),
                "npb_team_before": npb_seasons(p).get(year), "left_after": year, "route": "posting",
                "mlb_first": None, "mlb_last": None, "returned": None, "npb_team_after": None,
            })
    for mm in MANUAL_MOVES:
        p = npb[mm["player_id"]]
        seasons = npb_seasons(p)
        after = [y for y in seasons if y > mm["left_after"]]
        moves.append({
            "player_id": mm["player_id"], "name": p["name"], "mlb_id": None, "mlb_name": None, "birth": p.get("birth"),
            "npb_team_before": seasons.get(mm["left_after"]), "left_after": mm["left_after"], "route": mm["route"],
            "mlb_first": None, "mlb_last": None, "returned": min(after) if after else None,
            "npb_team_after": seasons.get(min(after)) if after else None,
        })
    moves.sort(key=lambda x: (x["left_after"], x["name"]))
    (DATA / "mlb_moves.json").write_text(json.dumps(moves, ensure_ascii=False, indent=1), encoding="utf-8")
    (DATA / "mlb_stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  -> data/mlb_moves.json ({len(moves)}人), data/mlb_stats.json")


if __name__ == "__main__":
    main()
