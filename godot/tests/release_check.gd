extends SceneTree
## 戦力外・引退の確認（ヘッドレス可。ウィンドウ付きで出力先を渡すとスクショも保存）。
## 1) 2008年から2012年のオフまで（2013年の開幕まで）進め、毎年のオフの「戦力外・引退」で次を調べる：
##    - 史実の引退（来季の能力値ファイルにいない選手）が一覧に出る（2008年オフは清原）
##    - CPU球団は来季の見込み（支配下＋新人などの見込み）が70人以内になるよう戦力外を決める
##    - 自球団で選んだ選手が実際にいなくなる（翌年の開幕で自球団にいない）。足りない分は締めるときに自動で選ぶ
##    - 戦力外の選手は、来季の成績（能力値ファイル）があれば市場に入り、無ければ引退。他球団が獲得しうる
##    - 開幕で全球団の支配下が70人以内。市場に残った戦力外の選手は引退し、以後の年に新加入として戻らない
##    - 支配下に空きがあれば自球団も市場の戦力外の選手を獲れる（自分で戦力外にした選手は獲れない）
##    - オフ→翌年の開幕で年・日付の表示が進む
## 2) 2012年オフ、ハブ → 可変ボタン → 戦力外・引退の画面をキーボード・マウスで操作し、ハブの日付が2013年の開幕に追従する
##
##   godot --headless --path godot --script res://tests/release_check.gd -- [出力先]

const USER_TEAM := "読売ジャイアンツ"
const LAST_OFF := 2012
const KIYOHARA := "41343862"  # 清原和博
const LIMIT := 70

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
## 自球団で戦力外にした選手 → その年
var _user_cut := {}
var _cpu_signed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	await _check_years()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_years() -> void:
	print("== 2008〜%d年のオフの戦力外・引退（自球団：%s） ==" % [LAST_OFF, USER_TEAM])
	_gs.new_game(USER_TEAM)
	var league: Variant = _gs.league
	while true:
		var y: int = _gs.year
		_gs.advance_through(_gs.season_last_day())
		while _gs.phase != _gs.Phase.CONTRACT:
			_gs.advance()
		_check(_gs.button_text() == "契約更改", "%d年オフ：契約更改の段階" % y)
		_gs.contract_resolve()
		_check(_gs.button_text() == "戦力外・引退へ", "%d年オフ：次は戦力外・引退（%s）" % [y, _gs.button_text()])
		if y == 2010 or y == LAST_OFF:
			_inject(12)
		if y == LAST_OFF:
			await _check_ui(y)
			_check_opening(y + 1)
			break
		_gs.advance()
		_check(_gs.phase == _gs.Phase.RELEASE and _gs.release_open() and _gs.button_text() == "戦力外・引退",
				"%d年オフ：戦力外・引退の段階（ボタン=%s）" % [y, _gs.button_text()])
		_check_stage(y)
		_choose_user(y)
		_gs.release_resolve()
		# 締めると次はドラフトの段階。その前に可変ボタンが一度だけ「作戦会議」（作業37）
		_check(not _gs.release_open() and _gs.button_text() == "作戦会議", "%d年オフ：締めると次はドラフト（作戦会議 %s）" % [
			y, _gs.button_text()])
		_after_resolve(y)
		while _gs.phase != _gs.Phase.SEASON:
			_gs.advance()
		_check_opening(y + 1)
	_check(_cpu_signed >= 1, "戦力外の選手を他球団が獲得した（%d人）" % _cpu_signed)
	var back := 0
	for e: Dictionary in league.log:
		if e["kind"] in ["rookie", "join"] and league.released.has(e["id"]) \
				and int(league.released[e["id"]]["year"]) < int(e["year"]):
			back += 1
			print("  戻ってきた: ", e["text"])
	_check(back == 0, "戦力外で引退した選手が新加入として戻ってこない")


## テスト用：自球団を上限超えにするため、CPU球団（阪神）の選手を n 人自球団へ移す
func _inject(n: int) -> void:
	var league: Variant = _gs.league
	var moved := 0
	for id: String in league.players_of("阪神タイガース"):
		if moved >= n:
			break
		if id in league.plan_retirements():
			continue
		league.team_of[id] = USER_TEAM
		moved += 1
	_gs._sync_roster()
	print("  （テスト用に阪神の%d人を自球団へ移す）" % moved)


