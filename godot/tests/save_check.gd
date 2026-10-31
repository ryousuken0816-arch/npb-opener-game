extends SceneTree
## セーブ／ロードの確認（docs/AUTORUN.md 作業6）。ヘッドレス可。ウィンドウ付きで出力先を渡すとセーブ画面のスクショを保存。
## セーブは user://test_saves/ に書き、最後に消す（ユーザーのセーブ user://saves/ には触らない）。
## 1) シーズン途中：2008年（阪神）を6月15日まで進め、1軍の入れ替えと方針を変えてスロット1にセーブ → そのまま5日進めた結果を控え →
##    別の年・球団で新しく始めてからロード → 日付・順位・勝敗・個人成績・所属・年俸・1軍登録・全状態が一致 →
##    5日進めて、セーブ直後に進めたときと日付・試合数が一致
## 2) オフの途中：FA段階（自球団の提示あり）→スロット2、契約更改段階（提示額を変更）→スロット3、ドラフト段階の途中
##    （1位入札〜何人か指名した後）→スロット1。それぞれ別の状態にしてからロード → 段階・途中経過・全状態が元どおり →
##    最後まで進めて2009年の開幕に到達（ドラフトは自球団の指名選手が2009年の自球団にいる）
## 3) オートセーブ：月替わり・段階の切り替わりで更新される。早送り中はセーブできない
## 4) タイトルの「続きから」→枠を選んでロード→ハブ、ハブのシステム→セーブ（上書きの確認・取り消し）／ロードをキーボードだけで
##
##   godot --headless --path godot --script res://tests/save_check.gd -- [出力先]

const USER := "阪神タイガース"

var _out := ""
var _failures := 0
var _gs: Node
var _sg: GDScript
var _season_gd: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_sg = load("res://scripts/save_game.gd")
	_season_gd = load("res://sim/season.gd")
	_sg.set("dir", "user://test_saves")
	_sg.set("autosave_enabled", false)
	for slot: String in _sg.call("all_slots"):
		_sg.call("delete", slot)
	_check_season()
	_check_offseason()
	await _check_autosave()
	await _check_ui()
	for slot: String in _sg.call("all_slots"):
		_sg.call("delete", slot)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


# --- 1) シーズン途中 ----------------------------------------------------------------------

func _check_season() -> void:
	print("\n-- 1) シーズン途中のセーブ／ロード --")
	_gs.new_game(USER, 2008)
	_gs.advance_through(_season_gd.day_number("2008-06-14"))
	_check(_gs.date_text() == "2008年 6月15日", "2008年6月15日まで進める（%s）" % _gs.date_text())
	# 1軍の入れ替え（2軍の投手を中継ぎの最後の投手と）と方針
	var mine: Object = _gs.my_team()
	var p_out: Object = mine.relievers[-1]
	var p_in: Object = null
	for p: Object in mine.players_where(false, true):
		if p.has_pitching and not p.is_ikusei and mine.reregister_day(p) < 0:
			p_in = p
			break
	var swap_error: String = mine.swap_registration(p_out, p_in, _gs.day) if p_in != null else "2軍の投手なし"
	_check(swap_error.is_empty() and mine.is_active(p_in), "1軍の入れ替え（%s ↔ %s）%s" % [
		p_out.name, p_in.name if p_in != null else "-", swap_error])
	_gs.set_tactic("bunt", 2)
	var before := _snapshot()
	var full: Variant = _norm(_gs.to_save())
	var t0 := Time.get_ticks_msec()
	var error: String = _sg.call("save", "slot1")
	var save_ms := Time.get_ticks_msec() - t0
	var size := FileAccess.get_file_as_bytes(_sg.call("path", "slot1")).size()
	_check(error.is_empty(), "スロット1にセーブ（%d ms、%.1f MB）%s" % [save_ms, size / 1048576.0, error])
	# セーブ直後にそのまま5日進めた結果
	var target_day: int = _gs.day + 4
	_gs.advance_through(target_day)
	var after_direct := {"day": _gs.day, "played": _gs.season.played_count(), "record": _gs.record_text(),
		"standings": _standings()}
	# 別の年・球団で新しく始める
	_gs.new_game("読売ジャイアンツ", 2010)
	_check(_gs.year == 2010 and _gs.team == "読売ジャイアンツ", "別の状態（2010年・巨人）にする")
	t0 = Time.get_ticks_msec()
	error = _sg.call("load_slot", "slot1")
	_check(error.is_empty(), "スロット1をロード（%d ms）%s" % [Time.get_ticks_msec() - t0, error])
	var after := _snapshot()
	for key: String in before:
		_check(JSON.stringify(before[key]) == JSON.stringify(after[key]), "ロード後に一致：%s" % key)
	_check_same(full, _norm(_gs.to_save()), "ロード後に全状態（GameState.to_save()）が一致")
	_check(_gs.my_team().is_active(_gs.my_team().by_id.get(p_in.id)), "入れ替えた投手が1軍のまま")
	_gs.advance_through(target_day)
	_check(_gs.day == after_direct["day"] and _gs.season.played_count() == after_direct["played"],
		"ロード後に5日進めて、セーブ直後に進めたときと日付・試合数が一致（%s・%d試合）" % [
			_gs.date_text(), _gs.season.played_count()])
	print("   参考：勝敗・順位も一致するか＝%s（%s / %s）" % [
		str(_gs.record_text() == after_direct["record"] and _standings() == after_direct["standings"]),
		_gs.record_text(), after_direct["record"]])


