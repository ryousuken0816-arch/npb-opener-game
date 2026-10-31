extends SceneTree
## 架空の外国人選手（`ForeignPlayers`、docs/AUTORUN.md 作業31）の確認（ヘッドレス）。
## - 作る選手：人数・出身の割合・年齢・1年目の実力が史実の新外国人（generated/foreign.json）に近い、外国人と判定される、
##   名前が年内で重ならない、ランク・役割とスタミナが食い違わない
## - 2026年シーズン後から YEARS 年ぶん、ゲームの年越しを使わずに進める（引退・退団は Growth、国内の引退は史実の新人で埋め、
##   毎年作った外国人を外国人の少ない球団から評価の高い順に獲る、Growth で成長）：
##   球団ごとの外国人の人数が史実の頃と同じくらい、1年で退団する選手の割合が史実に近い、当たりの選手ほど長く在籍する
##
##   godot --headless --path godot --script res://tests/foreign_check.gd -- [年数] [シード]

const START_FILE := "2026_post.json"
const START_YEAR := 2027
const DOMESTIC_YEARS := [2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026]
const MARKET_NOISE := 0.3  ## LeagueRoster.MARKET_NOISE と同じくらいの評価の誤差

var _failures := 0
var _years := 10
var _seed := 31
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
	var fp := ForeignPlayers.new({}, growth)
	_check(fp.is_ready(), "ひな形（generated/foreign.json）を読めた")
	_check_generation(fp)
	_check_league(growth, fp)
	print("\n%s（失敗 %d）" % ["OK" if _failures == 0 else "NG", _failures])
	quit(1 if _failures > 0 else 0)


# --- 作る選手 -----------------------------------------------------------------------

func _check_generation(fp: ForeignPlayers) -> void:
	print("== 作る選手（30年ぶん）==")
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var counts: Array[int] = []
	var origins := {}
	var ages: Array[float] = []
	var z := {"P": [], "B": []}
	var not_foreign := 0
	var dup_names := 0
	var bad := 0
	var ids := {}
	var total := 0
	for i in 30:
		var year := 2028 + i
		var crop := fp.generate_year(year, rng)
		counts.append(crop.size())
		var names := {}
		for p: Dictionary in crop:
			total += 1
			ids[p["id"]] = true
			if names.has(p["name"]):
				dup_names += 1
			names[p["name"]] = true
			if not RosterRules.is_foreign(p, year, null):
				not_foreign += 1
			var c: String = p["import"]["country"]
			var group := "中南米" if c in fp.data["latin_split"] else c
			origins[group] = int(origins.get(group, 0)) + 1
			ages.append(Growth.age_at(p, year))
			var side := Growth._side(p)
			z[side].append(float(Salary.ability(p)[0]))
			if side == "P":
				var st := float(Growth._value(p, "P", "stamina"))
				if (p["pitching"]["role"] == "先発") != (st >= Growth.STARTER_STAMINA):
					bad += 1
				for key: String in p["pitching"]["ratings"]:
					var r: Dictionary = p["pitching"]["ratings"][key]
					if Growth.rank_of(float(r["value"])) != r["rank"]:
						bad += 1
	var lo := 999
	var hi := 0
	for y: Variant in fp.data["count_years"]:
		var c: Dictionary = fp.data["counts"][str(int(y))]
		lo = mini(lo, int(c["p"]) + int(c["b"]))
		hi = maxi(hi, int(c["p"]) + int(c["b"]))
	var count_ok := true
	for n in counts:
		count_ok = count_ok and n >= lo and n <= hi
	print("  人数/年 %s（史実 %d〜%d）" % [str(counts.slice(0, 10)), lo, hi])
	_check(count_ok, "毎年の人数が史実の直近10年の範囲")
	_check(ids.size() == total, "選手IDが重ならない")
	_check(dup_names == 0, "同じ年の名前が重ならない（重なり %d）" % dup_names)
	_check(not_foreign == 0, "全員が外国人と判定される（RosterRules.is_foreign）")
	_check(bad == 0, "ランクが値と合い、役割とスタミナが食い違わない（%d件）" % bad)
	var share: Dictionary = fp.data["origin_share"]
	for g: String in ["米国", "中南米"]:
		var got := float(origins.get(g, 0)) / total
		print("  出身 %s %.1f%%（史実 %.1f%%）" % [g, got * 100.0, float(share[g]) * 100.0])
		_check(absf(got - float(share[g])) <= 0.07, "出身の割合（%s）が史実の±7%%" % g)
	var hist_ages: Array[float] = []
	var hist_z := {"P": [], "B": []}
	for t: Dictionary in fp.data["templates"]:
		hist_ages.append(float(t["age"]))
		hist_z[t["side"]].append(float(t["z"]))
	var a: float = Growth.mean_sd(ages)[0]
	var ha: float = Growth.mean_sd(hist_ages)[0]
	print("  年齢 平均 %.1f（史実 %.1f）" % [a, ha])
	_check(absf(a - ha) <= 1.5, "年齢の平均が史実の±1.5歳")
	for side: String in ["P", "B"]:
		var m: Array = Growth.mean_sd(z[side])
		var hm: Array = Growth.mean_sd(hist_z[side])
		print("  %s 1年目の実力 z 平均 %.2f sd %.2f（史実 %.2f / %.2f）" % [side, m[0], m[1], hm[0], hm[1]])
		_check(absf(float(m[0]) - float(hm[0])) <= 0.1 and float(m[1]) >= float(hm[1]) * 0.75 and float(m[1]) <= float(hm[1]) * 1.3,
			"%s：1年目の実力の平均・ばらつきが史実に近い" % ("投手" if side == "P" else "野手"))


