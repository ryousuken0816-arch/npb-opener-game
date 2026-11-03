#!/usr/bin/env python3
"""アマ選手（ドラフト候補・プロの成績が無い新人）の初期能力を、有識者の評価を主な根拠にして作る
（docs/AUTORUN.md 作業16・17。ユーザー指示 2026-11-01「成績よりも有識者の評価を総合して決める」）。

    python tools/amateur_ratings.py rookies --draft-year 2026   # 2026年秋の新人を generated/ratings/2027_pre.json に入れる
    python tools/amateur_ratings.py carry --year 2027           # 2027_post（引き継ぎ）と 2028_pre（＋2027年の候補）を作る
    python tools/amateur_ratings.py calibrate --draft-year 2025 # 2025年秋の新人（2026_pre）の入団時をそろえる（作り直しの最後に）

作り方（tools/README.md「アマ選手の初期能力」）：
1. 下地：既存の新人の初期能力の仕組み（compute_ratings.py の prior_pctl_for＝区分＋ドラフト順位）で作られた、
   1年前の新人（generated/ratings/<基準年>_pre.json のうち前年秋の指名選手）の能力を、
   「投手か・区分（高校／大学／社会人）・順位の帯」ごとに平均したもの
2. 順位の帯は、史実の指名（2026年）は実際の順位と有識者の格付け（scout.grade）を半々、
   候補（2027年）は格付けだけで決める（S・A＝1位、B＝2〜3位、C＝4〜5位、D＝育成）
3. 有識者の評価の長所・短所（scout.strengths / weaknesses）の言葉で個別の能力を上下し、
   球速（最速−MAX_TO_AVG_KMH）・50m走・遠投などの数字は補助として少し効かせる
4. 最後に入団時の水準をそろえる（作業62。`calibrate`。rookies・carry も最後に呼ぶ）：評価（S〜D。2025年秋は順位と競合の数から）の順に、
   その年の一番上が78〜81、大卒・社会人の1位が B 前後、高卒の上位は総合 C の60台＋武器（奪三振・パワー・走力）1つを B〜A。
   能力の形は残して全体を上下する。ピーク（growth.peak）は入団時を下回らないようにだけする
5. 守備（作業66。`calibrate` の中）：アマの選手には守備の記録が無いので、守備位置の書き方（pos_detail。2025年秋の新人は翌年の史実の守備位置）と
   評価・長所の言葉・遠投から、本職と近い位置の fielding（守備力・肩）と batting の defense・arm を作る。投手にも投手の守備力を付ける。
   架空の候補（godot/sim/fictional_draft.gd の fill_fielding）と同じ決め方
入力は data/amateur/<年>.json（形式は data/amateur/README.md）。
2026_pre の2025年秋の新人は下地（Templates）にも使うので、2025年秋をそろえるのは作り直しの最後（tools/rebuild_all_ratings.py）。
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import unicodedata
import zlib
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
## 格付けボーナス（目玉・上位新人をしっかり強くする）
GRADE_BONUS = {"S": 10, "A": 7, "B": 4, "C": 1, "D": -2}
GRADE_STEP = 5
## 長所・短所の言葉 → 能力（投手・野手）。1語あたりの加減と、1つの能力の上限（武器を尖らせる）
STRENGTH_BONUS = 9
WEAKNESS_PENALTY = -5
TRAIT_CAP = 18
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
## 最速→平均球速の差（km/h）
MAX_TO_AVG_KMH_HS = 4
MAX_TO_AVG_KMH_UNIV = 3
VELOCITY_MIN, VELOCITY_MAX = 130, 160
## 数字の補助：球速・走力・遠投
VELO_TO_OVERALL = 0.8
DASH_PER_TENTH = 2.5
THROW_PER_M = 0.35
NUMBER_CAP = 12
## 2026年の新人（すでに compute_ratings の下地がある）は、評価からの値をこの割合で混ぜる
ROOKIE_SCOUT_WEIGHT = 0.75


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
    grade = (a.get("scout") or {}).get("grade") or a.get("eval_rank") or "C"
    shift = GRADE_STEP * level_gap + GRADE_BONUS.get(grade, 0)
    deltas = trait_deltas(a, pitcher)
    if pitcher:
        r = e["pitching"]["ratings"]
        base_kmh = e["pitching"]["velocity"]["kmh"]
        kmh = base_kmh
        max_sub = MAX_TO_AVG_KMH_HS if category == "高校" else MAX_TO_AVG_KMH_UNIV
        if a.get("max_kmh"):
            kmh = max(VELOCITY_MIN, min(VELOCITY_MAX, int(a["max_kmh"]) - max_sub))
        kmh += 1 if deltas.get("velocity", 0) > 0 else 0
        velo_bonus = max(-NUMBER_CAP, min(NUMBER_CAP, VELO_TO_OVERALL * (kmh - base_kmh)))
        is_sp = "先発" in str(a.get("pos_detail") or "") or grade in ("S", "A")
        for k in list(r):
            extra = deltas.get(k, 0) + (velo_bonus if k in ("overall", "k9") else 0)
            set_value(r, k, r[k]["value"] + shift + extra)
        # 先発投手のスタミナ底上げ（即戦力化）
        if is_sp:
            min_sta = 50 if category == "高校" else (68 if grade == "S" else 60)
            r["stamina"]["value"] = max(r["stamina"]["value"], min_sta)
            r["stamina"]["rank"] = rank_of(r["stamina"]["value"])
        e["pitching"]["velocity"] = {"kmh": int(kmh), "source": "amateur" if a.get("max_kmh") else "provisional"}
        e["pitching"]["role"] = "先発" if is_sp else e["pitching"].get("role", "救援")
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


def make_amateur_growth(e: dict, a: dict) -> dict:
    pitcher = a.get("pos") == "投手"
    grade = (a.get("scout") or {}).get("grade") or a.get("eval_rank") or "C"
    cat = a.get("category") or "大学"
    is_hs = (cat == "高校")

    headroom = 18 if grade == "S" else (14 if grade == "A" else (10 if grade == "B" else 6))
    if is_hs:
        headroom += 6

    part = "pitching" if pitcher else "batting"
    ratings = e.get(part, {}).get("ratings", {})
    deltas = trait_deltas(a, pitcher)

    peak = {}
    for k, r in ratings.items():
        if isinstance(r, dict) and r.get("value") is not None:
            extra = 4 if deltas.get(k, 0) > 0 else 0
            peak[k] = min(98, r["value"] + headroom + extra)

    if pitcher and e.get("pitching", {}).get("velocity"):
        cur_v = int(e["pitching"]["velocity"].get("kmh", 145))
        peak["velocity"] = min(162, cur_v + (5 if is_hs else 3))

    peak_age = 29 if is_hs else (28 if pitcher else 27)
    gtype = "晩成" if is_hs else ("普通" if grade in ("S", "A") else "普通")
    return {"type": gtype, "peak_age": peak_age, "peak": peak}


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
    e["growth"] = make_amateur_growth(e, a)
    return e


def blend_into(base: dict, scouted: dict, w: float, a: dict = None) -> None:
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
    if a:
        base["growth"] = make_amateur_growth(base, a)


def fill_leagues(ratings: dict) -> int:
    """リーグが空の選手（史実の無い年は成績が無く compute_ratings が球団のリーグを決められない）を、
    基準年の能力値ファイルの「球団 → リーグ」で埋める。埋めた人数"""
    leagues = {p["team"]: p["league"] for p in load(RATINGS / f"{TEMPLATE_YEAR}_pre.json")["players"]
               if p.get("team") and p.get("league")}
    n = 0
    for p in ratings["players"]:
        if p.get("league") is None and p.get("team") in leagues:
            p["league"] = leagues[p["team"]]
            n += 1
    return n


def amateur_id(draft_year: int, name: str) -> str:
    return f"ama{draft_year}:{norm_name(name)}"


# ---------------------------------------------------------------- 入団時の水準をそろえる（作業62）
## 物差し：投手は総合（overall）。野手は 0.35ミート＋0.35パワー＋0.1選球眼＋0.1走力＋0.1（守備−13）を投手の総合に換算する
## （2026年のレギュラー（1軍300打席・50回以上）の中央・上位25%・上位10%を合わせた直線：投手 = 62 ＋ 1.875 ×（野手 − 60））
BAT_TO_PITCH_MID, PITCH_MID, BAT_TO_PITCH_SLOPE = 60.0, 62.0, 1.875
## 評価ごとの入団時の総合（投手の総合の物差し）[上, 下]。同じ評価の中は順に LEVEL_STEP ずつ下げる（下の値より下げない）
LEVEL_READY = {"S": (79, 74), "A": (75, 70), "B": (69, 64), "C": (63, 57), "D": (56, 50)}  # 大学・社会人・独立など
LEVEL_HS = {"S": (68, 64), "A": (64, 60), "B": (59, 55), "C": (54, 49), "D": (48, 43)}
LEVEL_STEP = 1.0
## 年ごとの豊作・不作（その年の全員を上下）。ユーザー：2027年は2026年より豊作（一番上が少し上、B以上が多い）。
## YEAR_DEPTH は評価 B 以下だけにさらに足す（豊作の年は中位の層も厚い）
YEAR_SHIFT = {2025: 0, 2026: 0, 2027: 2}
YEAR_DEPTH = {2027: 2}
## その年の一番上にする選手（ユーザー決定 2026-11-03：佐藤幻瑛は今年最強。メジャー志望で9位まで残っただけ）
TOP_OF_YEAR = {2026: "佐藤幻瑛"}
## 高卒の上位（評価 S・A）の武器 [上, 下]：投手は奪三振、野手はパワー・走力のうち長所の言葉か元の値で選ぶ
WEAPON = {"S": (80, 77), "A": (76, 72)}
## 入団時の個々の能力の上限（化け物以外は A に届かない）。その年の一番上の総合がこれを超えるときは総合まで
RATING_CAP = 79
SPEED_CAP = 85
CAP_KNEE, CAP_SOFTNESS = 7, 0.4
## 評価 S・A の投手は先発（スタミナの下限）
STARTER_STAMINA = {"高校": 50, "default": 60}
## 有識者の評価のデータが無い年（2025年秋）は順位と競合の数から評価を決める
LOTTERY = ROOT / "npb_collector" / "draft_lottery_manual.json"
PITCH_KEYS = ("overall", "k9", "bb9", "hr9")
BAT_MAIN = ("meet", "power", "eye")
BAT_WEAPONS = ("power", "speed")

## 守備位置・守備力・肩（作業66）。アマの選手には npb.jp・basement の守備の記録が無いので、守備位置の書き方と評価から作る。
## 架空の候補（godot/sim/fictional_draft.gd の fill_fielding）と同じ決め方
FIELD_POS = ("捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手")
INFIELD = ("一塁手", "二塁手", "三塁手", "遊撃手")
## 能力値の fielding で肩がある位置（一塁・二塁は守備力だけ）
ARM_POS = ("捕手", "三塁手", "遊撃手", "外野手")
## 守備位置の書き方（「遊撃手・三塁手」「右翼手・中堅手」「捕手（内外野も可）」など）→ 位置
POS_WORDS = (("捕手", "捕手"), ("一塁", "一塁手"), ("二塁", "二塁手"), ("三塁", "三塁手"), ("遊撃", "遊撃手"),
             ("外野", "外野手"), ("左翼", "外野手"), ("中堅", "外野手"), ("右翼", "外野手"))
## 書き方の無い内野手：守備力がこれ以上なら遊撃手、肩がこれ以上なら三塁手、守備力がこれ以上なら二塁手、ほかは一塁手（高校は FIELD_HS_GAP 下げる）
INFIELD_SS_DEF, INFIELD_3B_ARM, INFIELD_2B_DEF = 60, 60, 52
## 近い位置（本職の守備力からの差）。本職だけだと試合で控え・守備固めに回せないので、隣の位置も少し下げて守れるようにする。
## 書き方にある2つ目からの位置は NAMED_SUB_GAP 下げる
SUB_POS = {"遊撃手": {"二塁手": -3, "三塁手": -4}, "二塁手": {"遊撃手": -6, "一塁手": -2}, "三塁手": {"一塁手": -2}}
NAMED_SUB_GAP = 3
## 評価ごとの守備力・肩の見込み（大学・社会人など。高校は FIELD_HS_GAP 下げる）。2028年以降の架空の候補の入団時の中央（守備力・肩とも
## 大学・社会人など S 62・A 60・B 58・C 56・D 54 前後、高校はおよそ5低い）に合わせた
FIELD_LEVEL = {"S": 62, "A": 60, "B": 58, "C": 56, "D": 54}
FIELD_HS_GAP = 5
## 投手の守備力（npb.jp の失策率から。出場の少ない投手の中央は71）。高校は PITCH_FIELD_HS_GAP 下げる
PITCH_FIELD_LEVEL = {"S": 73, "A": 72, "B": 71, "C": 70, "D": 69}
PITCH_FIELD_HS_GAP = 2
## 選手ごとのゆらぎ（名前から決まる ± の幅。何度作っても同じ）
FIELD_SPREAD = 4
## 長所・短所の言葉（守備・強肩など。1語 STRENGTH_BONUS）は守備力・肩をこの割合だけ動かす
FIELD_TRAIT_SHARE = 0.7


def _num(block: dict, key: str, fallback: float) -> float:
    r = block.get(key)
    return float(r["value"]) if isinstance(r, dict) and r.get("value") is not None else fallback


def bat_composite(r: dict) -> float:
    return (0.35 * _num(r, "meet", 45) + 0.35 * _num(r, "power", 45) + 0.1 * _num(r, "eye", 45)
            + 0.1 * _num(r, "speed", 45) + 0.1 * (_num(r, "defense", 63) - 13))


def entry_level(p: dict) -> float:
    """入団時の総合（投手の総合の物差し）"""
    if p.get("is_pitcher") and isinstance(p.get("pitching"), dict):
        return _num(p["pitching"]["ratings"], "overall", 45)
    if not isinstance(p.get("batting"), dict):
        return 0.0
    return PITCH_MID + BAT_TO_PITCH_SLOPE * (bat_composite(p["batting"]["ratings"]) - BAT_TO_PITCH_MID)


def draft_round(text: str) -> tuple[int, bool]:
    m = re.search(r"ドラフト(\d+)位", text or "")
    return (int(m.group(1)) if m else 99), "育成" in (text or "")


def grade_from_draft(rnd: int, ikusei: bool, bids: int, wave: int) -> str:
    """有識者の評価が無い年：1位の競合（1回目の入札で2球団以上）＝S、1位＝A、2〜3位＝B、4位以下＝C、育成＝D"""
    if ikusei:
        return "D"
    if rnd == 1:
        return "S" if bids >= 2 and wave == 1 else "A"
    return "B" if rnd <= 3 else "C"


def _soft_cap(v: float, cap: float) -> float:
    """上限の手前（CAP_KNEE）から上は伸びを CAP_SOFTNESS に縮め、上限で止める（上限に何人も張り付かないように）"""
    knee = cap - CAP_KNEE
    return min(cap, v if v <= knee else knee + (v - knee) * CAP_SOFTNESS)


def _shift(block: dict, keys, delta: float, cap: float) -> None:
    if abs(delta) < 0.5:
        return  # そろえ済み（何度かけても同じになるように、上限の縮めも掛け直さない）
    for k in keys:
        if isinstance(block.get(k), dict) and block[k].get("value") is not None:
            lim = SPEED_CAP if k == "speed" else cap
            set_value(block, k, max(20, _soft_cap(block[k]["value"] + delta, lim)))


def _fit_batter(r: dict, target: float, keys, cap: float) -> None:
    """keys（＋走力は半分）を動かして野手の値を target（投手の物差し）に合わせる"""
    goal = BAT_TO_PITCH_MID + (target - PITCH_MID) / BAT_TO_PITCH_SLOPE
    for _ in range(6):
        d = goal - bat_composite(r)
        if abs(d) < 0.3:
            break
        w = 0.35 * sum(k in keys for k in ("meet", "power")) + 0.1 * ("eye" in keys) + 0.05 * ("speed" in keys)
        step = d / max(0.2, w)
        _shift(r, [k for k in keys if k != "speed"], step, cap)
        if "speed" in keys:
            _shift(r, ("speed",), step / 2, cap)  # 走力は半分だけ


def _weapon_key(a: dict, r: dict) -> str:
    words = " ".join(str(s) for s in ((a.get("scout") or {}).get("strengths") or []))
    for k in BAT_WEAPONS:
        if any(w in words for w in BAT_WORDS[k]):
            return k
    # 元の値が中央（パワー52・走力57）より上の分がいちばん大きいもの
    return max(BAT_WEAPONS, key=lambda k: _num(r, k, 0) - {"power": 52, "speed": 57}[k])


def _spread(pid: str, key: str) -> int:
    return zlib.crc32(f"{pid}:{key}".encode("utf-8")) % (2 * FIELD_SPREAD + 1) - FIELD_SPREAD


def positions_of(text) -> list[str]:
    """守備位置の書き方 → 位置（書かれた順）"""
    t = str(text or "")
    out = []
    for _, pos in sorted((t.find(w), pos) for w, pos in POS_WORDS if w in t):
        if pos not in out:
            out.append(pos)
    return out


def infield_pos(d: float, arm: float, hs: bool) -> str:
    gap = FIELD_HS_GAP if hs else 0
    if d >= INFIELD_SS_DEF - gap:
        return "遊撃手"
    if arm >= INFIELD_3B_ARM - gap:
        return "三塁手"
    return "二塁手" if d >= INFIELD_2B_DEF - gap else "一塁手"


def _field_entry(pos: str, d: float, arm: float) -> dict:
    e = {"games": 0, "defense": {}, "gold_glove": False}
    set_value(e, "defense", d)
    if pos in ARM_POS:
        set_value(e, "arm", arm)
    return e


def build_fielding(group: str, named: list[str], d: float, arm: float, hs: bool) -> tuple[str, dict]:
    """区分の守備位置（捕手・内野手・外野手。決まった位置でもよい）と書き方の位置 → (本職, fielding)"""
    named = [x for x in named if x in FIELD_POS]
    if group in FIELD_POS:
        primary = group
    else:
        same = [x for x in named if x in INFIELD] if group == "内野手" else named
        primary = same[0] if same else infield_pos(d, arm, hs)
    out = {primary: _field_entry(primary, d, arm)}
    for x in named:
        if x not in out:
            out[x] = _field_entry(x, d - NAMED_SUB_GAP, arm)
    for x, gap in SUB_POS.get(primary, {}).items():
        if x not in out:
            out[x] = _field_entry(x, d + gap, arm)
    return primary, out


def assign_fielding(p: dict, a: dict, grade: str, hs: bool, known: tuple | None = None) -> bool:
    """守備の記録が無い新人・候補 p に守備位置・守備力・肩を付ける（付けたら True）。
    a は有識者の評価（pos_detail・長所の言葉・遠投）、known は翌年の史実の (primary_pos, [守った位置])"""
    if p.get("fielding"):
        return False
    pid = str(p.get("id") or p.get("name"))
    br = p["batting"].get("ratings") if isinstance(p.get("batting"), dict) else None
    if p.get("is_pitcher"):
        e = {"games": 0, "defense": {}, "gold_glove": False}
        set_value(e, "defense", PITCH_FIELD_LEVEL.get(grade, 70) - (PITCH_FIELD_HS_GAP if hs else 0) + _spread(pid, "defense"))
        p["fielding"] = {"投手": e}
        if isinstance(br, dict) and br:
            br["defense"] = dict(e["defense"])  # 史実の投手と同じく打撃の側にも守備力
        return True
    if not isinstance(br, dict):
        return False
    deltas = trait_deltas(a, False) if a else {}
    base = FIELD_LEVEL.get(grade, FIELD_LEVEL["C"]) - (FIELD_HS_GAP if hs else 0)
    d = base + FIELD_TRAIT_SHARE * deltas.get("defense", 0) + _spread(pid, "defense")
    arm = base + FIELD_TRAIT_SHARE * deltas.get("arm", 0) + _spread(pid, "arm")
    if a and a.get("long_throw_m"):
        arm += max(-NUMBER_CAP, min(NUMBER_CAP, THROW_PER_M * (float(a["long_throw_m"]) - 100)))
    d, arm = (max(30.0, _soft_cap(x, RATING_CAP)) for x in (d, arm))
    if known:
        group, named = known
    else:
        group = (a or {}).get("pos") or p.get("primary_pos") or "内野手"
        named = positions_of((a or {}).get("pos_detail"))
    primary, fielding = build_fielding(group, named, d, arm, hs)
    p["primary_pos"] = primary
    p["fielding"] = fielding
    set_value(br, "defense", d)
    set_value(br, "arm", arm)
    return True


def known_positions(draft_year: int) -> dict:
    """draft_year 年秋の新人が翌年に史実で守った位置（<年+2>_pre が史実の成績から作ったファイルのとき）。id と名前 → (本職, [位置])"""
    path = RATINGS / f"{draft_year + 2}_pre.json"
    if not path.exists():
        return {}
    r = load(path)
    if r.get("carried_from"):
        return {}
    out = {}
    for q in r["players"]:
        if str(q.get("draft") or "").startswith(f"{draft_year}年") and not q.get("is_pitcher") \
                and q.get("primary_pos") in FIELD_POS:
            v = (q["primary_pos"], [k for k in (q.get("fielding") or {}) if k in FIELD_POS])
            out[str(q.get("id"))] = out[norm_name(q["name"])] = v
    return out


def draftee_grade(p: dict, draft_year: int, a: dict, lottery: dict) -> tuple[str, bool, tuple]:
    """新人・候補の評価（S〜D）、高卒か、並べる順の材料"""
    text = str(p.get("draft") or "")
    am = p.get("amateur") or {}
    key = norm_name(p["name"])
    rnd, ikusei = draft_round(text)
    lot = lottery.get(key, {})
    bids, wave = int(lot.get("bids", 0)), int(lot.get("wave", 9))
    grade = (a.get("scout") or {}).get("grade") or am.get("grade") or a.get("eval_rank")
    if grade not in GRADE_LEVEL:
        grade = grade_from_draft(rnd, ikusei, bids, wave)
    if TOP_OF_YEAR.get(draft_year) == key:
        grade = "S"
    school = str(p.get("career") or "").split(" - ")[-1]
    hs = (am.get("category") or a.get("category") or category_of(school)) == "高校"
    return grade, hs, (-GRADE_LEVEL[grade], not TOP_OF_YEAR.get(draft_year) == key, -bids, wave,
                       rnd + (100 if ikusei else 0))


def lottery_of(draft_year: int) -> dict:
    if not LOTTERY.exists():
        return {}
    return {norm_name(x["name"]): x for x in load(LOTTERY) if x.get("draft_year") == draft_year}


def fill_fielding(ratings: dict, draft_year: int, scout: dict, known: dict | None = None) -> int:
    """draft_year 年秋の新人で守備の記録が無い選手に守備を付ける（史実の成績から作ったファイルで、2軍でも守っていない新人など）。付けた人数"""
    lottery = lottery_of(draft_year)
    n = 0
    for p in ratings["players"]:
        if not str(p.get("draft") or "").startswith(f"{draft_year}年") or p.get("fielding"):
            continue
        a = scout.get(norm_name(p["name"]), {})
        grade, hs, _ = draftee_grade(p, draft_year, a, lottery)
        k = (known or {}).get(str(p.get("id"))) or (known or {}).get(norm_name(p["name"]))
        n += assign_fielding(p, a, grade, hs, k)
    return n


def calibrate(ratings: dict, draft_year: int, scout: dict, known: dict | None = None) -> list[dict]:
    """draft_year 年秋の新人・候補（draft が「<年>年」で始まる選手）の入団時の能力を、評価の順にそろえる。
    能力の形（長所・短所）は残し、全体を上下する。ピーク（growth.peak）は入団時を下回らないようにだけする。
    同じ能力値ファイルに何度かけても同じになる。そろえた選手の一覧（評価の順）を返す"""
    lottery = lottery_of(draft_year)
    rows = []
    for p in ratings["players"]:
        text = str(p.get("draft") or "")
        if not text.startswith(f"{draft_year}年") or not (isinstance(p.get("batting"), dict) or isinstance(p.get("pitching"), dict)):
            continue
        am = p.get("amateur") or {}
        key = norm_name(p["name"])
        a = scout.get(key, {})
        grade, hs, order = draftee_grade(p, draft_year, a, lottery)
        if am and grade in GRADE_LEVEL:
            am["grade"] = grade  # 当時の評価（ドラフト画面）も有識者の評価にそろえる
        # 守備（作業66）。入団時の総合（野手は守備力も少し入る）より先に付ける
        assign_fielding(p, a, grade, hs, (known or {}).get(str(p.get("id"))) or (known or {}).get(key))
        rows.append({"p": p, "a": a, "grade": grade, "hs": hs, "order": order + (-round(entry_level(p), 1),)})
    rows.sort(key=lambda x: x["order"])
    seen: dict[tuple, int] = defaultdict(int)
    shift = YEAR_SHIFT.get(draft_year, 0)
    for x in rows:
        p, grade, hs = x["p"], x["grade"], x["hs"]
        hi, lo = (LEVEL_HS if hs else LEVEL_READY)[grade]
        i = seen[(hs, grade)]
        seen[(hs, grade)] += 1
        target = max(lo, hi - LEVEL_STEP * i) + shift + (YEAR_DEPTH.get(draft_year, 0) if GRADE_LEVEL[grade] <= 3 else 0)
        x["target"] = target
        cap = max(RATING_CAP, round(target))
        weapon = WEAPON.get(grade) if hs else None
        w_val = (max(weapon[1], weapon[0] - LEVEL_STEP * i) + shift) if weapon else None
        if p.get("is_pitcher") and isinstance(p.get("pitching"), dict):
            r = p["pitching"]["ratings"]
            _shift(r, PITCH_KEYS, target - _num(r, "overall", 45), cap)
            set_value(r, "overall", target)
            if weapon:
                set_value(r, "k9", max(_num(r, "k9", 0), w_val))
            if grade in ("S", "A"):
                st = STARTER_STAMINA["高校" if hs else "default"]
                if _num(r, "stamina", 0) < st:
                    set_value(r, "stamina", st)
                p["pitching"]["role"] = "先発"
        else:
            r = p["batting"]["ratings"]
            keys = [k for k in BAT_MAIN + ("speed",) if isinstance(r.get(k), dict)]
            _fit_batter(r, target, keys, cap)
            if weapon:
                wk = _weapon_key(x["a"], r)
                set_value(r, wk, max(_num(r, wk, 0), w_val))
                _fit_batter(r, target, [k for k in keys if k != wk], cap)
        g = p.get("growth")
        if isinstance(g, dict) and isinstance(g.get("peak"), dict):
            part = p["pitching"] if p.get("is_pitcher") and isinstance(p.get("pitching"), dict) else p["batting"]
            for k, r in part["ratings"].items():
                if k in g["peak"] and isinstance(r, dict) and r.get("value") is not None:
                    g["peak"][k] = max(g["peak"][k], r["value"])
    return rows


def scout_index(draft_year: int) -> dict:
    src = AMATEUR / f"{draft_year}.json"
    return {norm_name(a["name"]): a for a in load(src)["players"]} if src.exists() else {}


## 新人・候補が入っている能力値ファイル（draft_year 年秋 → 翌年の pre と、それを引き継いだファイル）
def calibrate_files(draft_year: int) -> list[Path]:
    out = []
    for name in (f"{draft_year + 1}_pre", f"{draft_year + 1}_post", f"{draft_year + 2}_pre"):
        path = RATINGS / f"{name}.json"
        if not path.exists():
            continue
        if name != f"{draft_year + 1}_pre" and not load(path).get("carried_from"):
            continue  # 史実の成績から作ったファイル（引き継ぎでない）は触らない
        out.append(path)
    return out


def cmd_calibrate(args) -> None:
    y = args.draft_year
    scout = scout_index(y)
    known = known_positions(y)
    for path in calibrate_files(y):
        ratings = load(path)
        rows = calibrate(ratings, y, scout, known)
        dump(path, ratings)
        top = sorted(rows, key=lambda x: -entry_level(x["p"]))[:5]
        print(f"[amateur] {y}年秋の新人・候補の入団時をそろえた -> {path.name}: {len(rows)}人。上位 "
              + "・".join(f"{x['p']['name']} {round(entry_level(x['p']))}" for x in top))
    # 史実の成績から作った翌々年のファイル（2025年秋 → 2027_pre）と、それを引き継いだファイル（2027_post・2028_pre）でも、
    # 守備の記録が無い新人に守備を付ける
    for name in (f"{y + 2}_pre", f"{y + 2}_post", f"{y + 3}_pre"):
        later = RATINGS / f"{name}.json"
        if not later.exists() or later in calibrate_files(y):
            continue
        ratings = load(later)
        n = fill_fielding(ratings, y, scout, known)
        if n:
            dump(later, ratings)
            print(f"[amateur] {y}年秋の新人で守備の記録が無い {n}人に守備を付けた -> {later.name}")


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
            blend_into(cur, scouted, ROOKIE_SCOUT_WEIGHT, a)
            cur["amateur"] = amateur_fields(a, y)
            adjusted += 1
        else:
            entry = apply_profile(scouted, a, amateur_id(y, d["name"]), d["page_title"], text, y)
            ratings["players"].append(entry)
            added += 1
    filled = fill_leagues(ratings)
    dump(path, ratings)
    print(f"[amateur] {y}年秋の新人 -> {path.name}: 追加 {added}・補正 {adjusted}（リーグを埋めた {filled}人）")
    cmd_calibrate(argparse.Namespace(draft_year=y))


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
    if src.exists():
        cmd_calibrate(argparse.Namespace(draft_year=y))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("rookies")
    r.add_argument("--draft-year", type=int, required=True)
    c = sub.add_parser("carry")
    c.add_argument("--year", type=int, required=True)
    k = sub.add_parser("calibrate")
    k.add_argument("--draft-year", type=int, required=True)
    args = ap.parse_args(argv)
    {"rookies": cmd_rookies, "carry": cmd_carry, "calibrate": cmd_calibrate}[args.cmd](args)


if __name__ == "__main__":
    main()
