extends SceneTree
## 所属の管理と年越しの史実の出来事の確認（ヘッドレス）。2008年から END_YEAR年の開幕まで、シーズンを最後まで回して
## オフのフェーズを1つずつ進め、次を調べる：
## - メジャー移籍（data/mlb_moves.json）：史実の年のオフに退団し、戻る年の開幕には史実の球団にいる
##   （ダルビッシュは2011年オフに退団して戻らない、黒田は2015年まで戻らない）
## - 引退：来季の能力値ファイルにいない選手は引退し、どの球団にもいない
## - トレード（data/trades.json）：CPU球団どうしで全員が移籍元にいれば起きる。自球団が関わるものは起きない
## - 新人は史実の球団に入り、ドラフト順位どおりの年俸になる
## - 新外国人は外国人市場に出て、CPU球団が獲得する（史実どおりの球団とは限らない）
## - 開幕時の編成（Season）は GameState の所属どおり。全員の能力値が引ける
## - 年俸の分布（平均・中央値・1億円以上の人数・球団ごとの総額）を表示する
##
##   godot --headless --path godot --script res://tests/roster_year_check.gd -- [自球団] [最後の年]

const DARVISH := "61965110"
const KURODA := "21523884"
const KIYOHARA := "41343862"  # 清原和博（2008年で引退）

var _team := "読売ジャイアンツ"
var _end_year := 2012
var _failures := 0
var _gs: Node
var _gd: Node
var _moves: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	if args.size() > 1:
		_end_year = int(args[1])
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_moves = _gd.read_data("mlb_moves.json")
	_gs.new_game(_team)
	var league: Variant = _gs.league
	_check_opening(2008)
	_print_salaries(2008)
	_check_rookie_salaries(2008)
	# 2008年の開幕後に史実でトレードされた選手は移籍前の球団から始まる（小池正晃：横浜→中日 2008-06-17）
	_check(league.team_of.get("21523888", "") == "横浜ベイスターズ", "小池正晃は開幕時は横浜")

	while _gs.year < _end_year or _gs.phase != _gs.Phase.SEASON:
		var y: int = _gs.year
		var mid_day: int = Season.day_number("%d-06-30" % y)
		_gs.advance_through(mid_day)
		if y == 2008:
			_check(league.team_of.get("21523888", "") == "中日ドラゴンズ", "小池正晃は6/17のトレードで中日へ")
			var sim: SimTeam = _gs.season.teams["中日ドラゴンズ"]
			_check(sim.by_id.has("21523888") and not _gs.season.teams["横浜ベイスターズ"].by_id.has("21523888"),
					"シーズン中のトレードで編成（SimTeam）も入れ替わる")
		_gs.advance_through(_gs.season_last_day())
		_check(_gs.phase == _gs.Phase.AWARDS, "%d年 シーズン終了" % y)
		var before: Dictionary = league.team_of.duplicate()
		while _gs.phase != _gs.Phase.CAMP:
			_gs.advance()
			if _gs.phase == _gs.Phase.FA_TRADE:
				_check_mlb_departures(y, before)
		_gs.advance()  # 開幕へ
		_check(_gs.phase == _gs.Phase.SEASON and _gs.year == y + 1, "%d年の開幕へ" % (y + 1))
		_report_offseason(y)
		_check_opening(y + 1)
		_print_salaries(y + 1)
		if y + 1 >= _end_year:
			break

	_check(league.in_mlb.has(DARVISH) and not league.team_of.has(DARVISH) or _end_year < 2012,
			"ダルビッシュは2011年オフにメジャーへ（戻らない）")
	_check(not league.team_of.has(KURODA), "黒田は%d年までに戻らない（戻るのは2015年）" % _end_year)
	_check(league.retired.has(KIYOHARA), "清原は2008年で引退")
	print("\n== 結果: %s ==" % ("OK" if _failures == 0 else "%d件の失敗" % _failures))
	quit(1 if _failures > 0 else 0)


