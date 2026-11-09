extends SceneTree
## 史実の無い年の年越し（成長・衰え・引退・架空の外国人。docs/AUTORUN.md 作業27・31）の確認（ヘッドレスで数分）。
## 2027年開始で、シーズン → オフ → 春季キャンプを YEARS 年くり返し、次を調べる：
## - オフ（FA・トレード・ポスティング）で来季の能力値が作られ（GameData.synthetic）、春季キャンプでそれに切り替わる
## - 残った選手の能力が年ごとに変わる。引退・退団が毎年ある（割合が史実の範囲）。年齢の高い選手ほど引退する
## - 所属の野手全員に守備位置がある（新人にも入ったときに付く）。アマ出身の選手の能力が1年で大きく下がらない
## - 架空の外国人が外国人市場に出て、CPU球団が獲り、1球団の外国人の人数が史実の頃と同じくらい
## - 日程は前の年の写しで毎年143試合。日付を進めると日付・成績が追従する
## - 試合の成績（打率・防御率）とリーグ全体の能力の平均が年をまたいでほぼ一定
## - セーブ／ロード（オフの途中）で作った能力値がそのまま戻る
## ドラフトの候補（作業22）がまだ無いので、毎年 GameState.future_newcomers で史実の新人をひな形にした補充の新人を各球団に入れる。
##
##   godot --headless --path godot --script res://tests/future_year_check.gd -- [年数]
## （このスクリプトはオートロードより先にコンパイルされるので、GameData を使うクラス（LeagueRoster など）は型に使わない）

const USER := "北海道日本ハムファイターズ"
const START := 2027
const ROOKIES_PER_TEAM := 9  ## 史実の国内の新人（育成を含む）は年100人ほど
const DOMESTIC_YEARS := [2020, 2021, 2022, 2023, 2024, 2025, 2026]

