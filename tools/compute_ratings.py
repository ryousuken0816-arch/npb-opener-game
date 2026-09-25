"""能力値算出スクリプト。

data/<年>/ を入力に、指定年時点の各選手の能力値（1〜100 の実数値 + G〜S ランク）を
JSON で出力する。算出ロジックは docs/SPEC.md「能力値算出ロジック」、
出力フォーマットと各定数の根拠は tools/README.md を参照。

    python tools/compute_ratings.py --year 2008
    python tools/compute_ratings.py --year 2008 --out generated/ratings/2008.json

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
SCHEMA_VERSION = 1

# ---------------------------------------------------------------- 定数
# 直近シーズンほど重く（Marcel 方式）。キーは「対象年からの遡り年数」
SEASON_WEIGHTS = {0: 1.0, 1: 0.8, 2: 0.6}

# 2軍成績の扱い: 1軍換算係数（率に掛ける）と、サンプル数としての重み
FARM_SAMPLE_WEIGHT = 0.5
FARM_BAT = {"安打": 0.85, "二塁打": 0.85, "三塁打": 0.85, "本塁打": 0.70, "四球": 0.90, "三振": 1.15}
FARM_PIT = {"本塁打": 1.30, "四球": 1.10, "死球": 1.10, "三振": 0.85}

# 少サンプル補正: 重み w = min(1, サンプル / FULL) で 観測値 と 事前値 を線形ブレンド
FULL_PA = {"avg": 400, "contact": 200, "iso": 300, "bb": 200, "sb_att": 250, "sb_pct": 250, "triple": 400}
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
SCALE_MEAN = 55
SCALE_SD = 15
RANKS = [(90, "S"), (80, "A"), (70, "B"), (60, "C"), (50, "D"), (40, "E"), (20, "F"), (0, "G")]

# 守備: ゴールデングラブ受賞のボーナス（z 値加算）。キーは受賞年からの経過年数
GG_BONUS = {0: 1.2, 1: 0.9, 2: 0.6, 3: 0.3}

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
        # 古い年の players.json を新しい年で上書き（引退選手も母集団に含めるため全年分読む）
        self.players: dict[str, dict] = {}
        for y in self.years:
            self.players.update(load_json(data_dir / str(y) / "players.json"))
        self.teamstats = [r for y in self.years for r in load_json(data_dir / str(y) / "teamstats_linked.json")]
        self.awards = [a for y in self.years for a in load_json(data_dir / str(y) / "awards.json")]
        self.drafts = [d for y in self.years for d in load_json(data_dir / str(y) / "drafts.json")]


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


# ---------------------------------------------------------------- 本体
class Calculator:
    def __init__(self, data: Data):
        self.d = data
        self.year = data.year
        self._index()
        self.fip_c = self._fip_constants()
        self._build_pools()

    # ---- 索引
    def _index(self):
        y = self.year
        self.farm_bat = defaultdict(list)   # key -> [(season, row)]
        self.farm_pit = defaultdict(list)
        self.fld = defaultdict(list)        # key -> [(season, level, row)]
        self.unlinked: dict[str, dict] = {}
        for r in self.d.teamstats:
            if r["year"] > y:
                continue
            key = r["player_id"] or self._tmp_id(r)
            if not r["player_id"] and r["year"] == y:
                self.unlinked.setdefault(key, {"name": r["name"], "team": r["team"], "league": r["league"]})
            if r["kind"] == "f":
                self.fld[key].append((r["year"], r["level"], r))
            elif r["level"] == 2:
                (self.farm_bat if r["kind"] == "b" else self.farm_pit)[key].append((r["year"], r))
        self.league_of = {}
        for r in self.d.teamstats:
            if r["year"] == y and r["level"] == 1:
                self.league_of[r["team"]] = LEAGUES.get(r["league"])
        self.gg = defaultdict(list)  # player_id -> [(year, category)]
        for a in self.d.awards:
            if a["award"] == "ゴールデングラブ賞" and a["player_id"] and a["year"] <= y:
                self.gg[a["player_id"]].append((a["year"], a["category"]))
        # 守備成績のない選手の守備位置用（ドラフト指名時のポジション。名前で突合）
        self.draft_pos = {norm_name(d["name"]): d["pos"] for d in self.d.drafts if d["draft_year"] < y}

    @staticmethod
    def _tmp_id(r) -> str:
        # 1軍出場のない選手の仮ID（HANDOFF 既知の課題2）
        return f"tmp:{r['code']}:{r['name'].replace(' ', '')}"

    # ---- FIP 定数: 年ごとに リーグ防御率 − 素のFIP
    def _fip_constants(self) -> dict[int, float]:
        tot = defaultdict(lambda: defaultdict(float))
        from_team = {r["year"] for r in self.d.teamstats if r["kind"] == "p" and r["level"] == 1}
        for r in self.d.teamstats:
            if r["kind"] == "p" and r["level"] == 1:
                add_into(tot[r["year"]], r, PIT_KEYS)
        # チーム成績のない年（2007年以前）は選手ページの成績から近似
        for p in self.d.players.values():
            for r in p["pitching"]:
                if r["年度"] not in from_team:
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

    def fip_c_for(self, season: int) -> float:
        if season in self.fip_c:
            return self.fip_c[season]
        near = min(self.fip_c, key=lambda s: abs(s - season))
        return self.fip_c[near]

    # ---- 正規化の母集団（対象年から POOL_YEARS 年分の規定到達シーズン）
    def _build_pools(self):
        lo = self.year - POOL_YEARS + 1
        bat_rows, pit_rows = [], []
        for p in self.d.players.values():
            for rows, keys, out in ((p["batting"], BAT_KEYS, bat_rows), (p["pitching"], PIT_KEYS, pit_rows)):
                per = defaultdict(dict)
                for r in rows:
                    if lo <= r["年度"] <= self.year:
                        add_into(per[r["年度"]], r, keys)
                out.extend((s, c) for s, c in per.items())
        bat_pool = [c for _, c in bat_rows if c["打席"] >= POOL_MIN_PA]
        pit_pool = []
        for s, c in pit_rows:
            if c["outs"] >= POOL_MIN_OUTS:
                c["_c"] = self.fip_c_for(s)
                pit_pool.append(c)
        self.bat_dist = {k: Dist([m[0](c) for c in bat_pool], m[3]) for k, m in BAT_METRICS.items()}
        self.pit_dist = {k: Dist([m[0](c) for c in pit_pool], m[3]) for k, m in PIT_METRICS.items()}
        bat_vals = [{k: m[0](c) for k, m in BAT_METRICS.items()} for c in bat_pool]
        pit_vals = [{k: m[0](c) for k, m in PIT_METRICS.items()} for c in pit_pool]
        # 盗塁成功率は企図のない選手で未定義になるため、母集団では事前値で埋める
        prior_sb = self.bat_dist["sb_pct"].pctl_value(PRIOR_PCTL)
        for v in bat_vals:
            if v["sb_pct"] is None:
                v["sb_pct"] = prior_sb
        self.bat_comp = {k: Composite(w, self.bat_dist, bat_vals) for k, w in BAT_RATINGS.items()}
        self.pit_comp = {k: Composite(w, self.pit_dist, pit_vals) for k, w in PIT_RATINGS.items()}

        # 守備は位置ごと（teamstats のある年のみ）
        per = defaultdict(lambda: defaultdict(dict))  # pos -> (key, season) -> counts
        for key, rows in self.fld.items():
            for s, lvl, r in rows:
                if lvl == 1 and s >= lo:
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

    # ---- 選手ごとの加重カウント
    def _weighted(self, rows, keys, farm_rows, farm_factors, pitching: bool):
        """1軍（選手ページ）と2軍（チーム成績）を Marcel 加重で合算。
        戻り値: (率計算用カウント, 1軍サンプル, 2軍サンプル)"""
        c1, c2 = {k: 0.0 for k in keys}, {k: 0.0 for k in keys}
        csum = wsum = 0.0
        for r in rows:
            w = season_weight(r["年度"], self.year)
            if w:
                add_into(c1, r, keys, w)
                if pitching:
                    csum += self.fip_c_for(r["年度"]) * w * (r.get("outs") or 0)
                    wsum += w * (r.get("outs") or 0)
        for s, r in farm_rows:
            w = season_weight(s, self.year)
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
            comb["_c"] = csum / wsum if wsum else self.fip_c_for(self.year)
        return comb, c1, c2

    def _rate_block(self, comb, metrics, dists, full_override=None):
        vals, detail = {}, {}
        for k, (fn, sample_fn, full, _hb) in metrics.items():
            if k not in dists:
                continue
            prior = dists[k].pctl_value(PRIOR_PCTL)
            obs = fn(comb) if comb else None
            v, w = blend(obs, sample_fn(comb) if comb else 0, full, prior)
            vals[k] = v
            detail[k] = {"observed": round(obs, 4) if obs is not None else None,
                         "blended": round(v, 4), "weight": round(w, 3)}
        return vals, detail

    def batting(self, pid, key):
        p = self.d.players.get(pid) if pid else None
        comb, c1, c2 = self._weighted(p["batting"] if p else [], BAT_KEYS, self.farm_bat.get(key, []),
                                      FARM_BAT, pitching=False)
        vals, detail = self._rate_block(comb, BAT_METRICS, self.bat_dist)
        ratings = {}
        for name, comp in self.bat_comp.items():
            v = comp.score(vals)
            ratings[name] = {"value": v, "rank": rank_of(v)}
        return ratings, detail, {"pa_1": round(c1["打席"], 1), "pa_2": round(c2["打席"], 1)}

    def pitching(self, pid, key):
        p = self.d.players.get(pid) if pid else None
        rows = p["pitching"] if p else []
        farm = self.farm_pit.get(key, [])
        if not any(season_weight(r["年度"], self.year) for r in rows) and \
                not any(season_weight(s, self.year) for s, _ in farm):
            return None
        comb, c1, c2 = self._weighted(rows, PIT_KEYS, farm, FARM_PIT, pitching=True)
        vals, detail = self._rate_block(comb, PIT_METRICS, self.pit_dist)
        ratings = {}
        for name, comp in self.pit_comp.items():
            v = comp.score(vals)
            ratings[name] = {"value": v, "rank": rank_of(v)}
        abilities = []
        if comb["outs"] >= ABILITY_MIN_OUTS:
            for k, hi, lo, label in PITCH_ABILITIES:
                pc = self.pit_dist[k].pctl_of(vals[k])
                if (hi is not None and pc >= hi) or (lo is not None and pc <= lo):
                    abilities.append(label)
        # 先発/救援の目安（先発数がデータにないため 1登板あたりアウト数で判定）
        role = "先発" if (vals["stamina"] or 0) >= 12 else "救援"
        return {"ratings": ratings, "abilities": abilities, "role": role, "detail": detail,
                "sample": {"outs_1": round(c1["outs"], 1), "outs_2": round(c2["outs"], 1)}}

    def fielding(self, pid, key):
        """守備位置ごとの守備力・肩力。1軍＋2軍（2軍は重み半分）の Marcel 加重。"""
        per = defaultdict(lambda: {k: 0.0 for k in FLD_KEYS})
        games = defaultdict(float)
        for s, lvl, r in self.fld.get(key, []):
            w = season_weight(s, self.year) * (1.0 if lvl == 1 else FARM_SAMPLE_WEIGHT)
            if w:
                add_into(per[r["pos"]], r, FLD_KEYS, w)
                if s == self.year:
                    games[r["pos"]] += (r["試合"] or 0) if lvl == 1 else 0
        gg_by_pos = defaultdict(float)
        for yr, cat in self.gg.get(pid, []):
            gg_by_pos[cat] = max(gg_by_pos[cat], GG_BONUS.get(self.year - yr, 0.0))
        out = {}
        for pos in sorted(per, key=POS_ORDER.index):
            if pos not in self.fld_dist:
                continue
            c = per[pos]
            ms = {k: FLD_METRICS[k] for k in self.fld_dist[pos]}
            vals, detail = self._rate_block(c, ms, self.fld_dist[pos])
            comps = self.fld_comp[pos]
            d = comps["err"].score(vals, gg_by_pos.get(pos, 0.0))
            entry = {"games": int(games.get(pos, 0)), "defense": {"value": d, "rank": rank_of(d)},
                     "gold_glove": bool(gg_by_pos.get(pos)), "detail": detail}
            if "arm" in comps:
                a = comps["arm"].score(vals)
                entry["arm"] = {"value": a, "rank": rank_of(a)}
            out[pos] = entry
        return out

    # ---- 出力
    def player_entry(self, pid, key, name, team, team_id):
        p = self.d.players.get(pid) if pid else None
        bat, bat_detail, bat_sample = self.batting(pid, key)
        pit = self.pitching(pid, key)
        fld = self.fielding(pid, key)
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
            # 守備成績がない（DH専任・出場なし）: 登録ポジション → ドラフト時ポジション → 打撃成績があれば DH
            primary = bio.get("ポジション") or self.draft_pos.get(norm_name(name)) \
                or ("指名打者" if bat_sample["pa_1"] else None)
            is_pitcher = primary == "投手"
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
            "batting": {"ratings": bat, "detail": bat_detail, "sample": bat_sample},
            "pitching": pit,
            "fielding": fld,
        }

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
            "source_years": self.d.years,
            "scale": {"min": 1, "max": 100, "ranks": [{"min": th, "rank": r} for th, r in RANKS]},
            "fip_constant": round(self.fip_c_for(self.year), 3),
            "players": out,
        }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--year", type=int, required=True, help="対象年（この年までの実績で算出）")
    ap.add_argument("--data", type=Path, default=ROOT / "data")
    ap.add_argument("--out", type=Path, help="出力先（省略時 generated/ratings/<年>.json）")
    args = ap.parse_args(argv)
    out_path = args.out or ROOT / "generated" / "ratings" / f"{args.year}.json"
    result = Calculator(Data(args.data, args.year)).run()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print(f"{len(result['players'])} players -> {out_path}")


if __name__ == "__main__":
    main()
