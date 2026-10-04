class_name FreeAgency
extends RefCounted
## 1オフ分の FA・ポスティング（オフの「FA・トレード・ポスティング」の段階）。docs/SPEC.md「決定事項：FA・ポスティング」。
##
## - 国内FA：資格（在籍年数 DOMESTIC_FA_YEARS 年。1軍登録日数のデータが無いので年数で近似。前回の行使から
##   REFA_YEARS 年）のある日本人選手（外国人枠の選手を除く）が、能力・出場量・年齢から確率で宣言する
##   （史実と違う選手が宣言してもよい）。宣言した選手に CPU 球団（戦力の必要度・能力で）と自球団が
##   年俸・年数を提示し、締め切りで条件の良い球団へ移る（元の球団は少し有利。入札が無ければ宣言残留）。
##   自球団の選手への提示は「引き留め」
## - メジャー移籍（data/mlb_moves.json）：史実どおり出ていく（LeagueRoster.depart_mlb）。自球団の選手は
##   1回だけ引き留めを試せる。成功率は提示額に応じて MLB_KEEP_MIN〜MLB_KEEP_MAX（大きく出してもまれ）。
##   成功したら来季からはメジャーにいた年の能力値（GameData.mlb_player）、無ければ直前のNPBの能力値を使う
##
## 年俸は来季の額として決まり、契約年数のあいだは契約更改で変わらない（LeagueRoster.contract_until）。

const DOMESTIC_FA_YEARS := 8
const OVERSEAS_FA_YEARS := 9
const REFA_YEARS := 4
## 宣言の確率（ロジット）：基準＋実力z・出場量・働き盛り（PRIME_AGE）・高齢の減点
const DECLARE_BASE := -4.6
const DECLARE_Z := 1.6
const DECLARE_PLAYING := 2.0
const DECLARE_PRIME := 0.5
const DECLARE_OLD := 0.45
const PRIME_AGE := [27, 33]
const OLD_AGE := 34
## 希望額：市場価値（Salary.initial）のこの倍率と今の年俸の大きいほう
const ASKING_RATE := 1.1
## 提示額の範囲（希望額に対する倍率）。上限は BID_CAP（10億円）。自球団はさらに予算の残りまで（bid_range）
const BID_MIN_RATE := 0.7
const BID_MAX_RATE := 2.0
const BID_CAP := 100000
const YEARS_MAX := 5
## 選手が球団を選ぶ点数：年俸 ×（1＋YEAR_BONUS×(年数−1)）×（元の球団なら HOME_BONUS）×（1＋相性 0〜CHOICE_NOISE）
const YEAR_BONUS := 0.08
const HOME_BONUS := 1.15
const CHOICE_NOISE := 0.1
## CPU球団の入札：同じ種類（先発・救援・野手）で何人目に入るか（枠の数）で必要度を出す
const SLOTS := {"sp": 6, "rp": 7, "b": 9}
const CPU_BIDDERS_MAX := 4
## メジャー移籍の引き留めの成功率（希望額で MIN、希望額の2倍以上で MAX。年数1年ごとに +MLB_KEEP_YEAR）
const MLB_KEEP_MIN := 0.05
const MLB_KEEP_MAX := 0.20
const MLB_KEEP_YEAR := 0.01

var year: int                          ## このオフのシーズンの年
var declared: Array[String] = []       ## FA宣言した選手
var info := {}                         ## 選手ID → {from, asking, age, kind, salary}
var cpu_bids := {}                     ## 選手ID → [{team, amount, years}]（締め切りまで画面には出さない）
var user_bids := {}                    ## 選手ID → {amount, years}（自球団の提示。自球団の選手なら引き留め）
var mlb: Array[String] = []            ## このオフにメジャーへ移籍する選手
var mlb_info := {}                     ## 選手ID → {from, route, asking, status: leave/kept/failed, chance, amount, years}
var results: Array[Dictionary] = []    ## 締め切りの結果 {id, from, to, amount, years, bidders, user_bid}
var resolved := false
## テスト用：0以上なら乱数の代わりにこの値で判定する（引き留め・宣言）
var force_roll := -1.0

var _rng := RandomNumberGenerator.new()
## LeagueRoster（league.fa から参照し返すので循環しないよう弱参照）
var _league_ref: WeakRef = null


