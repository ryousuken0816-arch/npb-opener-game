extends SceneTree
## 1シーズンを最後までシミュレーションし、リーグ全体の成績を史実（teamstats_linked.json の1軍成績）と比べる。
##
##   godot --headless --path godot --script res://tests/season_check.gd -- [年] [シード]
##
## 試合シミュレーションの係数（sim/game_sim.gd 冒頭の定数）を調整するときに使う。

const REPO := "res://.."


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var year := int(args[0]) if args.size() > 0 else 2008
	var seed_value := int(args[1]) if args.size() > 1 else 0
	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var ratings: Dictionary = _load_json(root.path_join("generated/ratings/%d_pre.json" % year))
	var schedule: Array = _load_json(root.path_join("data/%d/schedule.json" % year))
	var actual_rows: Array = _load_json(root.path_join("data/%d/teamstats_linked.json" % year))

	var start := Time.get_ticks_msec()
	var debut_years := {}
	for r: Dictionary in _load_json(root.path_join("data/%d/rosters.json" % year)):
		if r.get("player_id") != null and r.get("debut_year") != null:
			debut_years[r["player_id"]] = r["debut_year"]
	var season := Season.new(year, ratings, schedule, seed_value, debut_years)
	var n := season.sim_all()
	print("%d年: %d試合をシミュレーション（%.1f秒）" % [year, n, (Time.get_ticks_msec() - start) / 1000.0])

	for league: String in ["C", "P", ""]:
		var sim := season.league_totals(league)
		var real := _actual(actual_rows, league)
		print("\n== %s ==" % ({"C": "セ・リーグ", "P": "パ・リーグ", "": "両リーグ"}[league]))
		print("            シミュ    史実")
		_row("打率", _avg(sim), _avg(real), "%.3f")
		_row("出塁率", _obp(sim), _obp(real), "%.3f")
		_row("長打率", _slg(sim), _slg(real), "%.3f")
		_row("本塁打", sim["hr"], real["hr"], "%d")
		_row("防御率", sim["er"] * 27.0 / sim["outs"], real["er"] * 27.0 / real["outs"], "%.2f")
		_row("得点/試合", float(sim["r"]) / sim["games"], float(real["r"]) / real["games"], "%.2f")
		_row("三振%", 100.0 * sim["so"] / sim["pa"], 100.0 * real["so"] / real["pa"], "%.1f")
		_row("四球%", 100.0 * sim["bb"] / sim["pa"], 100.0 * real["bb"] / real["pa"], "%.1f")
		_row("二塁打", sim["d"], real["d"], "%d")
		_row("三塁打", sim["t"], real["t"], "%d")
		_row("盗塁", sim["sb"], real["sb"], "%d")
		_row("盗塁刺", sim["cs"], real["cs"], "%d")
		_row("犠打", sim["sh"], real["sh"], "%d")
		_row("犠飛", sim["sf"], real["sf"], "%d")
		_row("併殺打", sim["gdp"], real["gdp"], "%d")
		_row("失点-自責", sim["ra"] - sim["er"], real["ra"] - real["er"], "%d")
		_row("打席", sim["pa"], real["pa"], "%d")
		_row("アウト数", sim["outs"], real["outs"], "%d")
		_row("失策出塁", sim["roe"], 0, "%d")

	print("\n== 順位 ==")
	for league: String in ["C", "P"]:
		var rows: Array = []
		for team: String in season.records:
			if season.leagues[team] == league:
				var r: Dictionary = season.records[team]
				rows.append([team, r["w"], r["l"], r["d"], r["rs"], r["ra"]])
		rows.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[1]) / maxi(a[1] + a[2], 1) > float(b[1]) / maxi(b[1] + b[2], 1))
		for r: Array in rows:
			print("  %s %d勝%d敗%d分 得%d 失%d" % r)
	_leaders(season)
	quit()


func _leaders(season: Season) -> void:
	print("\n== 個人成績（上位）==")
	var bats: Array = season.batting.keys().filter(func(id: String) -> bool:
		return season.batting[id]["pa"] >= 446)
	bats.sort_custom(func(a: String, b: String) -> bool:
		return Season.batting_avg(season.batting[a]) > Season.batting_avg(season.batting[b]))
	for id: String in bats.slice(0, 5):
		var b: Dictionary = season.batting[id]
		print("  打率 %s %.3f %d本 %d打点" % [
			season.player_name(id), Season.batting_avg(b), b["hr"], b["rbi"]])
	bats.sort_custom(func(a: String, b: String) -> bool:
		return season.batting[a]["hr"] > season.batting[b]["hr"])
	for id: String in bats.slice(0, 5):
		print("  本塁打 %s %d" % [season.player_name(id), season.batting[id]["hr"]])
	var pits: Array = season.pitching.keys()
	pits.sort_custom(func(a: String, b: String) -> bool:
		return season.pitching[a]["w"] > season.pitching[b]["w"])
	for id: String in pits.slice(0, 5):
		var p: Dictionary = season.pitching[id]
		print("  勝利 %s %d勝%d敗 防%.2f %d回" % [
			season.player_name(id), p["w"], p["l"], Season.era(p), p["outs"] / 3])
	pits.sort_custom(func(a: String, b: String) -> bool:
		return season.pitching[a]["sv"] > season.pitching[b]["sv"])
	for id: String in pits.slice(0, 3):
		var p: Dictionary = season.pitching[id]
		print("  セーブ %s %dS 防%.2f %d登板" % [season.player_name(id), p["sv"], Season.era(p), p["g"]])


func _actual(rows: Array, league: String) -> Dictionary:
	var league_name: String = {"C": "セントラル・リーグ", "P": "パシフィック・リーグ", "": ""}[league]
	var t := {
		"pa": 0, "ab": 0, "h": 0, "d": 0, "t": 0, "hr": 0, "bb": 0, "hbp": 0, "so": 0,
		"sb": 0, "cs": 0, "sh": 0, "sf": 0, "gdp": 0, "r": 0, "outs": 0, "er": 0, "ra": 0,
		"games": 144 * (6 if not league.is_empty() else 12),
	}
	var keys := {
		"pa": "打席", "ab": "打数", "h": "安打", "d": "二塁打", "t": "三塁打", "hr": "本塁打",
		"bb": "四球", "hbp": "死球", "so": "三振", "sb": "盗塁", "cs": "盗塁刺", "sh": "犠打",
		"sf": "犠飛", "gdp": "併殺打", "r": "得点",
	}
	for r: Dictionary in rows:
		if r["level"] != 1 or (not league_name.is_empty() and r["league"] != league_name):
			continue
		if r["kind"] == "b":
			for k: String in keys:
				var v: Variant = r.get(keys[k])
				t[k] += int(v) if v != null else 0
		elif r["kind"] == "p":
			t["outs"] += int(r["outs"])
			t["er"] += int(r["自責点"])
			t["ra"] += int(r["失点"])
	return t


func _avg(t: Dictionary) -> float:
	return float(t["h"]) / t["ab"]


func _obp(t: Dictionary) -> float:
	return float(t["h"] + t["bb"] + t["hbp"]) / (t["ab"] + t["bb"] + t["hbp"] + t["sf"])


func _slg(t: Dictionary) -> float:
	var tb: int = t["h"] + t["d"] + 2 * t["t"] + 3 * t["hr"]
	return float(tb) / t["ab"]


func _row(label: String, sim: Variant, real: Variant, fmt: String) -> void:
	print("  %-8s %8s %8s" % [label, fmt % sim, fmt % real])


func _load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("読めません: " + path)
		quit(1)
	return JSON.parse_string(text)
