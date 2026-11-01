"""能力値の点検（docs/AUTORUN.md 作業39 第1段階）の表を作る。ゲームの処理・能力値は変えない（読むだけ）。

    # 先にゲームを回して選手ごとの成績を JSON に書く（1回 約10秒、乱数は毎回変わる）
    godot --headless --path godot --script res://tests/ratings_audit_dump.gd -- 2026 <出力先>/sim2026_1.json
    python tools/ratings_audit.py --sims "<出力先>/sim*.json" --out <表の出力先.md>

入力：generated/ratings/（2025_pre・2025_post・2026_pre・2026_post・2023_post）、data/2023・2025・2026 の
teamstats_linked.json（1軍の打撃・投手・守備）と awards.json（ゴールデングラブ）、ゲームを回した結果の JSON。
出力：docs/reports/ratings_audit.md に貼る表（Markdown）と、要約の数字。標準ライブラリのみ。
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 野手の総合（godot/sim/salary.gd の Salary.ability と同じ重み）
BAT_OVERALL = {"meet": 0.35, "power": 0.35, "eye": 0.1, "speed": 0.1, "defense": 0.1}
SCALE_MEAN, SCALE_SD = 63, 17
RANKS = [(90, "S"), (80, "A"), (70, "B"), (60, "C"), (50, "D"), (40, "E"), (20, "F"), (0, "G")]
# Records.RUN_VALUES と同じ得点価値（wRC+ をゲームと同じ式で出す）
RUN_VALUES = {"bb": 0.30, "hbp": 0.33, "1b": 0.46, "2b": 0.77, "3b": 1.05, "hr": 1.40}
OUT_VALUE, BASE_RUNS_PER_PA = 0.27, 0.115
# 簡易 WAR（Records と同じ式。実際の成績には守備の指標が無いので守備得点は0、外野は左中右の平均）
POS_ADJ = {"捕手": 12.0, "遊撃手": 7.0, "二塁手": 3.0, "三塁手": 2.0, "外野手": -3.8, "一塁手": -12.0, "指名打者": -17.0}
REPLACEMENT_BAT, REPLACEMENT_PIT_RATE, REPLACEMENT_RELIEF_RATE, RUNS_PER_WIN_BASE = 16.5, 1.25, 1.12, 9.5

# 必ず入れる選手（ユーザーがよく知っていそうな主力）
MUST_BAT = ["佐藤輝明", "近藤健介", "牧秀悟", "源田壮亮", "中野拓夢", "菊池涼介", "坂本勇人", "村上宗隆", "岡本和真",
            "森下翔太", "細川成也", "近本光司", "柳田悠岐", "山川穂高", "中山礼都", "筒香嘉智", "清宮幸太郎", "郡司裕也",
            "万波中正", "辰己涼介", "大山悠輔", "丸佳浩", "宮﨑敏郎", "小園海斗", "栗原陵矢", "森友哉", "坂本誠志郎",
            "甲斐拓也", "周東佑京", "泉口友汰", "石川昂弥", "西川龍馬", "頓宮裕真", "レイエス", "ポランコ", "山田哲人",
            "浅村栄斗", "林琢真", "村林一輝", "中村奨成", "岡林勇希", "野村勇", "上林誠知", "牧原大成"]
MUST_PIT = ["村上頌樹", "才木浩人", "モイネロ", "伊藤大海", "山本由伸", "戸郷翔征", "宮城大弥", "東克樹", "髙橋宏斗",
            "有原航平", "床田寛樹", "森下暢仁", "大勢", "杉山一樹", "平良海馬", "石井大智", "松山晋也",
            "早川隆久", "今井達也", "デュプランティエ", "高橋遥人", "大関友久", "上沢直之", "髙橋光成", "岸孝之"]
TEAM_SHORT = {"読売ジャイアンツ": "巨人", "阪神タイガース": "阪神", "横浜DeNAベイスターズ": "DeNA", "広島東洋カープ": "広島",
              "東京ヤクルトスワローズ": "ヤクルト", "中日ドラゴンズ": "中日", "福岡ソフトバンク・ホークス": "ソフトバンク",
              "福岡ソフトバンクホークス": "ソフトバンク", "北海道日本ハムファイターズ": "日本ハム", "オリックス・バファローズ": "オリックス",
              "東北楽天ゴールデンイーグルス": "楽天", "埼玉西武ライオンズ": "西武", "千葉ロッテマリーンズ": "ロッテ"}
POS_SHORT = {"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "外野手": "外", "左翼手": "左",
             "中堅手": "中", "右翼手": "右", "指名打者": "指", "投手": "投", "内野手": "内"}
FLD_POS = ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手"]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def nn(name: str) -> str:
    return name.replace(" ", "").replace("　", "").replace("髙", "高").replace("﨑", "崎")


def rank_of(v):
    return next(r for th, r in RANKS if v >= th)


def rv(r):
    """{'value', 'rank'} → 'B72'。無ければ '-'"""
    if not isinstance(r, dict) or r.get("value") is None:
        return "-"
    return f"{r['rank']}{r['value']}"


def bat_overall(br: dict) -> int | None:
    """野手の総合を 1〜100 の目盛りに置いたもの（重みつき平均の z をそのまま 63+17z。平均すると z が縮む）"""
    if not br.get("meet"):
        return None
    z = 0.0
    for k, w in BAT_OVERALL.items():
        v = br.get(k, {}).get("value", 63) if isinstance(br.get(k), dict) else 63
        z += w * (v - SCALE_MEAN) / SCALE_SD
    return max(1, min(100, round(SCALE_MEAN + SCALE_SD * z)))


# 「現在の能力」（godot/sim/depth.gd の now_score ＝ Salary.ability の実力 z ＋ 0.6×出場量）とランクの境目（Draft.FUTURE_RANKS）
FUTURE_RANKS = [(1.6, "S"), (1.1, "A"), (0.65, "B"), (0.25, "C"), (-0.1, "D"), (-0.45, "E"), (-0.8, "F")]


def _z(r, fallback=45.0):
    v = r.get("value") if isinstance(r, dict) and r.get("value") is not None else fallback
    return (v - SCALE_MEAN) / SCALE_SD


def now_score(p: dict) -> float:
    pit = p.get("pitching")
    if p.get("is_pitcher") and isinstance(pit, dict):
        r = pit.get("ratings") or {}
        z = 0.85 * (0.75 * _z(r.get("overall")) + 0.25 * _z(r.get("k9")))
        outs = (pit.get("sample") or {}).get("outs_1", 0.0) / 2.4
        if pit.get("role") == "先発":
            return z + 0.6 * min(1.0, outs / 450)
        return z * 0.65 + 0.6 * min(1.0, outs / 170)
    br = (p.get("batting") or {}).get("ratings") or {}
    z = sum(w * _z(br.get(k), 63.0 if k == "defense" else 45.0) for k, w in BAT_OVERALL.items())
    pa = ((p.get("batting") or {}).get("sample") or {}).get("pa_1", 0.0) / 2.4
    return z + 0.6 * min(1.0, pa / 480)


def now_rank(p: dict) -> str:
    v = now_score(p)
    return next((r for th, r in FUTURE_RANKS if v >= th), "G") + f"({v:.2f})"


def short(team):
    return TEAM_SHORT.get(team, team or "")


# ---------------------------------------------------------------- 実際の成績
class Actual:
    """data/<年>/teamstats_linked.json の1軍成績（選手IDごとに合算。移籍で2行ある選手も1つに）。"""

    def __init__(self, year: int):
        self.year = year
        ts = load(ROOT / "data" / str(year) / "teamstats_linked.json")
        self.bat = defaultdict(lambda: defaultdict(float))
        self.pit = defaultdict(lambda: defaultdict(float))
        self.fld = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))  # id -> pos -> counts
        self.team = {}
        self.league = {}
        self.name = {}
        for r in ts:
            if r["level"] != 1 or not r["player_id"]:
                continue
            pid = r["player_id"]
            self.team[pid] = r["team"]
            self.league[pid] = "C" if r["league"].startswith("セ") else "P"
            self.name[pid] = r["name"]
            dst = {"b": self.bat, "p": self.pit}.get(r["kind"])
            if r["kind"] == "f":
                pos = r["pos"]
                for k in ("試合", "刺殺", "補殺", "失策"):
                    self.fld[pid][pos][k] += r.get(k) or 0
                continue
            for k, v in r.items():
                if isinstance(v, (int, float)) and not isinstance(v, bool) and k not in ("year", "level") \
                        and k not in ("打率", "長打率", "出塁率", "防御率", "勝率", "守備率"):
                    dst[pid][k] += v
        self._coef()
        self.awards = [a for a in load(ROOT / "data" / str(year) / "awards.json")] \
            if (ROOT / "data" / str(year) / "awards.json").exists() else []

    def _coef(self):
        """リーグごとの wOBA の重み・FIP 定数（godot/sim/records.gd の coefficients と同じ式）"""
        self.c = {}
        for lg in ("C", "P"):
            t = defaultdict(float)
            for pid, b in self.bat.items():
                if self.league.get(pid) == lg:
                    for k in ("打席", "打数", "安打", "二塁打", "三塁打", "本塁打", "四球", "死球", "犠飛", "得点"):
                        t[k] += b[k]
            rpa = t["得点"] / t["打席"]
            sc = rpa / BASE_RUNS_PER_PA
            raw = {k: v * sc + OUT_VALUE * sc for k, v in RUN_VALUES.items()}
            one = t["安打"] - t["二塁打"] - t["三塁打"] - t["本塁打"]
            den = t["打数"] + t["四球"] + t["死球"] + t["犠飛"]
            num = raw["bb"] * t["四球"] + raw["hbp"] * t["死球"] + raw["1b"] * one + raw["2b"] * t["二塁打"] \
                + raw["3b"] * t["三塁打"] + raw["hr"] * t["本塁打"]
            obp = (t["安打"] + t["四球"] + t["死球"]) / den
            scale = obp / (num / den)
            p = defaultdict(float)
            for pid, x in self.pit.items():
                if self.league.get(pid) == lg:
                    for k in ("outs", "自責点", "本塁打", "四球", "死球", "三振"):
                        p[k] += x[k]
            ip = p["outs"] / 3
            era = p["自責点"] * 9 / ip
            fipc = era - (13 * p["本塁打"] + 3 * (p["四球"] + p["死球"]) - 2 * p["三振"]) / ip
            rpg = 2 * t["得点"] / (6 * 143)  # 1試合の得点（両チーム）
            self.c[lg] = {"w": {k: v * scale for k, v in raw.items()}, "scale": scale, "lg_woba": obp, "rpa": rpa,
                          "fipc": fipc, "era": era, "rpw": RUNS_PER_WIN_BASE * rpg / 9}

    def bat_line(self, pid):
        b = self.bat.get(pid)
        if not b or b["打席"] <= 0:
            return None
        c = self.c[self.league[pid]]
        w = c["w"]
        ab, pa = b["打数"], b["打席"]
        one = b["安打"] - b["二塁打"] - b["三塁打"] - b["本塁打"]
        den = ab + b["四球"] + b["死球"] + b["犠飛"]
        woba = (w["bb"] * b["四球"] + w["hbp"] * b["死球"] + w["1b"] * one + w["2b"] * b["二塁打"]
                + w["3b"] * b["三塁打"] + w["hr"] * b["本塁打"]) / den if den else 0
        wraa = (woba - c["lg_woba"]) / c["scale"] * pa
        avg = b["安打"] / ab if ab else 0
        obp = (b["安打"] + b["四球"] + b["死球"]) / den if den else 0
        slg = (one + 2 * b["二塁打"] + 3 * b["三塁打"] + 4 * b["本塁打"]) / ab if ab else 0
        # 守備位置の補正：守った試合の割合（打撃の試合のうち守備の記録が無い分は指名打者・代打とみなす）
        f = self.fld.get(pid, {})
        g_f = {pos: c2["試合"] for pos, c2 in f.items() if pos in POS_ADJ}
        g_dh = max(0.0, b["試合"] - sum(g_f.values()))
        tot = sum(g_f.values()) + g_dh
        adj = (sum(POS_ADJ[pos] * g for pos, g in g_f.items()) + POS_ADJ["指名打者"] * g_dh) / tot if tot else 0
        war = (wraa + 0.2 * b["盗塁"] - 0.4 * b["盗塁刺"] + (adj + REPLACEMENT_BAT) * pa / 600) / c["rpw"]
        return {"pa": int(pa), "avg": avg, "war": war, "hr": int(b["本塁打"]), "rbi": int(b["打点"]), "sb": int(b["盗塁"]),
                "h": int(b["安打"]), "obp": obp, "slg": slg, "ops": obp + slg,
                "wrc_plus": (wraa / pa + c["rpa"]) / c["rpa"] * 100}

    def pit_line(self, pid):
        p = self.pit.get(pid)
        if not p or p["outs"] <= 0:
            return None
        c = self.c[self.league[pid]]
        ip = p["outs"] / 3
        fip = (13 * p["本塁打"] + 3 * (p["四球"] + p["死球"]) - 2 * p["三振"]) / ip + c["fipc"]
        relief = p["outs"] / max(p["登板"], 1) < 12  # 先発数が無いので 1登板12アウト未満を救援（compute_ratings と同じ）
        war = (c["era"] * (REPLACEMENT_RELIEF_RATE if relief else REPLACEMENT_PIT_RATE) - fip) * ip / 9 / c["rpw"]
        return {"ip": ip, "war": war, "g": int(p["登板"]), "w": int(p["勝利"]), "l": int(p["敗北"]), "sv": int(p["セーブ"]),
                "hp": int(p.get("ＨＰ", 0)), "so": int(p["三振"]), "era": p["自責点"] * 9 / ip,
                "fip": (13 * p["本塁打"] + 3 * (p["四球"] + p["死球"]) - 2 * p["三振"]) / ip + c["fipc"],
                "k9": p["三振"] * 9 / ip, "bb9": p["四球"] * 9 / ip}

    def main_pos(self, pid):
        f = self.fld.get(pid)
        if not f:
            return None, 0
        pos = max(f, key=lambda k: f[k]["試合"])
        return pos, int(f[pos]["試合"])

    def fld_z(self):
        """守備位置ごとの 失策率 と レンジファクター（(刺殺+補殺)/試合）の z（40試合以上の選手の分布で）。
        外野は左・中・右の区別が npb.jp に無いので「外野手」1つ"""
        out = defaultdict(dict)
        for pos in FLD_POS:
            rows = []
            for pid, f in self.fld.items():
                c = f.get(pos)
                if c and c["試合"] >= 40:
                    ch = c["刺殺"] + c["補殺"] + c["失策"]
                    rows.append((pid, c["失策"] / ch if ch else 0, (c["刺殺"] + c["補殺"]) / c["試合"],
                                 c["補殺"] / c["試合"]))
            if len(rows) < 5:
                continue
            for i, key in ((1, "err"), (2, "rf"), (3, "ast")):
                vals = [r[i] for r in rows]
                m, s = statistics.mean(vals), statistics.pstdev(vals) or 1
                for r in rows:
                    z = (r[i] - m) / s
                    out[r[0]].setdefault(pos, {})[key] = -z if key == "err" else z
        return out

    def titles(self):
        """成績から決まるタイトル（規定打席・投球回は試合数×3.1・×1.0、143試合）。選手ID → [タイトル]"""
        out = defaultdict(list)
        for lg in ("C", "P"):
            bats = [(pid, self.bat_line(pid)) for pid in self.bat if self.league.get(pid) == lg]
            bats = [(pid, b) for pid, b in bats if b]
            q = [(pid, b) for pid, b in bats if b["pa"] >= 443]
            for key, label, pool in (("avg", "首位打者", q), ("hr", "本塁打王", bats), ("rbi", "打点王", bats),
                                     ("sb", "盗塁王", bats), ("obp", "最高出塁率", q), ("h", "最多安打", bats)):
                if pool:
                    best = max(b[key] for _, b in pool)
                    out_ids = [pid for pid, b in pool if b[key] == best]
                    for pid in out_ids:
                        out[pid].append(label)
            pits = [(pid, self.pit_line(pid)) for pid in self.pit if self.league.get(pid) == lg]
            pits = [(pid, p) for pid, p in pits if p]
            qp = [(pid, p) for pid, p in pits if p["ip"] >= 143]
            for key, label, pool, low in (("era", "最優秀防御率", qp, True), ("w", "最多勝", pits, False),
                                          ("so", "最多奪三振", pits, False), ("sv", "最多セーブ", pits, False),
                                          ("hp", "最優秀中継ぎ", pits, False)):
                if pool:
                    best = (min if low else max)(p[key] for _, p in pool)
                    for pid, p in pool:
                        if p[key] == best:
                            out[pid].append(label)
        return out

    def gg(self):
        out = defaultdict(list)
        for a in self.awards:
            if a["award"] == "ゴールデングラブ賞" and a.get("player_id"):
                out[a["player_id"]].append("GG(" + POS_SHORT.get(a["category"], a["category"]) + ")")
        return out


# ---------------------------------------------------------------- ゲームを回した結果
class Sims:
    def __init__(self, files: list[str]):
        self.runs = [load(f) for f in files]

    def bat(self, pid):
        rows = [r["batting"][pid] for r in self.runs if pid in r["batting"]]
        if not rows:
            return None
        def m(f):
            return statistics.mean(f(x) for x in rows)
        def sd(f):
            return statistics.pstdev([f(x) for x in rows]) if len(rows) > 1 else 0.0
        posg = defaultdict(float)
        for x in rows:
            for pos, g in x["pos_g"].items():
                posg[pos] += g / len(rows)
        cat = defaultdict(float)
        for x in rows:
            for pos, fr in x["fld"]["pos"].items():
                for k in ("rng", "err", "arm", "cs", "wp"):
                    cat[k] += fr.get(k, 0.0) / len(rows)
        main = max(posg, key=posg.get) if posg else ""
        return {"n": len(rows), "pa": m(lambda x: x["row"]["pa"]), "avg": m(lambda x: x["row"]["avg"]),
                "hr": m(lambda x: x["row"]["hr"]), "ops": m(lambda x: x["row"]["ops"]),
                "wrc_plus": m(lambda x: x["row"]["wrc_plus"]), "fld": m(lambda x: x["fld"]["total"]),
                "fld_sd": sd(lambda x: x["fld"]["total"]), "war": m(lambda x: x["row"]["war"]),
                "war_sd": sd(lambda x: x["row"]["war"]), "main": main, "posg": dict(posg), "cat": dict(cat),
                "fld_runs": [x["fld"]["total"] for x in rows]}

    def pit(self, pid):
        rows = [r["pitching"][pid] for r in self.runs if pid in r["pitching"]]
        if not rows:
            return None
        def m(f):
            return statistics.mean(f(x) for x in rows)
        return {"n": len(rows), "ip": m(lambda x: x["row"]["ip"] / 3), "era": m(lambda x: x["row"]["era"]),
                "fip": m(lambda x: x["row"]["fip"]), "war": m(lambda x: x["row"]["war"]),
                "war_sd": statistics.pstdev([x["row"]["war"] for x in rows]) if len(rows) > 1 else 0.0,
                "w": m(lambda x: x["row"]["w"]), "sv": m(lambda x: x["row"]["sv"]), "k9": m(lambda x: x["row"]["k9"])}

    def lineups(self):
        return self.runs[0]["lineups"] if self.runs else {}


# ---------------------------------------------------------------- 表
def fmt3(x):
    return f"{x:.3f}".lstrip("0") if x is not None else "-"


def pearson(xs, ys):
    if len(xs) < 3:
        return float("nan")
    mx, my = statistics.mean(xs), statistics.mean(ys)
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy) if sx and sy else float("nan")


def ratings_index(path):
    d = load(path)
    idx = {p["id"]: p for p in d["players"]}
    for p in d.get("mlb_players", []):
        idx.setdefault(p["id"], dict(p, _mlb=True))
    return idx


SABER_POS = {"捕手": "捕手", "一塁手": "一塁手", "二塁手": "二塁手", "三塁手": "三塁手", "遊撃手": "遊撃手",
             "左翼手": "外野手", "中堅手": "外野手", "右翼手": "外野手"}


def saber_section(out, path: Path, R, A, sims):
    """外部の指標（tooldock の wRC+・WAR、DELTA の UZR・RngR、1.02 の WAR）とゲームの能力値・ゲームの成績を並べる"""
    import csv
    with open(path, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    rows = [r for r in rows if r["選手名"] != "名前"]  # 表の見出しが行として混ざっているもの
    pre = R["2026_pre"]
    by_name = {}
    for pid, p in pre.items():
        by_name.setdefault(nn(p["name"]).replace(".", ""), pid)

    def pid_of(nm):
        key = nn(nm).replace(".", "")
        if key in by_name:
            return by_name[key]
        c = [pid for n, pid in by_name.items() if n.endswith(key)]
        return c[0] if len(c) == 1 else None

    def val(r):
        return float(r["値"].rstrip("%"))

    out("")
    out("### 6.5 外部の指標との比べ")
    out("")
    out("外部のサイトの集計（ユーザーが別の AI に集めてもらった CSV。数字は下の出典から引用し、CSV そのものはリポジトリに入れない）。"
        "DELTA の UZR は守備範囲（RngR）・失策（ErrR）・肩（ARM）などの合計で、＋が平均より失点を防いだ。2026年の守備位置ごとの UZR は11月中旬に公開予定で、まだ無い")
    out("")
    out("#### 2025年の守備（DELTA）と、ゲームの守備力（2026_pre＝2025年までの成績）・ゲーム2026年のその位置の守備得点（10回の平均、300回以上）")
    out("")
    out("| 選手 | DELTA の位置 | UZR | RngR（範囲） | その他（DELTA） | ゲームの守備力（その位置） | ゲームの肩 | ゲーム26 の守備得点 |")
    out("|---|---|---|---|---|---|---|---|")
    fl = defaultdict(dict)
    for r in rows:
        if r["年"] == "2025" and r["指標名"].endswith("(DELTA)"):
            fl[(r["選手名"], r["守備位置"])][r["指標名"].split("(")[0]] = val(r)
    order = list(SABER_POS)
    xs, ys = defaultdict(list), defaultdict(list)
    gx, gy = [], []
    for (nm, pos), d in sorted(fl.items(), key=lambda t: (order.index(t[0][1]) if t[0][1] in order else 9,
                                                         -t[1].get("RngR", t[1].get("UZR", 0)))):
        pid = pid_of(nm)
        key = SABER_POS.get(pos)
        f = (pre.get(pid, {}).get("fielding") or {}).get(key) if pid and key else None
        fr = "-"
        if pid:
            got = [r2["batting"][pid]["fld"]["pos"].get(pos) for r2 in sims[2026].runs if pid in r2["batting"]]
            got = [g for g in got if g]
            if got:
                inn = statistics.mean(g["outs"] for g in got) / 3
                if inn >= 300:
                    fr = f"{statistics.mean(g['total'] for g in got):+.1f}（{inn:.0f}回）"
        others = "・".join(f"{k} {v:+.1f}" for k, v in d.items() if k not in ("UZR", "RngR"))
        uzr = f"{d['UZR']:+.1f}" if "UZR" in d else "-"
        rng = f"{d['RngR']:+.1f}" if "RngR" in d else "-"
        out(f"| {nm} | {pos} | {uzr} | {rng} | {others or '-'} | {rv(f['defense']) if f else '-'} | "
            f"{rv(f.get('arm')) if f else '-'} | {fr} |")
        if f and "RngR" in d and key != "捕手":
            xs[key].append(f["defense"]["value"])
            ys[key].append(d["RngR"])
            gx.append(f["defense"]["value"])
            gy.append(d["RngR"])
    out("")
    if gx:
        out(f"- ゲームの守備力と DELTA の RngR（範囲）の相関：全体 {pearson(gx, gy):.2f}（{len(gx)}人、捕手を除く）、"
            + "・".join(f"{k} {pearson(xs[k], ys[k]):.2f}（{len(xs[k])}人）" for k in xs if len(xs[k]) >= 5))

    def metric(year, name):
        return {r["選手名"]: val(r) for r in rows if r["年"] == str(year) and r["指標名"] == name}

    out("")
    out("#### 打撃・WAR（tooldock の簡易版、1.02 の WAR）と、ゲームの成績（10回の平均）")
    out("")
    out("tooldock の WAR は守備・球場の補正なし。1.02 の WAR は DELTA の守備・球場の補正込み。この資料の WAR（6.2）は守備なしで代替水準もゲームの式なので、tooldock・1.02 より1〜2高めに出る")
    out("")
    out("| 選手 | tooldock wRC+ 25→26 | この資料の wRC+ 25→26 | ゲーム wRC+ 25／26 | tooldock WAR 25→26 | 1.02 WAR 26 | ゲーム WAR 25／26 |")
    out("|---|---|---|---|---|---|---|")
    w25, w26 = metric(2025, "wRC+(tooldock)"), metric(2026, "wRC+(tooldock)")
    t25, t26 = metric(2025, "WAR(tooldock簡易・守備UZR未含)"), metric(2026, "WAR(tooldock簡易・守備UZR未含)")
    d26 = metric(2026, "WAR(DELTA/1.02)")
    names = sorted(set(w26) | set(w25) | set(d26), key=lambda n: -(w26.get(n) or w25.get(n) or 0))
    cx, cy = [], []
    for nm in names:
        pid = pid_of(nm)
        if not pid or pre.get(pid, {}).get("is_pitcher"):
            continue
        a25, a26 = A[2025].bat_line(pid), A[2026].bat_line(pid)
        s25, s26 = sims[2025].bat(pid), sims[2026].bat(pid)
        aw = lambda b: f"{b['wrc_plus']:.0f}" if b and b["pa"] >= 100 else "-"
        gw = lambda s: f"{s['wrc_plus']:.0f}" if s and s["pa"] >= 100 else "-"
        gwar = lambda s: f"{s['war']:.1f}" if s and s["pa"] >= 100 else "-"
        tw = lambda d: f"{d[nm]:.0f}" if nm in d else "-"
        out(f"| {nm} | {tw(w25)}→{tw(w26)} | {aw(a25)}→{aw(a26)} | {gw(s25)}／{gw(s26)} | "
            f"{t25.get(nm, '-')}→{t26.get(nm, '-')} | {d26.get(nm, '-')} | {gwar(s25)}／{gwar(s26)} |")
        if nm in w26 and a26 and a26["pa"] >= 300:
            cx.append(w26[nm])
            cy.append(a26["wrc_plus"])
    if cx:
        out("")
        out(f"- tooldock の2026年の wRC+ と、この資料で npb.jp から計算した wRC+ の相関 {pearson(cx, cy):.2f}（{len(cx)}人）、"
            f"平均の差（tooldock − この資料）{statistics.mean(a - b for a, b in zip(cx, cy)):+.1f}")
    out("")
    out("| 投手 | FIP 25（tooldock／ヌルデータ置き場） | tooldock FIP 26 | tooldock WAR 25→26 | 1.02 WAR 26 | ゲーム FIP 25／26 | ゲーム WAR 25／26 |")
    out("|---|---|---|---|---|---|---|")
    f25, n25, f26 = metric(2025, "FIP(tooldock)"), metric(2025, "FIP(nf3 ヌルデータ置き場)"), metric(2026, "FIP(tooldock)")
    pw25, pw26 = metric(2025, "WAR(tooldock簡易)"), metric(2026, "WAR(tooldock簡易)")
    pnames = set(f26) | set(f25) | set(n25) | {n for n in d26 if pid_of(n) and pre[pid_of(n)].get("is_pitcher")}
    for nm in sorted(pnames, key=lambda n: f26.get(n, f25.get(n, n25.get(n, 9)))):
        pid = pid_of(nm)
        if not pid or not pre.get(pid, {}).get("is_pitcher"):
            continue
        s25, s26 = sims[2025].pit(pid), sims[2026].pit(pid)
        gf = lambda s: f"{s['fip']:.2f}" if s and s["ip"] >= 30 else "-"
        gwar = lambda s: f"{s['war']:.1f}" if s and s["ip"] >= 30 else "-"
        out(f"| {nm} | {f25.get(nm, '-')}／{n25.get(nm, '-')} | {f26.get(nm, '-')} | {pw25.get(nm, '-')}→{pw26.get(nm, '-')} | "
            f"{d26.get(nm, '-')} | {gf(s25)}／{gf(s26)} | {gwar(s25)}／{gwar(s26)} |")
    u26 = [(r["選手名"], r["球団"], val(r)) for r in rows if r["年"] == "2026" and r["指標名"] == "UZR(DELTA/1.02)"]
    if u26:
        out("")
        out("- 1.02 の2026年の球団ごとの UZR 1位（守備位置の記載なし）：" + "・".join(
            f"{n}（{t}）{v:+.1f}" for n, t, v in sorted(u26, key=lambda t: -t[2])))
    out("")
    out("出典：" + "、".join(f"<{u}>" for u in sorted({r["出典URL"] for r in rows})))
    out("")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--sims", required=True, help="ゲームを回した結果の JSON（glob。2025年・2026年が混ざってよい）")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--saber", type=Path, help="外部のセイバー指標の CSV（年,選手名,球団,守備位置,指標名,値,出典URL）。リポジトリには入れない")
    args = ap.parse_args(argv)
    files = sorted(glob.glob(args.sims))
    sims = {y: Sims([f for f in files if load(f)["year"] == y]) for y in (2025, 2026)}
    R = {k: ratings_index(ROOT / "generated" / "ratings" / f"{k}.json")
         for k in ("2025_pre", "2025_post", "2026_pre", "2026_post", "2023_post")}
    A = {y: Actual(y) for y in (2023, 2025, 2026)}
    titles = {y: A[y].titles() for y in (2023, 2025, 2026)}
    gg = {y: A[y].gg() for y in (2023, 2025)}
    fz = {y: A[y].fld_z() for y in (2025, 2026)}
    lines = []
    out = lines.append

    # ---- 選手の選び方
    name_to_id = {}
    for k in ("2026_pre", "2025_post", "2023_post"):
        for pid, p in R[k].items():
            name_to_id.setdefault(nn(p["name"]), pid)
    def find(nm):
        key = nn(nm)
        if key in name_to_id:
            return name_to_id[key]
        cands = [pid for n, pid in name_to_id.items() if key in n]
        return cands[0] if len(cands) == 1 else None

    bat_ids, pit_ids = [], []
    for y in (2026,):
        for pid in A[y].bat:
            b = A[y].bat_line(pid)
            if b and b["pa"] >= 443 and pid not in bat_ids:
                rp = R["2026_pre"].get(pid) or R["2025_post"].get(pid)
                if rp and not rp["is_pitcher"]:
                    bat_ids.append(pid)
        for pid in A[y].pit:
            p = A[y].pit_line(pid)
            if p and (p["ip"] >= 143 or p["sv"] >= 30 or p["hp"] >= 40) and pid not in pit_ids:
                pit_ids.append(pid)
    missing = []
    for nm in MUST_BAT:
        pid = find(nm)
        if pid is None:
            missing.append(nm)
        elif pid not in bat_ids:
            bat_ids.append(pid)
    for nm in MUST_PIT:
        pid = find(nm)
        if pid is None:
            missing.append(nm)
        elif pid not in pit_ids:
            pit_ids.append(pid)

    def rating_of(pid):
        for k in ("2026_pre", "2025_post", "2023_post"):
            if pid in R[k]:
                return R[k][pid], k
        return None, None

    # ---- 野手の表（能力値と実際の成績）
    def awards_of(pid):
        a = []
        for y in (2025, 2026):
            t = titles[y].get(pid, []) + (gg.get(y, {}).get(pid, []))
            if t:
                a.append(f"{y % 100}:" + "・".join(t))
        return " ".join(a)

    def act_bat(y, pid):
        b = A[y].bat_line(pid)
        if not b or b["pa"] < 50:
            return "-"
        return f"{fmt3(b['avg'])} {b['hr']}本 OPS{fmt3(b['ops'])} ({b['pa']}) **{b['wrc_plus']:.0f}**"

    def sort_key(pid):
        b = A[2026].bat_line(pid) or A[2025].bat_line(pid)
        return -(b["wrc_plus"] if b else 0)

    bat_ids.sort(key=sort_key)
    out("### 野手：能力値（2026年開幕＝2026_pre）と実際の成績")
    out("")
    out("並びは2026年の実際の wRC+ の順（2026年に出ていない選手は2025年）。能力値はランク＋数値。総合はゲームの「デプス」の「現在の能力」のランク（`Depth.now_score`＝実力 z（ミート・パワー35%、選球眼・走力・守備10%）＋0.6×出場量。括弧は点。S≧1.6・A≧1.1・B≧0.65・C≧0.25）。"
        "実績は「打率 本塁打 OPS（打席）**wRC+**」（wRC+ はゲームの記録室と同じ式で npb.jp の1軍成績から計算。100＝リーグ平均）。表彰：25＝2025年、26＝2026年（タイトルは成績から、GG はゴールデングラブ。2026年の GG・ベストナイン・MVP は未発表）")
    out("")
    out("| 選手 | 球団 | 位置 | ミート | パワー | 選球眼 | 走力 | 守備 | 肩 | 総合 | 2025年 実績 | 2026年 実績 | タイトル・表彰 |")
    out("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for pid in bat_ids:
        p, src = rating_of(pid)
        if not p:
            continue
        br = p["batting"]["ratings"]
        ov = bat_overall(br)
        tag = "" if src == "2026_pre" else ("（MLB・2025_post）" if src == "2025_post" else f"（{src}）")
        team = short(p.get("team") or A[2025].team.get(pid, ""))
        out(f"| {p['name']}{tag} | {team} | {POS_SHORT.get(p['primary_pos'], p['primary_pos'] or '-')} | {rv(br.get('meet'))} | "
            f"{rv(br.get('power'))} | {rv(br.get('eye'))} | {rv(br.get('speed'))} | {rv(br.get('defense'))} | {rv(br.get('arm'))} | "
            f"{now_rank(p)} | {act_bat(2025, pid)} | {act_bat(2026, pid)} | {awards_of(pid)} |")
    out("")

    # ---- 野手の表（ゲームを回した結果と比べる）
    out("### 野手：ゲームで回した成績と実際の成績")
    out("")
    n26, n25 = len(sims[2026].runs), len(sims[2025].runs)
    out(f"ゲームは開始年を2026年（{n26}回）・2025年（{n25}回）にして公式戦を最後まで回した平均（自球団は阪神、CPU と同じ自動の采配）。"
        "守備得点は（範囲／失策／肩）の内訳つき、±は回ごとのばらつき（標準偏差）。守備位置はゲームで最も多く先発した位置と、実際に最も多く守った位置（npb.jp、外野は左中右の区別なし）。"
        "実際の守備は npb.jp の守備成績から、同じ守備位置（40試合以上）の中での z 値：失策率（＋が失策が少ない）／RF＝(刺殺＋補殺)/試合（＋が多くの打球を処理）／補殺/試合")
    out("")
    out("| 選手 | 実際の wRC+ 25→26 | ゲーム26 wRC+ | ゲーム26 打率・本 | ゲーム26 守備位置 | 実際26 守備位置 | ゲーム26 守備得点（範囲/失策/肩） | 実際26 守備 z（失策率/RF/補殺） | ゲーム26 WAR | 実際26 WAR（守備抜き） | ゲーム25 wRC+・WAR |")
    out("|---|---|---|---|---|---|---|---|---|---|---|")
    for pid in bat_ids:
        p, src = rating_of(pid)
        if not p:
            continue
        a25, a26 = A[2025].bat_line(pid), A[2026].bat_line(pid)
        s26, s25 = sims[2026].bat(pid), sims[2025].bat(pid)
        aw = lambda b: f"{b['wrc_plus']:.0f}" if b and b["pa"] >= 100 else "-"
        mp, mg = A[2026].main_pos(pid)
        zpos = mp if mp else None
        z = fz[2026].get(pid, {}).get(zpos, {}) if zpos else {}
        zs = f"{z['err']:+.1f}/{z['rf']:+.1f}/{z['ast']:+.1f}" if z else "-"
        if s26:
            c = s26["cat"]
            arm = c.get("arm", 0) + c.get("cs", 0) + c.get("wp", 0)
            g26 = f"{s26['wrc_plus']:.0f}"
            gl = f"{fmt3(s26['avg'])} {s26['hr']:.0f}本"
            gpos = f"{POS_SHORT.get(s26['main'], s26['main'])}({s26['posg'].get(s26['main'], 0):.0f})" if s26["posg"] else "控え"
            gf = f"{s26['fld']:+.1f}±{s26['fld_sd']:.1f}（{c.get('rng', 0):+.1f}/{c.get('err', 0):+.1f}/{arm:+.1f}）"
            gw = f"**{s26['war']:.1f}**±{s26['war_sd']:.1f}"
        else:
            g26 = gl = gpos = gf = gw = "-"
        g25 = f"{s25['wrc_plus']:.0f}・{s25['war']:.1f}" if s25 and s25["pa"] >= 100 else "-"
        apos = f"{POS_SHORT.get(mp, mp)}({mg})" if mp else "-"
        aw26 = f"{a26['war']:.1f}" if a26 and a26["pa"] >= 100 else "-"
        out(f"| {p['name']} | {aw(a25)}→{aw(a26)} | {g26} | {gl} | {gpos} | {apos} | {gf} | {zs} | {gw} | {aw26} | {g25} |")
    out("")

    # ---- 投手の表
    def act_pit(y, pid):
        p = A[y].pit_line(pid)
        if not p or p["ip"] < 20:
            return "-"
        extra = f" {p['sv']}S" if p["sv"] >= 10 else (f" {p['hp']}HP" if p["hp"] >= 20 else f" {p['w']}勝")
        return f"{p['ip']:.0f}回 {p['era']:.2f}/{p['fip']:.2f}{extra}"

    def pit_key(pid):
        p = A[2026].pit_line(pid) or A[2025].pit_line(pid) or A[2023].pit_line(pid)
        if not p:
            return 99
        return p["fip"] - min(p["ip"], 180) / 200  # 先発の主力を上に
    pit_ids.sort(key=pit_key)
    out("### 投手：能力値（2026_pre）・実際の成績・ゲームで回した成績")
    out("")
    out("実績は「投球回 防御率/FIP 勝利かセーブ・HP」（FIP は npb.jp の成績から、リーグの防御率に合わせた定数）。ゲームは上と同じ回し方の平均（投球回・防御率/FIP・WAR）")
    out("")
    out("| 投手 | 球団 | 役割 | 総合力 | 現在の能力 | スタミナ | 奪三振 | 制球 | 被弾 | 球速 | 2025年 実績 | 2026年 実績 | タイトル・表彰 | ゲーム26 | ゲーム26 WAR | 実際26 WAR | ゲーム25 |")
    out("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for pid in pit_ids:
        p, src = rating_of(pid)
        if not p or not p.get("pitching"):
            continue
        pr = p["pitching"]["ratings"]
        tag = "" if src == "2026_pre" else ("（MLB・2025_post）" if src == "2025_post" else f"（{src}）")
        s26, s25 = sims[2026].pit(pid), sims[2025].pit(pid)
        g26 = f"{s26['ip']:.0f}回 {s26['era']:.2f}/{s26['fip']:.2f}" if s26 else "-"
        gw = f"**{s26['war']:.1f}**±{s26['war_sd']:.1f}" if s26 else "-"
        g25 = f"{s25['ip']:.0f}回 {s25['era']:.2f}/{s25['fip']:.2f}・{s25['war']:.1f}" if s25 else "-"
        ap26 = A[2026].pit_line(pid)
        aw26 = f"{ap26['war']:.1f}" if ap26 and ap26["ip"] >= 20 else "-"
        a23 = f"（23: {act_pit(2023, pid)} {'・'.join(titles[2023].get(pid, []))}）" if src == "2023_post" else ""
        team = short(p.get("team") or A[2025].team.get(pid, "") or A[2023].team.get(pid, ""))
        out(f"| {p['name']}{tag} | {team} | {p['pitching']['role']} | {rv(pr.get('overall'))} | {now_rank(p)} | {rv(pr.get('stamina'))} | "
            f"{rv(pr.get('k9'))} | {rv(pr.get('bb9'))} | {rv(pr.get('hr9'))} | {p['pitching']['velocity']['kmh']} | "
            f"{act_pit(2025, pid)}{a23} | {act_pit(2026, pid)} | {awards_of(pid)} | {g26} | {gw} | {aw26} | {g25} |")
    out("")

    # ---- 要約の数字
    out("### 要約の数字")
    out("")
    for y in (2026, 2025):
        xs, ys = [], []
        for pid in A[y].bat:
            a = A[y].bat_line(pid)
            s = sims[y].bat(pid)
            if a and s and a["pa"] >= 300 and s["pa"] >= 300:
                xs.append(a["wrc_plus"])
                ys.append(s["wrc_plus"])
        if xs:
            out(f"- {y}年 野手（実際・ゲームとも300打席以上、{len(xs)}人）：実際の wRC+ とゲームの wRC+ の相関 {pearson(xs, ys):.2f}、"
                f"ばらつき（標準偏差）実際 {statistics.pstdev(xs):.1f} ／ゲーム {statistics.pstdev(ys):.1f}、"
                f"上位5人の平均 実際 {statistics.mean(sorted(xs)[-5:]):.0f} ／ゲーム {statistics.mean(sorted(ys)[-5:]):.0f}")
        xs, ys = [], []
        for pid in A[y].pit:
            a = A[y].pit_line(pid)
            s = sims[y].pit(pid)
            if a and s and a["ip"] >= 100 and s["ip"] >= 100:
                xs.append(a["fip"])
                ys.append(s["fip"])
        if xs:
            out(f"- {y}年 投手（実際・ゲームとも100回以上、{len(xs)}人）：実際の FIP とゲームの FIP の相関 {pearson(xs, ys):.2f}、"
                f"ばらつき 実際 {statistics.pstdev(xs):.2f} ／ゲーム {statistics.pstdev(ys):.2f}")
    # 1回ごと（平均しない）のばらつき：実際の1シーズンと同じ条件で比べる
    for y in (2026, 2025):
        g = [r["batting"][i]["row"]["wrc_plus"] for r in sims[y].runs for i in r["batting"]
             if r["batting"][i]["row"]["pa"] >= 300]
        a = [A[y].bat_line(i)["wrc_plus"] for i in A[y].bat if A[y].bat_line(i) and A[y].bat_line(i)["pa"] >= 300]
        gp = [r["pitching"][i]["row"]["fip"] for r in sims[y].runs for i in r["pitching"] if r["pitching"][i]["row"]["ip"] >= 300]
        ap = [A[y].pit_line(i)["fip"] for i in A[y].pit if A[y].pit_line(i) and A[y].pit_line(i)["ip"] >= 100]
        out(f"- {y}年 1回ごとのばらつき（平均しない）：野手 wRC+ 実際 {statistics.pstdev(a):.1f} ／ゲーム {statistics.pstdev(g):.1f}、"
            f"投手 FIP 実際 {statistics.pstdev(ap):.2f} ／ゲーム {statistics.pstdev(gp):.2f}")
    # WAR の上位（実際＝同じ式・守備抜き、ゲーム＝10回の平均）
    for y in (2026, 2025):
        ab = sorted(((A[y].bat_line(i)["war"], A[y].name[i]) for i in A[y].bat if A[y].bat_line(i)), reverse=True)[:10]
        ap = sorted(((A[y].pit_line(i)["war"], A[y].name[i]) for i in A[y].pit if A[y].pit_line(i)), reverse=True)[:10]
        ids_b = set().union(*[set(r["batting"]) for r in sims[y].runs]) if sims[y].runs else set()
        ids_p = set().union(*[set(r["pitching"]) for r in sims[y].runs]) if sims[y].runs else set()
        gb = sorted(((sims[y].bat(i)["war"] * sims[y].bat(i)["n"] / len(sims[y].runs), sims[y].bat(i)) for i in ids_b),
                    key=lambda t: -t[0])[:10]
        gp = sorted(((sims[y].pit(i)["war"] * sims[y].pit(i)["n"] / len(sims[y].runs), i) for i in ids_p), key=lambda t: -t[0])[:10]
        nm = {}
        for r in sims[y].runs:
            for i, x in list(r["batting"].items()) + list(r["pitching"].items()):
                nm[i] = x["name"]
        rev = {id(v[1]): k for k, v in []}
        out(f"- {y}年 WAR の上位10人（実際＝npb.jp の成績を同じ式で、守備得点なし）：野手 " +
            "・".join(f"{n} {w:.1f}" for w, n in ab) + "／投手 " + "・".join(f"{n} {w:.1f}" for w, n in ap))
        gbn = sorted(((sims[y].bat(i)["war"] * sims[y].bat(i)["n"] / len(sims[y].runs), nm[i]) for i in ids_b), reverse=True)[:10]
        gpn = sorted(((sims[y].pit(i)["war"] * sims[y].pit(i)["n"] / len(sims[y].runs), nm[i]) for i in ids_p), reverse=True)[:10]
        out(f"- {y}年 WAR の上位10人（ゲーム{len(sims[y].runs)}回の平均）：野手 " +
            "・".join(f"{n} {w:.1f}" for w, n in gbn) + "／投手 " + "・".join(f"{n} {w:.1f}" for w, n in gpn))
    # 目盛り：規定打席クラスのランクの分布
    for key in ("2026_pre",):
        cnt = defaultdict(lambda: defaultdict(int))
        n = 0
        for pid, p in R[key].items():
            if p.get("_mlb") or p["is_pitcher"]:
                continue
            if (p["batting"]["sample"]["pa_1"] or 0) < 900:  # 加重で900打席＝3年ほぼ毎年規定
                continue
            n += 1
            br = p["batting"]["ratings"]
            for k in ("meet", "power", "eye", "speed", "defense", "arm"):
                if isinstance(br.get(k), dict):
                    cnt[k][br[k]["rank"]] += 1
            ov = bat_overall(br)
            cnt["overall"][rank_of(ov)] += 1
            cnt["now"][now_rank(p)[0]] += 1
        out(f"- {key} の野手でレギュラー級（加重の1軍打席900以上、{n}人）のランクの人数：")
        for k, label in (("meet", "ミート"), ("power", "パワー"), ("eye", "選球眼"), ("speed", "走力"),
                         ("defense", "守備"), ("arm", "肩"), ("overall", "重みつき平均を 63+17z に置いた総合（参考）"),
                         ("now", "現在の能力（デプス）")):
            out(f"  - {label}：" + "・".join(f"{r}{cnt[k].get(r, 0)}" for _, r in RANKS))
    # 守備得点の再現性（同じ選手を回し直したときのばらつき vs 選手の間の差）
    out("")
    out("#### 守備得点の再現性（2026年、守備イニングが多い選手）")
    out("")
    by_pos = defaultdict(list)
    for pid in set().union(*[set(r["batting"]) for r in sims[2026].runs]):
        s = sims[2026].bat(pid)
        if s and s["n"] >= max(2, n26 - 1) and s["pa"] >= 400:
            by_pos[s["main"]].append(dict(s, id=pid))
    out("| 守備位置 | 人数 | 選手の間の差（平均の標準偏差） | 回ごとのばらつき（1人の標準偏差の平均） | 能力値の守備力との相関 |")
    out("|---|---|---|---|---|")
    pre = R["2026_pre"]
    for pos in ("捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手"):
        rows = by_pos.get(pos, [])
        if len(rows) < 4:
            continue
        means = [r["fld"] for r in rows]
        within = statistics.mean(r["fld_sd"] for r in rows)
        key = "外野手" if pos in ("左翼手", "中堅手", "右翼手") else pos
        xs, ys = [], []
        for r in rows:
            f = (pre.get(r["id"], {}).get("fielding") or {}).get(key)
            if f:
                xs.append(f["defense"]["value"])
                ys.append(r["fld"])
        out(f"| {pos} | {len(rows)} | {statistics.pstdev(means):.1f} | {within:.1f} | {pearson(xs, ys):.2f} |")
    out("")

    # ---- 自動のオーダーの守備位置
    out("#### 開幕の自動のオーダー（2026年、DH あり）と実際に最も多く守った位置")
    out("")
    out("ゲームの位置と実際の位置（npb.jp の2026年の守備で最も試合の多い位置。外野は左中右の区別なし）が違う選手だけ。「能力値」はゲームが使ったその位置の守備力（2026_pre）")
    out("")
    out("| 球団 | 選手 | ゲームの位置 | 実際の位置（試合） | 2025年のその位置の1軍試合 | 能力値（その位置の守備力） |")
    out("|---|---|---|---|---|---|")
    fld_key = lambda s: "外野手" if s in ("左翼手", "中堅手", "右翼手") else s
    for team, rows in sorted(sims[2026].lineups().items()):
        for name, slot, pid in rows:
            if slot in ("指名打者", "投手") or not pid:
                continue
            mp, mg = A[2026].main_pos(pid)
            key = fld_key(slot)
            if mp == key and key != "外野手":
                continue
            p = pre.get(pid, {})
            f = (p.get("fielding") or {}).get(key)
            prev = f["games"] if f else 0
            ab = rv(f["defense"]) if f else "記録なし（−2.5σ）"
            if mp == key:
                # 外野手どうし：中堅に入ったのに本職が両翼か、は npb.jp では分からない（評判で見る）
                if slot != "中堅手":
                    continue
                note = "外野（中堅かは不明）"
                out(f"| {short(team)} | {name} | {slot} | {note}({mg}) | {prev} | {ab} |")
                continue
            out(f"| {short(team)} | {name} | {slot} | {POS_SHORT.get(mp, mp) if mp else '-'}({mg}) | {prev} | {ab} |")
    out("")
    if args.saber and args.saber.exists():
        saber_section(out, args.saber, R, A, sims)
    if missing:
        out(f"（名前が見つからなかった選手：{'・'.join(missing)}）")
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{args.out}：野手 {len(bat_ids)}人・投手 {len(pit_ids)}人（ゲーム 2026年 {n26}回・2025年 {n25}回）")


if __name__ == "__main__":
    main()