## 比べる項目（人が読める単位）
func _snapshot() -> Dictionary:
	var s := {}
	s["日付"] = [_gs.year, _gs.day, _gs.phase, _gs.date_text()]
	s["球団"] = _gs.team
	s["勝敗"] = [_gs.wins, _gs.losses, _gs.draws]
	s["順位表"] = _standings()
	s["方針"] = _gs.tactics.duplicate()
	var season: Object = _gs.season
	if season != null:
		s["試合数"] = [season.played_count(), season.next_index]
		var ids: Array = season.batting.keys()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var pa := int(season.batting[a].get("pa", 0))
			var pb := int(season.batting[b].get("pa", 0))
			return pa > pb if pa != pb else a < b)
		var bat := {}
		for id: String in ids.slice(0, 4):
			bat[id] = season.batting[id].duplicate(true)  # pos_g（入れ子）も写す
		s["打撃成績（4人）"] = bat
		ids = season.pitching.keys()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var oa := int(season.pitching[a].get("outs", 0))
			var ob := int(season.pitching[b].get("outs", 0))
			return oa > ob if oa != ob else a < b)
		var pit := {}
		for id: String in ids.slice(0, 3):
			pit[id] = season.pitching[id].duplicate(true)
		s["投手成績（3人）"] = pit
	var league: Object = _gs.league
	var members: Array = league.players_of(_gs.team)
	members.sort()
	s["所属（自球団）"] = members
	var sal := {}
	for id: String in members.slice(0, 10):
		sal[id] = league.salary_of(id)
	s["年俸（自球団10人）"] = sal
	var payrolls := {}
	for t: String in root.get_node("GameData").teams():
		payrolls[t] = league.payroll(t)
	s["年俸総額（12球団）"] = payrolls
	s["所属の人数"] = league.team_of.size()
	var mine: Object = _gs.my_team()
	if mine != null and _gs.phase == 0:
		var active: Array = mine.active.keys()
		active.sort()
		s["1軍登録"] = active
		s["抹消日"] = mine.demoted_day.duplicate()
		var lineup := []
		for e: Array in mine.lineup_dh:
			lineup.append([e[0].id if e[0] != null else null, e[1]])
		s["オーダー（DHあり）"] = lineup
		var rot := []
		for p: Object in mine.rotation:
			rot.append(p.id)
		s["ローテ"] = rot
	return s


func _standings() -> Array:
	var rows := []
	for lg: String in ["C", "P"]:
		for row: Dictionary in _gs.standings(lg):
			rows.append([row["team"], row["wins"], row["losses"], row["draws"], row["rank"]])
	return rows


# --- 2) オフの途中 ------------------------------------------------------------------------

