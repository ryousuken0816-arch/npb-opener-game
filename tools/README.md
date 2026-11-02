# tools/

## compute_ratings.py — 能力値算出

```
python tools/compute_ratings.py --year 2008               # 開幕時点 → generated/ratings/2008_pre.json
python tools/compute_ratings.py --year 2008 --phase post  # シーズン後 → generated/ratings/2008_post.json
```

`data/` のうち対象年以前の全年を入力に、対象年の在籍選手の能力値を算出する（標準ライブラリのみ）。

- `pre`（既定）: **前年までの成績**で算出。開幕時の能力値
- `post`: **当年までの成績**で再計算。シーズン後（オフ）の能力値。翌年の `pre` と同じ成績範囲だが、在籍選手は当年のもの

2軍・守備成績と表彰は `data/<年>/` にしかないため、使える年がない場合（2008年 pre）は最古の年で代用し、出力の `fallbacks` に記録する。
ロジックは docs/SPEC.md「能力値算出ロジック」。定数はすべてスクリプト冒頭にまとめてある。

### 算出の流れ

1. **成績の合算**: 1軍（players.json）と2軍（teamstats_linked.json）を直近3年 1.0/0.7/0.5 の加重で合算（Marcel方式を少し直近寄りに。作業40で 1.0/0.8/0.6 から変更）。
   2軍は1軍換算係数（例: 本塁打×0.70）を掛け、サンプル量は半分として数える
2. **少サンプル補正**: `w = min(1, サンプル / FULL)` で 観測値 と 事前値 を線形ブレンド。
   FULL は指標ごと（打率 400打席、BB% 200打席、FIP 450アウト=150回 など）。
   事前値は正規化母集団の何パーセンタイル目か（`prior_pctl_for`）。既定は30パーセンタイル（`PRIOR_PCTL`。
   出場の少ない選手は平均以下が多いため）だが、ドラフト情報のある選手はそこから加減する（新人の初期能力。下記）
3. **正規化**: 対象年から5年分の1軍シーズン（200打席以上 / 50回以上 / 守備は同一位置40試合以上）を母集団に z 値化
4. **スケール**: `63 + 17 × z` を 1〜100 に丸め、ランク S≥90 A≥80 B≥70 C≥60 D≥50 E≥40 F≥20 G<20
   （母集団が規定打席/規定投球回クリア済みの「そこそこ良い選手」に絞られているため、平均をそのまま
   D帯に置くとレギュラーの大半がD以下に沈む。平均をC寄りに、SDを広めにして、レギュラー級がC〜D中心・
   主力がB以上・スターがA/Sに届くように調整済み。定数は `SCALE_MEAN` / `SCALE_SD`）

### 各能力の指標

| 能力 | 指標 |
|---|---|
| ミート | 打率 0.6 ＋ コンタクト率(1−三振/打数) 0.4 |
| パワー | ISO（塁打−安打）/打数 |
| 選球眼 | BB%（四球/打席） |
| 走力 | 盗塁企図率 0.45 ＋ 盗塁成功率 0.15 ＋ 三塁打率 0.4 |
| 肩力 | 守備位置別の 補殺/試合（捕手・三塁・遊撃・外野）※2020年以降は外野・捕手は npbbasement の ARM、三塁・遊撃は外野ARMまたは補殺/試合 |
| 守備力 | 守備位置別の失策率 ＋ ゴールデングラブ（2019年までの成績の外野は走力を25%混ぜる。作業43、`OF_SPEED_*`）。※2020年以降は npbbasement の守備得点（内野: RngR+ErrR+DPR、外野: RngR+ErrR、捕手: Framing+Blocking+ErrR+ARM） |
| 投手 総合力 | FIP（定数 = 年ごとのリーグ防御率 − 素のFIP）。**先発・救援で別々に正規化** |
| 投手 スタミナ | 1登板あたりアウト数（12以上で先発扱い。先発数がデータにないため）。先発・救援共通で正規化 |
| 投手 K/9・BB/9・HR/9 | 先発・救援で別々に正規化 |
| 投手 特殊能力 | K/9・BB/9・HR/9 が同じ役割の母集団で上位15%/下位15%なら付与（50回未満は付与しない） |
| 投手 球速 | `data/velocity.json`（2011年〜、実測 km/h）を Marcel 加重で平均。データが無い期間は代用（下記） |
| 野手 弾道（1〜4） | ISO と HR/打数 の z 値（0.5/0.5）をしきい値で分類。実データなしの代用指標 |

