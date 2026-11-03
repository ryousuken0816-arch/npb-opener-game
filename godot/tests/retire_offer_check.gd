extends SceneTree
## 契約更改・戦力外の「引退を勧める」の確認（ヘッドレス。docs/AUTORUN.md 作業56）
## 1) 2008年オフ（巨人）：33歳以上の選手だけ勧められる。受け入れる見込みは年齢が高いほど高く、能力が高いほど低い。
##    勧めると受け入れ・断りの両方が起きる。受け入れた選手はその場で引退（市場に出ない・速報が出る）、
##    断った選手は同じオフにもう一度は勧められず、戦力外は選べる
## 2) 画面：契約更改・戦力外の画面で33歳以上の選手を選ぶと「引退を勧める　受け入れ ★…」、押すと結果が出る
## 3) セーブ→ロードで勧めた結果・引退が一致。翌年の開幕で引退した選手はどの球団にもいない・市場にいない
## 4) 2027年オフ（史実の無い年）：CPU球団の引退の勧めで引退した選手は市場に出ない
##
##   godot --headless --path godot --script res://tests/retire_offer_check.gd

const USER := "読売ジャイアンツ"
const HUB_SCENE := "res://scenes/hub/hub.tscn"

var _failures := 0
var _gs: Node
var _gd: Node
var _sg: GDScript
var _fa: GDScript      ## FreeAgency（テストはオートロードより先にコンパイルされるので実行時に読む）
var _salary: GDScript  ## Salary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_sg = load("res://scripts/save_game.gd")
	_fa = load("res://sim/free_agency.gd")
	_salary = load("res://sim/salary.gd")
	_sg.set("dir", _sg.call("test_dir", "user://test_saves_retire_offer"))
	_sg.set("autosave_enabled", false)
	seed(56)
	_gs.new_game(USER, 2008)
	_gs.skip_to_phase(_gs.Phase.CONTRACT)
	_check(_gs.phase == _gs.Phase.CONTRACT and _gs.contract_with_release(), "2008年オフ：契約更改・戦力外の段階")
	var league: Object = _gs.league
	var vets: Array[String] = []
	var young := ""
	for id: String in league.players_of(USER):
		var age: int = _fa.age_of(_gd.player(id), 2008)
		if age >= 33:
			vets.append(id)
		elif young.is_empty() and age > 0 and age <= 28:
			young = id
	_check(vets.size() >= 4, "33歳以上の選手が4人以上（%d人）" % vets.size())
	_check(not _gs.retire_offer_block(young).is_empty(), "33歳未満は勧められない（%s：%s）" % [
		league.names.get(young, young), _gs.retire_offer_block(young)])
	_check_chance(vets)
	await _check_ui()
	print("\n-- 1) 受け入れ・断り --")
	var accepted: Array[String] = []
	var declined: Array[String] = []
	for id in vets:
		if not _gs.retire_offer_block(id).is_empty():
			continue
		var chance: float = _gs.retire_offer_chance(id)
		var res: Dictionary = _gs.retire_offer(id)
		print("  %s（%d歳、見込み%d%%）：%s" % [league.names[id], _fa.age_of(_gd.player(id), 2008),
			roundi(chance * 100.0), res["text"]])
		(accepted if res["accepted"] else declined).append(id)
		if accepted.size() >= 2 and declined.size() >= 2:
			break
	_check(not accepted.is_empty() and not declined.is_empty(), "受け入れ %d人・断り %d人（両方起きる）" % [
		accepted.size(), declined.size()])
	var r: Object = _gs.releases()
	for id in accepted:
		_check(not league.team_of.has(id) and league.retired.has(id) and id not in league.market,
			"%sはその場で引退（所属なし・市場にいない）" % league.names[id])
		var news := false
		for a: Dictionary in _gs.news.articles:
			if id in a["players"] and str(a["headline"]).contains("現役引退を表明") and a["mine"]:
				news = true
		_check(news, "%s：自球団の速報「現役引退を表明」" % league.names[id])
		_check(not _gs.release_toggle(id).is_empty(), "引退した選手は戦力外に選べない")
	for id in declined:
		_check(league.team_of.get(id, "") == USER and not _gs.retire_offer(id)["ok"],
			"%sは断ったので残り、同じオフにもう一度は勧められない" % league.names[id])
		_check(_gs.release_toggle(id).is_empty() and r.marked.has(id), "断った%sを戦力外に選び直せる" % league.names[id])
		_gs.release_toggle(id)
	print("\n-- 3) セーブ／ロード --")
	var asked: Dictionary = r.retire_asked.duplicate()
	_check(str(_sg.call("save", "slot1")).is_empty(), "セーブ")
	_gs.new_game("阪神タイガース", 2010)
	_check(str(_sg.call("load_slot", "slot1")).is_empty(), "ロード")
	var r2: Object = _gs.releases()
	_check(r2 != null and r2.retire_asked == asked, "ロードしても勧めた結果が同じ（%s）" % str(r2.retire_asked if r2 != null else {}))
	for id in accepted:
		_check(_gs.league.retired.has(id) and not _gs.league.team_of.has(id), "ロードしても%sは引退" % _gs.league.names[id])
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_check(_gs.year == 2009, "2009年の開幕（%s）" % _gs.date_text())
	for id in accepted:
		_check(not _gs.league.team_of.has(id) and id not in _gs.league.market and _gs.league.retired.has(id),
			"2009年：%sはどの球団にも市場にもいない" % _gs.league.names[id])
	_sg.call("delete", "slot1")
	_check_cpu()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## 受け入れる見込み：年齢が高いほど・能力が低いほど高い
