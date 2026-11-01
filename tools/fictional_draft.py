"""架空のドラフト候補（2028年以降）と転生選手のひな形（docs/AUTORUN.md 作業22・32）。

2008〜2020年の実際の指名選手（data/<年+1>/drafts.json の当年秋の分）について、区分（高校・大学・社会人・独立）・順位・
守備位置と、「入団時の能力」（<年+1>_pre.json の新人の初期能力）・「その後のピーク」（指名の翌年以降のシーズン後の能力値で
実力がいちばん高い年の値、球速は最速）・ピークの年齢・将来性の点（tools/draft_future.py と同じ式）を集めて
generated/fictional_draft.json に書き出す。Godot の `FictionalDraft`（godot/sim/fictional_draft.gd）が、
史実の無い年のドラフト候補をこの分布から作る。

    python tools/fictional_draft.py

- 学校（`schools`）：2008〜2026年の指名選手の出身校・所属と人数（実在の学校名。強豪校ほど多く出る重みに使う）
- 1年の人数（`class_sizes`）：2016〜2025年の本指名・育成指名の人数
- 転生のもと（`legends`）：2008〜2026年のシーズン後の能力値で、日本人選手の実力のピークが将来性 A 以上（`LEGEND_SCORE`）の選手。
  ピークの年の能力・球速・守備位置・投打・体格・球団・出身校
generated/ratings/ や generated/draft_future.json を作り直したら流し直す。標準ライブラリのみ。
"""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

import growth_coefficients as gc

ROOT = Path(__file__).resolve().parent.parent
RATINGS = ROOT / "generated" / "ratings"
OUT = ROOT / "generated" / "fictional_draft.json"

TEMPLATE_YEARS = range(2008, 2021)  # ピークが見えるまで6年以上ある指名（2020年まで）
SCHOOL_YEARS = range(2008, 2027)
SIZE_YEARS = range(2016, 2026)
LAST_HISTORY_YEAR = 2026  # 2027年以降の <年>_post は写しなので使わない
PLAYING_WEIGHT = 0.6      # tools/draft_future.py と同じ
LEGEND_SCORE = 1.1        # Draft.FUTURE_RANKS の A
FUTURE_NONE = -1.2        # Draft.FUTURE_NONE（1年も能力値ファイルに出てこない＝入団しなかった・すぐ消えた）

# 独立リーグの球団（所属がこれを含めば「独立」）
INDEPENDENT_WORDS = (
    "インディゴソックス", "オリーブガイナーズ", "ファイティングドッグス", "マンダリンパイレーツ", "グランセローズ",
    "ミリオンスターズ", "サンダーバーズ", "ダイヤモンドペガサス", "アルビレックス", "ワイルドラプターズ", "ヒートベアーズ",
    "ゴールデンブレーブス", "アストロプラネッツ", "フューチャードリームス", "サラマンダーズ", "ブルーオーシャンズ",
    "セイバーズ", "ハーキュリーズ", "ブレイブウォリアーズ", "ドリームス", "ホワイトベアーズ", "ネイチャーズ", "ベアーズ",
    "フェニックス", "ビックブルー", "ヴェルディ", "ゼロワン", "オセアン", "BC", "独立",
)


def category_of(school: str) -> str:
    if any(w in school for w in INDEPENDENT_WORDS):
        return "独立"
    if school.endswith("高") or "高校" in school or "高等学校" in school:
        return "高校"
    if "大学" in school or school.endswith("大"):
        return "大学"
    return "社会人"


def school_name(school: str) -> str:
    """表記ゆれをそろえる（「明治大学」→「明治大」、「〇〇高校」→「〇〇高」）"""
    school = school.strip()
    for long, short in (("高等学校", "高"), ("高校", "高"), ("大学", "大")):
        if school.endswith(long):
            return school[: -len(long)] + short
    return school


def round_of(text: str) -> int:
    m = re.search(r"\d+", text or "")
    return int(m.group()) if m else 1


def band_of(rnd: int, ikusei: bool) -> str:
    """順位の帯（作るときの層）"""
    if ikusei:
        return "育成"
    if rnd == 1:
        return "1"
    if rnd <= 3:
        return "2-3"
    if rnd <= 5:
        return "4-5"
    return "6-"


