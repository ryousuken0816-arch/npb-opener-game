class_name Health
extends RefCounted
## 選手の調子（好不調）と故障（作業45）。GameState が1つ持ち、シーズン中に1日ずつ進める。
##
## - 調子：絶不調〜絶好調の5段階（-2〜+2）。数日〜3週間ごとに1段階ずつ動き、普通へ戻りやすい。
##   試合では打撃（ミート・パワー・選球眼）と投球（奪三振・制球・被弾・総合）の z 値を FORM_Z ずつ上下させる（GameSim）
## - 故障：試合に出るたび（野手は1試合ごと、投手は投げた球数）と練習（試合に出ない日）に確率で起きる。年齢で上がる。
##   部位ごとの全治の日数があり、最後の REHAB_SHARE は2軍で調整（どちらの間も1軍の試合には出られない）。
##   CPU球団は GameState が自動で1軍を組み直す。自球団は1軍に残ったまま（試合では控えが代わりに出る）で、抹消を促す
## - 史実の故障のデータは無いので、発生率は NPB の離脱の規模（1球団で年に数人〜十数人）に合わせた定数
## オートロードは参照しない（年齢は age_of で受け取る）

const FORM_MIN := -2
const FORM_MAX := 2
const FORM_NAMES := {-2: "絶不調", -1: "不調", 0: "普通", 1: "好調", 2: "絶好調"}
## 名前札・一覧に出す印（矢印）
const FORM_MARKS := {-2: "⇓", -1: "↘", 0: "→", 1: "↗", 2: "⇑"}
## 印の色（絶不調＝青〜絶好調＝赤。UiTheme に依らない固定色）
const FORM_COLORS := {
	-2: Color(0.25, 0.4, 0.85), -1: Color(0.4, 0.6, 0.85), 0: Color(0.55, 0.55, 0.55),
	1: Color(0.95, 0.5, 0.2), 2: Color(0.9, 0.15, 0.15),
}
## 1段階あたりの能力（z 値）の上下。絶好調で +0.24（本塁打の確率で約1割、三振・四球で数%）
const FORM_Z := 0.12
## 調子が次に変わるまでの日数
const FORM_DAYS_MIN := 3
const FORM_DAYS_MAX := 21
## 調子が変わるとき、普通の側へ戻る・そのまま・離れる確率（普通のときは上下に半分ずつ）
const FORM_TOWARD := 0.5
const FORM_STAY := 0.2

## 野手が1試合に出るごとの故障の確率（年齢の補正前）
const P_FIELDER_GAME := 0.003
## 投手が1球投げるごとの故障の確率。1試合で FATIGUE_PITCHES を超えた分は OVERUSE 倍
const P_PITCHER_PITCH := 0.0002
const FATIGUE_PITCHES := 110
const OVERUSE := 2.5
## 試合に出なかった選手（控え・2軍）の練習中の故障（1日あたり）
const P_PRACTICE_DAY := 0.00006
## 年齢（4月1日時点）による倍率。[この年齢以下, 倍率]
const AGE_FACTOR := [[23, 0.75], [27, 0.9], [30, 1.0], [32, 1.15], [34, 1.35], [99, 1.6]]
## 全治のうち最後のこの割合（最低 REHAB_MIN 日）は2軍で調整
const REHAB_SHARE := 0.25
const REHAB_MIN := 3
## 復帰したときの調子
const RETURN_FORM := -1
## CPU球団の主力の故障をニュースにする全治の日数（長期離脱）
const LONG_DAYS := 30

## 部位（{arm} は利き腕「右」「左」）・全治の最短と最長の日数・起きやすさの重み
const PARTS_FIELDER := [
	["右太もも裏の肉離れ", 14, 42, 16], ["左太もも裏の肉離れ", 14, 42, 10], ["右足首の捻挫", 7, 28, 10],
	["腰痛", 7, 30, 14], ["左脇腹の肉離れ", 18, 45, 10], ["背中の張り", 5, 14, 14],
	["{arm}手首の骨折（死球）", 35, 75, 5], ["{arm}肩の炎症", 10, 40, 8], ["左膝の靱帯損傷", 70, 160, 3],
	["右ふくらはぎの肉離れ", 14, 35, 8],
]
const PARTS_PITCHER := [
	["{arm}肘の炎症", 14, 50, 16], ["{arm}肩の張り", 10, 35, 16], ["左脇腹の肉離れ", 18, 45, 12],
	["腰痛", 7, 30, 12], ["右太もも裏の肉離れ", 14, 40, 7], ["{arm}手指のまめ", 5, 14, 12],
	["{arm}肩の炎症", 21, 70, 10], ["{arm}肘の靱帯損傷（手術）", 300, 420, 3],
]

