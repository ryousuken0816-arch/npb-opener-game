class_name TradeOffers
extends RefCounted
## トレードの打診（docs/AUTORUN.md 作業87）。CPU球団から自球団へ来る話と、2026年以降の CPU球団どうしのトレードの中身を作る。
##
## - 1軍の戦力になる選手が動く話だけ：両側に「レギュラー級（今の能力 Depth のスコアが B 以上）」か
##   「伸びしろの大きい若手（PROSPECT_AGE 歳以下で将来性が B 以上、今より PROSPECT_RISE 以上高い）」が入る。
##   控えどうし・2軍どうしの交換は作らない（ユーザー「弱い選手同士のトレードいらんから、頻度減らしてでも」）
## - 話の形（kind）：
##   contender＝優勝争いの球団がこちらの主力・ベテランを欲しがり、有望な若手を出す
##   rebuild＝下位の球団がこちらの有望な若手を欲しがり、主力を出す
##   swap＝守備位置の過不足（Trade.need_factor）が合う主力どうしの交換
## - 相手が損する案は出さない：相手の目（守備位置の需要つき）で 受け取る÷出す が RATIO_MIN〜RATIO_MAX、
##   需要を掛けない目でも NEUTRAL_MIN 以上（受けるだけで自球団が得をしないように）。足りなければこちらの控えか金銭を
##   求め、取りすぎなら相手の控えを足す（片側3人まで）
## - 時期・件数は GameState（offer_plan）。中身はここ。乱数は渡された rng だけ使う（試合の乱数を動かさない）

const USER_COUNT_WEIGHTS := [0.15, 0.35, 0.35, 0.15]  ## 自球団への打診：年に 0・1・2・3件の割合
const CPU_COUNT_WEIGHTS := [0.0, 0.55, 0.45]           ## CPU球団どうし：年に 0・1・2件の割合
const CPU_START_YEAR := 2026                            ## CPU球団どうしを作る最初の年（2025年度までは史実のトレードだけ）
## 打診の時期：シーズン中（開幕＋SEASON_FIRST_DAYS 日〜LAST_SLOT_DATE）の割合。残りはオフ（OFF_SLOTS の段階に入ったとき）
const SEASON_SHARE := 0.65
const SEASON_FIRST_DAYS := 21
const LAST_SLOT_DATE := "07-24"
const OFF_SLOTS := [["FA_TRADE", 0.6], ["CAMP", 0.4]]
## 返事の期限：届いた日を入れて OFFER_DAYS 日（7月31日まで）。オフはその段階のあいだ
const OFFER_DAYS := 5
## 良い話が作れなかった日は翌日にもう一度（この日数まで）
const RETRY_DAYS := 10
## レギュラー級（Depth のスコアで B 以上。記録室の「層の厚さ」と同じ）
const REGULAR_SCORE := 0.65
## 伸びしろの大きい若手
const PROSPECT_AGE := 24
const PROSPECT_FUTURE := 0.65
const PROSPECT_RISE := 0.45
## ①で欲しがる主力・ベテランの年齢の下限、②で出す主力の年齢の下限
const VETERAN_AGE := 26
const REBUILD_GIVE_AGE := 27
const MAX_AGE := 37
## 優勝争い（同じリーグで2位以内か首位と GB 以内）・下位（5位以下か首位と BOTTOM_GB 以上）
const CONTENDER_GB := 5.0
const BOTTOM_GB := 12.0
## 相手の目の比・需要を掛けない目の比の範囲（自球団への打診）
const RATIO_MIN := 1.0
const RATIO_MAX := 1.25
const NEUTRAL_MIN := 0.97
const NEUTRAL_MAX := 1.2
## CPU球団どうし：受ける側も自分の目で CPU_ACCEPT 以上、需要を掛けない目は CPU_NEUTRAL の範囲
const CPU_ACCEPT := 0.97
const CPU_NEUTRAL := [0.88, 1.15]
## 足す控えの人数の上限（こちらに求める控え・相手が足す控え）
const MAX_FILLER_TARGET := 1
const MAX_FILLER_PARTNER := 2
## 1つの形で試す組み合わせの数（欲しい選手・出す選手の上位）
const TOP_WANT := 5
const TOP_GIVE := 5
const KIND_NAMES := {"contender": "優勝争いの補強", "rebuild": "若手の獲得", "swap": "主力どうしの交換"}