# --- リーグで進める ------------------------------------------------------------------

func _check_league(growth: Growth, fp: ForeignPlayers) -> void:
	print("\n== リーグで%d年進める ==" % _years)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var start: Dictionary = _load_json("generated/ratings/" + START_FILE)
	var players: Array = start["players"].filter(func(p: Dictionary) -> bool:
		return not String(p.get("team", "")).is_empty() and not Growth._side(p).is_empty())
	var debut := {}
	for r: Dictionary in _load_json("data/2026/rosters.json"):
		if r.get("player_id") != null and r.get("debut_year") != null:
			debut[r["player_id"]] = int(r["debut_year"])
	var templates := _domestic_templates()
	var target := roundi(float(fp.data["per_team_foreigners"]))
	var league_of := {}
	for p: Dictionary in players:
		league_of[p["team"]] = p["league"]
	var joined := {}   # 架空の外国人 → [来た年, 1年目の実力 z]
	var tenures: Array = []  # [在籍年数, 1年目の実力 z, まだ在籍しているか, 来た年]
	var serial := 0
	var per_team_last := {}
	for i in _years:
		var year := START_YEAR + 1 + i
		var keep: Array = []
		var fresh := {}
		for p: Dictionary in players:
			var foreign := RosterRules.is_foreign(p, year - 1, debut.get(p["id"]))
			if not growth.should_retire(p, year, foreign, rng):
				keep.append(p)
				continue
			if joined.has(p["id"]):
				tenures.append([year - int(joined[p["id"]][0]), joined[p["id"]][1], false, joined[p["id"]][0]])
			if foreign:
				continue
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
		# 外国人市場：外国人の少ない球団から、評価（実力＋出場の見込み＋誤差）の高い順に獲る
		var crop := fp.generate_year(year, rng)
		var value := {}
		for c: Dictionary in crop:
			var a := Salary.ability(c)
			value[c["id"]] = float(a[0]) + 0.5 * float(a[1]) + rng.randfn(0.0, MARKET_NOISE)
		crop.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return value[x["id"]] > value[y["id"]])
		var count := _foreign_count(keep, year, debut, league_of)
		while not crop.is_empty():
			var team := ""
			for tm: String in count:
				if count[tm] < target and (team.is_empty() or count[tm] < count[team]):
					team = tm
			if team.is_empty():
				break
			var c: Dictionary = crop.pop_front()
			c["team"] = team
			c["league"] = league_of[team]
			keep.append(c)
			fresh[c["id"]] = true
			joined[c["id"]] = [year, float(Salary.ability(c)[0])]
			count[team] += 1
		players = growth.grow_league(keep, year, rng, fresh)
		per_team_last = _foreign_count(players, year, debut, league_of)
		var total := 0
		for tm: String in per_team_last:
			total += per_team_last[tm]
		print("  %d年 外国人 %d人（1球団 %.1f人、架空 %d人）" % [year, total, float(total) / per_team_last.size(),
			players.filter(func(p: Dictionary) -> bool: return ForeignPlayers.is_fictional_foreign(p)).size()])
	for p: Dictionary in players:
		if joined.has(p["id"]):
			tenures.append([START_YEAR + _years + 1 - int(joined[p["id"]][0]), joined[p["id"]][1], true, joined[p["id"]][0]])

	var hist := float(fp.data["per_team_foreigners"])
	var counts: Array[float] = []
	for tm: String in per_team_last:
		counts.append(float(per_team_last[tm]))
	var mean: float = Growth.mean_sd(counts)[0]
	print("  %d年後の1球団の外国人 平均 %.1f人 最少 %d 最多 %d（史実 %.1f人）" % [_years, mean, counts.min(), counts.max(), hist])
	_check(absf(mean - hist) <= 1.5, "1球団の外国人の人数が史実の±1.5人")
	_check(counts.min() >= 3.0 and counts.max() <= 12.0, "どの球団も外国人が3〜12人")
	# 在籍年数：最初の5年に来た選手（まだ在籍している選手は終わりまでの年数で数える）
	var early := tenures.filter(func(t: Array) -> bool: return int(t[3]) <= START_YEAR + 5)
	var one_year := early.filter(func(t: Array) -> bool: return int(t[0]) == 1).size()
	var share := float(one_year) / maxf(1.0, early.size())
	var hist_one := float(fp.data["tenure_share"]["1"])
	print("  1年で退団 %.0f%%（史実 %.0f%%、%d人）" % [share * 100.0, hist_one * 100.0, early.size()])
	_check(absf(share - hist_one) <= 0.15, "1年で退団する割合が史実の±15%")
	early.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) < float(y[1]))
	var q := early.size() / 4
	var low := 0.0
	var high := 0.0
	for t: Array in early.slice(0, q):
		low += float(t[0])
	for t: Array in early.slice(early.size() - q):
		high += float(t[0])
	low /= maxf(1.0, q)
	high /= maxf(1.0, q)
	var hb: Dictionary = fp.data["tenure_by_ability"]
	print("  在籍年数の平均：1年目の実力の下位4分の1 %.1f年・上位4分の1 %.1f年（史実 %.1f / %.1f）" % [
		low, high, float(hb["bottom_quarter"]), float(hb["top_quarter"])])
	# 史実は上位3.6年・下位1.7年。成長の仕組みが高い能力を平均へ戻すので、ゲームでは上位が2〜3年ほどに縮む（あとで確認に記載）
	_check(high > low + 0.4, "当たりの選手ほど長く在籍する（上位が下位より0.4年以上長い）")


