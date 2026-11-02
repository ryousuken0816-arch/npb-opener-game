extends SceneTree
## 守備得点と WAR の確認（作業33）。2026年を開始年にして1シーズン回し、次を調べる：
## - 守備位置ごとの守備得点のリーグ合計がほぼ0
## - 守備の能力（能力値の守備力）が高い選手ほど守備得点（1イニングあたり）が高い（相関が正）
## - リーグ全体の WAR の合計（野手＋投手）が全試合数×約0.41（±15%）
## - セーブ／ロードで守備の記録・守備得点・WAR が一致
## - 記録室の守備ランキング・選手詳細の年度別 WAR が出て、日付を進めると追従する（6月末 → シーズン終了）
## 結果をユーザー向けの資料 docs/reports/2026_defense_war.md に書く（守備位置ごとの上位5人・下位3人、WAR の上位10人）。
##
##   godot --headless --path godot --script res://tests/defense_war_check.gd -- [スクショの出力先]
## 出力先を渡してウィンドウ付きで流すと記録室の守備ランキングと選手詳細を撮る（--position で画面の隅に置き、フォーカスを奪わない）

const TEAM := "阪神タイガース"
const YEAR := 2026
const WAR_PER_GAME := 0.41
const REPORT := "res://../docs/reports/2026_defense_war.md"
const POSITIONS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手"]
## 相関を見る選手の守備イニングの下限
const CORR_MIN_INNINGS := 150

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node


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
	_gd = root.get_node("GameData")
	var t0 := Time.get_ticks_msec()
	_gs.new_game(TEAM, YEAR)
	_gs.advance_through(Season.day_number("%d-06-30" % YEAR))
	print("6月末まで %d 秒" % ((Time.get_ticks_msec() - t0) / 1000))
	var mid := await _check_ui("6月末", {})
	_gs.advance_through(_gs.season_last_day())
	print("シーズン終了まで %d 秒" % ((Time.get_ticks_msec() - t0) / 1000))
	_check(_gs.phase == _gs.Phase.AWARDS, "%d年 シーズン終了（表彰の段階）" % YEAR)
	var st: Dictionary = _gs.season_stats(YEAR)
	var calc := _calc(st)
	_check_sums(calc)
	_check_corr(calc)
	_check_war(st, calc)
	await _check_ui("シーズン終了", mid)
	_check_save(calc)
	_write_report(st, calc)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## リーグごとの係数と、全選手の打撃・投手の行（Records）
func _calc(st: Dictionary) -> Dictionary:
	var league_of := func(id: String) -> String:
		return st["leagues"].get(st["players"].get(id, {}).get("team", ""), "")
	var coef := {}
	for lg: String in ["C", "P"]:
		coef[lg] = Records.coefficients(st["batting"], st["pitching"], league_of, lg)
	var bat := {}
	var fld := {}
	for id: String in st["batting"]:
		var b: Dictionary = st["batting"][id]
		var lg: String = league_of.call(id)
		if not coef.has(lg):
			continue
		if int(b.get("pa", 0)) > 0:
			bat[id] = Records.batting_row(b, coef[lg])
		fld[id] = Records.fielding_runs(b, coef[lg]["fielding"])
	var pit := {}
	for id: String in st["pitching"]:
		var lg: String = league_of.call(id)
		if coef.has(lg) and int(st["pitching"][id].get("outs", 0)) > 0:
			pit[id] = Records.pitching_row(st["pitching"][id], coef[lg])
	return {"coef": coef, "bat": bat, "pit": pit, "fld": fld}


func _check_sums(calc: Dictionary) -> void:
	for pos: String in POSITIONS:
		var sum := 0.0
		var outs := 0
		var spread := 0.0
		for id: String in calc["fld"]:
			var p: Dictionary = calc["fld"][id]["pos"].get(pos, {})
			if p.is_empty():
				continue
			sum += float(p["total"])
			outs += int(p["outs"])
			spread = maxf(spread, absf(float(p["total"])))
		print("  %s：守備得点の合計 %+.2f（守備イニング計 %d、最大の絶対値 %.1f）" % [pos, sum, outs / 3, spread])
		_check(absf(sum) < 0.5, "%s：守備得点のリーグ合計がほぼ0（%+.2f）" % [pos, sum])
		_check(spread > 2.0, "%s：守備得点に差が出る（最大の絶対値 %.1f）" % [pos, spread])


