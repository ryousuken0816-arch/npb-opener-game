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
##   史実の球団へ復帰する。自球団の選手は FA・ポスティングの画面で引き留めを試せる（FreeAgency。成功したら
##   kept_mlb に入り、来季以降はメジャーにいた年の能力値＝GameData.mlb_player、無ければ直前のNPBの能力値を使う）
## - 国内FA：FreeAgency（宣言・入札・移籍）。決まった年俸は契約年数のあいだ据え置き（contract_until）
## - 引退：来季の能力値ファイルにいない選手（成績が無く能力を計算できない）は「戦力外・引退」で引退
## - 戦力外：「戦力外・引退」（Releases）で支配下の上限 ROSTER_LIMIT に合わせて決める。来季のファイルにいる選手は
##   市場（market。外国人市場と同じ一覧で、market_info に released）に入り他球団が獲得できる。いなければ引退扱い。
##   開幕までにどこも獲らなければ引退（released に残り、以後の年に新加入として戻ってこない）
## - 新人：「ドラフト」（Draft。その年の史実のドラフト指名選手が候補）で指名した球団に入る。指名されなかった候補は入団しない
##   （draft_unsigned に残り、以後の年にも新加入として来ない）。能力値ファイルにいない候補は仮の選手（draft_synth）
## - その他の新加入（ドラフト以外。来季のファイルに初めて出てくる日本人）：「ドラフト」の段階で史実の球団に入る
## - 新外国人：「外国人市場」の候補になる。自球団は新戦力の画面で獲得、CPU球団はオフのフェーズごとに自動で獲得
##   （各球団が史実で獲得した人数ぶん。能力の高い順）。開幕までに誰も獲らなかった選手は来日しない
## - 1軍に出ていない選手の仮ID（tmp:…）は、1軍に出た年に本来の選手IDへ付け替える（名前で突合）

## 外国人市場の評価の誤差（z）。候補の評価・提示額は史実の来季の成績（来季のシーズン後の能力値）に
## この大きさの誤差を足した「不完全な未来視」（docs/SPEC.md のドラフトと同じ考え方）。画面の能力は開幕時点のまま
const MARKET_NOISE := 0.5

## 球団名が変わった球団（旧 → 新）。新しい年の能力値ファイルに旧名が無ければ付け替える
const TEAM_SUCCESSOR := {"横浜ベイスターズ": "横浜DeNAベイスターズ"}

## 支配下登録の上限（育成選手は数えない）
const ROSTER_LIMIT := 70
## 育成の契約年数（満了したら育成で再契約。_renew_ikusei）
const IKUSEI_CONTRACT_YEARS := 3
## CPU球団の育成からの昇格：支配下の実力の下からこの割合の選手より良ければ上げる。23歳以下は実力に足す
const CPU_PROMOTE_SHARE := 0.5
const CPU_PROMOTE_YOUTH := 0.3
## CPU球団が戦力外にするとき、投手・野手それぞれ最低これだけは残す
const MIN_KEEP_PITCHERS := 26
const MIN_KEEP_FIELDERS := 26
## CPU球団が市場の戦力外の選手を獲る評価（market_info.value）の下限と、1つのフェーズで獲る最大人数
const RELEASE_SIGN_MIN := -0.6
const RELEASE_SIGN_PER_ROUND := 1
## 戦力外の選手の市場での提示額（来季の見立ての年俸に対する割合）
const RELEASE_ASKING_RATE := 0.7
## 戦力外にした選手の出来事の種類（今オフに加わった選手＝戦力外にしない、の判定に使う）
const JOINED_KINDS := ["mlb_return", "fa_move", "fa_stay", "mlb_keep", "foreign_sign", "release_sign", "trade"]

## 2027年以降の日本人のメジャー移籍と帰国（docs/AUTORUN.md 作業41）
const MLB_FUTURE_START_YEAR := 2027
const MLB_DEPART_MIN_AGE := 25
const MLB_DEPART_MAX_AGE := 35
const MLB_DEPART_MIN_ABILITY := 0.70  ## トップクラスの実力z
const MLB_RETURN_MIN_AGE := 30
const MLB_RETURN_PEAK_AGE := 35
## 育成から支配下に登録した選手 → {year, date, team}（この年から支配下。docs/AUTORUN.md 作業19）
var promoted := {}
## 能力値ファイルにいないドラフトの新人（仮の選手）を何シーズン置いておくか（その間にファイルに出てこなければ引退）
const SYNTH_SEASONS := 3

var year: int
var user_team := ""
var team_of := {}              ## 選手ID → 球団（正式名）。所属している選手だけ
var salary := {}               ## 選手ID → 年俸（万円）。今の契約（オフの契約更改後は来季の額）
var salary_history := {}       ## 選手ID → [{year, team, salary}]（ゲーム内の契約の推移）
var joined := {}               ## 選手ID → NPB に入った年（在籍年数の起点）
var names := {}                ## 選手ID → 名前（引退・メジャーの選手も。一度でも所属した選手）
var retired := {}              ## 選手ID → 引退した年（その年のシーズン後）
var in_mlb := {}               ## 選手ID → mlb_moves の1件（今メジャーにいる選手）
## 選手ID → ポスティングを認めると約束した年（その年のシーズン後にメジャーへ。メジャー志望の新人の説得、作業26）
var posting_promise := {}
var market: Array[String] = [] ## 外国人市場の候補（未契約）
var market_info := {}          ## 選手ID → {hist_team, asking, pitcher}
var cpu_demand := {}           ## CPU球団 → {"p": 投手の残り人数, "b": 野手の残り人数}
var contract_until := {}       ## 選手ID → 複数年契約の最終年（その年まで契約更改で年俸が変わらない）
var fa_year := {}              ## 選手ID → 最後にFA権を行使した年（宣言した年）
## 引き留めたメジャー移籍の選手 → {move: mlb_moves の1件, fallback: 直前のNPBの能力値, last: 能力値を使う最後の年}
var kept_mlb := {}
## このオフの FA・ポスティング（FA・トレード・ポスティングの段階で作る。それ以外は前のオフのまま）
var fa: FreeAgency = null
## このオフの契約更改（契約更改の段階で作る。それ以外は前のオフのまま）
var contracts: ContractRenewal = null
## このオフの戦力外・引退（戦力外・引退の段階で作る。それ以外は前のオフのまま）
var releases: Releases = null
## 戦力外にした選手 → {year, from, market: 市場に出たか}
var released := {}
## このオフのドラフト（ドラフトの段階で作る。それ以外は前のオフのまま）
var draft: Draft = null
## ドラフトで入団した選手 → {year, team, round, ikusei, label}（育成の判定・選手詳細に使う）
var drafted := {}
## 能力値ファイルにいないドラフトの新人（仮の選手）→ 選手データ（GameData.set_extra_players で引けるようにする）
var draft_synth := {}
## ドラフトで指名されなかった候補（名前（norm_name）→ ドラフトの年）。以後の年に新加入として来ない
var draft_unsigned := {}
## 支配下の上限を守る（最初の戦力外・引退の段階から。2008年の開幕時点の編成はそのまま）
var limit_active := false
## 出来事の記録 {year, date, kind, id, name, from, to, text}。kind: trade / trade_skipped / mlb_leave /
## mlb_return / retire / rookie / join / foreign_candidate / foreign_sign / foreign_unsigned /
## rename / fa_declare / fa_move / fa_stay / mlb_keep / mlb_keep_failed / release / release_sign / release_unsigned /
## release_trim
var log: Array[Dictionary] = []