def drafts(year: int) -> list[dict]:
    path = ROOT / "data" / str(year + 1) / "drafts.json"
    if not path.exists():
        return []
    rows = json.loads(path.read_text(encoding="utf-8"))
    return [d for d in rows if int(d.get("draft_year", 0)) == year and not str(d.get("name", "")).startswith("(")]


def norm(s: str) -> str:
    s = s.replace(" ", "").replace("　", "").replace("・", "")
    for a, b in (("﨑", "崎"), ("髙", "高"), ("濵", "浜"), ("邊", "辺"), ("邉", "辺"), ("德", "徳"),
                 ("瀨", "瀬"), ("齋", "斎"), ("齊", "斉"), ("櫻", "桜"), ("澤", "沢"), ("眞", "真")):
        s = s.replace(a, b)
    return s


def score_of(p: dict) -> float | None:
    side = gc.side_of(p)
    if side is None:
        return None
    z, playing = gc.ability(p, side)
    return z + PLAYING_WEIGHT * playing


def kmh_of(p: dict) -> float | None:
    pit = p.get("pitching")
    if isinstance(pit, dict) and isinstance(pit.get("velocity"), dict) and pit["velocity"].get("kmh"):
        return float(pit["velocity"]["kmh"])
    return None


def peak_values(p: dict) -> dict:
    """Growth の peak の形（野手 meet/power/eye/speed/defense/arm、投手 k9/bb9/hr9/stamina/velocity/overall）"""
    side = gc.side_of(p)
    out = {}
    keys = gc.BATTING_KEYS if side == "B" else ["overall", "stamina", "k9", "bb9", "hr9"]
    for k in keys:
        v = gc.value_of(p, side, k)
        if v is not None:
            out[k] = round(v)
    if side == "P" and kmh_of(p) is not None:
        out["velocity"] = round(kmh_of(p))
    return out


def strip(p: dict) -> dict:
    q = {k: v for k, v in p.items() if k not in ("id", "name", "team", "team_id", "league", "birth", "draft", "career",
                                                  "provisional_id", "hist_team")}
    for side in ("batting", "pitching"):
        if isinstance(q.get(side), dict):
            q[side] = {k: v for k, v in q[side].items() if k != "detail"}
    return q