## FA宣言とメジャー移籍の一覧を作る。leaving: LeagueRoster.depart_mlb() の戻り値 [{id, from, route}]
func open(league: LeagueRoster, season_year: int, leaving: Array[Dictionary], seed_value: int) -> void:
	year = season_year
	_league_ref = weakref(league)
	_rng.seed = seed_value
	var retiring: Array = league.plan_retirements()
	var debut := GameData.load_debut_years(season_year)
	var ids: Array = league.team_of.keys()
	ids.sort()
	for id: String in ids:
		if id in retiring or not eligible(league, id, debut):
			continue
		if _rng.randf() < declare_chance(league, id):
			declare(league, id)
	for mv in leaving:
		var id: String = mv["id"]
		mlb.append(id)
		mlb_info[id] = {"from": mv["from"], "route": mv["route"], "asking": asking(league, id),
			"status": "leave", "chance": 0.0, "amount": 0, "years": 0}


## 国内FAの資格：在籍年数・前回の行使からの年数・複数年契約中でない・外国人枠でない
func eligible(league: LeagueRoster, id: String, debut: Dictionary = {}) -> bool:
	if id.begins_with("tmp:") or league.years_in_npb(id, year) < DOMESTIC_FA_YEARS:
		return false
	if league.fa_year.has(id) and year - int(league.fa_year[id]) < REFA_YEARS:
		return false
	if int(league.contract_until.get(id, 0)) > year:
		return false
	var p := GameData.player(id)
	return not p.is_empty() and not RosterRules.is_foreign(p, year, debut.get(id))


## 宣言する確率（能力・出場量・年齢）
func declare_chance(league: LeagueRoster, id: String) -> float:
	var p := GameData.player(id)
	var a := Salary.ability(p)
	var age := age_of(p, year)
	var logit := DECLARE_BASE + DECLARE_Z * float(a[0]) + DECLARE_PLAYING * float(a[1])
	if age >= PRIME_AGE[0] and age <= PRIME_AGE[1]:
		logit += DECLARE_PRIME
	logit -= DECLARE_OLD * maxi(0, age - OLD_AGE)
	# 年俸が実力に見合っていない（安い）ほど宣言しやすい
	if league.salary_of(id) < asking(league, id) / ASKING_RATE * 0.8:
		logit += 0.3
	return 1.0 / (1.0 + exp(-logit))


## FA宣言させる（テストでも使う）。CPU球団の入札もここで決める（締め切りまで非公開）
func declare(league: LeagueRoster, id: String) -> void:
	if id in declared or not league.team_of.has(id):
		return
	var p := GameData.player(id)
	declared.append(id)
	info[id] = {"from": league.team_of[id], "asking": asking(league, id), "age": age_of(p, year),
		"kind": kind_of(p), "salary": league.salary_of(id)}
	cpu_bids[id] = _cpu_bids(league, id)
	league.log_event("fa_declare", id, league.team_of[id], "", "%s（%s）がFA宣言" % [
		league.names.get(id, id), GameData.short_name(league.team_of[id])])


## 希望額（来季の年俸の目安）：市場価値×ASKING_RATE と今の年俸の大きいほう
func asking(league: LeagueRoster, id: String) -> int:
	var p := GameData.player(id)
	var market := Salary.initial(p, league.years_in_npb(id, year + 1), false, year + 1) if not p.is_empty() else 0
	return Salary.round_amount(maxf(league.salary_of(id), market * ASKING_RATE))


## 提示できる年俸の範囲 [下限, 上限]（CPU球団の入札の範囲。予算は考えない）
func base_range(id: String) -> Array[int]:
	var base: int = info[id]["asking"] if info.has(id) else mlb_info[id]["asking"]
	var low := maxi(Salary.minimum(year + 1), Salary.round_amount(base * BID_MIN_RATE))
	if mlb_info.has(id):
		low = base
	var high := Salary.round_amount(minf(BID_CAP, base * BID_MAX_RATE))
	return [low, maxi(low, high)]


## 自球団が提示できる年俸の範囲 [下限, 上限]。上限は base_range の上限と予算の残り（budget_room）の小さいほう。
## 予算の残りが下限より少なくても下限の額は提示できる（予算オーバーは画面で注意するだけ）
func bid_range(id: String) -> Array[int]:
	var r := base_range(id)
	if _league() == null:
		return r
	var room := budget_room(id)
	return [r[0], clampi(Salary.round_amount(room), r[0], r[1])]


## 自球団の予算の残り（万円）：予算上限 − 来季の年俸総額の見込み − ほかの選手への提示の上積み。
## id が自球団の選手なら、その選手の今の年俸は総額に入っているので足し戻す
func budget_room(id: String = "") -> int:
	var league := _league()
	if league == null:
		return 0
	var user := league.user_team
	var room := ContractRenewal.budget(user) - league.next_payroll(user)
	for other: String in user_bids:
		if other == id:
			continue
		var add: int = user_bids[other]["amount"]
		if info.has(other) and info[other]["from"] == user:
			add -= league.salary_of(other)
		room -= add
	if not id.is_empty() and league.team_of.get(id, "") == user:
		room += league.salary_of(id)
	return room