## 自球団のトレード交渉を断った球団 → 断った日（シーズン中は日付、オフは「年-段階」。同じ日にはもう交渉できない）
var trade_refused := {}
## このオフのFA移籍の補償（FAを締め切ったときに作る。FaCompensation）
var compensation: FaCompensation = null
## FAの補償で移った指名権 [{year（ドラフトの年）, round, from（獲得球団＝指名権を失う）, to（旧球団）, id（FAの選手）}]
var draft_pick_comp: Array = []
var _trades: Array[Dictionary] = []  ## trade_id ごと、日付順 {id, date, moves: [{pid, name, from, to}]}
var _trade_index := 0
var _moves_by_id := {}
var _roster_teams := {}  ## 年 → 選手ID → [球団]（_infer_trade_dest 用）
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
			if not team_of.has(pid) or str(mv["to"]).is_empty():
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
	if start_year >= MLB_FUTURE_START_YEAR:
		_sync_historical_mlb_players(start_year)


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
		var pid: String = r["player_id"] if r.get("player_id") != null else ""
		var to: String = r["to_team"]
		if to.is_empty() or to.is_valid_int():
			to = _infer_trade_dest(pid, r["date"], r["from_team"])
		by_id[key]["moves"].append({"pid": pid, "name": r["name"], "from": r["from_team"], "to": to})
	_trades.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["date"] < b["date"] if a["date"] != b["date"] else a["id"] < b["id"])


## trades.json の2018年度以降は移籍先（to_team）が背番号や空欄になっている行がある（取得時の列ずれ）。
## その選手がトレードの後にいる球団を data/<年>/rosters.json から探す（11月以降のトレードは翌年の名簿を先に見る）。
## 移籍元と違う球団が見つからなければ空（apply_trades_until で「移籍先が不明」として起こさない）
func _infer_trade_dest(pid: String, date: String, from_short: String) -> String:
	if pid.is_empty():
		return ""
	var y := int(date.substr(0, 4))
	var years := [y + 1, y] if int(date.substr(5, 2)) >= 11 else [y, y + 1]
	for ry: int in years:
		var from := GameData.resolve_team(from_short, ry)
		if not _roster_teams.has(ry):
			var by_pid := {}
			var rows: Variant = GameData.read_data("%d/rosters.json" % ry)
			if rows is Array:
				for row: Dictionary in rows:
					if row.get("player_id") != null:
						if not by_pid.has(row["player_id"]):
							by_pid[row["player_id"]] = []
						by_pid[row["player_id"]].append(row["team"])
			_roster_teams[ry] = by_pid
		for team: String in _roster_teams[ry].get(pid, []):
			if team != from:
				return team
	return ""


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
			if to.is_empty():
				reason = "%sの移籍先が不明" % mv["name"]
			elif from == user_team or to == user_team:
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

## FA・トレード・ポスティング：史実でこのオフにメジャーへ移籍する選手が退団する。退団した選手 [{id, from, route}]
func depart_mlb(season_year: int) -> Array[Dictionary]:
	var leaving: Array[Dictionary] = []
	var ids: Array = team_of.keys()
	ids.sort()
	for id: String in ids:
		var m: Dictionary = _moves_by_id.get(id, {})
		if m.is_empty() or int(m["left_after"]) != season_year:
			continue
		var from: String = team_of[id]
		team_of.erase(id)
		in_mlb[id] = m
		var route := "ポスティング" if m.get("route") == "posting" else "海外FA等"
		_log("", "mlb_leave", id, names.get(id, m["name"]), from, "",
				"%s：%s → メジャー（%s）" % [names.get(id, m["name"]), GameData.short_name(from), route])
		leaving.append({"id": id, "from": from, "route": route})
	for id: String in posting_promise.keys():
		if int(posting_promise[id]) != season_year or not team_of.has(id):
			continue
		var from: String = team_of[id]
		team_of.erase(id)
		posting_promise.erase(id)
		in_mlb[id] = {"player_id": id, "name": names.get(id, id), "left_after": season_year, "route": "posting",
			"npb_team_before": from, "returned": null, "promised": true}
		_log("", "mlb_leave", id, names.get(id, id), from, "",
				"%s：%s → メジャー（ポスティング。入団時の約束）" % [names.get(id, id), GameData.short_name(from)])
		leaving.append({"id": id, "from": from, "route": "ポスティング"})
	# 2027年以降の架空メジャー移籍（作業41）
	if season_year >= MLB_FUTURE_START_YEAR:
		_sync_historical_mlb_players(season_year)
		var future_leaving := _decide_future_mlb_departures(season_year)
		leaving.append_array(future_leaving)
	return leaving


## 2027年以降の架空メジャー進行のために、過去の史実メジャー在籍選手を in_mlb に同期する（作業41）
func _sync_historical_mlb_players(season_year: int) -> void:
	for id: String in _moves_by_id:
		var m: Dictionary = _moves_by_id[id]
		var left: int = int(m.get("left_after", 9999))
		var ret = m.get("returned")
		var is_returned := (ret != null and int(ret) <= season_year)
		if left <= season_year and not is_returned and not team_of.has(id) and not retired.has(id):
			if not in_mlb.has(id):
				var copy: Dictionary = m.duplicate(true)
				copy["npb_team_before"] = GameData.resolve_team(str(copy.get("npb_team_before", "")), season_year)
				in_mlb[id] = copy
			if not names.has(id):
				names[id] = str(m.get("name", id))


## 2027年以降の架空メジャー移籍の判定（作業41）
func _decide_future_mlb_departures(season_year: int) -> Array[Dictionary]:
	var debut := GameData.load_debut_years(season_year)
	var candidates: Array[Dictionary] = []
	var ids: Array = team_of.keys()
	ids.sort()
	for id: String in ids:
		if id.begins_with("tmp:") or int(contract_until.get(id, 0)) > season_year:
			continue
		var p := GameData.player(id)
		if p.is_empty() or RosterRules.is_foreign(p, season_year, debut.get(id)):
			continue
		var age := FreeAgency.age_of(p, season_year)
		if age < MLB_DEPART_MIN_AGE or age > MLB_DEPART_MAX_AGE:
			continue
		var a: Array = Salary.ability(p)
		var z: float = a[0]
		var play: float = a[1]
		if z < MLB_DEPART_MIN_ABILITY or play < 0.4:
			continue
		var years := years_in_npb(id, season_year)
		var is_overseas_fa := (years >= 9)
		var is_posting := (years >= 3 and years < 9 and z >= 0.85)
		if not is_overseas_fa and not is_posting:
			continue
		var score := (z - 0.7) * 2.0 + (1.0 - absf(float(age) - 28.5) * 0.1)
		if is_overseas_fa:
			score += 0.5
		candidates.append({"id": id, "from": team_of[id], "years": years,
			"route": "海外FA" if is_overseas_fa else "ポスティング",
			"score": score * _rng.randf_range(0.85, 1.15)})
	candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x["score"] > y["score"])
	# 年1〜3人（史実の2008〜2025年：平均約2人）
	var count := _rng.randi_range(1, 3)
	if candidates.size() < count:
		count = candidates.size()
	var chosen: Array[Dictionary] = []
	for i in count:
		var c: Dictionary = candidates[i]
		var id: String = c["id"]
		var from: String = c["from"]
		var route: String = c["route"]
		team_of.erase(id)
		var p := GameData.player(id)
		in_mlb[id] = {"player_id": id, "name": names.get(id, id), "left_after": season_year, "route": route,
			"npb_team_before": from, "returned": null, "fictional": true, "birth": p.get("birth", "")}
		_log("", "mlb_leave", id, names.get(id, id), from, "",
				"%s：%s → メジャー（%s）" % [names.get(id, id), GameData.short_name(from), route])
		chosen.append({"id": id, "from": from, "route": route})
	return chosen