球速・弾道はランク（G〜S）ではなく実数値のみを出力する（パワプロ画面で球速・弾道は数値のまま表示されるため）。

**球速のデータが無い場合の代用**（`velocity_for`、`source` に記録）:
1. 対象年までの実測値がない場合、その投手の最古の実測値を「最古の年との差×`VELOCITY_EARLY_DECAY_PER_YEAR`（上限 `VELOCITY_EARLY_DECAY_CAP`）」だけ下げて使う（`early_career`）。主に2008〜2010年向け
2. 実測値が一切ない投手（2010年以前引退など）は、実測値のある投手の通算K/9→実測値平均 の単回帰で推定し `VELOCITY_MIN_KMH`〜`VELOCITY_MAX_KMH` にクリップ（`estimated`）
3. 通常は対象年から遡り3年をMarcel加重平均（`observed`）
4. **1軍・2軍とも登板実績が一切ない投手**（新人・新外国人。K/9も算出できないため②の回帰も使えない）は
   平均球速（`velocity_mean_kmh`）にドラフト順位による加減（`PROVISIONAL_VELOCITY_ROUND_BONUS`。上位指名ほど+、育成は`PROVISIONAL_VELOCITY_IKUSEI_PENALTY`）を加えた仮の値（`provisional`）。`pitching`自体は下記「新人の初期能力」により null にならない

### 新人（プロ成績が少ない選手）の初期能力

少サンプル補正のブレンド先（事前値、上記②）を、通常の「母集団の30パーセンタイル目」ではなく
**ドラフト順位＋出身区分から決めたパーセンタイル目**にする（`prior_pctl_for`）。2軍の成績が出れば
blend の重みが自然に上がり実績側へ寄っていくので、この事前値は初期値（新人の頃）にしか効かない。

- 出身区分は drafts.json の `school` から判定（`draft_category`）：`〜高`＝高校（`ROOKIE_BASE_PCTL["高校"]`＝低め）、
  `大`を含む＝大学、それ以外＝社会人・独立リーグ等（即戦力寄り＝高め）
- ドラフト順位（`round`。「1位」「1巡目」どちらの表記も対応）が上位ほど加算（`ROOKIE_ROUND_PCTL_BONUS`）、育成指名は減算（`ROOKIE_IKUSEI_PCTL_PENALTY`）
- drafts.json に player_id が無いため名前（`norm_name`）で突合。ドラフト情報が見つからない選手（主に外国人）は既定値 `ROOKIE_IMPORT_PCTL`
- パーセンタイルは `ROOKIE_PCTL_MIN`〜`ROOKIE_PCTL_MAX` にクリップ

この事前値は打撃・投手・守備すべての `_rate_block` に共通で渡す（`batting`/`pitching`/`fielding` は `name` 引数を受け取る）。
投手は1軍・2軍とも成績が一切ない場合も `pitching(..., force=True)` で（全指標が事前値のみの）能力値を必ず生成するため、
`is_pitcher` な選手の `pitching` が null になることはない（役割は判定不能なため `role: "救援"` 扱い）。

### メジャーにいた年の能力値（`mlb_players`）

FA・ポスティングでメジャーへ行く選手を引き留めたときに使う（docs/SPEC.md「決定事項：FA・ポスティング」）。
`data/mlb_moves.json` の選手のうち **2008年以降に出ていった**（`MLB_RATINGS_MIN_LEFT_AFTER`）選手について、
対象年にメジャーにいる（`left_after < 年 < returned`）間の能力値を、各ファイルの `mlb_players` に出す（`players` とは別。所属は無し）。