var _failures := 0
var _years := 6
var _gs: Node
var _gd: Node
var _root := ""
var _templates := {"P": [], "B": []}
var _serial := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_load_templates()
	_gs.new_game(USER, START)
	_gs.future_newcomers = _newcomers
	var target := float(ForeignPlayers.new().data["per_team_foreigners"])
	var rows: Array = []
	var prev_values := _values()
	var new_pitch_total := 0
	var new_pitch_news := ""
	for i in _years:
		var y: int = _gs.year
		_check(_gs.season != null and _all_143(_gs.season), "%d年：日程があり12球団すべて143試合" % y)
		if i == 1:
			_check_follow(y)
		print("  … %d年のシーズンを進める（%d秒）" % [y, Time.get_ticks_msec() / 1000])
		var births := {}
		for p: Dictionary in _gd.rostered_players():
			births[p["id"]] = p
		_gs.skip_to_phase(_gs.Phase.FA_TRADE)
		print("  … %d年オフ FA（%d秒）" % [y, Time.get_ticks_msec() / 1000])
		var totals: Dictionary = _gs.season.league_totals() if _gs.season != null else {}
		var syn: Dictionary = _gd.synthetic.get(y + 1, {})
		_check(not syn.is_empty(), "%d年オフ：来季（%d年）の能力値が作られた（%s）" % [y, y + 1, syn.get("growth_note", {})])
		if i == 1:
			_check_save_load(y)
		_gs.skip_to_phase(_gs.Phase.CAMP)
		print("  … %d年 春季キャンプ（%d秒）" % [y + 1, Time.get_ticks_msec() / 1000])
		_check(_gs.year == y + 1 and bool(_gd.ratings.get("synthetic", false)), "%d年の春季キャンプ：作った能力値に切り替わった" % (y + 1))
		# 作業79：新しい球種を覚えた投手（毎年数十人）と、キャンプのニュース
		var learned: Array = _gd.ratings.get("new_pitches", [])
		new_pitch_total += learned.size()
		if _gs.news != null:
			for art: Dictionary in _gs.news.articles:
				if str(art.get("headline", "")).contains("新球"):
					new_pitch_news = art["headline"]
		var values := _values()
		var changed := 0
		var both := 0
		for id: String in values:
			if prev_values.has(id):
				both += 1
				if values[id] != prev_values[id]:
					changed += 1
		var retire_ages: Array[float] = []
		var retired: Array = _gs.league.events(y, "retire")
		for e: Dictionary in retired:
			var p: Dictionary = births.get(e["id"], {})
			if not p.is_empty() and Growth.age_at(p, y) > 0:
				retire_ages.append(Growth.age_at(p, y))
		var roster: Array = _gd.rostered_players()
		var signed: int = _gs.league.events(y + 1, "foreign_sign").size() + _gs.league.events(y, "foreign_sign").size()
		var row := {"year": y, "avg": float(totals.get("h", 0)) / maxf(1.0, totals.get("ab", 1)),
			"era": float(totals.get("er", 0)) * 27.0 / maxf(1.0, totals.get("outs", 1)),
			"retired": retired.size(), "rate": float(retired.size()) / maxf(1.0, roster.size() + retired.size()),
			"retire_age": Growth.mean_sd(retire_ages)[0] if not retire_ages.is_empty() else 0.0,
			"foreign": _foreign_per_team(), "changed": float(changed) / maxf(1.0, both), "roster": roster.size(),
			"means": _means(roster), "signed": signed}
		rows.append(row)
		print("  %d年：打率 %.3f 防御率 %.2f／オフ：引退 %d人（%.0f%%、平均%.1f歳）・外国人 %.1f人/球団・能力が変わった選手 %.0f%%・所属 %d人・平均 %s" % [
			y, row["avg"], row["era"], row["retired"], row["rate"] * 100.0, row["retire_age"], row["foreign"],
			row["changed"] * 100.0, row["roster"], row["means"]])
		if y + 1 >= Growth.FIRST_YEAR:
			_check(row["changed"] > 0.6, "%d年：残った選手の6割以上の能力が変わった（%.0f%%）" % [y + 1, row["changed"] * 100.0])
			var no_field := 0
			var batters := 0
			var am_delta: Array[float] = []
			for p: Dictionary in roster:
				if Growth._side(p) != "B":
					continue
				batters += 1
				if Growth._no_fielding(p):
					no_field += 1
				if p.get("amateur") is Dictionary and prev_values.has(p["id"]):
					am_delta.append(float(Growth._value(p, "B", "meet")) - float(prev_values[p["id"]][0]))
			_check(no_field == 0, "%d年：所属の野手全員（%d人）に守備位置がある（無い %d人）" % [y + 1, batters, no_field])
			if not am_delta.is_empty():
				var m: float = Growth.mean_sd(am_delta)[0]
				_check(m > -3.0, "%d年：アマ出身の野手のミートの1年の変化が大きく下がらない（平均 %+.1f、%d人）" % [y + 1, m, am_delta.size()])
		_check(row["rate"] > 0.05 and row["rate"] < 0.25, "%d年オフ：引退・退団の割合が5〜25%%（%.0f%%）" % [y, row["rate"] * 100.0])
		prev_values = values
		_gs.advance()
		_check(_gs.phase == _gs.Phase.SEASON and _gs.date_text().begins_with("%d年" % (y + 1)), "%d年の開幕（%s）" % [y + 1, _gs.date_text()])
	_check(new_pitch_total >= _years * 10 and new_pitch_total <= _years * 80 and not new_pitch_news.is_empty(),
		"新しい球種を覚えた投手が毎年いて、キャンプのニュースになる（%d年で %d人。例「%s」）" % [_years, new_pitch_total, new_pitch_news])
	# 年をまたいでほぼ一定
	var first: Dictionary = rows[0]
	var last: Dictionary = rows[-1]
	_check(absf(float(last["avg"]) - float(first["avg"])) <= 0.015, "打率が最初の年の±.015（%.3f → %.3f）" % [first["avg"], last["avg"]])
	_check(absf(float(last["era"]) - float(first["era"])) <= 0.5, "防御率が最初の年の±0.5（%.2f → %.2f）" % [first["era"], last["era"]])
	_check(absf(float(last["foreign"]) - target) <= 2.0, "1球団の外国人が史実（%.1f人）の±2人（%.1f人）" % [target, last["foreign"]])
	for key: String in ["meet", "power", "overall"]:
		var a: float = first["means"][key]
		var b: float = last["means"][key]
		_check(absf(b - a) <= 3.0, "所属選手の平均 %s が最初の年の±3（%.1f → %.1f）" % [key, a, b])
	var ages: Array[float] = []
	for r: Dictionary in rows:
		ages.append(float(r["retire_age"]))
	# 史実の国内の引退は29歳前後。補充の新人（テスト用）の若い退団も入るので幅を広めに
	_check(Growth.mean_sd(ages)[0] >= 26.0 and Growth.mean_sd(ages)[0] <= 35.0, "引退の平均年齢が26〜35歳（%.1f歳）" % Growth.mean_sd(ages)[0])
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