func _check_offseason() -> void:
	print("\n-- 2) オフの途中のセーブ／ロード --")
	_gs.new_game(USER, 2008)
	_gs.skip_to_phase(3)  # FA_TRADE
	var fa: Object = _gs.fa()
	_check(fa != null and _gs.fa_open(), "2008年オフ：FA段階")
	var offer_id := ""
	for id: String in fa.declared:
		if fa.info[id]["from"] != USER:
			offer_id = id
			break
	var offer_error := "宣言した他球団の選手なし"
	if not offer_id.is_empty():
		var r: Array = fa.bid_range(offer_id)
		offer_error = _gs.fa_offer(offer_id, r[1], 3)
	_check(offer_error.is_empty(), "FA：%sに提示 %s" % [_gs.league.names.get(offer_id, offer_id), offer_error])
	var fa_state: Variant = _norm(_gs.to_save())
	_check(str(_sg.call("save", "slot2")).is_empty(), "FA段階でスロット2にセーブ")

	_gs.advance()
	var c: Object = _gs.contracts()
	_check(c != null and _gs.contract_open(), "契約更改の段階")
	var renew_id := ""
	for id: String in c.order:
		if c.can_adjust(id) and int(c.rows[id]["high"]) > int(c.rows[id]["amount"]):
			renew_id = id
			break
	var renew_amount := 0
	if not renew_id.is_empty():
		renew_amount = int(c.rows[renew_id]["high"])
		_gs.contract_set(renew_id, renew_amount)
	_check(not renew_id.is_empty() and _gs.league.salary_of(renew_id) == renew_amount,
		"契約更改：%sの提示額を上限（%d万円）に" % [_gs.league.names.get(renew_id, renew_id), renew_amount])
	var contract_state: Variant = _norm(_gs.to_save())
	_check(str(_sg.call("save", "slot3")).is_empty(), "契約更改の段階でスロット3にセーブ")

	_gs.advance()
	_gs.advance()
	var d: Object = _gs.draft()
	_check(d != null and _gs.draft_open(), "ドラフトの段階")
	var guard := 0
	while d.stage == 0 and guard < 10:  # FIRST
		guard += 1
		d.run_first_wave()
	d.run_until_user()
	var user_picks := 0
	for i in 2:
		if d.is_user_turn():
			var best := ""
			var best_value := -INF
			for cand: Dictionary in d.remaining():
				if float(cand["hyouka"]) > best_value:
					best_value = float(cand["hyouka"])
					best = cand["id"]
			if str(d.user_pick(best)).is_empty():
				user_picks += 1
			d.run_until_user()
	_gs.draft_sync()
	var picks_before: int = d.picks.size()
	_check(user_picks >= 1 and d.stage != 3, "ドラフトの途中：%d人指名済み（自球団の2位以降 %d人）・%s" % [
		picks_before, user_picks, d.stage_text()])
	var draft_state: Variant = _norm(_gs.to_save())
	var draft_turn: String = d.current_team()
	_check(str(_sg.call("save", "slot1")).is_empty(), "ドラフトの途中でスロット1にセーブ（上書き）")

	# それぞれ別の状態にしてからロード → 元どおり → 最後まで進めて翌年の開幕へ
	for item: Array in [["slot2", fa_state, 3, "FA"], ["slot3", contract_state, 4, "契約更改"],
			["slot1", draft_state, 6, "ドラフト"]]:
		_gs.new_game("北海道日本ハムファイターズ", 2011)
		var error: String = _sg.call("load_slot", item[0])
		_check(error.is_empty() and _gs.phase == item[2] and _gs.year == 2008 and _gs.team == USER,
			"%s：別の状態からロードして同じ段階（%s）%s" % [item[3], _gs.phase_name(), error])
		_check_same(item[1], _norm(_gs.to_save()), "%s：全状態（所属・年俸・途中経過）が一致" % item[3])
		match item[3]:
			"FA":
				var f2: Object = _gs.fa()
				_check(f2 != null and f2.user_bids.has(offer_id) and not f2.resolved,
					"FA：自球団の提示が残っている・締め切り前")
			"契約更改":
				var c2: Object = _gs.contracts()
				_check(c2 != null and int(c2.rows[renew_id]["amount"]) == renew_amount
					and _gs.league.salary_of(renew_id) == renew_amount, "契約更改：変えた提示額のまま")
			"ドラフト":
				var d2: Object = _gs.draft()
				_check(d2 != null and d2.picks.size() == picks_before and d2.current_team() == draft_turn,
					"ドラフト：指名%d人・次の番（%s）が元どおり" % [picks_before, draft_turn])
				d2.run_until_user()
				d2.auto_complete()
				_gs.draft_sync()
		var mine_picks: Array = []
		if _gs.draft() != null:
			for rec: Dictionary in _gs.draft().picks_of(USER):
				mine_picks.append(rec["id"])
		_gs.skip_to_phase(7)  # CAMP
		_gs.advance()
		_check(_gs.year == 2009 and _gs.phase == 0 and _gs.season != null,
			"%s：最後まで進めて2009年の開幕に到達（%s）" % [item[3], _gs.date_text()])
		if item[3] == "ドラフト":
			var missing := 0
			for id: String in mine_picks:
				if _gs.league.team_of.get(id, "") != USER:
					missing += 1
			_check(not mine_picks.is_empty() and missing == 0,
				"ドラフト：自球団の指名%d人が2009年の自球団にいる" % mine_picks.size())
		_gs.advance()
		_check(_gs.day > _gs.season.first_day(), "%s：2009年の試合を進めてもエラーなし（%s）" % [
			item[3], _gs.date_text()])


