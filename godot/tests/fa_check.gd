extends SceneTree
## FA・ポスティングの確認（ヘッドレス可。ウィンドウ付きで出力先を渡すとスクショも保存）。
## 1) 2008年から2012年のオフまで（2013年の開幕まで）進め、毎年のオフに次を調べる：
##    - FA宣言が起き、締め切りで移籍（CPU球団どうしを含む）・残留が決まる。移籍した選手は翌年の開幕で新しい球団の編成にいる
##    - 自球団の入札（上限の額・5年）で他球団の選手を獲得できる
##    - 自球団の選手のFA宣言（無ければ資格のある選手に宣言させる）を引き留められる。決まった年俸は契約年数のあいだ据え置き
##    - オフの日付表示（「YYYY年 オフ」）と、翌年の開幕で年・日付が進む
## 2) 2011年オフ、日本ハムを自球団にしてダルビッシュ（ポスティング）を引き留める操作を、ハブ → 可変ボタン →
##    FA・ポスティングの画面（RB でメジャー移籍タブ、札を選ぶ、もう一度で選手詳細、「引き留める」）でキーボード・マウスで行う。
##    成功（乱数を固定）：日本ハムに残り、2012年はメジャーにいた年の能力値（mlb_players）で編成に入る。史実の復帰・引退が
##    二重に起きず、2013年の開幕にも日本ハムにいる。失敗：メジャーへ行き、2012年の開幕にはいない
##
##   godot --headless --path godot --script res://tests/fa_check.gd -- [出力先]

const DARVISH := "61965110"
const NIPPON_HAM := "北海道日本ハムファイターズ"
const USER_TEAM := "読売ジャイアンツ"
const LAST_OFF := 2012

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_check_offseasons()
	await _check_darvish(true)
	await _check_darvish(false)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


# --- 1) 2008〜2012年のオフ ---------------------------------------------------------------