## 2027年以降のメジャーからの帰国判定（作業41）
func decide_mlb_returns(season_year: int) -> Array[String]:
	if season_year < MLB_FUTURE_START_YEAR:
		return []
	var candidates: Array[Dictionary] = []
	var ids: Array = in_mlb.keys()
	ids.sort()
	for id: String in ids:
		var m: Dictionary = in_mlb[id]
		# 今オフ移籍したばかりの選手、またはすでに帰国/引退した選手は除く
		if int(m.get("left_after", 0)) >= season_year or m.get("returned") != null or retired.has(id):
			continue
		var p := GameData.mlb_player(id)
		if p.is_empty():
			p = GameData.player(id)
		if p.is_empty():
			continue
		var age := FreeAgency.age_of(p, season_year)
		var mlb_years := season_year - int(m.get("left_after", season_year - 1))
		var a: Array = Salary.ability(p)
		var z: float = a[0]
		# 30代半ば中心の確率
		var base_p := 0.05
		if age <= 29:
			base_p = 0.02
		elif age <= 31:
			base_p = 0.10
		elif age <= 33:
			base_p = 0.22
		elif age <= 35:
			base_p = 0.40
		elif age <= 37:
			base_p = 0.50
		else:
			base_p = 0.45
		if mlb_years >= 3:
			base_p += 0.10
		if z < 0.2:
			base_p += 0.15
		var weight := base_p * _rng.randf_range(0.8, 1.2)
		if _rng.randf() < base_p:
			candidates.append({"id": id, "weight": weight})
	candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x["weight"] > y["weight"])
	# 年1〜2人
	var max_returns := _rng.randi_range(1, 2)
	var returns: Array[String] = []
	for i in mini(max_returns, candidates.size()):
		var id: String = candidates[i]["id"]
		returns.append(id)
		var m: Dictionary = in_mlb[id]
		var from_team: String = m.get("npb_team_before", "")
		_log("", "mlb_declare_return", id, names.get(id, id), "", from_team,
				"%sが日本球界への復帰を表明" % names.get(id, id))
	return returns


## FA・ポスティングの段階を始める（depart_mlb・prepare_next_year のあと）。自球団の入札・引き留めは fa で行う
func open_fa(season_year: int, leaving: Array[Dictionary], mlb_returns: Array[String] = []) -> FreeAgency:
	fa = FreeAgency.new()
	fa.open(self, season_year, leaving, _rng.randi(), mlb_returns)
	return fa


## このオフに引退する予定の選手（prepare_next_year で決めたもの）
func plan_retirements() -> Array:
	return _plan.get("retire", [])


## FAの移籍・残留を決める（FreeAgency.resolve から）。bidders: 入札した球団の数
func sign_fa(id: String, from: String, to: String, amount: int, years: int, next_year: int,
		bidders: int) -> void:
	var was_in_mlb := in_mlb.has(id)
	if was_in_mlb:
		in_mlb.erase(id)
	team_of[id] = to
	_set_salary(id, amount, next_year)
	contract_until[id] = next_year + years - 1
	fa_year[id] = next_year - 1
	var name: String = names.get(id, id)
	if was_in_mlb:
		if to == from:
			_log("", "mlb_return", id, name, "", to, "%s：%sに復帰（メジャーから復帰、%s・%d年）" % [
				name, GameData.short_name(to), Salary.text(amount), years])
		else:
			_log("", "mlb_return", id, name, "", to, "%s：メジャー → %s（復帰、%s・%d年、%d球団が入札）" % [
				name, GameData.short_name(to), Salary.text(amount), years, bidders])
	elif to == from:
		_log("", "fa_stay", id, name, from, to, "%s：%sに残留（FA、%s・%d年）" % [
			name, GameData.short_name(to), Salary.text(amount), years])
	else:
		_log("", "fa_move", id, name, from, to, "%s：%s → %s（FA、%s・%d年、%d球団が入札）" % [
			name, GameData.short_name(from), GameData.short_name(to), Salary.text(amount), years, bidders])


## メジャー移籍の引き留めに成功：元の球団に戻し、来季以降の能力値の出どころを覚えておく
func keep_from_mlb(id: String, team: String, amount: int, years: int, next_year: int) -> void:
	var m: Dictionary = in_mlb.get(id, _moves_by_id.get(id, {}))
	in_mlb.erase(id)
	team_of[id] = team
	_set_salary(id, amount, next_year)
	contract_until[id] = next_year + years - 1
	var last := 9999
	if m.get("returned") == null and m.get("mlb_last") != null:
		last = int(m["mlb_last"])
	kept_mlb[id] = {"move": m, "fallback": GameData.player(id).duplicate(true), "last": last}
	_log("", "mlb_keep", id, names.get(id, id), team, team, "%s：メジャー移籍をやめて%sに残留（引き留め、%s・%d年）" % [
		names.get(id, id), GameData.short_name(team), Salary.text(amount), years])


## 引き留めた選手の能力値の代わり（選手ID → 直前のNPBの能力値。GameData.set_kept_players へ）
func kept_fallbacks() -> Dictionary:
	var result := {}
	for id: String in kept_mlb:
		result[id] = kept_mlb[id]["fallback"]
	return result


## 引き留めた選手で、その年も能力値を使える（来季のファイルにいなくても引退させない）
func _kept_in(id: String, at_year: int) -> bool:
	return kept_mlb.has(id) and at_year <= int(kept_mlb[id]["last"])


## 画面などから出来事を記録する
## 自球団のトレードの出来事（出来事の一覧には史実のトレードと同じ「trade」で出る）
func log_trade(date: String, mv: Dictionary, text: String) -> void:
	_log(date, "trade", mv["pid"], mv["name"], mv["from"], mv["to"], text)


func log_event(kind: String, id: String, from: String, to: String, text: String) -> void:
	_log("", kind, id, names.get(id, id), from, to, text)


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
		if not entries.has(id) and not renames.has(id) and not _kept_in(id, next_year) \
				and not _synth_alive(id, next_year):
			retire.append(id)
	var returns: Array[String] = []
	var newcomers: Array[String] = []
	var draftees: Array[String] = []
	var fictional := 0
	market.clear()
	market_info.clear()
	cpu_demand.clear()
	for id: String in entries:
		if team_of.has(id) or renamed_to.has(id) or released.has(id):
			continue
		var p: Dictionary = entries[id]
		if _was_unsigned(p):
			continue
		var m: Dictionary = _moves_by_id.get(id, {})
		if not m.is_empty() and m.get("returned") != null and int(m["returned"]) == next_year:
			returns.append(id)
		elif RosterRules.is_foreign(p, next_year, debut.get(id)):
			_add_candidate(p, next_year, post.get(id, {}))
			if ForeignPlayers.is_fictional_foreign(p):
				fictional += 1
		elif _is_draftee(p, season_year):
			draftees.append(id)
		else:
			var target_team: String = p.get("hist_team", p.get("team", ""))
			if not target_team.is_empty():
				newcomers.append(id)
	if fictional > 0:
		_fictional_demand(next, retire, next_year, debut, fictional)
	_plan = {"year": next_year, "entries": entries, "renames": renames, "retire": retire,
		"returns": returns, "newcomers": newcomers, "draftees": draftees, "debut": debut, "post": post,
		"draft_quota": _draft_quota(season_year)}