1. `data/mlb_stats.json` のメジャー年度別成績を選手ページと同じ形の行に直し、回数に **NPB換算の係数**を掛ける
   （打撃 `MLB_TO_NPB_BAT`、投手 `MLB_TO_NPB_PIT`。打席・打数・アウト数はそのまま）
2. その行を NPB の成績に足して、NPB の選手とまったく同じ手順（Marcel加重・少サンプル補正・同じ年の母集団で正規化）で算出。
   守備・2軍は退団した年までのもの
3. 直近にメジャーの成績が無い年（マイナー・故障。例：中島宏之 2013〜2014年）は、成績のある最後の年の時点で算出し、
   そこから年齢に応じて1年ごとに増減する（`MLB_NO_STATS_DRIFT`：26歳以下 +1、27〜31歳 ±0、32歳以上 −1.5）

換算の係数は、`mlb_moves.json` の選手の「移籍前3年のNPB ↔ 移籍後3年のMLB」「復帰前2年のMLB ↔ 復帰後2年のNPB」の率の比
（2026-09集計：安打 1.13・二塁打 1.10・本塁打 1.87・四球 1.20・三振 0.90・盗塁 1.12／被本塁打 0.61・与四球 0.75・奪三振 1.00）を、
好調期にメジャーへ行った選手が多い分だけ控えめに丸めた値（安打 1.12・本塁打 1.70・四球 1.15・三振 0.90／被本塁打 0.65・与四球 0.78・奪三振 1.00）。

各選手には `mlb` 項目が付く：`{mlb_id, npb_team_before, left_after, returned, stats_through（使った成績の最終年）, drift_years, mlb_seasons}`。
例：ダルビッシュ 2012 pre はNPB 2011年までで算出（NPB時代と同じ値）、2012 post はメジャー2012年の換算成績込み。

### 出力フォーマット（`generated/ratings/<年>_<phase>.json`）

```jsonc
{
  "schema_version": 4,              // 4: mlb_players を追加
  "year": 2008,                     // 在籍の年
  "phase": "pre",                   // pre=開幕時点 / post=シーズン後
  "stats_through": 2007,            // 使った成績の最終年
  "fallbacks": ["..."],             // データ不足で代用した内容
  "source_years": [2005, 2006, 2007, 2008],  // 入力に使った data/<年>
  "scale": {"min": 1, "max": 100, "ranks": [{"min": 90, "rank": "S"}, ...]},
  "fip_constant": 3.021,
  "players": [{
    "id": "21125113",               // npb.jp 選手ID。1軍出場なしは "tmp:<球団コード>:<名前>"
    "provisional_id": false,
    "name": "阿部 慎之助", "team": "読売ジャイアンツ", "team_id": "1947001", "league": "C",
    "throws": "右", "bats": "左", "birth": "1979-03-20", "height": 180, "weight": 97,
    "draft": "2000年ドラフト1位", "career": "...",
    "is_pitcher": false,
    "primary_pos": "捕手",          // 投手/捕手/一塁手/二塁手/三塁手/遊撃手/外野手/内野手/指名打者/null
    "batting": {
      "ratings": {                   // defense/arm は primary_pos の値（無い場合はキーなし）
        "meet": {"value": 59, "rank": "D"}, "power": {...}, "eye": {...}, "speed": {...},
        "defense": {...}, "arm": {...}
      },
      "detail": {"avg": {"observed": 0.281, "blended": 0.281, "weight": 1.0}, ...},  // 詳細画面の実数値（hr_rate含む）
      "sample": {"pa_1": 1246.2, "pa_2": 0.0},                                     // 加重後の打席数
      "trajectory": 3                                                             // 弾道 1〜4（実数値のみ）
    },
    "pitching": null | {          // null は投手でない選手のみ。投手は成績ゼロでも必ずオブジェクトが入る
      "ratings": {"overall": {...}, "stamina": {...}, "k9": {...}, "bb9": {...}, "hr9": {...}},
      "abilities": ["奪三振", "被弾抑制"],
      "role": "先発" | "救援",
      "detail": {"fip": {...}, ...},
      "velocity": {"kmh": 148, "source": "observed"},  // observed/early_career/estimated/provisional。nullにはならない
      "sample": {"outs_1": 1369.8, "outs_2": 0.0}
    },
    "fielding": {                    // 守備位置ごと（1軍・2軍いずれかで守備記録のある位置）
      "捕手": {"games": 122, "defense": {...}, "arm": {...}, "gold_glove": true, "detail": {...}}
    }
  }],
  "mlb_players": [{ /* players と同じ形。team/league は null、"mlb": {...} 付き（上記） */ }]
}
```