var league: LeagueRoster
## 年齢・価値を見る年（GameState.year）
var year := 0
## 選手ID → 将来性（GameState.trade_future）
var future := Callable()
## 球団 → {rank, gb}（同じリーグの順位。無ければ優勝争い・下位の話は作らない）
var standing := {}
## 交渉できない選手（ID → 理由。FA宣言中・育成・最近加わった選手など）
var excluded := {}
var rng := RandomNumberGenerator.new()
var _info := {}


# --- 時期と件数 ---------------------------------------------------------------------------

## その年の予定（シーズンの年 season_year）。opening：開幕日 "YYYY-MM-DD"（日程が無い年は空＝オフだけ）。
## {year, slots: [{who: "user"/"cpu", at: 日付 or 段階の名前, tries}]}
static func make_plan(r: RandomNumberGenerator, season_year: int, opening: String) -> Dictionary:
	var slots: Array = []
	var first := ""
	if not opening.is_empty():
		first = Season.date_of_day(Season.day_number(opening) + SEASON_FIRST_DAYS)
	var last := "%d-%s" % [season_year, LAST_SLOT_DATE]
	for who: String in ["user", "cpu"]:
		if who == "cpu" and season_year < CPU_START_YEAR:
			continue
		var n := _pick_count(r, USER_COUNT_WEIGHTS if who == "user" else CPU_COUNT_WEIGHTS)
		for i in n:
			var at := ""
			if not first.is_empty() and first < last and r.randf() < SEASON_SHARE:
				var d0 := Season.day_number(first)
				at = Season.date_of_day(r.randi_range(d0, Season.day_number(last)))
			else:
				var x := r.randf()
				for o: Array in OFF_SLOTS:
					x -= float(o[1])
					if x < 0.0 or o == OFF_SLOTS[-1]:
						at = o[0]
						break
			slots.append({"who": who, "at": at, "tries": 0})
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["at"]) < str(b["at"]))
	return {"year": season_year, "slots": slots}


static func _pick_count(r: RandomNumberGenerator, weights: Array) -> int:
	var x := r.randf()
	for i in weights.size():
		x -= float(weights[i])
		if x < 0.0:
			return i
	return weights.size() - 1


# --- 選手の見立て -------------------------------------------------------------------------

## {id, team, age, now, future, regular, prospect, group, salary}。見られない選手は空
func info(id: String) -> Dictionary:
	if _info.has(id):
		return _info[id]
	var p := GameData.player(id)
	var e := {}
	if not p.is_empty():
		var now := Depth.now_score(p)
		var fut: float = float(future.call(id)) if future.is_valid() else now
		var age := FreeAgency.age_of(p, year)
		e = {"id": id, "team": str(league.team_of.get(id, "")), "age": age, "now": now, "future": fut,
			"regular": now >= REGULAR_SCORE,
			"prospect": age > 0 and age <= PROSPECT_AGE and fut >= PROSPECT_FUTURE and fut - now >= PROSPECT_RISE,
			"group": LeagueRoster.pos_group(p), "salary": league.salary_of(id),
			"pitcher": bool(p.get("is_pitcher", false))}
	_info[id] = e
	return e


## レギュラー級か伸びしろの大きい若手（話の中心になれる選手）
func is_key(id: String) -> bool:
	var e := info(id)
	return not e.is_empty() and (bool(e["regular"]) or bool(e["prospect"]))


## 球団の選手のうち、トレードの話に出せる選手
func tradable(team: String) -> Array[String]:
	var result: Array[String] = []
	var ik := league.ikusei_of(team)
	for id in league.players_of(team):
		if ik.has(id) or excluded.has(id):
			continue
		var e := info(id)
		if e.is_empty() or int(e["age"]) > MAX_AGE:
			continue
		result.append(id)
	return result


## 優勝争い（contender）・下位（bottom）・その他（middle）
func role(team: String) -> String:
	var s: Dictionary = standing.get(team, {})
	if s.is_empty():
		return "middle"
	if int(s["rank"]) <= 2 or float(s["gb"]) <= CONTENDER_GB:
		return "contender"
	if int(s["rank"]) >= 5 or float(s["gb"]) >= BOTTOM_GB:
		return "bottom"
	return "middle"


func value(id: String, view_team: String) -> float:
	return Trade.side_value(league, year, view_team, [id], future)


# --- 話を作る -----------------------------------------------------------------------------

