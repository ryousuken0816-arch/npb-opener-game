extends SceneTree
## 数シーズン進めたときのメモリの量（docs/AUTORUN.md 作業74。ヘッドレス、約5分）。
## iPhone SE2（3GB）の Web 版でドラフトに入ると落ちて進めない件の調べ。Web 版のまね（NPB_SIM_WEB=1）・スマホの縦で、
## ハブを開いたまま可変ボタンと同じ GameState.advance() で月ごとに進め（月ごとにオートセーブと同じ保存もする）、
## オフはドラフトの画面で入札（外れ1位が起きるよう CPU の入札が最も多い候補）→ 演出を「次へ」で1つずつ → 自球団の番まで飛ばす → 選択終了。
## 段階ごとに、いまのメモリ（OS.get_static_memory_usage）と、それまでの最大（get_static_memory_peak_usage。Web の WASM のヒープは
## 一度増えると戻らないので、こちらが端末で効く）を出す。ドラフトの間は毎フレーム測って、ドラフトの中の最大も出す。
## 1年目の6月のあとに、記録室の歴代メンバー（野手・投手）・歴代ドラフトで年を全部見る → 閉じる → 采配の投手1軍登録を開く（作業75。
## iPhone SE2 で「歴代データを見たあとに投手の1軍登録を開いたら落ちた」件）。
## 最後に「ふだん（1年目の6月）・歴代 → 登録・ドラフト中の最大・3シーズン後」の表。Web 用のデータ（godot/data/）を置いて測ること。
## 「字の画像」は字の画像の覚え（UiTheme.glyph_bytes。新しい字ごとに増える）。
## 軽量モード（作業75）は、シェルで環境変数 NPB_LITE=1（オン）／0（オフ）を付けて起動する（付けなければオフ）。
##
##   godot --headless --path godot -s res://tests/memory_season_check.gd -- [シーズン数] [開始年] [上限MB]
##   （既定は 3 シーズン・2008年。上限MB を渡すと、全体の最大がそれを超えたら NG）

const PORTRAIT := Vector2i(390, 844)
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "福岡ソフトバンクホークス"
const MB := 1048576.0

var _gs: Node
var _ds: GDScript
var _hub: Node
var _seasons := 3
var _start_year := 2008
var _limit_mb := 0.0
var _draft_peak := 0
var _rows: Array[String] = []
var _summary := {}


func _initialize() -> void:
	OS.set_environment("NPB_SIM_WEB", "1")
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_seasons = int(args[0])
	if args.size() > 1 and not args[1].is_empty():
		_start_year = int(args[1])
	if args.size() > 2 and not args[2].is_empty():
		_limit_mb = float(args[2])
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_ds = load("res://sim/draft.gd")
	_ds.lottery_seed = 3
	root.get_node("UiLayout").set_force_mode("mobile")
	root.size = PORTRAIT
	await _frames(4)
	_note("起動直後")
	_gs.new_game(TEAM, _start_year)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	await _settle()
	_note("新しいゲーム・ハブ")
	for i in _seasons:
		await _play_season(i)
	print("\n%-34s %10s %10s %10s" % ["段階", "いま(MB)", "最大(MB)", "字の画像(MB)"])
	for r in _rows:
		print(r)
	var peak := OS.get_static_memory_peak_usage() / MB
	print("\n== まとめ ==")
	print("ふだん（1年目の6月末）: %.1fMB" % _summary.get("normal", 0.0))
	print("歴代 → 登録の最大（毎フレーム）: %.1fMB（その段の前 %.1fMB・閉じたあと %.1fMB・そこまでのヒープの山 %.1fMB）" % [
		_summary.get("history_peak", 0.0), _summary.get("normal", 0.0), _summary.get("history_after", 0.0),
		_summary.get("history_heap", 0.0)])
	print("ドラフト中の最大（毎フレーム）: %.1fMB" % (_draft_peak / MB))
	print("%dシーズン後: %.1fMB" % [_seasons, _summary.get("after", 0.0)])
	print("全体の最大（ヒープの山）: %.1fMB" % peak)
	var ok := _limit_mb <= 0.0 or peak <= _limit_mb
	print("\n== 結果: %s ==" % ("ALL OK" if ok else "FAILED（最大 %.1fMB が上限 %.1fMB を超えた）" % [peak, _limit_mb]))
	quit(0 if ok else 1)


func _play_season(index: int) -> void:
	var year: int = _gs.year
	var guard := 0
	while _gs.phase == _gs.Phase.SEASON and guard < 20:
		guard += 1
		var month_text: String = _gs.month_text()
		_gs.advance()
		await _settle()
		_save()
		_note("%d年 %s まで" % [year, month_text])
		if index == 0 and month_text.contains("6"):
			_summary["normal"] = OS.get_static_memory_usage() / MB
			await _history_stage()
	guard = 0
	while _gs.phase != _gs.Phase.DRAFT and _gs.phase != _gs.Phase.SEASON and guard < 30:
		guard += 1
		_gs.advance()
		await _settle()
		_note("%d年 %s" % [year, _gs.phase_name()])
	if _gs.phase == _gs.Phase.DRAFT:
		_save()
		_note("%d年 ドラフトの前（セーブ）" % year)
		await _play_draft(year)
	guard = 0
	while _gs.phase != _gs.Phase.SEASON and guard < 30:
		guard += 1
		_gs.advance()
		await _settle()
	_note("%d年 開幕" % (year + 1))
	_summary["after"] = OS.get_static_memory_usage() / MB


