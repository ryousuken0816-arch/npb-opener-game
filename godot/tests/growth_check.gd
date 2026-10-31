extends SceneTree
## 成長・衰え・引退（`Growth`、docs/AUTORUN.md 作業27）の確認（ヘッドレス）。
## 2026年シーズン後の能力値から、ゲームの年越しを使わずに Growth だけで YEARS 年ぶん進め、次を調べる：
## - 1人分：元のデータを変えない・ランクが値と合う・守備位置ごとの守備力が同じだけ動く・球速が範囲内・
##   守備の記録が無い新人に守備位置が付く・投手の役割とスタミナが食い違わない
## - リーグ全体の平均（target との差）と上位の人数（史実の直近10年の開幕時点と比べる）がほぼ一定
## - 20代前半で伸び、30代半ばから衰える（年齢ごとの1年の変化の平均）
## - 先発の人数・役割ごとのスタミナ・能力どうしの相関・球団ごとの主力の能力（表示のみ）
## - 引退：毎年の割合が史実の範囲（引退した分は、史実の直近10年の新人をひな形に、同じ球団・同じ守備位置で埋める）
## - 架空の選手（growth あり）：ピークの年齢でピーク近くまで育ち、そのあと衰える
## - 進めたあとの能力で1シーズン回し、打率・本塁打・防御率が開始時（史実の最後の能力）とほぼ同じ
##
##   godot --headless --path godot --script res://tests/growth_check.gd -- [年数] [シード]

const START_FILE := "2026_post.json"
const START_YEAR := 2027  ## START_FILE の能力で迎えるシーズン（2027年の開幕前の能力はこのファイルと同じ成績範囲）
const HISTORY_YEARS := [2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026]
const SEASON_SCHEDULE_YEAR := 2025
const STAR_VALUE := 70  ## 上位の人数：野手はミートかパワー、投手は総合がこれ以上（Bランク以上）

var _failures := 0
var _years := 10
var _seed := 27
var _root := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	if args.size() > 1:
		_seed = int(args[1])
	_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	_run.call_deferred()


func _run() -> void:
	var growth := Growth.new()
	_check(growth.is_ready(), "係数（generated/growth.json）を読めた")
	var start: Dictionary = _load_json("generated/ratings/" + START_FILE)
	var players: Array = start["players"].filter(func(p: Dictionary) -> bool:
		return not String(p.get("team", "")).is_empty() and not Growth._side(p).is_empty())
	_check_single(growth, players)
	_check_fictional(growth)
	_check_league(growth, players)
	print("\n%s（失敗 %d）" % ["OK" if _failures == 0 else "NG", _failures])
	quit(1 if _failures > 0 else 0)


# --- 1人分 -------------------------------------------------------------------------

