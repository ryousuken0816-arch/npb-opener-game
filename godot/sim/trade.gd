class_name Trade
extends RefCounted
## トレード交渉（docs/AUTORUN.md 作業8、docs/SPEC.md「決定事項：トレード交渉の時期」）。
## 自球団の選手（最大3人）＋金銭 ⇔ 相手の選手（最大3人）。相手（CPU球団）は次の見立てで受けるか決める：
## - 選手の価値：能力（Salary.ability の実力 z と出場量）からの市場価値 × 年齢（若いほど高い）− 年俸の負担
## - 守備位置の需要：その球団で足りない区分（投手・捕手・内野手・外野手）の選手は高く、余っている区分は低く見る。
##   出す選手も同じ（足りない区分の選手は出したくない）
## - 受け取る価値（自球団が出す選手＋金銭）÷ 出す価値（相手の選手）が大きいほど成功しやすい（成功率は★5段階で見せる）
## 断られたら、その球団とは同じ日（オフは同じ段階）にはもう交渉できない。金銭は相手の判断にだけ効く（球団の資金の仕組みは無い）。
## 交渉できる時期の判定（7月31日まで・オフの段階）は GameState.trade_block_reason()。

const MAX_PLAYERS := 3
## 金銭（万円）の刻みと上限
const MONEY_STEP := 1000
const MONEY_MAX := 50000
## シーズン中の移籍期限（この日まで交渉できる）
const DEADLINE := "07-31"
## 能力の低い選手・出場の少ない選手も能力で見る（出場量の下限）
const MIN_PLAYING := 0.35
## 年齢の係数 [この年齢まで, 係数]
const AGE_FACTORS := [[23, 1.35], [26, 1.2], [29, 1.05], [32, 0.85], [35, 0.6], [99, 0.4]]
## 年俸の負担（価値から年俸 × この割合を引く。価値の SURPLUS_MIN 倍は残す）
const SALARY_WEIGHT := 0.5
const SURPLUS_MIN := 0.15
## 価値の下限（万円。若手・控えも0にはしない）
const VALUE_FLOOR := 300.0
## 守備位置の需要（Draft.NEED_SHARE の割合と比べた過不足）の効き方と幅
const NEED_WEIGHT := 0.6
const NEED_MIN := 0.8
const NEED_MAX := 1.3
## 受け取る価値 ÷ 出す価値 がこの範囲で成功率 0 → 1（線形）
const RATIO_ZERO := 0.85
const RATIO_SURE := 1.5
const STAR_WORDS := ["", "かなり低い", "低い", "五分五分", "高い", "かなり高い"]


## 選手の価値（万円の目安）
static func player_value(p: Dictionary, at_year: int, salary: int) -> float:
	var a := Salary.ability(p)
	var value := Salary.market_value(a[0], maxf(float(a[1]), MIN_PLAYING), a[2])
	var age := FreeAgency.age_of(p, at_year)
	if age > 0:
		for f: Array in AGE_FACTORS:
			if age <= int(f[0]):
				value *= float(f[1])
				break
	value = maxf(value - SALARY_WEIGHT * salary, value * SURPLUS_MIN)
	return maxf(value, VALUE_FLOOR)


## 球団の守備位置の区分の需要（1.0 が普通。足りないほど大きい）
static func need_factor(league: LeagueRoster, team: String, group: String) -> float:
	var ids := league.players_of(team)
	if ids.is_empty():
		return 1.0
	var have := 0
	for id in ids:
		if LeagueRoster.pos_group(GameData.player(id)) == group:
			have += 1
	var target: float = Draft.NEED_SHARE.get(group, 0.25) * ids.size()
	return clampf(1.0 + NEED_WEIGHT * (target - have) / maxf(target, 1.0), NEED_MIN, NEED_MAX)


## 相手の見立て。give：自球団が出す選手、get：相手から受け取る選手、money：自球団が払う金銭（万円）。
## {chance（0〜1）, stars（1〜5）, gain（相手が受け取る価値）, loss（相手が出す価値）}
static func evaluate(league: LeagueRoster, at_year: int, partner: String, give: Array, get_ids: Array,
		money: int) -> Dictionary:
	var gain := float(money)
	for id: String in give:
		var p := GameData.player(id)
		gain += player_value(p, at_year, league.salary_of(id)) \
			* need_factor(league, partner, LeagueRoster.pos_group(p))
	var loss := 0.0
	for id: String in get_ids:
		var p := GameData.player(id)
		loss += player_value(p, at_year, league.salary_of(id)) \
			* need_factor(league, partner, LeagueRoster.pos_group(p))
	var ratio := gain / maxf(loss, 1.0)
	var chance := clampf((ratio - RATIO_ZERO) / (RATIO_SURE - RATIO_ZERO), 0.0, 1.0)
	return {"chance": chance, "stars": stars_of(chance), "gain": gain, "loss": loss}


static func stars_of(chance: float) -> int:
	for i in 4:
		if chance >= [0.8, 0.6, 0.4, 0.2][i]:
			return 5 - i
	return 1


## 条件が正しいか。だめなら理由の文（時期の判定は GameState 側）。excluded：交渉できない選手（FA宣言中など）
static func check(league: LeagueRoster, partner: String, give: Array, get_ids: Array, money: int,
		excluded: Dictionary) -> String:
	var user := league.user_team
	if partner.is_empty() or partner == user:
		return "相手の球団を選んでください"
	if get_ids.is_empty():
		return "相手の選手を1人以上選んでください"
	if give.size() > MAX_PLAYERS or get_ids.size() > MAX_PLAYERS:
		return "選手は片側%d人までです" % MAX_PLAYERS
	if money < 0 or money > MONEY_MAX:
		return "金銭は%sまでです" % Salary.text(MONEY_MAX)
	for id: String in give:
		if league.team_of.get(id, "") != user:
			return "%sは自球団の選手ではありません" % league.names.get(id, id)
		if excluded.has(id):
			return "%sは%s" % [league.names.get(id, id), excluded[id]]
	for id: String in get_ids:
		if league.team_of.get(id, "") != partner:
			return "%sは%sの選手ではありません" % [league.names.get(id, id), GameData.short_name(partner)]
		if excluded.has(id):
			return "%sは%s" % [league.names.get(id, id), excluded[id]]
	if league.limit_active:
		var diff := get_ids.size() - give.size()
		if diff > 0 and league.room(user) < diff:
			return "支配下登録が上限（%d人）を超えます" % LeagueRoster.ROSTER_LIMIT
		if diff < 0 and league.room(partner) < -diff:
			return "%sの支配下登録が上限（%d人）を超えます" % [GameData.short_name(partner), LeagueRoster.ROSTER_LIMIT]
	return ""


## トレードを成立させる（所属を入れ替えて出来事に記録）。動いた選手 [{pid, name, from, to}]
static func execute(league: LeagueRoster, partner: String, give: Array, get_ids: Array, money: int,
		date: String) -> Array[Dictionary]:
	var user := league.user_team
	var moves: Array[Dictionary] = []
	for id: String in give:
		moves.append({"pid": id, "name": league.names.get(id, id), "from": user, "to": partner})
	for id: String in get_ids:
		moves.append({"pid": id, "name": league.names.get(id, id), "from": partner, "to": user})
	var money_text := "＋金銭%s" % Salary.text(money) if money > 0 else ""
	for mv in moves:
		league.team_of[mv["pid"]] = mv["to"]
		league.log_trade(date, mv, "%s：%s → %s（トレード%s）" % [mv["name"], GameData.short_name(mv["from"]),
			GameData.short_name(mv["to"]), money_text if mv["to"] == partner else ""])
	return moves