## 段階に入った直後：史実の引退の一覧・CPU球団の戦力外・市場
func _check_stage(y: int) -> void:
	var league: Variant = _gs.league
	var r: Variant = _gs.releases()
	var retire_events: Array = league.events(y, "retire")
	var listed := {}
	for row: Dictionary in r.retired_rows:
		listed[row["id"]] = true
	var missing := 0
	for e: Dictionary in retire_events:
		if not listed.has(e["id"]):
			missing += 1
	_check(retire_events.size() > 10 and missing == 0, "%d年オフ：史実の引退 %d人が一覧に出る" % [y, retire_events.size()])
	if y == 2008:
		_check(listed.has(KIYOHARA), "2008年オフ：清原が引退の一覧に出る")
	var mine := 0
	for row: Dictionary in r.retired_rows:
		if row["team"] == USER_TEAM:
			mine += 1
	if mine > 0:
		_check(r.retired_rows[0]["team"] == USER_TEAM, "引退の一覧は自球団が先（%d人）" % mine)
	# CPU球団の戦力外
	var over: Array[String] = []
	var parts: Array[String] = []
	for t: String in _gd.teams():
		var reg: int = league.registered_count(t)
		var inc: int = league.incoming(t)
		parts.append("%s%d+%d" % [_gd.short_name(t), reg, inc])
		if t != USER_TEAM and reg + inc > LIMIT:
			over.append("%s %d+%d" % [_gd.short_name(t), reg, inc])
	print("  支配下＋見込み：", " ".join(parts))
	print("  CPU球団の戦力外 %d人（市場へ %d人）、自球団：あと %d人" % [r.cpu_rows.size(),
		r.cpu_rows.filter(func(x: Dictionary) -> bool: return x["market"]).size(), _gs.release_need()])
	_check(r.cpu_rows.size() > 0, "%d年オフ：CPU球団が戦力外を決める（%d人）" % [y, r.cpu_rows.size()])
	_check(over.is_empty(), "%d年オフ：CPU球団の来季の見込みが%d人以内 %s" % [y, LIMIT, str(over)])
	var wrong := 0
	for row: Dictionary in r.cpu_rows:
		var id: String = row["id"]
		if league.team_of.get(id, "") == row["team"]:
			wrong += 1
		elif row["market"] and not (id in league.market or league.team_of.has(id)):
			wrong += 1
		elif not row["market"] and not league.retired.has(id):
			wrong += 1
	_check(wrong == 0, "%d年オフ：戦力外の選手は市場（来季の成績あり）か引退" % y)
	# 来季の成績の有無と市場の対応
	var next: Dictionary = _gd.peek_ratings(y + 1, "pre")
	var next_ids := {}
	for p: Dictionary in next.get("players", []):
		next_ids[p["id"]] = true
	var mismatch := 0
	for row: Dictionary in r.cpu_rows:
		if bool(row["market"]) != next_ids.has(row["id"]):
			mismatch += 1
	_check(mismatch == 0, "%d年オフ：市場に入るのは来季の能力値ファイルにいる選手だけ" % y)


## 自球団：保護された選手は選べない、必要な人数より多めに（2009年は2人多く）選ぶ
func _choose_user(y: int) -> void:
	var league: Variant = _gs.league
	var r: Variant = _gs.releases()
	var need: int = _gs.release_need()
	for id: String in r.protected:
		_check(not _gs.release_toggle(id).is_empty(), "保護された選手（%s：%s）は戦力外にできない" % [
			league.names[id], r.protected[id]])
		break
	var extra := 2 if y == 2009 else 0
	var want := need + extra
	if y == 2010 and need > 1:
		want = need - 1   # 足りない分は締めるときに自動で選ぶ
	var chosen := 0
	for id: String in r.order:
		if chosen >= want:
			break
		if r.protected.has(id) or r.ikusei.has(id):
			continue
		_check(_gs.release_toggle(id).is_empty(), "%sを戦力外に選ぶ" % league.names[id])
		chosen += 1
	# 付けて外す
	if r.order.size() > 0:
		var last: String = r.order[-1]
		if not r.protected.has(last):
			_gs.release_toggle(last)
			_gs.release_toggle(last)
			_check(not r.marked.has(last), "印を外せる")
	print("  自球団：必要 %d人・選んだ %d人（残り %d人）" % [need, chosen, _gs.release_need()])
	if y == 2010:
		_check(need >= 2 and _gs.release_need() == 1, "2010年オフ：上限超え（必要 %d人）で1人足りないまま締める" % need)
	for id: String in r.marked:
		_user_cut[id] = y