## 選手ID → 調子（-2〜2。無ければ普通）
var form := {}
## 選手ID → 次に調子が変わる日（通し日数）
var form_next := {}
## 選手ID → 故障 {part, start, until（この日から出られる）, rehab（この日から2軍で調整）, team, name, key（主力）}
var injuries := {}
## 今年の故障の記録（離脱が決まったときに足す）。{id, name, team, part, start, until, key, pitcher, first}
var log: Array = []
## 治ったが、まだ1軍に戻せていない CPU球団の選手（抹消から10日の再登録の決まり）。選手ID → 故障の記録
var returning := {}
## 年齢を取る（選手ID → 4月1日時点の年齢。分からなければ -1）
var age_of: Callable = Callable()

var _rng := RandomNumberGenerator.new()
var _age := {}


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value if seed_value != 0 else 45


## 新しい年（年齢の覚えを捨て、記録を空にする。故障は残す＝年をまたいで治る）
func new_year() -> void:
	_age.clear()
	log.clear()


# --- 見る ---------------------------------------------------------------------------------

func form_level(id: String) -> int:
	return int(form.get(id, 0))


static func form_name(level: int) -> String:
	return FORM_NAMES.get(level, "普通")


static func form_mark(level: int) -> String:
	return FORM_MARKS.get(level, "→")


static func form_color(level: int) -> Color:
	return FORM_COLORS.get(level, FORM_COLORS[0])


func is_injured(id: String) -> bool:
	return injuries.has(id)


## "故障" / "調整中"（2軍で調整） / ""（出られる）
func status(id: String, today: int) -> String:
	if not injuries.has(id):
		return ""
	return "調整中" if today >= int(injuries[id]["rehab"]) else "故障"


## 出られるようになるまでの日数（故障していなければ 0）
func days_left(id: String, today: int) -> int:
	if not injuries.has(id):
		return 0
	return maxi(0, int(injuries[id]["until"]) - today)


## 一覧・名前札のひとこと（例："故障 右肘の炎症（あと12日）"、"調整中（あと3日）"）。出られれば空
func injury_text(id: String, today: int) -> String:
	var st := status(id, today)
	if st.is_empty():
		return ""
	if st == "調整中":
		return "2軍で調整中（あと%d日）" % days_left(id, today)
	return "故障 %s（あと%d日）" % [injuries[id]["part"], days_left(id, today)]


## 全治の日数を記事の言い方に（"全治約3週間" など）
static func length_text(days: int) -> String:
	if days < 14:
		return "全治%d日" % days
	if days < 60:
		return "全治約%d週間" % roundi(days / 7.0)
	return "全治約%dか月" % roundi(days / 30.0)


# --- 1日の進行 -------------------------------------------------------------------------------

## 試合の前：治った選手を戻し（返す）、調子を動かし、各球団の選手に印を付ける。
## teams: 正式名 → SimTeam（Season.teams）。返す: 治った故障の一覧（{id, …} 故障の記録のまま）
func begin_day(today: int, teams: Dictionary) -> Array:
	var healed: Array = []
	for id: String in injuries.keys():
		if today >= int(injuries[id]["until"]):
			var inj: Dictionary = injuries[id]
			inj["id"] = id
			healed.append(inj)
			injuries.erase(id)
			form[id] = RETURN_FORM
			form_next[id] = today + _rng.randi_range(FORM_DAYS_MIN, FORM_DAYS_MAX)
	for team_name: String in teams:
		for p: SimPlayer in teams[team_name].players:
			_step_form(p.id, today)
	apply(teams, today)
	return healed


## 試合の後：今日の試合（Season.games_on の結果つき）に出た選手と、出なかった選手の練習で故障を判定する。
## 返す: 新しい故障の一覧（{id, part, start, until, team, name, key, pitcher}）
func after_games(today: int, games: Array, teams: Dictionary) -> Array:
	var played := {}  # 選手ID → [野手として出た, 投げた球数]
	for g: Dictionary in games:
		var res: Dictionary = g.get("result", {})
		if res.is_empty():
			continue
		for side in 2:
			for line: Dictionary in res["batting"][side]:
				var e: Array = played.get_or_add(line["id"], [false, 0])
				if line.get("pos", "") != "投手":
					e[0] = true
			for line: Dictionary in res["pitching"][side]:
				var e: Array = played.get_or_add(line["id"], [false, 0])
				e[1] += int(line.get("np", 0))
	var fresh: Array = []
	for team_name: String in teams:
		var t: SimTeam = teams[team_name]
		for p: SimPlayer in t.players:
			if injuries.has(p.id):
				continue
			var chance := P_PRACTICE_DAY
			if played.has(p.id):
				var e: Array = played[p.id]
				var pitches: int = e[1]
				chance = 0.0
				if e[0] and not p.is_pitcher:
					chance += P_FIELDER_GAME
				if pitches > 0:
					chance += P_PITCHER_PITCH * (mini(pitches, FATIGUE_PITCHES)
						+ OVERUSE * maxi(0, pitches - FATIGUE_PITCHES))
			chance *= _age_factor(p.id)
			if _rng.randf() < chance:
				fresh.append(_injure(p, t, today))
	apply(teams, today)
	return fresh


