extends SceneTree
## 位置別の戦力（作業34）の確認。2026年を開始年にして：
## - 開幕前：昨季（2025年）が初期表示で、能力から見込んだ値。位置ごとの12球団の合計≈0
## - 5月末：今季が初期表示（試合が PV_MIN_GAMES 以上）。位置ごとの12球団の合計≈0
## - シーズン終了：値が5月末より大きくなる（日付に追従）。打撃＋守備の一番良い野手の球団×位置、FIP の一番良い投手の
##   球団×先発／救援がプラス
## - 画面：棒グラフ・12球団の一覧・能力ランクを開いてはみ出さない。一覧・能力ランクの見出しはスクロールの外（下まで
##   スクロールしても見える）。見出しで並び替え、球団名で棒グラフへ、◀▶で球団を送る
##
##   godot --headless --path godot --script res://tests/position_value_check.gd -- [スクショの出力先]

const TEAM := "阪神タイガース"
const YEAR := 2026

var _out := ""
var _failures := 0
var _gs: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
		DirAccess.make_dir_recursive_absolute(_out)
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(TEAM, YEAR)
	var pre := await _check_screen("開幕前", true, true)
	_gs.advance_through(Season.day_number("%d-05-31" % YEAR))
	var may := await _check_screen("5月末", false, false)
	_gs.advance_through(_gs.season_last_day())
	var end := await _check_screen("シーズン終了", false, false)
	_check(_spread(end) > _spread(may), "日付を進めると値が大きくなる（5月末 %.0f → 終了 %.0f）" % [_spread(may), _spread(end)])
	_check(not pre.is_empty(), "開幕前も見込みの値が出る")
	_check_best(end)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## 記録室の「位置別の戦力」を開いて調べる。want_last：昨季が初期表示か、want_estimate：能力から見込んだ値か