func _check_single(growth: Growth, players: Array) -> void:
	print("== 1人分 ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var bad_rank := 0
	var bad_field := 0
	var bad_vel := 0
	var mutated := 0
	for p: Dictionary in players:
		var before := JSON.stringify(p)
		var q := growth.grow(p, START_YEAR + 1, rng)
		if JSON.stringify(p) != before:
			mutated += 1
		var side := Growth._side(q)
		var block: Dictionary = q["pitching"]["ratings"] if side == "P" else q["batting"]["ratings"]
		for key: String in block:
			var r: Variant = block[key]
			if r is Dictionary and r.get("value") != null and Growth.rank_of(float(r["value"])) != r["rank"]:
				bad_rank += 1
		if side == "B" and p.get("fielding") is Dictionary:
			var d_old: Variant = Growth._value(p, "B", "defense")
			var d_new: Variant = Growth._value(q, "B", "defense")
			for pos: String in p["fielding"]:
				var f0: Variant = p["fielding"][pos].get("defense")
				var f1: Variant = q["fielding"][pos].get("defense")
				if f0 is Dictionary and d_old != null:
					var want := clampi(int(f0["value"]) + roundi(float(d_new) - float(d_old)), 1, 100)
					# 端（1・100）に当たった位置は差がずれてよい
					if int(f1["value"]) != want and want > 1 and want < 100 and int(f0["value"]) < 100:
						bad_field += 1
		if side == "P" and q["pitching"].get("velocity") is Dictionary:
			var kmh := int(q["pitching"]["velocity"]["kmh"])
			if kmh < Growth.VELOCITY_MIN or kmh > Growth.VELOCITY_MAX:
				bad_vel += 1
	_check(mutated == 0, "元の選手データを変えない（変わった %d人）" % mutated)
	_check(bad_rank == 0, "ランクが値と合う（合わない %d件）" % bad_rank)
	_check(bad_field == 0, "守備位置ごとの守備力が主な位置と同じだけ動く（ずれ %d件）" % bad_field)
	_check(bad_vel == 0, "球速が範囲内（範囲外 %d人）" % bad_vel)
	# 出場量の更新
	var b: Dictionary = players.filter(func(p: Dictionary) -> bool: return Growth._side(p) == "B")[0]
	var q := growth.grow(b, START_YEAR + 1, rng, {"pa_1": 500.0, "pa_2": 0.0})
	var want_pa := 500.0 + Growth.SAMPLE_DECAY * float(b["batting"]["sample"]["pa_1"])
	_check(absf(float(q["batting"]["sample"]["pa_1"]) - want_pa) < 0.2, "今季の打席で出場量が更新される")
	# 守備の記録が無い新人の野手には、最初の成長で守備位置・守備力が付く
	var rookie: Dictionary = b.duplicate(true)
	rookie["fielding"] = {}
	rookie["primary_pos"] = "内野手"
	rookie["batting"]["ratings"].erase("defense")
	rookie["batting"]["ratings"].erase("arm")
	rookie["batting"]["sample"] = {"pa_1": 0.0, "pa_2": 0.0}
	rookie.erase("growth_year")
	var grown_rookie := growth.grow(rookie, START_YEAR + 1, rng)
	var fielding: Dictionary = grown_rookie["fielding"]
	_check(not fielding.is_empty() and fielding.has(grown_rookie["primary_pos"])
		and grown_rookie["primary_pos"] in ["一塁手", "二塁手", "三塁手", "遊撃手"]
		and grown_rookie["batting"]["ratings"].get("defense") is Dictionary,
		"守備の記録が無い新人（内野手）に内野の守備位置・守備力が付く（%s %s）" % [grown_rookie["primary_pos"], fielding.keys()])
	var pit: Dictionary = players.filter(func(p: Dictionary) -> bool: return Growth._side(p) == "P")[0]
	var roles_ok := true
	for i in 200:
		var g := growth.grow(pit, START_YEAR + 1, rng)
		var st := float(Growth._value(g, "P", "stamina"))
		if (g["pitching"]["role"] == "先発") != (st >= Growth.STARTER_STAMINA):
			roles_ok = false
	_check(roles_ok, "投手の役割とスタミナが食い違わない（先発はスタミナ %.1f 以上）" % Growth.STARTER_STAMINA)
	_check(Growth.age_at({"birth": "2000-04-01"}, 2028) == 28 and Growth.age_at({"birth": "2000-04-02"}, 2028) == 27,
		"年齢は4月1日時点の満年齢")


# --- 架空の選手 ----------------------------------------------------------------------

func _check_fictional(growth: Growth) -> void:
	print("\n== 架空の選手（ピークへ育つ）==")
	var base := {
		"id": "fic", "name": "架空 選手", "birth": "2010-05-10", "is_pitcher": false, "primary_pos": "遊撃手",
		"batting": {"ratings": {}, "sample": {"pa_1": 0.0, "pa_2": 0.0}, "trajectory": 2},
		"pitching": null, "fielding": {"遊撃手": {"games": 0, "defense": {"value": 50, "rank": "D"}, "arm": {"value": 50, "rank": "D"}}},
	}
	for key: String in ["meet", "power", "eye", "speed", "defense", "arm"]:
		base["batting"]["ratings"][key] = {"value": 45, "rank": "E"}
	for type: String in ["早熟", "普通", "晩成"]:
		var p: Dictionary = base.duplicate(true)
		p["growth"] = {"type": type, "peak": {"meet": 85, "power": 75, "eye": 70, "speed": 70, "defense": 75, "arm": 70}}
		var peak_age := Growth.peak_age_of(p)
		var by_age := {}
		for rep in 200:
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed * 1000 + rep
			var q := p
			for y in range(2029, 2048):  # 18歳 → 36歳
				q = growth.grow(q, y, rng)
				var age := Growth.age_at(q, y)
				if not by_age.has(age):
					by_age[age] = []
				by_age[age].append(float(q["batting"]["ratings"]["meet"]["value"]))
		var at_peak: float = Growth.mean_sd(by_age[peak_age])[0]
		var at_20: float = Growth.mean_sd(by_age[20])[0]
		var after: float = Growth.mean_sd(by_age[mini(peak_age + 6, 36)])[0]
		print("  %s（ピーク%d歳）ミート 20歳 %.1f → ピーク %.1f → %d歳 %.1f" % [type, peak_age, at_20, at_peak, mini(peak_age + 6, 36), after])
		_check(absf(at_peak - 85.0) <= 4.0, "%s：ピークの年齢でピーク（85）近くまで育つ" % type)
		_check(after < at_peak - 3.0, "%s：ピークの6年後には衰えている" % type)
	var early: Dictionary = base.duplicate(true)
	early["growth"] = {"type": "早熟", "peak": {"meet": 80}}
	var late: Dictionary = base.duplicate(true)
	late["growth"] = {"type": "晩成", "peak": {"meet": 80}}
	_check(Growth.peak_age_of(early) < Growth.peak_age_of(late), "早熟は晩成よりピークが早い")


# --- リーグ全体 ----------------------------------------------------------------------

func _check_league(growth: Growth, start_players: Array) -> void:
	print("\n== リーグ全体（%d年ぶん）==" % _years)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var debut := {}
	for r: Dictionary in _load_json("data/2026/rosters.json"):
		if r.get("player_id") != null and r.get("debut_year") != null:
			debut[r["player_id"]] = int(r["debut_year"])
	var history := _history_stats()
	var templates := _entrant_templates()
	print("  史実（%d〜%d年の開幕時点の平均）：%s" % [HISTORY_YEARS[0], HISTORY_YEARS[-1], _fmt(history)])

	var players: Array = start_players.duplicate(true)
	var fresh := {}
	var deltas := {}  # 年齢 → [打者 ミート+パワー の変化, 投手 総合 の変化]
	var retired_counts: Array[int] = []
	var retired_rates: Array[float] = []
	var retire_ages: Array[float] = []
	var stats_by_year: Array = []
	var serial := 0
	for i in _years:
		var year := START_YEAR + 1 + i
		# 引退（前のシーズン後）→ 同じ球団・同じ守備位置（投手は投手）の新人で埋める（球団の編成で位置の偏りが出ないように）
		var keep: Array = []
		var retired := 0
		for p: Dictionary in players:
			var foreign := RosterRules.is_foreign(p, year - 1, debut.get(p["id"]))
			if growth.should_retire(p, year, foreign, rng):
				retired += 1
				retire_ages.append(Growth.age_at(p, year - 1))
				var pool: Array = templates.get(_slot(p), templates[Growth._side(p)])
				var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
				var rookie: Dictionary = t["player"].duplicate(true)
				serial += 1
				rookie["id"] = "sim:%d" % serial
				rookie["team"] = p["team"]
				rookie["league"] = p["league"]
				var birth: String = rookie["birth"]
				rookie["birth"] = "%d%s" % [int(birth.substr(0, 4)) + year - int(t["year"]), birth.substr(4)]
				keep.append(rookie)
				fresh[rookie["id"]] = true
			else:
				keep.append(p)
		retired_counts.append(retired)
		retired_rates.append(float(retired) / players.size())
		var before := {}
		for p: Dictionary in keep:
			before[p["id"]] = p
		players = growth.grow_league(keep, year, rng, fresh)
		fresh.clear()
		for q: Dictionary in players:
			var p0: Dictionary = before[q["id"]]
			# 入団1年目（事前値 → 1年目の成績が入った値）の変化は除く
			if not q.has("growth_year") or not p0.has("growth_year"):
				continue
			var age := Growth.age_at(q, year)
			if not deltas.has(age):
				deltas[age] = [[], []]
			if Growth._side(q) == "B":
				deltas[age][0].append((float(Growth._value(q, "B", "meet")) + float(Growth._value(q, "B", "power"))
					- float(Growth._value(p0, "B", "meet")) - float(Growth._value(p0, "B", "power"))) / 2.0)
			else:
				deltas[age][1].append(float(Growth._value(q, "P", "overall")) - float(Growth._value(p0, "P", "overall")))
		var s := _stats(players)
		stats_by_year.append(s)
		print("  %d年 引退%3d人 %s" % [year, retired, _fmt(s)])

	# 平均と上位の人数が史実の頃とほぼ同じ
	var last: Dictionary = stats_by_year[-1]
	for key: String in ["B:meet", "B:power", "B:speed", "P:overall", "P:k9", "P:stamina"]:
		_check(absf(float(last[key]) - float(history[key])) <= 2.5,
			"%d年後の平均 %s が史実（%.1f）の±2.5（%.1f）" % [_years, key, history[key], last[key]])
	for key: String in ["B:stars", "P:stars"]:
		var ratio := float(last[key]) / maxf(1.0, float(history[key]))
		_check(ratio >= 0.6 and ratio <= 1.6, "%d年後の上位の人数 %s が史実（%.0f）の0.6〜1.6倍（%d）" % [_years, key, history[key], last[key]])
	# 引退の人数
	var avg_retired := 0.0
	for n in retired_counts:
		avg_retired += n
	avg_retired /= retired_counts.size()
	var rate: float = Growth.mean_sd(retired_rates)[0]
	var avg_age: float = Growth.mean_sd(retire_ages)[0]
	print("  引退：平均 %.1f人/年（%.1f%%）、平均 %.1f歳" % [avg_retired, rate * 100.0, avg_age])
	_check(rate >= 0.09 and rate <= 0.17, "毎年の引退の割合が史実（約13%）に近い（9〜17%）")
	_check(avg_age >= 27.0 and avg_age <= 34.0, "引退の平均年齢が27〜34歳")
	# 年齢ごとの変化
	print("  年齢ごとの1年の変化の平均（打者 ミート・パワー／投手 総合。入団1年目を除く）")
	var young := [[], []]
	var old := [[], []]
	for age: int in range(19, 41):
		if not deltas.has(age):
			continue
		var b: Array = deltas[age][0]
		var p: Array = deltas[age][1]
		print("    %d歳 打者 %+.2f（%d人） 投手 %+.2f（%d人）" % [age, Growth.mean_sd(b)[0], b.size(), Growth.mean_sd(p)[0], p.size()])
		for k in 2:
			if age <= 24:
				young[k].append_array(deltas[age][k])
			elif age >= 35:
				old[k].append_array(deltas[age][k])
	_check(Growth.mean_sd(young[0])[0] > 0.2, "打者は24歳以下で伸びる")
	_check(Growth.mean_sd(old[0])[0] < -0.5, "打者は35歳以上で衰える")
	# 史実でもリーグ平均くらいの35歳以上の投手の総合は1年で −0.4 ほど（年齢ごとの人数が少なく、ぶれる）
	_check(Growth.mean_sd(old[1])[0] < -0.2, "投手は35歳以上で衰える")
	_check(Growth.mean_sd(young[1])[0] > Growth.mean_sd(old[1])[0] + 1.0, "投手は若いほうが35歳以上より伸びる")
	for pair: Array in [["B", "meet", "power"], ["B", "meet", "eye"], ["P", "overall", "k9"], ["P", "overall", "bb9"],
			["P", "overall", "hr9"], ["P", "overall", "stamina"]]:
		print("  相関 %s-%s：開始時 %.2f → %d年後 %.2f" % [pair[1], pair[2], _corr(start_players, pair), _years, _corr(players, pair)])
	print("  開始時の主力：" + _regulars(start_players))
	print("  %d年後の主力：" % _years + _regulars(players))
	_check_season(players, start_players)


## 球団ごとの主力（先発6人・救援7人は総合順、野手9人は打撃の総合順）の平均。
## 投手は 総合・K9・BB9・HR9 の z とスタミナ、野手は ミート・パワー・選球眼・走力・主な位置の守備力 の z
func _regulars(players: Array) -> String:
	var by_team := {}
	for p: Dictionary in players:
		if not by_team.has(p["team"]):
			by_team[p["team"]] = []
		by_team[p["team"]].append(SimPlayer.from_rating(p))
	var acc := {"sp": [0.0, 0.0, 0.0, 0.0, 0.0, 0], "rp": [0.0, 0.0, 0.0, 0.0, 0.0, 0], "b": [0.0, 0.0, 0.0, 0.0, 0.0, 0]}
	for team: String in by_team:
		var list: Array = by_team[team]
		var sp: Array = list.filter(func(x: SimPlayer) -> bool: return x.is_pitcher and x.role == "先発")
		var rp: Array = list.filter(func(x: SimPlayer) -> bool: return x.is_pitcher and x.role != "先発")
		var bt: Array = list.filter(func(x: SimPlayer) -> bool: return not x.is_pitcher)
		sp.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.overall > b.overall)
		rp.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.overall > b.overall)
		bt.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.batting_value() > b.batting_value())
		for x: SimPlayer in sp.slice(0, 6):
			_acc(acc["sp"], [x.overall, x.k9, x.bb9, x.hr9, x.stamina])
		for x: SimPlayer in rp.slice(0, 7):
			_acc(acc["rp"], [x.overall, x.k9, x.bb9, x.hr9, x.stamina])
		for x: SimPlayer in bt.slice(0, 9):
			_acc(acc["b"], [x.meet, x.power, x.eye, x.speed, x.defense_at(x.primary_pos) if not x.primary_pos.is_empty() else -2.5])
	var out := ""
	for k: String in ["sp", "rp", "b"]:
		var a: Array = acc[k]
		var n := maxf(1.0, a[5])
		out += "%s(%d) %.2f %.2f %.2f %.2f %.2f ／ " % [k, a[5], a[0] / n, a[1] / n, a[2] / n, a[3] / n, a[4] / n]
	return out


