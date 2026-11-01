extends SceneTree
## 能力値の点検（作業39 第1段階）用。指定の年を開始年にして公式戦を最後まで回し、選手ごとのゲーム内成績を JSON に書く。
## ゲームの処理は変えない（読むだけ）。集計と資料づくりは tools/ratings_audit.py。
##
##   godot --headless --path godot --script res://tests/ratings_audit_dump.gd -- <年> <出力先.json>
##
## 出力：{year, team_records, batting: {id: {名前・球団・打撃の行（Records.batting_row）・守備得点の内訳・pos_g・打撃の素の数}},
##        pitching: {id: {名前・球団・投手の行（Records.pitching_row）}}, lineups: {球団: [[選手名, 守備位置], ...]}}

const TEAM := "阪神タイガース"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var year := int(args[0]) if args.size() > 0 else 2026
	var out_path: String = args[1] if args.size() > 1 else "user://ratings_audit_%d.json" % year
	var gs: Node = root.get_node("GameState")
	var t0 := Time.get_ticks_msec()
	gs.new_game(TEAM, year)
	var lineups := _lineups(gs)
	gs.advance_through(gs.season_last_day())
	print("%d年 シーズン終了まで %d 秒" % [year, (Time.get_ticks_msec() - t0) / 1000])
	var st: Dictionary = gs.season_stats(year)
	var league_of := func(id: String) -> String:
		return st["leagues"].get(st["players"].get(id, {}).get("team", ""), "")
	var coef := {}
	for lg: String in ["C", "P"]:
		coef[lg] = Records.coefficients(st["batting"], st["pitching"], league_of, lg)
	var bat := {}
	for id: String in st["batting"]:
		var b: Dictionary = st["batting"][id]
		var lg: String = league_of.call(id)
		if not coef.has(lg) or int(b.get("pa", 0)) <= 0:
			continue
		var row: Dictionary = Records.batting_row(b, coef[lg])
		var fr: Dictionary = Records.fielding_runs(b, coef[lg]["fielding"])
		var raw := {}
		for key: String in ["pa", "ab", "h", "d", "t", "hr", "bb", "hbp", "so", "sb", "cs", "rbi"]:
			raw[key] = int(b.get(key, 0))
		bat[id] = {"name": st["players"].get(id, {}).get("name", ""), "team": st["players"].get(id, {}).get("team", ""),
			"row": row, "fld": fr, "pos_g": b.get("pos_g", {}), "raw": raw}
	var pit := {}
	for id: String in st["pitching"]:
		var p: Dictionary = st["pitching"][id]
		var lg: String = league_of.call(id)
		if not coef.has(lg) or int(p.get("outs", 0)) <= 0:
			continue
		pit[id] = {"name": st["players"].get(id, {}).get("name", ""), "team": st["players"].get(id, {}).get("team", ""),
			"row": Records.pitching_row(p, coef[lg]), "gs": int(p.get("gs", 0))}
	var out := {"year": year, "team_records": st["records"], "batting": bat, "pitching": pit, "lineups": lineups}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("書き出し: %s（野手 %d・投手 %d）" % [out_path, bat.size(), pit.size()])
	quit(0)


## 開幕時の各球団の自動のオーダー（DH あり）。[選手名, 守備位置, 選手ID]
func _lineups(gs: Node) -> Dictionary:
	var out := {}
	for team_name: String in gs.season.teams:
		var t: SimTeam = gs.season.teams[team_name]
		var rows: Array = []
		for entry: Array in t.lineup(true):
			var p: SimPlayer = entry[0]
			rows.append([p.name if p != null else "", entry[1], p.id if p != null else ""])
		out[team_name] = rows
	return out