func _after_resolve(y: int) -> void:
	var league: Variant = _gs.league
	var r: Variant = league.releases
	_check(r.user_rows.size() == r.marked.size(), "%d年オフ：選んだ %d人（自動を含む）を戦力外に" % [y, r.user_rows.size()])
	var still := 0
	for row: Dictionary in r.user_rows:
		_user_cut[row["id"]] = y
		if league.team_of.get(row["id"], "") == USER_TEAM:
			still += 1
	_check(still == 0, "%d年オフ：戦力外にした自球団の選手は所属から外れる" % y)
	_check(league.registered_count(USER_TEAM) + league.incoming(USER_TEAM) <= LIMIT,
			"%d年オフ：自球団の来季の見込み %d+%d が%d人以内" % [y, league.registered_count(USER_TEAM),
				league.incoming(USER_TEAM), LIMIT])
	var own := ""
	for row: Dictionary in r.user_rows:
		if row["market"]:
			own = row["id"]
	if not own.is_empty():
		_check(not _gs.sign_foreign(own).is_empty(), "自分で戦力外にした選手は獲れない")
	if y == 2009:
		var target := ""
		for id: String in league.released_in_market():
			if league.market_info[id]["released"] != USER_TEAM:
				target = id
				break
		_check(not target.is_empty() and _gs.user_room() > 0, "2009年オフ：自球団に空き（%d人）と市場の戦力外の選手" % _gs.user_room())
		if not target.is_empty():
			var error: String = _gs.sign_foreign(target)
			_check(error.is_empty() and league.team_of.get(target, "") == USER_TEAM, "市場の戦力外の選手（%s）を自球団が獲得 %s" % [
				league.names[target], error])
	if y == 2010:
		# 空きが無ければ獲れない
		var room: int = _gs.user_room()
		var target := ""
		for id: String in league.released_in_market():
			if league.market_info[id]["released"] != USER_TEAM:
				target = id
		if room <= 0 and not target.is_empty():
			_check(not _gs.sign_foreign(target).is_empty(), "支配下に空きが無いと獲れない")


## 開幕：全球団の支配下が70人以内、自球団で戦力外にした選手がいない、日付が進む
func _check_opening(y: int) -> void:
	var league: Variant = _gs.league
	_check(_gs.phase == _gs.Phase.SEASON and _gs.year == y and _gs.month_text() != "オフ"
			and _gs.date_text().begins_with("%d年 " % y), "%d年の開幕へ（%s）" % [y, _gs.date_text()])
	var parts: Array[String] = []
	var over: Array[String] = []
	for t: String in _gd.teams():
		var n: int = league.registered_count(t)
		parts.append("%s%d" % [_gd.short_name(t), n])
		if n > LIMIT:
			over.append("%s%d" % [_gd.short_name(t), n])
	print("%d年開幕 支配下：%s" % [y, " ".join(parts)])
	_check(over.is_empty(), "%d年開幕：全球団の支配下が%d人以内 %s" % [y, LIMIT, str(over)])
	var back := 0
	for id: String in _user_cut:
		if league.team_of.get(id, "") == USER_TEAM:
			back += 1
	_check(back == 0, "%d年開幕：自球団で戦力外にした選手（%d人）が自球団にいない" % [y, _user_cut.size()])
	var signed: Array = league.events(y - 1, "release_sign")
	signed.append_array(league.events(y, "release_sign"))
	var cpu := signed.filter(func(e: Dictionary) -> bool: return e["to"] != USER_TEAM).size()
	_cpu_signed += cpu
	var unsigned: Array = league.events(y, "release_unsigned")
	var still := 0
	for e: Dictionary in unsigned:
		if league.team_of.has(e["id"]) or not league.retired.has(e["id"]):
			still += 1
	print("  戦力外からの獲得：CPU %d人、未契約で引退 %d人" % [cpu, unsigned.size()])
	_check(still == 0, "%d年開幕：市場に残った戦力外の選手は引退" % y)
	_check(_gs.season != null and _gs.season.teams.size() == 12, "%d年開幕：12球団の編成" % y)


# --- 2) 画面の操作 -------------------------------------------------------------------------