func _league() -> LeagueRoster:
	return _league_ref.get_ref() as LeagueRoster if _league_ref != null else null


## 自球団の提示（FA宣言した選手。自球団の選手なら引き留め）。だめなら理由の文
func offer(id: String, amount: int, years: int) -> String:
	if resolved:
		return "FAの交渉は締め切りました"
	if id not in declared:
		return "FA宣言した選手ではありません"
	var r := bid_range(id)
	user_bids[id] = {"amount": clampi(amount, r[0], r[1]), "years": clampi(years, 1, YEARS_MAX)}
	return ""


func cancel_offer(id: String) -> void:
	if not resolved:
		user_bids.erase(id)


## 自球団の提示が通りそうか（★1〜5）。CPU球団の最高の条件と比べる（最後は相性で少し変わる）
func stars(league: LeagueRoster, id: String, amount: int, years: int) -> int:
	var mine := _score(id, league.user_team, amount, years)
	var best := 0.0
	for b: Dictionary in cpu_bids.get(id, []):
		best = maxf(best, _score(id, b["team"], b["amount"], b["years"]) * (1.0 + CHOICE_NOISE * 0.5))
	if best <= 0.0:
		return 5
	var ratio := mine / best
	for i in 4:
		if ratio >= [1.1, 1.0, 0.92, 0.82][i]:
			return 5 - i
	return 1


## 獲得に動いている CPU 球団の数
func cpu_bidder_count(id: String) -> int:
	return cpu_bids.get(id, []).size()


## メジャー移籍の引き留めの成功率
func keep_chance(id: String, amount: int, years: int) -> float:
	var base: float = maxf(1.0, mlb_info[id]["asking"])
	var t := clampf(amount / base - 1.0, 0.0, 1.0)
	var c := MLB_KEEP_MIN + (MLB_KEEP_MAX - MLB_KEEP_MIN) * t + MLB_KEEP_YEAR * (clampi(years, 1, YEARS_MAX) - 1)
	return minf(c, MLB_KEEP_MAX)


## メジャー移籍する自球団の選手を引き留める（1人1回）。{ok: bool, chance, text}
func keep_mlb(league: LeagueRoster, id: String, amount: int, years: int) -> Dictionary:
	if id not in mlb:
		return {"ok": false, "chance": 0.0, "text": "メジャーへ移籍する選手ではありません"}
	var m: Dictionary = mlb_info[id]
	if m["from"] != league.user_team:
		return {"ok": false, "chance": 0.0, "text": "他球団の選手は引き留められません"}
	if m["status"] != "leave":
		return {"ok": false, "chance": m["chance"], "text": "引き留めの交渉はもう終わっています"}
	var r := bid_range(id)
	amount = clampi(amount, r[0], r[1])
	years = clampi(years, 1, YEARS_MAX)
	var chance := keep_chance(id, amount, years)
	var roll := force_roll if force_roll >= 0.0 else _rng.randf()
	var ok := roll < chance
	m["chance"] = chance
	m["amount"] = amount
	m["years"] = years
	m["status"] = "kept" if ok else "failed"
	var name: String = league.names.get(id, id)
	if ok:
		league.keep_from_mlb(id, m["from"], amount, years, year + 1)
		return {"ok": true, "chance": chance, "text": "%sの引き留めに成功！（%s・%d年）" % [
			name, Salary.text(amount), years]}
	league.log_event("mlb_keep_failed", id, m["from"], "", "%s：%sの引き留めは失敗（メジャーへ）" % [
		name, GameData.short_name(m["from"])])
	return {"ok": false, "chance": chance, "text": "%sの引き留めは失敗しました。メジャーへ移籍します。" % name}


## 締め切り：宣言した選手の移籍先を決める（条件の良い球団。入札が無ければ宣言残留）
func resolve(league: LeagueRoster) -> void:
	if resolved:
		return
	resolved = true
	for id in declared:
		if not league.team_of.has(id):
			continue
		var from: String = info[id]["from"]
		var bids: Array = cpu_bids.get(id, []).duplicate()
		if user_bids.has(id):
			bids.append({"team": league.user_team, "amount": user_bids[id]["amount"],
				"years": user_bids[id]["years"]})
		var best: Dictionary = {}
		var best_score := -1.0
		for b: Dictionary in bids:
			var s := _score(id, b["team"], b["amount"], b["years"]) * (1.0 + CHOICE_NOISE * _rng.randf())
			if s > best_score:
				best_score = s
				best = b
		if best.is_empty():
			best = {"team": from, "amount": league.salary_of(id), "years": 1}
		league.sign_fa(id, from, best["team"], best["amount"], best["years"], year + 1, bids.size())
		results.append({"id": id, "from": from, "to": best["team"], "amount": best["amount"],
			"years": best["years"], "bidders": bids.size(), "user_bid": user_bids.has(id)})