### 決定済み

- 捕手の肩力は 補殺/試合（盗塁阻止率の代替）で確定
- 投手は先発/救援を別々に正規化
- 能力値は前年までの成績で算出し、シーズン後に再計算
- スタミナと先発/救援判定（1登板12アウト以上）を採用
- 守備成績もドラフト情報もない選手（2006年以前指名の未出場選手など）は `primary_pos: null`。全年データが揃えば解消する見込み
- 2005〜2007年のチーム成績・表彰（data/2005〜2007）を取得済みのため、2008年 pre のフォールバックは解消（players.json・drafts.json が無い年はスキップして読み込む）
- 球速・弾道の指標と代用ロジックは上記のとおり確定（係数は `tools/compute_ratings.py` 冒頭の `VELOCITY_*` / `TRAJECTORY_*` 定数で調整可能）
- 新人の初期能力はドラフト順位＋出身区分ベースで確定（係数は `ROOKIE_*` 定数）。2軍成績が出れば既存の少サンプル補正でそのまま実績側に寄っていく

## fetch_basement.py — basement守備データ取得

```
python tools/fetch_basement.py   # → data/basement/<年>_<1g|2g>.json（リポジトリ外・.gitignore）
```

https://npbbasement.com/ から 2020〜2026年（1軍・2軍）の守備指標データ（RngR, ErrR, DPR, ARM, Framing, Blocking）を取得・保存する。取得した JSON は git 管理外。

## rebuild_all_ratings.py — 全能力値・派生ファイルの一括再生成

```
python tools/rebuild_all_ratings.py
```

2008〜2026年の全 ratings（pre/post）および 2027_pre、手で決めた能力値の当て直し（`manual_overrides.py`。下記）、アマチュア新人・継続データ、将来性、成長係数（growth.json）、外国人（foreign.json）、架空ドラフト（fictional_draft.json）を一括で順番通りに再生成するパイプラインスクリプト。

## manual_overrides.py — 手で決めた能力値の当て直し

```
python tools/manual_overrides.py   # rebuild_all_ratings.py が compute_ratings のあとに呼ぶ
```

`tools/manual_overrides.json` の `files.<年>_<phase>.<選手ID>` の打撃（ミート・パワー・選球眼・走力・弾道）・投球（総合・スタミナ・K/9・BB/9・HR/9・球速）・成長（`growth`）を、
作り直した `generated/ratings/` に当てる。守備力・肩は当てない（basement から出した値のまま）。今は Antigravity が 2026-11-01 に強化した2024年ドラフトの6人
（石塚裕惺・金丸夢斗・中村優斗・宗山塁・渡部聖弥・西川史礁。2026_pre・2026_post・2027_pre）だけ。

## growth_coefficients.py — 成長・衰え・引退の係数（docs/AUTORUN.md 作業27）

```
python tools/growth_coefficients.py   # → generated/growth.json（Godot の Growth が読む。godot/README.md「成長・衰え・引退」）
```

史実の能力値ファイルが無い年（2028年の開幕から）に、毎オフ能力を動かすための係数。`generated/ratings/` を作り直したら流し直す（標準ライブラリのみ、十数秒）。
定数はスクリプト冒頭（`LAST_FROM`・`TARGET_YEARS`・`AGE_BANDWIDTH`・`MIN_SAMPLE_*` など）。

