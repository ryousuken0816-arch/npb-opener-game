# Antigravity でドラフト画面を作り込むときの決まり

ユーザーが Antigravity に、ドラフト画面の見た目を実際のドラフト会議の中継に近づけてもらうためのメモ。最初に `CLAUDE.md`・`HANDOFF.md`（ドラフト画面・3D抽選・中継風の発表の節）・`godot/README.md` を読むこと。

## 編集してよいファイル（許可してよい範囲）

- `godot/scenes/draft/` の中のすべて（`lottery_3d.gd`・`lottery_3d.tscn`・`pick_announce.gd`）。新しいファイルを作ってもよい
- `godot/scenes/hub/draft_view.gd`（ドラフト画面の本体）
- `godot/scripts/draft_voice.gd`（読み上げ）
- `godot/assets/draft/`（新しく作ってよい。自分で作った画像・効果音だけ）
- ドラフトのテスト：`godot/tests/draft_check.gd`・`draft_rebid_check.gd`・`draft_announce_check.gd`・`draft_balance_check.gd`・`lottery_3d_check.gd`・`draft_2026_capture.gd`。新しいテスト `godot/tests/draft_*.gd` を足してもよい
- 記録：`HANDOFF.md`・`docs/AUTORUN.md`（追記だけ。ほかの人の書いた行は消さない）

## 読むだけ（変えたいときはユーザー経由で相談）

- `godot/sim/draft.gd`（入札・抽選・ウェーバーなどの進行のルール）・`godot/sim/fictional_draft.gd`（架空の候補）
- `godot/autoload/`・`godot/scripts/ui_theme.gd` など共通の部品
- `data/`・`generated/`・`tools/`・`npb_collector/`（データ。触らない）

## 実行してよいコマンド

- `git status` / `git diff` / `git log` / `git fetch` / `git pull` / `git add` / `git commit` / `git switch -c antigravity/<名前>` / `git push origin antigravity/<名前>`
- Godot のテスト（必ず `--headless` と `timeout` を付ける）：
  `timeout 900 "C:/Users/user/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path godot -s res://tests/draft_check.gd`

## 守ること

- 作業は `antigravity/<名前>` のブランチで行い、終わったら main を取り込んでからドラフトのテストを流し、main に入れる（または入れる前にユーザーに伝える）
- **Godot のウィンドウを前面に出さない・マウスカーソルを動かさない**（ユーザーは同じ PC で作業している）。スクショが必要なときだけ、画面の右下の隅に `--position` で小さく置き、起動直後に `DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)` を立てて1回だけ撮る
- テストは最後に1回だけ流す（何度も繰り返さない）
- 動画から切り出した画像・音声、実在の球団ロゴ・スポンサーの表示・実在の人物の顔は、リポジトリに入れない（見た目を参考に作り直すのはよい）
- 抽選の結果・指名の順番などの進行は変えない（見せ方だけを変える）。結果がこれまでと同じことはドラフトのテストで確かめる
- 始める前と終わったあとに、ユーザーに一言伝える（Claude の作業セッションとぶつからないように順番を合わせるため）

---

# 全体の UI の整理（2026-11-01 追加）

ユーザーの希望：全体的に UI が見やすいように画面を整理したい。Claude の作業セッションがまだいくつかの画面を作っている最中なので、**2段階**で進める。

## 第1段階：今すぐ触ってよい画面（Claude のセッションが触っていない）

- タイトル：`godot/scenes/title/title.gd`
- 日程表と順位表：`godot/scenes/hub/schedule_view.gd`・`standings_panel.gd`
- 采配：`tactics_view.gd`・`order_page.gd`・`register_page.gd`・`info_page.gd`・`roster_view.gd`
- オフの画面：`contract_view.gd`（契約更改）・`release_view.gd`（戦力外）・`trade_view.gd`（トレード）・`awards_view.gd`（表彰）・`postseason_view.gd`・`celebration.gd`（CS・日本シリーズ・優勝）
- ハブのメニューのボタン：`hub_menu_button.gd`

## 第2段階：Claude のセッションが終わってから（司令塔が「入ってよい」と伝えるまで触らない）

- ハブ本体 `hub.gd`、ニュース `news_view.gd`・`news_ticker.gd`、セーブ・設定 `save_view.gd`・`game_settings.gd`・`user_settings.gd`（担当H）
- 記録室 `records_view.gd`、選手詳細 `godot/scenes/player_detail/`（担当B2）
- FA `fa_view.gd`・`comp_view.gd`（担当I）
- ドラフト `draft_view.gd`・`draft_meeting_view.gd`（作戦会議・有識者の予想。担当Jが作業37・38で追加）・`scout_view.gd`・`godot/scenes/draft/`（担当J。そのあとドラフト画面の作り込み）
  - `draft_view.gd` に担当Jが足したもの（見た目は変えてよいが、働きは残す）：一覧の左端の印（◎○△☆✕）、絞り込み「目星だけ」、列「予想」、要約の「作戦会議：…」の1行、
    入札・指名の番におすすめを選んでおく `_preselect`、開幕の演出の「有識者3人の1位予想」`_experts_grid`。テストは `godot/tests/draft_meeting_check.gd`