func _acc(a: Array, v: Array) -> void:
	for i in v.size():
		a[i] += v[i]
	a[5] += 1


func _corr(players: Array, pair: Array) -> float:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for p: Dictionary in players:
		if Growth._side(p) != pair[0]:
			continue
		var x: Variant = Growth._value(p, pair[0], pair[1])
		var y: Variant = Growth._value(p, pair[0], pair[2])
		if x != null and y != null:
			xs.append(float(x))
			ys.append(float(y))
	var mx: float = Growth.mean_sd(xs)[0]
	var my: float = Growth.mean_sd(ys)[0]
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in xs.size():
		sxy += (xs[i] - mx) * (ys[i] - my)
		sxx += (xs[i] - mx) * (xs[i] - mx)
		syy += (ys[i] - my) * (ys[i] - my)
	return sxy / sqrt(maxf(1e-9, sxx * syy))


func _check_season(grown: Array, start_players: Array) -> void:
	print("\n== 進めたあとの能力で1シーズン（%d年の日程）==" % SEASON_SCHEDULE_YEAR)
	var schedule: Array = _load_json("data/%d/schedule.json" % SEASON_SCHEDULE_YEAR)
	var rows := {}
	for label: String in ["開始時", "%d年後" % _years]:
		var src: Array = start_players if label == "開始時" else grown
		var season := Season.new(START_YEAR, {"players": src.duplicate(true)}, schedule, _seed)
		season.sim_all()
		var t := season.league_totals()
		var avg := float(t["h"]) / maxf(1.0, t["ab"])
		var hr := float(t["hr"]) / maxf(1.0, t["games"])
		var era := float(t["er"]) * 27.0 / maxf(1.0, t["outs"])
		rows[label] = [avg, hr, era]
		print("  %s 打率 %.3f 本塁打/試合 %.2f 防御率 %.2f（%d試合）" % [label, avg, hr, era, t["games"] / 2])
	# 試合のシミュレーション自体が史実より打高（2025年の能力・日程で打率 .269・防御率 3.82、史実 .244・3.01。
	# tests/season_check.gd）なので、絶対値ではなく開始時（史実の最後の能力）からのずれで見る
	var s0: Array = rows["開始時"]
	var g: Array = rows["%d年後" % _years]
	_check(absf(g[0] - s0[0]) <= 0.012, "打率が開始時の±.012")
	_check(g[1] >= s0[1] * 0.8 and g[1] <= s0[1] * 1.25, "本塁打が開始時の0.8〜1.25倍")
	_check(absf(g[2] - s0[2]) <= 0.35, "防御率が開始時の±0.35")