## 能力値の守備力と守備得点（1000イニングあたり）の相関（守備位置ごと・全体）
func _check_corr(calc: Dictionary) -> void:
	var all_x: Array = []
	var all_y: Array = []
	var positive := 0
	for pos: String in POSITIONS:
		var xs: Array = []
		var ys: Array = []
		for id: String in calc["fld"]:
			var p: Dictionary = calc["fld"][id]["pos"].get(pos, {})
			if p.is_empty() or int(p["outs"]) < CORR_MIN_INNINGS * 3:
				continue
			var v := _defense_value(id, pos)
			if v < 0.0:
				continue
			xs.append(v)
			ys.append(float(p["total"]) / (int(p["outs"]) / 3.0) * 1000.0)
		var r := _pearson(xs, ys)
		print("  %s：守備力と守備得点/1000回の相関 %.2f（%d人）" % [pos, r, xs.size()])
		if r > 0.0:
			positive += 1
		# 全体は位置ごとに守備力を中心化してから合わせる
		var mean_x := 0.0
		for x: float in xs:
			mean_x += x / xs.size()
		for i in xs.size():
			all_x.append(xs[i] - mean_x)
			all_y.append(ys[i])
	var r_all := _pearson(all_x, all_y)
	_check(r_all >= 0.3, "守備力が高いほど守備得点が高い（全体の相関 %.2f）" % r_all)
	_check(positive >= 7, "守備位置ごとの相関が正（%d／8位置）" % positive)
	_check_fast_cf(calc)


## 作業43：足の速い中堅手（走力 75 以上）の守備得点（1000回あたり）の平均が、中堅手全体の平均より上
func _check_fast_cf(calc: Dictionary) -> void:
	var fast := []
	var others := []
	var names := []
	for id: String in calc["fld"]:
		var p: Dictionary = calc["fld"][id]["pos"].get("中堅手", {})
		if p.is_empty() or int(p["outs"]) < CORR_MIN_INNINGS * 3:
			continue
		var rate := float(p["total"]) / (int(p["outs"]) / 3.0) * 1000.0
		var pl: Dictionary = _gd.player(id)
		var spd: Variant = pl.get("batting", {}).get("ratings", {}).get("speed")
		var sv := int(spd["value"]) if spd is Dictionary else 0
		if sv >= 75:
			fast.append(rate)
			names.append("%s（走力%d、%+.1f）" % [pl.get("name", id), sv, p["total"]])
		else:
			others.append(rate)
	var mf := 0.0
	for x: float in fast:
		mf += x / maxf(fast.size(), 1)
	var mo := 0.0
	for x: float in others:
		mo += x / maxf(others.size(), 1)
	print("  中堅手の足の速い選手：%s" % "、".join(names))
	_check(not fast.is_empty() and mf > mo, "足の速い中堅手の守備得点/1000回が平均より上（%+.1f／ほか %+.1f）" % [mf, mo])


func _check_war(st: Dictionary, calc: Dictionary) -> void:
	var games := 0
	for team: String in st["records"]:
		var rec: Dictionary = st["records"][team]
		games += int(rec["w"]) + int(rec["l"]) + int(rec["d"])
	games /= 2
	var war_b := 0.0
	var war_p := 0.0
	var fld_sum := 0.0
	for id: String in calc["bat"]:
		war_b += float(calc["bat"][id]["war"])
		fld_sum += float(calc["bat"][id]["fld"])
	for id: String in calc["pit"]:
		war_p += float(calc["pit"][id]["war"])
	var want := games * WAR_PER_GAME
	print("  WAR 合計：野手 %.1f・投手 %.1f・計 %.1f（%d試合×%.2f＝%.1f）。守備得点の合計 %+.1f" % [
		war_b, war_p, war_b + war_p, games, WAR_PER_GAME, want, fld_sum])
	_check(absf(war_b + war_p - want) <= want * 0.15, "WAR の合計が試合数×%.2f に見合う（%.1f / %.1f）" % [
		WAR_PER_GAME, war_b + war_p, want])
	_check(war_b > war_p * 0.8 and war_b < war_p * 2.0, "野手と投手の WAR の配分（%.1f / %.1f）" % [war_b, war_p])