func _foreign_count(players: Array, year: int, debut: Dictionary, league_of: Dictionary) -> Dictionary:
	var count := {}
	for tm: String in league_of:
		count[tm] = 0
	for p: Dictionary in players:
		if RosterRules.is_foreign(p, year, debut.get(p["id"])) and count.has(p["team"]):
			count[p["team"]] += 1
	return count


## 史実の国内の新人（ドラフトで入った選手）を守備位置ごとに
func _domestic_templates() -> Dictionary:
	var out := {"B": [], "P": []}
	for y: int in DOMESTIC_YEARS:
		var prev := {}
		for p: Dictionary in _load_json("generated/ratings/%d_post.json" % (y - 1))["players"]:
			prev[p["id"]] = true
		for p: Dictionary in _load_json("generated/ratings/%d_pre.json" % y)["players"]:
			var side := Growth._side(p)
			if prev.has(p["id"]) or side.is_empty() or Growth.age_at(p, y) < 0 or String(p.get("draft", "")).is_empty():
				continue
			var t := {"year": y, "player": p}
			out[side].append(t)
			var slot := _slot(p)
			if not out.has(slot):
				out[slot] = []
			out[slot].append(t)
	return out


static func _slot(p: Dictionary) -> String:
	if Growth._side(p) == "P":
		return "P"
	return "B:" + str(p.get("primary_pos", ""))


func _load_json(relative: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(_root.path_join(relative)))


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
