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