func _check_ui(y: int) -> void:
	print("\n== %d年オフ：戦力外・引退の画面 ==" % y)
	var league: Variant = _gs.league
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene
	_check(hub.get("_year_label").text == str(y) and hub.get("_month_label").text == "オフ", "ハブ：%d年 オフ" % y)
	_check(_focus_key() == "advance", "ハブ：可変ボタンにフォーカス（%s）" % _focus_key())
	await _key(KEY_ENTER)
	_check(_gs.phase == _gs.Phase.RELEASE and hub.get("_open_key") == "release",
			"可変ボタン「戦力外・引退へ」で戦力外・引退の画面（%s / %s）" % [_gs.phase_name(), hub.get("_open_key")])
	_check(str(hub.get("_sub_title_label").text).contains("%d年オフ" % y), "見出しが %d年オフ" % y)
	var view: Node = hub.get("_release_view")
	var r: Variant = _gs.releases()
	_check(view.get("_tab") == "p" and view.list_ids().size() > 0, "投手タブに自球団の投手（%d人）" % view.list_ids().size())
	var first: String = view.list_ids()[0]
	_check(_focused() == view.get("_tags").get(first), "先頭の札にフォーカス")
	await _shot("r1_list")
	await _key(KEY_ENTER)
	_check(view.selected_id() == first, "Enter で札を選ぶ")
	await _key(KEY_ENTER)
	_check(_detail() != null, "もう一度 Enter で選手詳細")
	await _key(KEY_ESCAPE)
	_check(_detail() == null and view.selected_id() == first, "Esc で選手詳細を閉じる")
	# 戦力外にする（キーボード：十字キー↑で上のボタンへ → Enter）
	var target := first
	if r.protected.has(first) or r.ikusei.has(first):
		target = ""
		for id: String in view.list_ids():
			if not r.protected.has(id) and not r.ikusei.has(id):
				target = id
				break
		await _click(view.get("_tags").get(target))
	_check(view.selected_id() == target, "戦力外にする選手を選ぶ（%s）" % league.names.get(target, target))
	var need_before: int = _gs.release_need()
	_check(need_before >= 2, "上限を超えている（あと%d人）" % need_before)
	view.get("_toggle_button").grab_focus()
	await _key(KEY_ENTER)
	_check(r.marked.has(target), "「戦力外にする」で印が付く（%s）" % league.names[target])
	_check(_gs.release_need() == maxi(0, need_before - 1), "あと何人の表示が減る（%d → %d）" % [need_before, _gs.release_need()])
	await _shot("r2_marked")
	# マウスで別の選手（野手タブ）
	await _key(KEY_E)
	_check(view.get("_tab") == "b", "E（RB）で野手タブ")
	var fielder := ""
	for id: String in view.list_ids():
		if not r.protected.has(id) and not r.ikusei.has(id):
			fielder = id
			break
	await _click(view.get("_tags").get(fielder))
	await _click(view.get("_toggle_button"))
	_check(r.marked.has(fielder), "クリックで野手（%s）を戦力外に" % league.names[fielder])
	await _click(view.get("_toggle_button"))
	_check(not r.marked.has(fielder), "もう一度クリックで取り消し")
	await _key(KEY_E)
	_check(view.get("_tab") == "retire" and view.list_ids().size() == r.retired_rows.size(),
			"E で引退（史実）タブ（%s：%d人／引退%d人）" % [view.get("_tab"), view.list_ids().size(), r.retired_rows.size()])
	await _shot("r3_retire")
	await _key(KEY_E)
	_check(view.get("_tab") == "cpu" and view.list_ids().size() == r.cpu_rows.size(),
			"E で他球団の戦力外（%d人）" % view.list_ids().size())
	await _shot("r4_cpu")
	await _key(KEY_ESCAPE)
	_check(hub.get("_open_key") == "" and _gs.button_text() == "戦力外・引退", "Esc でハブへ（ボタン=%s）" % _gs.button_text())
	await _key(KEY_ENTER)
	_check(hub.get("_open_key") == "release" and _gs.phase == _gs.Phase.RELEASE, "可変ボタンで戦力外・引退の画面に戻る")
	# 確定：足りないときは1回目で確認、2回目で残りを自動で選んで締める
	var close: Button = view.get("_close_button")
	_check(_gs.release_need() > 0, "まだ上限を超えている（あと%d人）" % _gs.release_need())
	await _click(close)
	_check(not r.resolved and str(view.get("_status_label").text).contains("自動"), "足りないときは確認を出す（%s）" %
		view.get("_status_label").text)
	await _shot("r5_confirm")
	await _key(KEY_ESCAPE)
	_check(not r.resolved and hub.get("_open_key") == "release" and not view.get("_confirm_pending"),
			"Esc で確認をやめる（画面はそのまま）")
	var marked_before: int = r.marked.size()
	await _click(view.get("_auto_button"))
	_check(_gs.release_need() == 0 and r.marked.size() > marked_before, "「おまかせで選ぶ」で残り %d人を選ぶ" % [
		r.marked.size() - marked_before])
	await _click(close)
	_check(r.resolved and _gs.release_need() == 0, "「戦力外を確定」で締める")
	_check(not league.team_of.has(target) or league.team_of[target] != USER_TEAM, "選んだ選手（%s）が自球団からいなくなる" %
		league.names[target])
	for row: Dictionary in r.user_rows:
		_user_cut[row["id"]] = y
	await _shot("r6_done")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	_check(_gs.button_text() == "作戦会議", "締めると可変ボタンは「作戦会議」（ドラフトの前。%s）" % _gs.button_text())
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	await _frames(3)
	_check(hub.get("_year_label").text == str(y + 1) and hub.get("_month_label").text != "オフ",
			"ハブの日付が%d年の開幕に追従（%s %s）" % [y + 1, hub.get("_year_label").text, hub.get("_month_label").text])


# --- 共通 --------------------------------------------------------------------------------

func _focus_key() -> String:
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
