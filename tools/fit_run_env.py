"""年ごとの点の入りやすさ（generated/run_env.json、作業70）を、試合を回して史実のリーグ成績に合わせる。

Godot の godot/tests/run_env_fit.gd を、年を分けて並列に流す（1年あたり1シーズン × 回数）。
すでに generated/run_env.json があれば、その値から始めて直す（2回目以降は回数 1〜2 で足りる）。
future（表に無い先の年 = 2027年〜）は直近3年の平均。
league（年ごとの史実のリーグの OPS・防御率。年俸の査定の基準に使う）も書く。--league-only ならそれだけ書き直す（試合は回さない）。

    python tools/fit_run_env.py [--rounds 3] [--jobs 4] [--years 2008-2026] [--godot <Godot の実行ファイル>] [--league-only]
"""
import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "generated" / "run_env.json"
KEYS = ["k", "bb", "hr", "sharp"]
FUTURE_YEARS = 3
DEFAULT_GODOT = "C:/Users/user/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"


def league_stats(year: int) -> dict:
    """史実の1軍のリーグ全体の OPS・防御率"""
    rows = json.loads((ROOT / f"data/{year}/teamstats_linked.json").read_text(encoding="utf-8"))
    b = {k: 0 for k in ["打数", "安打", "二塁打", "三塁打", "本塁打", "四球", "死球", "犠飛"]}
    er = outs = 0
    for r in rows:
        if r["level"] != 1:
            continue
        if r["kind"] == "b":
            for k in b:
                b[k] += int(r.get(k) or 0)
        elif r["kind"] == "p":
            er += int(r["自責点"])
            outs += int(r["outs"])
    obp = (b["安打"] + b["四球"] + b["死球"]) / (b["打数"] + b["四球"] + b["死球"] + b["犠飛"])
    slg = (b["安打"] + b["二塁打"] + 2 * b["三塁打"] + 3 * b["本塁打"]) / b["打数"]
    return {"ops": round(obp + slg, 4), "era": round(er * 27 / outs, 3)}


def write_league(data: dict, years: list) -> None:
    data["league"] = {str(y): league_stats(y) for y in years}
    last = [str(y) for y in years[-FUTURE_YEARS:]]
    data["league_future"] = {k: round(sum(data["league"][y][k] for y in last) / len(last), 4) for k in ["ops", "era"]}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--years", default="2008-2026")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--godot", default=os.environ.get("GODOT", DEFAULT_GODOT))
    ap.add_argument("--league-only", action="store_true")
    a = ap.parse_args()
    lo, hi = (int(x) for x in a.years.split("-"))
    years = [y for y in range(lo, hi + 1) if (ROOT / f"data/{y}/teamstats_linked.json").exists()]
    if a.league_only:
        data = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
        write_league(data, years)
        OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
        print(OUT, "league", data["league_future"])
        return
    chunks = [years[i::a.jobs] for i in range(a.jobs) if years[i::a.jobs]]
    tmp = Path(tempfile.mkdtemp(prefix="run_env_"))
    procs = []
    for i, ys in enumerate(chunks):
        out = tmp / f"part{i}.json"
        log = open(tmp / f"part{i}.log", "w", encoding="utf-8")
        cmd = [a.godot, "--headless", "--path", str(ROOT / "godot"), "--script", "res://tests/run_env_fit.gd",
               "--", ",".join(map(str, ys)), str(a.rounds), str(out), str(a.seed)]
        procs.append((subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT), out, log))
    fitted = {}
    for p, out, log in procs:
        p.wait()
        log.close()
        if not out.exists():
            raise SystemExit(f"失敗しました（ログ: {log.name}）")
        fitted.update(json.loads(out.read_text(encoding="utf-8")))

    data = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
    data.setdefault("years", {})
    data.setdefault("fit", {})
    for y, r in fitted.items():
        data["years"][y] = {k: r["env"][k] for k in KEYS}
        data["fit"][y] = {"sim": {k: round(v, 4) for k, v in r["last"].items()},
                          "real": {k: round(v, 4) for k, v in r["real"].items()}}
    last = sorted(data["years"], key=int)[-FUTURE_YEARS:]
    data["future"] = {k: round(sum(data["years"][y][k] for y in last) / len(last), 3) for k in KEYS}
    data["note"] = ("GameSim の基準の確率（ロジット）に足す年ごとのずれ。tools/fit_run_env.py が作る。"
                    f"future は {last[0]}〜{last[-1]}年の平均。fit は最後に回したシミュ（ずれを直す前）と史実")
    write_league(data, sorted(int(y) for y in data["years"]))
    data["years"] = dict(sorted(data["years"].items(), key=lambda kv: int(kv[0])))
    data["fit"] = dict(sorted(data["fit"].items(), key=lambda kv: int(kv[0])))
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
    for y in sorted(fitted, key=int):
        s, r = fitted[y]["last"], fitted[y]["real"]
        print(f"{y}: 打率 {s['avg']:.3f}/{r['avg']:.3f} 本塁打 {s['hr_n']}/{r['hr_n']} 防御率 {s['era']:.2f}/{r['era']:.2f}"
              f"  ずれ {data['years'][y]}")
    print(OUT, "future", data["future"], "ログ", tmp)


if __name__ == "__main__":
    main()