func _check_offseasons() -> void:
	print("== 2008〜%d年のオフ（自球団：%s） ==" % [LAST_OFF, USER_TEAM])
	# 毎年上限の額で獲得するので、ここでは予算上限を外す（予算の効き方は tests/contract_check.gd で確かめる）
	var contract_renewal: GDScript = load("res://sim/contract_renewal.gd")
	contract_renewal.set_budget_override(USER_TEAM, 10000000)
	_gs.new_game(USER_TEAM)
	var league: Variant = _gs.league
	var total_declared := 0
	var cpu_moves := 0
	var bought := 0
	var kept := 0
	while true:
		var y: int = _gs.year
		_gs.advance_through(_gs.season_last_day())
		_check(_gs.phase == _gs.Phase.AWARDS and _gs.date_text() == "%d年 オフ" % y,
				"%d年 シーズン終了で日付は「%s」" % [y, _gs.date_text()])
		_gs.advance()
		_check(_gs.phase == _gs.Phase.FA_TRADE, "%d年オフ：FA・トレード・ポスティングへ" % y)
		var f: Variant = _gs.fa()
		_check(f != null and _gs.fa_open() and _gs.button_text() == "FA・移籍交渉",
				"%d年オフ：FAの交渉中（ボタン=%s）" % [y, _gs.button_text()])
		total_declared += f.declared.size()
		var names: Array[String] = []
		for id: String in f.declared:
			names.append("%s(%s)" % [league.names.get(id, id), _gd.short_name(f.info[id]["from"])])
		print("%d年オフ FA宣言 %d人：%s" % [y, f.declared.size(), "、".join(names)])
		# 自球団の入札：他球団の宣言選手のうち一番能力の高い選手に上限の額・5年
		var target := _best_other(f, league)
		if not target.is_empty():
			var r: Array = f.bid_range(target)
			_check(_gs.fa_offer(target, r[1], 5).is_empty(), "%d年オフ：%sに提示できる" % [y, league.names[target]])
			_check(f.stars(league, target, r[1], 5) >= 4, "%d年オフ：上限の提示の成功率は高い（★%d）" % [
				y, f.stars(league, target, r[1], 5)])
		# 自球団の選手の引き留め（宣言が無ければ資格のある選手に宣言させる）
		var own := _own_declared(f)
		if own.is_empty():
			own = _force_own_declare(f, league)
		if not own.is_empty():
			var r: Array = f.bid_range(own)
			_check(_gs.fa_offer(own, r[1], 3).is_empty(), "%d年オフ：自球団の%sを引き留める提示" % [y, league.names[own]])
		_check(not _gs.fa_offer("00000000", 1000, 1).is_empty(), "宣言していない選手には提示できない")
		_gs.fa_resolve()
		_check(f.resolved and not _gs.fa_open() and _gs.button_text() == "契約更改へ",
				"%d年オフ：締め切ると次は契約更改（%s）" % [y, _gs.button_text()])
		_check(not _gs.fa_offer(target if not target.is_empty() else own, 1000, 1).is_empty(),
				"締め切ったあとは提示できない")
		var moved_to := {}
		for res: Dictionary in f.results:
			print("  %s：%s → %s %s・%d年（入札%d球団%s）" % [league.names[res["id"]], _gd.short_name(res["from"]),
				_gd.short_name(res["to"]), Salary.text(res["amount"]), res["years"], res["bidders"],
				"、自球団も" if res["user_bid"] else ""])
			_check(league.team_of.get(res["id"], "") == res["to"], "%sの所属が結果どおり" % league.names[res["id"]])
			_check(league.salary_of(res["id"]) == res["amount"], "%sの来季の年俸が結果どおり" % league.names[res["id"]])
			if res["to"] != res["from"]:
				moved_to[res["id"]] = res
				if res["to"] != USER_TEAM and res["from"] != USER_TEAM:
					cpu_moves += 1
		if not target.is_empty():
			var ok: bool = league.team_of.get(target, "") == USER_TEAM
			_check(ok, "%d年オフ：入札で%sを獲得" % [y, league.names[target]])
			if ok:
				bought += 1
		if not own.is_empty():
			var ok: bool = league.team_of.get(own, "") == USER_TEAM
			_check(ok, "%d年オフ：%sを引き留めた" % [y, league.names[own]])
			if ok:
				kept += 1
		var contract := {}
		for id: String in moved_to:
			contract[id] = league.salary_of(id)
		while _gs.phase != _gs.Phase.SEASON:
			_gs.advance()
		_check(_gs.year == y + 1 and _gs.date_text().begins_with("%d年 " % (y + 1)) and _gs.month_text() != "オフ",
				"%d年の開幕へ（%s）" % [y + 1, _gs.date_text()])
		for id: String in moved_to:
			var res: Dictionary = moved_to[id]
			if not league.team_of.has(id):
				continue  # その後に引退など
			var sim: SimTeam = _gs.season.teams.get(league.team_of[id])
			_check(sim != null and sim.by_id.has(id), "%d年開幕：%sが%sの編成にいる" % [
				y + 1, league.names[id], _gd.short_name(league.team_of[id])])
			if int(league.contract_until.get(id, 0)) >= y + 1:
				_check(league.salary_of(id) == contract[id], "%sの年俸は契約年数のあいだ据え置き" % league.names[id])
		if y >= LAST_OFF:
			break
	contract_renewal.set_budget_override(USER_TEAM, -1)
	print("FA宣言 計%d人、CPU球団どうしの移籍 %d人、自球団の獲得 %d人、引き留め %d人" % [
		total_declared, cpu_moves, bought, kept])
	_check(total_declared >= 10, "5年でFA宣言が10人以上（%d人）" % total_declared)
	_check(cpu_moves >= 1, "CPU球団どうしのFA移籍が起きる（%d人）" % cpu_moves)
	_check(bought >= 3, "自球団の入札で獲得できる（%d人）" % bought)
	_check(kept >= 3, "自球団の選手を引き留められる（%d人）" % kept)
	var fa_logs := 0
	for e: Dictionary in league.log:
		if e["kind"] in ["fa_move", "fa_stay", "fa_declare"]:
			fa_logs += 1
	_check(fa_logs > 0, "FAの出来事が記録される（%d件）" % fa_logs)


func _best_other(f: Variant, league: Variant) -> String:
	var best := ""
	var best_z := -INF
	for id: String in f.declared:
		if f.info[id]["from"] == USER_TEAM:
			continue
		var z := float(Salary.ability(_gd.player(id))[0])
		if z > best_z:
			best_z = z
			best = id
	return best


func _own_declared(f: Variant) -> String:
	for id: String in f.declared:
		if f.info[id]["from"] == USER_TEAM:
			return id
	return ""


func _force_own_declare(f: Variant, league: Variant) -> String:
	var debut: Dictionary = _gd.load_debut_years(_gs.year)
	for id: String in league.players_of(USER_TEAM):
		if id in league.plan_retirements():
			continue
		if f.eligible(league, id, debut):
			f.declare(league, id)
			print("  （%sに宣言させた）" % league.names[id])
			return id
	return ""


# --- 2) ダルビッシュの引き留め ------------------------------------------------------------

