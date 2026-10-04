extends SceneTree
## ドラフトの確認（ヘッドレス可。ウィンドウ付きで出力先を渡すとスクショも保存）。docs/AUTORUN.md 作業5「確認」：
## 1) 2008年開始（巨人）：すぐドラフトへ → 候補は2008年秋の史実の指名選手全員（本指名・育成）。2つのランクが付く。
##    CPU球団の入札を見て、CPU球団が入札した他球団の史実の1位を自球団も入札 → 競合して抽選になる（自球団が抽選に入る）。
##    残りはおまかせ → CPU球団はそれぞれ史実の人数（本指名・育成）を指名、指名されなかった候補はいない（全員指名）。
##    翌年（2009年）の開幕で、自球団の指名選手が自球団にいる・育成指名は支配下に数えない・年俸が順位どおり
## 2) 2024年開始（巨人）：ハブ → 可変ボタン → ドラフトの画面で、宗山塁（史実は楽天、5球団競合）を1位入札 → 抽選の演出。
##    並び替えが全項目で効く（列の見出しのキーすべて、昇順・降順）・絞り込み。2位以降は自球団の番で止まり、画面から指名・
##    選択終了。結果まとめ（指名一覧）。翌年（2025年）の開幕で指名選手が自球団の編成にいて、シーズンを進めると試合に出る
## 3) 2025年開始（日本ハム）：すぐドラフトへ → ドラフトの段階で候補がいる → 次へ進むとおまかせで終わり、2026年の春季キャンプ
##
##   godot --headless --path godot --script res://tests/draft_check.gd -- [出力先]

const USER := "読売ジャイアンツ"
const MUNETAKA := "宗山 塁"

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
## class_name を型として書くとオートロードより先にコンパイルされて失敗するので、実行時に読む
var _ds: GDScript
var _dv: GDScript
var _salary: GDScript
var _done := 3
var _first := 0
var _waiver := 1
var _ikusei := 2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_dv = load("res://scenes/hub/draft_view.gd")
	_salary = load("res://sim/salary.gd")
	_done = _ds.Stage["DONE"]
	_first = _ds.Stage["FIRST"]
	_waiver = _ds.Stage["WAIVER"]
	_ikusei = _ds.Stage["IKUSEI"]
	_check_2008()
	await _check_2024_ui()
	_check_2025()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


# --- 1) 2008年 ----------------------------------------------------------------------------

