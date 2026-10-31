class_name FutureYear
extends RefCounted
## 史実の能力値ファイルが無い年（Growth.FIRST_YEAR〜）の「来季の開幕時点の能力値」を作る（docs/AUTORUN.md 作業27・31）。
##
## オフの「FA・トレード・ポスティング」に入るとき（GameState._enter）に1回だけ作り、GameData.synthetic に置く。
## 以後は来季の能力値ファイルと同じに扱われるので、LeagueRoster の来季の準備（引退＝来季にいない選手・新人・外国人市場）が
## そのまま動く：
## - 今の所属の選手：`Growth.should_retire` で引退（来季の能力値に入れない）。残った選手は `Growth.grow_league` で来季の能力へ
##   （今季のゲーム内の打席・アウト数で出場量を更新し、引退の判定にも使う）。複数年契約の途中の選手は引退しない
## - 来季のファイルがあれば（tools/amateur_ratings.py carry の 2028_pre など）、その球団なし（team が空）の選手＝ドラフト候補を加える
## - 架空の外国人選手（ForeignPlayers）をその年の人数だけ加える（球団なし。LeagueRoster が外国人市場に出す）
## - GameState.future_newcomers が返す選手（作業22の候補・テストの補充）を加える
## 加えた選手は成長させず（fresh）、リーグ全体の平均を寄せる計算にだけ入れる。守備の記録が無い野手には守備位置を付ける

var growth: Growth
var foreign: ForeignPlayers


func _init(growth_model: Growth = null, foreign_model: ForeignPlayers = null) -> void:
	growth = growth_model if growth_model != null else Growth.new()
	foreign = foreign_model if foreign_model != null else ForeignPlayers.new({}, growth)


## season_year のオフに、来季（season_year + 1）の開幕時点の能力値（能力値ファイルと同じ形）を作る。
## base：来季のファイル（無ければ空）。season：今季の Season（無ければ null）。
## extra：ほかに加える選手（GameState.future_newcomers。hist_team のある選手はその球団の新加入、空ならドラフト候補）
func build(season_year: int, league: LeagueRoster, season: Season, base: Dictionary,
		rng: RandomNumberGenerator, extra: Array = []) -> Dictionary:
	var next_year := season_year + 1
	var debut := GameData.load_debut_years(season_year)
	var keep: Array = []
	var seasons := {}
	var fresh := {}
	var retired := 0
	for id: String in league.team_of:
		var p := GameData.player(id)
		if p.is_empty():
			continue
		var stats := season_stats(season, id, p)
		if not Growth._side(p).is_empty() and _can_retire(league, id, season_year):
			var foreign_flag := RosterRules.is_foreign(p, season_year, debut.get(id))
			if growth.should_retire(p, next_year, foreign_flag, rng, playing_after(p, stats)):
				retired += 1
				continue
		keep.append(p)
		seasons[id] = stats
	for p: Dictionary in base.get("players", []):
		var id: String = p["id"]
		if str(p.get("hist_team", p.get("team", ""))).is_empty() and not league.team_of.has(id) \
				and not league.retired.has(id) and not fresh.has(id):
			keep.append(p)
			fresh[id] = true
	var newcomer_team := {}
	for p: Dictionary in extra:
		var id: String = p["id"]
		if league.team_of.has(id) or fresh.has(id):
			continue
		keep.append(p)
		fresh[id] = true
		newcomer_team[id] = str(p.get("hist_team", p.get("team", "")))
	var imports := foreign.generate_year(next_year, rng)
	for p: Dictionary in imports:
		keep.append(p)
		fresh[p["id"]] = true
	var players := growth.grow_league(keep, next_year, rng, fresh, seasons)
	for q: Dictionary in players:
		# 入ったばかりの野手に守備の記録が無ければ、1年目から守備位置を付ける（ゲームは2軍の試合をしないため）
		if fresh.has(q["id"]):
			growth.assign_fielding_if_missing(q, rng)
		var team: String = league.team_of.get(q["id"], newcomer_team.get(q["id"], ""))
		q["team"] = team
		q["hist_team"] = team
		if team.is_empty() and ForeignPlayers.is_fictional_foreign(q):
			q["league"] = null
	return {
		"schema_version": base.get("schema_version", 4), "year": next_year, "phase": "pre", "synthetic": true,
		"players": players, "mlb_players": [],
		"foreign_target": float(foreign.data.get("per_team_foreigners", 7.0)),
		"foreign_pitcher_share": foreign.pitcher_share(),
		"growth_note": {"retired": retired, "imports": imports.size(), "candidates": fresh.size() - imports.size()},
	}


## 今季のゲーム内の1軍の成績（Growth.grow の season の形）。投手は投球のアウト数、野手は打席
static func season_stats(season: Season, id: String, p: Dictionary) -> Dictionary:
	if season == null:
		return {}
	if Growth._side(p) == "P":
		return {"outs_1": float(season.pitching.get(id, {}).get("outs", 0)), "outs_2": 0.0}
	return {"pa_1": float(season.batting.get(id, {}).get("pa", 0)), "pa_2": 0.0}


## 今季の成績で出場量を更新したときの出場量（Salary.ability の 0〜1。成績が無ければ −1＝今の値のまま）
static func playing_after(p: Dictionary, stats: Dictionary) -> float:
	if stats.is_empty() or Growth._side(p).is_empty():
		return -1.0
	var q: Dictionary = p.duplicate(true)
	Growth._update_sample(q, Growth._side(q), stats)
	return float(Salary.ability(q)[1])


## 引退の判定をするか（複数年契約の途中・メジャーから引き留めた選手はしない）
static func _can_retire(league: LeagueRoster, id: String, season_year: int) -> bool:
	if int(league.contract_until.get(id, 0)) > season_year:
		return false
	return not league.kept_mlb.has(id)