## partner（話を持ちかける CPU球団）から target への話。target が CPU球団なら cpu＝true（target も自分の目で受ける）。
## 作れなければ空。{partner, target, kind, give（target が出す）, get（target が受け取る）, money（target が払う）,
##  ratio（partner の目）, neutral, target_ratio}
func build(partner: String, target: String, cpu := false) -> Dictionary:
	var mine := tradable(target)
	var theirs := tradable(partner)
	if mine.is_empty() or theirs.is_empty():
		return {}
	var kinds: Array[String] = ["swap"]
	match role(partner):
		"contender":
			kinds.append("contender")
		"bottom":
			kinds.append("rebuild")
	var found: Array[Dictionary] = []
	for kind in kinds:
		for pair: Array in _pairs(kind, partner, target, mine, theirs):
			var deal := _balance(partner, target, [pair[0]], [pair[1]], mine, theirs, cpu)
			if not deal.is_empty():
				deal["kind"] = kind
				found.append(deal)
	if found.is_empty():
		return {}
	# 釣り合いのよい話ほど選ばれやすい（需要を掛けない目で 1.05 に近いもの）
	var weights: Array[float] = []
	var total := 0.0
	for d in found:
		var w := 1.0 / (0.05 + absf(float(d["neutral"]) - 1.05))
		weights.append(w)
		total += w
	var x := rng.randf() * total
	for i in found.size():
		x -= weights[i]
		if x <= 0.0:
			return found[i]
	return found[-1]


## 話の中心の組み合わせ [target の選手, partner の選手]
func _pairs(kind: String, partner: String, target: String, mine: Array[String], theirs: Array[String]) -> Array:
	var want: Array[String] = []
	var give: Array[String] = []
	for id in mine:
		var e := info(id)
		match kind:
			"contender":
				if e["regular"] and int(e["age"]) >= VETERAN_AGE:
					want.append(id)
			"rebuild":
				if e["prospect"]:
					want.append(id)
			"swap":
				if e["regular"]:
					want.append(id)
	for id in theirs:
		var e := info(id)
		match kind:
			"contender":
				if e["prospect"]:
					give.append(id)
			"rebuild":
				if e["regular"] and int(e["age"]) >= REBUILD_GIVE_AGE:
					give.append(id)
			"swap":
				if e["regular"]:
					give.append(id)
	want = _top(want, partner, TOP_WANT)
	give = _top(give, partner, TOP_GIVE)
	var pairs: Array = []
	for w in want:
		for g in give:
			if kind == "swap":
				var gw: String = info(w)["group"]
				var gg: String = info(g)["group"]
				if gw == gg:
					continue
				# 相手は w の区分が足りず g の区分は余り気味、こちらはその逆
				if Trade.need_factor(league, partner, gw) <= Trade.need_factor(league, partner, gg) \
						or Trade.need_factor(league, target, gg) <= Trade.need_factor(league, target, gw):
					continue
			pairs.append([w, g])
	return pairs


## 相手の目の価値の高い順に n 人
func _top(ids: Array[String], view_team: String, n: int) -> Array[String]:
	var v := {}
	for id in ids:
		v[id] = value(id, view_team)
	ids.sort_custom(func(a: String, b: String) -> bool: return v[a] > v[b])
	return ids.slice(0, n)


## 比をそろえる：足りなければ target の控えか金銭を求め、取りすぎなら partner の控えを足す
func _balance(partner: String, target: String, give: Array, get_ids: Array, mine: Array[String],
		theirs: Array[String], cpu: bool) -> Dictionary:
	var money := 0
	var neutral_min: float = CPU_NEUTRAL[0] if cpu else NEUTRAL_MIN
	var neutral_max: float = CPU_NEUTRAL[1] if cpu else NEUTRAL_MAX
	for step in 5:
		var e := measure(partner, target, give, get_ids, money)
		var r: float = e["ratio"]
		var n: float = e["neutral"]
		var ok_target := not cpu or float(e["target_ratio"]) >= CPU_ACCEPT
		if r >= RATIO_MIN and r <= RATIO_MAX and n >= neutral_min and n <= neutral_max and ok_target:
			e.merge({"partner": partner, "target": target, "give": give.duplicate(), "get": get_ids.duplicate(),
				"money": money}, true)
			return e
		if r < RATIO_MIN or n < neutral_min:
			# 相手はもう少し欲しい：こちらの控え（話の中心でない選手）か金銭
			var gap := maxf(RATIO_MIN * 1.04 * float(e["loss"]) - float(e["gain"]),
				neutral_min * 1.03 * float(e["loss_n"]) - float(e["gain_n"]))
			var filler := _filler(mine, give, partner, gap) if give.size() <= MAX_FILLER_TARGET else ""
			if not filler.is_empty():
				give.append(filler)
				continue
			var add := int(ceil(gap / Trade.MONEY_STEP)) * Trade.MONEY_STEP
			if money + add <= Trade.MONEY_MAX and add > 0:
				money += add
				continue
			return {}
		if r > RATIO_MAX or n > neutral_max:
			# 相手が取りすぎ：相手の控えを足す（金銭を求めていれば先に減らす）
			var excess := minf(float(e["gain"]) - RATIO_MAX * 0.95 * float(e["loss"]),
				float(e["gain_n"]) - neutral_max * 0.95 * float(e["loss_n"]))
			if money > 0:
				money = maxi(0, money - int(ceil(excess / Trade.MONEY_STEP)) * Trade.MONEY_STEP)
				continue
			var filler := _filler(theirs, get_ids, partner, excess / 1.1) if get_ids.size() <= MAX_FILLER_PARTNER else ""
			if filler.is_empty():
				return {}
			get_ids.append(filler)
			continue
		return {}
	return {}