- **成長**：同じ選手の開幕時点どうし（`<年>_pre` → `<年+1>_pre`、2008→2009 〜 2025→2026）の変化を、項目ごと（野手：ミート・パワー・選球眼・走力・守備力・肩力、
  投手：総合・スタミナ・K/9・BB/9・HR/9・球速）に `来季 − 今 = a(年齢) + b(年齢)×(今 − 63) + sd(年齢)×ゆらぎ` で回帰（年齢は来季の4月1日時点、
  近い年齢に重みを付けたガウス核・幅1.5歳）。前年までの出場が多い選手（加重の打席・アウト数100以上。2軍は半分）は `keys`、少ない国内の選手（新人）は `keys_low`
  （幅3歳、組の少ない年齢は `keys` に寄せる）。球速は実測どうしの組だけ
  - リーグの平均くらいの選手の1年の変化（`keys`、20/24/28/32/36/40歳）：ミート +0.2/+1.0/+1.0/+0.5/+0.1/+0.8、パワー +1.1/+0.6/+0.2/0/−0.4/−0.2、
    走力 +4.1/+1.1/−0.5/−1.2/−1.7/−1.4、K/9 +1.1/0/−0.4/−0.8/−1.4/−1.9、球速 +0.5/+0.2/0/−0.3/−0.4/−0.5 km/h。
    ばらつき（sd）はミート 6〜7・パワー 4〜5・走力 3〜8・守備力 9〜13・K/9 5〜8。b は −0.05〜−0.4（高い選手ほど下がりやすい）
- **ゆらぎ**：残差を sd で割った値の分位点（`shock_quantiles`。0.1%点 −3.9、99.9%点 +4.2 と正規分布より裾が重い）と、項目どうしの残差の相関のコレスキー分解（`shock_cholesky`）
- **投手の総合**（`derived.overall`）：役割ごとに `総合 = const + c×K/9 + c×BB/9 + c×HR/9 + ずれ`（先発 R²=0.95、救援 0.89）。ずれは翌年 rho（約0.72）倍に縮む
- **投手の役割**（`role`）：来季に先発になる確率のロジスティック回帰（今の役割ごと。年齢・スタミナ・総合・出場の少なさ）。先発のまま 83%、救援から先発 8.5%（新人は高め）。
  スタミナは移り変わりの種類（先発>先発・先発>救援・救援>先発・救援>救援）ごとの回帰（`stamina_by_role`）
- **新人の守備位置**（`batting.rookie_fielding`）：守備の記録が無い新人の野手（primary_pos が「内野手」「外野手」「捕手」）が2年目に付いた守備位置・守備力・肩力の例（区分ごとに最大200）
- **リーグ全体の目標**（`target`）：2017〜2026年の開幕時点の全選手の平均・ばらつき（スタミナは役割ごとも）と先発の割合（22.9%）
- **引退**（`retire`）：`<年>_post` の選手が `<年+1>_post` にいない確率（メジャー移籍は除く、2008→2009 〜 2025→2026）のロジスティック回帰。
  特徴量は 年齢−30・max(0,年齢−33)・max(0,26−年齢)・実力 z と出場量（`Salary.ability` と同じ式）・外国人・投手・外国人×実力・外国人×出場量。
  国内の選手の実際の割合と予測は 18〜23歳 1.4%/1.2%、28〜30歳 11.2%/11.3%、34〜36歳 24.7%/22.5%、40歳〜 35.2%/36.4%、
  外国人は 42%（1年目の実力の下位4分の1 62%/59%、上位4分の1 18%/17%）

## foreign_players.py — 架空の外国人選手のひな形（docs/AUTORUN.md 作業31）

```
python tools/foreign_players.py   # → generated/foreign.json（Godot の ForeignPlayers が読む。godot/README.md「架空の外国人選手」）
```

2009〜2025年の新外国人（その年の `<年>_post` にいて前年の `<年−1>_post` にいない外国人。599人）の、出身・前の所属・年齢・1年目の能力（`<年>_post` の選手データ、detail は除く）・在籍年数。
`growth_coefficients.py`（`is_foreign` などの関数）を使う。`generated/ratings/` を作り直したら流し直す。