- **共通の部品**（すべての画面に効く）：`godot/scripts/ui_theme.gd`・`gloss_box.gd`・`name_tag.gd`・`pad_guide.gd`・`team_background.gd`・`ui_fx.gd`

## 整理するときの決まり（上の「守ること」に加えて）

- 情報を減らさない（見せ方・並び・大きさ・余白・色・まとめ方を変える）。操作（コントローラー・キーボード・マウス）はこれまでどおり全部できること
- 1280x720 からはみ出さない。最後に `godot/tests/layout_fit_check.gd` を `--headless` で流して通ること（時間がかかる：10〜30分）
- 変えた画面の既存のテスト（`tactics_check`・`day_progress_check`・`contract_check`・`release_check`・`trade_check` など、`godot/tests/` の該当するもの）も1回だけ流す
- 第1段階のブランチは `antigravity/ui-tidy-1`。main に入れる前に main を取り込む


---

# Claude が止まったときの引き継ぎ（2026-11-01）

ユーザーの Claude の使用量が上限に近い。Claude（司令塔と作業セッション）が止まったら、**Antigravity がこのファイルを見て続きを進める**。

## Claude が途中だった作業（止まっていたら、ここから続ける）

それぞれ Claude の作業セッションが「テストして main に入れる」途中だった。`git log origin/main` で入ったか確かめ、入っていなければ次の手順で自分で入れる。

| 作業 | ブランチ（ローカル） | すること |
|---|---|---|
| 作業41 メジャー移籍と帰国（Antigravity 作） | `antigravity/mlb-moves`（`5fb2180`） | origin/main を取り込み → 関係テスト（mlb_future_check・roster_year_check・fa_check・fa_comp_check・future_year_check・growth_check・foreign_check・save_check・news_check・start_year_check）→ main へ |
| アマのニュースの作り直し（Codex 作） | `antigravity/amateur-news-text`（`d6ac0db`） | origin/main を取り込み → news_check・news_stop_check・fictional_draft_check・draft_check・save_check・history_check → main へ |
| 作業42 ドラフトの外れ1位の発表でフリーズ（最優先の不具合） | Claude の担当L の `claude/lane-l-draft-freeze-*`（`git branch -a` で探す） | 途中なら docs/AUTORUN.md の作業42 を読んで続きを直す。読み上げオン・オフ両方で、2020年のように外れ1位が続く年を最後まで進められるかテスト |

main に入れたら `docs/AUTORUN.md` の表を「完了」にし、`HANDOFF.md` に数行書く。

## 次にやる作業（おすすめの順）

1. **作業42**（上。ドラフトのフリーズ。最優先）
2. **作業40** シーズン中に能力を史実へ寄せる＋直近の年を重く（佐藤輝明が弱い件）。docs/AUTORUN.md の作業40
3. **作業43** 中堅の守備に走力・昔の年の外野の守備力に走力（docs/AUTORUN.md の作業43）
4. **CPU の自動オーダーの守備位置の選び方**（近藤・筒香が中堅、清宮が二塁など。`godot/sim/sim_team.gd` の自動編成）と**試合での守備の効き方**（近藤が肩だけで+15.7）。根拠は `docs/reports/ratings_audit.md`
5. **ドラフト画面の見た目の作り込み**（上の「Antigravity でドラフト画面を作り込むとき」。作業42のあと）
6. **UI 整理の第2段階**（上の「全体の UI の整理」の第2段階。Claude の担当はもう動いていないので、全部触ってよい。共通の部品を変えたら `layout_fit_check` を必ず流す）
7. 新しい機能（ユーザーと相談して順番を決める）：故障・好不調／試合結果画面／育成と春季キャンプ／2軍の試合／現役ドラフト（2022年オフ〜。オフの段階だけあって中身が空）

## Claude がいないときの進め方

- 1つの作業ごとにブランチ（`antigravity/<名前>`）を作る → 実装 → 関係するテストを `--headless` で → origin/main を取り込み直す → main にマージして push → `docs/AUTORUN.md`（表と詳細）と `HANDOFF.md` を更新
- 画面を作ったら、`CLAUDE.md` の「完成の条件」どおり Godot を起動してエラー0件とスクショ（右下の隅、フォーカスを奪わず1回だけ）、ゲーム内の日付を進めて表示が追従するか確かめる
- 新しいワークツリー・フォルダでテストする前は `--headless --path godot --import` で準備する
- テストは同時に流さない（セーブの枠がぶつかる）。`draft_check` の「2025年に指名選手が試合に出た」と `fa_comp_check` の長野の件は、乱数しだいで落ちる既知の件
- ユーザーは遊ぶとき `C:/Users/user/Desktop/npb-opener-game-play/play_latest.bat`（main の最新で起動）を使う。デスクトップの `npb-opener-game` が作業中のブランチでも遊べる