func _check_chance(vets: Array[String]) -> void:
	var league: Object = _gs.league
	var rows: Array = []
	for id in vets:
		var p: Dictionary = _gd.player(id)
		rows.append([id, _fa.age_of(p, 2008), float(_salary.ability(p)[0]), _gs.retire_offer_chance(id)])
	var lines: Array[String] = []
	for row: Array in rows:
		lines.append("%s %d歳 z%+.1f %d%%" % [league.names[row[0]], row[1], row[2], roundi(row[3] * 100.0)])
	print("  見込み：", "、".join(lines))
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	_check(float(rows[0][3]) >= float(rows[-1][3]) or float(rows[0][2]) > float(rows[-1][2]),
		"年齢の高い選手（%s %d歳）ほど受け入れやすい（%d%% ≧ %d%%）" % [league.names[rows[0][0]], rows[0][1],
			roundi(rows[0][3] * 100.0), roundi(rows[-1][3] * 100.0)])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[2] > y[2])
	_check(float(rows[0][3]) <= float(rows[-1][3]) or int(rows[0][1]) > int(rows[-1][1]),
		"能力の高い選手（%s）ほど断りやすい（%d%% ≦ %d%%）" % [league.names[rows[0][0]], roundi(rows[0][3] * 100.0),
			roundi(rows[-1][3] * 100.0)])


## 画面：33歳以上の選手を選ぶと「引退を勧める　受け入れ ★…」、押すと結果が出てボタンが押せなくなる
func _check_ui() -> void:
	print("\n-- 2) 画面 --")
	change_scene_to_file(HUB_SCENE)
	for i in 6:
		await process_frame
	var hub := current_scene
	hub.call("_open_sub_screen", "contract")
	for i in 3:
		await process_frame
	var view: Node = hub.get("_contract_view")
	var target := ""
	var young := ""
	for key in ["p", "b"]:
		view.call("_show_tab", key)
		for id: String in view.list_ids():
			if _gs.retire_offer_block(id).is_empty() and target.is_empty():
				target = id
			elif young.is_empty() and _fa.age_of(_gd.player(id), 2008) < 33:
				young = id
		if not target.is_empty():
			break
	_check(not target.is_empty(), "一覧に33歳以上の選手がいる")
	if target.is_empty():
		return
	var button: Button = view.get("_retire_button")
	if not young.is_empty():
		view.select_player(young)
		_check(button.disabled, "33歳未満の選手では「引退を勧める」が押せない（%s）" % button.text)
	view.select_player(target)
	_check(button.visible and not button.disabled and button.text.contains("★"),
		"33歳以上の選手を選ぶと「%s」" % button.text)
	view.offer_retire()
	var r: Object = _gs.releases()
	_check(r.retire_asked.has(target) and button.disabled, "押すと結果が出てもう押せない（%s）" % view.get("_status_label").text)
	change_scene_to_file("res://scenes/title/title.tscn")
	for i in 3:
		await process_frame


## 史実の無い年：CPU球団の引退の勧めで引退した選手は市場に出ない
func _check_cpu() -> void:
	print("\n-- 4) 2027年オフ（史実の無い年）のCPU球団 --")
	_gs.new_game(USER, 2027)
	_gs.skip_to_phase(_gs.Phase.CONTRACT)
	var r: Object = _gs.releases()
	var league: Object = _gs.league
	var offered: Array = r.cpu_rows.filter(func(x: Dictionary) -> bool: return x.get("retire_offer", false))
	var bad := 0
	for row: Dictionary in offered:
		if league.team_of.has(row["id"]) or row["id"] in league.market or not league.retired.has(row["id"]):
			bad += 1
	print("  CPU球団の戦力外 %d人のうち引退の勧めで引退 %d人" % [r.cpu_rows.size(), offered.size()])
	_check(bad == 0, "CPU球団の引退の勧めで引退した選手（%d人）は所属・市場にいない" % offered.size())


func _check(ok: bool, label: String) -> void:
	print(("  OK  " if ok else "  NG  ") + label)
	if not ok:
		_failures += 1