## その年のドラフト会議の指名選手か（ドラフト会議の一覧に名前があり、選手ページのドラフトの年が違わない）
static func _is_draftee(p: Dictionary, draft_year: int) -> bool:
	var text: String = p.get("draft") if p.get("draft") is String else ""
	if not text.is_empty() and not text.begins_with("%d年" % draft_year):
		return false
	return not GameData.draft_entry_for(p, draft_year).is_empty()


## ドラフトで指名されなかった候補（同じ年のドラフトの選手）か
func _was_unsigned(p: Dictionary) -> bool:
	var key := norm_name(str(p.get("name", "")))
	if not draft_unsigned.has(key):
		return false
	var text: String = p.get("draft") if p.get("draft") is String else ""
	return text.is_empty() or text.begins_with("%d年" % int(draft_unsigned[key]))


## 史実のドラフトで各球団が指名した人数（今の所属の球団名 → {reg, ikusei}）。来季の新人の見込みに使う
func _draft_quota(draft_year: int) -> Dictionary:
	var result := {}
	var rows := Draft.draft_rows(draft_year)
	if not rows.is_empty() and bool(rows[0].get("amateur", false)):
		# 史実の無い年（アマ選手の候補）：どの球団も同じ人数
		for team: String in GameData.teams():
			result[team] = Draft.AMATEUR_QUOTA.duplicate()
		return result
	for d in rows:
		var team := _current_name(Draft.hist_team_of(d, draft_year))
		if team.is_empty():
			continue
		if not result.has(team):
			result[team] = {"reg": 0, "ikusei": 0}
		result[team]["ikusei" if d.get("ikusei", false) else "reg"] += 1
	return result


## 仮の選手（ドラフトの新人で能力値ファイルにいない）を at_year にも置いておくか
func _synth_alive(id: String, at_year: int) -> bool:
	return draft_synth.has(id) and at_year <= int(drafted.get(id, {}).get("year", 0)) + SYNTH_SEASONS


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
	if ForeignPlayers.is_fictional_foreign(p):
		# 架空の外国人（史実の無い年）：史実の球団が無いので、CPU球団の欲しい人数は _fictional_demand でまとめて決める
		var imp: Dictionary = p["import"]
		market_info[id]["fictional"] = true
		# 一覧に出す見立て：本当の能力に誤差（評価の誤差と同じ大きさ）を足した値
		var scout := {}
		var block: Variant = p.get("pitching") if pitcher else p.get("batting")
		if block is Dictionary and block.get("ratings") is Dictionary:
			for key: String in block["ratings"]:
				var r: Variant = block["ratings"][key]
				if r is Dictionary and r.get("value") != null:
					scout[key] = clampi(roundi(float(r["value"]) + _rng.randfn(0.0, MARKET_NOISE * SimPlayer.SCALE_SD)), 1, 100)
		market_info[id]["scout"] = scout
		_log("", "foreign_candidate", id, p["name"], "", "", "%s（%s、%s・前所属 %s）が外国人市場に" % [
			p["name"], "投手" if pitcher else "野手", imp.get("country", ""), str(p.get("career", "")).get_slice(" - ", 0)])
		return
	var team := _current_name(hist)
	if team != user_team:
		if not cpu_demand.has(team):
			cpu_demand[team] = {"p": 0, "b": 0}
		cpu_demand[team]["p" if pitcher else "b"] += 1
	_log("", "foreign_candidate", id, p["name"], "", "", "%s（%s）が外国人市場に（史実は%s）" % [
		p["name"], "投手" if pitcher else "野手", GameData.short_name(team)])


## 架空の外国人（史実の無い年）を CPU球団が獲る人数：来季も残る外国人が目安（next.foreign_target。史実の1球団の平均）に
## 足りない分。投手・野手は史実の新外国人の投手の割合（next.foreign_pitcher_share）で分ける
func _fictional_demand(next: Dictionary, retire: Array[String], next_year: int, debut: Dictionary, available: int) -> void:
	var target := float(next.get("foreign_target", 7.0))
	var share := float(next.get("foreign_pitcher_share", 0.55))
	var leaving := {}
	for id in retire:
		leaving[id] = true
	var staying := {}
	for id: String in team_of:
		if leaving.has(id):
			continue
		var p := GameData.player(id)
		if p.is_empty() or not RosterRules.is_foreign(p, next_year, debut.get(id)):
			continue
		var team: String = team_of[id]
		if not staying.has(team):
			staying[team] = {"p": 0, "b": 0}
		staying[team]["p" if p.get("is_pitcher", false) else "b"] += 1
	var total := 0
	for team: String in GameData.teams():
		if team == user_team:
			continue
		var st: Dictionary = staying.get(team, {"p": 0, "b": 0})
		var need := maxi(0, roundi(target) - int(st["p"]) - int(st["b"]))
		if need == 0:
			continue
		var want_p := clampi(roundi(target * share) - int(st["p"]), 0, need)
		var d: Dictionary = cpu_demand.get(team, {"p": 0, "b": 0})
		d["p"] += want_p
		d["b"] += need - want_p
		cpu_demand[team] = d
		total += need
	if total > available:
		push_warning("架空の外国人の候補（%d人）より CPU球団の欲しい人数（%d人）が多い" % [available, total])


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


## 契約更改：今季のゲーム内成績（season。無ければ能力値だけ）で全選手の来季の年俸を査定してすぐ反映する。
## 自球団の選手は contracts（ContractRenewal）に提示額として持ち、締めるまで画面で調整できる。
## 複数年契約中の選手・このオフに加わった選手（メジャーからの復帰・FAの残留など）は据え置き
func renew_contracts(season_year: int, season: Season) -> ContractRenewal:
	var next_year := season_year + 1
	var retiring: Array = _plan.get("retire", [])
	var debut := GameData.load_debut_years(season_year)
	contracts = ContractRenewal.new(season_year, user_team)
	var ids: Array = team_of.keys()
	ids.sort()
	for id: String in ids:
		if id in retiring or not salary.has(id):
			continue
		var mine: bool = team_of[id] == user_team
		var prev := int(salary[id])
		var history: Array = salary_history.get(id, [])
		var fixed := ""
		if int(contract_until.get(id, 0)) >= next_year:
			fixed = "%d年まで複数年契約" % int(contract_until[id])
		elif not history.is_empty() and history[-1]["year"] == next_year:
			# このオフに加わった選手（メジャーからの復帰など）は加入時の額のまま
			fixed = "今オフに契約済み"
			prev = int(history[-2]["salary"]) if history.size() >= 2 else prev
		if not fixed.is_empty():
			if mine:
				contracts.add_row(id, prev, int(salary[id]), fixed)
			continue
		var p := GameData.player(id)
		if p.is_empty():
			continue
		var stats: Dictionary = {}
		if season != null:
			stats = (season.pitching if p.get("is_pitcher", false) else season.batting).get(id, {})
		var foreign := RosterRules.is_foreign(p, next_year, debut.get(id))
		var years := years_in_npb(id, next_year)
		var amount := Salary.renew(prev, p, stats, years, foreign, next_year)
		_set_salary(id, amount, next_year)
		if mine:
			contracts.add_row(id, prev, amount, "")
	contracts.sort_rows()
	return contracts


