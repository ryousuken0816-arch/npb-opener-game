class_name SimTeam
extends RefCounted
## 1球団の編成（スタメン・打順・先発ローテーション・ブルペン）と、投手の登板間隔の管理。
## シーズン開始時に能力値から一度だけ組み、試合ごとに先発投手と使えるリリーフを選ぶ。

const ROTATION_SIZE := 6
const BULLPEN_SIZE := 8
const BENCH_SIZE := 6
const STARTER_REST_DAYS := 5  ## 先発は中5日以上あける
const RELIEVER_MAX_PITCHES_YESTERDAY := 35

## スタメンを決める順（守備の難しい位置から埋める）
const FIELD_SLOTS := ["捕手", "遊撃手", "二塁手", "中堅手", "三塁手", "左翼手", "右翼手", "一塁手"]
## 守備位置ごとの守備力の重み（スタメン選考で打撃力に足す）
const DEFENSE_WEIGHT := {
	"捕手": 0.9, "遊撃手": 0.8, "二塁手": 0.6, "中堅手": 0.6, "三塁手": 0.4,
	"左翼手": 0.25, "右翼手": 0.3, "一塁手": 0.15,
}

var name: String
var league: String
var players: Array[SimPlayer] = []
var by_id := {}

## [SimPlayer, 守備位置] ×9（DH なし: 投手の枠は null）
var lineup_dh: Array = []
var lineup_no_dh: Array = []
## 代打要員（打撃力順）
var bench_dh: Array[SimPlayer] = []
var bench_no_dh: Array[SimPlayer] = []
var rotation: Array[SimPlayer] = []
var bullpen: Array[SimPlayer] = []  ## 抑え・セットアッパー2人・中継ぎの順
## 投手ID → 最後に登板した日（通し日数）
var last_pitched := {}
## 投手ID → 最後に先発した日
var last_started := {}
## 投手ID → [日, 球数] の直近の登板
var recent_outings := {}
var _rotation_index := 0


func _init(team_name: String, league_code: String, ratings_players: Array) -> void:
	name = team_name
	league = league_code
	for p: Dictionary in ratings_players:
		var s := SimPlayer.from_rating(p)
		players.append(s)
		by_id[s.id] = s
	_build_pitching_staff()
	lineup_dh = _build_lineup(true)
	lineup_no_dh = _build_lineup(false)


## 野手の守備位置（中堅手などは fielding の「外野手」を見る）
static func field_key(slot: String) -> String:
	if slot in ["左翼手", "中堅手", "右翼手"]:
		return "外野手"
	return slot


func _build_lineup(use_dh: bool) -> Array:
	var candidates: Array[SimPlayer] = []
	for p in players:
		if not p.is_pitcher:
			candidates.append(p)
	var used := {}
	var assigned := {}
	for slot: String in FIELD_SLOTS:
		var best: SimPlayer = null
		var best_score := -INF
		for p in candidates:
			if used.has(p.id):
				continue
			var score := _starter_score(p, slot)
			if score > best_score:
				best_score = score
				best = p
		if best != null:
			used[best.id] = true
			assigned[slot] = best
	if use_dh:
		var dh: SimPlayer = null
		for p in candidates:
			if used.has(p.id):
				continue
			if dh == null or _starter_score(p, "指名打者") > _starter_score(dh, "指名打者"):
				dh = p
		if dh != null:
			used[dh.id] = true
			assigned["指名打者"] = dh
	_improve_assignment(assigned, used, candidates)

	# ベンチ（代打要員）: 残りの野手を打撃力順に
	var rest: Array[SimPlayer] = []
	for p in candidates:
		if not used.has(p.id):
			rest.append(p)
	rest.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
		return _experience_value(a) > _experience_value(b))
	if use_dh:
		bench_dh = rest.slice(0, BENCH_SIZE)
	else:
		bench_no_dh = rest.slice(0, BENCH_SIZE)

	var order: Array = []
	for slot: String in assigned:
		order.append([assigned[slot], slot])
	if not use_dh:
		order.append([null, "投手"])
	return _batting_order(order)


## 貪欲法の割り当てを、守備位置の入れ替え・控えとの入れ替えで改善する
## （例：外野の記録がない強打者が左翼に入り、指名打者が空いていた…を直す）
func _improve_assignment(assigned: Dictionary, used: Dictionary,
		candidates: Array[SimPlayer]) -> void:
	var slots: Array = assigned.keys()
	for round_i in 6:
		var improved := false
		for i in slots.size():
			for j in range(i + 1, slots.size()):
				var a: String = slots[i]
				var b: String = slots[j]
				var before := _starter_score(assigned[a], a) + _starter_score(assigned[b], b)
				var after := _starter_score(assigned[b], a) + _starter_score(assigned[a], b)
				if after > before + 0.001:
					var tmp: SimPlayer = assigned[a]
					assigned[a] = assigned[b]
					assigned[b] = tmp
					improved = true
		for slot: String in slots:
			for p in candidates:
				if used.has(p.id):
					continue
				var current: SimPlayer = assigned[slot]
				if _starter_score(p, slot) > _starter_score(current, slot) + 0.001:
					used.erase(current.id)
					used[p.id] = true
					assigned[slot] = p
					improved = true
		if not improved:
			break


## スタメン選考の点数：打撃力＋守備力（位置の重み）＋1軍での実績（出場の多い選手を優先）
func _starter_score(p: SimPlayer, slot: String) -> float:
	var score := _experience_value(p)
	if slot == "指名打者":
		return score
	var key := field_key(slot)
	var def := p.defense_at(key)
	if slot == "中堅手":
		def += p.speed * 0.3
	if slot == "捕手" and not p.defense.has("捕手"):
		return -INF
	if slot in ["遊撃手", "二塁手", "中堅手"] and not p.defense.has(key):
		def -= 1.5
	return score + def * DEFENSE_WEIGHT[slot]


