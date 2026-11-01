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
- ドラフト `draft_view.gd`・`scout_view.gd`・`godot/scenes/draft/`（担当J。そのあとドラフト画面の作り込み）
- **共通の部品**（すべての画面に効く）：`godot/scripts/ui_theme.gd`・`gloss_box.gd`・`name_tag.gd`・`pad_guide.gd`・`team_background.gd`・`ui_fx.gd`

## 整理するときの決まり（上の「守ること」に加えて）

- 情報を減らさない（見せ方・並び・大きさ・余白・色・まとめ方を変える）。操作（コントローラー・キーボード・マウス）はこれまでどおり全部できること
- 1280x720 からはみ出さない。最後に `godot/tests/layout_fit_check.gd` を `--headless` で流して通ること（時間がかかる：10〜30分）
- 変えた画面の既存のテスト（`tactics_check`・`day_progress_check`・`contract_check`・`release_check`・`trade_check` など、`godot/tests/` の該当するもの）も1回だけ流す
- 第1段階のブランチは `antigravity/ui-tidy-1`。main に入れる前に main を取り込む
