extends SceneTree
## ドラフトの外れ1位で進行が止まらないかの確認（docs/AUTORUN.md 作業12。ヘッドレス可、約1分）。
## 不具合：自球団の1位が決まったあと CPU球団にだけ外れが残ると、画面の入札のボタンがすべて押せず「おまかせ」でしか進めなかった。
## CPU球団に外れが出やすい年（2012年 藤浪・東浜、2019年 佐々木）で、自球団が
##   単独で確定／競合して当選／競合して外れ（外れ1位を画面で入札）
## の3通りを、画面の操作（入札する・演出の「次へ」・自球団の番まで飛ばす・選択終了）だけで進める。おまかせは使わない。
## 抽選は乱数なので、入札の直前の状態に戻して乱数を変え、狙った結果が出るまでくり返す。
## 最後の通りはドラフトの終わりまで進め、オフの残り（作業54：FA・現役ドラフト）を進めて翌年の春季キャンプでハブの年が追従するかも調べる。
##
##   godot --headless --path godot -s res://tests/draft_rebid_check.gd -- [出力先]
##   （出力先はウィンドウ付きのときだけ。CPU球団の外れ1位の結果の演出と、2019年の候補一覧（表の投手能力）をスクショ）

const CASES := [
	{"year": 2012, "team": "阪神タイガース"},
	{"year": 2019, "team": "千葉ロッテマリーンズ"},
]
## 狙った抽選の結果が出るまでのくり返しの上限
const MAX_TRIES := 16

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _dv: GDScript
var _first := 0
var _waiver := 1
var _done := 3
var _shot_taken := false


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_ds.lottery_seed = 1  # 抽選の当たりはテストのときだけ決めた種で引く（作業58。本番はその場で引く）
	_dv = load("res://scenes/hub/draft_view.gd")
	_first = _ds.Stage["FIRST"]
	_waiver = _ds.Stage["WAIVER"]
	_done = _ds.Stage["DONE"]
	_check_live_lottery()
	for c: Dictionary in CASES:
		await _check_year(c["year"], c["team"])
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


## 作業58：抽選の当たりだけはその場で引く。同じ状態（セーブ）から何度やり直しても CPU の1位の入札は同じで、
## 抽選の当たりは変わることがある。テストの種（lottery_seed）を決めれば同じ当たりになる
func _check_live_lottery() -> void:
	print("\n== 抽選はその場で引く（2024年 巨人・宗山塁） ==")
	_gs.new_game("読売ジャイアンツ", 2024)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d0: RefCounted = _gs.draft()
	var mune := ""
	for c: Dictionary in d0.candidates:
		if c["name"] == "宗山 塁":
			mune = c["id"]
	var snap: Dictionary = JSON.parse_string(JSON.stringify(d0.to_save()))
	var bids_seen := {}
	var winners := {}
	_ds.lottery_seed = -1
	for i in 16:
		var d: RefCounted = _ds.from_save(JSON.parse_string(JSON.stringify(snap)))
		d.user_bid(mune)
		bids_seen[JSON.stringify(d.cpu_first_bids())] = true
		d.run_first_wave()
		winners[str(d.by_id[mune]["picked_by"])] = true
	_check(bids_seen.size() == 1, "同じ状態から16回やり直しても CPU の1位の入札は同じ（%d通り）" % bids_seen.size())
	_check(winners.size() >= 2, "抽選の当たりはその場で引くので変わる（宗山の当たり %d通り：%s）" % [winners.size(),
		", ".join(winners.keys().map(func(t: String) -> String: return _gd.short_name(t)))])
	var fixed := {}
	_ds.lottery_seed = 7
	for i in 4:
		var d: RefCounted = _ds.from_save(JSON.parse_string(JSON.stringify(snap)))
		d.user_bid(mune)
		d.run_first_wave()
		fixed[str(d.by_id[mune]["picked_by"])] = true
	_check(fixed.size() == 1, "テストの種を決めれば当たりは同じ（%s）" % ", ".join(fixed.keys()))
	_ds.lottery_seed = 1


