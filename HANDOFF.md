# 引き継ぎメモ（クラウドセッション向け）

仕様は [docs/SPEC.md](docs/SPEC.md)。設計は確定済み。ユーザーは日本語で会話する。

## 役割分担（push衝突を避けるため）

- **ローカルセッション**：npb.jp のスクレイピングと `data/` 以下の更新のみ。全年（2008〜2026）の収集が進行中で、完了次第 `data/<年>/` を追加でpushする
- **クラウドセッション**：コード（能力値算出・Godot）。`data/` は読み取り専用として扱う
- クラウド環境から npb.jp へは接続できない前提で進める（必要データはローカル側に依頼）

## データ（現在は `data/2008/` のみ）

| ファイル | 中身 |
|---|---|
| rosters.json | その年の在籍選手。`player_id`(8桁, npb.jp の選手ID)・name・team・debut_year |
| players.json | `{player_id: {...}}`。throws/bats/height/weight/birth、bio(経歴・ドラフト 例:"2000年ドラフト1位")、batting/pitching = **1軍の年度別成績（2008年より前も含む通算）** |
| teamstats_linked.json | 球団別 個人成績。`level` 1=1軍 2=2軍、`kind` b=打撃 p=投手 f=守備(pos別: 刺殺・補殺・失策・併殺・捕逸)。`player_id` で突合済み（2軍のみの選手は null） |
| awards.json | ゴールデングラブ賞（player_id付き） |
| drafts.json | 前年秋(2007)と当年秋(2008)のドラフト指名。名前・順位・ポジション・出身校。**player_idなし**（名前で突合が必要） |

補足:
- 投球回は `outs`（アウト数）に変換済み。IP = outs/3
- 選手ページ打撃の列：試合 打席 打数 得点 安打 二塁打 三塁打 本塁打 塁打 打点 盗塁 盗塁刺 犠打 犠飛 四球 死球 三振 併殺打 打率 長打率 出塁率
- 選手ページ投手の列：登板 勝利 敗北 セーブ H HP 完投 完封勝 無四球 勝率 打者 outs 安打 本塁打 四球 死球 三振 暴投 ボーク 失点 自責点 防御率
- 2軍成績は teamstats_linked.json にのみ存在（選手ページは1軍のみ）

## 全年データ（2008〜2026）

- `data/<年>/`（2008〜2026）：rosters / players / teamstats_linked / awards / drafts の5ファイル。形式は data/2008 と同じ
  - **1軍成績は全年・全員 player_id 突合済み**（未突合0）。2軍のみの選手は player_id が null
  - drafts.json は「前年秋＋当年秋」の2回分（例: 2015/ は 2014年・2015年ドラフト）
  - **2026年はシーズン途中（9/25時点）の成績**。awards なし、当年秋ドラフト未実施
  - 2026年の rosters.json は現役選手名簿から作成しており、`number`（背番号）・`pos`・`ikusei`（育成）が付く。2025年以前には無い
  - 2025年以降、npb.jp の成績表の形式が変わったがパーサで吸収済み（出力形式は同じ）

## 史実の年間日程（ユーザー決定 2026-09-25：日程は自動生成せず史実を使う）

- `data/<年>/schedule.json`：npb.jp の日ごとの試合結果ページから取得した**公式戦のみ**の日程（CS・日本シリーズ・オールスター・アジアシリーズは除外）
  - 項目: date, kind（central / pacific / interleague）, home, away, venue, game_no（N回戦）, status（played / canceled）, home_score, away_score
  - **先に書かれている球団がホーム**。球団名は npb.jp の略称（読売, 阪神, 東京ヤクルト, 広島東洋, 横浜, 北海道日本ハム, 福岡ソフトバンク, 東北楽天, 埼玉西武, 千葉ロッテ, オリックス, 中日 など）。ratings の正式名とは別なので対応表が必要
  - 使い方：**status=played の試合を日付順にシミュレーション**する（雨天中止の振替は別の日付に played として入っているので、自然に史実どおりの日程になる）。canceled は日程表で「中止」表示に使える
  - スコアは史実の参考値。ゲームでは使わない（試合はシミュレーションする）
  - 2008年で検証済み：12球団すべて144試合、交流戦144試合
  - 取得スクリプト `npb_collector/schedule.py`。**2009〜2025年は取得中**、2026年は npb.jp のページ構成が違うため未対応

## ドラフト1巡目の競合データ