func _check_2008() -> void:
	print("== 2008年開始・すぐドラフトへ（%s） ==" % USER)
	_gs.new_game(USER, 2008)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	_check(d != null and _gs.draft_open() and _gs.button_text() == "ドラフト会議",
		"2008年オフ：ドラフトの段階でドラフト会議が開いている（ボタン=%s）" % _gs.button_text())
	if d == null:
		return
	var rows: Array = _ds.draft_rows(2008)
	var ikusei := 0
	for c: Dictionary in d.candidates:
		if c["hist_ikusei"]:
			ikusei += 1
	_check(d.candidates.size() == rows.size() and ikusei > 0,
		"候補は2008年の史実の指名選手全員（%d人／一覧%d人、うち育成%d人）" % [d.candidates.size(), rows.size(), ikusei])
	var no_rank := 0
	for c: Dictionary in d.candidates:
		if not c["hyouka_rank"] in _ds.RANK_LETTERS or not c["future_rank"] in _ds.RANK_LETTERS:
			no_rank += 1
	_check(no_rank == 0, "全候補に当時の評価・将来性のランク（S〜G）")
	var asano: Dictionary = _find(d, "浅村 栄斗")
	_check(not asano.is_empty() and asano["hyouka_rank"] == "C",
		"浅村（2008年3位）の当時の評価はC（%s）、将来性 %s" % [asano.get("hyouka_rank", "?"), asano.get("future_rank", "?")])
	var ota: Dictionary = _find(d, "大田 泰示")
	_check(not ota.is_empty() and ota["hyouka_rank"] == "A", "大田泰示（1位・2球団競合）の当時の評価はA（%s）" % \
		ota.get("hyouka_rank", "?"))
	var room_before: int = _gs.league.room(USER)
	# CPU球団の入札を見て、CPU球団が入札した他球団の史実の1位に自球団も入札する
	var bids: Dictionary = d.cpu_first_bids()
	var count := {}
	for t: String in bids:
		count[bids[t]] = int(count.get(bids[t], 0)) + 1
	var target := ""
	for id: String in count:
		var c: Dictionary = d.by_id[id]
		if c["hist_round"] == 1 and not c["hist_ikusei"] and c["hist_team"] != USER:
			if target.is_empty() or count[id] > count[target]:
				target = id
	_check(not target.is_empty(), "CPU球団が他球団の史実の1位に入札している（%s %d球団）" % [
		d.by_id.get(target, {}).get("name", "?"), int(count.get(target, 0))])
	if target.is_empty():
		return
	var error: String = d.user_bid(target)
	_check(error.is_empty(), "自球団が史実の他球団（%s）の1位 %s を入札できる %s" % [
		_gd.short_name(d.by_id[target]["hist_team"]), d.by_id[target]["name"], error])
	d.run_first_wave()
	var lot := {}
	for l: Dictionary in d.lotteries:
		if l["id"] == target:
			lot = l
	_check(not lot.is_empty() and USER in lot["teams"] and lot["winner"] in lot["teams"],
		"競合して抽選（%s：%s → %s）" % [d.by_id[target]["name"], ", ".join(_shorts(lot.get("teams", []))),
			_gd.short_name(lot.get("winner", ""))])
	_check(d.by_id[target]["picked_by"] == lot.get("winner", "?"), "抽選の勝者が交渉権を得る")
	_gs.draft_resolve()
	_check(not _gs.draft_open() and d.resolved and d.stage == _done, "残りはおまかせで終わる")
	_check_quota(d, "2008年")
	_check(d.remaining().is_empty(), "候補は全員どこかが指名（未指名 %d人）" % d.remaining().size())
	_check(_gs.button_text() == "春季キャンプへ", "終わると可変ボタンは春季キャンプへ（%s）" % _gs.button_text())
	var mine: Array = d.picks_of(USER)
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	var league: Variant = _gs.league
	var present := 0
	var ik_ok := true
	var salary_ok := true
	var debut09: Dictionary = _gd.load_debut_years(2009)
	for rec: Dictionary in mine:
		if league.team_of.get(rec["id"], "") == USER:
			present += 1
		var p: Dictionary = _gd.player(rec["id"])
		if rec["ikusei"] != league.is_ikusei(rec["id"], p, 2009, debut09):
			ik_ok = false
		var c: Dictionary = d.by_id[rec["id"]]
		var expected: int = _salary.rookie({"round": rec["round"], "high_school": c["career"] == "高校生",
			"ikusei": rec["ikusei"]}, 2009)
		if league.salary_of(rec["id"]) != expected:
			salary_ok = false
	_check(present == mine.size() and mine.size() > 0, "2009年の開幕：自球団の指名選手 %d/%d人が自球団にいる" % [
		present, mine.size()])
	_check(ik_ok, "育成指名だけが育成（支配下に数えない）")
	_check(salary_ok, "新人の年俸は指名順位どおり")
	_check(_gs.year == 2009 and _gs.date_text().begins_with("2009年"), "2009年の開幕（%s）" % _gs.date_text())
	var team_roster: Variant = _gs.season.teams.get(USER)
	var in_sim := 0
	for rec: Dictionary in mine:
		if team_roster != null and team_roster.by_id.has(rec["id"]):
			in_sim += 1
	_check(in_sim == mine.size(), "指名選手が2009年の自球団の編成（試合の選手）に入っている（%d/%d）" % [in_sim, mine.size()])
	var cut_back := 0
	for e: Dictionary in league.events(2009, "join"):
		if league.draft_unsigned.has(league.norm_name(e["name"])):
			cut_back += 1
	_check(cut_back == 0, "指名されなかった候補は翌年も入団しない")
	print("  room（ドラフト前）=", room_before)


func _find(d: RefCounted, name: String) -> Dictionary:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c
	return {}


func _shorts(teams: Array) -> Array[String]:
	var result: Array[String] = []
	for t: String in teams:
		result.append(_gd.short_name(t))
	return result


## CPU球団はそれぞれ史実の人数（本指名・育成）を指名した
func _check_quota(d: RefCounted, label: String) -> void:
	var bad: Array[String] = []
	for t: String in d.teams:
		if t == d.user_team:
			continue
		var reg := 0
		var ik := 0
		for rec: Dictionary in d.picks_of(t):
			if rec["ikusei"]:
				ik += 1
			else:
				reg += 1
		if reg != int(d.quota[t]["reg"]) or ik != int(d.quota[t]["ikusei"]):
			bad.append("%s %d/%d 育成%d/%d" % [_gd.short_name(t), reg, d.quota[t]["reg"], ik, d.quota[t]["ikusei"]])
	_check(bad.is_empty(), "%s：CPU球団はそれぞれ史実の人数を指名（本指名・育成）%s" % [label, " ".join(bad)])


# --- 2) 2024年・画面 -----------------------------------------------------------------------