func _check_year(year: int, team: String) -> void:
	print("\n== %d年 %s ==" % [year, _gd.short_name(team)])
	_gs.new_game(team, year)
	var ok: bool = _gs.skip_to_phase(_gs.Phase.DRAFT)
	_check(ok and _gs.draft() != null, "%d年オフのドラフトに飛べる" % year)
	if _gs.draft() == null:
		return
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	# 入札の直前の状態（ここへ戻して3通りを試す）
	var snap: Dictionary = _gs.draft().to_save().duplicate(true)
	var cpu_losers := 0
	var cases: Array[String] = ["single", "win", "lose"]
	for kind: String in cases:
		var last: bool = kind == cases[-1]
		var result := {}
		for i in MAX_TRIES:
			_gs.league.draft = _ds.from_save(snap.duplicate(true))
			_gs.draft().get("_rng").seed = hash("%d-%s-%d" % [year, kind, i])
			_ds.lottery_seed = absi(hash("lottery-%d-%s-%d" % [year, kind, i]))
			result = await _play_first(hub, kind)
			result["tries"] = i + 1
			if result["kind"] == kind:
				break
		_check(result["kind"] == kind, "%d年：自球団が「%s」になる（%d回目で%s）" % [year, _kind_text(kind),
			result.get("tries", 0), _kind_text(result["kind"])])
		if result["kind"] != kind:
			continue
		var d: RefCounted = _gs.draft()
		cpu_losers += result["cpu_losers"]
		_check(result["stuck"] == "" and d.stage == _waiver and d.teams_without_first().is_empty(),
			"%d年 %s：おまかせを使わずに全球団の1位が決まりウェーバーへ（自球団の1位：%s、入札%d回、CPUの外れ%d、自球団が決まったあとの外れ1位%d回）%s"
			% [year, _kind_text(kind), d.by_id.get(d.first_pick_of(team), {}).get("name", "?"), d.wave - 1,
				result["cpu_losers"], result["after_mine"], result["stuck"]])
		_check(not d.user_auto, "%d年 %s：自球団の入札はおまかせになっていない" % [year, _kind_text(kind)])
		if last:
			await _finish_draft(hub, year, team)
	_check(cpu_losers > 0, "%d年：CPU球団に抽選の外れが出た（のべ%d球団）" % [year, cpu_losers])


## 1位入札を画面で進める。kind は狙う結果（single：CPUの入札が無い候補、win/lose：CPUの入札が最も多い候補）。
## 戻り値 {kind（実際の結果）, cpu_losers, after_mine（自球団が決まったあとの入札の回数）, stuck（止まった理由）}
func _play_first(hub: Node, kind: String) -> Dictionary:
	var d: RefCounted = _gs.draft()
	var me: String = _gs.team
	hub.call("_close_sub_screen")
	await _frames(1)
	hub.call("_open_sub_screen", "draft")
	await _frames(2)
	var view: Node = _find_draft_view(hub)
	view.call("finish_overlays")
	var bids: Dictionary = d.cpu_first_bids()
	var count := {}
	for t: String in bids:
		count[bids[t]] = int(count.get(bids[t], 0)) + 1
	var target := ""
	for c: Dictionary in view.call("sorted_candidates", d):
		if not str(c["picked_by"]).is_empty():
			continue
		var n := int(count.get(c["id"], 0))
		if kind == "single" and n == 0:
			target = c["id"]
			break
		# 当選を狙うときは競合の少ない候補（当たりやすい）、外れを狙うときは競合の多い候補
		var better := n < int(count.get(target, 0)) if kind == "win" else n > int(count.get(target, 0))
		if kind != "single" and n > 0 and (target.is_empty() or better):
			target = c["id"]
	var out := {"kind": "", "cpu_losers": 0, "after_mine": 0, "stuck": ""}
	view.call("select_candidate", target)
	view.call("press_action")
	await _frames(2)
	var mine_wave := 0
	var guard := 0
	while d.stage == _first and guard < 200:
		guard += 1
		if not view.call("overlay_visible"):
			if not d.first_pick_of(me).is_empty():
				out["stuck"] = "（%d回目の入札のあと止まった：自球団は決まり、%d球団が未定）" % [
					d.wave - 1, d.teams_without_first().size()]
				break
			# 外れ1位：画面で残りの候補の評価の高い順に入札
			for c: Dictionary in view.call("sorted_candidates", d):
				if str(c["picked_by"]).is_empty():
					view.call("select_candidate", c["id"])
					break
			view.call("press_action")
			await _frames(2)
			continue
		if not _shot_taken and mine_wave > 0 and d.wave - 1 > mine_wave:
			await _shot("rebid_cpu_wave")
		# 演出を1つずつ「次へ」（自球団の1位が決まっていれば、最後の「次へ」で次の入札が自動で締まる）
		view.call("_skip_overlay")
		if mine_wave == 0 and not d.first_pick_of(me).is_empty():
			mine_wave = d.wave - 1
		await _frames(1)
	view.call("finish_overlays")
	if mine_wave > 0:
		out["after_mine"] = d.wave - 1 - mine_wave
	for lot: Dictionary in d.lotteries:
		for t: String in lot["teams"]:
			if t != lot["winner"] and t != me:
				out["cpu_losers"] += 1
	var my_lot := {}
	for lot: Dictionary in d.lotteries:
		if lot["wave"] == 1 and me in lot["teams"]:
			my_lot = lot
	if my_lot.is_empty():
		out["kind"] = "single" if d.by_id[target]["picked_by"] == me else "?"
	else:
		out["kind"] = "win" if my_lot["winner"] == me else "lose"
	return out