- `data/draft_first_round.json`：2001〜2025年の1位（1巡目）指名選手ごとに、1回目の入札で指名した球団数 `bids`（1=単独、2以上=競合）・`bidders`・確定した入札の回 `wave`（2以上=外れ1位）
  - 2022年までは npb.jp 指名一覧の注記から、2023〜2025年はウィキペディアの情報欄から（`source: "wikipedia"`、単独の外れ1位は wave が分からず 1）
  - 用途：ドラフト候補一覧の「当時の評価」ランク（docs/references/README.md「draft_list_pawapuro.webp」参照）
  - 取得スクリプト `npb_collector/draft_lottery.py`、手動補足 `npb_collector/draft_lottery_manual.json`

## 追加データ（2008年開幕時点の算出用）

- `data/2005/` `data/2006/` `data/2007/`：rosters.json・teamstats_linked.json（1軍・2軍・守備、1軍は全員player_id突合済み）・awards.json（GG賞。**2005年は0件**＝ページ構造が違い未取得）。players.json は無し（2008年以降の選手の2007年以前の1軍成績は各年の players.json の batting/pitching に含まれる）
- `data/drafts_2001-2007.json`：2001〜2007年ドラフト（2000年はページなし）。形式は drafts.json と同じ

## 既知の課題

1. **捕手の盗塁阻止率が npb.jp の守備成績にない**。肩力(捕手)の代替指標を決める必要あり（ユーザーと相談）
2. **1軍出場のない選手には player_id がない**（2008年2軍で67人、未出場のドラフト指名選手も同様）。ゲーム用に仮ID（名前+球団+指名年など）を振る
3. 表彰はゴールデングラブ賞のみ。MVP・ベストナインは未取得（タイトルは成績から算出可能）
4. 名前突合の手動補正は `npb_collector/overrides.json`

## 次にやること

1. ~~能力値算出スクリプト~~ → `tools/compute_ratings.py`（出力 `generated/ratings/<年>_<pre|post>.json`、仕様は tools/README.md）。新しい年の data を追加したら `--year <年> --phase pre/post` で再生成
2. ~~能力値の要相談事項~~ 決定済み（tools/README.md「決定済み」）。2005〜2007年のチーム成績・表彰は取得済み（data/2005〜2007、上記「追加データ」）。compute_ratings.py の fallbacks を解消する
3. ~~Godot プロジェクトの骨組み（ハブ画面）~~ → `godot/`（構成は godot/README.md）。タイトル（球団選択）→ ハブ画面（可変ボタン・メニュー・自球団の選手一覧）。
   ローカルの Godot 4.7.2 で起動確認済み（エラーなし、2011年まで進行OK）。**ユーザーは Godot 4.7 を使用**。クラウドでも Godot 4.7 を GitHub Releases から取得して xvfb で起動・スクショ確認できる（godot/README.md「メモ」）
3.5 ~~球速（投手）と弾道（野手）を能力値に追加する~~ → 完了（2026-09-25）。`tools/compute_ratings.py` に実装済み
   - **球速**：`data/velocity.json` の実測 km/h をMarcel加重平均。実データ不足時は「最古の実測値を年数差ぶん減算」または「K/9からの単回帰」で代用（`source: observed/early_career/estimated`）。定数は `VELOCITY_*`（スクリプト冒頭）
   - **弾道**：ISO・HR/打数の z 値から 1〜4 を算出。定数は `TRAJECTORY_*`
   - 出力: `pitching.velocity`（`{"kmh":..., "source":...}`）、`batting.trajectory`（1〜4の整数）。schema_version 3。詳細は tools/README.md
   - ついでに直していた既存バグ：`data/2005〜2007/` に players.json・drafts.json が無いため2008年pre生成が落ちる問題を修正（存在確認してスキップ）→ 2008年pre のフォールバック（HANDOFF旧記載）も解消
