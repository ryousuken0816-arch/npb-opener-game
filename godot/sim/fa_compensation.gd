class_name FaCompensation
extends RefCounted
## FA移籍の補償（docs/AUTORUN.md 作業18）。FAを締め切ったあと（FA・トレード・ポスティングの段階）に、
## 移籍した選手の旧球団の年俸順位（旧球団の日本人選手の中で）でランクを付け、獲得した球団が旧球団に補償する。
## ルールは年ごとに切り替える（rule()）：
## - 2025年オフまで：A＝上位1〜3位、B＝4〜10位、C＝それ以外は補償なし。A・Bは旧球団が
##   「人的補償（獲得球団のプロテクト28人の外から1人）＋金銭」か「金銭のみ」を選ぶ
##   （A：年俸の50%＋人的／80%、B：40%＋人的／60%。年俸は移籍前の額）
## - 2026年オフ：上と同じで、35歳以上の選手の移籍は補償なし（2026-10-30 NPBと選手会が合意）
## - 2027年オフから：人的補償は無く、ドラフトの指名権（A＝獲得球団の2巡目、B＝3巡目）か金銭（A：年俸の100%、
##   B：80%。報道の目安 A 80〜130%・B 60〜100% の間）。A＝上位1〜3位、B＝4〜8位。35歳以上は補償なし
## プロテクトの外にできない選手（自動でプロテクト）：外国人枠の選手・育成選手・このオフにFAか人的補償で加わった選手。
## 自球団が獲得した側はプロテクトを画面で選ぶ（おまかせあり）、旧球団の側は人的補償の選手か金銭（指名権か金銭）を選ぶ。
## CPU球団どうしは自動。補償は出来事（kind: fa_comp）に残り、人的補償の選手はその場で旧球団へ移る。
## 指名権は LeagueRoster.draft_pick_comp に残り、その年のドラフト（Draft.set_pick_moves）で旧球団の指名が1つ増える。

const PROTECT := 28
const OLD_RULE_UNTIL := 2025
const AGE_RULE_FROM := 2026
const PICK_RULE_FROM := 2027
const AGE_LIMIT := 35
## CPU の旧球団が人的補償を選ぶ価値の下限（Trade.player_value、万円の目安）。下回れば金銭のみ
## （史実でも A・B ランクの多くは人的補償を選ぶので低めにする）
const CPU_TAKE_VALUE := 1000.0

var year: int
## {id, name, from（旧球団）, to（獲得球団）, rank, age, salary（移籍前）, kind（player/pick/none）, reason,
##  protect: [ID], state（protect＝自球団のプロテクト待ち / choose＝自球団の選択待ち / done）,
##  result（player/money/pick）, player（人的補償の選手）, amount（金銭）, round（指名権の巡）}
var cases: Array[Dictionary] = []
var resolved := false


## 年ごとのルール
static func rule(at_year: int) -> Dictionary:
	if at_year >= PICK_RULE_FROM:
		return {"kind": "pick", "a_max": 3, "b_max": 8, "age_limit": AGE_LIMIT,
			"pick_round": {"A": 2, "B": 3}, "money_only": {"A": 1.0, "B": 0.8}}
	return {"kind": "player", "a_max": 3, "b_max": 10, "age_limit": AGE_LIMIT if at_year >= AGE_RULE_FROM else 0,
		"with_player": {"A": 0.5, "B": 0.4}, "money_only": {"A": 0.8, "B": 0.6}}


## 旧球団の日本人選手の中での年俸の順位からランク（A・B・C）
static func rank_of(league: LeagueRoster, id: String, team: String, at_year: int, debut: Dictionary) -> String:
	var mine := league.salary_of(id)
	var higher := 0
	for other in league.players_of(team):
		if other == id or RosterRules.is_foreign(GameData.player(other), at_year, debut.get(other)):
			continue
		if league.salary_of(other) > mine:
			higher += 1
	var r := rule(at_year)
	if higher + 1 <= int(r["a_max"]):
		return "A"
	if higher + 1 <= int(r["b_max"]):
		return "B"
	return "C"