## 契約更改で自球団が調整した来季の年俸（ContractRenewal.set_amount から）
func set_next_salary(id: String, amount: int, next_year: int) -> void:
	_set_salary(id, amount, next_year)


## 来季の年俸総額の見込み（このオフに引退する予定の選手を除く）。予算との比較に使う
func next_payroll(team: String) -> int:
	var retiring: Array = _plan.get("retire", [])
	var total := 0
	for id: String in team_of:
		if team_of[id] == team and id not in retiring:
			total += int(salary.get(id, 0))
	return total


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


## ドラフトの段階：ドラフト以外の新加入（史実の球団へ）。ドラフトの新人は apply_draft で入る
func apply_newcomers() -> void:
	var next_year: int = _plan.get("year", year + 1)
	_plan["newcomers_done"] = true
	for id: String in _plan.get("newcomers", []):
		var p: Dictionary = _plan["entries"][id]
		var team := _current_name(p.get("hist_team", p["team"]))
		if team.is_empty() or (team_of.has(id) and not team_of[id].is_empty()):
			continue
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


## このオフにドラフトができるか（来季の能力値ファイルとドラフト会議の一覧がある）
func draft_available() -> bool:
	return not _plan.get("draft_quota", {}).is_empty()


## ドラフトの段階を始める（apply_newcomers のあと）。waiver_order：2巡目の指名順（下位から）
func open_draft(season_year: int, waiver_order: Array[String], teams: Array[String]) -> Draft:
	draft = Draft.new()
	var pool := {}
	var entries: Dictionary = _plan.get("entries", {})
	for id: String in _plan.get("draftees", []):
		pool[id] = entries[id]
	draft.setup(season_year, user_team, teams, pool, team_of, waiver_order, _rng.randi())
	var moves: Array = []
	for m: Dictionary in draft_pick_comp:
		if int(m["year"]) == season_year:
			moves.append(m)
	draft.set_pick_moves(moves)
	var counts := {}
	for id: String in team_of:
		var team: String = team_of[id]
		if not counts.has(team):
			counts[team] = {}
		var group := pos_group(GameData.player(id))
		counts[team][group] = int(counts[team].get(group, 0)) + 1
	draft.set_team_counts(counts)
	draft.user_room = draft_room(user_team)
	return draft


## 守備位置の4区分（投手・捕手・内野手・外野手）
static func pos_group(p: Dictionary) -> String:
	if p.get("is_pitcher", false):
		return "投手"
	var pos: Variant = p.get("primary_pos")
	if pos == "捕手":
		return "捕手"
	if pos in ["外野手", "左翼手", "中堅手", "右翼手"]:
		return "外野手"
	return "内野手"


## ドラフトで本指名できる人数（支配下の上限 − 今の支配下 − ドラフト以外の入る見込み）
func draft_room(team: String) -> int:
	return ROSTER_LIMIT - registered_count(team) - _incoming_other(team)


## ドラフトの結果で入団させる（指名されなかった候補は入団しない）
func apply_draft() -> void:
	if draft == null or draft.resolved:
		return
	draft.resolve_talks()
	draft.resolved = true
	_plan["draft_done"] = true
	var next_year: int = _plan.get("year", year + 1)
	var synth := draft.synthetic_players()
	for rec in draft.picks:
		var id: String = rec["id"]
		var c: Dictionary = draft.by_id[id]
		var team: String = rec["team"]
		var talk: Dictionary = draft.talks.get(id, {})
		if not talk.is_empty() and not talk["ok"]:
			# メジャー志望の説得に失敗：入団せず渡米（ゲームの NPB には出てこない）
			draft_unsigned[norm_name(c["name"])] = draft.year
			names[id] = c["name"]
			_log("", "mlb_draftee", id, c["name"], team, "", "%s：%sの説得に応じず、メジャーへ挑戦（ドラフト%s）" % [
				c["name"], GameData.short_name(team), rec["label"]])
			continue
		if int(talk.get("promise", 0)) > 0:
			posting_promise[id] = draft.year + int(talk["promise"])
		team_of[id] = team
		names[id] = c["name"]
		retired.erase(id)
		joined[id] = next_year
		drafted[id] = {"year": draft.year, "team": team, "round": rec["round"], "ikusei": rec["ikusei"],
			"label": rec["label"]}
		if synth.has(id):
			draft_synth[id] = synth[id]
		var amount := Salary.rookie({"round": rec["round"], "high_school": c["career"] == "高校生",
			"ikusei": rec["ikusei"]}, next_year)
		_set_salary(id, amount, next_year)
		var hist := "" if c["hist_team"] == team and c["hist_label"] == rec["label"] else "、史実は%s%s" % [
			GameData.short_name(c["hist_team"]), c["hist_label"]]
		_log("", "rookie", id, c["name"], "", team, "%s：%s（ドラフト%s%s）" % [c["name"],
			GameData.short_name(team), rec["label"], hist])
	for c in draft.remaining():
		draft_unsigned[norm_name(c["name"])] = draft.year
		_log("", "draft_unsigned", c["id"], c["name"], "", "", "%s：ドラフトで指名されず（史実は%s%s）" % [
			c["name"], GameData.short_name(c["hist_team"]), c["hist_label"]])


## GameData に足す選手（能力値ファイルにいない選手）：所属している・引退した仮の新人と、ドラフト中の仮の候補
## （引退した仮の新人も戦力外・引退の一覧や出来事で名前を引くので残す）
func extra_players() -> Dictionary:
	var result := {}
	for id: String in draft_synth:
		if team_of.has(id) or retired.has(id):
			result[id] = draft_synth[id]
	if draft != null and not draft.resolved:
		result.merge(draft.synthetic_players())
	return result


## 外国人市場の選手を獲得する（自球団・CPU球団とも）。獲得できなければ空でないエラー文
func sign_foreign(id: String, team: String) -> String:
	if id not in market:
		return "市場にいない選手です"
	market.erase(id)
	var info: Dictionary = market_info[id]
	team_of[id] = team
	var name: String = names.get(id, id)
	if info.has("released"):
		_set_salary(id, info["asking"], _plan.get("year", year + 1))
		_log("", "release_sign", id, name, info["released"], team, "%s：%s が獲得（%s、%sを戦力外）" % [
			name, GameData.short_name(team), Salary.text(info["asking"]), GameData.short_name(info["released"])])
		return ""
	joined[id] = _plan.get("year", year + 1)
	_set_salary(id, info["asking"], joined[id])
	if info.get("fictional", false):
		_log("", "foreign_sign", id, name, "", team, "%s：%s が獲得（%s）" % [
			name, GameData.short_name(team), Salary.text(info["asking"])])
		return ""
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
		if market_info[id]["pitcher"] != pitcher or market_info[id].has("released"):
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
	# 引き留めた選手：史実でNPBに戻って能力値ファイルにいれば、以後は普通の選手
	for id: String in kept_mlb.keys():
		if ids.has(id):
			kept_mlb.erase(id)
	for id: String in team_of.keys():
		if not ids.has(id) and not kept_mlb.has(id) and not _synth_alive(id, new_year):
			push_warning("能力値の無い選手を所属から外します: %s %s" % [id, names.get(id, "")])
			retired[id] = new_year - 1
			team_of.erase(id)
	_renew_ikusei(new_year)