## 実績の少ない選手（能力値が事前値寄り）は起用されにくくする
func _experience_value(p: SimPlayer) -> float:
	var experience := clampf(p.batting_sample / 400.0, 0.0, 1.0)
	return p.batting_value() + 0.5 * experience


## 打順：1番=出塁・走力、2番=ミート、3〜5番=長打と総合力、以降は総合力順。投手は9番
func _batting_order(order: Array) -> Array:
	var pitcher_slot: Array = []
	var hitters: Array = []
	for entry: Array in order:
		if entry[0] == null:
			pitcher_slot = entry
		else:
			hitters.append(entry)
	var power_key := func(p: SimPlayer) -> float: return p.power * 0.7 + p.meet * 0.4
	var lead_off_key := func(p: SimPlayer) -> float: return p.eye * 0.4 + p.meet * 0.4 + p.speed * 0.6
	var second_key := func(p: SimPlayer) -> float: return p.meet * 0.6 + p.speed * 0.3 + p.eye * 0.2
	var overall_key := func(p: SimPlayer) -> float: return p.batting_value()
	# 4番→3番→5番の順に強打者を取り、残りから1・2番を選ぶ
	var fourth := _take_best(hitters, power_key)
	var third := _take_best(hitters, power_key)
	var fifth := _take_best(hitters, power_key)
	var first := _take_best(hitters, lead_off_key)
	var second := _take_best(hitters, second_key)
	var result: Array = []
	for entry: Array in [first, second, third, fourth, fifth]:
		if not entry.is_empty():
			result.append(entry)
	while not hitters.is_empty():
		result.append(_take_best(hitters, overall_key))
	if not pitcher_slot.is_empty():
		result.append(pitcher_slot)
	return result


## hitters（[SimPlayer, 守備位置] の配列）から key が最大のものを取り除いて返す。空なら []
static func _take_best(hitters: Array, key: Callable) -> Array:
	if hitters.is_empty():
		return []
	var best_i := 0
	for i in hitters.size():
		if key.call(hitters[i][0]) > key.call(hitters[best_i][0]):
			best_i = i
	var entry: Array = hitters[best_i]
	hitters.remove_at(best_i)
	return entry


func _build_pitching_staff() -> void:
	var starters: Array[SimPlayer] = []
	var relievers: Array[SimPlayer] = []
	for p in players:
		if not p.is_pitcher or not p.has_pitching:
			continue
		if p.role == "先発":
			starters.append(p)
		else:
			relievers.append(p)
	var by_value := func(a: SimPlayer, b: SimPlayer) -> bool:
		return _pitcher_value(a) > _pitcher_value(b)
	starters.sort_custom(by_value)
	relievers.sort_custom(by_value)
	# 先発が足りなければスタミナのある救援投手で埋める
	while starters.size() < ROTATION_SIZE and not relievers.is_empty():
		var best_i := 0
		for i in relievers.size():
			if relievers[i].stamina > relievers[best_i].stamina:
				best_i = i
		starters.append(relievers[best_i])
		relievers.remove_at(best_i)
	rotation = starters.slice(0, ROTATION_SIZE)
	# 余った先発はロングリリーフとしてブルペンの後ろに入れる
	var extra := starters.slice(ROTATION_SIZE)
	bullpen = relievers.slice(0, BULLPEN_SIZE)
	for p in extra:
		if bullpen.size() >= BULLPEN_SIZE + 1:
			break
		bullpen.append(p)


## 投手の起用の優先度：総合力＋実績
func _pitcher_value(p: SimPlayer) -> float:
	return p.overall + 0.6 * clampf(p.pitching_sample / 300.0, 0.0, 1.0)


func lineup(use_dh: bool) -> Array:
	return lineup_dh if use_dh else lineup_no_dh


func bench(use_dh: bool) -> Array[SimPlayer]:
	return bench_dh if use_dh else bench_no_dh


## その日の先発投手。ローテーション順に、中5日以上あいている投手を選ぶ
func pick_starter(day: int) -> SimPlayer:
	for i in rotation.size():
		var p: SimPlayer = rotation[(_rotation_index + i) % rotation.size()]
		if day - int(last_pitched.get(p.id, -100)) > STARTER_REST_DAYS:
			_rotation_index = (_rotation_index + i + 1) % rotation.size()
			return p
	# 全員詰まっているときは最も間隔のあいた投手
	var best: SimPlayer = rotation[0]
	for p in rotation:
		if int(last_pitched.get(p.id, -100)) < int(last_pitched.get(best.id, -100)):
			best = p
	return best


## その日に投げられるリリーフ（前日に多く投げた・3連投になる投手は除く）
func available_relievers(day: int) -> Array[SimPlayer]:
	var result: Array[SimPlayer] = []
	for p in bullpen:
		var outings: Array = recent_outings.get(p.id, [])
		var yesterday := 0
		var streak := 0
		for o: Array in outings:
			if o[0] == day - 1:
				yesterday += o[1]
			if o[0] == day - 1 or o[0] == day - 2:
				streak += 1
		if yesterday > RELIEVER_MAX_PITCHES_YESTERDAY or streak >= 2:
			continue
		result.append(p)
	return result


func record_outing(p: SimPlayer, day: int, pitches: int, started: bool) -> void:
	last_pitched[p.id] = day
	if started:
		last_started[p.id] = day
	var outings: Array = recent_outings.get(p.id, [])
	outings = outings.filter(func(o: Array) -> bool: return o[0] >= day - 3)
	outings.append([day, pitches])
	recent_outings[p.id] = outings