# --- 3) オートセーブ ----------------------------------------------------------------------

func _check_autosave() -> void:
	print("\n-- 3) オートセーブ --")
	_sg.set("autosave_enabled", true)
	_sg.call("delete", "auto")
	_gs.new_game("中日ドラゴンズ", 2008)
	await _frames(3)
	_check(not _sg.call("exists", "auto"), "新しく始めただけではオートセーブしない")
	_gs.start_fast_forward(_gs.day + 5)
	_check(not _gs.can_save() and not str(_sg.call("save", "slot2")).is_empty(),
		"早送り中はセーブできない（%s）" % _gs.save_block_reason())
	_gs.stop_fast_forward()
	_check(_gs.can_save(), "早送りを止めればセーブできる")
	for i in 2:
		_gs.advance()  # 翌月1日へ（月替わり）
		await _frames(3)
		var info: Dictionary = _sg.call("info", "auto")
		_check(info.get("summary", {}).get("date", "") == _gs.date_text(),
			"月替わりでオートセーブを更新（%s）" % info.get("summary", {}).get("date", "なし"))
	_gs.skip_to_phase(3)  # FA_TRADE（表彰を通る）
	await _frames(3)
	var info2: Dictionary = _sg.call("info", "auto")
	_check(int(info2.get("summary", {}).get("phase", -1)) == 3, "段階の切り替わり（FA）でオートセーブを更新")
	_gs.advance()
	await _frames(3)
	info2 = _sg.call("info", "auto")
	_check(int(info2.get("summary", {}).get("phase", -1)) == 4, "段階の切り替わり（契約更改）でオートセーブを更新（%s）"
		% info2.get("summary", {}).get("text", ""))
	_gs.new_game("広島東洋カープ", 2009)
	var error: String = _sg.call("load_slot", "auto")
	_check(error.is_empty() and _gs.phase == 4 and _gs.team == "中日ドラゴンズ", "オートセーブをロードできる")
	_sg.set("autosave_enabled", false)


# --- 4) 画面（キーボード） ---------------------------------------------------------------