## 記録室の守備ランキング・選手詳細の年度別 WAR。prev（6月末の結果）と比べて追従を確かめる
func _check_ui(when: String, prev: Dictionary) -> Dictionary:
	var hub: Control = load("res://scenes/hub/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.call("_on_menu_chosen", "records")
	await process_frame
	var view: Control = hub.get("_records_view")
	view.call("set_tab", "bat")
	_check(view.call("shown_year") == YEAR, "%s：記録室は%d年" % [when, YEAR])
	# 打撃成績に「守備」の列
	var has_col := false
	for col: Array in Records.BAT_COLUMNS:
		has_col = has_col or col[0] == "fld"
	_check(has_col, "打撃成績に「守備」の列")
	view.set("_fld_pos", "遊撃手")
	view.set("_qualified", true)
	view.call("refresh")
	await process_frame
	var rows: Array = view.call("fielding_rows", "遊撃手")
	var ids: Array = view.call("list_ids")
	_check(not ids.is_empty(), "%s：遊撃手の守備ランキングに選手がいる（%d人）" % [when, ids.size()])
	var result := {"outs": 0, "id": ""}
	if not ids.is_empty():
		var top := {}
		var best := -INF
		for r: Dictionary in rows:
			if r["id"] == ids[0]:
				top = r
			best = maxf(best, float(r["row"]["total"]))
		_check(not top.is_empty() and is_equal_approx(float(top["row"]["total"]), best),
			"%s：表示の1位が守備得点の最大（%.1f）" % [when, best])
		result = {"outs": int(top["row"]["outs"]), "id": ids[0]}
		print("  %s：遊撃手の守備得点1位 %s（%s）%s回 %+.1f" % [when, top["name"], _gd.short_name(top["team"]),
			Records.format("ip", top["row"]["outs"]), top["row"]["total"]])
		if not prev.is_empty() and prev["id"] == ids[0]:
			_check(result["outs"] > prev["outs"], "%s：日付を進めると守備イニングが増える（%d → %d）" % [
				when, prev["outs"] / 3, result["outs"] / 3])
	await _no_overflow(hub, view, "%s：守備ランキング（遊撃手）" % when)
	for pos: String in ["捕手", "中堅手"]:
		view.set("_fld_pos", pos)
		view.call("refresh")
		_check(not view.call("list_ids").is_empty(), "%s：%sの守備ランキング" % [when, pos])
		await _no_overflow(hub, view, "%s：守備ランキング（%s）" % [when, pos])
	view.set("_fld_pos", "中堅手")
	view.call("refresh")
	await _capture("fielding_ranking_%s" % ("mid" if prev.is_empty() else "end"))
	# 選手詳細：年度別 WAR（1位の選手）
	if not ids.is_empty():
		var detail: Node = load("res://scenes/player_detail/player_detail.gd").call("open", view, ids[0], ids)
		await process_frame
		detail.call("show_tab", 1)
		await process_frame
		_check(detail.find_child("WarHistory", true, false) != null, "%s：選手詳細の成績タブに年度別 WAR の表" % when)
		await _capture("player_detail_%s" % ("mid" if prev.is_empty() else "end"))
		var rows_war: Array = load("res://scenes/player_detail/stat_table.gd").call("war_rows", ids[0], false)
		_check(rows_war.size() == 1 and int(rows_war[0]["year"]) == YEAR, "%s：選手詳細の年度別 WAR に%d年の行" % [when, YEAR])
		if not rows_war.is_empty():
			print("  %s：選手詳細 %s WAR %s・守備得点 %s・守備 %s回" % [when, ids[0], rows_war[0]["war"], rows_war[0]["fld"],
				rows_war[0]["inn"]])
		detail.call("close")
		await process_frame
	view.set("_fld_pos", "")
	hub.queue_free()
	await process_frame
	return result


func _check_save(calc: Dictionary) -> void:
	var sg: GDScript = load("res://scripts/save_game.gd")
	var dir := "user://test_saves_dw_%d" % OS.get_process_id()
	sg.set("dir", dir)
	sg.set("autosave_enabled", false)
	var error: String = sg.call("save", "slot1")
	_check(error.is_empty(), "セーブ %s" % error)
	_gs.new_game("読売ジャイアンツ", 2010)
	error = sg.call("load_slot", "slot1")
	_check(error.is_empty(), "ロード %s" % error)
	var after := _calc(_gs.season_stats(YEAR))
	var worst := 0.0
	var count := 0
	for id: String in calc["bat"]:
		count += 1
		for key: String in ["fld", "war"]:
			worst = maxf(worst, absf(float(calc["bat"][id][key]) - float(after["bat"].get(id, {}).get(key, 1e9))))
	for id: String in calc["pit"]:
		worst = maxf(worst, absf(float(calc["pit"][id]["war"]) - float(after["pit"].get(id, {}).get("war", 1e9))))
	_check(worst < 1e-6 and count > 0, "セーブ／ロードで守備得点・WAR が一致（%d人、最大の差 %.6f）" % [count, worst])
	for slot: String in sg.call("all_slots"):
		sg.call("delete", slot)
	DirAccess.remove_absolute(dir)


# --- ユーザー向けの資料 ---------------------------------------------------------------------

func _write_report(st: Dictionary, calc: Dictionary) -> void:
	var lines: Array[String] = []
	var games := 0
	for team: String in st["records"]:
		var rec: Dictionary = st["records"][team]
		games += int(rec["w"]) + int(rec["l"]) + int(rec["d"])
	lines.append("# 2026年の守備得点と WAR（ゲーム内で1シーズン回した結果）")
	lines.append("")
	lines.append("作業33の確認用。`godot/tests/defense_war_check.gd` で 2026年を開始年にして公式戦を最後まで回し、記録室と同じ計算"
		+ "（`godot/sim/records.gd`）で出した。自球団は%s（CPU と同じ自動の采配）。乱数しだいなので回すたびに少し変わる。" % TEAM)
	lines.append("")
	lines.append("- 守備得点：同じ守備位置のリーグ平均（両リーグ合計）と比べて、何点防いだか（＋）・許したか（−）。"
		+ "内訳は 範囲（打球をアウトにした数）・失策・肩（外野：長打を単打に止めた・走者を止めた／刺した）、捕手は 盗塁阻止・暴投捕逸")
	lines.append("- 守備イニングは公式戦でその位置を守ったイニング。順位はその位置の守備イニングが %d 回以上（チーム試合数×%d）の選手" % [
		int(games / 12.0 * 4.0), 4])
	lines.append("- 能力は今の能力値の守備力のランク（S〜G）。捕手・外野手は「守備力／肩」。「能力値なし」はその位置の能力値が無い選手（CPU の自動のオーダーが本職でない位置に入れた。試合では不慣れとして守備力を低く扱う）")
	lines.append("- 試合数 %d、リーグ全体の WAR は下の「合計」" % (games / 2))
	lines.append("")
	var min_outs := int(games / 12.0 * 4.0) * 3
	lines.append("## 守備位置ごとの守備得点（上位5人・下位3人）")
	for pos: String in POSITIONS:
		var list: Array = []
		for id: String in calc["fld"]:
			var p: Dictionary = calc["fld"][id]["pos"].get(pos, {})
			if p.is_empty() or int(p["outs"]) < min_outs:
				continue
			list.append({"id": id, "p": p})
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["p"]["total"] > b["p"]["total"])
		lines.append("")
		lines.append("### %s（%d人）" % [pos, list.size()])
		lines.append("")
		if pos == "捕手":
			lines.append("| 順位 | 選手 | 球団 | 守備イニング | 守備得点 | 盗塁阻止 | 暴投捕逸 | 阻止率 | 能力（守備力／肩） |")
			lines.append("|---|---|---|---|---|---|---|---|---|")
		elif pos in Records.OUTFIELD:
			lines.append("| 順位 | 選手 | 球団 | 守備イニング | 守備得点 | 範囲 | 失策 | 肩 | 能力（守備力／肩） |")
			lines.append("|---|---|---|---|---|---|---|---|---|")
		else:
			lines.append("| 順位 | 選手 | 球団 | 守備イニング | 守備得点 | 範囲 | 失策 | 能力（守備力） |")
			lines.append("|---|---|---|---|---|---|---|---|")
		var shown: Array = []
		for i in list.size():
			if i < 5 or i >= list.size() - 3:
				shown.append(i)
		var last := -1
		for i: int in shown:
			if last >= 0 and i != last + 1:
				lines.append("| … |" + " |".repeat(8 if pos == "捕手" or pos in Records.OUTFIELD else 7))
			last = i
			var e: Dictionary = list[i]
			var p: Dictionary = e["p"]
			var id: String = e["id"]
			var head := "| %d | %s | %s | %s | **%s** |" % [i + 1, _name(st, id), _gd.short_name(_team(st, id)),
				Records.format("ip", p["outs"]), Records.format("runs", p["total"])]
			if pos == "捕手":
				var line: Dictionary = st["batting"][id]["fld"][pos]
				var sba := int(line.get("sba", 0))
				lines.append(head + " %s | %s | %s | %s |" % [Records.format("runs", p["cs"]), Records.format("runs", p["wp"]),
					"%.3f（%d/%d）" % [float(line.get("cs", 0)) / sba if sba > 0 else 0.0, int(line.get("cs", 0)), sba],
					_rank_text(id, pos, true)])
			elif pos in Records.OUTFIELD:
				lines.append(head + " %s | %s | %s | %s |" % [Records.format("runs", p["rng"]), Records.format("runs", p["err"]),
					Records.format("runs", p["arm"]), _rank_text(id, pos, true)])
			else:
				lines.append(head + " %s | %s | %s |" % [Records.format("runs", p["rng"]), Records.format("runs", p["err"]),
					_rank_text(id, pos, false)])
	# WAR
	lines.append("")
	lines.append("## WAR の上位10人")
	lines.append("")
	lines.append("### 野手")
	lines.append("")
	lines.append("| 順位 | 選手 | 球団 | 主な守備 | 打席 | 打率 | 本塁打 | wRC+ | 守備得点 | WAR |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	var bat_ids: Array = calc["bat"].keys()
	bat_ids.sort_custom(func(a: String, b: String) -> bool: return calc["bat"][a]["war"] > calc["bat"][b]["war"])
	for i in mini(10, bat_ids.size()):
		var id: String = bat_ids[i]
		var r: Dictionary = calc["bat"][id]
		lines.append("| %d | %s | %s | %s | %d | %s | %d | %s | %s | **%s** |" % [i + 1, _name(st, id),
			_gd.short_name(_team(st, id)), _main_pos(calc, id), r["pa"], Records.format("rate3", r["avg"]), r["hr"],
			Records.format("plus", r["wrc_plus"]), Records.format("runs", r["fld"]), Records.format("war", r["war"])])
	lines.append("")
	lines.append("### 投手")
	lines.append("")
	lines.append("| 順位 | 選手 | 球団 | 登板 | 投球回 | 勝敗 | 防御率 | FIP | WAR |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	var pit_ids: Array = calc["pit"].keys()
	pit_ids.sort_custom(func(a: String, b: String) -> bool: return calc["pit"][a]["war"] > calc["pit"][b]["war"])
	for i in mini(10, pit_ids.size()):
		var id: String = pit_ids[i]
		var r: Dictionary = calc["pit"][id]
		lines.append("| %d | %s | %s | %d | %s | %d勝%d敗%dS | %s | %s | **%s** |" % [i + 1, _name(st, id),
			_gd.short_name(_team(st, id)), r["g"], Records.format("ip", r["ip"]), r["w"], r["l"], r["sv"],
			Records.format("rate2", r["era"]), Records.format("rate2", r["fip"]), Records.format("war", r["war"])])
	var war_b := 0.0
	var war_p := 0.0
	for id: String in calc["bat"]:
		war_b += float(calc["bat"][id]["war"])
	for id: String in calc["pit"]:
		war_p += float(calc["pit"][id]["war"])
	lines.append("")
	lines.append("## 合計")
	lines.append("")
	lines.append("- リーグ全体の WAR：野手 %.1f＋投手 %.1f＝**%.1f**（目安は %d試合×0.41＝%.0f）" % [war_b, war_p, war_b + war_p,
		games / 2, games / 2 * WAR_PER_GAME])
	lines.append("- 守備得点の式・係数は HANDOFF.md の 4.41（作業33）にある")
	var path := ProjectSettings.globalize_path(REPORT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("資料を書いた：%s" % path)


func _name(st: Dictionary, id: String) -> String:
	return str(st["players"].get(id, {}).get("name", id))


func _team(st: Dictionary, id: String) -> String:
	return str(st["players"].get(id, {}).get("team", ""))


func _main_pos(calc: Dictionary, id: String) -> String:
	var pos := "指名打者"
	var best := 0
	for p: String in calc["fld"].get(id, {}).get("pos", {}):
		var outs := int(calc["fld"][id]["pos"][p]["outs"])
		if outs > best:
			best = outs
			pos = p
	return pos


## 能力値の守備力（その位置。無ければ -1）
func _defense_value(id: String, pos: String) -> float:
	var f: Variant = _fielding(id, pos)
	if not f is Dictionary or not f.get("defense") is Dictionary or f["defense"].get("value") == null:
		return -1.0
	# 捕手の守備得点は盗塁阻止（肩）が主なので、守備力と肩の平均と比べる
	if pos == "捕手" and f.get("arm") is Dictionary and f["arm"].get("value") != null:
		return (float(f["defense"]["value"]) + float(f["arm"]["value"])) / 2.0
	# 外野は試合の守備範囲と同じく走力を混ぜる（作業43、SimPlayer.range_at）
	var share: float = SimPlayer.RANGE_SPEED_SHARE.get(pos, 0.0)
	var spd: Variant = _gd.player(id).get("batting", {}).get("ratings", {}).get("speed")
	if share > 0.0 and spd is Dictionary and spd.get("value") != null:
		return (1.0 - share) * float(f["defense"]["value"]) + share * float(spd["value"])
	return float(f["defense"]["value"])


func _rank_text(id: String, pos: String, with_arm: bool) -> String:
	var f: Variant = _fielding(id, pos)
	if not f is Dictionary:
		return "（能力値なし）"
	var d: String = str(f.get("defense", {}).get("rank", "-")) if f.get("defense") is Dictionary else "-"
	if not with_arm:
		return d
	var a: String = str(f["arm"].get("rank", "-")) if f.get("arm") is Dictionary else "-"
	return "%s／%s" % [d, a]


## 能力値のその位置の守備（外野は「外野手」）。無ければ null
func _fielding(id: String, pos: String) -> Variant:
	var fielding: Variant = _gd.player(id).get("fielding")
	if not fielding is Dictionary:
		return null
	return fielding.get("外野手" if pos in Records.OUTFIELD else pos)


static func _pearson(xs: Array, ys: Array) -> float:
	var n := xs.size()
	if n < 3:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += float(xs[i]) / n
		my += float(ys[i]) / n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		sxy += (float(xs[i]) - mx) * (float(ys[i]) - my)
		sxx += pow(float(xs[i]) - mx, 2)
		syy += pow(float(ys[i]) - my, 2)
	return sxy / sqrt(sxx * syy) if sxx > 0.0 and syy > 0.0 else 0.0


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
