"""能力値算出スクリプト。

data/<年>/ を入力に、指定年時点の各選手の能力値（1〜100 の実数値 + G〜S ランク）を
JSON で出力する。算出ロジックは docs/SPEC.md「能力値算出ロジック」、
出力フォーマットと各定数の根拠は tools/README.md を参照。

    python tools/compute_ratings.py --year 2008                # 開幕時点（2007年までの成績）
    python tools/compute_ratings.py --year 2008 --phase post   # シーズン後（2008年までの成績）

外部ライブラリ不要（標準ライブラリのみ）。
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_VERSION = 4

# ---------------------------------------------------------------- 定数
# 直近シーズンほど重く（Marcel 方式）。キーは「対象年からの遡り年数」
# 作業40（2026-11-02）：Marcel の 1.0/0.8/0.6 から少し直近寄りに（最新年の割合 42% → 45%）
SEASON_WEIGHTS = {0: 1.0, 1: 0.7, 2: 0.5}

# 2軍成績の扱い: 1軍換算係数（率に掛ける）と、サンプル数としての重み
FARM_SAMPLE_WEIGHT = 0.5
FARM_BAT = {"安打": 0.85, "二塁打": 0.85, "三塁打": 0.85, "本塁打": 0.70, "四球": 0.90, "三振": 1.15}
FARM_PIT = {"本塁打": 1.30, "四球": 1.10, "死球": 1.10, "三振": 0.85}

# 少サンプル補正: 重み w = min(1, サンプル / FULL) で 観測値 と 事前値 を線形ブレンド
FULL_PA = {"avg": 400, "contact": 200, "iso": 300, "bb": 200, "sb_att": 250, "sb_pct": 250, "triple": 400,
           "hr_rate": 300}
FULL_OUTS = {"fip": 450, "k9": 210, "bb9": 360, "hr9": 600, "stamina": 150}
FULL_CHANCES = {"err": 250, "arm": 60}  # 守備機会（arm は守備試合数）

# 事前値 = 母集団分布の何パーセンタイル（良い方向を 100 とする）か。
# サンプルの少ない選手は平均以下であることが多いため平均より下に置く
PRIOR_PCTL = 30

# 正規化の母集団: 対象年から遡る年数と、規定サンプル
POOL_YEARS = 5
POOL_MIN_PA = 200
POOL_MIN_OUTS = 150  # 50 IP
POOL_MIN_FIELD_G = 40

# 1〜100 スケール: 母集団平均 → SCALE_MEAN, 1σ → SCALE_SD
# 母集団は規定打席/規定投球回に達した「そこそこ良い選手」に絞られているため、
# 平均をそのまま D(50台) に置くと大多数のレギュラーが D〜E 以下に沈んでしまう。
# 平均を C 寄りに、標準偏差を広めにして、主力が B 以上・スターが A/S に届くようにする
SCALE_MEAN = 63
SCALE_SD = 17
RANKS = [(90, "S"), (80, "A"), (70, "B"), (60, "C"), (50, "D"), (40, "E"), (20, "F"), (0, "G")]

# 守備: ゴールデングラブ受賞のボーナス（z 値加算）。キーは受賞年からの経過年数
GG_BONUS = {0: 1.2, 1: 0.9, 2: 0.6, 3: 0.3}

# basement (2020年〜): セイバーメトリクス守備指標（RngR, ARM, ErrR, DPR, Framing, Blocking）
# 2020〜2025年の母集団（Inn >= 200）の rate1000（1000イニングあたり得点）の平均・標準偏差
BASEMENT_START_YEAR = 2020
BASEMENT_FULL_INN = {"一塁手": 600, "二塁手": 700, "三塁手": 700, "遊撃手": 700, "外野手": 800, "捕手": 600}
BASEMENT_STATS = {
    "一塁手": {"def_mean": 0.50, "def_sd": 7.16},
    "二塁手": {"def_mean": 0.58, "def_sd": 10.39},
    "三塁手": {"def_mean": 0.68, "def_sd": 9.67},
    "遊撃手": {"def_mean": 0.27, "def_sd": 9.71},
    "外野手": {"def_mean": 0.22, "def_sd": 12.29, "arm_mean": -0.19, "arm_sd": 4.25},
    "捕手":   {"def_mean": -0.89, "def_sd": 12.40, "arm_mean": 0.00, "arm_sd": 4.70},
}

# 球速（投手）: data/velocity.json（2011年〜）の年別最速を Marcel 加重で平均。
# データが無い年（2008〜2010）は、その投手の最古の実測値を年数差ぶん少し下げて代用。
# 実測値が一切ない投手（2010年以前引退など）は K/9 からの単回帰で推定
VELOCITY_EARLY_DECAY_PER_YEAR = 0.3   # 最古の実測値から遡る1年あたりの減算(km/h)
VELOCITY_EARLY_DECAY_CAP = 3.0        # 減算の上限(km/h)
VELOCITY_MIN_OUTS_FOR_K9 = 30         # これ未満のアウト数は回帰の説明変数として使わず平均K/9で代用
VELOCITY_MIN_KMH = 125
VELOCITY_MAX_KMH = 162

# 1軍・2軍とも登板実績が一切ない投手（新人・新外国人）向けの仮の球速。
# 平均球速からの加算(km/h)。ドラフト順位が分かる場合のみ加減、無ければ平均のまま
PROVISIONAL_VELOCITY_ROUND_BONUS = {1: 5, 2: 3, 3: 1}
PROVISIONAL_VELOCITY_IKUSEI_PENALTY = -3

# 新人（プロ成績が少ない選手）の初期能力。
# 少サンプル補正のブレンド先（事前値）は通常 母集団の PRIOR_PCTL パーセンタイルだが、
# ドラフト順位・出身区分が分かる選手はそこから加減する（値が大きいほど高能力側）。
# 単位は「母集団分布の何パーセンタイル」。2軍成績が出れば blend() の重みが自然に増え、
# 実績側に寄っていく（既存の少サンプル補正の仕組みをそのまま利用）
ROOKIE_BASE_PCTL = {"社会人": 45, "大学": 35, "高校": 20}  # 出身区分（即戦力度）
ROOKIE_ROUND_PCTL_BONUS = {1: 15, 2: 8, 3: 4}              # ドラフト順位（該当なければ0）
ROOKIE_IKUSEI_PCTL_PENALTY = -10                            # 育成指名
ROOKIE_IMPORT_PCTL = 35                                     # ドラフト情報がない新加入選手（主に外国人）の既定値
ROOKIE_PCTL_MIN, ROOKIE_PCTL_MAX = 5, 70

# 弾道（野手）: ISO と HR/打数 の z 値を加重平均し、しきい値で 1〜4 に分類。
# 実データが無いための代用指標。係数・しきい値は後で調整できるようここに定数化
TRAJECTORY_WEIGHTS = {"iso": 0.5, "hr_rate": 0.5}
TRAJECTORY_CUTOFFS = [(1.0, 4), (0.0, 3), (-1.0, 2)]  # 該当しなければ 1

# 投手の特殊能力（K/9・BB/9・HR/9 の母集団パーセンタイルで判定、良い方向を 100）
PITCH_ABILITIES = [
    ("k9", 85, None, "奪三振"),
    ("k9", None, 15, "三振取れず"),
    ("bb9", 85, None, "制球力"),
    ("bb9", None, 15, "四球病"),
    ("hr9", 85, None, "被弾抑制"),
    ("hr9", None, 15, "一発病"),
]
ABILITY_MIN_OUTS = 150  # この投球回（アウト数）未満は特殊能力を付与しない

# 先発/救援の判定: 1登板あたりアウト数がこれ以上なら先発。
# 投手の総合力・K/9・BB/9・HR/9・特殊能力は先発/救援で別々に正規化する（スタミナは共通）
STARTER_MIN_OUTS_PER_G = 12
ROLE_SPLIT_RATINGS = {"overall", "k9", "bb9", "hr9"}

# メジャー成績の NPB 換算（data/mlb_stats.json → メジャーにいた年の能力値。引き留めたときに使う）。
# 各項目の回数に掛ける係数（打席・打数・アウト数はそのまま）。data/mlb_moves.json の選手の
# 「移籍前3年のNPB ↔ 移籍後3年のMLB」「復帰前2年のMLB ↔ 復帰後2年のNPB」の率の比（2026-09 集計：
# 安打1.13 二塁打1.10 本塁打1.87 四球1.20 三振0.90 盗塁1.12／被本塁打0.61 与四球0.75 奪三振1.00）を、
# 選ばれてメジャーへ行った選手は好調期の年が多い分だけ控えめに丸めたもの
MLB_TO_NPB_BAT = {"安打": 1.12, "二塁打": 1.10, "三塁打": 1.00, "本塁打": 1.70, "四球": 1.15, "死球": 1.00,
                  "三振": 0.90, "盗塁": 1.10, "盗塁刺": 1.00}
MLB_TO_NPB_PIT = {"安打": 0.90, "本塁打": 0.65, "四球": 0.78, "死球": 0.78, "三振": 1.00, "自責点": 0.80}
# メジャー能力値を作るのは、ゲーム開始年以降にNPBから出ていった選手だけ（それより前に出た選手は引き留められない）
MLB_RATINGS_MIN_LEFT_AFTER = 2008
# メジャーの成績が無い年（マイナー・故障など）は直前の能力値から年齢に応じて緩やかに変化させる。
# (この年齢以下, 1年あたりの能力値の増減)
MLB_NO_STATS_DRIFT = [(26, 1.0), (31, 0.0), (99, -1.5)]

POS_ORDER = ["投手", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手"]
ARM_POS = {"捕手", "三塁手", "遊撃手", "外野手"}  # 補殺が肩力の指標になる守備位置
LEAGUES = {"セントラル・リーグ": "C", "パシフィック・リーグ": "P"}

BAT_KEYS = ["打席", "打数", "安打", "二塁打", "三塁打", "本塁打", "塁打", "盗塁", "盗塁刺",
            "犠打", "犠飛", "四球", "死球", "三振"]
PIT_KEYS = ["登板", "outs", "打者", "安打", "本塁打", "四球", "死球", "三振", "自責点"]
FLD_KEYS = ["試合", "刺殺", "補殺", "失策"]


# ---------------------------------------------------------------- 入力
def load_json(path: Path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


class Data:
    """data/<年>/ のうち対象年以前のものをまとめて読み込む。"""

    def __init__(self, data_dir: Path, year: int):
        self.year = year
        self.years = sorted(int(p.name) for p in data_dir.iterdir()
                            if p.is_dir() and p.name.isdigit() and int(p.name) <= year)
        if year not in self.years:
            sys.exit(f"data/{year}/ がありません")
        cur = data_dir / str(year)
        self.rosters = load_json(cur / "rosters.json")
        # 古い年の players.json を新しい年で上書き（引退選手も母集団に含めるため全年分読む）。
        # 2005〜2007年は players.json / drafts.json がない（HANDOFF「追加データ」参照）ためスキップ
        self.players: dict[str, dict] = {}
        for y in self.years:
            p = data_dir / str(y) / "players.json"
            if p.exists():
                self.players.update(load_json(p))
        self.teamstats = [r for y in self.years for r in load_json(data_dir / str(y) / "teamstats_linked.json")]
        self.awards = [a for y in self.years for a in load_json(data_dir / str(y) / "awards.json")]
        self.drafts = [d for y in self.years if (data_dir / str(y) / "drafts.json").exists()
                       for d in load_json(data_dir / str(y) / "drafts.json")]
        vpath = data_dir / "velocity.json"
        self.velocity = load_json(vpath) if vpath.exists() else []
        mpath, spath = data_dir / "mlb_moves.json", data_dir / "mlb_stats.json"
        self.mlb_moves = load_json(mpath) if mpath.exists() else []
        self.mlb_stats = load_json(spath) if spath.exists() else {}
        # npbbasement.com 守備データ（2020年〜、1軍・2軍。data/basement/）
        self.basement: dict[tuple[int, str], dict[str, dict]] = {}
        bdir = data_dir / "basement"
        if bdir.exists():
            for bp in bdir.glob("*.json"):
                parts = bp.stem.split("_")
                if len(parts) == 2 and parts[0].isdigit():
                    byr, blvl = int(parts[0]), parts[1]
                    bdata = load_json(bp)
                    b_index = {}
                    for row in bdata:
                        for nk in ["nameJ", "nameSponavi"]:
                            nm = norm_name(row.get(nk) or "")
                            if nm:
                                b_index[nm] = row
                    self.basement[(byr, blvl)] = b_index


# ---------------------------------------------------------------- 集計ヘルパ
# 名前突合用の正規化（npb_collector/collect.py の norm_name と同じ規則）
_VARIANTS = str.maketrans({"﨑": "崎", "髙": "高", "濵": "浜", "邊": "辺", "邉": "辺", "德": "徳",
                           "瀨": "瀬", "齋": "斎", "齊": "斉", "櫻": "桜", "澤": "沢", "眞": "真",
                           "惠": "恵", "槇": "槙", "ヶ": "ケ"})


def norm_name(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).translate(_VARIANTS)
    return re.sub(r"[\s・=＝.]+", "", s)


def add_into(acc: dict, row: dict, keys, w: float = 1.0, factors: dict | None = None):
    for k in keys:
        v = row.get(k) or 0
        acc[k] = acc.get(k, 0) + v * w * (factors.get(k, 1.0) if factors else 1.0)


def season_weight(season: int, year: int) -> float:
    return SEASON_WEIGHTS.get(year - season, 0.0) if season <= year else 0.0


def div(a, b):
    return a / b if b else None


# ---------------------------------------------------------------- 指標定義
# 各指標: (関数(counts)->値, サンプル関数(counts)->量, FULL, 高い方が良いか)
def singles(c):
    return c["安打"] - c["二塁打"] - c["三塁打"] - c["本塁打"]


BAT_METRICS = {
    "avg": (lambda c: div(c["安打"], c["打数"]), lambda c: c["打席"], FULL_PA["avg"], True),
    "contact": (lambda c: div(c["打数"] - c["三振"], c["打数"]), lambda c: c["打席"], FULL_PA["contact"], True),
    "iso": (lambda c: div(c["塁打"] - c["安打"], c["打数"]), lambda c: c["打席"], FULL_PA["iso"], True),
    "bb": (lambda c: div(c["四球"], c["打席"]), lambda c: c["打席"], FULL_PA["bb"], True),
    # 盗塁企図率（一塁到達機会あたり）・盗塁成功率・三塁打率
    "sb_att": (lambda c: div(c["盗塁"] + c["盗塁刺"], singles(c) + c["四球"] + c["死球"]),
               lambda c: c["打席"], FULL_PA["sb_att"], True),
    "sb_pct": (lambda c: div(c["盗塁"], c["盗塁"] + c["盗塁刺"]),
               lambda c: (c["盗塁"] + c["盗塁刺"]) * 10, FULL_PA["sb_pct"], True),
    "triple": (lambda c: div(c["三塁打"], c["安打"] - c["本塁打"]), lambda c: c["打席"], FULL_PA["triple"], True),
    "hr_rate": (lambda c: div(c["本塁打"], c["打数"]), lambda c: c["打席"], FULL_PA["hr_rate"], True),
}

# FIP 定数は年ごとに別途計算して counts["_c"] に入れる
PIT_METRICS = {
    "fip": (lambda c: div(13 * c["本塁打"] + 3 * (c["四球"] + c["死球"]) - 2 * c["三振"], c["outs"] / 3) + c["_c"]
            if c["outs"] else None, lambda c: c["outs"], FULL_OUTS["fip"], False),
    "k9": (lambda c: div(c["三振"] * 27, c["outs"]), lambda c: c["outs"], FULL_OUTS["k9"], True),
    "bb9": (lambda c: div(c["四球"] * 27, c["outs"]), lambda c: c["outs"], FULL_OUTS["bb9"], False),
    "hr9": (lambda c: div(c["本塁打"] * 27, c["outs"]), lambda c: c["outs"], FULL_OUTS["hr9"], False),
    # 1登板あたりのアウト数
    "stamina": (lambda c: div(c["outs"], c["登板"]), lambda c: c["outs"], FULL_OUTS["stamina"], True),
}

FLD_METRICS = {
    "err": (lambda c: div(c["失策"], c["刺殺"] + c["補殺"] + c["失策"]),
            lambda c: c["刺殺"] + c["補殺"] + c["失策"], FULL_CHANCES["err"], False),
    "arm": (lambda c: div(c["補殺"], c["試合"]), lambda c: c["試合"], FULL_CHANCES["arm"], True),
}

# 能力値 = 構成指標の z 値の加重平均（母集団上で再標準化）
BAT_RATINGS = {
    "meet": {"avg": 0.6, "contact": 0.4},
    "power": {"iso": 1.0},
    "eye": {"bb": 1.0},
    "speed": {"sb_att": 0.45, "sb_pct": 0.15, "triple": 0.4},
}
PIT_RATINGS = {
    "overall": {"fip": 1.0},
    "stamina": {"stamina": 1.0},
    "k9": {"k9": 1.0},
    "bb9": {"bb9": 1.0},
    "hr9": {"hr9": 1.0},
}


class Dist:
    """母集団分布。平均・標準偏差・パーセンタイル。"""

    def __init__(self, values: list[float], higher_better: bool):
        vs = sorted(v for v in values if v is not None)
        if len(vs) < 2:
            raise ValueError("母集団が小さすぎます")
        self.values = vs
        self.hb = higher_better
        self.mean = sum(vs) / len(vs)
        self.sd = math.sqrt(sum((v - self.mean) ** 2 for v in vs) / (len(vs) - 1)) or 1.0

    def pctl_value(self, p: float) -> float:
        """良い方向を 100 としたパーセンタイル p の値。"""
        q = p if self.hb else 100 - p
        i = q / 100 * (len(self.values) - 1)
        lo, hi = math.floor(i), math.ceil(i)
        return self.values[lo] + (self.values[hi] - self.values[lo]) * (i - lo)

    def z(self, v: float) -> float:
        z = (v - self.mean) / self.sd
        return z if self.hb else -z

    def pctl_of(self, v: float) -> float:
        n = sum(1 for x in self.values if (x <= v if self.hb else x >= v))
        return 100 * n / len(self.values)


def blend(value, sample, full, prior):
    """打席数（サンプル）比率での線形ブレンド。"""
    w = min(1.0, sample / full) if full else 1.0
    if value is None:
        return prior, 0.0
    return w * value + (1 - w) * prior, w


def to_scale(z: float) -> int:
    return max(1, min(100, round(SCALE_MEAN + SCALE_SD * z)))


def rank_of(v: int) -> str:
    return next(r for th, r in RANKS if v >= th)


class Composite:
    """構成指標の z 値を加重平均し、母集団上で再標準化して 1〜100 にする。"""

    def __init__(self, weights: dict, dists: dict[str, Dist], pool: list[dict]):
        self.weights = weights
        self.dists = dists
        raw = [self._raw(row) for row in pool]
        raw = [r for r in raw if r is not None]
        self.mean = sum(raw) / len(raw)
        self.sd = math.sqrt(sum((r - self.mean) ** 2 for r in raw) / (len(raw) - 1)) or 1.0

    def _raw(self, vals: dict):
        if any(vals.get(k) is None for k in self.weights):
            return None
        return sum(w * self.dists[k].z(vals[k]) for k, w in self.weights.items())

    def score(self, vals: dict, bonus_z: float = 0.0) -> int:
        return to_scale((self._raw(vals) - self.mean) / self.sd + bonus_z)

    def zscore(self, vals: dict) -> float | None:
        raw = self._raw(vals)
        return None if raw is None else (raw - self.mean) / self.sd


def trajectory_of(z: float | None) -> int:
    if z is None:
        return 1
    for th, v in TRAJECTORY_CUTOFFS:
        if z >= th:
            return v
    return 1


# ---------------------------------------------------------------- 本体
class Calculator:
    def __init__(self, data: Data, phase: str):
        self.d = data
        self.year = data.year                                   # 在籍（ロースター）の年
        self.phase = phase
        self.through = self.year - 1 if phase == "pre" else self.year  # 成績を使う最終年
        # チーム成績（2軍・守備）と表彰は data/<年> にしかないため、
        # through 以前が無い場合（開始年の開幕時点）は最古の年で代用する
        ts_years = sorted({r["year"] for r in data.teamstats})
        ok = [yr for yr in ts_years if yr <= self.through]
        self.ts_through = ok[-1] if ok else ts_years[0]
        self.fallbacks = [] if ok else [
            f"{self.through}年以前のチーム成績（2軍・守備）と表彰がないため {self.ts_through}年のもので代用"]
        self._index()
        self.fip_c = self._fip_constants()
        self._build_pools()
        self._build_velocity()

    # ---- 索引
    def _index(self):
        y, ty = self.year, self.ts_through
        self.farm_bat = defaultdict(list)   # key -> [(season, row)]
        self.farm_pit = defaultdict(list)
        self.fld = defaultdict(list)        # key -> [(season, level, row)]
        self.unlinked: dict[str, dict] = {}
        for r in self.d.teamstats:
            key = r["player_id"] or self._tmp_id(r)
            if not r["player_id"] and r["year"] == y:
                self.unlinked.setdefault(key, {"name": r["name"], "team": r["team"], "league": r["league"]})
            if r["year"] > ty:
                continue
            if r["kind"] == "f":
                self.fld[key].append((r["year"], r["level"], r))
            elif r["level"] == 2:
                (self.farm_bat if r["kind"] == "b" else self.farm_pit)[key].append((r["year"], r))
        # 対象年のシーズンの守備位置別の出場試合（1軍・2軍の合計）。前年までに成績が無い新加入選手の
        # 守備位置の判定にだけ使う（能力値の算出には使わない）
        self.cur_fld = defaultdict(lambda: defaultdict(int))
        for r in self.d.teamstats:
            if r["year"] == y and r["kind"] == "f" and r["pos"] in POS_ORDER:
                self.cur_fld[r["player_id"] or self._tmp_id(r)][r["pos"]] += r["試合"] or 0
        self.league_of = {}
        for r in self.d.teamstats:
            if r["year"] == y and r["level"] == 1:
                self.league_of[r["team"]] = LEAGUES.get(r["league"])
        self.gg = defaultdict(list)  # player_id -> [(year, category)]
        for a in self.d.awards:
            if a["award"] == "ゴールデングラブ賞" and a["player_id"] and a["year"] <= ty:
                self.gg[a["player_id"]].append((a["year"], a["category"]))
        # ドラフト指名情報（守備位置・仮の球速の算出に使用。名前で突合、player_idなしのため）
        self.draft_info = {norm_name(d["name"]): d for d in self.d.drafts if d["draft_year"] < y}
        self.draft_pos = {k: v["pos"] for k, v in self.draft_info.items()}

    @staticmethod
    def _tmp_id(r) -> str:
        # 1軍出場のない選手の仮ID（HANDOFF 既知の課題2）
        return f"tmp:{r['code']}:{r['name'].replace(' ', '')}"

    # ---- FIP 定数: 年ごとに リーグ防御率 − 素のFIP
    def _fip_constants(self) -> dict[int, float]:
        tot = defaultdict(lambda: defaultdict(float))
        pit1 = [r for r in self.d.teamstats
                if r["kind"] == "p" and r["level"] == 1 and r["year"] <= self.through]
        from_team = {r["year"] for r in pit1}
        for r in pit1:
            if True:
                add_into(tot[r["year"]], r, PIT_KEYS)
        # チーム成績のない年（2007年以前）は選手ページの成績から近似
        for p in self.d.players.values():
            for r in p["pitching"]:
                if r["年度"] not in from_team and r["年度"] <= self.through:
                    add_into(tot[r["年度"]], r, PIT_KEYS)
        out = {}
        for yr, c in tot.items():
            ip = c["outs"] / 3
            if ip < 300:
                continue
            era = c["自責点"] * 9 / ip
            raw = (13 * c["本塁打"] + 3 * (c["四球"] + c["死球"]) - 2 * c["三振"]) / ip
            out[yr] = era - raw
        return out

    @staticmethod
    def role_of(outs_per_g: float) -> str:
        """先発数がデータにないため 1登板あたりアウト数で判定。"""
        return "先発" if outs_per_g >= STARTER_MIN_OUTS_PER_G else "救援"

    def fip_c_for(self, season: int) -> float:
        if season in self.fip_c:
            return self.fip_c[season]
        near = min(self.fip_c, key=lambda s: abs(s - season))
        return self.fip_c[near]

    # ---- 正規化の母集団（対象年から POOL_YEARS 年分の規定到達シーズン）
    def _build_pools(self):
        lo = self.through - POOL_YEARS + 1
        bat_rows, pit_rows = [], []
        for p in self.d.players.values():
            for rows, keys, out in ((p["batting"], BAT_KEYS, bat_rows), (p["pitching"], PIT_KEYS, pit_rows)):
                per = defaultdict(dict)
                for r in rows:
                    if lo <= r["年度"] <= self.through:
                        add_into(per[r["年度"]], r, keys)
                out.extend((s, c) for s, c in per.items())
        bat_pool = [c for _, c in bat_rows if c["打席"] >= POOL_MIN_PA]
        pit_pool = []
        for s, c in pit_rows:
            if c["outs"] >= POOL_MIN_OUTS:
                c["_c"] = self.fip_c_for(s)
                pit_pool.append(c)
        self.bat_dist = {k: Dist([m[0](c) for c in bat_pool], m[3]) for k, m in BAT_METRICS.items()}
        bat_vals = [{k: m[0](c) for k, m in BAT_METRICS.items()} for c in bat_pool]
        # 投手は 全体 / 先発 / 救援 の3母集団
        self.pit_dist, self.pit_comp = {}, {}
        for role in ("全体", "先発", "救援"):
            pool = [c for c in pit_pool if role == "全体" or self.role_of(c["outs"] / c["登板"]) == role]
            dist = {k: Dist([m[0](c) for c in pool], m[3]) for k, m in PIT_METRICS.items()}
            vals = [{k: m[0](c) for k, m in PIT_METRICS.items()} for c in pool]
            self.pit_dist[role] = dist
            self.pit_comp[role] = {k: Composite(w, dist, vals) for k, w in PIT_RATINGS.items()}
        # 盗塁成功率は企図のない選手で未定義になるため、母集団では事前値で埋める
        prior_sb = self.bat_dist["sb_pct"].pctl_value(PRIOR_PCTL)
        for v in bat_vals:
            if v["sb_pct"] is None:
                v["sb_pct"] = prior_sb
        self.bat_comp = {k: Composite(w, self.bat_dist, bat_vals) for k, w in BAT_RATINGS.items()}
        self.traj_comp = Composite(TRAJECTORY_WEIGHTS, self.bat_dist, bat_vals)

        # 守備は位置ごと（teamstats のある年のみ）
        per = defaultdict(lambda: defaultdict(dict))  # pos -> (key, season) -> counts
        for key, rows in self.fld.items():
            for s, lvl, r in rows:
                if lvl == 1 and s >= self.ts_through - POOL_YEARS + 1:
                    add_into(per[r["pos"]].setdefault((key, s), {}), r, FLD_KEYS)
        self.fld_dist = {}
        self.fld_comp = {}
        for pos, rows in per.items():
            pool = [c for c in rows.values() if c["試合"] >= POOL_MIN_FIELD_G]
            if len(pool) < 5:
                continue
            ms = {"err": FLD_METRICS["err"]}
            if pos in ARM_POS:
                ms["arm"] = FLD_METRICS["arm"]
            dists = {k: Dist([m[0](c) for c in pool], m[3]) for k, m in ms.items()}
            vals = [{k: m[0](c) for k, m in ms.items()} for c in pool]
            self.fld_dist[pos] = dists
            self.fld_comp[pos] = {k: Composite({k: 1.0}, dists, vals) for k in ms}

    # ---- 球速（投手）
    def _build_velocity(self):
        self.velocity_by_pid = defaultdict(dict)  # pid -> {year: max_kmh}（全年、フォールバック探索用）
        for r in self.d.velocity:
            pid = r.get("player_id")
            if not pid:
                continue
            y = r["year"]
            self.velocity_by_pid[pid][y] = max(self.velocity_by_pid[pid].get(y, 0), r["max_kmh"])
        # K/9 からの回帰（実測値のある投手の通算 K/9 → 実測値の単純平均）
        xs, ys = [], []
        for pid, years_data in self.velocity_by_pid.items():
            p = self.d.players.get(pid)
            if not p or not years_data:
                continue
            k_tot = sum(r.get("三振") or 0 for r in p["pitching"])
            outs_tot = sum(r.get("outs") or 0 for r in p["pitching"])
            if outs_tot < VELOCITY_MIN_OUTS_FOR_K9:
                continue
            xs.append(k_tot * 27 / outs_tot)
            ys.append(sum(years_data.values()) / len(years_data))
        if len(xs) >= 5:
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            sxx = sum((x - mx) ** 2 for x in xs)
            b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx if sxx else 0.0
            a = my - b * mx
        else:
            a, b, my = 140.0, 0.0, 140.0
        self.velocity_reg = (a, b)
        self.velocity_mean_kmh = my

    def velocity_for(self, pid: str | None, comb: dict) -> dict | None:
        """{'kmh': int, 'source': 'observed'|'early_career'|'estimated'}。実測値も推定材料もなければ None。"""
        years_data = self.velocity_by_pid.get(pid, {}) if pid else {}
        window = [y for y in years_data if y <= self.through]
        if window:
            num = sum(years_data[y] * season_weight(y, self.through) for y in window)
            den = sum(season_weight(y, self.through) for y in window)
            if den:
                return {"kmh": round(num / den), "source": "observed"}
        if years_data:
            earliest = min(years_data)
            gap = max(0, earliest - self.through)
            reduction = min(VELOCITY_EARLY_DECAY_CAP, VELOCITY_EARLY_DECAY_PER_YEAR * gap)
            return {"kmh": round(years_data[earliest] - reduction), "source": "early_career"}
        if not comb or not comb.get("outs"):
            return None
        if comb["outs"] >= VELOCITY_MIN_OUTS_FOR_K9:
            a, b = self.velocity_reg
            est = a + b * (comb["三振"] * 27 / comb["outs"])
        else:
            est = self.velocity_mean_kmh
        est = max(VELOCITY_MIN_KMH, min(VELOCITY_MAX_KMH, est))
        return {"kmh": round(est), "source": "estimated"}

    @staticmethod
    def draft_category(school: str | None) -> str:
        if not school:
            return "社会人"
        if school.endswith("高"):
            return "高校"
        if "大" in school:
            return "大学"
        return "社会人"

    def prior_pctl_for(self, name: str) -> float:
        """少サンプル補正のブレンド先（事前値）のパーセンタイル。ドラフト情報があれば加減する。"""
        info = self.draft_info.get(norm_name(name))
        if not info:
            return ROOKIE_IMPORT_PCTL
        pctl = ROOKIE_BASE_PCTL[self.draft_category(info.get("school"))]
        m = re.match(r"(\d+)", info.get("round") or "")
        if m:
            pctl += ROOKIE_ROUND_PCTL_BONUS.get(int(m.group(1)), 0)
        if info.get("ikusei"):
            pctl += ROOKIE_IKUSEI_PCTL_PENALTY
        return max(ROOKIE_PCTL_MIN, min(ROOKIE_PCTL_MAX, pctl))

    def provisional_velocity(self, name: str) -> dict:
        """1軍・2軍とも登板実績が一切ない投手向けの仮の球速。ドラフト順位が分かれば加減する。"""
        info = self.draft_info.get(norm_name(name))
        bonus = 0.0
        if info:
            m = re.match(r"(\d+)", info.get("round") or "")
            if m:
                bonus += PROVISIONAL_VELOCITY_ROUND_BONUS.get(int(m.group(1)), 0.0)
            if info.get("ikusei"):
                bonus += PROVISIONAL_VELOCITY_IKUSEI_PENALTY
        est = max(VELOCITY_MIN_KMH, min(VELOCITY_MAX_KMH, self.velocity_mean_kmh + bonus))
        return {"kmh": round(est), "source": "provisional"}

    # ---- 選手ごとの加重カウント
    def _weighted(self, rows, keys, farm_rows, farm_factors, pitching: bool):
        """1軍（選手ページ）と2軍（チーム成績）を Marcel 加重で合算。
        戻り値: (率計算用カウント, 1軍サンプル, 2軍サンプル)"""
        c1, c2 = {k: 0.0 for k in keys}, {k: 0.0 for k in keys}
        csum = wsum = 0.0
        for r in rows:
            w = season_weight(r["年度"], self.through)
            if w:
                add_into(c1, r, keys, w)
                if pitching:
                    csum += self.fip_c_for(r["年度"]) * w * (r.get("outs") or 0)
                    wsum += w * (r.get("outs") or 0)
        for s, r in farm_rows:
            w = season_weight(s, self.ts_through)
            if w:
                add_into(c2, r, keys, w, farm_factors)
                if pitching:
                    csum += self.fip_c_for(s) * w * (r.get("outs") or 0) * FARM_SAMPLE_WEIGHT
                    wsum += w * (r.get("outs") or 0) * FARM_SAMPLE_WEIGHT
        comb = {k: c1[k] + c2[k] * FARM_SAMPLE_WEIGHT for k in keys}
        # 塁打は換算後の内訳から再計算（2軍換算で整合が崩れないように）
        if "塁打" in comb:
            comb["塁打"] = comb["安打"] + comb["二塁打"] + 2 * comb["三塁打"] + 3 * comb["本塁打"]
        if pitching:
            comb["_c"] = csum / wsum if wsum else self.fip_c_for(self.through)
        return comb, c1, c2

    def _rate_block(self, comb, metrics, dists, prior_pctl=PRIOR_PCTL):
        vals, detail = {}, {}
        for k, (fn, sample_fn, full, _hb) in metrics.items():
            if k not in dists:
                continue
            prior = dists[k].pctl_value(prior_pctl)
            obs = fn(comb) if comb else None
            v, w = blend(obs, sample_fn(comb) if comb else 0, full, prior)
            vals[k] = v
            detail[k] = {"observed": round(obs, 4) if obs is not None else None,
                         "blended": round(v, 4), "weight": round(w, 3)}
        return vals, detail

    def batting(self, pid, key, name):
        p = self.d.players.get(pid) if pid else None
        comb, c1, c2 = self._weighted(p["batting"] if p else [], BAT_KEYS, self.farm_bat.get(key, []),
                                      FARM_BAT, pitching=False)
        vals, detail = self._rate_block(comb, BAT_METRICS, self.bat_dist, self.prior_pctl_for(name))
        ratings = {}
        for rating_name, comp in self.bat_comp.items():
            v = comp.score(vals)
            ratings[rating_name] = {"value": v, "rank": rank_of(v)}
        trajectory = trajectory_of(self.traj_comp.zscore(vals))
        return ratings, detail, {"pa_1": round(c1["打席"], 1), "pa_2": round(c2["打席"], 1)}, trajectory

    def pitching(self, pid, key, name, force=False):
        """force=True: 1軍・2軍とも成績が一切ない投手でも、ドラフト情報による事前値だけで初期の能力値を返す
        （新人・新外国人向け。データが増えれば blend() の重みが上がり実績側に寄っていく）"""
        p = self.d.players.get(pid) if pid else None
        rows = p["pitching"] if p else []
        farm = self.farm_pit.get(key, [])
        has_data = any(season_weight(r["年度"], self.through) for r in rows) or \
            any(season_weight(s, self.ts_through) for s, _ in farm)
        if not has_data and not force:
            return None
        comb, c1, c2 = self._weighted(rows, PIT_KEYS, farm, FARM_PIT, pitching=True)
        # 先発/救援は少サンプル補正前の実績で判定（補正後は事前値に引っ張られるため）。
        # 成績が一切ない場合は判定できないため救援扱い
        role = self.role_of(PIT_METRICS["stamina"][0](comb) or 0) if has_data else "救援"
        # 率の補正（事前値）は役割別の母集団から取る
        vals, detail = self._rate_block(comb, PIT_METRICS, self.pit_dist[role], self.prior_pctl_for(name))
        ratings = {}
        for rating_name in PIT_RATINGS:
            r = role if rating_name in ROLE_SPLIT_RATINGS else "全体"
            v = self.pit_comp[r][rating_name].score(vals)
            ratings[rating_name] = {"value": v, "rank": rank_of(v)}
        abilities = []
        if comb["outs"] >= ABILITY_MIN_OUTS:
            for k, hi, lo, label in PITCH_ABILITIES:
                pc = self.pit_dist[role][k].pctl_of(vals[k])
                if (hi is not None and pc >= hi) or (lo is not None and pc <= lo):
                    abilities.append(label)
        return {"ratings": ratings, "abilities": abilities, "role": role, "detail": detail,
                "velocity": self.velocity_for(pid, comb) or self.provisional_velocity(name),
                "sample": {"outs_1": round(c1["outs"], 1), "outs_2": round(c2["outs"], 1)}}

    def _fielding_basement(self, pid, key, name, games, gg_by_pos):
        """npbbasement.com のデータを用いた守備力・肩力の算出（2020年以降）。"""
        nm = norm_name(name)
        pos_acc = defaultdict(lambda: {"inn": 0.0, "runs": 0.0, "arm": 0.0, "rng": 0.0, "err": 0.0,
                                       "dpr": 0.0, "frm": 0.0, "blk": 0.0})
        # 直近3年の basement データを加重合算（SEASON_WEIGHTS、2軍は重み半分）
        for dy in range(3):
            yr = self.through - dy
            if yr < BASEMENT_START_YEAR:
                continue
            w = season_weight(yr, self.through)
            if not w:
                continue
            for lvl in ["1g", "2g"]:
                lw = w * (1.0 if lvl == "1g" else FARM_SAMPLE_WEIGHT)
                p = self.d.basement.get((yr, lvl), {}).get(nm)
                if not p:
                    continue
                for f in p.get("Stats", {}).get("fld", []):
                    pos = f.get("POS")
                    inn = f.get("Inn") or 0.0
                    if inn <= 0:
                        continue
                    if pos in ["LF", "CF", "RF"]:
                        target_pos = "外野手"
                        runs = (f.get("RngR") or 0.0) + (f.get("ErrR") or 0.0)
                        arm = f.get("ARM") or 0.0
                    elif pos == "1B":
                        target_pos = "一塁手"
                        runs = (f.get("RngR") or 0.0) + (f.get("ErrR") or 0.0) + (f.get("DPR") or 0.0)
                        arm = 0.0
                    elif pos == "2B":
                        target_pos = "二塁手"
                        runs = (f.get("RngR") or 0.0) + (f.get("ErrR") or 0.0) + (f.get("DPR") or 0.0)
                        arm = 0.0
                    elif pos == "3B":
                        target_pos = "三塁手"
                        runs = (f.get("RngR") or 0.0) + (f.get("ErrR") or 0.0) + (f.get("DPR") or 0.0)
                        arm = 0.0
                    elif pos == "SS":
                        target_pos = "遊撃手"
                        runs = (f.get("RngR") or 0.0) + (f.get("ErrR") or 0.0) + (f.get("DPR") or 0.0)
                        arm = 0.0
                    elif pos == "C":
                        target_pos = "捕手"
                        runs = (f.get("Framing") or 0.0) + (f.get("Blocking") or 0.0) + (f.get("ErrR") or 0.0) + (f.get("ARM") or 0.0)
                        arm = f.get("ARM") or 0.0
                    else:
                        continue

                    acc = pos_acc[target_pos]
                    acc["inn"] += inn * lw
                    acc["runs"] += runs * lw
                    acc["arm"] += arm * lw
                    acc["rng"] += (f.get("RngR") or 0.0) * lw
                    acc["err"] += (f.get("ErrR") or 0.0) * lw
                    acc["dpr"] += (f.get("DPR") or 0.0) * lw
                    acc["frm"] += (f.get("Framing") or 0.0) * lw
                    acc["blk"] += (f.get("Blocking") or 0.0) * lw

        if not pos_acc:
            return None

        out = {}
        for pos in sorted(pos_acc, key=POS_ORDER.index):
            acc = pos_acc[pos]
            inn = acc["inn"]
            if inn < 5.0:
                continue
            st = BASEMENT_STATS[pos]
            full = BASEMENT_FULL_INN[pos]
            w_blend = min(1.0, inn / full)

            # 守備力
            obs_rate = (acc["runs"] / inn) * 1000
            blended_rate = w_blend * obs_rate + (1 - w_blend) * 0.0
            z_def = (blended_rate - st["def_mean"]) / st["def_sd"]
            d = to_scale(z_def)

            detail = {
                "inn": round(inn, 1),
                "rate1000": round(obs_rate, 2),
                "blended": round(blended_rate, 2),
                "weight": round(w_blend, 3),
                "rngr": round(acc["rng"], 1),
                "errr": round(acc["err"], 1),
            }
            if pos in ["一塁手", "二塁手", "三塁手", "遊撃手"]:
                detail["dpr"] = round(acc["dpr"], 1)
            elif pos == "捕手":
                detail["frm"] = round(acc["frm"], 1)
                detail["blk"] = round(acc["blk"], 1)

            entry = {"games": int(games.get(pos, 0)), "defense": {"value": d, "rank": rank_of(d)},
                     "gold_glove": bool(gg_by_pos.get(pos)), "detail": detail}

            # 肩力（外野手・捕手）
            if pos in ["外野手", "捕手"]:
                obs_arm = (acc["arm"] / inn) * 1000
                blended_arm = w_blend * obs_arm + (1 - w_blend) * 0.0
                z_arm = (blended_arm - st["arm_mean"]) / st["arm_sd"]
                a = to_scale(z_arm)
                entry["arm"] = {"value": a, "rank": rank_of(a)}
                detail["arm"] = round(acc["arm"], 1)
                detail["arm1000"] = round(obs_arm, 2)

            out[pos] = entry
        return out

    def fielding(self, pid, key, name):
        """守備位置ごとの守備力・肩力。2020年以降は basement（RngR, ARM, ErrR, DPR, FRM）、
        2019年以前は npb.jp（失策率＋GG賞、補殺/試合）の Marcel 加重で算出。"""
        prior_pctl = self.prior_pctl_for(name)
        per = defaultdict(lambda: {k: 0.0 for k in FLD_KEYS})
        games = defaultdict(float)
        for s, lvl, r in self.fld.get(key, []):
            w = season_weight(s, self.ts_through) * (1.0 if lvl == 1 else FARM_SAMPLE_WEIGHT)
            if w:
                add_into(per[r["pos"]], r, FLD_KEYS, w)
                if s == self.ts_through:
                    games[r["pos"]] += (r["試合"] or 0) if lvl == 1 else 0
        gg_by_pos = defaultdict(float)
        for yr, cat in self.gg.get(pid, []):
            gg_by_pos[cat] = max(gg_by_pos[cat], GG_BONUS.get(self.ts_through - yr, 0.0))

        # 2020年以降かつ basement データがある場合
        b_out = None
        if self.through >= BASEMENT_START_YEAR and self.d.basement:
            b_out = self._fielding_basement(pid, key, name, games, gg_by_pos)

        out = {}
        # 従来方式での算出（basementが無いポジション、投手、三塁・遊撃の肩力、2019年以前のフォールバック用）
        for pos in sorted(per, key=POS_ORDER.index):
            if pos not in self.fld_dist:
                continue
            c = per[pos]
            ms = {k: FLD_METRICS[k] for k in self.fld_dist[pos]}
            vals, detail = self._rate_block(c, ms, self.fld_dist[pos], prior_pctl)
            comps = self.fld_comp[pos]
            d = comps["err"].score(vals, gg_by_pos.get(pos, 0.0))
            entry = {"games": int(games.get(pos, 0)), "defense": {"value": d, "rank": rank_of(d)},
                     "gold_glove": bool(gg_by_pos.get(pos)), "detail": detail}
            if "arm" in comps:
                a = comps["arm"].score(vals)
                entry["arm"] = {"value": a, "rank": rank_of(a)}
            out[pos] = entry

        if b_out:
            # basement の結果で上書き（投手以外）
            for pos, b_entry in b_out.items():
                if pos in out and "arm" in out[pos] and "arm" not in b_entry:
                    # 三塁手・遊撃手：外野守備があれば外野 ARM、無ければ従来の補殺肩力を引き継ぐ
                    if "外野手" in b_out and "arm" in b_out["外野手"]:
                        b_entry["arm"] = b_out["外野手"]["arm"]
                    else:
                        b_entry["arm"] = out[pos]["arm"]
                out[pos] = b_entry
            return out

        return out

    # ---- 出力
    def current_pos(self, key) -> str | None:
        """対象年の1軍・2軍で最も多く守った守備位置（同数なら POS_ORDER の先）。無ければ None。"""
        games = self.cur_fld.get(key)
        if not games:
            return None
        return max(games, key=lambda pos: (games[pos], -POS_ORDER.index(pos)))

    @staticmethod
    def career_pos(p: dict | None) -> str | None:
        """選手ページの全年の成績（対象年より後も含む）から、守備位置の手がかりが他に無い選手の投手/野手を判定する。
        投球アウト数が打席数以上なら投手、打席があれば野手（指名打者）、どちらも無ければ None。"""
        if not p:
            return None
        outs = sum(r.get("outs") or 0 for r in p["pitching"])
        pa = sum(r.get("打席") or 0 for r in p["batting"])
        if outs and outs >= pa:
            return "投手"
        return "指名打者" if pa else None

    def player_entry(self, pid, key, name, team, team_id):
        p = self.d.players.get(pid) if pid else None
        bat, bat_detail, bat_sample, trajectory = self.batting(pid, key, name)
        pit = self.pitching(pid, key, name)
        fld = self.fielding(pid, key, name)
        pos_games = {pos: v["games"] for pos, v in fld.items()}
        is_pitcher = bool(pit) and (pos_games.get("投手", 0) >= max(pos_games.values() or [0])
                                    or not any(g for pos, g in pos_games.items() if pos != "投手"))
        fielder = {pos: v for pos, v in fld.items() if pos != "投手"}
        if fielder:
            primary = max(fielder, key=lambda pos: (fielder[pos]["games"], -POS_ORDER.index(pos)))
        else:
            primary = "投手" if is_pitcher else None
        if is_pitcher:
            primary = "投手"
        bio = (p or {}).get("bio", {})
        if primary is None:
            # 守備成績がない（DH専任・出場なし・新加入）: 登録ポジション → ドラフト時ポジション →
            # 対象年の守備位置（新外国人・由規など前年までに成績が無い選手。投手なら投手になる）→ 打撃成績があれば DH
            primary = bio.get("ポジション") or self.draft_pos.get(norm_name(name)) \
                or self.current_pos(key) or self.career_pos(p) or ("指名打者" if bat_sample["pa_1"] else None)
            is_pitcher = primary == "投手"
        if is_pitcher and pit is None:
            # 1軍・2軍とも登板実績が一切ない投手（新人・新外国人）: ドラフト情報による初期の能力値を入れる
            pit = self.pitching(pid, key, name, force=True)
        # 野手の肩力・守備力はメイン守備位置の値を代表値にする
        if primary and primary in fld:
            bat["defense"] = fld[primary]["defense"]
            if "arm" in fld[primary]:
                bat["arm"] = fld[primary]["arm"]
        return {
            "id": pid or key,
            "provisional_id": pid is None,
            "name": name,
            "team": team,
            "team_id": team_id,
            "league": self.league_of.get(team),
            "throws": (p or {}).get("throws"),
            "bats": (p or {}).get("bats"),
            "birth": (p or {}).get("birth"),
            "height": (p or {}).get("height"),
            "weight": (p or {}).get("weight"),
            "draft": bio.get("ドラフト"),
            "career": bio.get("経歴"),
            "is_pitcher": is_pitcher,
            "primary_pos": primary,
            "batting": {"ratings": bat, "detail": bat_detail, "sample": bat_sample, "trajectory": trajectory},
            "pitching": pit,
            "fielding": fld,
        }

    # ---- メジャーにいた年の能力値
    @staticmethod
    def _mlb_row(r: dict, mapping: dict, factors: dict) -> dict:
        row = {"年度": r["season"]}
        for npb_key, mlb_key in mapping.items():
            row[npb_key] = (r.get(mlb_key) or 0) * factors.get(npb_key, 1.0)
        return row

    MLB_BAT_KEYS = {"打席": "plateAppearances", "打数": "atBats", "安打": "hits", "二塁打": "doubles",
                    "三塁打": "triples", "本塁打": "homeRuns", "塁打": "totalBases", "盗塁": "stolenBases",
                    "盗塁刺": "caughtStealing", "犠打": "sacBunts", "犠飛": "sacFlies", "四球": "baseOnBalls",
                    "死球": "hitByPitch", "三振": "strikeOuts"}
    MLB_PIT_KEYS = {"登板": "gamesPitched", "outs": "outs", "打者": "battersFaced", "安打": "hits",
                    "本塁打": "homeRuns", "四球": "baseOnBalls", "死球": "hitBatsmen", "三振": "strikeOuts",
                    "自責点": "earnedRuns"}

    def mlb_rows(self, mlb_id) -> tuple[list, list]:
        """メジャーの年度別成績を NPB 換算した選手ページ形式の行（打撃, 投手）。"""
        st = self.d.mlb_stats.get(str(mlb_id), {})
        bat = [self._mlb_row(r, self.MLB_BAT_KEYS, MLB_TO_NPB_BAT) for r in st.get("hitting", [])]
        pit = [self._mlb_row(r, self.MLB_PIT_KEYS, MLB_TO_NPB_PIT) for r in st.get("pitching", [])]
        return bat, pit

    @staticmethod
    def _drift_per_year(age: int) -> float:
        return next(d for th, d in MLB_NO_STATS_DRIFT if age <= th)

    def mlb_entry(self, move: dict) -> dict | None:
        """対象年にメジャーにいる選手の能力値。NPB の成績にメジャー成績（NPB換算）を足して同じ手順で算出する。
        対象年までの数年にメジャー成績が無い（マイナー・故障）場合は、成績のある最後の年時点で算出し、
        そこから年齢に応じて緩やかに変化させる（MLB_NO_STATS_DRIFT）。"""
        pid = move["player_id"]
        page = self.d.players.get(pid)
        if not page:
            return None
        mbat, mpit = self.mlb_rows(move["mlb_id"]) if move.get("mlb_id") else ([], [])
        patched = dict(page, batting=page["batting"] + mbat, pitching=page["pitching"] + mpit)
        played = [r["年度"] for r in patched["batting"] if (r.get("打席") or 0) > 0] + \
                 [r["年度"] for r in patched["pitching"] if (r.get("outs") or 0) > 0]
        played = [y for y in played if y <= self.through]
        through = max(played) if played else self.through
        saved = self.through, self.ts_through, self.d.players[pid]
        try:
            self.through = through
            self.ts_through = min(self.ts_through, move["left_after"])
            self.d.players[pid] = patched
            entry = self.player_entry(pid, pid, page.get("name") or move["name"], None, None)
        finally:
            self.through, self.ts_through, self.d.players[pid] = saved
        gap = self.through - through
        if gap > 0:
            birth = entry.get("birth") or ""
            age = self.year - int(birth[:4]) if birth[:4].isdigit() else 30
            delta = round(self._drift_per_year(age) * gap)
            self._shift_ratings(entry, delta)
        entry["league"] = None
        entry["mlb"] = {
            "mlb_id": move.get("mlb_id"), "npb_team_before": move["npb_team_before"],
            "left_after": move["left_after"], "returned": move.get("returned"),
            "stats_through": through, "drift_years": gap,
            "mlb_seasons": sorted({r["年度"] for r in mbat + mpit if r["年度"] <= self.through}),
        }
        return entry

    @staticmethod
    def _shift_ratings(entry: dict, delta: int):
        def shift(r):
            if isinstance(r, dict) and r.get("value") is not None:
                r["value"] = max(1, min(100, r["value"] + delta))
                r["rank"] = rank_of(r["value"])
        for r in (entry.get("batting") or {}).get("ratings", {}).values():
            shift(r)
        for r in ((entry.get("pitching") or {}).get("ratings") or {}).values():
            shift(r)
        for f in (entry.get("fielding") or {}).values():
            shift(f.get("defense"))
            shift(f.get("arm"))

    def mlb_players(self) -> list[dict]:
        out = []
        for m in self.d.mlb_moves:
            if m["left_after"] < MLB_RATINGS_MIN_LEFT_AFTER or m["left_after"] >= self.year:
                continue
            if m.get("returned") is not None and self.year >= m["returned"]:
                continue
            e = self.mlb_entry(m)
            if e:
                out.append(e)
        return out

    def run(self) -> dict:
        out = []
        seen = set()
        for r in self.d.rosters:
            if r["year"] != self.year or r["player_id"] in seen:
                continue
            seen.add(r["player_id"])
            out.append(self.player_entry(r["player_id"], r["player_id"], r["name"], r["team"], r["team_id"]))
        for key, u in self.unlinked.items():
            out.append(self.player_entry(None, key, u["name"], u["team"], None))
        return {
            "schema_version": SCHEMA_VERSION,
            "year": self.year,
            "phase": self.phase,
            "stats_through": self.through,
            "fallbacks": self.fallbacks,
            "source_years": self.d.years,
            "scale": {"min": 1, "max": 100, "ranks": [{"min": th, "rank": r} for th, r in RANKS]},
            "fip_constant": round(self.fip_c_for(self.through), 3),
            "players": out,
            "mlb_players": self.mlb_players(),
        }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--year", type=int, required=True, help="対象年（この年の在籍選手を出力）")
    ap.add_argument("--phase", choices=["pre", "post"], default="pre",
                    help="pre=開幕時点（前年までの成績） / post=シーズン後（当年までの成績）")
    ap.add_argument("--data", type=Path, default=ROOT / "data")
    ap.add_argument("--out", type=Path, help="出力先（省略時 generated/ratings/<年>.json）")
    args = ap.parse_args(argv)
    out_path = args.out or ROOT / "generated" / "ratings" / f"{args.year}_{args.phase}.json"
    result = Calculator(Data(args.data, args.year), args.phase).run()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print(f"{len(result['players'])} players -> {out_path}")


if __name__ == "__main__":
    main()