func _check_ui() -> void:
	print("\n-- 4) タイトル・ハブの画面（キーボード） --")
	change_scene_to_file("res://scenes/title/title.tscn")
	await _frames(8)
	var title := current_scene
	var cont: Button = title.get("_continue_button")
	_check(cont != null and cont.visible and _focused() == cont, "タイトル：「続きから」が出てフォーカス")
	await _key(KEY_ENTER)
	var view: Node = title.get("_save_view")
	_check(title.get("_continue_panel").visible and view.is_ancestor_of(_focused()),
		"Enter で枠の一覧（%s）" % _focus_text())
	await _key(KEY_ESCAPE)
	_check(not title.get("_continue_panel").visible and _focused() == cont, "Esc で戻る")
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	_check(_focus_text().begins_with("スロット2"), "↓でスロット2（%s）" % _focus_text().get_slice("\n", 0))
	await _key(KEY_ENTER)
	await _frames(8)
	var hub := current_scene
	_check(hub.name == "Hub" and _gs.phase == 3 and _gs.team == USER, "Enter でロードしてハブ（%s %s）" % [
		_gs.date_text(), _gs.phase_name()])

	for i in 5:
		await _key(KEY_DOWN)
	_check(_menu_key() == "system", "ハブ：↓でシステム")
	await _key(KEY_ENTER)
	var sv: Node = hub.get("_save_view")
	_check(hub.get("_open_key") == "system" and sv.mode() == "save" and _focus_text().begins_with("スロット1"),
		"Enter でセーブ画面（スロット1にフォーカス）")
	var saved_before: String = _sg.call("info", "slot1").get("saved_at", "")
	await _key(KEY_ENTER)
	_check(sv.pending() == "slot1" and _focus_text() == "いいえ", "上書きは確認が出る（いいえにフォーカス）")
	await _key(KEY_ESCAPE)
	_check(sv.pending().is_empty() and hub.get("_open_key") == "system", "Esc で確認を閉じる（画面は開いたまま）")
	await _key(KEY_ENTER)
	await _key(KEY_LEFT)
	_check(_focus_text() == "はい", "←で「はい」")
	await create_timer(1.1).timeout  # 保存日時（秒）が変わるのを待つ
	await _key(KEY_ENTER)
	var info: Dictionary = _sg.call("info", "slot1")
	_check(sv.pending().is_empty() and int(info.get("summary", {}).get("phase", -1)) == 3
		and info.get("saved_at", "") != saved_before, "はい で上書きセーブ（%s）" % info.get("summary", {}).get("text", ""))
	await _key(KEY_E)
	_check(sv.mode() == "load", "E（RB）でロードに切り替え")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_check(_focus_text().begins_with("スロット3"), "↓↓でスロット3")
	await _key(KEY_ENTER)
	_check(sv.pending() == "slot3", "ロードも確認が出る")
	await _key(KEY_LEFT)
	await _key(KEY_ENTER)
	await _frames(8)
	var hub2 := current_scene
	_check(hub2 != hub and hub2.name == "Hub" and _gs.phase == 4, "はい でロードしてハブを作り直す（%s）" % _gs.phase_name())

	# スクショ（ウィンドウ付きのときだけ）：セーブ画面で上書きの確認を出したところ
	for i in 5:
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	await _frames(3)
	var sv2: Control = hub2.get("_save_view")
	var screen: Control = hub2.get_node("%SubScreen")
	var confirm: Control = sv2.get("_confirm_panel")
	var label: Label = sv2.get("_confirm_label")
	# 1280x720 のときのサブ画面の高さ（hub.tscn：上100・下104）に、確認を出した状態の最小の高さが収まる
	# （中身はスクロールの包み %Fit の中なので、中身の最小の高さ＋余白（パネルの余白は包みの内側へ移してある）で測る）
	var need := int(hub2.get_node("%VBox").get_combined_minimum_size().y
		+ hub2.get_node("%Fit").get_theme_stylebox("panel").get_minimum_size().y
		+ screen.get_theme_stylebox("panel").get_minimum_size().y)
	_check(confirm.visible and need <= 720 - 100 - 104 and label.get_line_count() == 1,
		"確認を出してもセーブ画面が枠に収まる（必要な高さ %d / 516、確認の行数 %d）" % [need, label.get_line_count()])
	await _shot("save_view")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	_check(hub2.get("_open_key") == "", "Esc でハブへ戻る")


# --- 補助 ------------------------------------------------------------------------------

func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1


func _check_same(a: Variant, b: Variant, label: String) -> void:
	var diff := _diff(a, b, "")
	_check(diff.is_empty(), label + ("" if diff.is_empty() else "（違い：%s）" % diff))


## JSON にしてから戻し、整数をそろえた形（比べる用）
func _norm(v: Variant) -> Variant:
	return _sg.call("ints", JSON.parse_string(JSON.stringify(v, "", false, true)))


## 最初に違うところのパス（同じなら空）
func _diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s 型 %s / %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		if a.size() != b.size():
			return "%s 項目数 %d / %d" % [path, a.size(), b.size()]
		var ka: Array = a.keys()
		var kb: Array = b.keys()
		for i in ka.size():
			if ka[i] != kb[i]:
				return "%s キーの並び %s / %s" % [path, ka[i], kb[i]]
			var d := _diff(a[ka[i]], b[ka[i]], "%s.%s" % [path, ka[i]])
			if not d.is_empty():
				return d
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s 要素数 %d / %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _diff(a[i], b[i], "%s[%d]" % [path, i])
			if not d.is_empty():
				return d
		return ""
	return "" if a == b else "%s %s / %s" % [path, str(a).left(60), str(b).left(60)]


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focus_text() -> String:
	var c := _focused()
	if c is Button:
		return (c as Button).text
	return "なし" if c == null else "%s %s" % [c.get_class(), c.name]


func _menu_key() -> String:
	var c := _focused()
	if c != null and c.get_parent() != null and c.get_parent().has_signal("chosen"):
		return c.get_parent().get("key")
	return _focus_text()


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String, wait := 0.4) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("スクショ: ", _out.path_join(shot_name + ".png"))