## 開幕時：Season の編成が所属どおり、所属選手の能力値が引ける、メジャーから戻る選手は史実の球団にいる
func _check_opening(y: int) -> void:
	var league: Variant = _gs.league
	var season: Season = _gs.season
	_check(season != null, "%d年の日程がある" % y)
	var missing := 0
	var mismatch := 0
	for id: String in league.team_of:
		if _gd.player(id).is_empty():
			missing += 1
		var sim: SimTeam = season.teams.get(league.team_of[id])
		if sim == null or not sim.by_id.has(id):
			mismatch += 1
	_check(missing == 0, "%d年開幕：所属選手の能力値が全員ある（無い%d人）" % [y, missing])
	_check(mismatch == 0, "%d年開幕：編成が所属どおり（違う%d人）" % [y, mismatch])
	var counts := {}
	for id: String in league.team_of:
		counts[league.team_of[id]] = counts.get(league.team_of[id], 0) + 1
	var parts: Array[String] = []
	for t: String in _gd.teams():
		parts.append("%s%d" % [_gd.short_name(t), counts.get(t, 0)])
	print("%d年開幕 所属 %d人：%s" % [y, league.team_of.size(), " ".join(parts)])
	_check(counts.size() == 12, "%d年開幕：12球団" % y)
	for m: Dictionary in _moves:
		if m.get("returned") != null and int(m["returned"]) == y:
			var want: String = _gd.resolve_team(m["npb_team_after"], y)
			_check(league.team_of.get(m["player_id"], "") == want,
					"%d年開幕：%sがメジャーから%sに復帰（今=%s）" % [y, m["name"], _gd.short_name(want),
						league.team_of.get(m["player_id"], "なし")])
		elif m.get("mlb_first") != null and int(m["left_after"]) < y and \
				(m.get("returned") == null or int(m["returned"]) > y) and \
				_gd.player(m["player_id"]).get("hist_team", "").is_empty():
			# 史実でその年にNPBにいない（能力値ファイルにいない）選手はどこにも所属しない
			# （岡島は2012年だけソフトバンクにいたので対象外）
			_check(not league.team_of.has(m["player_id"]), "%d年開幕：%sはメジャーにいる" % [y, m["name"]])


func _check_mlb_departures(y: int, before: Dictionary) -> void:
	var league: Variant = _gs.league
	for m: Dictionary in _moves:
		if int(m["left_after"]) != y or not before.has(m["player_id"]):
			continue
		_check(not league.team_of.has(m["player_id"]) and league.in_mlb.has(m["player_id"]),
				"%d年オフ：%sがメジャーへ（%s）" % [y, m["name"], m["route"]])


func _report_offseason(y: int) -> void:
	var league: Variant = _gs.league
	var by_kind := {}
	for e: Dictionary in league.log:
		if e["year"] == y or (e["year"] == y + 1 and e["kind"] in ["trade", "trade_skipped", "rename"]):
			by_kind[e["kind"]] = by_kind.get(e["kind"], 0) + 1
	print("\n--- %d年オフ〜%d年開幕：%s" % [y, y + 1, by_kind])
	for e: Dictionary in league.log:
		if e["year"] == y and e["kind"] in ["mlb_leave", "mlb_return"]:
			print("  ", e["text"])
		if e["year"] == y and e["kind"] == "trade" and e["date"] >= "%d-10-01" % y:
			print("  ", e["date"], " ", e["text"])
		if e["year"] == y and e["kind"] == "trade_skipped" and e["date"] >= "%d-10-01" % y:
			print("  ", e["date"], " ", e["text"])
	# 引退した選手は次の年のファイルにいない・どこにも所属していない
	var retired_now := 0
	for id: String in league.retired:
		if league.retired[id] == y:
			retired_now += 1
			_check(not league.team_of.has(id), "引退した選手は所属していない: " + league.names.get(id, id))
	print("  引退・退団 %d人（例：%s）" % [retired_now, ", ".join(_sample_names(league.events(y, "retire"), 6))])
	# 実行したトレード：移籍先にいる（その後に別の移籍が無ければ）
	var rookies: Array[Dictionary] = league.events(y, "rookie")
	print("  新人 %d人（例：%s）" % [rookies.size(), ", ".join(_sample_names(rookies, 5))])
	var mine := 0
	for e in rookies:
		if e["to"] == _gs.team:
			mine += 1
	_check(rookies.size() > 50, "%d年ドラフトの新人が入団（%d人、自球団%d人）" % [y, rookies.size(), mine])
	for e in rookies:
		var p: Dictionary = _gd.player(e["id"])
		# 新人の入団先はドラフト会議（Draft）の指名結果で決まる（史実の球団とは限らない）
		_check(p.is_empty() or (league.drafted.has(e["id"]) and league.drafted[e["id"]]["team"] == e["to"]),
				"新人はドラフトで指名した球団へ: %s（%s → %s）" % [e["name"], str(league.drafted.get(e["id"], "指名なし")),
					e["to"]])
	var candidates: Array[Dictionary] = league.events(y, "foreign_candidate")
	var signed := 0
	var same := 0
	var mine_foreign := 0
	for e in candidates:
		var t: String = league.team_of.get(e["id"], "")
		if t.is_empty():
			continue
		signed += 1
		if _gd.player(e["id"]).get("hist_team", "") == t:
			same += 1
		if t == _gs.team:
			mine_foreign += 1
	var unsigned: Array[Dictionary] = league.events(y + 1, "foreign_unsigned")
	print("  外国人市場 候補%d人 → 獲得%d人（史実と同じ球団%d人、自球団%d人）・未契約%d人" % [
		candidates.size(), signed, same, mine_foreign, unsigned.size()])
	_check(candidates.size() > 10, "%d年オフ：新外国人が市場に出る" % y)
	_check(signed + unsigned.size() == candidates.size(), "市場の候補は獲得か未契約のどちらか")
	var trades := 0
	for e in league.log:
		var in_offseason: bool = e["year"] == y and e["date"] >= "%d-10-01" % y or e["year"] == y + 1
		if e["kind"] == "trade" and in_offseason:
			trades += 1
			if e["from"] == _gs.team or e["to"] == _gs.team:
				_failures += 1
				print("NG 自球団が関わるトレードが起きた: ", e["text"])
	_check(trades > 0, "%d年オフ：史実のトレードが起きる（%d件）" % [y, trades])


