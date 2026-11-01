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

    print("\nAll ratings and derived files regenerated successfully!")

if __name__ == "__main__":
    main()