# --- 戦力外 ---------------------------------------------------------------------------

## 育成選手か：ドラフトが育成指名（選手ページの「育成ドラフト」、無ければドラフト会議の一覧の育成）で、
## その年までに1軍に出ていない（debut：選手ID → 1軍初出場の年）。データに育成の区別が無いので近似
func is_ikusei(id: String, p: Dictionary, at_year: int, debut: Dictionary) -> bool:
	if p.is_empty():
		return false
	# 支配下に登録した選手（作業19）。登録した年から支配下
	if promoted.has(id) and at_year >= int(promoted[id]["year"]):
		return false
	# ゲームのドラフトで育成指名した選手は、入団1年目は史実で1軍に出ていても育成（支配下の枠を指名時の見込みどおりにする）
	if drafted.has(id) and bool(drafted[id]["ikusei"]) and at_year <= int(drafted[id]["year"]) + 1:
		return true
	var d: Variant = debut.get(id)
	if d != null and int(d) <= at_year:
		return false
	if drafted.has(id):
		return bool(drafted[id]["ikusei"])
	var text: String = p.get("draft") if p.get("draft") is String else ""
	if not text.is_empty():
		return "育成" in text
	if id.begins_with("tmp:"):
		var entry := GameData.draft_entry_for(p, int(joined.get(id, at_year)) - 1)
		return bool(entry.get("ikusei", false))
	return false


## 今の時点（オフは来季）で育成選手か
func ikusei_now(id: String) -> bool:
	return is_ikusei(id, GameData.player(id), _count_year(), _count_debut())


## 球団の育成選手（選手ID → true）
func ikusei_of(team: String) -> Dictionary:
	var at := _count_year()
	var debut := _count_debut()
	var result := {}
	for id: String in team_of:
		if team_of[id] == team and is_ikusei(id, GameData.player(id), at, debut):
			result[id] = true
	return result


## 育成選手を支配下に登録する（期限などの確認は GameState.promote_ikusei）。だめなら理由
func promote_ikusei(id: String, date: String) -> String:
	var team: String = team_of.get(id, "")
	var name: String = str(names.get(id, GameData.player(id).get("name", id)))
	if team.is_empty():
		return "%sは所属がありません" % name
	if not ikusei_now(id):
		return "%sは育成選手ではありません" % name
	# 上限は最初の戦力外の段階から（2008年の開幕は史実の編成のままで70人を超える球団がある）
	if limit_active and registered_count(team) >= ROSTER_LIMIT:
		return "支配下登録が上限（%d人）です。戦力外で枠を空けてください" % ROSTER_LIMIT
	promoted[id] = {"year": _count_year(), "date": date, "team": team}
	_log(date, "ikusei_promote", id, name, team, team, "%s：%sを育成から支配下に登録" % [GameData.short_name(team), name])
	return ""


## CPU球団が支配下に上げる育成選手（実力が支配下の下位 CPU_PROMOTE_SHARE より上の選手を、良い順に最大 count 人）
func cpu_promotion_candidates(team: String, count: int) -> Array[String]:
	var at := _count_year()
	var debut := _count_debut()
	var regular: Array[float] = []
	var cands: Array = []
	for id: String in team_of:
		if team_of[id] != team:
			continue
		var p := GameData.player(id)
		var z := float(Salary.ability(p)[0]) if not p.is_empty() else -9.0
		if is_ikusei(id, p, at, debut):
			var age := FreeAgency.age_of(p, at)
			cands.append([id, z + (CPU_PROMOTE_YOUTH if age > 0 and age <= 23 else 0.0)])
		else:
			regular.append(z)
	if cands.is_empty() or regular.is_empty():
		return []
	regular.sort()
	var bar: float = regular[int(regular.size() * CPU_PROMOTE_SHARE)]
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var result: Array[String] = []
	var room_left := ROSTER_LIMIT - registered_count(team)
	for c: Array in cands:
		if result.size() >= mini(count, room_left) or c[1] < bar:
			break
		result.append(c[0])
	return result


## 育成の契約（3年）が終わった選手（年が替わるとき。join の年から数える）。史実の育成選手と同じく
## いったん自由契約にして育成で再契約したことにする（所属・年俸は変えず、出来事に残すだけ。作業19）
func _renew_ikusei(new_year: int) -> void:
	var debut := GameData.load_debut_years(new_year)
	for id: String in team_of:
		var joined_year := _ikusei_joined_year(id)
		if joined_year <= 0 or (new_year - joined_year) % IKUSEI_CONTRACT_YEARS != 0 or new_year == joined_year:
			continue
		if not is_ikusei(id, GameData.player(id), new_year, debut):
			continue
		var name: String = str(names.get(id, GameData.player(id).get("name", id)))
		_log("", "ikusei_renew", id, name, team_of[id], team_of[id],
			"%s：%sの育成契約（%d年）が満了、育成で再契約" % [GameData.short_name(team_of[id]), name,
				IKUSEI_CONTRACT_YEARS])


## 育成選手の入団の年（ゲームのドラフト、無ければ能力値の経歴「2006年育成選手ドラフト1巡目」の翌年）。分からなければ 0
func _ikusei_joined_year(id: String) -> int:
	if drafted.has(id):
		return int(drafted[id]["year"]) + 1
	var text: Variant = GameData.player(id).get("draft")
	if text is String and "育成" in text and (text as String).length() >= 5 and (text as String)[4] == "年":
		return int((text as String).left(4)) + 1
	return 0


## 支配下の人数を数える年と1軍初出場の年（オフは来季。戦力外は来季の編成に向けて決める）
func _count_year() -> int:
	return int(_plan.get("year", year))


func _count_debut() -> Dictionary:
	return _plan["debut"] if _plan.has("debut") else GameData.load_debut_years(year)


## 球団の支配下の人数（育成選手を除く）
func registered_count(team: String) -> int:
	var at := _count_year()
	var debut := _count_debut()
	var n := 0
	for id: String in team_of:
		if team_of[id] == team and not is_ikusei(id, GameData.player(id), at, debut):
			n += 1
	return n


## 来季に入る見込みの支配下の人数：ドラフト（ドラフトが終わるまでは史実でその球団が本指名した人数）、
## ドラフト以外の新加入（支配下）と、CPU球団は外国人市場で獲る予定の残り（cpu_demand）
func incoming(team: String) -> int:
	var n := _incoming_other(team)
	if _plan.has("draft_quota") and not _plan.get("draft_done", false):
		n += int(_plan["draft_quota"].get(team, {}).get("reg", 0))
	return n