func _check_2024_ui() -> void:
	print("== 2024年開始・ドラフトの画面（%s） ==" % USER)
	_gs.new_game(USER, 2024)
	_gs.skip_to_phase(_gs.Phase.RELEASE)
	_gs.release_resolve()
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_on_menu_chosen", "advance")
	await _frames(3)
	var d: RefCounted = _gs.draft()
	var view: Node = _find_draft_view(hub)
	_check(d != null and view != null and view.is_visible_in_tree(),
		"可変ボタン「ドラフトへ」でドラフトの画面が開く（段階=%s）" % _gs.phase_name())
	if d == null or view == null:
		return
	view.set("instant", true)
	_check(view.call("overlay_visible"), "開幕の演出が出る")
	await _shot("d0_opening")
	view.call("finish_overlays")
	await _frames(2)
	await _shot("d1_list")
	# 並び替え
	var bad: Array[String] = []
	for key: String in _dv.SORT_KEYS:
		for desc: bool in [true, false]:
			view.call("set_sort", key, desc)
			var ids: Array = view.call("list_ids")
			var prev: Variant = null
			for id: String in ids:
				var v: Variant = _ds.sort_value(d.by_id[id], key)
				if prev != null and ((desc and v > prev) or (not desc and v < prev)):
					bad.append("%s%s" % [key, "▼" if desc else "▲"])
					break
				prev = v
			if ids.size() != d.candidates.size():
				bad.append("%s 件数%d" % [key, ids.size()])
	_check(bad.is_empty(), "並び替えが全項目（%d項目×昇順・降順）で効く %s" % [_dv.SORT_KEYS.size(), " ".join(bad)])
	view.call("set_filter", "投手")
	var pitchers_only := true
	for id: String in view.call("list_ids"):
		if d.by_id[id]["pos"] != "投手":
			pitchers_only = false
	_check(pitchers_only and not view.call("list_ids").is_empty(), "絞り込み（投手）")
	view.call("set_filter", "all")
	view.call("set_sort", "hyouka", true)
	# 宗山を1位入札
	var mune: Dictionary = _find(d, MUNETAKA)
	_check(not mune.is_empty() and mune["hyouka_rank"] == "S", "宗山塁（5球団競合）の当時の評価はS（%s）" % \
		mune.get("hyouka_rank", "?"))
	var kanemaru: Dictionary = _find(d, "金丸 夢斗")
	_check(not kanemaru.is_empty() and kanemaru["hyouka_rank"] == "S", "金丸夢斗（4球団競合）の当時の評価はS（%s）" % \
		kanemaru.get("hyouka_rank", "?"))
	if mune.is_empty():
		return
	var bids: Dictionary = d.cpu_first_bids()
	var rivals := 0
	for t: String in bids:
		if bids[t] == mune["id"]:
			rivals += 1
	view.call("select_candidate", mune["id"])
	await _frames(2)
	view.call("press_action")
	await _frames(3)
	var lot := {}
	for l: Dictionary in d.lotteries:
		if l["id"] == mune["id"]:
			lot = l
	if rivals > 0:
		_check(not lot.is_empty() and USER in lot["teams"] and view.call("overlay_visible"),
			"宗山に%d球団＋自球団が入札 → 抽選の演出（%s → %s）" % [rivals, ", ".join(_shorts(lot.get("teams", []))),
				_gd.short_name(lot.get("winner", ""))])
		await _shot("d2_lottery")
	else:
		_check(d.by_id[mune["id"]]["picked_by"] == USER, "宗山はどこも入札せず単独で交渉権（CPU入札なし）")
	var guard := 0
	while d.stage == _first and guard < 10:
		guard += 1
		view.call("finish_overlays")
		if d.stage == _first and d.first_pick_of(USER).is_empty():
			# 外れ1位：残っている候補で評価の高い順
			var rest: Array = view.call("sorted_candidates", d)
			for c: Dictionary in rest:
				if str(c["picked_by"]).is_empty():
					view.call("select_candidate", c["id"])
					break
			view.call("press_action")
		elif d.stage == _first:
			d.run_first_wave()
	view.call("finish_overlays")
	_check(d.stage == _waiver and not d.first_pick_of(USER).is_empty(),
		"全球団の1位が決まりウェーバーへ（自球団の1位：%s）" % d.by_id.get(d.first_pick_of(USER), {}).get("name", "?"))
	# 2位以降：自球団の番で止まる
	view.call("_on_skip_pressed")
	await _frames(2)
	_check(d.is_user_turn() or d.stage == _ikusei, "自球団の番まで飛ばす → 自球団の番で止まる（%s）" % d.stage_text())
	var picked := 0
	while d.is_user_turn() and d.stage == _waiver and picked < 3:
		var rest2: Array = view.call("sorted_candidates", d)
		for c: Dictionary in rest2:
			if str(c["picked_by"]).is_empty():
				view.call("select_candidate", c["id"])
				break
		view.call("press_action")
		picked += 1
		view.call("_on_skip_pressed")
		await _frames(1)
	_check(picked >= 1 and d.user_reg_count() >= 2, "画面から2位以降を指名（本指名 %d人）" % d.user_reg_count())
	if d.is_user_turn() and d.stage == _waiver:
		view.call("_on_finish_pressed")
	view.call("_on_skip_pressed")
	_check(d.stage == _ikusei or d.stage == _done, "選択終了で本指名を終える → 育成へ（%s）" % \
		d.stage_text())
	view.call("_on_complete_pressed")
	await _frames(3)
	_check(d.resolved and not _gs.draft_open(), "残りをおまかせで終える → ドラフト終了")
	_check_quota(d, "2024年")
	await _shot("d3_result")
	var mine: Array = d.picks_of(USER)
	hub.call("_close_sub_screen")
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	await _frames(2)
	_check(_gs.year == 2025, "2025年の開幕（%s）" % _gs.date_text())
	var roster: Variant = _gs.season.teams.get(USER)
	var in_sim := 0
	for rec: Dictionary in mine:
		if roster != null and roster.by_id.has(rec["id"]):
			in_sim += 1
	_check(in_sim == mine.size() and mine.size() > 0, "2025年の開幕：指名選手 %d/%d人が自球団の編成にいる" % [
		in_sim, mine.size()])
	# 新人は能力が低く自動編成では1軍に入らないことが多いので、1人を1軍に上げてスタメン（投手なら先発）に入れる
	var rookie: Variant = null
	for rec: Dictionary in mine:
		var sp: Variant = roster.by_id.get(rec["id"]) if roster != null else null
		if sp != null and (rookie == null or (rookie.is_pitcher and not sp.is_pitcher)):
			rookie = sp
	var reg_err := "指名選手なし"
	if rookie != null and roster.is_active(rookie):
		reg_err = ""
	elif rookie != null:
		var out_p: Variant = null
		if rookie.is_pitcher:
			for sp: Variant in roster.active_players(true):
				if roster.pitcher_role(sp)[0] == "rotation":
					out_p = sp
					break
		else:
			var order: Array = roster.lineup(true)
			for i in range(order.size() - 1, -1, -1):
				if order[i][0] != null and order[i][1] != "投手":
					out_p = order[i][0]
					break
		reg_err = "入れ替える選手なし" if out_p == null else str(roster.swap_registration(out_p, rookie, _gs.day))
	_check(reg_err.is_empty(), "指名選手を1軍に登録できる（%s%s）" % [
		rookie.name if rookie != null else "", reg_err])
	_gs.advance_through(_gs.season_last_day())
	var played: Array[String] = []
	for rec: Dictionary in mine:
		var b: Dictionary = _gs.season.batting.get(rec["id"], {})
		var p: Dictionary = _gs.season.pitching.get(rec["id"], {})
		if int(b.get("pa", 0)) > 0 or int(p.get("outs", 0)) > 0:
			played.append(rec["name"])
	_check(not played.is_empty(), "2025年のシーズンで指名選手が試合に出た（%s）" % ", ".join(played))