# --- 集計 ------------------------------------------------------------------------

func _stats(players: Array) -> Dictionary:
	var vals := {}
	var stars := {"B": 0, "P": 0}
	for p: Dictionary in players:
		var side := Growth._side(p)
		if side.is_empty():
			continue
		for key: String in (["meet", "power", "speed"] if side == "B" else ["overall", "k9", "stamina"]):
			var v: Variant = Growth._value(p, side, key)
			if v != null:
				var k := "%s:%s" % [side, key]
				if not vals.has(k):
					vals[k] = []
				vals[k].append(float(v))
		var top: float = maxf(float(Growth._value(p, "B", "meet")), float(Growth._value(p, "B", "power"))) 			if side == "B" else float(Growth._value(p, "P", "overall"))
		if top >= STAR_VALUE:
			stars[side] += 1
	var out := {"B:stars": stars["B"], "P:stars": stars["P"], "n": players.size(),
		"P:starters": players.filter(func(x: Dictionary) -> bool:
			return Growth._side(x) == "P" and x["pitching"].get("role") == "先発").size()}
	for k: String in vals:
		var ms := Growth.mean_sd(vals[k])
		out[k] = ms[0]
		out[k + ":sd"] = ms[1]
	return out


func _history_stats() -> Dictionary:
	var sums := {}
	for y: int in HISTORY_YEARS:
		var s := _stats(_load_json("generated/ratings/%d_pre.json" % y)["players"].filter(
			func(p: Dictionary) -> bool: return not String(p.get("team", "")).is_empty()))
		for k: String in s:
			sums[k] = float(sums.get(k, 0.0)) + float(s[k]) / HISTORY_YEARS.size()
	return sums