func _check_rookie_salaries(y: int) -> void:
	var league: Variant = _gs.league
	# 2008年の新人（2007年ドラフト）：中田翔（高校1位）、由規（高校1位）、長野は入団せず
	for pair: Array in [["中田 翔", 1200], ["由規", 1200]]:
		for id: String in league.team_of:
			if league.names[id] == pair[0]:
				_check(league.salary_of(id) == pair[1], "%d年 新人 %s の年俸 %s" % [y, pair[0],
						Salary.text(league.salary_of(id))])


func _print_salaries(y: int) -> void:
	var league: Variant = _gs.league
	var amounts: Array[int] = []
	for id: String in league.team_of:
		amounts.append(league.salary_of(id))
	amounts.sort()
	var total := 0
	for a in amounts:
		total += a
	var over := func(th: int) -> int:
		return amounts.filter(func(a: int) -> bool: return a >= th).size()
	print("%d年 年俸：平均 %s・中央値 %s・最高 %s・1億円以上 %d人・3億円以上 %d人・1千万円未満 %d人" % [
		y, Salary.text(total / amounts.size()), Salary.text(amounts[amounts.size() / 2]),
		Salary.text(amounts[-1]), over.call(10000), over.call(30000),
		amounts.size() - over.call(1000)])
	var rows: Array = []
	for t: String in _gd.teams():
		rows.append([t, league.payroll(t)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var parts: Array[String] = []
	for r: Array in rows:
		parts.append("%s %s" % [_gd.short_name(r[0]), Salary.text(r[1])])
	print("  球団の総額：", "／".join(parts))
	var ids: Array = league.team_of.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return league.salary_of(a) > league.salary_of(b))
	var top: Array[String] = []
	for id: String in ids.slice(0, 12):
		top.append("%s(%s)%s" % [league.names[id], _gd.short_name(league.team_of[id]),
			Salary.text(league.salary_of(id))])
	print("  上位：", "、".join(top))
	_check(amounts[0] >= Salary.ROOKIE_IKUSEI[1], "%d年：最低年俸（育成）以上" % y)
	# レギュラー（能力値の直近3年で年平均400打席・120回以上）の年俸
	var regular: Array[int] = []
	for id: String in league.team_of:
		var a := Salary.ability(_gd.player(id))
		if a[1] >= 0.85:
			regular.append(league.salary_of(id))
	regular.sort()
	if not regular.is_empty():
		print("  出場の多い選手 %d人：中央値 %s・下位1/4 %s・上位1/4 %s" % [regular.size(),
			Salary.text(regular[regular.size() / 2]), Salary.text(regular[regular.size() / 4]),
			Salary.text(regular[regular.size() * 3 / 4])])


static func _sample_names(events: Array[Dictionary], n: int) -> Array[String]:
	var result: Array[String] = []
	for e in events.slice(0, n):
		result.append(e["name"])
	return result


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("NG ", label)