def main() -> None:
    post = {}
    for y in range(2008, LAST_HISTORY_YEAR + 1):
        path = RATINGS / f"{y}_post.json"
        if path.exists():
            post[y] = json.loads(path.read_text(encoding="utf-8"))["players"]
    # 選手ID → 年 → 選手（シーズン後）
    by_id: dict[str, dict[int, dict]] = {}
    by_name: dict[str, list[dict]] = {}
    for y, players in post.items():
        for p in players:
            by_id.setdefault(p["id"], {})[y] = p
            by_name.setdefault(norm(p["name"]), []).append((y, p))

    schools: dict[tuple[str, str], int] = Counter()
    for y in SCHOOL_YEARS:
        for d in drafts(y):
            school = school_name(str(d.get("school", "")))
            if school:
                schools[(category_of(school), school)] += 1

    sizes = {}
    for y in SIZE_YEARS:
        rows = drafts(y)
        sizes[str(y)] = {"reg": sum(1 for d in rows if not d.get("ikusei")), "ikusei": sum(1 for d in rows if d.get("ikusei"))}

    templates = []
    for y in TEMPLATE_YEARS:
        pre_path = RATINGS / f"{y + 1}_pre.json"
        if not pre_path.exists():
            continue
        pre = {}
        for p in json.loads(pre_path.read_text(encoding="utf-8"))["players"]:
            if str(p.get("draft") or "").startswith(f"{y}年"):
                pre[norm(p["name"])] = p
        for d in drafts(y):
            key = norm(d["name"])
            entry = pre.get(key)
            if entry is None or gc.side_of(entry) is None:
                continue
            side = gc.side_of(entry)
            best = None
            best_year = None
            seasons = 0
            top_kmh = kmh_of(entry)
            for yy, p in by_name.get(key, []):
                if yy <= y or not str(p.get("draft") or "").startswith(f"{y}年") or gc.side_of(p) != side:
                    continue
                seasons += 1
                s = score_of(p)
                if s is not None and (best is None or s > best[0]):
                    best = (s, p)
                    best_year = yy
                k = kmh_of(p)
                if k is not None and (top_kmh is None or k > top_kmh):
                    top_kmh = k
            peak_src = best[1] if best else entry
            peak = peak_values(peak_src)
            if side == "P" and top_kmh is not None:
                peak["velocity"] = round(top_kmh)
            age = gc.age_at(peak_src, best_year) if best_year else None
            school = str(d.get("school", "")).strip()
            rnd = round_of(d.get("round", ""))
            ikusei = bool(d.get("ikusei", False))
            templates.append({
                "year": y, "category": category_of(school), "band": band_of(rnd, ikusei), "round": rnd, "ikusei": ikusei,
                "pos": d.get("pos", ""), "side": side,
                "score": round(best[0], 3) if best else FUTURE_NONE, "seasons": seasons,
                "peak_age": age, "peak": peak, "player": strip(entry),
            })

    # 転生のもと：日本人選手（ドラフト歴あり）の実力のピーク
    legends = []
    for pid, years in by_id.items():
        best = None
        for y, p in years.items():
            if not p.get("draft"):
                continue  # 外国人（ドラフト歴なし）は除く
            s = score_of(p)
            if s is not None and (best is None or s > best[0]):
                best = (s, y, p)
        if best is None or best[0] < LEGEND_SCORE:
            continue
        s, y, p = best
        side = gc.side_of(p)
        top_kmh = max((kmh_of(q) or 0.0) for q in years.values()) if side == "P" else 0.0
        peak = peak_values(p)
        if side == "P" and top_kmh > 0:
            peak["velocity"] = round(top_kmh)
        career = str(p.get("career") or "")
        legends.append({
            "id": pid, "name": p["name"], "side": side, "score": round(s, 3), "peak_year": y,
            "peak_team": p.get("team", ""), "peak_age": gc.age_at(p, y), "last_year": max(years),
            "throws": p.get("throws"), "bats": p.get("bats"), "height": p.get("height"), "weight": p.get("weight"),
            "primary_pos": p.get("primary_pos"), "role": (p.get("pitching") or {}).get("role") if side == "P" else None,
            "trajectory": (p.get("batting") or {}).get("trajectory"),
            "schools": [s.strip() for s in career.split(" - ") if s.strip()][:2],
            "abilities": (p.get("pitching") or {}).get("abilities", []) if side == "P" else [],
            "fielding": p.get("fielding") or {}, "peak": peak,
        })
    legends.sort(key=lambda x: -x["score"])

    out = {
        "template_years": [TEMPLATE_YEARS.start, TEMPLATE_YEARS.stop - 1],
        "class_sizes": sizes,
        "schools": [{"category": c, "name": n, "count": k} for (c, n), k in sorted(schools.items(), key=lambda x: -x[1])],
        "templates": templates,
        "legends": legends,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    report(out)


def report(out: dict) -> None:
    t = out["templates"]
    print(OUT, f"{OUT.stat().st_size // 1024}KB", len(t), "templates,", len(out["legends"]), "legends,",
          len(out["schools"]), "schools")
    print("区分:", Counter(x["category"] for x in t))
    print("帯:", Counter(x["band"] for x in t))
    years = len(range(*[out["template_years"][0], out["template_years"][1] + 1]))
    for th, label in ((1.6, "S"), (1.1, "A以上")):
        n = sum(1 for x in t if x["score"] >= th)
        print(f"将来性{label}: {n}人（年 {n / years:.1f}人）")
    late = sum(1 for x in t if x["score"] >= 1.1 and x["band"] in ("6-", "育成"))
    print(f"6位以下・育成から A以上: {late}人（年 {late / years:.2f}人）")
    print("学校の上位:", [(s["name"], s["count"]) for s in out["schools"][:12]])
    print("1年の人数:", out["class_sizes"])


if __name__ == "__main__":
    main()