func _find_draft_view(node: Node) -> Node:
	if node.get_script() == _dv:
		return node
	for child in node.get_children():
		var found := _find_draft_view(child)
		if found != null:
			return found
	return null


# --- 3) 2025年 ----------------------------------------------------------------------------

func _check_2025() -> void:
	print("== 2025年開始・すぐドラフトへ（日本ハム） ==")
	_gs.new_game("北海道日本ハムファイターズ", 2025)
	var ok: bool = _gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	_check(ok and d != null and d.candidates.size() > 100, "2025年オフのドラフトに飛べる（候補 %d人）" % [
		d.candidates.size() if d != null else 0])
	if d == null:
		return
	_check(d.year >= d.data_through - 2, "2025年は将来性の元データが少ない年として扱う（data_through=%d）" % d.data_through)
	_gs.advance()
	_check(d.resolved and _gs.phase == _gs.Phase.CAMP and _gs.year == 2026, "次へ進むとおまかせで終わり2026年の春季キャンプ")
	_check_quota(d, "2025年")
	var present := 0
	for rec: Dictionary in d.picks_of("北海道日本ハムファイターズ"):
		if _gs.league.team_of.get(rec["id"], "") == "北海道日本ハムファイターズ":
			present += 1
	_check(present == d.picks_of("北海道日本ハムファイターズ").size() and present > 0,
		"2026年：日本ハムの指名選手 %d人が所属" % present)


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
