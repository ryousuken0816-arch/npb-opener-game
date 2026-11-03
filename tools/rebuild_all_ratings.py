import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def run(cmd):
    print(f"Running: {cmd}")
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    res = subprocess.run(cmd, shell=True, cwd=str(ROOT), env=env)
    if res.returncode != 0:
        sys.exit(f"Failed: {cmd}")

def main():
    # 1. compute_ratings for 2008-2026 pre and post, and 2027 pre
    for yr in range(2008, 2027):
        run(f"python tools/compute_ratings.py --year {yr} --phase pre")
        run(f"python tools/compute_ratings.py --year {yr} --phase post")
    run("python tools/compute_ratings.py --year 2027 --phase pre")

    # 1.5 手で決めた能力値（tools/manual_overrides.json：2024年ドラフトの6人の強化）を当て直す
    run("python tools/manual_overrides.py")

    # 2. amateur_ratings rookies --draft-year 2026
    run("python tools/amateur_ratings.py rookies --draft-year 2026")

    # 3. amateur_ratings carry --year 2027
    run("python tools/amateur_ratings.py carry --year 2027")

    # 4. draft_future.py
    run("python tools/draft_future.py")

    # 5. growth_coefficients.py
    run("python tools/growth_coefficients.py")

    # 6. foreign_players.py
    run("python tools/foreign_players.py")

    # 7. fictional_draft.py
    run("python tools/fictional_draft.py")

    # 8. 2025年秋の新人（2026_pre）の入団時をそろえる（docs/AUTORUN.md 作業62）。最後に回す：
    #    2026_pre の2025年秋の新人は、2・3 の下地（Templates）と 5 の成長の係数（出場の少ない組）にも使われるので、
    #    そろえる前の値で作る（そろえた値を混ぜると、出場の少ない選手の伸び方の係数が大きく変わる）。
    #    2026年秋・2027年秋の分は 2・3 の中でそろえている
    run("python tools/amateur_ratings.py calibrate --draft-year 2025")

    print("\nAll ratings and derived files regenerated successfully!")

if __name__ == "__main__":
    main()