func _score(id: String, team: String, amount: int, years: int) -> float:
	var s := float(amount) * (1.0 + YEAR_BONUS * (years - 1))
	return s * (HOME_BONUS if team == info.get(id, {}).get("from", "") else 1.0)


## CPU球団の入札：戦力の必要度（同じ種類で何人目に入るか）・能力・年俸で決める
func _cpu_bids(league: LeagueRoster, id: String) -> Array[Dictionary]:
	var p := GameData.player(id)
	var z := float(Salary.ability(p)[0])
	var kind := kind_of(p)
	var from: String = league.team_of[id]
	var base: int = info[id]["asking"]
	var r := base_range(id)
	var teams := {}
	for other: String in league.team_of:
		teams[league.team_of[other]] = true
	var names: Array = teams.keys()
	names.sort()
	var bids: Array[Dictionary] = []
	for team: String in names:
		if team == league.user_team:
			continue
		var need := need_of(league, team, kind, z, id)
		var chance := clampf(need * (0.3 + 0.25 * z), 0.02, 0.8)
		if team == from:
			chance = clampf(0.45 + 0.3 * need + 0.15 * z, 0.2, 0.95)
		if _rng.randf() >= chance:
			continue
		var rate := _rng.randf_range(0.85, 1.15) * (0.9 + 0.3 * need)
		var amount := clampi(Salary.round_amount(base * rate), r[0], r[1])
		# 予算上限を超える入札はしない（元の球団はその選手の今の年俸の分を差し引いて考える）
		var payroll := league.next_payroll(team) - (league.salary_of(id) if team == from else 0)
		if payroll + amount > ContractRenewal.budget(team):
			continue
		bids.append({"team": team, "amount": amount, "years": _cpu_years(int(info[id]["age"])),
			"need": need})
	if bids.size() > CPU_BIDDERS_MAX:
		bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["team"] == from or (b["team"] != from and a["need"] > b["need"]))
		bids.resize(CPU_BIDDERS_MAX)
	return bids


## 必要度（0〜1）：その球団の同じ種類の選手のうち、この選手より実力の高い選手が何人いるか
func need_of(league: LeagueRoster, team: String, kind: String, z: float, exclude: String) -> float:
	var better := 0
	for other: String in league.team_of:
		if other == exclude or league.team_of[other] != team:
			continue
		var q := GameData.player(other)
		if q.is_empty() or kind_of(q) != kind:
			continue
		if float(Salary.ability(q)[0]) >= z:
			better += 1
	return clampf(1.0 - float(better) / SLOTS[kind], 0.0, 1.0)


func _cpu_years(age: int) -> int:
	if age <= 29:
		return _rng.randi_range(2, 4)
	if age <= 32:
		return _rng.randi_range(2, 3)
	if age <= 34:
		return _rng.randi_range(1, 2)
	return 1


## 選手の種類：先発 sp・救援 rp・野手 b
static func kind_of(p: Dictionary) -> String:
	var pitching: Variant = p.get("pitching")
	if p.get("is_pitcher", false) and pitching is Dictionary:
		return "sp" if pitching.get("role") == "先発" else "rp"
	return "b"


## その年のシーズン終了時点の年齢（誕生日を考えない近似。年末の年齢）
static func age_of(p: Dictionary, at_year: int) -> int:
	var birth: Variant = p.get("birth")
	if birth is String and birth.length() >= 4 and birth.substr(0, 4).is_valid_int():
		return at_year - int(birth.substr(0, 4))
	return 0


# --- セーブ／ロード ----------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"year": year, "declared": declared, "info": info, "cpu_bids": cpu_bids, "user_bids": user_bids,
		"mlb": mlb, "mlb_info": mlb_info, "results": results, "resolved": resolved,
		"rng": SaveUtil.rng_state(_rng)}


static func from_save(d: Dictionary, league: LeagueRoster) -> FreeAgency:
	var f := FreeAgency.new()
	f.year = int(d["year"])
	f._league_ref = weakref(league)
	f.declared.assign(d.get("declared", []))
	f.info = d.get("info", {})
	f.cpu_bids = d.get("cpu_bids", {})
	f.user_bids = d.get("user_bids", {})
	f.mlb.assign(d.get("mlb", []))
	f.mlb_info = d.get("mlb_info", {})
	f.results.assign(d.get("results", []))
	f.resolved = bool(d.get("resolved", false))
	SaveUtil.set_rng_state(f._rng, d.get("rng", ""))
	return f
