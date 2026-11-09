"""Godot のテストを並列に流す（docs/AUTORUN.md 作業52）。

    python tools/run_tests.py quick                  # 速い組（5分以内。main に入れる前に、関係するテストと一緒に）
    python tools/run_tests.py full                   # 全部（1日1回まとめてか、Web 版を公開する前だけ）
    python tools/run_tests.py save_check trade_check # 名前を並べて（.gd は付けなくてよい）
    python tools/run_tests.py layout_fit_check:quick # 軽い版（下の VARIANTS）
    python tools/run_tests.py --list                 # 組の中身と見込みの時間

- Godot をヘッドレスで同時に N 本（-j。既定は CPU のコア数の半分、最大6）起動し、重いテストから先に流す。
  同じ PC でほかの作業もテストを流すので、Godot は優先度を「通常以下」で起動する。ウィンドウは出さない
- 各テストに時間制限（見込みの4倍、最低3分。--timeout で上限）。超えたらそのプロセスだけ止めて NG にする
- セーブの場所：テストごとに別のフォルダ（godot/.godot/test_logs/<日時>/saves/<テスト>）を環境変数
  NPB_TEST_SAVE_DIR で渡す（SaveGame.test_dir()）。ユーザーのセーブ（user://saves/）は読まない・触らない
- 出力はテストごとに godot/.godot/test_logs/<日時>/<テスト>.log。最後に OK/NG の一覧と時間を出す
- NG のテストはその場でもう一度だけ流す（--retry。乱数しだいの NG を見分けるため。2回目で OK なら「流し直して OK」）
- 時間は godot/.godot/test_times.json に覚え、次から重い順の並びと時間制限に使う（無ければ下の EST_SEC）
- 終了コード：全部 OK（流し直して OK を含む）なら 0、NG があれば 1

外部ライブラリ不要（標準ライブラリのみ）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT_DIR = ROOT / "godot"
TESTS_DIR = GODOT_DIR / "tests"
LOG_ROOT = GODOT_DIR / ".godot" / "test_logs"
TIMES_PATH = GODOT_DIR / ".godot" / "test_times.json"
DEFAULT_GODOT = "C:/Users/user/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
SAVE_DIR_ENV = "NPB_TEST_SAVE_DIR"
## 残しておくログの回数
KEEP_RUNS = 5
MAX_JOBS = 6
## ヘッドレスの Godot はフレームの上限が無いと、演出を待つ間も全力でフレームを回して CPU を使い切る
MAX_FPS = 0

# ---------------------------------------------------------------- 定数

## テストとして流すファイル（*_capture はウィンドウ付きのスクショ用、*_dump・*_examples は資料づくりなので流さない）
TEST_PATTERNS = ("*_check.gd", "*_test.gd")

## 引数付きの版：「名前:印」→（ファイル名, 引数）。:quick は重いテストの代表の1年・代表の画面だけを見る軽い版
VARIANTS = {
    # 2008年の開幕〜オフのドラフトまで（全部は2008〜2012年を続けて）
    "layout_fit_check:quick": ("layout_fit_check", ["", "2008", "2008"]),
    # full ではこの3つに分けて同時に流す（1本で続けると約17分かかり、full 全体がそれより短くならないため）
    "layout_fit_check:2008-2009": ("layout_fit_check", ["", "2009", "2008"]),
    "layout_fit_check:2010-2011": ("layout_fit_check", ["", "2011", "2010"]),
    "layout_fit_check:2012": ("layout_fit_check", ["", "2012", "2012"]),
}

## full で、1本の代わりに分けた版を流すテスト（名前を指定したときは1本で全部）
FULL_SPLIT = {
    "layout_fit_check": ["layout_fit_check:2008-2009", "layout_fit_check:2010-2011", "layout_fit_check:2012"],
}

## 速い組。主な仕組みを一通り：タイトル→ハブ→日程表で数日→采配→オフの各段階の入口→ドラフトの入口→セーブ／ロード。
## 並列で5分以内に収まるよう、1本数分までのものだけ入れる
QUICK = [
    "pad_flow_check",        # タイトル→球団選択→ハブ→日程表で日付を選んで進める（キーボードだけ）
    "tactics_check",         # 采配（1軍登録・オーダー・ローテ）
    "order_page_check",      # 起用設定
    "start_year_check",      # 開始年・すぐドラフトへ（オフの段階の入口）
    "draft_rebid_check",     # ドラフトの入札・外れ1位
    "draft_fullscreen_check",  # ドラフトの画面いっぱい・後ろが見えない（作業81）
    "save_check",            # セーブ／ロード
    "ikusei_roster_check",   # 育成の判定（開始年・2026年から3年・ロード後の支配下と育成の人数）
    "trade_check",           # トレード交渉（オフの段階）
    "fullscreen_check",
    "mobile_layout_check",
    "mobile_fit_check",      # スマホの縦横で全画面（約2分なので軽い版は作らずそのまま）
    "layout_fit_check:quick",
    "rookie_fielding_check", # 新人・ドラフト候補の守備位置・守備力・肩（作業66。約10秒）
    "draft_first_bid_check", # CPU球団の1位入札の競合の分布（30年分、作業68。約20秒）
    "lite_mode_check",       # サブ画面を開くときに作る・軽量モードで閉じたら捨てる（作業75。約1分）
    "pitch_arsenal_check",   # 投手の持ち球（作業79。実在の投手の奪三振・被弾抑制に合う・球種がばらける。約10秒）
    "draft_intent_check",    # ドラフトの意中の球団・入団拒否・説得・数年後に候補へ戻る（作業77。約1分40秒）
]

## 見込みの時間（秒。並列で流したときの目安）。覚えた時間（TIMES_PATH）が無いときに使う。無いものは DEFAULT_EST
EST_SEC = {
    "layout_fit_check": 1200,
    "layout_fit_check:quick": 240,
    "layout_fit_check:2008-2009": 420,
    "layout_fit_check:2010-2011": 420,
    "layout_fit_check:2012": 240,
}
DEFAULT_EST = 180
## 時間制限：見込みの何倍か・最低（秒）
TIMEOUT_FACTOR = 4
MIN_TIMEOUT = 180

## ログの中のスクリプトのエラー（終了コードが 0 でも NG にする）
ERROR_RE = re.compile(r"^(SCRIPT ERROR|Parse Error)", re.M)
## エンジンのエラー（描画など）：NG にはせず一覧に「注意」で出す。終了時のリークの報告（テストの多くで出る）は数えない
ENGINE_ERROR_RE = re.compile(r"^ERROR: (?!.*(leaked at exit|still in use at exit))(.*)$", re.M)
## ログの中の NG の行（一覧に出す）
NG_RE = re.compile(r"^\s*(\[?NG\b.*|FAILED.*|.*Assertion failed.*)$", re.M)

# Windows：コンソールを出さない・優先度を通常以下に
CREATE_NO_WINDOW = 0x08000000
BELOW_NORMAL_PRIORITY_CLASS = 0x00004000


def discover() -> list[str]:
    names: set[str] = set()
    for pattern in TEST_PATTERNS:
        names.update(p.stem for p in TESTS_DIR.glob(pattern))
    return sorted(names)


def resolve(names: list[str]) -> list[str]:
    """引数（quick・full・テスト名）を、流すテストの並びにする"""
    all_tests = discover()
    result: list[str] = []
    for name in names:
        name = name.removesuffix(".gd")
        if name == "quick":
            items = QUICK
        elif name == "full":
            items = [part for t in all_tests for part in FULL_SPLIT.get(t, [t])]
        elif name in VARIANTS or name in all_tests:
            items = [name]
        else:
            sys.exit(f"テストが見つかりません：{name}（--list で一覧）")
        for item in items:
            if item not in result and (item in VARIANTS or item in all_tests):
                result.append(item)
    return result


def load_times() -> dict[str, float]:
    try:
        return json.loads(TIMES_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def estimate(item: str, times: dict[str, float]) -> float:
    return float(times.get(item, EST_SEC.get(item, DEFAULT_EST)))


def godot_bin() -> str:
    path = os.environ.get("GODOT", DEFAULT_GODOT)
    if not Path(path).exists():
        sys.exit(f"Godot が見つかりません：{path}（環境変数 GODOT で指定）")
    return path


def ensure_imported(godot: str) -> None:
    """新しいワークツリー・新しい class_name を取り込んだあとは、先に --import が要る（しないと読み込みでエラー）"""
    cache = GODOT_DIR / ".godot" / "global_script_class_cache.cfg"
    if cache.exists():
        cache_time = cache.stat().st_mtime
        if all(p.stat().st_mtime <= cache_time for p in GODOT_DIR.rglob("*.gd") if ".godot" not in p.parts):
            return
    print("スクリプトが新しくなったので --import します…", flush=True)
    subprocess.run([godot, "--headless", "--path", str(GODOT_DIR), "--import"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900,
                   creationflags=CREATE_NO_WINDOW if os.name == "nt" else 0)


def kill_tree(proc: subprocess.Popen) -> None:
    """自分が起動した Godot だけを止める（ユーザーのエディタには触れない）"""
    if os.name == "nt":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        proc.kill()


class Runner:
    def __init__(self, godot: str, run_dir: Path, times: dict[str, float], max_timeout: float, max_fps: int):
        self.godot = godot
        self.max_fps = max_fps
        self.run_dir = run_dir
        self.times = times
        self.max_timeout = max_timeout
        self.lock = threading.Lock()
        self.started = time.monotonic()

    def run(self, item: str, attempt: int) -> dict:
        script, args = VARIANTS.get(item, (item, []))
        safe = item.replace(":", "@")
        suffix = "" if attempt == 1 else f".{attempt}"
        log_path = self.run_dir / f"{safe}{suffix}.log"
        save_dir = self.run_dir / "saves" / f"{safe}{suffix}"
        save_dir.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        env[SAVE_DIR_ENV] = save_dir.as_posix()
        timeout = min(self.max_timeout, max(MIN_TIMEOUT, estimate(item, self.times) * TIMEOUT_FACTOR))
        cmd = [self.godot, "--headless", "--path", str(GODOT_DIR), "-s", f"res://tests/{script}.gd"]
        if self.max_fps > 0:
            cmd[1:1] = ["--max-fps", str(self.max_fps)]
        if args:
            cmd += ["--", *args]
        flags = CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
        t0 = time.monotonic()
        timed_out = False
        with open(log_path, "wb") as log:
            proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL, creationflags=flags)
            try:
                code = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                kill_tree(proc)
                code = proc.wait()
        sec = time.monotonic() - t0
        text = log_path.read_text(encoding="utf-8", errors="replace")
        errors = len(ERROR_RE.findall(text))
        ng_lines = [m.group(1).strip() for m in NG_RE.finditer(text)]
        engine_errors = sorted({m.group(2).strip() for m in ENGINE_ERROR_RE.finditer(text)})
        if timed_out:
            status = f"NG（{int(timeout)}秒で打ち切り）"
        elif code != 0:
            status = f"NG（終了コード {code}）"
        elif errors:
            status = f"NG（エラー {errors}件）"
        else:
            status = "OK"
        ok = status == "OK"
        if ok:
            shutil.rmtree(save_dir, ignore_errors=True)
        result = {"item": item, "ok": ok, "status": status, "sec": sec, "log": log_path,
                  "ng_lines": ng_lines, "engine_errors": engine_errors,
                  "attempt": attempt}
        with self.lock:
            elapsed = time.monotonic() - self.started
            mark = "OK" if ok else "NG"
            retry = "" if attempt == 1 else "（流し直し）"
            print(f"[{fmt(elapsed)}] {mark} {item}{retry}  {fmt(sec)}"
                  + ("" if ok else f"  {status}  {log_path.relative_to(ROOT).as_posix()}"), flush=True)
        return result


def fmt(sec: float) -> str:
    sec = int(round(sec))
    return f"{sec // 60}分{sec % 60:02d}秒"


def run_all(runner: Runner, items: list[str], jobs: int, retry: int) -> list[tuple[dict, dict]]:
    """各テストの（1回目, 最後の回）。NG はその場で流し直す（最後にまとめると、そのぶん待つ）"""
    def run_item(item: str) -> tuple[dict, dict]:
        first = last = runner.run(item, 1)
        for attempt in range(2, 2 + retry):
            if last["ok"]:
                break
            last = runner.run(item, attempt)
        return first, last

    # 重いものから先に（最後に重いのが1本だけ残って待つのを避ける）
    ordered = sorted(items, key=lambda i: -estimate(i, runner.times))
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_item, item) for item in ordered]
        return [f.result() for f in as_completed(futures)]


def cleanup_old_runs() -> None:
    runs = sorted(p for p in LOG_ROOT.iterdir() if p.is_dir())
    for old in runs[:-KEEP_RUNS]:
        shutil.rmtree(old, ignore_errors=True)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Godot のテストを並列に流す")
    parser.add_argument("names", nargs="*", help="quick・full・テスト名（layout_fit_check:quick のような軽い版も）")
    parser.add_argument("-j", "--jobs", type=int, default=0, help=f"同時に流す本数（既定はコア数の半分、最大{MAX_JOBS}）")
    parser.add_argument("--retry", type=int, default=1, help="NG を流し直す回数（既定1）")
    parser.add_argument("--timeout", type=float, default=3600, help="1本の時間制限の上限（秒、既定3600）")
    parser.add_argument("--max-fps", type=int, default=MAX_FPS, help=f"Godot のフレームの上限（既定{MAX_FPS}。0で上限なし）")
    parser.add_argument("--list", action="store_true", help="組の中身と見込みの時間を出す")
    opts = parser.parse_args()

    times = load_times()
    if opts.list:
        quick = set(QUICK)
        for item in sorted(discover() + list(VARIANTS), key=lambda i: -estimate(i, times)):
            print(f"{'quick' if item in quick else '     '}  {fmt(estimate(item, times)):>8}  {item}")
        return 0
    if not opts.names:
        parser.error("quick・full・テスト名のどれかを渡してください")
    items = resolve(opts.names)
    jobs = opts.jobs or max(1, min(MAX_JOBS, (os.cpu_count() or 2) // 2))
    jobs = min(jobs, len(items))

    godot = godot_bin()
    ensure_imported(godot)
    LOG_ROOT.mkdir(parents=True, exist_ok=True)
    run_dir = LOG_ROOT / datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir()
    cleanup_old_runs()
    print(f"{len(items)}本を {jobs}本ずつ並列に流します（ログ：{run_dir.relative_to(ROOT).as_posix()}）", flush=True)

    runner = Runner(godot, run_dir, times, opts.timeout, opts.max_fps)
    results: dict[str, dict] = {}
    retried: dict[str, dict] = {}
    for first, last in run_all(runner, items, jobs, opts.retry):
        results[first["item"]] = first
        if last is not first:
            retried[first["item"]] = last
    first_ng = [i for i in items if not results[i]["ok"]]
    wall = time.monotonic() - runner.started

    # 覚えておく時間（OK だった回。打ち切りは時間が分からないので覚えない）
    for r in list(results.values()) + list(retried.values()):
        if r["ok"]:
            times[r["item"]] = round(r["sec"], 1)
    try:
        TIMES_PATH.write_text(json.dumps(times, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
    except OSError:
        pass

    print("\n==== 結果 ====")
    ng_count = 0
    for item in sorted(items, key=lambda i: -results[i]["sec"]):
        r = results[item]
        line = f"{'OK' if r['ok'] else 'NG'}  {fmt(r['sec']):>8}  {item}"
        if not r["ok"]:
            again = retried.get(item)
            if again and again["ok"]:
                line = f"OK  {fmt(r['sec']):>8}  {item}  （1回目 {r['status']} → 流し直して OK）"
            else:
                ng_count += 1
                final = again or r
                line += f"  {final['status']}  {final['log'].relative_to(ROOT).as_posix()}"
        print(line)
        if not r["ok"]:
            for ng in r["ng_lines"][:5]:
                print(f"            {ng}")
        for err in r["engine_errors"][:3]:
            print(f"            注意（エンジンのエラー）：{err}")
    total = sum(r["sec"] for r in results.values())
    print(f"\n{len(items)}本：OK {len(items) - ng_count}・NG {ng_count}"
          f"（流し直して OK {sum(1 for i in first_ng if retried.get(i, {}).get('ok'))}本）")
    print(f"かかった時間 {fmt(wall)}（1本ずつ流した時間の合計 {fmt(total)}、{jobs}本ずつ並列）")
    print("== " + ("ALL OK" if ng_count == 0 else f"FAILED（{ng_count}本）") + " ==")
    return 0 if ng_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
