extends SceneTree
## 育成選手の支配下への昇格の確認（ヘッドレス）。docs/AUTORUN.md 作業19。
## 1) 2008年の開幕：どの球団も育成選手が1軍にいない。自球団の育成選手は1軍に上げられない
## 2) 自球団の育成選手を支配下に登録 → 支配下の人数が1人増える → 1軍の先発（投手）／スタメン（野手）と入れ替え →
##    2週間進めて試合に出る。登録画面（投手・野手1軍登録）の「支配下に登録する」ボタンからも上げられる
## 3) 7月31日を過ぎると上げられない（ボタンも押せない）。セーブ→ロードで昇格が残る
## 4) 2008〜2010年：CPU球団が毎年何人か昇格させ、育成選手が1軍にいない。育成3年の再契約が記録される
##    （CPU の昇格は支配下70人の空きがあるときだけ。上限そのものは release_check・roster_year_check で調べる）
##
##   godot --headless --path godot --script res://tests/ikusei_check.gd -- [自球団] [出力先]
## 出力先を渡してウィンドウ付きで流すと、登録画面で育成選手を選んだところを1枚撮る（--position で画面の隅に置き、フォーカスを奪わない）

const HUB_SCENE := "res://scenes/hub/hub.tscn"

var _team := "読売ジャイアンツ"
var _out := ""
var _failures := 0
var _gs: Node
var _season_gd: GDScript
var _sg: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_team = args[0]
	if args.size() > 1:
		_out = args[1]
		DirAccess.make_dir_recursive_absolute(_out)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_season_gd = load("res://sim/season.gd")
	_sg = load("res://scripts/save_game.gd")
	# 他のテスト（save_check）と同時に流しても枠がぶつからないよう専用のフォルダ
	_sg.set("dir", "user://test_saves_ikusei")
	_sg.set("autosave_enabled", false)
	_gs.new_game(_team, 2008)
	print("\n-- 1) 2008年の開幕 --")
	_check_no_ikusei_active("開幕")
	var mine: Object = _gs.my_team()
	var ikusei: Array = mine.players.filter(func(p: Object) -> bool: return p.is_ikusei)
	_check(ikusei.size() >= 2, "自球団（%s）に育成選手が2人以上（%d人）" % [_team, ikusei.size()])
	if ikusei.size() < 2:
		_finish()
		return
	var target: Object = ikusei[0]
	var err: String = mine.promote(target, _gs.day)
	_check(not err.is_empty() and not mine.is_active(target), "育成のままでは1軍に上げられない（%s）" % err)

	print("\n-- 2) 支配下に登録して1軍で試合に出る --")
	var before: int = _gs.league.registered_count(_team)
	err = _gs.promote_ikusei(target.id)
	_check(err.is_empty(), "%sを支配下に登録 %s" % [target.name, err])
	_check(not target.is_ikusei and not _gs.is_ikusei(target.id), "支配下に登録したら育成ではない")
	_check(_gs.league.registered_count(_team) == before + 1, "支配下が1人増える（%d → %d）" % [
		before, _gs.league.registered_count(_team)])
	var out_p: Object = mine.rotation[0] if target.is_pitcher else mine.lineup(true)[0][0]
	err = mine.swap_registration(out_p, target, _gs.day)
	_check(err.is_empty() and mine.is_active(target), "%sを1軍に登録（%sと入れ替え）%s" % [target.name, out_p.name, err])
	_gs.advance_through(_gs.day + 14)
	var stats: Dictionary = (_gs.season.pitching if target.is_pitcher else _gs.season.batting).get(target.id, {})
	_check(int(stats.get("g", 0)) > 0, "2週間で%sが試合に出た（%d試合）" % [target.name, int(stats.get("g", 0))])
	await _check_ui(ikusei[1])

	print("\n-- 3) 7月31日の期限・セーブ --")
	var left: Array = mine.players.filter(func(p: Object) -> bool: return p.is_ikusei)
	_gs.advance_through(_season_gd.day_number("2008-07-30"))
	_check(_gs.date_text() == "2008年 7月31日", "7月31日まで進める（%s）" % _gs.date_text())
	_check(_gs.ikusei_promote_block().is_empty(), "7月31日は支配下に登録できる")
	_gs.advance_through(_season_gd.day_number("2008-07-31"))
	_check(not _gs.ikusei_promote_block().is_empty(), "8月1日は支配下に登録できない（%s）" % _gs.ikusei_promote_block())
	if not left.is_empty():
		err = _gs.promote_ikusei(left[0].id)
		_check(not err.is_empty() and _gs.is_ikusei(left[0].id), "8月に%sを上げようとすると断られる（%s）" % [left[0].name, err])
	_check(_sg.call("save", "slot1").is_empty(), "セーブ")
	_gs.new_game("阪神タイガース", 2010)
	_check(_sg.call("load_slot", "slot1").is_empty(), "ロード")
	_check(_gs.league.promoted.has(target.id) and not _gs.is_ikusei(target.id)
		and not _gs.my_team().by_id[target.id].is_ikusei, "ロードしても%sは支配下" % target.name)
	if not left.is_empty():
		_check(_gs.my_team().by_id[left[0].id].is_ikusei, "ロードしても%sは育成" % left[0].name)
	_sg.call("delete", "slot1")

	print("\n-- 4) 2008〜2010年：CPU球団の昇格 --")
	for y in [2008, 2009, 2010]:
		if y > 2008:
			while _gs.phase != _gs.Phase.SEASON:
				_gs.advance()
			_check_no_ikusei_active("%d年開幕" % y)
		_gs.advance_through(_gs.season_last_day() - 1)
		var count := 0
		var teams := {}
		for e: Dictionary in _gs.league.log:
			if e["kind"] == "ikusei_promote" and int(e["year"]) == y and e["from"] != _gs.team:
				count += 1
				teams[e["from"]] = true
		_check(count >= 2, "%d年：CPU球団の昇格 %d人（%d球団）" % [y, count, teams.size()])
		_check_no_ikusei_active("%d年の終盤" % y)
		_gs.advance_through(_gs.season_last_day())
	_check_renew()
	_finish()


