class_name Season
extends RefCounted
## 1年分のペナント。史実の日程（data/<年>/schedule.json）の status=played の試合を
## 日付順にシミュレーションし、全試合のスコア・勝敗投手・個人成績・順位を保持する。
##
## 日程の球団名は npb.jp の略称（読売, 東京ヤクルト, …）なので、能力値の正式名に対応づける。
## status=canceled の試合はシミュレーションせず、日程表で「中止」と表示する。

const DAY_SECONDS := 86400
const WEEKDAY_NAMES := ["日", "月", "火", "水", "木", "金", "土"]

var year: int
## 日付順。{date, day, kind, home, away, venue, status, game_no, result}
var games: Array[Dictionary] = []
var teams := {}                     ## 正式名 → SimTeam
var leagues := {}                   ## 正式名 → "C" / "P"
var players := {}                   ## 選手ID → {name, team}
var records := {}                   ## 正式名 → {w, l, d, rs, ra}
var batting := {}                   ## 選手ID → 打撃成績（通算）
var pitching := {}                  ## 選手ID → 投手成績（通算）
var next_index := 0                 ## 次にシミュレーションする games の添字
var unknown_teams: Array[String] = []

var _rng := RandomNumberGenerator.new()
var _games_by_date := {}
var _debut_years := {}


## ratings: {"players": 所属している選手}（GameData.rostered_players()。team が空の選手は除く）、schedule: schedule.json の中身、
## debut_years: 選手ID → 1軍初出場の年（外国人枠の判定用。GameData.load_debut_years()）
func _init(season_year: int, ratings: Dictionary, schedule: Array, seed_value: int = 0,
		debut_years: Dictionary = {}) -> void:
	year = season_year
	_rng.seed = seed_value if seed_value != 0 else hash("season-%d" % year)
	_debut_years = debut_years
	var by_team := {}
	for p: Dictionary in ratings.get("players", []):
		var team: String = p["team"]
		if team.is_empty():
			continue
		if not by_team.has(team):
			by_team[team] = []
		by_team[team].append(p)
		players[p["id"]] = {"name": p["name"], "team": team}
	for team: String in by_team:
		leagues[team] = by_team[team][0]["league"]
		teams[team] = SimTeam.new(team, leagues[team], by_team[team], year, debut_years)
		records[team] = {"w": 0, "l": 0, "d": 0, "rs": 0, "ra": 0}

	for g: Dictionary in schedule:
		var home := resolve_team(g["home"])
		var away := resolve_team(g["away"])
		if home.is_empty() or away.is_empty():
			continue
		var entry := {
			"date": g["date"], "day": day_number(g["date"]), "kind": g.get("kind", ""),
			"home": home, "away": away, "venue": g.get("venue", ""),
			"status": g.get("status", "played"), "game_no": g.get("game_no", 0),
			"result": {},
		}
		games.append(entry)
	# 日付順（同じ日は元の並びのまま）
	for i in games.size():
		games[i]["order"] = i
	games.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["day"] < b["day"] if a["day"] != b["day"] else a["order"] < b["order"])
	for g in games:
		if not _games_by_date.has(g["date"]):
			_games_by_date[g["date"]] = []
		_games_by_date[g["date"]].append(g)
	_skip_canceled()
	for team: String in teams:
		teams[team].opening_day = first_day()


## 日程の略称（"読売" "横浜" など）→ 能力値の正式名。前方一致で、その年の球団から選ぶ
func resolve_team(short: String) -> String:
	if teams.has(short):
		return short
	var best := ""
	for team: String in teams:
		if team.begins_with(short) and (best.is_empty() or team.length() < best.length()):
			best = team
	if best.is_empty() and short not in unknown_teams:
		unknown_teams.append(short)
		push_warning("日程の球団名を能力値の球団に対応づけられません: " + short)
	return best


static func day_number(date: String) -> int:
	return Time.get_unix_time_from_datetime_string(date + "T12:00:00") / DAY_SECONDS


static func date_of_day(day: int) -> String:
	return Time.get_date_string_from_unix_time(day * DAY_SECONDS + DAY_SECONDS / 2)


static func month_of(day: int) -> int:
	return int(date_of_day(day).substr(5, 2))


