# gdlint: disable=max-public-methods,max-file-lines
class_name LeagueRoster
extends RefCounted
## 所属の管理（誰がどの球団にいるか）・年俸・年越しの史実の出来事。docs/SPEC.md「決定事項：所属の管理と史実の出来事」。
##
## FA などで史実と違う移籍が起きるので、所属はゲーム側（GameState.league）で持ち、年が変わっても引き継ぐ。
## 能力値ファイル（generated/ratings）は能力の値を引くためだけに使う（GameData.apply_roster() が所属を上書きする）。
##
## 史実の出来事：
## - トレード（data/trades.json）：日付が来たら実行（シーズン中は毎日、オフはフェーズごと）。CPU球団同士で、
##   その時点で全員がまだ移籍元にいる場合だけ。自球団が関わるトレードは起きない
## - メジャー移籍（data/mlb_moves.json）：史実の年のオフ（FA・トレード・ポスティング）に退団し、戻る年の前のオフに
##   史実の球団へ復帰する（引き留めは FA・ポスティングの画面で作る）
## - 引退：来季の能力値ファイルにいない選手（成績が無く能力を計算できない）は「戦力外・引退」で引退
## - 新人・その他の新加入：「ドラフト」で史実の球団に入る（ドラフト画面ができたら差し替える）
## - 新外国人：「外国人市場」の候補になる。自球団は新戦力の画面で獲得、CPU球団はオフのフェーズごとに自動で獲得
##   （各球団が史実で獲得した人数ぶん。能力の高い順）。開幕までに誰も獲らなかった選手は来日しない
## - 1軍に出ていない選手の仮ID（tmp:…）は、1軍に出た年に本来の選手IDへ付け替える（名前で突合）

## 外国人市場の評価の誤差（z）。候補の評価・提示額は史実の来季の成績（来季のシーズン後の能力値）に
## この大きさの誤差を足した「不完全な未来視」（docs/SPEC.md のドラフトと同じ考え方）。画面の能力は開幕時点のまま
const MARKET_NOISE := 0.5

## 球団名が変わった球団（旧 → 新）。新しい年の能力値ファイルに旧名が無ければ付け替える
const TEAM_SUCCESSOR := {"横浜ベイスターズ": "横浜DeNAベイスターズ"}

var year: int
var user_team := ""
var team_of := {}              ## 選手ID → 球団（正式名）。所属している選手だけ
var salary := {}               ## 選手ID → 年俸（万円）。今の契約（オフの契約更改後は来季の額）
var salary_history := {}       ## 選手ID → [{year, team, salary}]（ゲーム内の契約の推移）
var joined := {}               ## 選手ID → NPB に入った年（在籍年数の起点）
var names := {}                ## 選手ID → 名前（引退・メジャーの選手も。一度でも所属した選手）
var retired := {}              ## 選手ID → 引退した年（その年のシーズン後）
var in_mlb := {}               ## 選手ID → mlb_moves の1件（今メジャーにいる選手）
var market: Array[String] = [] ## 外国人市場の候補（未契約）
var market_info := {}          ## 選手ID → {hist_team, asking, pitcher}
var cpu_demand := {}           ## CPU球団 → {"p": 投手の残り人数, "b": 野手の残り人数}
## 出来事の記録 {year, date, kind, id, name, from, to, text}。kind: trade / trade_skipped / mlb_leave /
## mlb_return / retire / rookie / join / foreign_candidate / foreign_sign / foreign_unsigned /
## rename
var log: Array[Dictionary] = []