- 人数（`counts`）：投手 12〜26人・野手 10〜19人／年。作るときは直近10年（`COUNT_YEARS`）のどれか1年の人数
- 出身（`origin_share`、推定）：npb.jp に国籍が無いので経歴と名前から。漢字の名前は韓国（経歴に「韓国」）か台湾、経歴に「キューバ」はキューバ、
  スペイン語の姓（`HISPANIC_SURNAMES`）か中南米の学校名（`HISPANIC_SCHOOL_WORDS`）は中南米、ほかは米国。米国 65%・中南米 30%・キューバ 3%・台湾 2%・韓国 1%。
  中南米の国は分からないので `LATIN_SPLIT`（ドミニカ 50%・ベネズエラ 25%・メキシコ 8%・プエルトリコ 8%・パナマ 5%・コロンビア 4%）で割り振る
- 前の所属（`prev_share`）：メジャー球団 70%・米マイナー 15%・韓国 4%・台湾 3%・日本の独立リーグ 3%・キューバ 3%・アマチュア 2%
- 1年目の実力（`Salary.ability` の z）：投手 平均 −0.18（sd 0.32）、野手 −0.34（sd 0.46）
- 球団ごとの外国人（`per_team_foreigners`、2017〜2026年の開幕時点）：7.1人
- 在籍年数（`tenure_share`、2021年までに来た選手）：1年 52%・2年 22%・3年 8%・4年以上 18%。1年目の実力の下位4分の1は平均1.7年、上位4分の1は3.5年

## amateur_ratings.py — アマ選手の初期能力（作業16・17）

プロの成績が無い選手（2026年秋の新人・2027年秋のドラフト候補）の初期能力を、**有識者の評価**（`data/amateur/<年>.json` の
`scout`：長所・短所・総合の格付け）を主な根拠に作る（ユーザー指示 2026-11-01）。数字（最速・50m走・遠投）は補助。

```
python tools/compute_ratings.py --year 2027 --phase pre      # 先に名簿の選手（2026年の成績まで）
python tools/amateur_ratings.py rookies --draft-year 2026    # 2026年秋の新人を 2027_pre に足す（仮ID ama2026:<名前>）
python tools/amateur_ratings.py carry --year 2027            # 2027_post（2027_pre の引き継ぎ）と 2028_pre（＋2027年の候補）
python tools/draft_future.py                                 # 将来性の元データ（2026年まで）
```

1. 下地：`generated/ratings/2026_pre.json` の2025年秋の新人（compute_ratings の新人の初期能力＝区分＋順位）を、
   投手か・区分（高校／大学／社会人。独立は社会人）・順位の帯（1／2〜3／4〜5／6〜／育成）ごとに平均したもの
2. 帯：史実の指名（2026年）は実際の順位で選び、格付けとの差1段あたり ±3（`GRADE_STEP`×差/2）。候補（2027年）は格付けで
   選ぶ（S・A＝1位、B＝2〜3位、C＝4〜5位、D＝育成。S は +3）
3. 長所・短所の言葉（`PITCH_WORDS`・`BAT_WORDS`）で該当の能力を +6／−5（1能力 ±12 まで）。長打の長所で弾道+1
4. 投手の球速は 最速−5km（128〜158）。下地の球速との差1kmあたり総合・奪三振を ±0.5（±8まで）。50m走は6.0秒との差0.1秒あたり
   走力 ±2、遠投は100mとの差1mあたり肩力 ±0.3（±8まで）
5. 史実の無い年は成績が無いので、選手のリーグを2026年の「球団 → リーグ」で埋める（`fill_leagues`）

出力の選手には `amateur`（intro・grade・type・projected・fictional など）が付き、ドラフト画面の紹介文に使う。
2028_pre の候補は球団が空（`team: ""`）で、ゲームのドラフトで行き先が決まる。