## 例: "4月30日（水）"
static func day_label(day: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(day * DAY_SECONDS + DAY_SECONDS / 2)
	return "%d月%d日（%s）" % [dt["month"], dt["day"], WEEKDAY_NAMES[dt["weekday"]]]


func is_finished() -> bool:
	return next_index >= games.size()


## 開幕日・最終日（通し日数）
func first_day() -> int:
	return games[0]["day"] if not games.is_empty() else 0


func last_day() -> int:
	return games[-1]["day"] if not games.is_empty() else 0


## 次に試合をする日（全日程が終わっていれば最終日の翌日）
func current_day() -> int:
	if is_finished():
		return last_day() + 1
	return games[next_index]["day"]


## 試合のある月（例: [3, 4, ..., 10]）
func months() -> Array[int]:
	var result: Array[int] = []
	for g in games:
		var m := int(g["date"].substr(5, 2))
		if m not in result:
			result.append(m)
	return result


## 指定した日（通し日数）の前日までの全試合をシミュレーションする。消化した試合数を返す
func sim_until_day(day_exclusive: int) -> int:
	var count := 0
	while not is_finished() and games[next_index]["day"] < day_exclusive:
		_play(games[next_index])
		next_index += 1
		_skip_canceled()
		count += 1
	return count


## その月の残り試合をすべて行う
func sim_month(month: int) -> int:
	var next_month_year := year + (1 if month == 12 else 0)
	var next_month := 1 if month == 12 else month + 1
	var first_of_next := "%04d-%02d-01" % [next_month_year, next_month]
	return sim_until_day(day_number(first_of_next))


func sim_all() -> int:
	return sim_until_day(last_day() + 1)


func games_on(date: String) -> Array:
	return _games_by_date.get(date, [])


func played_count() -> int:
	var n := 0
	for g in games:
		if not g["result"].is_empty():
			n += 1
	return n


func scheduled_count() -> int:
	var n := 0
	for g in games:
		if g["status"] == "played":
			n += 1
	return n


## 最後に試合を行った日（まだなら空文字）
func last_played_date() -> String:
	for i in range(next_index - 1, -1, -1):
		if not games[i]["result"].is_empty():
			return games[i]["date"]
	return ""


## リーグの順位表。各行は {team, wins, losses, draws, runs, runs_allowed}（並べ替えは GameState）
func record_of(team: String) -> Dictionary:
	return records.get(team, {"w": 0, "l": 0, "d": 0, "rs": 0, "ra": 0})


## シーズン中の移籍（史実のトレード）：選手を to_team へ移し、両球団の1軍を自動で組み直す（CPU球団どうしのみ）。
## p は能力値データ（GameData.player()）。今季の成績はそのまま引き継ぐ
func transfer(p: Dictionary, to_team: String) -> void:
	var id: String = p["id"]
	var from_team: String = players.get(id, {}).get("team", "")
	if teams.has(from_team):
		teams[from_team].remove_player(id)
	if teams.has(to_team):
		teams[to_team].add_player(p, _debut_years)
	players[id] = {"name": p["name"], "team": to_team}


func player_name(id: String) -> String:
	return players.get(id, {}).get("name", "")


func _skip_canceled() -> void:
	while not is_finished() and games[next_index]["status"] != "played":
		next_index += 1


func _play(g: Dictionary) -> void:
	var home: SimTeam = teams[g["home"]]
	var away: SimTeam = teams[g["away"]]
	var use_dh := _uses_dh(g)
	var sim := GameSim.new(away, home, g["day"], use_dh, _rng)
	var result := sim.play()
	g["result"] = result
	var hs: int = result["home_score"]
	var away_score: int = result["away_score"]
	var hr: Dictionary = records[g["home"]]
	var ar: Dictionary = records[g["away"]]
	hr["rs"] += hs
	hr["ra"] += away_score
	ar["rs"] += away_score
	ar["ra"] += hs
	if hs > away_score:
		hr["w"] += 1
		ar["l"] += 1
	elif hs < away_score:
		hr["l"] += 1
		ar["w"] += 1
	else:
		hr["d"] += 1
		ar["d"] += 1
	for side in 2:
		for line: Dictionary in result["batting"][side]:
			_add_line(batting, line, ["pos", "order"])
		for line: Dictionary in result["pitching"][side]:
			_add_line(pitching, line, [])


## パ・リーグ主催の試合（交流戦を含む）は DH 制
func _uses_dh(g: Dictionary) -> bool:
	return leagues.get(g["home"], "C") == "P"


static func _add_line(totals: Dictionary, line: Dictionary, skip: Array) -> void:
	var id: String = line["id"]
	if not totals.has(id):
		totals[id] = {"g": 0}
	var t: Dictionary = totals[id]
	t["g"] += 1
	for key: String in line:
		if key == "id" or key in skip:
			continue
		t[key] = t.get(key, 0) + line[key]


# --- 集計 -----------------------------------------------------------------------------

## リーグ全体（league="" で両リーグ）の打撃・投手の合計。検証（tests/season_check.gd）と記録表示に使う
func league_totals(league: String = "") -> Dictionary:
	var t := {
		"games": 0, "pa": 0, "ab": 0, "h": 0, "d": 0, "t": 0, "hr": 0, "bb": 0, "hbp": 0,
		"so": 0, "sb": 0, "cs": 0, "sh": 0, "sf": 0, "gdp": 0, "r": 0, "roe": 0,
		"outs": 0, "er": 0, "ra": 0,
	}
	for id: String in batting:
		if not _in_league(id, league):
			continue
		var b: Dictionary = batting[id]
		for key: String in t:
			if b.has(key) and key != "g":
				t[key] += b[key]
	for id: String in pitching:
		if not _in_league(id, league):
			continue
		var p: Dictionary = pitching[id]
		t["outs"] += p["outs"]
		t["er"] += p["er"]
		t["ra"] += p["r"]
	for team: String in records:
		if league.is_empty() or leagues[team] == league:
			var rec: Dictionary = records[team]
			t["games"] += rec["w"] + rec["l"] + rec["d"]
	return t


func _in_league(id: String, league: String) -> bool:
	if league.is_empty():
		return true
	var team: String = players.get(id, {}).get("team", "")
	return leagues.get(team, "") == league


## 打率など（試合数・打席数が足りない選手も含む）
static func batting_avg(b: Dictionary) -> float:
	return float(b.get("h", 0)) / b["ab"] if b.get("ab", 0) > 0 else 0.0


static func era(p: Dictionary) -> float:
	return p.get("er", 0) * 27.0 / p["outs"] if p.get("outs", 0) > 0 else 0.0