## 日付を進めると日付・成績が追従する（1か月進める）
func _check_follow(y: int) -> void:
	var before: String = _gs.date_text()
	var played: int = _gs.games_played()
	_gs.advance()
	var after: String = _gs.date_text()
	_check(after != before and after.begins_with("%d年" % y) and _gs.games_played() > played,
		"%d年：1か月進めると日付と試合数が進む（%s → %s、%d → %d試合）" % [y, before, after, played, _gs.games_played()])


func _check_save_load(y: int) -> void:
	var data: Variant = SaveUtil.ints(JSON.parse_string(JSON.stringify(_gs.to_save(), "", false, true)))
	var before := _values()
	var syn_before: int = (_gd.synthetic[y + 1]["players"] as Array).size()
	_gs.load_state(data)
	var after := _values()
	_check(_gd.synthetic.has(y + 1) and (_gd.synthetic[y + 1]["players"] as Array).size() == syn_before,
		"%d年オフ：セーブ／ロードで来季の能力値（%d人）が戻る" % [y, syn_before])
	var same := before.size() == after.size()
	for id: String in before:
		same = same and after.get(id) == before[id]
	_check(same, "%d年オフ：セーブ／ロードで今の能力値が同じ" % y)


## 所属選手の 選手ID → [ミート, パワー, 総合, 球速]
func _values() -> Dictionary:
	var out := {}
	for p: Dictionary in _gd.rostered_players():
		var side := Growth._side(p)
		if side == "B":
			out[p["id"]] = [Growth._value(p, "B", "meet"), Growth._value(p, "B", "power")]
		elif side == "P":
			out[p["id"]] = [Growth._value(p, "P", "overall"), Growth._value(p, "P", "velocity")]
	return out


func _means(roster: Array) -> Dictionary:
	var vals := {"meet": [], "power": [], "overall": []}
	for p: Dictionary in roster:
		var side := Growth._side(p)
		for key: String in (["meet", "power"] if side == "B" else (["overall"] if side == "P" else [])):
			var v: Variant = Growth._value(p, side, key)
			if v != null:
				vals[key].append(float(v))
	var out := {}
	for key: String in vals:
		out[key] = snappedf(Growth.mean_sd(vals[key])[0], 0.1)
	return out


func _foreign_per_team() -> float:
	var debut: Dictionary = _gd.load_debut_years(_gs.year)
	var n := 0
	for p: Dictionary in _gd.rostered_players():
		if RosterRules.is_foreign(p, _gs.year, debut.get(p["id"])):
			n += 1
	return float(n) / maxf(1.0, _gd.teams().size())


func _all_143(season: Season) -> bool:
	var count := {}
	for g: Dictionary in season.games:
		for t: String in [g["home"], g["away"]]:
			count[t] = int(count.get(t, 0)) + 1
	if count.size() != 12:
		return false
	for t: String in count:
		if count[t] != 143:
			return false
	return true


## 補充の新人（作業22の候補の代わり）：各球団に ROOKIES_PER_TEAM 人、史実の新人（ドラフトで入った選手）をひな形に
func _newcomers(next_year: int, _league: Object) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = next_year
	var out: Array = []
	for team: String in _gd.teams():
		for i in ROOKIES_PER_TEAM:
			var side := "P" if i % 2 == 0 else "B"
			var t: Dictionary = _templates[side][rng.randi_range(0, _templates[side].size() - 1)]
			var p: Dictionary = t["player"].duplicate(true)
			_serial += 1
			p["id"] = "test:%d:%d" % [next_year, _serial]
			p["name"] = "補充 新人%d" % _serial
			var birth: String = p["birth"]
			p["birth"] = "%d%s" % [int(birth.substr(0, 4)) + next_year - int(t["year"]), birth.substr(4)]
			p["team"] = team
			p["hist_team"] = team
			out.append(p)
	return out


func _load_templates() -> void:
	for y: int in DOMESTIC_YEARS:
		var prev := {}
		for p: Dictionary in _load_json("generated/ratings/%d_post.json" % (y - 1))["players"]:
			prev[p["id"]] = true
		for p: Dictionary in _load_json("generated/ratings/%d_pre.json" % y)["players"]:
			var side := Growth._side(p)
			if prev.has(p["id"]) or side.is_empty() or Growth.age_at(p, y) < 0 or str(p.get("draft", "")).is_empty():
				continue
			_templates[side].append({"year": y, "player": p})


func _load_json(relative: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(_root.path_join(relative)))


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
