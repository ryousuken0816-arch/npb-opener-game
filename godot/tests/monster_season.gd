extends SceneTree
## 怪物を1人ずつ2026年のシーズンに入れて、1年目の成績を見る（docs/AUTORUN.md 作業85。表示だけ。ヘッドレスで1〜2分）。
## 高卒の怪物の打者・投手を何人か作り、球団ごとに1人ずつ、その球団の中堅の主力（打者は5番目に強い野手、投手は3番目にスタミナのある投手）と
## 入れ替えて1シーズン（能力は開幕のまま）回し、成績を出す。比べるために、リーグの打撃・投手の上位も出す。
##
##   godot --headless --path godot -s res://tests/monster_season.gd -- [打者の人数] [投手の人数] [シード] [hs|all]

const YEAR := 2026

var _n_bat := 5
var _n_pit := 5
var _seed := 1
var _hs_only := true


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_n_bat = int(args[0])
	if args.size() > 1:
		_n_pit = int(args[1])
	if args.size() > 2:
		_seed = int(args[2])
	if args.size() > 3:
		_hs_only = args[3] != "all"
	_run.call_deferred()


func _run() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var ratings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("generated/ratings/%d_pre.json" % YEAR)))
	var schedule: Array = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("data/%d/schedule.json" % YEAR)))
	PitchArsenal.ensure_all(ratings.get("players", []), YEAR)

	# 怪物を集める
	var fd: RefCounted = (load("res://sim/fictional_draft.gd") as GDScript).new()
	var bats: Array = []
	var pits: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 8500 + _seed
	var y := 2028
	while (bats.size() < _n_bat or pits.size() < _n_pit) and y < 2400:
		for p: Dictionary in fd.generate_year(y, rng):
			if not bool(p.get("is_monster", false)):
				continue
			if _hs_only and str(p["category"]) != "高校":
				continue
			if bool(p["is_pitcher"]):
				if pits.size() < _n_pit:
					PitchArsenal.ensure(p, y + 1)
					pits.append(p)
			elif bats.size() < _n_bat:
				bats.append(p)
		y += 1

	# 球団ごとに入れ替える
	var by_team := {}
	for p: Dictionary in ratings["players"]:
		if not p["team"].is_empty():
			if not by_team.has(p["team"]):
				by_team[p["team"]] = []
			by_team[p["team"]].append(p)
	var teams: Array = by_team.keys()
	teams.sort()
	var injected: Array = []  # [id, 種類, 怪物, 入れ替えた選手の名前, 球団]
	var ti := 0
	for m: Dictionary in bats:
		var team: String = teams[ti % teams.size()]
		ti += 1
		var hitters: Array = by_team[team].filter(func(q: Dictionary) -> bool: return not q["is_pitcher"])
		hitters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _bat_sum(a) > _bat_sum(b))
		var target: Dictionary = hitters[4]
		var old_name := str(target["name"])
		target["batting"] = m["batting"].duplicate(true)
		target["batting"]["sample"] = {"pa_1": 0.0, "pa_2": 0.0}
		injected.append([target["id"], "B", m, old_name, team])
	for m: Dictionary in pits:
		var team: String = teams[ti % teams.size()]
		ti += 1
		var arms: Array = by_team[team].filter(func(q: Dictionary) -> bool: return q["is_pitcher"] and str(q["pitching"].get("role", "")) == "先発")
		arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _stamina(a) > _stamina(b))
		var target: Dictionary = arms[mini(2, arms.size() - 1)]
		var old_name := str(target["name"])
		var keep_role: String = str(target["pitching"].get("role", "先発"))
		target["pitching"] = m["pitching"].duplicate(true)
		target["pitching"]["role"] = keep_role
		target["pitching"]["sample"] = {"outs_1": 0.0, "outs_2": 0.0}
		injected.append([target["id"], "P", m, old_name, team])
	PitchArsenal.ensure_all(ratings["players"], YEAR)

	var season := Season.new(YEAR, ratings, schedule, 77 + _seed, {})
	season.sim_all()

	print("== 怪物を入れた %d年のシーズン（高卒のみ：%s） ==" % [YEAR, str(_hs_only)])
	for row: Array in injected:
		var id: String = row[0]
		var m: Dictionary = row[2]
		var r: Dictionary = m["pitching"]["ratings"] if row[1] == "P" else m["batting"]["ratings"]
		var ab: Array = []
		for k: String in (["k9", "bb9", "hr9", "stamina"] if row[1] == "P" else ["meet", "power", "eye", "speed", "defense"]):
			ab.append("%s%d" % [k, int(r[k]["value"])])
		if row[1] == "B":
			var b: Dictionary = season.batting.get(id, {})
			if b.is_empty() or int(b["pa"]) == 0:
				print("%s %s（%s の %s と入れ替え）出場なし" % [m["category"], "打者", row[4], row[3]])
				continue
			var ab_n := maxf(1.0, float(b["ab"]))
			var obp := (float(b["h"]) + float(b["bb"]) + float(b.get("hbp", 0))) / maxf(1.0, float(b["pa"]))
			var slg := (float(b["h"]) + float(b["d"]) + 2.0 * float(b["t"]) + 3.0 * float(b["hr"])) / ab_n
			print("%s 打者（%s）%d打席 打率%.3f 出塁%.3f 長打%.3f OPS%.3f %d本 %d打点 %d盗塁　%s" % [m["category"], row[4], int(b["pa"]),
				Season.batting_avg(b), obp, slg, obp + slg, int(b["hr"]), int(b["rbi"]), int(b["sb"]), " ".join(ab)])
		else:
			var pt: Dictionary = season.pitching.get(id, {})
			if pt.is_empty() or int(pt["outs"]) == 0:
				print("%s 投手（%s）登板なし" % [m["category"], row[4]])
				continue
			print("%s 投手（%s）%d試合 %.1f回 %d勝%d敗 防御率%.2f 奪三振%d（9回あたり %.1f）与四球%d 被本塁打%d 球速%d　%s" % [m["category"], row[4], int(pt["g"]),
				float(pt["outs"]) / 3.0, int(pt["w"]), int(pt["l"]), Season.era(pt), int(pt["so"]), 27.0 * float(pt["so"]) / float(pt["outs"]),
				int(pt["bb"]), int(pt["hr"]), int(m["pitching"]["velocity"]["kmh"]), " ".join(ab)])

	# リーグの上位（比べる用）
	var bs: Array = season.batting.keys().filter(func(id: String) -> bool: return int(season.batting[id]["pa"]) >= 446)
	bs.sort_custom(func(a: String, b: String) -> bool: return _ops(season.batting[a]) > _ops(season.batting[b]))
	var line := "リーグの打者（446打席以上）OPS 上位："
	for id: String in bs.slice(0, 5):
		line += " %.3f（%d本）" % [_ops(season.batting[id]), int(season.batting[id]["hr"])]
	print(line)
	bs.sort_custom(func(a: String, b: String) -> bool: return int(season.batting[a]["hr"]) > int(season.batting[b]["hr"]))
	line = "　本塁打 上位："
	for id: String in bs.slice(0, 5):
		line += " %d" % int(season.batting[id]["hr"])
	print(line)
	var ps: Array = season.pitching.keys().filter(func(id: String) -> bool: return int(season.pitching[id]["outs"]) >= 3 * 120)
	ps.sort_custom(func(a: String, b: String) -> bool: return Season.era(season.pitching[a]) < Season.era(season.pitching[b]))
	line = "リーグの投手（120回以上）防御率 上位："
	for id: String in ps.slice(0, 5):
		line += " %.2f（%d三振・%d勝）" % [Season.era(season.pitching[id]), int(season.pitching[id]["so"]), int(season.pitching[id]["w"])]
	print(line)
	ps.sort_custom(func(a: String, b: String) -> bool: return int(season.pitching[a]["so"]) > int(season.pitching[b]["so"]))
	line = "　奪三振 上位："
	for id: String in ps.slice(0, 5):
		line += " %d" % int(season.pitching[id]["so"])
	print(line)
	quit(0)


func _ops(b: Dictionary) -> float:
	var ab_n := maxf(1.0, float(b["ab"]))
	var obp := (float(b["h"]) + float(b["bb"]) + float(b.get("hbp", 0))) / maxf(1.0, float(b["pa"]))
	return obp + (float(b["h"]) + float(b["d"]) + 2.0 * float(b["t"]) + 3.0 * float(b["hr"])) / ab_n


func _bat_sum(p: Dictionary) -> float:
	var r: Dictionary = p["batting"]["ratings"]
	return float(r["meet"]["value"]) + float(r["power"]["value"]) + 0.5 * float(r["eye"]["value"])


func _stamina(p: Dictionary) -> float:
	var s: Variant = p["pitching"]["ratings"].get("stamina")
	return float(s["value"]) if s is Dictionary else 0.0
