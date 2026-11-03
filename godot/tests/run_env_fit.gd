extends SceneTree
## 年ごとの点の入りやすさ（RunEnv、作業70）を合わせ込む。tools/fit_run_env.py から呼ぶ（年を分けて並列に流す）。
##
##   godot --headless --path godot --script res://tests/run_env_fit.gd -- <年,年,...> <回数> <出力の JSON> [種]
##
## 1年ずつ、ゲームと同じ流れ（月替わりに能力を post へ寄せる。season_check と同じ）で1シーズン回し、リーグ全体の
## 三振率・四球率・本塁打率・BABIP を史実（data/<年>/teamstats_linked.json の1軍）と比べて、ずれ（ロジット）を直す。
## 回数ぶん繰り返し、最後のずれと、最後に回した成績を出力する

const REPO := "res://.."
## BABIP のロジットの差 → 鋭い当たりのずれ（鋭い当たり以外も BABIP に入るので、差より大きく動かす）
const SHARP_GAIN := 1.6
## 1回に動かす割合（乱数のぶれで行き過ぎないように）
const STEP := 0.9


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var years: Array = Array(args[0].split(",")).map(func(s: String) -> int: return int(s))
	var rounds := int(args[1])
	var out_path: String = args[2]
	var seed_base := int(args[3]) if args.size() > 3 else 1
	var root := ProjectSettings.globalize_path(REPO).simplify_path()
	var result := {}
	for year: int in years:
		var env: Dictionary = RunEnv.for_year(year).duplicate()
		for k: String in RunEnv.KEYS:
			env[k] = float(env.get(k, 0.0))
		var real := _actual(_load_json(root.path_join("data/%d/teamstats_linked.json" % year)))
		var last := {}
		for r in rounds:
			var sim := _sim_year(root, year, env, seed_base * 100 + r)
			last = _summary(sim)
			var target := _summary(real)
			print("%d年 %d回目 ずれ %s → 打率 %.3f/%.3f 本塁打 %d/%d 防御率 %.2f/%.2f 三振%% %.1f/%.1f 四球%% %.1f/%.1f BABIP %.3f/%.3f" % [
				year, r + 1, _fmt(env), last["avg"], target["avg"], sim["hr"], real["hr"], last["era"], target["era"],
				100 * last["k"], 100 * target["k"], 100 * last["bb"], 100 * target["bb"], last["babip"], target["babip"]])
			env["k"] += STEP * (_logit(target["k"]) - _logit(last["k"]))
			env["bb"] += STEP * (_logit(target["bb"]) - _logit(last["bb"]))
			env["hr"] += STEP * (_logit(target["hr"]) - _logit(last["hr"]))
			env["sharp"] += STEP * SHARP_GAIN * (_logit(target["babip"]) - _logit(last["babip"]))
		for k: String in RunEnv.KEYS:
			env[k] = snappedf(env[k], 0.001)
		result[str(year)] = {"env": env, "last": last, "real": _summary(real)}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " "))
	f.close()
	quit()


func _sim_year(root: String, year: int, env: Dictionary, seed_value: int) -> Dictionary:
	var ratings: Dictionary = _load_json(root.path_join("generated/ratings/%d_pre.json" % year))
	var schedule: Array = _load_json(root.path_join("data/%d/schedule.json" % year))
	var debut_years := {}
	for r: Dictionary in _load_json(root.path_join("data/%d/rosters.json" % year)):
		if r.get("player_id") != null and r.get("debut_year") != null:
			debut_years[r["player_id"]] = r["debut_year"]
	var season := Season.new(year, ratings, schedule, seed_value, debut_years)
	season.env = env
	var post_path := root.path_join("generated/ratings/%d_post.json" % year)
	var post: Dictionary = _load_json(post_path) if FileAccess.file_exists(post_path) else {}
	if not post.is_empty() and SeasonBlend.applies(ratings, post):
		var by_id := {}
		var post_by_id := {}
		var base := {}
		for p: Dictionary in ratings["players"]:
			by_id[p["id"]] = p
		for q: Dictionary in post["players"]:
			post_by_id[q["id"]] = q
		var shift := SeasonBlend.league_shift(ratings["players"], post_by_id)
		for m: int in season.months():
			season.sim_month(m)
			var t := SeasonBlend.fraction(season.played_count(), season.scheduled_count())
			for id: String in by_id:
				if post_by_id.has(id):
					if not base.has(id):
						base[id] = SeasonBlend.snapshot(by_id[id])
					SeasonBlend.blend(by_id[id], base[id], post_by_id[id], t, shift)
			season.refresh_ratings(func(id: String) -> Dictionary: return by_id.get(id, {}), season.teams.keys())
	season.sim_all()
	return season.league_totals("")


## 三振率・四球率（死球を除く打席あたり）・本塁打率・BABIP・打率・防御率
func _summary(t: Dictionary) -> Dictionary:
	var pa := float(t["pa"])
	var bip := float(t["ab"] - t["so"] - t["hr"] + t["sf"])
	return {
		"k": t["so"] / pa, "bb": t["bb"] / pa, "hr": t["hr"] / pa,
		"babip": float(t["h"] - t["hr"]) / bip, "avg": float(t["h"]) / t["ab"],
		"era": t["er"] * 27.0 / t["outs"], "hr_n": t["hr"],
	}


func _actual(rows: Array) -> Dictionary:
	var t := {"pa": 0, "ab": 0, "h": 0, "hr": 0, "bb": 0, "so": 0, "sf": 0, "outs": 0, "er": 0}
	var keys := {"pa": "打席", "ab": "打数", "h": "安打", "hr": "本塁打", "bb": "四球", "so": "三振", "sf": "犠飛"}
	for r: Dictionary in rows:
		if r["level"] != 1:
			continue
		if r["kind"] == "b":
			for k: String in keys:
				var v: Variant = r.get(keys[k])
				t[k] += int(v) if v != null else 0
		elif r["kind"] == "p":
			t["outs"] += int(r["outs"])
			t["er"] += int(r["自責点"])
	return t


func _fmt(env: Dictionary) -> String:
	return "k%+.3f bb%+.3f hr%+.3f sharp%+.3f" % [env["k"], env["bb"], env["hr"], env["sharp"]]


static func _logit(p: float) -> float:
	return log(p / (1.0 - p))


func _load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("読めません: " + path)
		quit(1)
	return JSON.parse_string(text)
