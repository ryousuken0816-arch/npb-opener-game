"""記録室のデプスチャート用：全選手の「その年の実力」を年ごとに並べる（将来性ランクの元データ）。

generated/ratings/<年>_post.json（シーズン後の能力値）の全選手について、tools/draft_future.py と同じ
「実力 = 実力z + PLAYING_WEIGHT × 出場量」を出し、選手IDごとに年 → 実力 を記録する。
Godot 側（godot/sim/depth.gd）は「今の年より後の年の最大値」にドラフトと同じノイズを足して将来性ランクにする。

出力: generated/player_future.json
{
  "data_through": 2026,                # 使った能力値ファイルの最終年（その年はシーズン途中のことがある）
  "players": {"<選手ID>": {"2008": 0.53, "2009": 0.71, ...}, ...}
}
python tools/player_future.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from draft_future import ROOT, FIRST_YEAR, PLAYING_WEIGHT, ability, load_json  # noqa: E402


def main():
    out = {"data_through": FIRST_YEAR, "players": {}}
    y = FIRST_YEAR
    while True:
        path = os.path.join(ROOT, "generated", "ratings", f"{y}_post.json")
        if not os.path.exists(path):
            break
        for p in load_json(path)["players"]:
            z, playing = ability(p)
            out["players"].setdefault(p["id"], {})[str(y)] = round(z + PLAYING_WEIGHT * playing, 2)
        out["data_through"] = y
        y += 1
    dest = os.path.join(ROOT, "generated", "player_future.json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(dest, len(out["players"]), "players, through", out["data_through"])


if __name__ == "__main__":
    main()
