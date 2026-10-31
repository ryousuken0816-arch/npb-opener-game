#!/usr/bin/env python3
"""アマ選手（ドラフト候補・プロの成績が無い新人）の初期能力を、有識者の評価を主な根拠にして作る
（docs/AUTORUN.md 作業16・17。ユーザー指示 2026-11-01「成績よりも有識者の評価を総合して決める」）。

    python tools/amateur_ratings.py rookies --draft-year 2026   # 2026年秋の新人を generated/ratings/2027_pre.json に入れる
    python tools/amateur_ratings.py carry --year 2027           # 2027_post（引き継ぎ）と 2028_pre（＋2027年の候補）を作る

作り方（tools/README.md「アマ選手の初期能力」）：
1. 下地：既存の新人の初期能力の仕組み（compute_ratings.py の prior_pctl_for＝区分＋ドラフト順位）で作られた、
   1年前の新人（generated/ratings/<基準年>_pre.json のうち前年秋の指名選手）の能力を、
   「投手か・区分（高校／大学／社会人）・順位の帯」ごとに平均したもの
2. 順位の帯は、史実の指名（2026年）は実際の順位と有識者の格付け（scout.grade）を半々、
   候補（2027年）は格付けだけで決める（S・A＝1位、B＝2〜3位、C＝4〜5位、D＝育成）
3. 有識者の評価の長所・短所（scout.strengths / weaknesses）の言葉で個別の能力を上下し、
   球速（最速−MAX_TO_AVG_KMH）・50m走・遠投などの数字は補助として少し効かせる
入力は data/amateur/<年>.json（形式は data/amateur/README.md）。
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATINGS = ROOT / "generated" / "ratings"
AMATEUR = ROOT / "data" / "amateur"

## 下地にする新人の年（<年>_pre.json の前年秋の指名選手）。2025年秋の新人は全員が npb.jp の名簿にいる
TEMPLATE_YEAR = 2026
RANKS = [(90, "S"), (80, "A"), (70, "B"), (60, "C"), (50, "D"), (40, "E"), (20, "F"), (0, "G")]
## 順位の帯（下地の平均を取る単位）
BANDS = {1: "1", 2: "2-3", 3: "2-3", 4: "4-5", 5: "4-5"}
BAND_LEVEL = {"1": 4, "2-3": 3, "4-5": 2, "6-": 1, "育成": 0}
GRADE_LEVEL = {"S": 5, "A": 4, "B": 3, "C": 2, "D": 0}
## 格付けが帯より上（下）なら全能力を1段階あたりこれだけ上げる（下げる）。S は帯「1」の上に1段
GRADE_STEP = 3
## 長所・短所の言葉 → 能力（投手・野手）。1語あたりの加減と、1つの能力の上限
STRENGTH_BONUS = 6
WEAKNESS_PENALTY = -5
TRAIT_CAP = 12
PITCH_WORDS = {
    "bb9": ["制球", "コントロール", "四球", "安定感", "まとまり"],
    "k9": ["奪三振", "三振", "変化球", "キレ", "フォーク", "スライダー", "カーブ", "チェンジアップ", "スプリット",
           "ツーシーム", "カット", "決め球", "空振り"],
    "stamina": ["スタミナ", "完投", "タフ", "イニング", "馬力", "連投"],
    "hr9": ["球威", "低め", "ゴロ", "重い"],
    "overall": ["完成度", "即戦力", "総合力", "投球術", "実戦", "マウンド度胸", "度胸", "修正力"],
    "velocity": ["球速", "直球", "ストレート", "剛速球", "速球", "豪速球", "最速"],
}
BAT_WORDS = {
    "power": ["長打", "パワー", "本塁打", "飛距離", "強打", "スラッガー", "長距離"],
    "meet": ["ミート", "巧打", "打撃", "バットコントロール", "コンタクト", "安打", "広角", "対応力"],
    "eye": ["選球", "出塁", "四球"],
    "speed": ["俊足", "走力", "足", "盗塁", "走塁", "脚力"],
    "defense": ["守備", "守備範囲", "グラブ", "フットワーク", "捕球", "リード", "キャッチング", "ブロッキング"],
    "arm": ["強肩", "肩", "送球", "スローイング"],
}
## 最速→平均球速の差（km/h）。能力値の球速はシーズンの平均球速の目安（tools/README.md「球速」）
MAX_TO_AVG_KMH = 5
VELOCITY_MIN, VELOCITY_MAX = 128, 158
## 数字の補助：球速は下地の球速との差1km/hあたり総合を、50m走は6.0秒との差0.1秒あたり走力を、
## 遠投は100mとの差1mあたり肩力を上下する（上限 NUMBER_CAP）
VELO_TO_OVERALL = 0.5
DASH_PER_TENTH = 2.0
THROW_PER_M = 0.3
NUMBER_CAP = 8
## 2026年の新人（すでに compute_ratings の下地がある）は、下地と評価からの値をこの割合で混ぜる（評価側）
ROOKIE_SCOUT_WEIGHT = 0.6


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")


_VARIANTS = str.maketrans({"﨑": "崎", "髙": "高", "濵": "浜", "濱": "浜", "邊": "辺", "邉": "辺", "德": "徳",
                           "瀨": "瀬", "齋": "斎", "齊": "斉", "櫻": "桜", "澤": "沢", "眞": "真", "槇": "槙"})


def norm_name(s: str) -> str:
    s = re.sub("[\U000E0100-\U000E01EF︀-️]", "", unicodedata.normalize("NFKC", s or ""))
    return re.sub(r"[\s・=＝.]+", "", s.translate(_VARIANTS))


def rank_of(v: int) -> str:
    return next(r for th, r in RANKS if v >= th)


def category_of(school: str, category: str | None = None) -> str:
    """compute_ratings.draft_category と同じ区分（高校／大学／社会人。独立・その他は社会人）"""
    if category in ("高校", "大学"):
        return category
    if category:
        return "社会人"
    if school.endswith("高") or "高校" in school:
        return "高校"
    return "大学" if "大" in school else "社会人"


def round_band(round_text: str, ikusei: bool) -> str:
    if ikusei:
        return "育成"
    m = re.match(r"(\d+)", round_text or "")
    return BANDS.get(int(m.group(1)), "6-") if m else "6-"


def grade_band(grade: str) -> str:
    return {"S": "1", "A": "1", "B": "2-3", "C": "4-5", "D": "育成"}.get(grade or "C", "4-5")


# ---------------------------------------------------------------- 下地
class Templates:
    """1年前の新人の能力を（投手か, 区分, 帯）ごとに平均したもの"""

    def __init__(self, ratings: dict, draft_year: int):
        self.groups: dict[tuple, list[dict]] = defaultdict(list)
        for p in ratings["players"]:
            text = str(p.get("draft") or "")
            if not text.startswith(f"{draft_year}年") or not p.get("primary_pos"):
                continue
            ikusei = "育成" in text
            m = re.search(r"ドラフト(\d+)位", text)
            band = round_band(f"{m.group(1)}位" if m else "", ikusei)
            school = str(p.get("career") or "").split(" - ")[-1]
            self.groups[(bool(p["is_pitcher"]), category_of(school), band)].append(p)

    def pick(self, pitcher: bool, category: str, band: str) -> list[dict]:
        """近い組を探す（区分→帯の順にゆるめる）"""
        order = list(BAND_LEVEL)
        near = sorted(order, key=lambda b: abs(BAND_LEVEL[b] - BAND_LEVEL[band]))
        for b in near:
            for c in [category] + [x for x in ("社会人", "大学", "高校") if x != category]:
                if self.groups.get((pitcher, c, b)):
                    return self.groups[(pitcher, c, b)]
        return [p for (pit, _, _), ps in self.groups.items() if pit == pitcher for p in ps]

    @staticmethod
    def mean_entry(ps: list[dict]) -> dict:
        """先頭の選手の形を写し、能力の値を組の平均にする"""
        base = copy.deepcopy(ps[0])
        for part, keys in (("batting", ["meet", "power", "eye", "speed", "defense", "arm"]),
                           ("pitching", ["overall", "stamina", "k9", "bb9", "hr9"])):
            if not isinstance(base.get(part), dict):
                continue
            for k in keys:
                vals = [p[part]["ratings"][k]["value"] for p in ps if isinstance(p.get(part), dict)
                        and isinstance(p[part]["ratings"].get(k), dict) and p[part]["ratings"][k].get("value") is not None]
                if vals and k in base[part]["ratings"]:
                    v = round(sum(vals) / len(vals))
                    base[part]["ratings"][k] = {"value": v, "rank": rank_of(v)}
        if isinstance(base.get("pitching"), dict):
            kmh = [p["pitching"]["velocity"]["kmh"] for p in ps if isinstance(p.get("pitching"), dict)
                   and isinstance(p["pitching"].get("velocity"), dict)]
            if kmh:
                base["pitching"]["velocity"] = {"kmh": round(sum(kmh) / len(kmh)), "source": "provisional"}
        trajs = [p["batting"].get("trajectory", 2) for p in ps if isinstance(p.get("batting"), dict)]
        if trajs and isinstance(base.get("batting"), dict):
            base["batting"]["trajectory"] = round(sum(trajs) / len(trajs))
        return base


# ---------------------------------------------------------------- 評価で補正
def trait_deltas(a: dict, pitcher: bool) -> dict[str, float]:
    words = PITCH_WORDS if pitcher else BAT_WORDS
    scout = a.get("scout") or {}
    out: dict[str, float] = defaultdict(float)
    for items, step in ((scout.get("strengths") or [], STRENGTH_BONUS), (scout.get("weaknesses") or [], WEAKNESS_PENALTY)):
        for text in items:
            for key, keys in words.items():
                if any(w in str(text) for w in keys):
                    out[key] += step
    return {k: max(-TRAIT_CAP, min(TRAIT_CAP, v)) for k, v in out.items()}


def set_value(block: dict, key: str, value: float) -> None:
    v = max(1, min(100, round(value)))
    block[key] = {"value": v, "rank": rank_of(v)}


def scouted_entry(a: dict, templates: Templates, band: str, level_gap: float) -> dict:
    """評価からの能力（下地の平均＋格付けの段差＋長所・短所＋数字の補助）"""
    pitcher = a["pos"] == "投手"
    category = category_of(a.get("school") or "", a.get("category"))
    e = Templates.mean_entry(templates.pick(pitcher, category, band))
    shift = GRADE_STEP * level_gap
    deltas = trait_deltas(a, pitcher)
    if pitcher:
        r = e["pitching"]["ratings"]
        base_kmh = e["pitching"]["velocity"]["kmh"]
        kmh = base_kmh
        if a.get("max_kmh"):
            kmh = max(VELOCITY_MIN, min(VELOCITY_MAX, int(a["max_kmh"]) - MAX_TO_AVG_KMH))
        kmh += 1 if deltas.get("velocity", 0) > 0 else 0
        velo_bonus = max(-NUMBER_CAP, min(NUMBER_CAP, VELO_TO_OVERALL * (kmh - base_kmh)))
        for k in list(r):
            extra = deltas.get(k, 0) + (velo_bonus if k in ("overall", "k9") else 0)
            set_value(r, k, r[k]["value"] + shift + extra)
        e["pitching"]["velocity"] = {"kmh": int(kmh), "source": "amateur" if a.get("max_kmh") else "provisional"}
        e["pitching"]["role"] = "先発" if "先発" in str(a.get("pos_detail") or "") else e["pitching"].get("role", "救援")
    else:
        r = e["batting"]["ratings"]
        numbers = {}
        if a.get("dash50_s"):
            numbers["speed"] = DASH_PER_TENTH * (6.0 - float(a["dash50_s"])) * 10
        if a.get("long_throw_m"):
            numbers["arm"] = THROW_PER_M * (float(a["long_throw_m"]) - 100)
        for k in list(r):
            extra = deltas.get(k, 0) + max(-NUMBER_CAP, min(NUMBER_CAP, numbers.get(k, 0)))
            set_value(r, k, r[k]["value"] + shift + extra)
        if deltas.get("power", 0) > 0:
            e["batting"]["trajectory"] = min(4, int(e["batting"].get("trajectory", 2)) + 1)
    return e


def amateur_fields(a: dict, draft_year: int) -> dict:
    scout = a.get("scout") or {}
    return {"draft_year": draft_year, "intro": a.get("intro"), "grade": scout.get("grade") or a.get("eval_rank"),
            "type": scout.get("type"), "projected": a.get("projected"), "fictional": bool(a.get("fictional")),
            "category": a.get("category"), "grade_text": a.get("grade")}


def apply_profile(e: dict, a: dict, pid: str, team, draft_text: str, draft_year: int) -> dict:
    e = copy.deepcopy(e)
    pitcher = a["pos"] == "投手"
    e.update({
        "id": pid, "provisional_id": True, "name": a["name"], "team": team, "team_id": None, "league": None,
        "throws": a.get("throws"), "bats": a.get("bats"),
        "birth": str(a["birth_year"]) if a.get("birth_year") else None,
        "height": a.get("height"), "weight": a.get("weight"), "draft": draft_text, "career": a.get("school"),
        "is_pitcher": pitcher, "primary_pos": "投手" if pitcher else a["pos"],
        "fielding": {}, "amateur": amateur_fields(a, draft_year),
    })
    if not pitcher:
        e["pitching"] = None
    for part, sample in (("batting", {"pa_1": 0.0, "pa_2": 0.0}), ("pitching", {"outs_1": 0.0, "outs_2": 0.0})):
        if isinstance(e.get(part), dict):
            e[part]["sample"] = sample
    if isinstance(e.get("pitching"), dict):
        e["pitching"]["abilities"] = []
    return e


def blend_into(base: dict, scouted: dict, w: float) -> None:
    """下地（compute_ratings の新人の初期能力）に評価からの値を w の割合で混ぜる"""
    for part in ("batting", "pitching"):
        if not isinstance(base.get(part), dict) or not isinstance(scouted.get(part), dict):
            continue
        for k, r in base[part]["ratings"].items():
            s = scouted[part]["ratings"].get(k)
            if isinstance(r, dict) and r.get("value") is not None and isinstance(s, dict):
                set_value(base[part]["ratings"], k, (1 - w) * r["value"] + w * s["value"])
    if isinstance(base.get("pitching"), dict) and scouted["pitching"]["velocity"]["source"] == "amateur":
        base["pitching"]["velocity"] = scouted["pitching"]["velocity"]
    if isinstance(base.get("batting"), dict):
        base["batting"]["trajectory"] = scouted["batting"].get("trajectory", base["batting"].get("trajectory"))


def amateur_id(draft_year: int, name: str) -> str:
    return f"ama{draft_year}:{norm_name(name)}"


# ---------------------------------------------------------------- コマンド
def cmd_rookies(args) -> None:
    """史実の指名選手（data/<年+1>/drafts.json の当年秋）を <年+1>_pre.json に入れる／補正する"""
    y = args.draft_year
    path = RATINGS / f"{y + 1}_pre.json"
    ratings = load(path)
    templates = Templates(load(RATINGS / f"{TEMPLATE_YEAR}_pre.json"), TEMPLATE_YEAR - 1)
    info = {norm_name(a["name"]): a for a in load(AMATEUR / f"{y}.json")["players"]}
    by_name = {norm_name(p["name"]): p for p in ratings["players"]}
    added = adjusted = 0
    for d in load(ROOT / "data" / str(y + 1) / "drafts.json"):
        if d["draft_year"] != y:
            continue
        a = dict(info.get(norm_name(d["name"]), {}), name=d["name"], pos=d["pos"], school=d["school"])
        grade = (a.get("scout") or {}).get("grade") or a.get("eval_rank")
        band = round_band(d["round"], d["ikusei"])
        level = BAND_LEVEL[band]
        gap = ((GRADE_LEVEL[grade] - level) / 2) if grade in GRADE_LEVEL else 0.0
        scouted = scouted_entry(a, templates, band, gap)
        text = f"{y}年{'育成選手' if d['ikusei'] else ''}ドラフト{re.sub(r'[^0-9]', '', d['round'])}位"
        cur = by_name.get(norm_name(d["name"]))
        if cur is not None and str(cur.get("draft") or "").startswith(f"{y}年"):
            blend_into(cur, scouted, ROOKIE_SCOUT_WEIGHT)
            cur["amateur"] = amateur_fields(a, y)
            adjusted += 1
        else:
            entry = apply_profile(scouted, a, amateur_id(y, d["name"]), d["page_title"], text, y)
            ratings["players"].append(entry)
            added += 1
    dump(path, ratings)
    print(f"[amateur] {y}年秋の新人 -> {path.name}: 追加 {added}・補正 {adjusted}")


def cmd_carry(args) -> None:
    """史実の無い年：<年>_post を <年>_pre から引き継ぎ（成長なし）、<年+1>_pre に <年>の候補を足す"""
    y = args.year
    pre = load(RATINGS / f"{y}_pre.json")
    post = dict(copy.deepcopy(pre), phase="post", carried_from=f"{y}_pre")
    dump(RATINGS / f"{y}_post.json", post)
    nxt = dict(copy.deepcopy(pre), year=y + 1, phase="pre", carried_from=f"{y}_pre")
    # 候補は指名されなければ入団しない。来季の新人は「ドラフト候補」として足し、ゲームのドラフトで行き先が決まる
    templates = Templates(load(RATINGS / f"{TEMPLATE_YEAR}_pre.json"), TEMPLATE_YEAR - 1)
    src = AMATEUR / f"{y}.json"
    n = 0
    if src.exists():
        for a in load(src)["players"]:
            grade = (a.get("scout") or {}).get("grade") or a.get("eval_rank") or "C"
            band = grade_band(grade)
            gap = 1.0 if grade == "S" else 0.0
            e = scouted_entry(a, templates, band, gap)
            nxt["players"].append(apply_profile(e, a, amateur_id(y, a["name"]), "", f"{y}年ドラフト候補", y))
            n += 1
    dump(RATINGS / f"{y + 1}_pre.json", nxt)
    print(f"[amateur] {y}_post（{y}_pre の引き継ぎ）と {y + 1}_pre（＋候補 {n}人）")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("rookies")
    r.add_argument("--draft-year", type=int, required=True)
    c = sub.add_parser("carry")
    c.add_argument("--year", type=int, required=True)
    args = ap.parse_args(argv)
    {"rookies": cmd_rookies, "carry": cmd_carry}[args.cmd](args)


if __name__ == "__main__":
    main()
