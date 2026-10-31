"""架空の外国人選手のひな形（docs/AUTORUN.md 作業31）。

2009〜2025年の新外国人（その年のシーズン後の能力値ファイルにいて、前年のシーズン後にいない外国人）について、
出身・前の所属・人数・1年目の能力（その年のシーズン後の能力値）・在籍年数を集めて generated/foreign.json に書き出す。
Godot の `ForeignPlayers`（godot/sim/foreign_players.gd）が、史実の無い年の外国人市場の候補を作るのに使う。

    python tools/foreign_players.py

- 出身の国は npb.jp に無いので、経歴（出身校・前の所属）と名前の書き方から推定する（`origin_of`）:
  漢字の名前 → 韓国（経歴に「韓国」）か台湾、経歴に「キューバ」→ キューバ、スペイン語の姓（`HISPANIC_SURNAMES`）か
  中南米の学校名（`HISPANIC_SCHOOL_WORDS`。大学を経ない高校から）→ 中南米、
  それ以外で米国の大学・高校やメジャー球団の経歴 → 米国、どれでもない → その他。
  中南米は国までは分からないので、作るときに `LATIN_SPLIT` の割合で国を割り振る（ドミニカ・ベネズエラ・メキシコ・プエルトリコ・その他）
- 前の所属は経歴の最後（`prev_of`）：メジャー球団・米マイナー・米独立リーグ・韓国・台湾・キューバ・メキシコ・日本の独立リーグ・その他
- 1年目の能力は能力値ファイルの選手データそのもの（成績の内訳 detail は除く）。作るときはこれに小さなゆらぎを足す
標準ライブラリのみ。
"""
from __future__ import annotations

import json
import math
from collections import Counter
from pathlib import Path

import growth_coefficients as gc

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "generated" / "foreign.json"

FIRST_YEAR = 2009  # 2008年は前年のファイルが無く、新外国人を見分けられない
LAST_YEAR = 2025   # 2026年はシーズン途中の成績
COUNT_YEARS = range(2016, 2026)  # 毎年の人数の基準（直近10年。年々増えているので）
PER_TEAM_YEARS = range(2017, 2027)  # 球団ごとの外国人の人数の基準（開幕時点）

LATIN_SPLIT = {"ドミニカ": 0.5, "ベネズエラ": 0.25, "メキシコ": 0.08, "プエルトリコ": 0.08, "パナマ": 0.05, "コロンビア": 0.04}

HISPANIC_SURNAMES = {
    "ロドリゲス", "ヘルナンデス", "エルナンデス", "マルティネス", "ゴンザレス", "ゴンザレズ", "ペレス", "ロペス", "ガルシア",
    "サンチェス", "ラミレス", "トーレス", "フローレス", "リベラ", "ゴメス", "ディアス", "レイエス", "モラレス", "クルーズ",
    "クルス", "オルティス", "グティエレス", "チャベス", "ラモス", "ゲレーロ", "メンドーサ", "ルイーズ", "アルバレス",
    "カスティーヨ", "カスティージョ", "ヒメネス", "モレノ", "ロメロ", "エレーラ", "ヘレーラ", "メディナ", "アギラー",
    "バルガス", "カストロ", "フェルナンデス", "ゲラ", "ソーサ", "バルデス", "ペーニャ", "ペニャ", "サンタナ", "メヒア",
    "ベラスケス", "パヤノ", "グスマン", "ヌニェス", "アブレイユ", "アブレウ", "デラクルーズ", "カブレラ", "オスナ",
    "ロサリオ", "ピネダ", "エスピナル", "ソト", "メルセデス", "モンテロ", "カラスコ", "アルモンテ", "エンカーナシオン",
    "ブランコ", "ブリトー", "ミランダ", "セサル", "サンティアゴ", "マルテ", "ロハス", "ペゲーロ", "モンテス", "ナニータ",
    "デスパイネ", "グラシアル", "モイネロ", "メルセデス", "ビシエド", "ロメロ", "アルカンタラ", "ガルシア", "マルモレホス",
    "ロサ", "オビスポ", "ペルドモ", "アルメンゴ", "アキーノ", "セデーニョ", "コラス", "ゼラス", "ソリス", "サントス",
    "マチャド", "ルーゴ", "ゲレロ", "パディーヤ", "ベタンコート", "エスコバー", "ビヤール", "ガルビス", "アコスタ",
    "ドミンゲス", "オテロ", "カリダ", "メネセス", "マルティン", "バレンティン", "ペーニャ", "パーラ", "オルランド",
    "ムニス", "アギーラ", "デラクルス", "カラバイヨ", "モリーヨ", "ザラテ", "バリオス", "ブラゾバン", "フィガロ", "サラサー",
    "レデズマ", "ピント", "テレーロ", "ヘルマン", "マドリガル", "ルナ", "モスコーソ", "カニザレス", "エレラ", "ガラテ",
    "アルフォンゾ", "アルバラード", "ベルトラン", "バティスタ", "ペラルタ", "オリベラ", "ヌニエス", "フリアス", "ポランコ",
    "アルシア", "サンタナ", "カスティーヤ", "ピメンテル", "ロドニー", "セペダ", "ラミレズ", "ゴンサレス", "ベタンセス",
}
# 中南米の学校名によく出る語（リセオ＝高校、エスクエラ＝学校、UE＝ベネズエラの学校、「〜デ〜」など）
HISPANIC_SCHOOL_WORDS = ("リセオ", "エスク", "エスケ", "コレヒオ", "ホセ", "フアン", "ペドロ", "マヌエル", "ラファエル",
                         "アントニオ", "ヘスス", "マリア", "ドゥアルテ", "デュアルテ", "UE", "U.E", "ESPA", "サンペドロ",
                         "デマコリス", "デパレンケ", "デディシェンブレ", "ウデ", "ロスシーオ", "ペルムイ", "パームイ",
                         "グレゴリオ", "パブロ", "アビラ", "ロドリゲス高", "ヘルマン", "ネグラ", "エイデ")