## FAの締め切りの結果から補償を決める（CPU球団どうしはここで決めてしまう）
func open(league: LeagueRoster, f: FreeAgency) -> void:
	year = f.year
	var r := rule(year)
	for res: Dictionary in f.results:
		if res["to"] == res["from"]:
			continue
		var id: String = res["id"]
		var c := {"id": id, "name": league.names.get(id, id), "from": res["from"], "to": res["to"],
			"rank": res.get("rank", "C"), "age": int(f.info.get(id, {}).get("age", 0)),
			"salary": int(f.info.get(id, {}).get("salary", 0)), "kind": r["kind"], "reason": "", "protect": [],
			"state": "done", "result": "", "player": "", "amount": 0, "round": 0}
		if c["rank"] == "C":
			c["kind"] = "none"
			c["reason"] = "Cランク"
		elif int(r["age_limit"]) > 0 and c["age"] >= int(r["age_limit"]):
			c["kind"] = "none"
			c["reason"] = "%d歳以上" % int(r["age_limit"])
		cases.append(c)
		if c["kind"] == "none":
			league.log_event("fa_comp", id, c["from"], c["to"], "%s（%s → %s）：補償なし（%s）" % [c["name"],
				GameData.short_name(c["from"]), GameData.short_name(c["to"]), c["reason"]])
			continue
		if c["kind"] == "player":
			if c["to"] == league.user_team:
				c["protect"] = auto_protect(league, c)
				c["state"] = "protect"
				continue
			c["protect"] = auto_protect(league, c)
		if c["from"] == league.user_team:
			c["state"] = "choose"
			continue
		_cpu_choose(league, c)


## 自球団が関わる補償で、まだ決めていないもの
func pending() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in cases:
		if c["state"] != "done":
			result.append(c)
	return result


## プロテクトの外にできる選手（獲得球団の支配下から、外国人枠・育成・このオフにFAか人的補償で加わった選手を除く）
func protectable(league: LeagueRoster, c: Dictionary) -> Array[String]:
	var debut := GameData.load_debut_years(year)
	var joined_fa := {}
	for other in cases:
		if other["to"] == c["to"]:
			joined_fa[other["id"]] = true
		if not str(other["player"]).is_empty():
			joined_fa[other["player"]] = true
	var result: Array[String] = []
	for id in league.players_of(c["to"]):
		var p := GameData.player(id)
		if p.is_empty() or joined_fa.has(id) or RosterRules.is_foreign(p, year + 1, debut.get(id)) \
				or league.is_ikusei(id, p, year + 1, debut):
			continue
		result.append(id)
	return result


## おまかせのプロテクト（残す価値 LeagueRoster.keep_score の高い順に28人）
func auto_protect(league: LeagueRoster, c: Dictionary) -> Array[String]:
	var ids := protectable(league, c)
	var score := {}
	for id in ids:
		score[id] = league.keep_score(id, year + 1)
	ids.sort_custom(func(a: String, b: String) -> bool: return score[a] > score[b])
	return ids.slice(0, PROTECT)