func _check_darvish(success: bool) -> void:
	var label := "成功" if success else "失敗"
	print("\n== 2011年オフ：日本ハムでダルビッシュを引き留める（%s） ==" % label)
	_gs.new_game(NIPPON_HAM, 2011)
	var league: Variant = _gs.league
	_check(league.team_of.get(DARVISH, "") == NIPPON_HAM, "2011年開幕：ダルビッシュは日本ハム")
	_gs.advance_through(_gs.season_last_day())
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene
	_check(hub.get("_year_label").text == "2011" and hub.get("_month_label").text == "オフ",
			"ハブ：2011年 オフ（%s %s）" % [hub.get("_year_label").text, hub.get("_month_label").text])
	# 可変ボタン（「FA/トレードへ」）で FA・ポスティングの画面が開く
	_check(_focus_key(hub) == "advance", "ハブ：可変ボタンにフォーカス")
	await _key(KEY_ENTER)
	_check(_gs.phase == _gs.Phase.FA_TRADE and hub.get("_open_key") == "fa",
			"可変ボタンで FA・ポスティングの画面（%s / %s）" % [_gs.phase_name(), hub.get("_open_key")])
	var view: Node = hub.get("_fa_view")
	var f: Variant = _gs.fa()
	_check(DARVISH in f.mlb and f.mlb_info[DARVISH]["from"] == NIPPON_HAM and not league.team_of.has(DARVISH),
			"ダルビッシュはメジャー移籍の一覧にいる（いったん退団）")
	if success and not view.list_ids().is_empty():
		var first: String = view.list_ids()[0]
		await _key(KEY_ENTER)
		_check(view.selected_id() == first, "FA宣言の先頭の札を Enter で選ぶ")
		await _shot("fa1_declared")
		await _key(KEY_ESCAPE)
		_check(view.selected_id().is_empty() and hub.get("_open_key") == "fa", "Esc で選択だけ取り消す")
	await _key(KEY_E)
	_check(view.get("_tab") == "mlb", "E（RB）でメジャー移籍タブ")
	_check(view.list_ids().size() > 0 and view.list_ids()[0] == DARVISH, "自球団のダルビッシュが先頭")
	var tag: Control = view.get("_tags").get(DARVISH)
	if success:
		_check(_focused() == tag, "先頭の札にフォーカス")
		await _key(KEY_ENTER)
	else:
		await _click(tag)
	_check(view.selected_id() == DARVISH, "札を選ぶ（%s）" % ("Enter" if success else "クリック"))
	# もう一度で選手詳細（Esc で閉じる）
	if success:
		await _key(KEY_ENTER)
	else:
		await _click(view.get("_tags").get(DARVISH))
	var detail := _detail()
	_check(detail != null, "同じ札をもう一度で選手詳細が開く")
	await _key(KEY_ESCAPE)
	_check(_detail() == null and view.selected_id() == DARVISH, "Esc で選手詳細を閉じる（選択はそのまま）")
	# 年俸を上限まで上げて、年数5年
	var r: Array = f.bid_range(DARVISH)
	for i in 80:
		view.call("_step_amount", 1)
	for i in 5:
		view.call("_step_years", 1)
	_check(view.get("_amount") == r[1] and view.get("_years") == 5, "◀▶で年俸を上限（%s）・5年に" % Salary.text(r[1]))
	var chance: float = f.keep_chance(DARVISH, r[1], 5)
	_check(chance >= 0.05 and chance <= 0.2, "成功率は5〜20%%（%d%%）" % roundi(chance * 100))
	if success:
		await _shot("fa2_mlb_keep")
	f.force_roll = 0.0 if success else 0.999
	var button: Button = view.get("_action_button")
	_check(button.text == "引き留める" and not button.disabled, "「引き留める」を押せる")
	UiInput_grab(button)
	await _key(KEY_ENTER)
	var status: String = f.mlb_info[DARVISH]["status"]
	_check(status == ("kept" if success else "failed"), "引き留めの結果：%s" % status)
	if success:
		await _shot("fa3_mlb_kept")
		_check(league.team_of.get(DARVISH, "") == NIPPON_HAM and not league.in_mlb.has(DARVISH)
				and league.kept_mlb.has(DARVISH), "成功：日本ハムに残留（メジャーにいない）")
		_check(league.salary_of(DARVISH) == r[1] and int(league.contract_until[DARVISH]) == 2016,
				"成功：年俸 %s・2016年まで" % Salary.text(league.salary_of(DARVISH)))
	else:
		_check(not league.team_of.has(DARVISH) and league.in_mlb.has(DARVISH), "失敗：メジャーへ")
	_check(button.disabled, "引き留めは1回だけ（ボタンが押せない）")
	var again: Dictionary = _gs.mlb_keep(DARVISH, r[1], 5)
	_check(not again["ok"], "2回目の引き留めはできない")
	# Esc で選択の取り消し → ハブへ。可変ボタンはまだ FA の交渉（締め切っていない）
	await _key(KEY_ESCAPE)
	_check(view.selected_id().is_empty() and hub.get("_open_key") == "fa", "Esc で選択の取り消し")
	await _key(KEY_ESCAPE)
	_check(hub.get("_open_key") == "" and _gs.button_text() == "FA・移籍交渉", "Esc でハブへ（ボタン=%s）" % _gs.button_text())
	await _key(KEY_ENTER)
	_check(hub.get("_open_key") == "fa" and _gs.phase == _gs.Phase.FA_TRADE, "可変ボタンで FA の画面に戻る（段階は進まない）")
	UiInput_grab(view.get("_close_button"))
	await _key(KEY_ENTER)
	_check(f.resolved and view.get("_tab") == "result", "「締め切って結果を見る」で結果タブ")
	if success:
		await _shot("fa4_result")
	await _key(KEY_ESCAPE)
	_check(hub.get("_open_key") == "" and _gs.button_text() == "契約更改へ", "締め切ると可変ボタンは「契約更改へ」")
	# 2012年の開幕へ
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	await _frames(3)
	_check(hub.get("_year_label").text == "2012" and hub.get("_month_label").text != "オフ",
			"ハブの日付が2012年の開幕に追従（%s %s）" % [hub.get("_year_label").text, hub.get("_month_label").text])
	var p: Dictionary = _gd.player(DARVISH)
	if success:
		_check(league.team_of.get(DARVISH, "") == NIPPON_HAM, "2012年開幕：ダルビッシュは日本ハム")
		_check(p.get("kept_from_mlb") == "mlb" and p.get("team") == NIPPON_HAM,
				"2012年：能力値はメジャーにいた年の換算（%s）" % str(p.get("kept_from_mlb")))
		var sim: SimTeam = _gs.season.teams.get(NIPPON_HAM)
		_check(sim != null and sim.by_id.has(DARVISH), "2012年：日本ハムの編成にいる")
		_gs.advance_through(Season.day_number("2012-06-30"))
		var stats: Dictionary = _gs.season.pitching.get(DARVISH, {})
		_check(int(stats.get("outs", 0)) > 0, "2012年：試合に投げている（%d回）" % (int(stats.get("outs", 0)) / 3))
		_gs.advance_through(_gs.season_last_day())
		while _gs.phase != _gs.Phase.SEASON:
			_gs.advance()
		_check(league.team_of.get(DARVISH, "") == NIPPON_HAM and not league.retired.has(DARVISH),
				"2013年開幕：まだ日本ハム（引退・復帰の処理が二重に起きない）")
		var counts := {}
		for e: Dictionary in league.log:
			if e["id"] == DARVISH:
				counts[e["kind"]] = counts.get(e["kind"], 0) + 1
		_check(counts.get("mlb_leave", 0) == 1 and counts.get("mlb_return", 0) == 0 and counts.get("retire", 0) == 0
				and counts.get("mlb_keep", 0) == 1, "ダルビッシュの出来事：%s" % str(counts))
		_check(league.salary_of(DARVISH) == r[1], "2013年も契約どおりの年俸（%s）" % Salary.text(league.salary_of(DARVISH)))
	else:
		_check(not league.team_of.has(DARVISH) and league.in_mlb.has(DARVISH), "2012年開幕：ダルビッシュはメジャー")
		var sim: SimTeam = _gs.season.teams.get(NIPPON_HAM)
		_check(sim != null and not sim.by_id.has(DARVISH), "2012年：日本ハムの編成にいない")


# --- 共通 --------------------------------------------------------------------------------

func UiInput_grab(c: Control) -> void:
	root.get_node("UiInput").grab(c)


func _focus_key(hub: Node) -> String:
	var c := _focused()
	if c != null and c.get_parent() != null and c.get_parent().has_signal("chosen"):
		return str(c.get_parent().get("key"))
	return ""


func _detail() -> Node:
	var scene := current_scene
	for layer in scene.get_children():
		if layer is CanvasLayer:
			for c in layer.get_children():
				if c.has_method("_show_player"):
					return c
	return null


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


## マウスのクリック（ヘッドレスでは Input.parse_input_event のマウスが GUI に届かないので、ビューポートへ直接送る）
func _click(c: Control) -> void:
	# 画面の引き伸ばし（ヘッドレスはウィンドウが基準の解像度と違う）を考えてウィンドウの座標にする
	var pos := root.get_final_transform() * c.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	root.push_input(move)
	await _frames(1)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.position = pos
		e.global_position = pos
		e.pressed = pressed
		root.push_input(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.35) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