## 記録室の歴代メンバー（野手・投手）・歴代ドラフトで年を全部見る → 閉じる → 采配の投手1軍登録（作業75）
func _history_stage() -> void:
	_draft_peak = 0
	_hub.call("_open_sub_screen", "records")
	await _sample(3)
	var view: Node = _hub.get("_records_view")
	var rh: GDScript = load("res://scenes/hub/records_history.gd")
	view.call("set_tab", "members")
	for y: int in rh.member_years():
		for pitch: bool in [false, true]:
			view.set("_mem_year", y)
			view.set("_mem_pitch", pitch)
			view.call("refresh")
			await _sample(1)
	view.call("set_tab", "drafts")
	for y: int in rh.draft_years():
		view.set("_dr_year", y)
		view.call("refresh")
		await _sample(1)
	_note("歴代メンバー%d年・歴代ドラフト%d年を見る" % [rh.member_years().size(), rh.draft_years().size()])
	_hub.call("_close_sub_screen")
	await _sample(3)
	_note("記録室を閉じる")
	_summary["history_after"] = OS.get_static_memory_usage() / MB
	_hub.call("_open_sub_screen", "tactics")
	await _sample(3)
	_hub.get("_tactics_view").call("_show_page", "pitchers", true)
	await _sample(3)
	_note("采配の投手1軍登録")
	_hub.get("_tactics_view").call("_show_page", "")
	_hub.call("_close_sub_screen")
	await _settle()
	_summary["history_peak"] = _draft_peak / MB
	_summary["history_heap"] = OS.get_static_memory_peak_usage() / MB
	_draft_peak = 0


func _play_draft(year: int) -> void:
	_hub.call("_open_sub_screen", "draft")
	await _sample(4)
	_note("%d年 ドラフトを開く" % year)
	var view: Node = _hub.get("_draft_view")
	var d: RefCounted = _gs.draft()
	var me: String = _gs.team
	await _walk_overlays(view)
	var guard := 0
	while d.stage == _ds.Stage["FIRST"] and guard < 12:
		guard += 1
		if d.first_pick_of(me).is_empty():
			var target := _most_bid(d)
			if view.call("selected_id") != target:
				view.call("select_candidate", target)
			await _sample(2)
			(view.call("notebook") as Control).emit_signal("go_pressed")
		else:
			view.call("_continue_first")
		await _walk_overlays(view)
		await _sample(2)
	_note("%d年 ドラフト 1位まで（入札%d回）" % [year, d.wave - 1])
	guard = 0
	var picked := 0
	while d.stage != _ds.Stage["DONE"] and guard < 300:
		guard += 1
		if d.is_user_turn():
			if picked < 4 and d.stage == _ds.Stage["WAIVER"]:
				view.call("set_filter", "left")
				(view.call("notebook") as Control).emit_signal("go_pressed")
				picked += 1
			else:
				view.call("_on_finish_pressed")
		else:
			view.call("_on_skip_pressed")
		await _walk_overlays(view)
		await _sample(1)
	_note("%d年 ドラフトの終わり" % year)
	_hub.call("_close_sub_screen")
	await _settle()
	_note("%d年 ドラフトを閉じる" % year)


func _walk_overlays(view: Node) -> void:
	var guard := 0
	while view.call("overlay_visible") and guard < 400:
		guard += 1
		(view.get("_overlay_next") as Button).pressed.emit()
		await _sample(2)


func _most_bid(d: RefCounted) -> String:
	var count := {}
	var bids: Dictionary = d.cpu_first_bids()
	for t: String in bids:
		count[bids[t]] = int(count.get(bids[t], 0)) + 1
	var best := ""
	for c: Dictionary in d.remaining():
		if best.is_empty() or int(count.get(c["id"], 0)) > int(count.get(best, 0)):
			best = c["id"]
	return best


## オートセーブと同じ保存（テストの保存先）
func _save() -> void:
	var sg: GDScript = load("res://scripts/save_game.gd")
	var error: String = sg.save("auto")
	if not error.is_empty():
		print("  （保存できない：%s）" % error)


func _note(label: String) -> void:
	_rows.append("%-34s %10.1f %10.1f %10.1f" % [label, OS.get_static_memory_usage() / MB,
		OS.get_static_memory_peak_usage() / MB, load("res://scripts/ui_theme.gd").glyph_bytes() / MB])


## n フレーム進めながらドラフト中のメモリを測る
func _sample(n: int) -> void:
	for i in n:
		await process_frame
		_draft_peak = maxi(_draft_peak, OS.get_static_memory_usage())


func _settle() -> void:
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