4. ~~ハブ画面の見た目~~ → パワプロ風に作り直し済み（球団カラーのテーマ、明るい背景、色付きの大きなメニューボタン、説明文・日付・順位表パネル、同梱フォント）。采配 = 選手一覧
4.5 ~~日程表画面（見た目）~~ → `godot/scenes/hub/schedule_view.gd`（ハブから「日程表」で開く）。3日分×全カードのタイル（日ごとにセ・パを左右の列に分けて、スクロールなしで全カード表示）、自球団カードは球団カラーで縁取り、終了済みは暗色＋スコア、月曜は「移動日」、右にセ・パ順位表（`StandingsPanel` 再利用、◀▶切替）、進行バーとスライダー。開いたとき／月を進めたときは現在の月付近の3日間を表示する（`_elapsed_days()` を起点に `_day_offset` を計算）。
   **日程生成・試合シミュレーションは未実装なので、カード・組み合わせ・スコアはすべて仮データ**（総当たりもどきの仮ペアリング、スコアはハッシュ由来の乱数、本拠地名もハードコード）。実装したら差し替えること。
   クラウドで Godot 4.7 を実際に起動しスクショ確認済み（エラーなし）。前回 claude/peaceful-lamport-1mbcsc の `schedule_view.gd` は `GameData.team_color`/`team_text_color`/`stadium_of` という存在しないメソッドを呼んでいて起動できなかった（今回は `GameData.team_colors`（複数形・Array[Color]）や `UiTheme.text_on` など実在するAPIのみ使用）。ほかにハマった点：ScrollContainer は該当方向の scroll_mode を DISABLED にしても子の最小サイズをそのまま親に伝える（=切り詰めない）ので幅がはみ出す／Label は既定で自身のテキスト幅を最小サイズとして要求するので `clip_text = true` にしないと横幅の指定が無視される／チームチップを横並びではなく縦積み（アウェイ→中央→ホーム）にすると1タイルの横幅が半分で済み、セ・パ2列でも収まる
   ローカル（Windows）で `.import` が全件差分になる件は `.gitattributes`（`* text=auto eol=lf`）で解消。既存ファイルは `git add --renormalize .` 済み
4.6 ~~2009年以降の能力値の生成、能力値正規化の見直し~~ → 完了（2026-09-25）。`generated/ratings/` に 2008〜2026年の pre/post 全て生成済み（球速・弾道込み、schema_version 3）。
   正規化のスケールを `55+15z` → `63+17z` に変更（`SCALE_MEAN`/`SCALE_SD`）：母集団が規定打席/規定投球回クリア済みの「そこそこ良い選手」に絞られているため平均をそのままD帯に置くとレギュラーの大半がD以下に沈んでいた問題を修正し、レギュラー級C〜D中心・主力B以上・スターA/Sになるよう調整。
   また1軍・2軍とも登板実績が一切ない投手（新人・新外国人、年50〜120人程度）の球速がnullだったのを、ドラフト順位による加減つきの仮の値（`provisional_velocity`, `source: "provisional"`）で埋めた
4.7 ~~新人（プロの成績がない選手）の能力値~~ → 完了（2026-09-25）。`tools/compute_ratings.py`
   - 少サンプル補正のブレンド先（事前値）を、通常の「母集団の30パーセンタイル目」から
     **ドラフト順位＋出身区分で決めたパーセンタイル目**に変更（`prior_pctl_for`）。
     出身区分は drafts.json の `school` から判定（`draft_category`：〜高＝高校／大を含む＝大学／それ以外＝社会人・独立リーグ等）。
     社会人は即戦力寄り（高め）、高校生は低め、大学生は中間、育成指名はさらに低め。
     ドラフト情報が見つからない選手（主に外国人新加入）は既定値（`ROOKIE_IMPORT_PCTL`）。定数は `ROOKIE_*`
   - 2軍成績が出れば既存の少サンプル補正の重み `w = min(1, サンプル/FULL)` がそのまま効いて実績側に寄っていく（追加実装なし）
   - 投手は1軍・2軍とも成績が一切なくても `pitching(..., force=True)` で（全指標が上記の初期値だけの）能力値を必ず生成するようにし、`is_pitcher` な選手の `pitching` が null になることは無くなった（球速も同様に null 無し）
   - 確認済み：2008 pre で新人（古川祐樹＝大学3位、赤坂和幸＝高校1位など）に能力値が入り指名順位・出身で差がつく、全年 pre/post で投手の `pitching`/`ratings`/`velocity` が null の選手が0人
   - generated/ratings/ の2008〜2026年 pre/post を全て再生成（schema_versionは3のまま、フォーマット変更なし）
5. 次の候補（どれから進めるかユーザーと相談）
   - 選手詳細画面（概要／成績／経歴／契約の4タブ。実数値は ratings の `detail`。球速・弾道もここに表示）… Sonnet 向き
   - セーブ/ロード（`GameState` の内容を user:// に保存）… Sonnet 向き
   - （試合シミュレーション＋日程生成は別セッションが着手中。godot/ は触らないこと）