## プロテクトの外の選手（人的補償で選べる選手）
func unprotected(league: LeagueRoster, c: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in protectable(league, c):
		if id not in c["protect"]:
			result.append(id)
	return result


## 金銭の額（万円）。with_player：人的補償といっしょのとき
func money_of(c: Dictionary, with_player: bool) -> int:
	var r := rule(year)
	var rate: float = (r["with_player"] if with_player else r["money_only"])[c["rank"]]
	return roundi(c["salary"] * rate / 10.0) * 10


## 自球団のプロテクトを決める（28人まで）。だめなら理由の文
func set_protect(league: LeagueRoster, c: Dictionary, ids: Array) -> String:
	if c["state"] != "protect":
		return "プロテクトはもう決まっています"
	if ids.size() > PROTECT:
		return "プロテクトは%d人までです" % PROTECT
	var allowed := protectable(league, c)
	for id: String in ids:
		if id not in allowed:
			return "%sはプロテクトの対象ではありません（自動でプロテクト）" % league.names.get(id, id)
	c["protect"] = ids.duplicate()
	return ""


## 自球団のプロテクトを確定する → 旧球団（CPU）が選ぶ
func confirm_protect(league: LeagueRoster, c: Dictionary) -> void:
	if c["state"] != "protect":
		return
	_cpu_choose(league, c)


## 自球団が旧球団のとき：kind は player（id を獲る）・money・pick。だめなら理由の文
func choose(league: LeagueRoster, c: Dictionary, kind: String, id: String = "") -> String:
	if c["state"] != "choose":
		return "この補償はもう決まっています"
	match kind:
		"player":
			if c["kind"] != "player":
				return "この年のルールでは人的補償はありません"
			if id not in unprotected(league, c):
				return "プロテクトの外の選手を選んでください"
			_execute(league, c, "player", id)
		"pick":
			if c["kind"] != "pick":
				return "この年のルールでは指名権の補償はありません"
			_execute(league, c, "pick")
		_:
			_execute(league, c, "money")
	return ""


## 残りをすべて決める（自球団の分はおまかせ。可変ボタンで次の段階へ進むとき）
func resolve_all(league: LeagueRoster) -> void:
	for c in cases:
		if c["state"] == "protect":
			confirm_protect(league, c)
		elif c["state"] == "choose":
			_cpu_choose(league, c)
	resolved = true


## 旧球団（CPU、またはおまかせの自球団）が選ぶ：人的補償はプロテクト外のいちばん価値の高い選手が
## CPU_TAKE_VALUE 以上なら獲る（なければ金銭のみ）。指名権のルールでは指名権
func _cpu_choose(league: LeagueRoster, c: Dictionary) -> void:
	if c["kind"] == "pick":
		_execute(league, c, "pick")
		return
	var best := ""
	var best_value := -1.0
	for id in unprotected(league, c):
		var v := Trade.player_value(GameData.player(id), year + 1, league.salary_of(id))
		if v > best_value:
			best_value = v
			best = id
	if best.is_empty() or best_value < CPU_TAKE_VALUE:
		_execute(league, c, "money")
	else:
		_execute(league, c, "player", best)


func _execute(league: LeagueRoster, c: Dictionary, kind: String, id: String = "") -> void:
	c["state"] = "done"
	c["result"] = kind
	var head := "%s（%sランク、%s → %s）の補償：" % [c["name"], c["rank"], GameData.short_name(c["from"]),
		GameData.short_name(c["to"])]
	match kind:
		"player":
			c["player"] = id
			c["amount"] = money_of(c, true)
			league.team_of[id] = c["from"]
			league.log_event("fa_comp", id, c["to"], c["from"], head + "%sが%sへ（人的補償）＋金銭%s" % [
				league.names.get(id, id), GameData.short_name(c["from"]), Salary.text(c["amount"])])
		"pick":
			c["round"] = int(rule(year)["pick_round"][c["rank"]])
			league.draft_pick_comp.append({"year": year, "round": c["round"], "from": c["to"], "to": c["from"],
				"id": c["id"]})
			league.log_event("fa_comp", c["id"], c["to"], c["from"], head + "%sの%d巡目の指名権が%sへ" % [
				GameData.short_name(c["to"]), c["round"], GameData.short_name(c["from"])])
		_:
			c["amount"] = money_of(c, false)
			league.log_event("fa_comp", c["id"], c["to"], c["from"], head + "金銭%s" % Salary.text(c["amount"]))


func to_save() -> Dictionary:
	return {"year": year, "cases": cases, "resolved": resolved}


static func from_save(d: Dictionary) -> FaCompensation:
	var comp := FaCompensation.new()
	comp.year = int(d.get("year", 0))
	comp.cases.assign(d.get("cases", []))
	comp.resolved = bool(d.get("resolved", false))
	return comp