var _trades: Array[Dictionary] = []  ## trade_id ごと、日付順 {id, date, moves: [{pid, name, from, to}]}
var _trade_index := 0
var _moves_by_id := {}
var _plan := {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_load_trades()
	var moves: Variant = GameData.read_data("mlb_moves.json")
	if moves is Array:
		for m: Dictionary in moves:
			_moves_by_id[m["player_id"]] = m


# --- 開始 -----------------------------------------------------------------------------

## ゲーム開始時の所属：開幕時点の能力値ファイルの球団。ただしその年の開幕後に史実でトレードされた選手は
## 移籍前の球団から始める（能力値ファイルは1年分の在籍なので、移籍後の球団になっていることがある）
func start(start_year: int, ratings: Dictionary, opening_date: String, user: String,
		seed_value: int = 0) -> void:
	year = start_year
	user_team = user
	_rng.seed = seed_value if seed_value != 0 else hash("league-%d" % start_year)
	var debut := GameData.load_debut_years(start_year)
	for p: Dictionary in ratings.get("players", []):
		var id: String = p["id"]
		team_of[id] = p.get("hist_team", p["team"])
		names[id] = p["name"]
		joined[id] = _joined_year(p, debut.get(id), start_year)
	var first_trade := {}
	_trade_index = 0
	for t in _trades:
		var date: String = t["date"]
		if date < "%d-01-01" % start_year:
			_trade_index += 1
			continue
		if date.substr(0, 4) != str(start_year):
			break
		for mv: Dictionary in t["moves"]:
			var pid: String = mv["pid"]
			if not team_of.has(pid):
				continue
			if date < opening_date:
				team_of[pid] = _team_name(mv["to"], start_year)
			elif not first_trade.has(pid):
				first_trade[pid] = true
				team_of[pid] = _team_name(mv["from"], start_year)
		if date < opening_date:
			_trade_index += 1
	for id: String in team_of:
		var p := GameData.player(id)
		var draft := _rookie_draft(p, start_year - 1)
		var foreign := RosterRules.is_foreign(p, start_year, debut.get(id))
		var amount := Salary.rookie(draft, start_year) if not draft.is_empty() else Salary.initial(
				p, years_in_npb(id, start_year), foreign, start_year)
		_set_salary(id, amount, start_year)


# --- トレード -------------------------------------------------------------------------

func _load_trades() -> void:
	var rows: Variant = GameData.read_data("trades.json")
	if not rows is Array:
		return
	var by_id := {}
	for r: Dictionary in rows:
		var key: String = r["trade_id"]
		if not by_id.has(key):
			by_id[key] = {"id": key, "date": r["date"], "moves": []}
			_trades.append(by_id[key])
		by_id[key]["moves"].append({
			"pid": r["player_id"] if r.get("player_id") != null else "",
			"name": r["name"], "from": r["from_team"], "to": r["to_team"]})
	_trades.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["date"] < b["date"] if a["date"] != b["date"] else a["id"] < b["id"])


## date（"YYYY-MM-DD"）までの史実のトレードを実行する。実行した移籍 [{pid, from, to}] を返す
func apply_trades_until(date: String) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	while _trade_index < _trades.size() and _trades[_trade_index]["date"] <= date:
		var t: Dictionary = _trades[_trade_index]
		_trade_index += 1
		var trade_year := int(t["date"].substr(0, 4))
		var reason := ""
		var moves: Array[Dictionary] = []
		for mv: Dictionary in t["moves"]:
			var from := _team_name(mv["from"], trade_year)
			var to := _team_name(mv["to"], trade_year)
			moves.append({"pid": mv["pid"], "name": mv["name"], "from": from, "to": to})
			if from == user_team or to == user_team:
				reason = "自球団が関わる"
			elif reason.is_empty() and (mv["pid"].is_empty() or team_of.get(mv["pid"], "") != from):
				reason = "%sが%sにいない" % [mv["name"], GameData.short_name(from)]
		if not reason.is_empty():
			_log(t["date"], "trade_skipped", "", t["id"], "", "", "史実のトレード（%s）は起きない：%s" % [
				_trade_label(moves), reason])
			continue
		for mv in moves:
			team_of[mv["pid"]] = mv["to"]
			_log(t["date"], "trade", mv["pid"], mv["name"], mv["from"], mv["to"],
					"%s：%s → %s（トレード）" % [mv["name"], GameData.short_name(mv["from"]),
						GameData.short_name(mv["to"])])
			done.append(mv)
	return done