func _check_screen(when: String, want_last: bool, want_estimate: bool) -> Dictionary:
	var hub: Control = load("res://scenes/hub/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.call("_on_menu_chosen", "records")
	await process_frame
	var view: Control = hub.get("_records_view")
	view.call("set_tab", "pos_rank")
	await process_frame
	_check(view.get("_pv_last") == want_last, "%s：%sが初期表示" % [when, "昨季" if want_last else "今季"])
	_check(view.call("pv_estimated") == want_estimate, "%s：%s" % [when, "能力から見込んだ値" if want_estimate else "成績からの値"])
	var values: Dictionary = view.call("position_values")
	_check(values.size() == 12, "%s：12球団の値（%d）" % [when, values.size()])
	var cols: Array = load("res://sim/team_value.gd").get("COLUMNS")
	var worst := 0.0
	for col: String in cols:
		var sum := 0.0
		for team: String in values:
			sum += float(values[team][col]["total"])
		worst = maxf(worst, absf(sum))
	_check(worst < 0.01, "%s：位置ごとの12球団の合計がほぼ0（最大のずれ %.4f）" % [when, worst])
	var line: Array[String] = []
	for team: String in values:
		line.append("%s %+.0f(%d位)" % [root.get_node("GameData").short_name(team), values[team]["total"], values[team]["rank"]])
	print("  %s（%d年）：%s" % [when, view.call("shown_pv_year"), "、".join(line)])
	# 棒グラフ
	view.set("_pv_mode", "chart")
	view.call("refresh")
	await process_frame
	var chart: Node = view.find_child("TeamValueChart", true, false)
	_check(chart != null, "%s：棒グラフがある" % when)
	if chart != null:
		_check(is_equal_approx(float(chart.call("value_of", "先発")), float(values[TEAM]["先発"]["total"])),
			"%s：棒グラフは自球団の値" % when)
	await _no_overflow(hub, view, "%s：棒グラフ" % when)
	if when == "シーズン終了":
		await _capture("pv_chart")
	view.call("refresh")
	var before: String = view.get("_pv_team")
	_press_option(view, "▶")
	_check(view.get("_pv_team") != before, "%s：▶で次の球団（%s → %s）" % [when, before, view.get("_pv_team")])
	_press_option(view, "◀")
	_check(view.get("_pv_team") == before, "%s：◀で戻る" % when)
	# 12球団の一覧：見出しはスクロールの外、並び替え、球団名で棒グラフへ
	view.set("_pv_mode", "list")
	view.call("refresh")
	await process_frame
	await _check_fixed_header(view, when + "：一覧")
	await _no_overflow(hub, view, "%s：一覧" % when)
	if when == "シーズン終了":
		await _capture("pv_list")
	view.get("_sort")["pv"] = ["遊撃手", true]
	view.call("refresh")
	var body: Node = view.get("_body")
	var first_team := ""
	for b: Node in body.find_children("*", "Button", true, false):
		first_team = (b as Button).text
		break
	var best_ss := ""
	for team: String in values:
		if best_ss.is_empty() or float(values[team]["遊撃手"]["total"]) > float(values[best_ss]["遊撃手"]["total"]):
			best_ss = team
	_check(first_team == root.get_node("GameData").short_name(best_ss), "%s：遊撃で並び替えると1位は%s（%s）" % [
		when, best_ss, first_team])
	for b: Node in body.find_children("*", "Button", true, false):
		(b as Button).pressed.emit()
		break
	_check(view.get("_pv_mode") == "chart" and view.get("_pv_team") == best_ss, "%s：球団名で棒グラフへ" % when)
	# 能力ランク（今までの表）も見出し固定
	view.set("_pv_mode", "ability")
	view.call("refresh")
	await process_frame
	await _check_fixed_header(view, when + "：能力ランク")
	await _no_overflow(hub, view, "%s：能力ランク" % when)
	# 今季／昨季の切り替え
	view.set("_pv_mode", "list")
	view.set("_pv_last", not want_last)
	view.call("refresh")
	_check(view.call("shown_pv_year") == YEAR - (0 if want_last else 1), "%s：今季／昨季の切り替え（%d年）" % [
		when, view.call("shown_pv_year")])
	view.set("_pv_mode", "chart")
	hub.queue_free()
	await process_frame
	return values


## 見出し（_fixed）がスクロールの外にあり、一番下までスクロールしても見える
func _check_fixed_header(view: Control, label: String) -> void:
	var fixed: Control = view.get("_fixed")
	var scroll: ScrollContainer = view.get("_scroll")
	_check(fixed.visible and fixed.get_child_count() > 0, "%s：見出しの行がスクロールの外にある" % label)
	scroll.scroll_vertical = 100000
	await process_frame
	await process_frame
	var r := fixed.get_global_rect()
	var s := scroll.get_global_rect()
	_check(r.size.y > 10.0 and r.end.y <= s.position.y + 1.0, "%s：下までスクロールしても見出しが見える（%s / %s）" % [
		label, r, s])
	scroll.scroll_vertical = 0


func _check_best(values: Dictionary) -> void:
	var gs := _gs
	var st: Dictionary = gs.season_stats(YEAR)
	var league_of := func(id: String) -> String:
		return st["leagues"].get(st["players"].get(id, {}).get("team", ""), "")
	var coef := {}
	for lg: String in ["C", "P"]:
		coef[lg] = Records.coefficients(st["batting"], st["pitching"], league_of, lg)
	var best_id := ""
	var best := -INF
	for id: String in st["batting"]:
		var b: Dictionary = st["batting"][id]
		var lg: String = league_of.call(id)
		if int(b.get("pa", 0)) < 400 or not coef.has(lg):
			continue
		var r := Records.batting_row(b, coef[lg])
		var v: float = float(r["wraa"]) + float(r["fld"])
		if v > best:
			best = v
			best_id = id
	var pos := ""
	var most := 0
	for p: String in st["batting"][best_id].get("pos_g", {}):
		if int(st["batting"][best_id]["pos_g"][p]) > most and p != "投手":
			most = int(st["batting"][best_id]["pos_g"][p])
			pos = p
	var team: String = st["players"][best_id]["team"]
	var cell := float(values[team][pos]["total"])
	print("  打撃＋守備の1位：%s（%s・%s）%+.1f点 → 球団×位置 %+.1f" % [st["players"][best_id]["name"], team, pos, best, cell])
	_check(cell > 0.0, "打撃＋守備の一番良い野手の球団×位置がプラス（%+.1f）" % cell)
	var best_p := ""
	best = -INF
	for id: String in st["pitching"]:
		var p: Dictionary = st["pitching"][id]
		var lg: String = league_of.call(id)
		if int(p.get("outs", 0)) < 300 or not coef.has(lg):
			continue
		var r := Records.pitching_row(p, coef[lg])
		var v: float = (float(coef[lg]["lg_era"]) - float(r["fip"])) * int(p["outs"]) / 27.0
		if v > best:
			best = v
			best_p = id
	var pp: Dictionary = st["pitching"][best_p]
	var col := "先発" if int(pp.get("gs", 0)) * 2 >= int(pp.get("g", 0)) else "救援"
	var pteam: String = st["players"][best_p]["team"]
	var pcell := float(values[pteam][col]["total"])
	print("  投手の1位：%s（%s・%s）%+.1f点 → 球団×位置 %+.1f" % [st["players"][best_p]["name"], pteam, col, best, pcell])
	_check(pcell > 0.0, "FIP の一番良い投手の球団×%sがプラス（%+.1f）" % [col, pcell])


func _press_option(view: Control, text: String) -> void:
	for c: Node in (view.get("_options") as Node).get_children():
		if c is Button and (c as Button).text == text:
			(c as Button).pressed.emit()
			return


## 合計の絶対値の和（値の大きさ）
static func _spread(values: Dictionary) -> float:
	var s := 0.0
	for team: String in values:
		s += absf(float(values[team]["total"]))
	return s


func _no_overflow(hub: Control, view: Control, label: String) -> void:
	await process_frame
	var bar: Control = hub.get_node("%BottomBar")
	var over: Array[String] = []
	for c: Node in view.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if not ctrl.is_visible_in_tree():
			continue
		var r := ctrl.get_global_rect()
		var in_scroll := false
		var n: Node = ctrl.get_parent()
		while n != null and n != view:
			if n is ScrollContainer:
				in_scroll = true
			n = n.get_parent()
		if r.end.x > 1281.0 or (not in_scroll and r.end.y > bar.get_global_rect().position.y + 1.0):
			over.append("%s%s" % [ctrl.name, r])
	_check(over.is_empty(), "%s：画面からはみ出さない %s" % [label, " ".join(over.slice(0, 3))])


func _capture(file_name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(file_name + ".png"))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("NG ", label)
	else:
		print("OK ", label)
