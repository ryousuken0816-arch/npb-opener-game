"""ドラフト候補の「将来性（未来視）」の元データを作る。

各年のドラフト指名選手（data/<年+1>/drafts.json の当年秋の分）について、指名の翌年以降のシーズン後の能力値
（generated/ratings/<年>_post.json）から「その年の実力」を出し、そのピークを記録する。
Godot 側（godot/sim/draft.gd）はこのピークに難易度のノイズを足して S〜G のランクにする。

実力 = Salary.ability と同じ実力z + PLAYING_WEIGHT × 出場量（0〜1）
（godot/sim/salary.gd の ability() と同じ計算。係数を変えたらそろえる）

出力: generated/draft_future.json
{
  "data_through": 2026,          # 使った能力値ファイルの最終年（その年はシーズン途中のことがある）
  "years": {"2008": {"<名前(空白除く)>": {"score": 1.23, "peak_year": 2012, "seasons": 5}, ...}, ...}
}
seasons: 能力値ファイルに出てきた年数（1軍・2軍の在籍）。未入団・1年も在籍が無い選手は載らない
python tools/draft_future.py
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIRST_YEAR = 2008
LAST_DRAFT_YEAR = 2025
PLAYING_WEIGHT = 0.6

# godot/sim/salary.gd と同じ値
SCALE_MEAN = 63.0
SCALE_SD = 17.0
PITCHER_Z_SCALE = 0.85
RELIEVER_Z_SCALE = 0.65
FULL_PA = 480.0
FULL_OUTS_STARTER = 450.0
FULL_OUTS_RELIEVER = 170.0
SAMPLE_YEARS = 2.4

PAIRS = [("﨑", "崎"), ("髙", "高"), ("濵", "浜"), ("邊", "辺"), ("邉", "辺"), ("德", "徳"),
         ("瀨", "瀬"), ("齋", "斎"), ("齊", "斉"), ("櫻", "桜"), ("澤", "沢"), ("眞", "真")]


def norm_name(s):
    s = s.replace(" ", "").replace("　", "").replace("・", "")
    for a, b in PAIRS:
        s = s.replace(a, b)
    return s


def z_of(r, fallback=45.0):
    v = fallback
    if isinstance(r, dict) and r.get("value") is not None:
        v = float(r["value"])
    return (v - SCALE_MEAN) / SCALE_SD


def ability(p):
    pit = p.get("pitching")
    if p.get("is_pitcher") and isinstance(pit, dict):
        r = pit.get("ratings") or {}
        z = PITCHER_Z_SCALE * (0.75 * z_of(r.get("overall")) + 0.25 * z_of(r.get("k9")))
        outs = float((pit.get("sample") or {}).get("outs_1", 0.0)) / SAMPLE_YEARS
        if pit.get("role") == "先発":
            return z, min(1.0, outs / FULL_OUTS_STARTER)
        return z * RELIEVER_Z_SCALE, min(1.0, outs / FULL_OUTS_RELIEVER)
    bat = p.get("batting") or {}
    br = bat.get("ratings") or {}
    pa = float((bat.get("sample") or {}).get("pa_1", 0.0)) / SAMPLE_YEARS
    z = (0.35 * z_of(br.get("meet")) + 0.35 * z_of(br.get("power")) + 0.1 * z_of(br.get("eye"))
         + 0.1 * z_of(br.get("speed")) + 0.1 * z_of(br.get("defense"), 63.0))
    return z, min(1.0, pa / FULL_PA)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main():
    post = {}
    y = FIRST_YEAR
    while os.path.exists(os.path.join(ROOT, "generated", "ratings", f"{y}_post.json")):
        post[y] = load_json(os.path.join(ROOT, "generated", "ratings", f"{y}_post.json"))["players"]
        y += 1
    data_through = max(post)
    out = {"data_through": data_through, "years": {}}
    for dy in range(FIRST_YEAR, LAST_DRAFT_YEAR + 1):
        path = os.path.join(ROOT, "data", str(dy + 1), "drafts.json")
        if not os.path.exists(path):
            continue
        names = {norm_name(d["name"]) for d in load_json(path) if int(d.get("draft_year", 0)) == dy}
        result = {}
        for year in range(dy + 1, data_through + 1):
            for p in post.get(year, []):
                key = norm_name(p["name"])
                if key not in names:
                    continue
                draft = p.get("draft") or ""
                # 同姓同名の別人を避ける：選手ページのドラフトの年が違えば別人
                if draft and not re.match(rf"{dy}年", draft):
                    continue
                z, playing = ability(p)
                score = round(z + PLAYING_WEIGHT * playing, 3)
                cur = result.get(key)
                if cur is None:
                    result[key] = {"score": score, "peak_year": year, "seasons": 1}
                else:
                    cur["seasons"] += 1
                    if score > cur["score"]:
                        cur["score"] = score
                        cur["peak_year"] = year
        out["years"][str(dy)] = result
    dest = os.path.join(ROOT, "generated", "draft_future.json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(dest, sum(len(v) for v in out["years"].values()), "players")


if __name__ == "__main__":
    main()
