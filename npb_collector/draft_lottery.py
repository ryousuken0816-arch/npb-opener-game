#!/usr/bin/env python3
"""ドラフト1巡目の入札・抽選の情報を、各球団の指名一覧ページの注記から作る。

注記の例（draft.npb.jp/draft/<年>/draftlist_<球団>.html の下部）:
  ※1巡目： 藤浪晋太郎投手でオリックス、阪神、東京ヤクルトと重複、抽選で外れる
  ※1巡目（第2回）： オリックスと重複、抽選で確定
  ※1巡目：中日、横浜、読売と競合、抽選で獲得

  python draft_lottery.py

出力: ../data/draft_first_round.json
  [{draft_year, name, pos, school, team_code, bids, bidders, wave}]
  - 1位（1巡目）で指名が確定した選手ごとに1行
  - bids: 1回目の入札でこの選手を指名した球団数（1=単独、2以上=競合）
  - bidders: 1回目の入札で指名した球団（注記の表記のまま＋確定球団）
  - wave: 確定した入札の回（1=1回目の入札で確定、2以上=抽選に外れた後の「外れ1位」）
  - 抽選に外れた選手（他球団が獲得）は、獲得した球団側の行の bidders に入る
  - 2023年以降は npb.jp に注記が無いため draft_lottery_manual.json（ウィキペディアの情報欄の
    最多指名数）で補う（source: "wikipedia"）。この年は競合しなかった外れ1位の wave が分からず 1 になる。
    wave が2以上の行の bids は、その回の入札での指名球団数
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

from bs4 import BeautifulSoup

import collect
from collect import norm_name

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"

NOTE = re.compile(r"※\s*[1１]巡目(?:（第(\d)回）)?[：:]\s*(.+)")
EVENT = re.compile(r"(?:(.+?)(?:投手|捕手|内野手|外野手)で)?(.+?)と(?:競合|重複)、抽選で(外れる|獲得|確定)")


def load_drafts() -> list[dict]:
    rows = []
    for p in (ROOT / "out" / "drafts.json", ROOT / "out_pre" / "drafts.json"):
        if p.exists():
            rows += json.loads(p.read_text(encoding="utf-8"))
    seen, out = set(), []
    for r in rows:
        k = (r["draft_year"], r["code"], r["round"], r["name"], r["section"])
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


def team_name_of_page(html: str) -> str:
    t = BeautifulSoup(html, "html.parser").title
    return re.sub(r"\s*選択選手一覧.*$", "", t.get_text()).strip() if t else ""


def main():
    drafts = load_drafts()
    firsts = [r for r in drafts if not r["ikusei"] and re.match(r"1(位|巡目)$", r["round"])
              and "高校生" not in r["section"]]  # 2005-2007年の高校生ドラフトは別枠
    firsts_hs = [r for r in drafts if not r["ikusei"] and re.match(r"1(位|巡目)$", r["round"])
                 and "高校生" in r["section"]]

    # (年, 球団コード) -> 注記のイベント
    events = defaultdict(list)
    for (year, code) in sorted({(r["draft_year"], r["code"]) for r in drafts}):
        html = collect.fetch(f"https://draft.npb.jp/draft/{year}/draftlist_{code}.html")
        if not html:
            continue
        text = BeautifulSoup(html, "html.parser").get_text("|", strip=True)
        for part in text.split("|"):
            m = NOTE.search(part)
            if not m:
                continue
            wave = int(m.group(1) or 1)
            e = EVENT.search(m.group(2))
            if not e:
                print(f"  ? {year} {code}: {part}")
                continue
            events[(year, code)].append({
                "wave": wave,
                "player": norm_name(e.group(1)) if e.group(1) else None,  # None = この球団が獲得した選手
                "others": [x.strip() for x in re.split(r"[、,]", e.group(2)) if x.strip()],
                "won": e.group(3) != "外れる",
            })

    # 選手ごとに1回目の入札の指名球団を集める
    bidders = defaultdict(set)  # (年, 正規化名) -> 球団（注記の表記）
    nbids = defaultdict(int)    # (年, 正規化名) -> 入札球団数（注記ごとに「他球団数＋自球団」、その最大）
    for (year, code), evs in events.items():
        pick = next((r for r in firsts + firsts_hs if r["draft_year"] == year and r["code"] == code), None)
        for e in evs:
            name = e["player"] or (norm_name(pick["name"]) if pick else None)
            if not name or e["wave"] != 1:
                continue
            bidders[(year, name)] |= set(e["others"])
            nbids[(year, name)] = max(nbids[(year, name)], len(e["others"]) + 1)

    out = []
    for r in firsts + firsts_hs:
        evs = events.get((r["draft_year"], r["code"]), [])
        won_wave = next((e["wave"] for e in evs if e["won"] and e["player"] is None), None)
        lost_waves = [e["wave"] for e in evs if not e["won"]]
        wave = won_wave or ((max(lost_waves) + 1) if lost_waves else 1)
        key = (r["draft_year"], norm_name(r["name"]))
        b = bidders.get(key, set()) if wave == 1 else set()
        n = nbids.get(key, 1) if wave == 1 else 1
        out.append({
            "draft_year": r["draft_year"], "name": r["name"], "pos": r["pos"], "school": r["school"],
            "team_code": r["code"], "section": r["section"],
            "bids": n, "bidders": sorted(b), "wave": wave,
        })
    # 2023年以降は npb.jp に注記が無いので、ウィキペディアの記事の情報欄（最多指名数）から補う
    manual_path = ROOT / "draft_lottery_manual.json"
    if manual_path.exists():
        manual = {(m["draft_year"], norm_name(m["name"])): m
                  for m in json.loads(manual_path.read_text(encoding="utf-8"))}
        for r in out:
            m = manual.get((r["draft_year"], norm_name(r["name"])))
            if m:
                r["bids"], r["wave"], r["source"] = m["bids"], m["wave"], "wikipedia"
    out.sort(key=lambda x: (x["draft_year"], -x["bids"], x["wave"]))
    (DATA / "draft_first_round.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  -> data/draft_first_round.json ({len(out)} rows)")


if __name__ == "__main__":
    main()