MLB_TEAMS = [
    "ヤンキース", "レッドソックス", "オリオールズ", "ブルージェイズ", "レイズ", "デビルレイズ", "ホワイトソックス", "インディアンス",
    "ガーディアンズ", "タイガース", "ロイヤルズ", "ツインズ", "アストロズ", "エンゼルス", "アスレチックス", "マリナーズ",
    "レンジャーズ", "ブレーブス", "マーリンズ", "メッツ", "フィリーズ", "ナショナルズ", "エクスポズ", "カブス", "レッズ",
    "ブルワーズ", "パイレーツ", "カージナルス", "ダイヤモンドバックス", "ロッキーズ", "ドジャース", "パドレス", "ジャイアンツ",
]
JAPAN_INDEPENDENT = ("BC・", "四国・", "関西・", "北海道・", "九州・", "日本海・", "さわかみ")


def is_kanji_name(name: str) -> bool:
    return "." not in name and any("一" <= ch <= "鿿" for ch in name)


def surname_of(name: str) -> str:
    return name.split(".")[-1].split("・")[-1].strip()


def segments(p: dict) -> list[str]:
    return [s.strip() for s in (p.get("career") or "").split(" - ") if s.strip()]


def origin_of(p: dict) -> str:
    career = p.get("career") or ""
    name = p.get("name") or ""
    if is_kanji_name(name):
        return "韓国" if "韓国" in career else "台湾"
    if "キューバ" in career:
        return "キューバ"
    segs = segments(p)
    first = segs[0] if segs else ""
    if surname_of(name) in HISPANIC_SURNAMES or ("大" not in first and any(w in first for w in HISPANIC_SCHOOL_WORDS)):
        return "中南米"
    if "大" in first or "高" in first or "校" in first or any(t in career for t in MLB_TEAMS) or "米" in career:
        return "米国"
    return "その他"


def prev_of(p: dict) -> str:
    segs = segments(p)
    last = segs[-1] if segs else ""
    if last in MLB_TEAMS:
        return "メジャー球団"
    for key, label in [("米マイナー", "米マイナー"), ("米独立", "米独立リーグ"), ("韓国", "韓国"), ("台湾", "台湾"),
                       ("キューバ", "キューバ"), ("メキシ", "メキシコ"), ("ドミニカ", "ドミニカ")]:
        if key in last:
            return label
    if last.startswith(JAPAN_INDEPENDENT):
        return "日本の独立リーグ"
    if len(segs) <= 1:
        return "アマチュア"
    return "その他"


def mlb_org(p: dict) -> bool:
    return any(seg in MLB_TEAMS for seg in segments(p))