## 育成3年の再契約：入団から3年たっても育成の選手がいる年で LeagueRoster._renew_ikusei を呼ぶと出来事に残る
## （2008〜2010年は該当者が少なく、年越しで出るとは限らないので直接呼ぶ）
func _check_renew() -> void:
	var league: Object = _gs.league
	var gd: Node = root.get_node("GameData")
	for id: String in league.team_of:
		var jy: int = league.call("_ikusei_joined_year", id)
		if jy <= 0:
			continue
		var y := jy + 3
		if not league.is_ikusei(id, gd.player(id), y, gd.load_debut_years(y)):
			continue
		var n: int = league.log.size()
		league.call("_renew_ikusei", y)
		var added: Array = league.log.slice(n).filter(func(e: Dictionary) -> bool:
			return e["kind"] == "ikusei_renew" and e["id"] == id)
		_check(not added.is_empty(), "育成3年の再契約が記録される（%s）" % (added[0]["text"] if not added.is_empty() else id))
		return
	_check(false, "育成3年の再契約：入団から3年たっても育成の選手が見つからない")


func _finish() -> void:
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## どの球団も1軍に育成選手がいない
func _check_no_ikusei_active(when: String) -> void:
	var bad: Array[String] = []
	for t: String in _gs.season.teams:
		var team: Object = _gs.season.teams[t]
		for p: Object in team.players:
			if p.is_ikusei and team.is_active(p):
				bad.append("%s %s" % [t, p.name])
	_check(bad.is_empty(), "%s：育成選手が1軍にいない %s" % [when, ", ".join(bad.slice(0, 3))])


## 登録画面：育成選手を選ぶと「支配下に登録する」が出て、押すと支配下になる
func _check_ui(p: Object) -> void:
	change_scene_to_file(HUB_SCENE)
	for i in 6:
		await process_frame
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "tactics")
	var tactics: Node = hub.get("_tactics_view")
	var page_key := "pitchers" if p.is_pitcher else "fielders"
	tactics.call("_show_page", page_key, true)
	await process_frame
	var page: Node = tactics.get("_register_" + page_key)
	page.set("_selected", p)
	page.refresh()
	await process_frame
	var button: Button = _find_button(page, "支配下に登録する")
	_check(button != null and not button.disabled, "登録画面に「支配下に登録する」（%s）" % p.name)
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("ikusei_register.png"))
		print("  スクショ: ikusei_register.png")
	if button != null:
		button.pressed.emit()
		await process_frame
		_check(not p.is_ikusei and _gs.league.promoted.has(p.id), "ボタンで%sが支配下に" % p.name)
		_check(_find_button(page, "支配下に登録する") == null, "登録したらボタンは消える")
	tactics.call("_show_page", "")
	hub.call("_close_sub_screen")


func _find_button(node: Node, text: String) -> Button:
	for c in node.find_children("*", "Button", true, false):
		if (c as Button).text == text and (c as Button).is_visible_in_tree():
			return c
	return null


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1
