#!/usr/bin/env python3
"""NPB公式サイト(npb.jp)から2008年以降のデータを収集する。

段階(stage)ごとに実行でき、取得したHTMLは cache/ に保存するので再実行時は通信しない。

  python collect.py rosters   # 年度×球団の在籍選手(選手ID付き)
  python collect.py players   # 選手個別ページ(投打・生年月日・経歴・1軍年度別成績)
  python collect.py teamstats # 球団別 個人打撃/投手/守備 (1軍・2軍)
  python collect.py awards    # ゴールデングラブ賞ほか表彰
  python collect.py drafts    # ドラフト指名一覧(本指名・育成)
  python collect.py link      # 球団別成績・ドラフトを選手IDに突合 → unmatched を出力
  python collect.py all       # 上記を順に全部

出力は out/ 以下のJSON(UTF-8)。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import unicodedata
from collections import defaultdict
from pathlib import Path

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / "cache"
OUT = ROOT / "out"
UA = "Mozilla/5.0 (personal NPB sim data collector)"
DELAY = 1.0  # 秒。サーバー負荷への配慮

_session = requests.Session()
_session.headers["User-Agent"] = UA
_last = 0.0


# ---------------------------------------------------------------- 通信・キャッシュ
def fetch(url: str) -> str | None:
    """URLのHTMLを返す。キャッシュ優先。404はNoneをキャッシュ('')する。"""
    global _last
    key = re.sub(r"^https?://", "", url).rstrip("/")
    key = re.sub(r"[^A-Za-z0-9._/-]", "_", key)
    path = CACHE / (key + ("" if key.endswith(".html") else "/index.html"))
    if path.exists():
        return decode(path.read_bytes()) or None
    wait = DELAY - (time.time() - _last)
    if wait > 0:
        time.sleep(wait)
    for attempt in range(3):
        try:
            r = _session.get(url, timeout=30)
            _last = time.time()
            break
        except requests.RequestException as e:
            print(f"  retry {attempt + 1}: {url} ({e})", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    else:
        raise RuntimeError(f"fetch failed: {url}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if r.status_code == 404:
        path.write_bytes(b"")
        return None
    r.raise_for_status()
    path.write_bytes(r.content)
    return decode(r.content)


def decode(raw: bytes) -> str:
    """npb.jpはUTF-8、古いページはShift_JISの場合がある。"""
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("cp932", errors="replace")


def soup(url: str) -> BeautifulSoup | None:
    html = fetch(url)
    return BeautifulSoup(html, "html.parser") if html else None


def save(name: str, data) -> None:
    OUT.mkdir(exist_ok=True)
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  -> out/{name}")


def load(name: str):
    return json.loads((OUT / name).read_text(encoding="utf-8"))


# ---------------------------------------------------------------- 共通ユーティリティ
_VARIANTS = str.maketrans({"﨑": "崎", "髙": "高", "濵": "浜", "邊": "辺", "邉": "辺", "德": "徳",
                           "瀨": "瀬", "齋": "斎", "齊": "斉", "櫻": "桜", "澤": "沢", "眞": "真",
                           "﨑": "崎", "塚": "塚", "惠": "恵", "槇": "槙", "ヶ": "ケ"})


def norm_name(s: str) -> str:
    """突合用の名前正規化(空白・中黒除去・NFKC・異体字寄せ)。"""
    s = unicodedata.normalize("NFKC", s).translate(_VARIANTS)
    return re.sub(r"[\s・=＝.]+", "", s)


def surname_keys(full: str) -> set[str]:
    """外国人選手のフルネーム 'アレックス・カブレラ' → {'カブレラ', ...} (末尾側の部分)。"""
    parts = [x for x in re.split(r"[・\s=＝.]+", unicodedata.normalize("NFKC", full)) if x]
    return {norm_name("".join(parts[i:])) for i in range(1, len(parts))}


def clean(s: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", s)).strip()


def num(s: str):
    """'123'→123, '.271'→0.271, ''→None。それ以外は文字列のまま。"""
    s = s.strip()
    if s in ("", "-", "--"):
        return None
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        return s


def ip_to_outs(whole, frac) -> int | None:
    """投球回 '89' '.2' → アウト数 269。"""
    if whole is None:
        return None
    if whole == "+":  # アウトを取れず降板
        return 0
    f = str(frac or "").strip().lstrip(".")
    return int(whole) * 3 + (int(f) if f.isdigit() else 0)


def direct_cells(tr):
    return [c.get_text(" ", strip=True) for c in tr.find_all(["th", "td"], recursive=False)]


def own_rows(table):
    """入れ子テーブルの行を除いた、そのテーブル自身の行。"""
    return [tr for tr in table.find_all("tr") if tr.find_parent("table") is table]


def years(args) -> range:
    return range(args.start, args.end + 1)


# ---------------------------------------------------------------- rosters
def stage_rosters(args):
    """/bis/players/search/yearly/{年}/{球団ID}/ から年度別在籍選手を取得。"""
    idx = soup("https://npb.jp/bis/players/all/index.html")
    teams = defaultdict(list)  # year -> [(team_id, team_name)]
    for a in idx.find_all("a", href=True):
        m = re.search(r"/search/yearly/(\d{4})/(\d+)/", a["href"])
        if m and args.start <= int(m.group(1)) <= args.end:
            teams[int(m.group(1))].append((m.group(2), clean(a.get_text())))
    rosters = []
    for y in years(args):
        print(f"[rosters] {y}: {len(teams[y])} teams")
        for tid, tname in teams[y]:
            s = soup(f"https://npb.jp/bis/players/search/yearly/{y}/{tid}/")
            if not s:
                print(f"  missing roster {y}/{tid}", file=sys.stderr)
                continue
            for a in s.find_all("a", href=True):
                m = re.search(r"/bis/players/(\d{8})\.html", a["href"])
                if not m:
                    continue
                text = clean(a.get_text(" "))
                debut = re.search(r"(\d{4})年\s*公式戦初出場", text)
                name = re.sub(r"\s*\d{4}年.*$", "", text)
                rosters.append({
                    "year": y, "team_id": tid, "team": tname,
                    "player_id": m.group(1), "name": name,
                    "debut_year": int(debut.group(1)) if debut else None,
                })
    # 当年(シーズン中)は年度別名簿が未掲載なので、現役選手名簿(育成含む)で補う
    for y in years(args):
        if teams[y]:
            continue
        act = soup("https://npb.jp/bis/players/active/index.html")
        codes = re.findall(r"rst_([a-z]+)\.html", str(act))
        print(f"[rosters] {y}: 年度別名簿なし → 現役選手名簿 {len(set(codes))} 球団")
        for code in dict.fromkeys(codes):
            s = soup(f"https://npb.jp/bis/players/active/rst_{code}.html")
            for a in s.select("a.player_unit_1"):
                m = re.search(r"/bis/players/(\d{8})\.html", a.get("href", ""))
                pos = clean(a.find(class_="pos").get_text(" ")) if a.find(class_="pos") else ""
                pm = re.match(r"(\d+)\s*(\S+)", pos)
                rosters.append({
                    "year": y, "team_id": None, "team": clean(a.find(class_="team").get_text()),
                    "player_id": m.group(1), "name": clean(a.find(class_="name").get_text()),
                    "debut_year": None, "number": pm.group(1) if pm else None,
                    "pos": pm.group(2) if pm else None, "ikusei": "育成" in pos,
                })
    save("rosters.json", rosters)
    ids = {r["player_id"] for r in rosters}
    print(f"  {len(rosters)} roster rows, {len(ids)} unique players")


# ---------------------------------------------------------------- players
def parse_stat_table(table):
    rows = own_rows(table)
    if not rows:
        return None, []
    header = direct_cells(rows[0])
    out = []
    for tr in rows[1:]:
        tds = tr.find_all(["th", "td"], recursive=False)
        if not tds:
            continue
        rec = {}
        for h, td in zip(header, tds):
            if h == "投球回":
                inner = td.find("table")
                if inner:
                    parts = [c.get_text(strip=True) for c in inner.find_all(["th", "td"])]
                    rec["outs"] = ip_to_outs(num(parts[0]), parts[1] if len(parts) > 1 else "")
                else:
                    t = td.get_text(" ", strip=True).split()
                    rec["outs"] = ip_to_outs(num(t[0]), t[1] if len(t) > 1 else "") if t else None
                continue
            val = td.get_text(" ", strip=True)
            rec[h] = norm_name(val) if h == "所属球団" else num(val)
        if rec.get("年度") is not None:
            out.append(rec)
    return header, out


def stage_players(args):
    rosters = load("rosters.json")
    ids = sorted({r["player_id"] for r in rosters})
    players = {}
    for i, pid in enumerate(ids, 1):
        if i % 100 == 0 or i == len(ids):
            print(f"[players] {i}/{len(ids)}")
        s = soup(f"https://npb.jp/bis/players/{pid}.html")
        if not s:
            continue
        title = s.title.get_text() if s.title else ""
        p = {"player_id": pid, "name": clean(title.split("（")[0]), "bio": {},
             "batting": [], "pitching": [], "other_tables": []}
        for t in s.find_all("table"):
            if t.find_parent("table"):
                continue
            cls = " ".join(t.get("class") or [])
            tid = t.get("id") or ""
            if "tablefix" in tid or "tablefix" in cls:
                _, rows = parse_stat_table(t)
                if "tablefix_b" in (tid + cls):
                    p["batting"] = rows
                elif "tablefix_p" in (tid + cls):
                    p["pitching"] = rows
                else:
                    p["other_tables"].append({"id": tid, "class": cls, "rows": rows})
            elif not p["bio"]:
                for tr in own_rows(t):
                    c = direct_cells(tr)
                    if len(c) == 2:
                        p["bio"][c[0]] = clean(c[1])
        b = p["bio"]
        m = re.match(r"(.)投(.)打", b.get("投打", ""))
        if m:
            p["throws"], p["bats"] = m.group(1), m.group(2)
        m = re.match(r"(\d+)cm／(\d+)kg", b.get("身長／体重", "").replace("/", "／"))
        if m:
            p["height"], p["weight"] = int(m.group(1)), int(m.group(2))
        m = re.match(r"(\d{4})年(\d{1,2})月(\d{1,2})日", b.get("生年月日", ""))
        if m:
            p["birth"] = f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
        players[pid] = p
    save("players.json", players)


# ---------------------------------------------------------------- teamstats
def parse_team_table_v2(table, kind):
    """2025年以降の形式: 見出し1列目が「選手」、記号(*,+)は名前に含む、守備は位置ごとに別テーブル。"""
    rows = own_rows(table)
    header = [re.sub(r"\s+", "", x) for x in direct_cells(rows[0])]
    pos = None
    if kind == "f":
        h = table.find_previous(["h2", "h3", "h4", "h5", "p"])
        pos = clean(h.get_text()) if h else None
    out = []
    for tr in rows[1:]:
        c = direct_cells(tr)
        if len(c) < 3:
            continue
        m = re.match(r"^([*+]+)\s*(.*)$", c[0])
        rec = {"name": clean(m.group(2) if m else c[0]), "mark": m.group(1) if m else ""}
        if pos:
            rec["pos"] = pos
        for h, v in zip(header[1:], c[1:]):
            if h == "投球回":
                t = v.split()
                rec["outs"] = ip_to_outs(num(t[0]) if t[0] != "+" else "+", t[1] if len(t) > 1 else "") if t else None
            elif h:
                rec[{"ホールド": "ホール"}.get(h, h)] = num(v)
        out.append(rec)
    return out


def parse_team_table(table, kind):
    first = own_rows(table)[:1]
    if first and re.sub(r"\s+", "", (direct_cells(first[0]) or [""])[0]) == "選手":
        return parse_team_table_v2(table, kind)
    rows = own_rows(table)
    header, out, pos = None, [], None
    for tr in rows:
        c = direct_cells(tr)
        if not c:
            continue
        if header is None:
            c = [re.sub(r"\s+", "", x) for x in c]
        if kind == "f" and any(x.startswith("【") for x in c):
            pos = next(x for x in c if x.startswith("【")).strip("【】")
            if any(c[1:]) and header is None:
                header = c
            continue
        if header is None and len(c) > 3 and any(x in c for x in ("試合", "登板")):
            header = c
            continue
        if header is None or len(c) < 3:
            continue
        mark, name, vals = c[0], c[1], c[2:]
        hs = header[2:] if kind != "f" else header[1:]
        if kind == "f":
            vals = c[2:]
        rec = {"name": clean(name), "mark": mark}
        if pos:
            rec["pos"] = pos
        i = 0
        while i < len(hs) and i < len(vals):
            h = hs[i]
            if h == "投球回" and i + 1 < len(hs) and hs[i + 1] == "":
                rec["outs"] = ip_to_outs(num(vals[i]), vals[i + 1])
                i += 2
                continue
            if h:
                rec[h.replace("｜", "ー")] = num(vals[i])
            i += 1
        out.append(rec)
    return out


def stage_teamstats(args):
    result = []
    for y in years(args):
        idx = fetch(f"https://npb.jp/bis/{y}/stats/")
        codes = sorted(set(re.findall(r"idb1_([a-z]+)\.html", idx or "")))
        print(f"[teamstats] {y}: {codes}")
        team_names = {}
        for code in codes:
            for level in (1, 2):
                for kind in ("b", "p", "f"):
                    url = f"https://npb.jp/bis/{y}/stats/id{kind}{level}_{code}.html"
                    s = soup(url)
                    if not s:
                        continue
                    title = s.title.get_text() if s.title else ""
                    m = re.match(r"\d{4}年度\s*(.+?)\s+個人", title)
                    league = re.search(r"（(.+?)）", title)
                    if level == 1 and m:
                        team_names[code] = m.group(1)
                    rows = []
                    for t in s.find_all("table"):
                        if not t.find_parent("table"):
                            rows += parse_team_table(t, kind)
                    for r in rows:
                        r.update(year=y, code=code, level=level, kind=kind,
                                 team=team_names.get(code), farm_team=m.group(1) if m and level == 2 else None,
                                 league=league.group(1) if league else None)
                    result += rows
    save("teamstats.json", result)


# ---------------------------------------------------------------- awards
def stage_awards(args):
    out = []
    for y in years(args):
        for page in ("", "glove.html"):
            s = soup(f"https://npb.jp/award/{y}/{page}")
            if not s:
                continue
            for a in s.select("a.player_unit_1"):
                m = re.search(r"/bis/players/(\d{8})\.html", a.get("href", ""))
                h6 = a.find("h6")
                name = a.find(class_="name")
                team = a.find(class_="team")
                league = a.find_previous("h5")
                award = a.find_previous(["h3", "h4"])
                out.append({
                    "year": y,
                    "award": "ゴールデングラブ賞" if page == "glove.html" else (clean(award.get_text()) if award else None),
                    "league": clean(league.get_text()) if league else None,
                    "category": clean(h6.get_text()) if h6 else None,
                    "player_id": m.group(1) if m else None,
                    "name": clean(name.get_text()) if name else None,
                    "team": clean(team.get_text()).strip("（）") if team else None,
                })
        print(f"[awards] {y}: {sum(1 for r in out if r['year'] == y)}")
    save("awards.json", out)


# ---------------------------------------------------------------- drafts
def stage_drafts(args):
    """draft.npb.jp/draft/{年}/draftlist_*.html。ドラフト年=開催年(入団は翌年)。"""
    out = []
    for y in range(args.start - 1, args.end + 1):
        top = fetch(f"https://draft.npb.jp/draft/{y}/")
        codes = sorted(set(re.findall(r"draftlist_([a-z]+)\.html", top or "")))
        for code in codes:
            s = soup(f"https://draft.npb.jp/draft/{y}/draftlist_{code}.html")
            if not s:
                continue
            title = s.title.get_text() if s.title else ""
            for t in s.find_all("table"):
                head = t.find_previous(["h3", "h4", "h5", "caption"])
                section = clean(head.get_text()) if head else ""
                for tr in own_rows(t):
                    c = [clean(x) for x in direct_cells(tr)]
                    if len(c) < 4 or not re.match(r"\d+(位|巡目)", c[0]):
                        continue
                    if "選択権なし" in c[1] or not c[1]:
                        continue
                    out.append({
                        "draft_year": y, "code": code, "section": section,
                        "page_title": clean(title.split("|")[0]),
                        "round": c[0], "name": c[1], "pos": c[2].replace(" ", ""),
                        "school": c[3],
                        "ikusei": "育成" in section or "育成" in c[0],
                    })
        print(f"[drafts] {y}: {sum(1 for r in out if r['draft_year'] == y)} picks")
    save("drafts.json", out)


# ---------------------------------------------------------------- link
def stage_link(args):
    """球団別成績・ドラフトの名前を選手IDへ突合する。overrides.json で手動補正可能。"""
    rosters = load("rosters.json")
    teamstats = load("teamstats.json")
    overrides_path = ROOT / "overrides.json"
    overrides = json.loads(overrides_path.read_text(encoding="utf-8")) if overrides_path.exists() else {}

    by_year_team = defaultdict(dict)  # (year, 正規化球団名) -> {正規化選手名: id}
    by_name = defaultdict(set)
    by_surname = defaultdict(dict)
    for r in rosters:
        by_year_team[(r["year"], norm_name(r["team"]))][norm_name(r["name"])] = r["player_id"]
        by_name[norm_name(r["name"])].add(r["player_id"])
        for k in surname_keys(r["name"]):
            by_surname[(r["year"], norm_name(r["team"]))].setdefault(k, set()).add(r["player_id"])

    roster_teams = defaultdict(set)
    for r in rosters:
        roster_teams[r["year"]].add(norm_name(r["team"]))

    def team_key(year, team):
        """成績ページと名簿で球団名が揺れる(例: 東京ヤクルト/ヤクルト)ので末尾一致で寄せる。"""
        t = norm_name(team or "")
        if t in roster_teams[year]:
            return (year, t)
        hits = [x for x in roster_teams[year] if x.endswith(t) or t.endswith(x)]
        return (year, hits[0] if len(hits) == 1 else t)

    unmatched = defaultdict(int)
    for r in teamstats:
        key = f'{r["year"]}|{r["team"]}|{r["name"]}'
        tk = team_key(r["year"], r["team"])
        pid = overrides.get(key) or by_year_team[tk].get(norm_name(r["name"]))
        if not pid and len(by_name.get(norm_name(r["name"]), ())) == 1:
            pid = next(iter(by_name[norm_name(r["name"])]))  # 移籍年の表記揺れ等
        if not pid:  # 外国人: 成績表は姓のみ、名簿はフルネーム
            cands = by_surname[tk].get(norm_name(r["name"]), set())
            if not cands:  # 成績表側がフルネーム(サンティアゴ・ラミレス)、名簿がS.ラミレス
                for k in surname_keys(r["name"]):
                    cands = by_surname[tk].get(k, set())
                    if cands:
                        break
            if len(cands) == 1:
                pid = next(iter(cands))
        r["player_id"] = pid
        if not pid and r["level"] == 1:
            unmatched[key] += 1
    save("teamstats_linked.json", teamstats)
    save("unmatched_1軍.json", sorted(unmatched))
    farm_only = {f'{r["year"]}|{r["team"]}|{r["name"]}' for r in teamstats if not r["player_id"] and r["level"] == 2}
    print(f"  1軍未突合: {len(unmatched)} / 2軍のみ(ID無し): {len(farm_only)}")


# ---------------------------------------------------------------- main
STAGES = {
    "rosters": stage_rosters, "players": stage_players, "teamstats": stage_teamstats,
    "awards": stage_awards, "drafts": stage_drafts, "link": stage_link,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", choices=[*STAGES, "all"])
    ap.add_argument("--start", type=int, default=2008)
    ap.add_argument("--end", type=int, default=2025)
    ap.add_argument("--out", default="out", help="出力先ディレクトリ(collect.py からの相対)")
    args = ap.parse_args()
    global OUT
    OUT = ROOT / args.out
    for name in (STAGES if args.stage == "all" else [args.stage]):
        STAGES[name](args)


if __name__ == "__main__":
    main()
