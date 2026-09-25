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
3.5 **球速（投手）と弾道（野手）を能力値に追加する**（ユーザー決定 2026-09-25）… Opus 向き（式の設計）
   - **球速は実データあり**：`data/velocity.json`（baseballdata.jp の「最速」、**2011〜2026年**の1軍投手 5,403行、全行 player_id 突合済み）。項目: year, league, name, team, max_kmh, games, player_id
     - シーズン途中の移籍投手は同じ年に2行ある（30件）→ その年の **max_kmh の最大値** を使う
     - 2008〜2010年はサイトに無い。方針：①その投手の2011年以降で最も古い値を使う（若手は少し下げる）②実データが一切ない投手（〜2010年引退・1軍未登板）は、実データのある投手で K/9 等→球速 の回帰を作って推定
     - 収集スクリプトは `npb_collector/velocity.py`、手動補正は `npb_collector/velocity_overrides.json`（サイト側に選手名の取り違えがあるため）
   - **弾道は実データなし**：HR/打数・ISO から推定（1〜4）。係数は定数化して後で調整できるように
   - 画面の参考画像は docs/references/（ハブ・日程表・1軍登録・オーダー・選手詳細・采配メニュー・トレード）。現SPECに無い要素（調子・疲労・変化球図）は一旦保留
4. ~~ハブ画面の見た目~~ → パワプロ風に作り直し済み（球団カラーのテーマ、明るい背景、色付きの大きなメニューボタン、説明文・日付・順位表パネル、同梱フォント）。采配 = 選手一覧
4.5 ~~日程表画面（見た目）~~ → `godot/scenes/hub/schedule_view.gd`（ハブから「日程表」で開く）。3日分×全カードのタイル、自球団カードは球団カラーで縁取り、終了済みは暗色＋スコア、月曜は「移動日」、右にセ・パ順位表（`StandingsPanel` 再利用、◀▶切替）、進行バーとスライダー。
   **日程生成・試合シミュレーションは未実装なので、カード・組み合わせ・スコアはすべて仮データ**（総当たりもどきの仮ペアリング、スコアはハッシュ由来の乱数、本拠地名もハードコード）。実装したら差し替えること。
   クラウドで Godot 4.7 を実際に起動しスクショ確認済み（エラーなし）。前回 claude/peaceful-lamport-1mbcsc の `schedule_view.gd` は `GameData.team_color`/`team_text_color`/`stadium_of` という存在しないメソッドを呼んでいて起動できなかった（今回は `GameData.team_colors`（複数形・Array[Color]）や `UiTheme.text_on` など実在するAPIのみ使用）。ほかにハマった点：ScrollContainer は該当方向の scroll_mode を DISABLED にしても子の最小サイズをそのまま親に伝える（=切り詰めない）ので幅がはみ出す／Label は既定で自身のテキスト幅を最小サイズとして要求するので `clip_text = true` にしないと横幅の指定が無視される
5. 次の候補（どれから進めるかユーザーと相談）
   - 2009年以降の能力値の生成（data/2008〜2026 が揃ったので `tools/compute_ratings.py --year <年>`。クラウドの generated/ratings は 2008 のみ）… Sonnet 向き
   - 選手詳細画面（概要／成績／経歴／契約の4タブ。実数値は ratings の `detail`）… Sonnet 向き
   - 試合シミュレーション（打席単位、docs/SPEC.md の8段階）＋ 日程生成 … Opus 向き
   - セーブ/ロード（`GameState` の内容を user:// に保存）… Sonnet 向き
