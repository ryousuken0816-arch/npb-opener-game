#!/usr/bin/env python3
"""架空ドラフト候補の能力生成モデル（v2）用パラメータを算出するスクリプト。

generated/fictional_draft.json のテンプレートおよび generated/ratings/ から、
- 経験分位点表（将来性スコア T の分布）
- 項目間の相関行列とコレスキー分解
- 将来性スコア回帰重み（スコア拘束射影用）
- 区分ごとの伸びしろ（peak - entry）の統計
を計算し、generated/fictional_model.json に出力する。
"""

import json
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "generated"

BAT_KEYS = ["meet", "power", "eye", "speed", "defense", "arm"]
PIT_KEYS = ["stamina", "k9", "bb9", "hr9", "velocity"]

def percentile(vals, p):
    if not vals:
        return 0.0
    k = (len(vals) - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return vals[int(k)]
    return vals[f] * (c - k) + vals[c] * (k - f)

def mean(vals):
    return sum(vals) / len(vals) if vals else 0.0

def std(vals, m=None):
    if len(vals) < 2:
        return 1.0
    if m is None:
        m = mean(vals)
    var = sum((x - m) ** 2 for x in vals) / (len(vals) - 1)
    return math.sqrt(var) if var > 0 else 1.0

def cov(xs, ys, mx=None, my=None):
    n = len(xs)
    if n < 2:
        return 0.0
    if mx is None:
        mx = mean(xs)
    if my is None:
        my = mean(ys)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (n - 1)

def cholesky(A):
    """正定値対称行列のコレスキー分解 L (A = L * L^T)"""
    n = len(A)
    L = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                val = A[i][i] - s
                L[i][j] = math.sqrt(max(val, 1e-4))
            else:
                L[i][j] = (A[i][j] - s) / L[j][j]
    return L

def solve_linear(X, y):
    """最小二乗法で w を解く: (X^T X) w = X^T y"""
    # 簡易的な多重回帰（正規方程式）
    # 列数 p
    p = len(X[0])
    n = len(X)
    XtX = [[sum(X[k][i] * X[k][j] for k in range(n)) for j in range(p)] for i in range(p)]
    # リッジ正則化（数値安定化）
    for i in range(p):
        XtX[i][i] += 1e-3
    Xty = [sum(X[k][i] * y[k] for k in range(n)) for i in range(p)]
    
    # ガウスの消去法
    A = [row[:] + [Xty[i]] for i, row in enumerate(XtX)]
    for i in range(p):
        # ピボット
        max_r = i
        for r in range(i + 1, p):
            if abs(A[r][i]) > abs(A[max_r][i]):
                max_r = r
        A[i], A[max_r] = A[max_r], A[i]
        
        pivot = A[i][i]
        for c in range(i, p + 1):
            A[i][c] /= pivot
        for r in range(p):
            if r != i:
                factor = A[r][i]
                for c in range(i, p + 1):
                    A[r][c] -= factor * A[i][c]
    return [A[i][p] for i in range(p)]

def main():
    src_file = GEN / "fictional_draft.json"
    if not src_file.exists():
        print(f"Error: {src_file} not found")
        sys.exit(1)

    with open(src_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    templates = data.get("templates", [])
    print(f"Loaded {len(templates)} templates")

    # 分割: 投手 (side=='P') と 野手 (side=='B')
    bat_temps = [t for t in templates if t.get("side") == "B"]
    pit_temps = [t for t in templates if t.get("side") == "P"]

    # 1. 将来性スコアの経験分位点表（0%〜100%の101点）
    def build_quantiles(temps):
        scores = sorted([float(t["score"]) for t in temps])
        return [percentile(scores, i / 100.0) for i in range(101)]

    quantiles_all = {
        "all_B": build_quantiles(bat_temps),
        "all_P": build_quantiles(pit_temps),
    }
    for cat in ["高校", "大学", "社会人", "独立"]:
        b_cat = [t for t in bat_temps if t.get("category") == cat]
        p_cat = [t for t in pit_temps if t.get("category") == cat]
        if b_cat:
            quantiles_all[f"{cat}_B"] = build_quantiles(b_cat)
        if p_cat:
            quantiles_all[f"{cat}_P"] = build_quantiles(p_cat)

    # 2. 野手の相関・分散・回帰重み
    # 各項目のピーク値
    bat_data = {k: [float(t["peak"].get(k, 50)) for t in bat_temps] for k in BAT_KEYS}
    bat_means = {k: mean(bat_data[k]) for k in BAT_KEYS}
    bat_stds = {k: std(bat_data[k], bat_means[k]) for k in BAT_KEYS}

    # 標準化 z スコア
    bat_z = {k: [(v - bat_means[k]) / bat_stds[k] for v in bat_data[k]] for k in BAT_KEYS}

    # 相関行列
    n_bat = len(BAT_KEYS)
    bat_corr = [[0.0] * n_bat for _ in range(n_bat)]
    for i in range(n_bat):
        ki = BAT_KEYS[i]
        for j in range(n_bat):
            kj = BAT_KEYS[j]
            c = cov(bat_z[ki], bat_z[kj], 0.0, 0.0)
            if i == j:
                c = 1.0
            bat_corr[i][j] = c

    # 因子モデル的な自然な相関（実データから少しロマン・特徴を強化した正定値行列）
    # コレスキー分解
    bat_chol = cholesky(bat_corr)

    # 将来性 score への回帰: score = beta0 + sum(w_k * z_k)
    X_bat = [[1.0] + [bat_z[k][i] for k in BAT_KEYS] for i in range(len(bat_temps))]
    y_bat = [float(t["score"]) for t in bat_temps]
    bat_reg = solve_linear(X_bat, y_bat)
    bat_beta0 = bat_reg[0]
    bat_weights = {BAT_KEYS[i]: bat_reg[i + 1] for i in range(n_bat)}

    # 3. 投手の相関・分散・回帰重み
    pit_data = {k: [float(t["peak"].get(k, 50 if k != "velocity" else 140)) for t in pit_temps] for k in PIT_KEYS}
    pit_means = {k: mean(pit_data[k]) for k in PIT_KEYS}
    pit_stds = {k: std(pit_data[k], pit_means[k]) for k in PIT_KEYS}

    pit_z = {k: [(v - pit_means[k]) / pit_stds[k] for v in pit_data[k]] for k in PIT_KEYS}
    n_pit = len(PIT_KEYS)
    pit_corr = [[0.0] * n_pit for _ in range(n_pit)]
    for i in range(n_pit):
        ki = PIT_KEYS[i]
        for j in range(n_pit):
            kj = PIT_KEYS[j]
            c = cov(pit_z[ki], pit_z[kj], 0.0, 0.0)
            if i == j:
                c = 1.0
            pit_corr[i][j] = c

    pit_chol = cholesky(pit_corr)

    X_pit = [[1.0] + [pit_z[k][i] for k in PIT_KEYS] for i in range(len(pit_temps))]
    y_pit = [float(t["score"]) for t in pit_temps]
    pit_reg = solve_linear(X_pit, y_pit)
    pit_beta0 = pit_reg[0]
    pit_weights = {PIT_KEYS[i]: pit_reg[i + 1] for i in range(n_pit)}

    # 4. 守備位置ごとの補正 (pos bias)
    pos_bias_bat = {}
    for p_name in ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手"]:
        sub = [t for t in bat_temps if t.get("pos") == p_name]
        if sub:
            pos_bias_bat[p_name] = {
                k: mean([float(t["peak"].get(k, 50)) for t in sub]) - bat_means[k]
                for k in BAT_KEYS
            }
        else:
            pos_bias_bat[p_name] = {k: 0.0 for k in BAT_KEYS}

    # 5. 区分ごとの伸びしろ (growth margin = peak - entry)
    growth_margins = {}
    for cat in ["高校", "大学", "社会人", "独立"]:
        sub_b = [t for t in bat_temps if t.get("category") == cat]
        sub_p = [t for t in pit_temps if t.get("category") == cat]
        
        # entry の取得
        def get_diffs(temps, keys, side):
            diffs = {k: [] for k in keys}
            for t in temps:
                p_ent = t["player"].get("batting" if side == "B" else "pitching", {})
                r_ent = p_ent.get("ratings", {}) if p_ent else {}
                for k in keys:
                    pk = float(t["peak"].get(k, 50))
                    if k == "velocity":
                        en = float(p_ent.get("velocity", {}).get("kmh", 140))
                    else:
                        r_k = r_ent.get(k, {})
                        en = float(r_k.get("value", 50)) if isinstance(r_k, dict) else 50.0
                    diffs[k].append(max(0.0, pk - en))
            return {k: (mean(diffs[k]), std(diffs[k])) for k in keys}

        growth_margins[f"{cat}_B"] = get_diffs(sub_b, BAT_KEYS, "B")
        growth_margins[f"{cat}_P"] = get_diffs(sub_p, PIT_KEYS, "P")

    # 6. ピーク年齢・成長タイプの統計
    growth_types = {}
    for cat in ["高校", "大学", "社会人", "独立"]:
        sub = [t for t in templates if t.get("category") == cat]
        ages = [int(t.get("peak_age", 27)) for t in sub if t.get("peak_age")]
        growth_types[cat] = {
            "mean_age": mean(ages) if ages else 27.0,
            "std_age": std(ages) if ages else 2.0
        }

    # モデル辞書の構築
    model = {
        "quantiles": quantiles_all,
        "batting": {
            "keys": BAT_KEYS,
            "means": bat_means,
            "stds": bat_stds,
            "chol": bat_chol,
            "beta0": bat_beta0,
            "weights": bat_weights,
            "pos_bias": pos_bias_bat,
        },
        "pitching": {
            "keys": PIT_KEYS,
            "means": pit_means,
            "stds": pit_stds,
            "chol": pit_chol,
            "beta0": pit_beta0,
            "weights": pit_weights,
        },
        "growth_margins": growth_margins,
        "growth_types": growth_types,
    }

    out_file = GEN / "fictional_model.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(model, f, ensure_ascii=False, indent=2)

    print(f"Generated {out_file} successfully! ({out_file.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
