"""成長・衰え・引退の係数（docs/AUTORUN.md 作業27）。

generated/ratings/<年>_pre.json（開幕時点）の同じ選手の「1年での能力の変化」（<年>_pre → <年+1>_pre）を、
年齢・能力の高さ・出場の多さごとに集計して generated/growth.json に書き出す。
Godot の `Growth`（godot/sim/growth.gd）が史実の無い年（2028年〜）の春季キャンプで「今の能力 → 来季の開幕時点の能力」に使う。
開幕時点どうしの組なので、新人・新外国人の「事前値 → 1年目の成績が入った値」の変化も入る。

    python tools/growth_coefficients.py            # 2008→2009 〜 LAST_FROM→LAST_FROM+1 の組で集計

モデル（能力の項目ごと、投手・野手別）:
    来年の値 = 今の値 + a(年齢) + b(年齢) × (今の値 − 中心) + sd(年齢) × ゆらぎ
- 年齢は来季の4月1日時点の満年齢。a・b・sd は年齢ごとに、近い年齢の組に重みを付けた回帰（ガウス核、幅 AGE_BANDWIDTH）
- 前年までの出場が多い選手（加重の打席・アウト数 100 以上。2軍は半分）と少ない選手（新人・新外国人）で別々に集計
  （keys / keys_low。少ない側は年齢の幅 LOW_AGE_BANDWIDTH、外国人は除く）。少ない選手の値は事前値に寄せたもので、
  多い選手の回帰をそのまま当てると平均へ引き上げられすぎるため。Godot では入団して最初の1回だけ少ない側を使う
- 引退は <年>_post → <年+1>_post（シーズン後の出場・実力で、来季の名簿にいるか）
- 守備の記録が無い新人の野手（primary_pos は「内野手」など）は、史実の新人の2年目の守備位置・守備力の例（rookie_fielding）から1つ選ぶ
- ゆらぎは残差を sd で割った値の分位点（裾の重い「急成長・急な衰え」も史実どおり）と、
  同じ選手の項目どうしの相関行列（のコレスキー分解）
- 投手の役割（先発・救援）は来季に先発になる確率のロジスティック回帰（今の役割ごと。年齢・スタミナ・総合・出場の少なさ）で
  移り変わり、スタミナは移り変わりの種類（先発>先発 など）ごとの回帰で動かす（スタミナは役割で2つの山に分かれるため）
- 投手の総合だけは、役割ごとに K/9・BB/9・HR/9 の値からの回帰＋選手ごとのずれ（翌年に縮む）で出す（derived）
- リーグ全体の平均・ばらつき（target。開幕時点の全選手）：毎年これに少し寄せて、何十年進めても分布が変わらないようにする
- 引退：来季のファイルにいない確率のロジスティック回帰（年齢・実力・出場・外国人・投手）
標準ライブラリのみ。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATINGS = ROOT / "generated" / "ratings"
OUT = ROOT / "generated" / "growth.json"

FIRST_FROM = 2008
LAST_FROM = 2025  # 2025_pre → 2026_pre（2026_pre は2025年までの成績）。2026年の最終成績で 2027_pre ができたら 2026 に
RETIRE_LAST_FROM = 2025  # 引退は「来季の名簿にいるか」だけなので 2025→2026 まで使える
TARGET_YEARS = range(2017, 2027)  # リーグ全体の平均・ばらつきの基準（直近10年の開幕時点＝<年>_pre。成長を当てる時点と同じ顔ぶれ）

CENTER = 63.0  # 能力値の正規化の中心（tools/README.md「スケール」）
VELOCITY_CENTER = 145.0
AGE_MIN, AGE_MAX = 18, 42
AGE_BANDWIDTH = 1.5
LOW_AGE_BANDWIDTH = 3.0
LOW_SHRINK_N = 40.0  # 出場の少ない側は、その年齢の組が少ないほど多い側の係数に寄せる（n_eff / (n_eff + これ)）
# 出場の多い・少ないの境（加重の打席・アウト数。2軍は半分）
MIN_SAMPLE_PA = 100.0
MIN_SAMPLE_OUTS = 100.0
QUANTILE_PROBS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5,
                  0.6, 0.7, 0.8, 0.9, 0.95, 0.975, 0.99, 0.995, 0.999]

BATTING_KEYS = ["meet", "power", "eye", "speed", "defense", "arm"]
PITCHING_KEYS = ["overall", "stamina", "k9", "bb9", "hr9", "velocity"]
# 投手の総合は FIP（K・BB・HR）から出しているので、成長では総合を K/9・BB/9・HR/9 の値から出す
#（別々に動かすと総合と内訳の相関が年々薄れ、総合で選ばれた投手が実際には打たれるようになり、20年で防御率が1点以上悪くなる）
OVERALL_FROM = ["k9", "bb9", "hr9"]

# Salary.ability と同じ実力の z（引退の回帰に使う。godot/sim/salary.gd）
PITCHER_Z_SCALE = 0.85
RELIEVER_Z_SCALE = 0.65
FULL_PA = 480.0
FULL_OUTS_STARTER = 450.0
FULL_OUTS_RELIEVER = 170.0
SAMPLE_YEARS = 2.4
FOREIGN_EXEMPT_SEASONS = 9  # RosterRules.FOREIGN_EXEMPT_SEASONS


def load(year: int, phase: str = "post") -> dict:
    data = json.loads((RATINGS / f"{year}_{phase}.json").read_text(encoding="utf-8"))
    return {p["id"]: p for p in data["players"]}


def age_at(p: dict, year: int) -> int | None:
    b = p.get("birth")
    if not b:
        return None
    by, bm, bd = map(int, b.split("-"))
    return year - by - (1 if (bm, bd) > (4, 1) else 0)


def value_of(p: dict, side: str, key: str) -> float | None:
    if side == "P":
        pit = p.get("pitching")
        if not isinstance(pit, dict):
            return None
        if key == "velocity":
            v = pit.get("velocity") or {}
            return float(v["kmh"]) if v.get("kmh") and v.get("source") == "observed" else None
        r = (pit.get("ratings") or {}).get(key)
    else:
        bat = p.get("batting")
        if not isinstance(bat, dict):
            return None
        r = (bat.get("ratings") or {}).get(key)
    return float(r["value"]) if isinstance(r, dict) and r.get("value") is not None else None


def side_of(p: dict) -> str | None:
    if p.get("is_pitcher") and isinstance(p.get("pitching"), dict):
        return "P"
    if not p.get("is_pitcher") and isinstance(p.get("batting"), dict):
        return "B"
    return None


def sample_of(p: dict, side: str) -> float:
    if side == "P":
        s = p["pitching"].get("sample") or {}
        return float(s.get("outs_1", 0)) + 0.5 * float(s.get("outs_2", 0))
    s = p["batting"].get("sample") or {}
    return float(s.get("pa_1", 0)) + 0.5 * float(s.get("pa_2", 0))


def z_of(p: dict, side: str, key: str, fallback: float = 45.0) -> float:
    v = value_of(p, side, key)
    return ((v if v is not None else fallback) - CENTER) / 17.0


def ability(p: dict, side: str) -> tuple[float, float]:
    """Salary.ability と同じ [実力 z, 出場量 0〜1]"""
    if side == "P":
        pit = p["pitching"]
        z = PITCHER_Z_SCALE * (0.75 * z_of(p, "P", "overall") + 0.25 * z_of(p, "P", "k9"))
        outs = float((pit.get("sample") or {}).get("outs_1", 0)) / SAMPLE_YEARS
        if pit.get("role") == "先発":
            return z, min(1.0, outs / FULL_OUTS_STARTER)
        return z * RELIEVER_Z_SCALE, min(1.0, outs / FULL_OUTS_RELIEVER)
    pa = float((p["batting"].get("sample") or {}).get("pa_1", 0)) / SAMPLE_YEARS
    z = (0.35 * z_of(p, "B", "meet") + 0.35 * z_of(p, "B", "power") + 0.1 * z_of(p, "B", "eye")
         + 0.1 * z_of(p, "B", "speed") + 0.1 * z_of(p, "B", "defense", 63.0))
    return z, min(1.0, pa / FULL_PA)


def is_foreign(p: dict, year: int, debut: dict) -> bool:
    """RosterRules.is_foreign と同じ判定"""
    if p.get("provisional_id"):
        return False
    draft, career = p.get("draft"), p.get("career")
    if (isinstance(draft, str) and draft) or not isinstance(career, str) or not career:
        return False
    d = debut.get(p["id"])
    return not (d is not None and year - int(d) >= FOREIGN_EXEMPT_SEASONS)


def debut_years() -> dict:
    out: dict = {}
    for y in range(2008, 2027):
        path = ROOT / "data" / str(y) / "rosters.json"
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        rows = data.get("players", data) if isinstance(data, dict) else data
        for r in rows:
            if isinstance(r, dict) and r.get("player_id") and r.get("debut_year"):
                out.setdefault(r["player_id"], r["debut_year"])
    return out


def mlb_leavers() -> set:
    rows = json.loads((ROOT / "data" / "mlb_moves.json").read_text(encoding="utf-8"))
    return {(r["player_id"], int(r["left_after"])) for r in rows if r.get("player_id") and r.get("left_after")}


# --- 年齢ごとの回帰 -------------------------------------------------------------------

def kernel_fit(rows: list[tuple[int, float, float]], center: float, bandwidth: float = AGE_BANDWIDTH) -> dict:
    """rows = [(年齢, 今の値, 来年の値)] → 年齢ごとの a, b, sd"""
    out = {"ages": [], "a": [], "b": [], "sd": []}
    for age in range(AGE_MIN, AGE_MAX + 1):
        sw = sx = sy = sxx = sxy = 0.0
        for a, cur, nxt in rows:
            w = math.exp(-0.5 * ((a - age) / bandwidth) ** 2)
            x, y = cur - center, nxt - cur
            sw += w
            sx += w * x
            sy += w * y
            sxx += w * x * x
            sxy += w * x * y
        mx, my = sx / sw, sy / sw
        b = (sxy - sw * mx * my) / max(1e-9, sxx - sw * mx * mx)
        a = my - b * mx
        sr = 0.0
        for ag, cur, nxt in rows:
            w = math.exp(-0.5 * ((ag - age) / bandwidth) ** 2)
            r = (nxt - cur) - a - b * (cur - center)
            sr += w * r * r
        out["ages"].append(age)
        out.setdefault("n_eff", []).append(round(sw, 1))
        out["a"].append(round(a, 3))
        out["b"].append(round(b, 4))
        out["sd"].append(round(math.sqrt(sr / sw), 3))
    return out


def shrink_to(fit: dict, base: dict) -> None:
    """組の少ない年齢の係数を base（出場の多い側）に寄せる"""
    for i, n in enumerate(fit["n_eff"]):
        k = n / (n + LOW_SHRINK_N)
        for f in ("a", "b", "sd"):
            fit[f][i] = round(k * fit[f][i] + (1 - k) * base[f][i], 4)


def at_age(fit: dict, age: int, field: str) -> float:
    i = min(max(age, AGE_MIN), AGE_MAX) - AGE_MIN
    return fit[field][i]


def quantiles(values: list[float]) -> list[float]:
    s = sorted(values)
    n = len(s)
    out = []
    for p in QUANTILE_PROBS:
        k = p * (n - 1)
        lo = int(math.floor(k))
        hi = min(n - 1, lo + 1)
        out.append(round(s[lo] + (s[hi] - s[lo]) * (k - lo), 3))
    return out


def corr_cholesky(resid: dict[str, dict], keys: list[str]) -> tuple[list[list[float]], dict]:
    """同じ選手・同じ年の標準化残差の相関行列と、そのコレスキー分解（下三角。ゆらぎを相関させて引くのに使う）。
    組ごとに数えた相関で正定値にならないときは、非対角を少しずつ縮める"""
    n = len(keys)
    corr = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            ids = resid[keys[i]].keys() & resid[keys[j]].keys()
            if len(ids) < 50:
                continue
            xs = [resid[keys[i]][t] for t in ids]
            ys = [resid[keys[j]][t] for t in ids]
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
            vx = sum((x - mx) ** 2 for x in xs)
            vy = sum((y - my) ** 2 for y in ys)
            corr[i][j] = corr[j][i] = cov / math.sqrt(vx * vy)
    shrink = 1.0
    while True:
        m = [[corr[i][j] * (1.0 if i == j else shrink) for j in range(n)] for i in range(n)]
        low = cholesky(m)
        if low is not None:
            break
        shrink *= 0.95
    named = {f"{keys[i]}|{keys[j]}": round(corr[i][j], 3) for i in range(n) for j in range(i + 1, n)}
    return [[round(x, 4) for x in row] for row in low], named


def cholesky(m: list[list[float]]) -> list[list[float]] | None:
    n = len(m)
    low = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = m[i][j] - sum(low[i][k] * low[j][k] for k in range(j))
            if i == j:
                if s <= 1e-6:
                    return None
                low[i][j] = math.sqrt(s)
            else:
                low[i][j] = s / low[j][j]
    return low


def derive_overall(pre_files: dict) -> dict:
    """役割（先発・救援）ごとに 総合 = const + Σ c × 内訳 + r（最小二乗、TARGET_YEARS の開幕時点）。
    r（選手ごとのずれ）は翌年 rho 倍に縮み、sd × √(1−rho²) のゆらぎが足される（rho は翌年の r との相関）"""
    out = {}
    for role in ["先発", "救援"]:
        xs, ys, keys = [], [], []
        for y in TARGET_YEARS:
            for pid, p in pre_files[y].items():
                if side_of(p) != "P" or p["pitching"].get("role") != role:
                    continue
                v = [value_of(p, "P", k) for k in OVERALL_FROM + ["overall"]]
                if None in v:
                    continue
                xs.append([1.0] + v[:-1])
                ys.append(v[-1])
                keys.append((pid, y))
        k = len(xs[0])
        xtx = [[sum(x[i] * x[j] for x in xs) for j in range(k)] for i in range(k)]
        xty = [sum(x[i] * y for x, y in zip(xs, ys)) for i in range(k)]
        c = solve(xtx, xty)
        res = {key: y - sum(ci * xi for ci, xi in zip(c, x)) for key, x, y in zip(keys, xs, ys)}
        sd = math.sqrt(sum(r * r for r in res.values()) / len(res))
        pairs = [(r, res[(pid, y + 1)]) for (pid, y), r in res.items() if (pid, y + 1) in res]
        rho = sum(a * b for a, b in pairs) / math.sqrt(sum(a * a for a, _ in pairs) * sum(b * b for _, b in pairs))
        my = sum(ys) / len(ys)
        vy = sum((y - my) ** 2 for y in ys) / len(ys)
        out[role] = {"const": round(c[0], 4), "from": {key: round(ci, 4) for key, ci in zip(OVERALL_FROM, c[1:])},
                     "sd": round(sd, 3), "rho": round(rho, 3), "r2": round(1 - sd * sd / vy, 3), "n": len(ys)}
    return out


# --- 新人の守備位置 ------------------------------------------------------------------

ROOKIE_FIELDING_MAX = 200


def rookie_fielding_sample(p: dict, q: dict | None) -> dict | None:
    """守備の記録が無い野手の新人 p が、翌年 q で付いた守備位置ごとの守備力・肩力"""
    if q is None or side_of(p) != "B" or side_of(q) != "B" or p.get("fielding") or not p.get("draft"):
        return None
    fielding = {}
    for pos, f in (q.get("fielding") or {}).items():
        d = (f.get("defense") or {}).get("value")
        if d is None:
            continue
        entry = {"defense": d}
        if isinstance(f.get("arm"), dict) and f["arm"].get("value") is not None:
            entry["arm"] = f["arm"]["value"]
        fielding[pos] = entry
    if not fielding or q.get("primary_pos") not in fielding:
        return None
    return {"primary_pos": q["primary_pos"], "fielding": fielding}


# --- 投手の役割 ----------------------------------------------------------------------

ROLE_FEATURES = ["const", "age_27", "stamina_z", "overall_z", "low"]


def role_of(p: dict) -> str:
    return "先発" if p["pitching"].get("role") == "先発" else "救援"


def role_features(age: int, p: dict, low: bool) -> list[float]:
    st = value_of(p, "P", "stamina")
    ov = value_of(p, "P", "overall")
    return [1.0, age - 27.0, ((st if st is not None else 40.0) - CENTER) / 17.0,
            ((ov if ov is not None else 45.0) - CENTER) / 17.0, 1.0 if low else 0.0]


# --- 引退（ロジスティック回帰） ------------------------------------------------------

RETIRE_FEATURES = ["const", "age_30", "over_33", "under_26", "z", "playing", "foreign", "pitcher"]


def retire_features(age: int, z: float, playing: float, foreign: bool, pitcher: bool) -> list[float]:
    return [1.0, age - 30.0, max(0.0, age - 33.0), max(0.0, 26.0 - age), z, playing,
            1.0 if foreign else 0.0, 1.0 if pitcher else 0.0]


def logistic_fit(xs: list[list[float]], ys: list[int]) -> list[float]:
    """ニュートン法（小さなリッジ付き）"""
    k = len(xs[0])
    w = [0.0] * k
    for _ in range(30):
        g = [0.0] * k
        hess = [[0.0] * k for _ in range(k)]
        for x, y in zip(xs, ys):
            t = sum(wi * xi for wi, xi in zip(w, x))
            p = 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, t))))
            for i in range(k):
                g[i] += (y - p) * x[i]
                for j in range(k):
                    hess[i][j] += p * (1 - p) * x[i] * x[j]
        for i in range(k):
            g[i] -= 1e-3 * w[i]
            hess[i][i] += 1e-3
        step = solve(hess, g)
        w = [wi + si for wi, si in zip(w, step)]
        if max(abs(s) for s in step) < 1e-7:
            break
    return w


def solve(a: list[list[float]], b: list[float]) -> list[float]:
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[piv] = m[piv], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                for k in range(c, n + 1):
                    m[r][k] -= f * m[c][k]
    return [m[i][n] / m[i][i] for i in range(n)]


def main() -> None:
    debut = debut_years()
    leavers = mlb_leavers()
    rows: dict[tuple[str, str], list] = {}
    pair_ids: dict[tuple[str, str], list] = {}
    retire_x: list[list[float]] = []
    retire_y: list[int] = []
    retire_rows: list[tuple] = []
    role_x: dict[str, list] = {}
    role_y: dict[str, list] = {}
    stamina_rows: dict[str, list] = {}
    files = {y: load(y) for y in range(FIRST_FROM, RETIRE_LAST_FROM + 2)}
    pre_files = {y: load(y, "pre") for y in range(FIRST_FROM, LAST_FROM + 2)}
    for y in range(FIRST_FROM, RETIRE_LAST_FROM + 1):
        cur, nxt = files[y], files[y + 1]
        for pid, p in cur.items():
            side = side_of(p)
            age = age_at(p, y + 1)
            if side is None or age is None:
                continue
            q = nxt.get(pid)
            # 引退：メジャーへ行った選手は除く
            if (pid, y) not in leavers:
                z, playing = ability(p, side)
                foreign = is_foreign(p, y, debut)
                retire_x.append(retire_features(age, z, playing, foreign, side == "P"))
                retire_y.append(0 if q is not None else 1)
                retire_rows.append((age, z, playing, foreign, side, retire_y[-1]))
    # 成長：開幕時点どうし（<年>_pre → <年+1>_pre）
    rookie_fielding: dict[str, list] = {}
    for y in range(FIRST_FROM, LAST_FROM + 1):
        cur, nxt = pre_files[y], pre_files[y + 1]
        for pid, p in cur.items():
            sample = rookie_fielding_sample(p, nxt.get(pid))
            if sample is not None:
                rookie_fielding.setdefault(p.get("primary_pos") or "", []).append(sample)
            side = side_of(p)
            age = age_at(p, y + 1)
            q = nxt.get(pid)
            if side is None or age is None or q is None or side_of(q) != side:
                continue
            group = "regular" if sample_of(p, side) >= (MIN_SAMPLE_OUTS if side == "P" else MIN_SAMPLE_PA) else "low"
            # 新外国人の事前値は当てにならず（1年目に大きく動く）、2028年以降は新外国人がいないので出場の少ない側から除く
            if group == "low" and is_foreign(p, y, debut):
                continue
            if side == "P":
                r0, r1 = role_of(p), role_of(q)
                role_x.setdefault(r0, []).append(role_features(age, p, group == "low"))
                role_y.setdefault(r0, []).append(1 if r1 == "先発" else 0)
                st0, st1 = value_of(p, "P", "stamina"), value_of(q, "P", "stamina")
                if st0 is not None and st1 is not None:
                    stamina_rows.setdefault(f"{r0}>{r1}", []).append((age, st0, st1))
            for key in (PITCHING_KEYS if side == "P" else BATTING_KEYS):
                a, b = value_of(p, side, key), value_of(q, side, key)
                if a is None or b is None:
                    continue
                rows.setdefault((side, key, group), []).append((age, a, b))
                pair_ids.setdefault((side, key, group), []).append((pid, y))

    out: dict = {
        "schema_version": 2,
        "source": f"generated/ratings/<年>_pre.json {FIRST_FROM}→{FIRST_FROM + 1} 〜 {LAST_FROM}→{LAST_FROM + 1}"
                  f"（引退は <年>_post.json 〜{RETIRE_LAST_FROM}→{RETIRE_LAST_FROM + 1}）",
        "age_note": "来季の4月1日時点の満年齢",
        "center": CENTER, "velocity_center": VELOCITY_CENTER,
        "age_min": AGE_MIN, "age_max": AGE_MAX,
        "quantile_probs": QUANTILE_PROBS,
    }
    for side, keys, label in [("B", BATTING_KEYS, "batting"), ("P", PITCHING_KEYS, "pitching")]:
        block: dict = {"keys": {}, "keys_low": {}, "order": keys,
                       "full_sample": MIN_SAMPLE_OUTS if side == "P" else MIN_SAMPLE_PA}
        resid: dict[str, dict] = {k: {} for k in keys}
        pooled: list[float] = []
        for key in keys:
            center = VELOCITY_CENTER if key == "velocity" else CENTER
            for group, field, bw in [("regular", "keys", AGE_BANDWIDTH), ("low", "keys_low", LOW_AGE_BANDWIDTH)]:
                r = rows.get((side, key, group), [])
                fit = kernel_fit(r, center, bw)
                fit["center"] = center
                fit["n"] = len(r)
                if field == "keys_low":
                    shrink_to(fit, block["keys"][key])
                block[field][key] = fit
                for (age, a, b), ident in zip(r, pair_ids[(side, key, group)]):
                    e = ((b - a) - at_age(fit, age, "a") - at_age(fit, age, "b") * (a - center)) / at_age(fit, age, "sd")
                    resid[key][ident] = e
                    pooled.append(e)
        block["shock_quantiles"] = quantiles(pooled)
        block["shock_cholesky"], block["residual_corr"] = corr_cholesky(resid, keys)
        # リーグ全体の平均・ばらつき（開幕時点の全選手。直近10年の平均）
        target: dict = {}
        for key in keys:
            means, sds = [], []
            for y in TARGET_YEARS:
                vals = [v for p in pre_files[y].values() if side_of(p) == side
                        for v in [value_of(p, side, key)] if v is not None]
                if len(vals) > 50:
                    m = sum(vals) / len(vals)
                    means.append(m)
                    sds.append(math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals)))
            target[key] = {"mean": round(sum(means) / len(means), 2), "sd": round(sum(sds) / len(sds), 2)}
        if side == "P":
            shares = []
            for y in TARGET_YEARS:
                ps = [p for p in pre_files[y].values() if side_of(p) == "P"]
                shares.append(sum(1 for p in ps if role_of(p) == "先発") / len(ps))
            target["starter_share"] = round(sum(shares) / len(shares), 4)
            # スタミナは役割で2つの山に分かれるので、役割ごとの平均・ばらつきも
            for role in ["先発", "救援"]:
                means, sds = [], []
                for y in TARGET_YEARS:
                    vals = [value_of(p, "P", "stamina") for p in pre_files[y].values()
                            if side_of(p) == "P" and role_of(p) == role and value_of(p, "P", "stamina") is not None]
                    m = sum(vals) / len(vals)
                    means.append(m)
                    sds.append(math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals)))
                target[f"stamina:{role}"] = {"mean": round(sum(means) / len(means), 2), "sd": round(sum(sds) / len(sds), 2)}
        block["target"] = target
        if side == "P":
            block["derived"] = {"overall": derive_overall(pre_files)}
            # 役割の移り変わり（来季に先発になる確率）と、移り変わりごとのスタミナ
            block["role"] = {r: {"features": ROLE_FEATURES, "weights": [round(x, 4) for x in logistic_fit(role_x[r], role_y[r])],
                                 "n": len(role_y[r]), "rate": round(sum(role_y[r]) / len(role_y[r]), 4)}
                             for r in ["先発", "救援"]}
            block["stamina_by_role"] = {}
            for t, r in stamina_rows.items():
                fit = kernel_fit(r, CENTER, AGE_BANDWIDTH if t[:2] == t[-2:] else LOW_AGE_BANDWIDTH)
                fit["center"] = CENTER
                fit["n"] = len(r)
                block["stamina_by_role"][t] = fit
        out[label] = block

    # 守備位置の記録が無い新人（primary_pos は「内野手」など）の2年目の守備位置・守備力（成長の最初の1回で割り当てる）
    out["batting"]["rookie_fielding"] = {k: v[::max(1, len(v) // ROOKIE_FIELDING_MAX)][:ROOKIE_FIELDING_MAX]
                                         for k, v in rookie_fielding.items()}
    w = logistic_fit(retire_x, retire_y)
    out["retire"] = {
        "features": RETIRE_FEATURES,
        "weights": [round(x, 4) for x in w],
        "note": "logit = Σ weights × features。age_30 = 年齢−30, over_33 = max(0,年齢−33), under_26 = max(0,26−年齢)。"
                "z・playing は Salary.ability。年齢は来季の満年齢",
        "n": len(retire_y),
        "rate": round(sum(retire_y) / len(retire_y), 4),
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    report(out, retire_rows, w)


def report(out: dict, retire_rows: list, w: list[float]) -> None:
    for label in ["batting", "pitching"]:
        block = out[label]
        print(f"[{label}] shock quantiles {block['shock_quantiles']}")
        for field in ["keys", "keys_low"]:
            for key, fit in block[field].items():
                t = block["target"][key]
                line = " ".join(f"{a}:{fit['a'][a - AGE_MIN]:+.1f}/{fit['b'][a - AGE_MIN]:+.2f}/{fit['sd'][a - AGE_MIN]:.1f}"
                                for a in (19, 22, 25, 28, 31, 34, 37, 40))
                print(f"  {field[5:] or 'reg':3s} {key:8s} n={fit['n']:5d} target {t['mean']:.1f}±{t['sd']:.1f}  a/b/sd {line}")
    print("[derived overall]", out["pitching"]["derived"])
    print("[role]", out["pitching"]["role"])
    for t, fit in out["pitching"]["stamina_by_role"].items():
        print(f"  stamina {t} n={fit['n']} " + " ".join(f"{a}:{fit['a'][a - AGE_MIN]:+.1f}/{fit['b'][a - AGE_MIN]:+.2f}/{fit['sd'][a - AGE_MIN]:.1f}" for a in (20, 24, 28, 32, 36)))
    print("[retire] weights", dict(zip(RETIRE_FEATURES, [round(x, 3) for x in w])))
    for lo, hi in [(18, 23), (24, 27), (28, 30), (31, 33), (34, 36), (37, 39), (40, 50)]:
        sub = [r for r in retire_rows if lo <= r[0] <= hi and not r[3]]
        if not sub:
            continue
        pred = sum(1 / (1 + math.exp(-sum(a * b for a, b in zip(w, retire_features(*r[:5][:3], r[3], r[4] == "P")))))
                   for r in sub) / len(sub)
        print(f"  国内 {lo}-{hi}歳 n={len(sub)} 実際 {sum(r[5] for r in sub) / len(sub):.3f} 予測 {pred:.3f}")
    sub = [r for r in retire_rows if r[3]]
    print(f"  外国人 n={len(sub)} 実際 {sum(r[5] for r in sub) / len(sub):.3f}")


if __name__ == "__main__":
    main()