## ドラフト以外で来季に入る見込みの支配下の人数（ドラフト以外の新加入と、CPU球団の外国人市場の残り）
func _incoming_other(team: String) -> int:
	var n := 0
	if _plan.has("newcomers") and not _plan.get("newcomers_done", false):
		var at := _count_year()
		var debut: Dictionary = _plan["debut"]
		for id: String in _plan["newcomers"]:
			var p: Dictionary = _plan["entries"][id]
			if _current_name(p.get("hist_team", p["team"])) == team and not is_ikusei(id, p, at, debut):
				n += 1
	if team != user_team and cpu_demand.has(team):
		n += int(cpu_demand[team]["p"]) + int(cpu_demand[team]["b"])
	return n


## 支配下の空き（上限 − 今の支配下 − 入る見込み）
func room(team: String) -> int:
	return ROSTER_LIMIT - registered_count(team) - incoming(team)


## 残す価値（低いほど戦力外の候補）：能力（Salary.ability の実力z＋出場量）・年齢（若手は伸びしろで上乗せ、
## ベテランは減点）・年俸（高いほど残す）
func keep_score(id: String, at_year: int) -> float:
	var p := GameData.player(id)
	if p.is_empty():
		return -9.0
	var a := Salary.ability(p)
	var score: float = float(a[0]) + 0.6 * float(a[1])
	var age := FreeAgency.age_of(p, at_year)
	if age > 0:
		if age <= 22:
			score += 0.9
		elif age <= 25:
			score += 0.5
		elif age >= 33:
			score -= 0.3 + 0.15 * (age - 33)
	score += minf(0.6, 0.12 * sqrt(maxf(0.0, salary_of(id) / 1000.0)))
	return score


## 戦力外にできない理由（複数年契約中・引き留め・今オフに加わった選手）。できるなら空
## joins：recent_joins() の結果（省略すると毎回数える）
func protected_reason(id: String, season_year: int, joins: Dictionary = {}) -> String:
	if int(contract_until.get(id, 0)) >= season_year + 1:
		return "%d年まで複数年契約" % int(contract_until[id])
	if kept_mlb.has(id):
		return "メジャー移籍を引き留めた"
	if (joins if not joins.is_empty() else recent_joins(season_year)).has(id):
		return "今オフに加入"
	return ""


## season_year のオフ以降に加わった選手（FA・復帰・引き留め・外国人・戦力外からの獲得・トレード）
func recent_joins(season_year: int) -> Dictionary:
	var result := {"": true}
	for i in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		if e["year"] < season_year:
			break
		if e["kind"] in JOINED_KINDS:
			result[e["id"]] = true
	return result


## 戦力外・引退の段階を始める（apply_retirements のあと）。CPU球団の戦力外はここで決めて実行する
func open_releases(season_year: int) -> Releases:
	limit_active = true
	releases = Releases.new(season_year, user_team)
	var debut := _count_debut()
	var at := _count_year()
	for e in events(year, "retire"):
		var id: String = e["id"]
		var p := GameData.player(id)
		releases.retired_rows.append({"id": id, "name": e["name"], "team": e["from"],
			"age": FreeAgency.age_of(p, season_year), "pitcher": p.get("is_pitcher", false),
			"foreign": str(e["text"]).ends_with("退団")})
	var user := user_team
	releases.retired_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ua: bool = a["team"] == user
		var ub: bool = b["team"] == user
		if ua != ub:
			return ua
		return a["team"] < b["team"] if a["team"] != b["team"] else a["id"] < b["id"])
	# 自球団の候補
	var rel := releases
	var joins := recent_joins(season_year)
	var mine := players_of(user_team)
	for id in mine:
		rel.scores[id] = keep_score(id, season_year)
		if is_ikusei(id, GameData.player(id), at, debut):
			rel.ikusei[id] = true
		var reason := protected_reason(id, season_year, joins)
		if not reason.is_empty():
			rel.protected[id] = reason
	mine.sort_custom(func(a: String, b: String) -> bool:
		return rel.scores[a] < rel.scores[b] if rel.scores[a] != rel.scores[b] else a < b)
	rel.order = mine
	# CPU球団
	for team: String in GameData.teams():
		if team == user_team:
			continue
		for id in _cpu_cuts(team, season_year, -room(team)):
			rel.cpu_rows.append(release_player(id))
	return rel


## CPU球団が戦力外にする選手（count 人。keep_score の低い順、投手・野手の最低人数は残す）
func _cpu_cuts(team: String, season_year: int, count: int) -> Array[String]:
	var cuts: Array[String] = []
	if count <= 0:
		return cuts
	var at := _count_year()
	var debut := _count_debut()
	var candidates: Array[String] = []
	var pitchers := 0
	var fielders := 0
	var scores := {}
	var joins := recent_joins(season_year)
	for id in players_of(team):
		var p := GameData.player(id)
		if is_ikusei(id, p, at, debut):
			continue
		if p.get("is_pitcher", false):
			pitchers += 1
		else:
			fielders += 1
		if protected_reason(id, season_year, joins).is_empty():
			scores[id] = keep_score(id, season_year) + _rng.randfn(0.0, 0.15)
			candidates.append(id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		return scores[a] < scores[b] if scores[a] != scores[b] else a < b)
	for id in candidates:
		if cuts.size() >= count:
			break
		var pitcher: bool = GameData.player(id).get("is_pitcher", false)
		if pitcher and pitchers <= MIN_KEEP_PITCHERS or not pitcher and fielders <= MIN_KEEP_FIELDERS:
			continue
		if pitcher:
			pitchers -= 1
		else:
			fielders -= 1
		cuts.append(id)
	return cuts


## 選手を戦力外にする。来季の能力値ファイルにいれば（同じ選手IDで）市場へ、いなければ引退。{id, name, team, market}
func release_player(id: String) -> Dictionary:
	var from: String = team_of.get(id, "")
	team_of.erase(id)
	var name: String = names.get(id, id)
	var entries: Dictionary = _plan.get("entries", {})
	var to_market := entries.has(id)
	released[id] = {"year": year, "from": from, "market": to_market}
	if to_market:
		var next_p: Dictionary = entries[id]
		var post: Dictionary = _plan.get("post", {}).get(id, {})
		var basis := post if not post.is_empty() else next_p
		var a := Salary.ability(basis)
		var noise := _rng.randfn(0.0, MARKET_NOISE)
		var next_year := _count_year()
		var asking := Salary.round_amount(maxf(Salary.minimum(next_year),
				Salary.initial(next_p, years_in_npb(id, next_year), false, next_year) * RELEASE_ASKING_RATE))
		market.append(id)
		market_info[id] = {"hist_team": next_p.get("hist_team", next_p["team"]), "released": from,
			"pitcher": next_p.get("is_pitcher", false), "value": a[0] + 0.5 * a[1] + noise, "asking": asking}
	else:
		retired[id] = year
	_log("", "release", id, name, from, "", "%s（%s）戦力外%s" % [name, GameData.short_name(from),
		" → 市場へ" if to_market else " → 引退"])
	return {"id": id, "name": name, "team": from, "market": to_market}


## 市場の戦力外の選手（獲得されていない）
func released_in_market() -> Array[String]:
	var result: Array[String] = []
	for id in market:
		if market_info[id].has("released"):
			result.append(id)
	return result