## 足す控え：話の中心でない選手で、相手の目の価値が target_value に近いもの（target_value の 1.5倍まで）
func _filler(pool: Array[String], used: Array, view_team: String, target_value: float) -> String:
	var best := ""
	var best_diff := INF
	for id in pool:
		if id in used or is_key(id):
			continue
		var v := value(id, view_team)
		if v > target_value * 1.5:
			continue
		var diff := absf(v - target_value)
		if diff < best_diff:
			best_diff = diff
			best = id
	return best


## 話の比：ratio＝partner の目（受け取る give＋金銭 ÷ 出す get）、neutral＝需要を掛けない目、
## target_ratio＝target の目（受け取る get ÷ 出す give＋金銭）
func measure(partner: String, target: String, give: Array, get_ids: Array, money: int) -> Dictionary:
	var gain := float(money) + Trade.side_value(league, year, partner, give, future)
	var loss := Trade.side_value(league, year, partner, get_ids, future)
	var gain_n := float(money) + Trade.side_value(league, year, "", give, future)
	var loss_n := Trade.side_value(league, year, "", get_ids, future)
	var t_gain := Trade.side_value(league, year, target, get_ids, future)
	var t_loss := float(money) + Trade.side_value(league, year, target, give, future)
	return {"ratio": gain / maxf(loss, 1.0), "neutral": gain_n / maxf(loss_n, 1.0),
		"target_ratio": t_gain / maxf(t_loss, 1.0), "gain": gain, "loss": loss, "gain_n": gain_n, "loss_n": loss_n,
		"value_give": gain_n - float(money), "value_get": loss_n}


## 支配下の上限を守れるか（CPU球団どうし。自球団は Trade.check）
func room_ok(team: String, partner: String, give: Array, get_ids: Array) -> bool:
	if not league.limit_active:
		return true
	var diff := get_ids.size() - give.size()
	return (diff <= 0 or league.room(team) >= diff) and (diff >= 0 or league.room(partner) >= -diff)


# --- 文 ---------------------------------------------------------------------------------

## 打診の説明（自球団への話）
func reason_text(deal: Dictionary) -> String:
	var partner := GameData.short_name(str(deal["partner"]))
	var give: Array = deal["give"]
	var get_ids: Array = deal["get"]
	var lead := ""
	match str(deal["kind"]):
		"contender":
			lead = "優勝争いをしている%sが、主力の%sを欲しがっています。代わりに有望な若手の%sを出すそうです。" % [
				partner, _name(give[0]), _name(get_ids[0])]
		"rebuild":
			lead = "%sが若手の%sを欲しがっています。代わりに主力の%sを出すそうです。" % [
				partner, _name(give[0]), _name(get_ids[0])]
		_:
			lead = "%sから主力どうしの交換の話です。%sは%sが手薄で、こちらは%sが手薄です。" % [
				partner, partner, info(give[0]).get("group", ""), info(get_ids[0]).get("group", "")]
	if int(deal["money"]) > 0:
		lead += "金銭%sもつけてほしいとのことです。" % Salary.text(int(deal["money"]))
	return lead


## 「A・B（＋金銭）」
func side_text(ids: Array, money := 0) -> String:
	var names: Array[String] = []
	for id: String in ids:
		names.append(_name(id))
	var text := "・".join(names)
	if money > 0:
		text += "＋金銭%s" % Salary.text(money)
	return text


func _name(id: String) -> String:
	return str(league.names.get(id, GameData.player(id).get("name", id)))