## 史実の新人（その年の開幕時点にいて、前年のシーズン後にいない、ドラフトで入った選手）
func _entrant_templates() -> Dictionary:
	var out := {"B": [], "P": []}
	for y: int in HISTORY_YEARS:
		var prev := {}
		for p: Dictionary in _load_json("generated/ratings/%d_post.json" % (y - 1))["players"]:
			prev[p["id"]] = true
		for p: Dictionary in _load_json("generated/ratings/%d_pre.json" % y)["players"]:
			var side := Growth._side(p)
			# 2028年以降は新外国人が来ない前提なので、ドラフトで入った国内の新人だけ
			if prev.has(p["id"]) or side.is_empty() or Growth.age_at(p, y) < 0 or String(p.get("draft", "")).is_empty():
				continue
			var t := {"year": y, "player": p}
			out[side].append(t)
			var slot := _slot(p)
			if not out.has(slot):
				out[slot] = []
			out[slot].append(t)
	return out


## 新人で埋めるときの区分（投手は投手、野手は主な守備位置）
static func _slot(p: Dictionary) -> String:
	if Growth._side(p) == "P":
		return "P"
	return "B:" + str(p.get("primary_pos", ""))


func _fmt(s: Dictionary) -> String:
	return "打者 ミート%.1f±%.1f パワー%.1f±%.1f 走力%.1f 上位%d ／ 投手 総合%.1f±%.1f K9 %.1f スタミナ%.1f 上位%d 先発%d" % [
		s["B:meet"], s["B:meet:sd"], s["B:power"], s["B:power:sd"], s["B:speed"], int(s["B:stars"]),
		s["P:overall"], s["P:overall:sd"], s["P:k9"], s["P:stamina"], int(s["P:stars"]), int(s["P:starters"])]


func _load_json(relative: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(_root.path_join(relative)))


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