## CPU球団が市場の戦力外の選手を獲る（支配下に空きがある球団が、評価の高い順に1巡で最大
## RELEASE_SIGN_PER_ROUND 人。元の球団は獲らない）。rounds 巡くり返す
func cpu_release_round(rounds: int = 1) -> void:
	if not limit_active:
		return
	var order: Array[String] = []
	for team: String in GameData.teams():
		if team != user_team:
			order.append(team)
	for r in rounds:
		for i in range(order.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp := order[i]
			order[i] = order[j]
			order[j] = tmp
		for team in order:
			for k in RELEASE_SIGN_PER_ROUND:
				if room(team) <= 0:
					break
				var best := ""
				var best_value := RELEASE_SIGN_MIN
				for id in released_in_market():
					var info: Dictionary = market_info[id]
					if info["released"] == team or float(info["value"]) < best_value:
						continue
					best_value = info["value"]
					best = id
				if best.is_empty():
					break
				sign_foreign(best, team)


## 開幕：支配下の上限を超えている CPU球団（年明けの史実のトレードの人数差など）は、超えた分を戦力外にする（引退扱い）
func trim_to_limit() -> void:
	if not limit_active:
		return
	for team: String in GameData.teams():
		if team == user_team:
			continue
		for id in _cpu_cuts(team, year - 1, registered_count(team) - ROSTER_LIMIT):
			team_of.erase(id)
			retired[id] = year - 1
			released[id] = {"year": year - 1, "from": team, "market": false}
			_log("", "release_trim", id, names.get(id, id), team, "", "%s（%s）支配下の上限で戦力外 → 引退" % [
				names.get(id, id), GameData.short_name(team)])


func _rename(old: String, new_id: String) -> void:
	for dict: Dictionary in [team_of, salary, salary_history, joined, names, drafted]:
		if dict.has(old):
			dict[new_id] = dict[old]
			dict.erase(old)
	draft_synth.erase(old)
	_log("", "rename", new_id, names.get(new_id, ""), old, new_id, "%s：仮ID %s → %s" % [
		names.get(new_id, ""), old, new_id])


## 開幕：外国人市場を閉じる（残った選手は来日しない）
func close_market() -> void:
	for id in market:
		if market_info[id].has("released"):
			retired[id] = year - 1
			_log("", "release_unsigned", id, names.get(id, id), market_info[id]["released"], "",
					"%s：どの球団とも契約せず引退（%sを戦力外）" % [names.get(id, id),
						GameData.short_name(market_info[id]["released"])])
			continue
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
	var entry: Dictionary = GameData.draft_entry_for(p, draft_year)
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
	var result := s.replace(" ", "").replace("　", "").replace("・", "").replace("※", "")
	for pair: Array in [["攝", "摂"], ["靍", "鶴"], ["﨑", "崎"], ["髙", "高"], ["濵", "浜"], ["邊", "辺"], ["邉", "辺"], ["德", "徳"],
			["瀨", "瀬"], ["齋", "斎"], ["齊", "斉"], ["櫻", "桜"], ["澤", "沢"], ["眞", "真"]]:
		result = result.replace(pair[0], pair[1])
	return result


# --- セーブ／ロード ----------------------------------------------------------------------

## _plan のうち能力値ファイルから作り直せるもの（entries・post・debut）は保存しない（restore_plan で読み直す）
const PLAN_RELOADED := ["entries", "post", "debut"]


## 所属・年俸・推移・出来事・市場・引退などと、このオフの FA・契約更改・戦力外・ドラフトの途中経過
func to_save() -> Dictionary:
	var plan := {}
	for key: String in _plan:
		if key not in PLAN_RELOADED:
			plan[key] = _plan[key]
	return {
		"year": year, "user_team": user_team, "team_of": team_of, "salary": salary,
		"salary_history": salary_history, "joined": joined, "names": names, "retired": retired,
		"in_mlb": in_mlb, "posting_promise": posting_promise, "market": market, "market_info": market_info, "cpu_demand": cpu_demand,
		"contract_until": contract_until, "fa_year": fa_year, "kept_mlb": kept_mlb, "released": released,
		"drafted": drafted, "promoted": promoted, "draft_synth": draft_synth, "draft_unsigned": draft_unsigned,
		"limit_active": limit_active, "log": log, "trade_index": _trade_index, "plan": plan,
		"trade_refused": trade_refused, "draft_pick_comp": draft_pick_comp,
		"compensation": compensation.to_save() if compensation != null else null,
		"rng": SaveUtil.rng_state(_rng),
		"fa": fa.to_save() if fa != null else null,
		"contracts": contracts.to_save() if contracts != null else null,
		"releases": releases.to_save() if releases != null else null,
		"draft": draft.to_save() if draft != null else null,
	}


## to_save() の中身を戻す（d は SaveUtil.ints() で整数を戻したもの）。オフの途中なら続けて restore_plan() を呼ぶ
func from_save(d: Dictionary) -> void:
	year = int(d["year"])
	user_team = str(d["user_team"])
	team_of = d.get("team_of", {})
	salary = d.get("salary", {})
	salary_history = d.get("salary_history", {})
	joined = d.get("joined", {})
	names = d.get("names", {})
	retired = d.get("retired", {})
	in_mlb = d.get("in_mlb", {})
	posting_promise = d.get("posting_promise", {})
	market.assign(d.get("market", []))
	market_info = d.get("market_info", {})
	cpu_demand = d.get("cpu_demand", {})
	contract_until = d.get("contract_until", {})
	fa_year = d.get("fa_year", {})
	kept_mlb = d.get("kept_mlb", {})
	released = d.get("released", {})
	drafted = d.get("drafted", {})
	promoted = d.get("promoted", {})
	draft_synth = d.get("draft_synth", {})
	draft_unsigned = d.get("draft_unsigned", {})
	limit_active = bool(d.get("limit_active", false))
	log.assign(d.get("log", []))
	_trade_index = int(d.get("trade_index", 0))
	trade_refused = d.get("trade_refused", {})
	draft_pick_comp = d.get("draft_pick_comp", [])
	compensation = FaCompensation.from_save(d["compensation"]) if d.get("compensation") is Dictionary else null
	_plan = d.get("plan", {})
	SaveUtil.set_rng_state(_rng, d.get("rng", ""))
	fa = FreeAgency.from_save(d["fa"], self) if d.get("fa") is Dictionary else null
	contracts = ContractRenewal.from_save(d["contracts"]) if d.get("contracts") is Dictionary else null
	releases = Releases.from_save(d["releases"]) if d.get("releases") is Dictionary else null
	draft = Draft.from_save(d["draft"]) if d.get("draft") is Dictionary else null


## 来季の準備（_plan）の能力値ファイルの部分を読み直す（FA・トレード・ポスティング〜春季キャンプのロード時）
func restore_plan() -> void:
	if not _plan.has("year"):
		return
	var next_year := int(_plan["year"])
	_plan["year"] = next_year
	var entries := {}
	for p: Dictionary in GameData.peek_ratings(next_year, "pre").get("players", []):
		entries[p["id"]] = p
	var post := {}
	for p: Dictionary in GameData.peek_ratings(next_year, "post").get("players", []):
		post[p["id"]] = p
	_plan["entries"] = entries
	_plan["post"] = post
	_plan["debut"] = GameData.load_debut_years(next_year)