## 各球団の選手（SimPlayer）に調子・故障の印を付ける
func apply(teams: Dictionary, today: int) -> void:
	for team_name: String in teams:
		for p: SimPlayer in teams[team_name].players:
			p.form = form_level(p.id)
			p.injured = injuries.has(p.id)
			p.injury = injury_text(p.id, today)


## 故障させる（テスト・デバッグからも使う）。days を渡せば全治をその日数に
func injure(p: SimPlayer, t: SimTeam, today: int, days := -1) -> Dictionary:
	return _injure(p, t, today, days)


func _injure(p: SimPlayer, t: SimTeam, today: int, days := -1) -> Dictionary:
	var parts: Array = PARTS_PITCHER if p.is_pitcher else PARTS_FIELDER
	var total := 0
	for row: Array in parts:
		total += int(row[3])
	var pick := _rng.randi_range(1, total)
	var row: Array = parts[0]
	for r: Array in parts:
		pick -= int(r[3])
		if pick <= 0:
			row = r
			break
	var length := days
	if length <= 0:
		length = int(row[1]) + int(round((int(row[2]) - int(row[1])) * pow(_rng.randf(), 1.3)))
	var rehab := maxi(REHAB_MIN, roundi(length * REHAB_SHARE))
	var part: String = str(row[0]).replace("{arm}", "左" if p.throws == "左" else "右")
	var inj := {
		"part": part, "start": today, "until": today + length, "rehab": today + length - mini(rehab, length),
		"team": t.name, "name": p.name, "key": t.is_key_player(p), "pitcher": p.is_pitcher,
		"first": t.is_active(p),
	}
	injuries[p.id] = inj
	var entry := inj.duplicate()
	entry["id"] = p.id
	log.append(entry)
	p.injured = true
	p.injury = injury_text(p.id, today)
	return entry


func _step_form(id: String, today: int) -> void:
	if not form_next.has(id):
		# 初めて見る選手：今の調子は散らばった状態から始める
		form[id] = _initial_form()
		form_next[id] = today + _rng.randi_range(0, FORM_DAYS_MAX)
		return
	if today < int(form_next[id]):
		return
	var cur := form_level(id)
	var r := _rng.randf()
	var next := cur
	if cur == 0:
		if r < (1.0 - FORM_STAY) / 2.0:
			next = 1
		elif r < 1.0 - FORM_STAY:
			next = -1
	elif r < FORM_TOWARD:
		next = cur - signi(cur)
	elif r >= FORM_TOWARD + FORM_STAY:
		next = clampi(cur + signi(cur), FORM_MIN, FORM_MAX)
	if next == 0:
		form.erase(id)
	else:
		form[id] = next
	form_next[id] = today + _rng.randi_range(FORM_DAYS_MIN, FORM_DAYS_MAX)


func _initial_form() -> int:
	var r := _rng.randf()
	if r < 0.07:
		return -2
	if r < 0.27:
		return -1
	if r < 0.73:
		return 0
	if r < 0.93:
		return 1
	return 2


func _age_factor(id: String) -> float:
	if not _age.has(id):
		_age[id] = int(age_of.call(id)) if age_of.is_valid() else -1
	var age: int = _age[id]
	if age < 0:
		return 1.0
	for row: Array in AGE_FACTOR:
		if age <= int(row[0]):
			return float(row[1])
	return 1.0


# --- 集計（テスト・記録用） -------------------------------------------------------------------

## 今年の故障の人数と平均の全治日数（team を渡せばその球団だけ）
func summary(team_name := "") -> Dictionary:
	var n := 0
	var total_days := 0
	for e: Dictionary in log:
		if not team_name.is_empty() and e["team"] != team_name:
			continue
		n += 1
		total_days += int(e["until"]) - int(e["start"])
	return {"count": n, "avg_days": float(total_days) / n if n > 0 else 0.0}


# --- セーブ／ロード ------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"form": form, "form_next": form_next, "injuries": injuries, "log": log, "returning": returning,
		"rng": SaveUtil.rng_state(_rng)}


## d は SaveUtil.ints() で整数を戻したもの。無ければ空の状態
static func from_save(d: Variant) -> Health:
	var h := Health.new()
	if not (d is Dictionary):
		return h
	for id: String in d.get("form", {}):
		h.form[id] = int(d["form"][id])
	for id: String in d.get("form_next", {}):
		h.form_next[id] = int(d["form_next"][id])
	for id: String in d.get("injuries", {}):
		var inj: Dictionary = d["injuries"][id]
		for key in ["start", "until", "rehab"]:
			inj[key] = int(inj[key])
		inj["key"] = bool(inj.get("key", false))
		inj["first"] = bool(inj.get("first", false))
		h.injuries[id] = inj
	h.log = d.get("log", [])
	h.returning = d.get("returning", {})
	SaveUtil.set_rng_state(h._rng, d.get("rng", ""))
	return h