## ウェーバー・育成を画面の操作（自球団の番まで飛ばす・指名する・選択終了）で最後まで進め、翌年へ
func _finish_draft(hub: Node, year: int, team: String) -> void:
	var d: RefCounted = _gs.draft()
	var view: Node = _find_draft_view(hub)
	if year == CASES[-1]["year"]:
		# スクショ：表の投手能力のタブを当時の評価の順に並べ、先頭の候補の要約（1年目の列は作業51で消した）
		view.call("set_mode", "table")
		view.call("switch_tab", 1)
		view.call("set_sort", "hyouka", true)
		var top: Array = view.call("list_ids")
		if not top.is_empty():
			view.call("select_candidate", top[0])
		await _shot("first_year_list", true)
	var picked := 0
	var guard := 0
	while d.stage != _done and guard < 200:
		guard += 1
		if d.is_user_turn():
			if picked < 3 and d.stage == _waiver:
				for c: Dictionary in view.call("sorted_candidates", d):
					if str(c["picked_by"]).is_empty():
						view.call("select_candidate", c["id"])
						break
				view.call("press_action")
				picked += 1
			else:
				view.call("_on_finish_pressed")
		else:
			view.call("_on_skip_pressed")
		await _frames(1)
	_check(d.stage == _done and d.resolved and not d.user_auto,
		"%d年：おまかせを使わずにドラフトの最後まで進む（自球団の指名 %d人）" % [year, d.picks_of(team).size()])
	hub.call("_close_sub_screen")
	await _frames(2)
	# ドラフトのあとは FA → 現役ドラフト → 春季キャンプ（作業54）。翌年になるまで可変ボタンで進める
	for i in 6:
		if _gs.year == year + 1:
			break
		hub.call("_close_sub_screen")
		_gs.fa_resolve()
		_gs.comp_resolve()
		hub.call("_on_menu_chosen", "advance")
		await _frames(4)
	var year_text: String = hub.get_node("%YearLabel").text
	_check(_gs.year == year + 1 and year_text.contains(str(year + 1)),
		"可変ボタンで翌年へ進み、ハブの年が追従（%s／%s）" % [year_text, _gs.phase_name()])


func _kind_text(kind: String) -> String:
	return {"single": "単独で確定", "win": "競合して当選", "lose": "競合して外れ"}.get(kind, "不明")


func _find_draft_view(node: Node) -> Node:
	if node.get_script() == _dv:
		return node
	for child in node.get_children():
		var found := _find_draft_view(child)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## other：外れ1位の演出以外のスクショ（_shot_taken を立てない）
func _shot(name: String, other := false) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	if not other:
		_shot_taken = true
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