## fictional_draft.py — 架空のドラフト候補・転生選手のひな形（docs/AUTORUN.md 作業22・32）

```
python tools/fictional_draft.py   # → generated/fictional_draft.json（Godot の FictionalDraft が読む。godot/README.md「架空のドラフト候補・転生選手」）
```

- ひな形（`templates`、990人）：2008〜2020年の指名選手で翌年の `<年+1>_pre` にいる選手。区分（出身校から 高校・大学・社会人・独立）・順位の帯（1／2〜3／4〜5／6〜／育成）・守備位置、
  入団時の能力（`<年+1>_pre` の選手データ、detail は除く）、ピーク（指名の翌年以降の `<年>_post` で実力＝`Salary.ability` の z＋0.6×出場量 がいちばん高い年の能力、球速は最速）・ピークの年齢・点（`draft_future.py` と同じ式。一度も出てこない選手は −1.2）
- 史実の割合（流したときの表示）：将来性S（点1.6以上）は年1.8人、A以上は年4.9人、6位以下・育成から A以上は年0.5人
- 学校（`schools`、777校）：2008〜2026年の指名の出身校・所属と人数（「〇〇大学」は「〇〇大」にそろえる）。1年の人数（`class_sizes`）：2016〜2025年の本指名・育成の人数
- 転生のもと（`legends`、132人）：2008〜2026年の `_post` の日本人選手（ドラフト歴あり）で実力のピークが1.1以上。ピークの年の能力・球速（最速）・守備の記録・投打・体格・球団・出身校
- `generated/ratings/` を作り直したら流し直す

## ratings_audit.py — 能力値の点検の表（docs/AUTORUN.md 作業39）

```
godot --headless --path godot --script res://tests/ratings_audit_dump.gd -- 2026 <出力先>/sim2026_1.json   # 1回 約10秒、年と回数を変えて何回か
python tools/ratings_audit.py --sims "<出力先>/sim*.json" --out <表>.md [--saber <外部の指標の CSV（リポジトリには入れない）>]
```

能力値（2026_pre など）・npb.jp の実際の成績（記録室と同じ式の wRC+・FIP・WAR）・タイトルとゴールデングラブ・ゲームを回した成績の平均を並べた表を作る。
ゲームの処理・能力値は変えない（読むだけ）。結果の資料は `docs/reports/ratings_audit.md`。

## run_tests.py — Godot のテストを並列に流す（docs/AUTORUN.md 作業52）

```
python tools/run_tests.py quick                   # 速い組（約5分以内。作業中に関係するテストと一緒に）
python tools/run_tests.py full                    # 全部（main に入れる前に1回）
python tools/run_tests.py save_check trade_check  # 名前を並べて
python tools/run_tests.py layout_fit_check:quick  # 軽い版（2008年だけ）
python tools/run_tests.py --list                  # 組の中身と見込みの時間
```

- `godot/tests/` の `*_check.gd`・`*_test.gd` を Godot のヘッドレスで同時に N 本（`-j`。既定はコア数の半分、最大6）流す。重いものから先に。Godot は優先度「通常以下」・ウィンドウなし
- テストごとにセーブの場所（`godot/.godot/test_logs/<日時>/saves/<テスト>`）を環境変数 `NPB_TEST_SAVE_DIR` で渡す（`SaveGame.test_dir()`）。ユーザーのセーブ（`user://saves/`）は読まない・触らない
- ログは `godot/.godot/test_logs/<日時>/<テスト>.log`（直近5回分）。NG は終了コードが0でない・時間切れ・`SCRIPT ERROR`／`Parse Error`。エンジンの `ERROR:`（描画など）は NG にせず一覧に「注意」で出す（終了時のリークの報告は数えない）。NG は最後に1回流し直す（`--retry`）
- かかった時間は `godot/.godot/test_times.json` に覚えて、次の並び順と時間制限（見込みの4倍、最低3分）に使う
- 組の中身は冒頭の `QUICK`（速い組）・`VARIANTS`（軽い版）。新しい `*_check.gd` は自動で full に入る