def trimmed(p: dict) -> dict:
    """ひな形に残す選手データ（成績の内訳 detail・所属・名前などは除く）"""
    keep = {k: p.get(k) for k in ["is_pitcher", "primary_pos", "throws", "bats", "height", "weight", "birth"]}
    for block in ["batting", "pitching"]:
        b = p.get(block)
        if isinstance(b, dict):
            b = {k: v for k, v in b.items() if k != "detail"}
        keep[block] = b
    fielding = {}
    for pos, f in (p.get("fielding") or {}).items():
        fielding[pos] = {k: v for k, v in f.items() if k != "detail"}
    keep["fielding"] = fielding
    return keep


def main() -> None:
    debut = gc.debut_years()
    post = {y: gc.load(y) for y in range(FIRST_YEAR - 1, LAST_YEAR + 2)}
    templates = []
    counts = {}
    origins = Counter()
    prevs = Counter()
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        n = {"p": 0, "b": 0}
        for pid, p in post[y].items():
            side = gc.side_of(p)
            if pid in post[y - 1] or side is None or not gc.is_foreign(p, y, debut):
                continue
            age = gc.age_at(p, y)
            if age is None:
                continue
            # 在籍年数（その年から続けてシーズン後のファイルにいる年数。2026年まで）
            tenure = 1
            while y + tenure in post and pid in post[y + tenure]:
                tenure += 1
            z, playing = gc.ability(p, side)
            n["p" if side == "P" else "b"] += 1
            origin, prev = origin_of(p), prev_of(p)
            origins[origin] += 1
            prevs[prev] += 1
            templates.append({"year": y, "side": side, "age": age, "origin": origin, "prev": prev, "mlb_org": mlb_org(p),
                              "tenure": tenure, "censored": y + tenure > LAST_YEAR + 1, "z": round(z, 3),
                              "playing": round(playing, 3), "player": trimmed(p)})
        counts[y] = n
    # 球団ごとの外国人（支配下・育成の区別なし）の人数（開幕時点）
    per_team = []
    for y in PER_TEAM_YEARS:
        teams = Counter()
        all_teams = set()
        for p in gc.load(y, "pre").values():
            all_teams.add(p.get("team"))
            if gc.is_foreign(p, y, debut):
                teams[p.get("team")] += 1
        per_team.append(sum(teams.values()) / max(1, len(all_teams)))
    total = sum(origins.values())
    # 在籍年数の分布（2024年までに来た選手。打ち切りの少ない範囲）と、1年目の実力の上位・下位4分の1の平均在籍年数
    done = [t for t in templates if t["year"] <= 2021]
    tenure_share = {str(k): round(sum(1 for t in done if min(t["tenure"], 4) == k) / len(done), 3) for k in (1, 2, 3, 4)}
    by_z = sorted(done, key=lambda t: t["z"])
    q = len(by_z) // 4
    out = {
        "schema_version": 1,
        "source": f"generated/ratings/<年>_post.json の新外国人 {FIRST_YEAR}〜{LAST_YEAR}年",
        "counts": {str(y): counts[y] for y in counts},
        "count_years": list(COUNT_YEARS),
        "origin_share": {k: round(v / total, 4) for k, v in origins.most_common()},
        "latin_split": LATIN_SPLIT,
        "prev_share": {k: round(v / total, 4) for k, v in prevs.most_common()},
        "per_team_foreigners": round(sum(per_team) / len(per_team), 2),
        "tenure_share": tenure_share,
        "tenure_by_ability": {"bottom_quarter": round(sum(t["tenure"] for t in by_z[:q]) / q, 2),
                              "top_quarter": round(sum(t["tenure"] for t in by_z[-q:]) / q, 2)},
        "templates": templates,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=None, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}（{len(templates)}人, {OUT.stat().st_size // 1024}KB）")
    for k in ["counts", "origin_share", "prev_share", "per_team_foreigners", "tenure_share", "tenure_by_ability"]:
        print(k, out[k])
    ages = [t["age"] for t in templates]
    print("年齢 平均", round(sum(ages) / len(ages), 1), "最小", min(ages), "最大", max(ages))
    for side in ["P", "B"]:
        zs = [t["z"] for t in templates if t["side"] == side]
        m = sum(zs) / len(zs)
        print(side, "実力z 平均", round(m, 2), "sd", round(math.sqrt(sum((x - m) ** 2 for x in zs) / len(zs)), 2),
              "z≥0.5", sum(1 for x in zs if x >= 0.5), "/", len(zs))


if __name__ == "__main__":
    main()