static func _trade_label(moves: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for mv in moves:
		parts.append("%s %s→%s" % [mv["name"], GameData.short_name(mv["from"]),
			GameData.short_name(mv["to"])])
	return "、".join(parts)


# --- オフ ---------------------------------------------------------------------------

## FA・トレード・ポスティング：史実でこのオフにメジャーへ移籍する選手が退団する
func depart_mlb(season_year: int) -> void:
	for id: String in team_of.keys():
		var m: Dictionary = _moves_by_id.get(id, {})
		if m.is_empty() or int(m["left_after"]) != season_year:
			continue
		var from: String = team_of[id]
		team_of.erase(id)
		in_mlb[id] = m
		var route := "ポスティング" if m.get("route") == "posting" else "海外FA等"
		_log("", "mlb_leave", id, names.get(id, m["name"]), from, "",
				"%s：%s → メジャー（%s）" % [names.get(id, m["name"]), GameData.short_name(from), route])


## 来季（season_year + 1）の準備。next: 来季の開幕時点の能力値ファイル、next_post: 来季のシーズン後の能力値
## ファイル（外国人市場の評価に使う。無ければ空）。
## 引退・仮IDの付け替え・メジャーからの復帰・新加入・外国人市場の候補を決める（実行はフェーズごと）
func prepare_next_year(season_year: int, next: Dictionary, next_post: Dictionary = {}) -> void:
	var next_year := season_year + 1
	var post := {}
	for p: Dictionary in next_post.get("players", []):
		post[p["id"]] = p
	var debut := GameData.load_debut_years(next_year)
	var entries := {}
	for p: Dictionary in next.get("players", []):
		entries[p["id"]] = p
	var renames := _match_renames(entries)
	var renamed_to := {}
	for old: String in renames:
		renamed_to[renames[old]] = old
	var retire: Array[String] = []
	for id: String in team_of:
		if not entries.has(id) and not renames.has(id):
			retire.append(id)
	var returns: Array[String] = []
	var newcomers: Array[String] = []
	market.clear()
	market_info.clear()
	cpu_demand.clear()
	for id: String in entries:
		if team_of.has(id) or renamed_to.has(id):
			continue
		var p: Dictionary = entries[id]
		var m: Dictionary = _moves_by_id.get(id, {})
		if not m.is_empty() and m.get("returned") != null and int(m["returned"]) == next_year:
			returns.append(id)
		elif RosterRules.is_foreign(p, next_year, debut.get(id)):
			_add_candidate(p, next_year, post.get(id, {}))
		else:
			newcomers.append(id)
	_plan = {"year": next_year, "entries": entries, "renames": renames, "retire": retire,
		"returns": returns, "newcomers": newcomers, "debut": debut}


func _add_candidate(p: Dictionary, next_year: int, post: Dictionary) -> void:
	var id: String = p["id"]
	var hist: String = p.get("hist_team", p["team"])
	var pitcher: bool = p.get("is_pitcher", false)
	var basis := post if not post.is_empty() else p
	var a := Salary.ability(basis)
	var noise := _rng.randfn(0.0, MARKET_NOISE)
	market.append(id)
	names[id] = p["name"]
	market_info[id] = {"hist_team": hist, "pitcher": pitcher, "value": a[0] + 0.5 * a[1] + noise,
		"asking": Salary.foreign_asking(basis, noise, next_year)}
	var team := _current_name(hist)
	if team != user_team:
		if not cpu_demand.has(team):
			cpu_demand[team] = {"p": 0, "b": 0}
		cpu_demand[team]["p" if pitcher else "b"] += 1
	_log("", "foreign_candidate", id, p["name"], "", "", "%s（%s）が外国人市場に（史実は%s）" % [
		p["name"], "投手" if pitcher else "野手", GameData.short_name(team)])


## 仮ID（tmp:球団コード:名前）の選手が来季のファイルで本来のIDになっていれば {旧ID: 新ID}
func _match_renames(entries: Dictionary) -> Dictionary:
	var by_name := {}
	for id: String in entries:
		if not team_of.has(id) and not names.has(id):
			by_name[norm_name(entries[id]["name"])] = id
	var result := {}
	for id: String in team_of:
		if id.begins_with("tmp:") and not entries.has(id):
			var key := norm_name(names.get(id, ""))
			if by_name.has(key):
				result[id] = by_name[key]
				by_name.erase(key)
	return result


## メジャーからの復帰（FA・トレード・ポスティング）。戻り先は史実の球団
func apply_returns() -> void:
	for id: String in _plan.get("returns", []):
		var p: Dictionary = _plan["entries"][id]
		var team := _current_name(p.get("hist_team", p["team"]))
		team_of[id] = team
		in_mlb.erase(id)
		names[id] = p["name"]
		if not joined.has(id):
			joined[id] = _joined_year(p, _plan["debut"].get(id), _plan["year"])
		var next_year: int = _plan["year"]
		_set_salary(id, Salary.initial(p, years_in_npb(id, next_year), false, next_year), next_year)
		_log("", "mlb_return", id, p["name"], "", team, "%s：メジャー → %s（復帰）" % [
			p["name"], GameData.short_name(team)])


## 契約更改：今季のゲーム内成績（season。無ければ能力値だけ）で来季の年俸を決める
func renew_contracts(season_year: int, season: Season) -> void:
	var next_year := season_year + 1
	var retiring: Array = _plan.get("retire", [])
	var debut := GameData.load_debut_years(season_year)
	for id: String in team_of:
		if id in retiring or not salary.has(id):
			continue
		# このオフに加わった選手（メジャーからの復帰など）は加入時の額のまま
		var history: Array = salary_history.get(id, [])
		if not history.is_empty() and history[-1]["year"] == next_year:
			continue
		var p := GameData.player(id)
		if p.is_empty():
			continue
		var stats: Dictionary = {}
		if season != null:
			stats = (season.pitching if p.get("is_pitcher", false) else season.batting).get(id, {})
		var foreign := RosterRules.is_foreign(p, next_year, debut.get(id))
		var years := years_in_npb(id, next_year)
		_set_salary(id, Salary.renew(salary[id], p, stats, years, foreign, next_year), next_year)


## 戦力外・引退：来季の能力値ファイルにいない選手
func apply_retirements() -> void:
	for id: String in _plan.get("retire", []):
		if not team_of.has(id):
			continue
		var team: String = team_of[id]
		team_of.erase(id)
		retired[id] = _plan["year"] - 1
		var p := GameData.player(id)
		var foreign := RosterRules.is_foreign(p, _plan["year"] - 1, null) if not p.is_empty() else false
		_log("", "retire", id, names.get(id, id), team, "", "%s（%s）%s" % [
			names.get(id, id), GameData.short_name(team), "退団" if foreign else "引退"])


## ドラフト：新人とその他の新加入（史実の球団へ）
func apply_newcomers() -> void:
	var next_year: int = _plan.get("year", year + 1)
	for id: String in _plan.get("newcomers", []):
		var p: Dictionary = _plan["entries"][id]
		var team := _current_name(p.get("hist_team", p["team"]))
		team_of[id] = team
		names[id] = p["name"]
		retired.erase(id)
		var draft := _rookie_draft(p, next_year - 1)
		if not joined.has(id):
			var debut_year: Variant = _plan["debut"].get(id)
			joined[id] = next_year if not draft.is_empty() else _joined_year(p, debut_year, next_year)
		var amount := Salary.rookie(draft, next_year) if not draft.is_empty() else Salary.initial(
				p, years_in_npb(id, next_year), false, next_year)
		_set_salary(id, amount, next_year)
		var kind := "rookie" if not draft.is_empty() else "join"
		var what := "新人" if kind == "rookie" else "入団"
		var text := "%s：%s（%s）" % [p["name"], GameData.short_name(team), what]
		_log("", kind, id, p["name"], "", team, text)


## 外国人市場の選手を獲得する（自球団・CPU球団とも）。獲得できなければ空でないエラー文
func sign_foreign(id: String, team: String) -> String:
	if id not in market:
		return "市場にいない選手です"
	market.erase(id)
	var info: Dictionary = market_info[id]
	team_of[id] = team
	joined[id] = _plan.get("year", year + 1)
	_set_salary(id, info["asking"], joined[id])
	var name: String = names.get(id, id)
	_log("", "foreign_sign", id, name, "", team, "%s：%s が獲得（%s、史実は%s）" % [
		name, GameData.short_name(team), Salary.text(info["asking"]),
		GameData.short_name(_current_name(info["hist_team"]))])
	return ""


## CPU球団が外国人市場から獲得する（1巡でそれぞれ最大 picks 人。picks < 0 は残りの必要人数すべて）
func cpu_market_round(picks: int = 1) -> void:
	var order: Array = cpu_demand.keys()
	order.sort()
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	var rounds := 0
	var any := true
	while any and (picks < 0 or rounds < picks):
		any = false
		rounds += 1
		for team: String in order:
			var need: Dictionary = cpu_demand[team]
			if need["p"] + need["b"] <= 0:
				continue
			var want_pitcher: bool = need["p"] >= need["b"]
			var id := _best_candidate(want_pitcher)
			if id.is_empty():
				id = _best_candidate(not want_pitcher)
			if id.is_empty():
				return
			var kind := "p" if market_info[id]["pitcher"] else "b"
			if need[kind] <= 0:
				kind = "b" if kind == "p" else "p"
			need[kind] -= 1
			sign_foreign(id, team)
			any = true


func _best_candidate(pitcher: bool) -> String:
	var best := ""
	var best_value := -INF
	for id in market:
		if market_info[id]["pitcher"] != pitcher:
			continue
		var value: float = market_info[id]["value"]
		if value > best_value:
			best_value = value
			best = id
	return best


## 春季キャンプ（新しい年）：仮IDの付け替え・球団名の変更・新しい年の能力値ファイルにいない選手の整理
func begin_year(new_year: int, ratings: Dictionary) -> void:
	year = new_year
	var renames: Dictionary = _plan.get("renames", {})
	for old: String in renames:
		_rename(old, renames[old])
	var teams := {}
	for p: Dictionary in ratings.get("players", []):
		teams[p.get("hist_team", p["team"])] = true
	for old: String in TEAM_SUCCESSOR:
		var succ: String = TEAM_SUCCESSOR[old]
		if teams.has(succ) and not teams.has(old):
			for id: String in team_of:
				if team_of[id] == old:
					team_of[id] = succ
			for team: String in cpu_demand.keys():
				if team == old:
					cpu_demand[succ] = cpu_demand[old]
					cpu_demand.erase(old)
			if user_team == old:
				user_team = succ
			_log("", "rename", "", "", old, succ, "球団名の変更：%s → %s" % [old, succ])
	# 念のため：能力値の無い選手は所属から外す（通常は「戦力外・引退」で整理済み）
	var ids := {}
	for p: Dictionary in ratings.get("players", []):
		ids[p["id"]] = true
	for id: String in team_of.keys():
		if not ids.has(id):
			push_warning("能力値の無い選手を所属から外します: %s %s" % [id, names.get(id, "")])
			retired[id] = new_year - 1
			team_of.erase(id)


func _rename(old: String, new_id: String) -> void:
	for dict: Dictionary in [team_of, salary, salary_history, joined, names]:
		if dict.has(old):
			dict[new_id] = dict[old]
			dict.erase(old)
	_log("", "rename", new_id, names.get(new_id, ""), old, new_id, "%s：仮ID %s → %s" % [
		names.get(new_id, ""), old, new_id])


## 開幕：外国人市場を閉じる（残った選手は来日しない）
func close_market() -> void:
	for id in market:
		_log("", "foreign_unsigned", id, names.get(id, id), "", "", "%s：どの球団とも契約せず" % names.get(id, id))
	market.clear()
	cpu_demand.clear()
	_plan = {}


# --- 参照 -----------------------------------------------------------------------------

func players_of(team: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in team_of:
		if team_of[id] == team:
			result.append(id)
	return result


## 球団の年俸総額（万円）
func payroll(team: String) -> int:
	var total := 0
	for id: String in team_of:
		if team_of[id] == team:
			total += int(salary.get(id, 0))
	return total


func salary_of(id: String) -> int:
	return int(salary.get(id, 0))


## 在籍年数（その年が何年目か。1年目=1）
func years_in_npb(id: String, at_year: int) -> int:
	return maxi(1, at_year - int(joined.get(id, at_year)) + 1)


## その年の出来事（kind を指定するとその種類だけ）
func events(of_year: int, kind: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in log:
		if e["year"] == of_year and (kind.is_empty() or e["kind"] == kind):
			result.append(e)
	return result


# --- 内部 -----------------------------------------------------------------------------

func _set_salary(id: String, amount: int, for_year: int) -> void:
	salary[id] = amount
	if not salary_history.has(id):
		salary_history[id] = []
	var history: Array = salary_history[id]
	var entry := {"year": for_year, "team": team_of.get(id, ""), "salary": amount}
	if not history.is_empty() and history[-1]["year"] == for_year:
		history[-1] = entry
	else:
		history.append(entry)


func _log(date: String, kind: String, id: String, name: String, from: String, to: String,
		text: String) -> void:
	log.append({"year": year, "date": date, "kind": kind, "id": id, "name": name, "from": from,
		"to": to, "text": text})


## 史実のデータの略称（"読売" "横浜" "西武" など）→ 今の所属の球団名
func _team_name(short: String, at_year: int) -> String:
	return _current_name(GameData.resolve_team(short, at_year))


## 来季のファイルの球団名が、今の所属ではまだ旧名なら旧名に直す（例：2011年オフの DeNA → 横浜）
func _current_name(team: String) -> String:
	for old: String in TEAM_SUCCESSOR:
		if TEAM_SUCCESSOR[old] == team and team_of.values().has(old):
			return old
	return team


## NPB に入った年：ドラフト（"2000年ドラフト1位" → 2001年）→ 1軍初出場の年 → その年
static func _joined_year(p: Dictionary, debut_year: Variant, fallback: int) -> int:
	var draft: Variant = p.get("draft")
	if draft is String and draft.length() >= 5 and draft.substr(4, 1) == "年" \
			and draft.substr(0, 4).is_valid_int():
		return int(draft.substr(0, 4)) + 1
	if debut_year != null:
		return int(debut_year)
	return fallback


## その年のドラフトで指名された新人なら {round, high_school, ikusei}、違えば空
static func _rookie_draft(p: Dictionary, draft_year: int) -> Dictionary:
	if p.is_empty():
		return {}
	var text: String = p.get("draft") if p.get("draft") is String else ""
	if not text.is_empty() and not text.begins_with("%d年" % draft_year):
		return {}
	# 選手ページのない選手（1軍出場なし）はドラフト会議の指名一覧から名前で探す
	var entry: Dictionary = GameData.draft_entry(p["name"], draft_year)
	if entry.is_empty() and text.is_empty():
		return {}
	var result := {"round": 6, "high_school": false, "ikusei": false}
	var round_text: String = entry.get("round", "")
	if round_text.is_empty():
		var k := text.find("ドラフト")
		round_text = text.substr(k + 4) if k >= 0 else ""
	var digits := ""
	for c in round_text:
		if c.is_valid_int():
			digits += c
		elif not digits.is_empty():
			break
	if not digits.is_empty():
		result["round"] = int(digits)
	elif "自由" in round_text or "希望" in round_text:
		result["round"] = 1
	if not entry.is_empty():
		result["high_school"] = str(entry.get("school", "")).ends_with("高")
		result["ikusei"] = bool(entry.get("ikusei", false))
	else:
		result["high_school"] = "高校生" in text
		result["ikusei"] = "育成" in text
	return result


## 名前の突合用（空白を除き、異体字をそろえる）
static func norm_name(s: String) -> String:
	var result := s.replace(" ", "").replace("　", "").replace("・", "")
	for pair: Array in [["﨑", "崎"], ["髙", "高"], ["濵", "浜"], ["邊", "辺"], ["邉", "辺"], ["德", "徳"],
			["瀨", "瀬"], ["齋", "斎"], ["齊", "斉"], ["櫻", "桜"], ["澤", "沢"], ["眞", "真"]]:
		result = result.replace(pair[0], pair[1])
	return result
