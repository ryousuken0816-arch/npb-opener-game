# gdlint: disable=max-public-methods
class_name SimTeam
extends RefCounted
## 1球団の編成と、投手の登板間隔の管理。
##
## - 1軍登録（出場選手登録）：試合に出るのは1軍の選手だけ。人数の上限・外国人枠は RosterRules（史実のルール）
## - スタメン・打順（DHあり/なし）と控え、先発ローテーション、中継ぎ（先頭2人がセットアッパー）・抑え
## - 采配方針（送りバント・盗塁・継投の傾向）
##
## シーズン開始時に能力値から自動で編成する（CPU球団はそのまま）。自球団は采配画面
## （scenes/hub/tactics_view.gd）から登録・オーダー・方針を変える。試合ごとに先発投手と使えるリリーフを選ぶ。

const ROTATION_SIZE := 6
const SETUP_COUNT := 2  ## 中継ぎの先頭からこの人数をセットアッパー（勝ちパターン）として使う
const STARTER_REST_DAYS := 5  ## 先発は中5日以上あける
const RELIEVER_MAX_PITCHES_YESTERDAY := 35

## スタメンを決める順（守備の難しい位置から埋める）
const FIELD_SLOTS := ["捕手", "遊撃手", "二塁手", "中堅手", "三塁手", "左翼手", "右翼手", "一塁手"]
## オーダー画面の守備位置の選択肢（表示順）
const LINEUP_POSITIONS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手", "指名打者"]
## 守備位置ごとの守備力の重み（スタメン選考で打撃力に足す）
const DEFENSE_WEIGHT := {
	"捕手": 0.9, "遊撃手": 0.8, "二塁手": 0.6, "中堅手": 0.6, "三塁手": 0.4,
	"左翼手": 0.25, "右翼手": 0.3, "一塁手": 0.15,
}

## 投手の持ち場
const ROLE_ROTATION := "rotation"
const ROLE_RELIEF := "relief"
const ROLE_CLOSER := "closer"

## 采配方針のキー（値は -2〜+2、0 が標準）
const TACTIC_KEYS := ["bunt", "steal", "relief"]
const TACTIC_MIN := -2
const TACTIC_MAX := 2

var name: String
var league: String
var year: int
var players: Array[SimPlayer] = []
var by_id := {}

## 1軍に登録されている選手ID → true
var active := {}
## 選手ID → 登録を抹消した日（通し日数）。この日から10日間は再登録できない
var demoted_day := {}
## 開幕日（通し日数）。開幕日の試合前の入れ替えは抹消の記録を残さない（Season が設定）
var opening_day := -1

## [SimPlayer, 守備位置] ×9（DH なし: 投手の枠は [null, "投手"]）
var lineup_dh: Array = []
var lineup_no_dh: Array = []
## 控え（1軍の野手でスタメン以外）。代打は先頭から使う（打撃力順）
var bench_dh: Array[SimPlayer] = []
var bench_no_dh: Array[SimPlayer] = []
var rotation: Array[SimPlayer] = []
var closer: SimPlayer = null
var relievers: Array[SimPlayer] = []  ## 中継ぎ（先頭の SETUP_COUNT 人がセットアッパー）
var bullpen: Array[SimPlayer] = []  ## 抑え・中継ぎの順（GameSim が使う。closer と relievers から作る）
## 采配方針 {bunt, steal, relief}（-2〜+2）
var tactics := {"bunt": 0, "steal": 0, "relief": 0}

## 投手ID → 最後に登板した日（通し日数）
var last_pitched := {}
## 投手ID → 最後に先発した日
var last_started := {}
## 投手ID → [日, 球数] の直近の登板
var recent_outings := {}
var _rotation_index := 0


## debut_years: 選手ID → 1軍初出場の年（外国人枠の「日本人扱い」の判定用）
func _init(team_name: String, league_code: String, ratings_players: Array,
		season_year: int = 2008, debut_years: Dictionary = {}) -> void:
	name = team_name
	league = league_code
	year = season_year
	for p: Dictionary in ratings_players:
		var s := SimPlayer.from_rating(p)
		s.is_foreign = RosterRules.is_foreign(p, year, debut_years.get(s.id))
		players.append(s)
		by_id[s.id] = s
	auto_register()


## 選手を加える（シーズン中の移籍。1軍・持ち場・スタメンは自動で組み直す）
func add_player(p: Dictionary, debut_years: Dictionary = {}) -> void:
	if by_id.has(p["id"]):
		return
	var s := SimPlayer.from_rating(p)
	s.team = name
	s.is_foreign = RosterRules.is_foreign(p, year, debut_years.get(s.id))
	players.append(s)
	by_id[s.id] = s
	auto_register()


## 育成選手の印を付け直す（ids：選手ID → true）。rebuild なら、1軍にいる育成選手を外して自動で組み直す
func set_ikusei(ids: Dictionary, rebuild := true) -> void:
	var on_first := false
	for p in players:
		p.is_ikusei = ids.has(p.id)
		if p.is_ikusei and is_active(p):
			on_first = true
	if on_first and rebuild:
		auto_register()


## 選手を外す（シーズン中の移籍。1軍・持ち場・スタメンは自動で組み直す）
func remove_player(id: String) -> void:
	if not by_id.has(id):
		return
	players.erase(by_id[id])
	by_id.erase(id)
	active.erase(id)
	auto_register()


## 野手の守備位置（中堅手などは fielding の「外野手」を見る）
static func field_key(slot: String) -> String:
	if slot in ["左翼手", "中堅手", "右翼手"]:
		return "外野手"
	return slot


# --- 自動編成 -------------------------------------------------------------------------

## 1軍登録・投手の持ち場・スタメンをすべて能力値から自動で組み直す（外国人枠・人数の上限を守る）
func auto_register() -> void:
	var excluded := {}
	var chosen: Array[SimPlayer] = []
	for attempt in 30:
		chosen = _auto_choose(excluded)
		var over := _foreign_to_exclude(chosen)
		if over == null:
			break
		excluded[over.id] = true
	active.clear()
	for p in chosen:
		active[p.id] = true
	auto_pitching_staff()
	auto_lineup(true)
	auto_lineup(false)


## 1軍に登録する選手を選ぶ：投手は上限の半分−1人（28人なら13人）、残りを野手（スタメン2通り＋控え捕手＋実績順）
func _auto_choose(excluded: Dictionary) -> Array[SimPlayer]:
	var limit := RosterRules.roster_limit(year)
	var pitcher_slots := limit / 2 - 1
	var pitchers: Array[SimPlayer] = []
	var fielders: Array[SimPlayer] = []
	for p in players:
		if excluded.has(p.id) or p.is_ikusei or p.injured:
			continue
		if p.is_pitcher:
			if p.has_pitching:
				pitchers.append(p)
		else:
			fielders.append(p)
	var staff := _plan_pitching_staff(pitchers)
	var chosen: Array[SimPlayer] = []
	chosen.append_array(staff["rotation"])
	for p: SimPlayer in staff["bullpen"]:
		if chosen.size() >= pitcher_slots:
			break
		chosen.append(p)

	var chosen_fielders: Array[SimPlayer] = []
	for use_dh in [true, false]:
		for entry: Array in _build_order(use_dh, fielders):
			if entry[0] != null and entry[0] not in chosen_fielders:
				chosen_fielders.append(entry[0])
	var rest := fielders.filter(func(p: SimPlayer) -> bool: return p not in chosen_fielders)
	rest.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
		return _experience_value(a) > _experience_value(b))
	# 控え捕手を必ず1人入れる
	var catchers := chosen_fielders.filter(func(p: SimPlayer) -> bool: return p.can_play("捕手"))
	if catchers.size() < 2:
		for p: SimPlayer in rest:
			if p.can_play("捕手"):
				chosen_fielders.append(p)
				rest.erase(p)
				break
	for p: SimPlayer in rest:
		if chosen.size() + chosen_fielders.size() >= limit:
			break
		chosen_fielders.append(p)
	chosen.append_array(chosen_fielders)
	return chosen


## 外国人枠を超えていれば、外すべき外国人（超えている側で最も優先度の低い選手）。守れていれば null
func _foreign_to_exclude(chosen: Array[SimPlayer]) -> SimPlayer:
	var fp: Array[SimPlayer] = []
	var ff: Array[SimPlayer] = []
	for p in chosen:
		if p.is_foreign:
			(fp if p.is_pitcher else ff).append(p)
	var group: Array[SimPlayer] = []
	if fp.size() > RosterRules.foreign_type_limit(year):
		group = fp
	elif ff.size() > RosterRules.foreign_type_limit(year):
		group = ff
	elif fp.size() + ff.size() > RosterRules.foreign_limit(year):
		group.append_array(fp)
		group.append_array(ff)
	else:
		return null
	var worst: SimPlayer = group[0]
	for p in group:
		if _auto_value(p) < _auto_value(worst):
			worst = p
	return worst


func _auto_value(p: SimPlayer) -> float:
	return _pitcher_value(p) if p.is_pitcher else _experience_value(p)


## 1軍の投手で先発ローテーション・抑え・中継ぎを組み直す
func auto_pitching_staff() -> void:
	var staff := _plan_pitching_staff(active_players(true))
	rotation = staff["rotation"]
	var pen: Array[SimPlayer] = staff["bullpen"]
	closer = pen[0] if not pen.is_empty() else null
	relievers = pen.slice(1)
	_rebuild_bullpen()


## 投手の一覧から {rotation: 先発6人, bullpen: 救援（優先度順、余った先発はロングリリーフとして後ろ）}
func _plan_pitching_staff(pitchers: Array[SimPlayer]) -> Dictionary:
	var starters: Array[SimPlayer] = []
	var relief: Array[SimPlayer] = []
	for p in pitchers:
		if p.role == "先発":
			starters.append(p)
		else:
			relief.append(p)
	var by_value := func(a: SimPlayer, b: SimPlayer) -> bool:
		return _pitcher_value(a) > _pitcher_value(b)
	starters.sort_custom(by_value)
	relief.sort_custom(by_value)
	# 先発が足りなければスタミナのある救援投手で埋める
	while starters.size() < ROTATION_SIZE and not relief.is_empty():
		var best_i := 0
		for i in relief.size():
			if relief[i].stamina > relief[best_i].stamina:
				best_i = i
		starters.append(relief[best_i])
		relief.remove_at(best_i)
	var pen: Array[SimPlayer] = relief.duplicate()
	pen.append_array(starters.slice(ROTATION_SIZE))
	return {"rotation": starters.slice(0, ROTATION_SIZE), "bullpen": pen}


## 1軍の野手でスタメン・打順を自動で組む
func auto_lineup(use_dh: bool) -> void:
	var order := _build_order(use_dh, active_players(false))
	if use_dh:
		lineup_dh = order
	else:
		lineup_no_dh = order
	_rebuild_bench()


func _build_order(use_dh: bool, candidates: Array[SimPlayer]) -> Array:
	var used := {}
	var assigned := {}
	for slot: String in FIELD_SLOTS:
		var best: SimPlayer = null
		var best_score := -INF
		for p in candidates:
			if used.has(p.id):
				continue
			var score := _starter_score(p, slot)
			if best == null or score > best_score:
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

	var order: Array = []
	for slot: String in assigned:
		order.append([assigned[slot], slot])
	if not use_dh:
		order.append([null, "投手"])
	return _batting_order(order)


## 貪欲法の割り当てを、守備位置の入れ替え・控えとの入れ替え・控えを入れて押し出しで回す入れ替えで改善する
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
		# 控えを位置 a に入れ、a にいた選手を位置 b へ回し、b にいた選手を外す（作業44：近藤を左翼へ回して周東を中堅に、など）
		for a: String in slots:
			for p in candidates:
				if used.has(p.id):
					continue
				var q: SimPlayer = assigned[a]
				for b: String in slots:
					if b == a:
						continue
					var r: SimPlayer = assigned[b]
					var before := _starter_score(q, a) + _starter_score(r, b)
					var after := _starter_score(p, a) + _starter_score(q, b)
					if after > before + 0.001:
						used.erase(r.id)
						used[p.id] = true
						assigned[a] = p
						assigned[b] = q
						improved = true
						break
		if not improved:
			break


## スタメン選考の点数：打撃力＋守備力（位置の重み）＋1軍での実績（出場の多い選手を優先）
func _starter_score(p: SimPlayer, slot: String) -> float:
	var score := _experience_value(p)
	if slot == "指名打者":
		return score
	var def := p.range_at(slot)
	if slot == "捕手" and not p.can_play("捕手"):
		return -1000.0 + score
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


## 投手の起用の優先度：総合力＋実績
func _pitcher_value(p: SimPlayer) -> float:
	return p.overall + 0.6 * clampf(p.pitching_sample / 300.0, 0.0, 1.0)


func _rebuild_bullpen() -> void:
	bullpen.clear()
	if closer != null:
		bullpen.append(closer)
	bullpen.append_array(relievers)


func _rebuild_bench() -> void:
	for use_dh in [true, false]:
		var in_lineup := {}
		for entry: Array in lineup(use_dh):
			if entry[0] != null:
				in_lineup[entry[0].id] = true
		var rest: Array[SimPlayer] = []
		for p in active_players(false):
			if not in_lineup.has(p.id):
				rest.append(p)
		rest.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
			return _experience_value(a) > _experience_value(b))
		if use_dh:
			bench_dh = rest
		else:
			bench_no_dh = rest


# --- 1軍登録 --------------------------------------------------------------------------

func is_active(p: SimPlayer) -> bool:
	return active.has(p.id)


## 1軍（active=true）または2軍の投手（pitchers=true）/野手
func players_where(is_active_flag: bool, pitchers: bool) -> Array[SimPlayer]:
	var result: Array[SimPlayer] = []
	for p in players:
		if p.is_pitcher == pitchers and active.has(p.id) == is_active_flag:
			result.append(p)
	return result


func active_players(pitchers: bool) -> Array[SimPlayer]:
	return players_where(true, pitchers)


func active_count() -> int:
	return active.size()


## 1軍の外国人の人数 [投手, 野手]
func foreign_counts() -> Array[int]:
	var result: Array[int] = [0, 0]
	for p in players:
		if p.is_foreign and active.has(p.id):
			result[0 if p.is_pitcher else 1] += 1
	return result


## 再登録できる最初の日（通し日数）。制限がなければ -1
func reregister_day(p: SimPlayer) -> int:
	if not demoted_day.has(p.id):
		return -1
	return int(demoted_day[p.id]) + RosterRules.REREGISTER_DAYS


## 2軍の p を1軍に上げられるか。できなければ理由、できれば空文字。swap_out は同時に2軍へ落とす1軍の選手
func promote_error(p: SimPlayer, today: int, swap_out: SimPlayer = null) -> String:
	if is_active(p):
		return "%sはすでに1軍です" % p.name
	if p.is_ikusei:
		return "%sは育成選手です（支配下に登録すると1軍に上げられます）" % p.name
	if p.injured:
		return "%sは%sのため1軍に上げられません" % [p.name, p.injury if not p.injury.is_empty() else "故障中"]
	var back := reregister_day(p)
	# 抹消したその日のうち（試合前）に戻すのは取り消しとみなす
	if back >= 0 and today != int(demoted_day[p.id]) and today < back:
		return "%sは登録抹消から10日間は再登録できません（%s以降）" % [p.name, Season.day_label(back)]
	var limit := RosterRules.roster_limit(year)
	var count := active_count() - (1 if swap_out != null else 0)
	if count + 1 > limit:
		return "1軍に登録できるのは%d人までです（入れ替える選手を選んでください）" % limit
	if p.is_foreign:
		var counts := foreign_counts()
		if swap_out != null and swap_out.is_foreign:
			counts[0 if swap_out.is_pitcher else 1] -= 1
		var f_limit := RosterRules.foreign_limit(year)
		var type_limit := RosterRules.foreign_type_limit(year)
		if counts[0] + counts[1] + 1 > f_limit:
			return "外国人は1軍に%d人までしか登録できません" % f_limit
		if counts[0 if p.is_pitcher else 1] + 1 > type_limit:
			return "外国人%sは%d人までです（投手・野手の片方だけで外国人枠を使い切れません）" % [
				"投手" if p.is_pitcher else "野手", type_limit]
	return ""


## 1軍の p を2軍に落とせるか。できなければ理由。swap_in は同時に1軍へ上げる選手
func demote_error(p: SimPlayer, swap_in: SimPlayer = null) -> String:
	if not is_active(p):
		return "%sは2軍の選手です" % p.name
	if swap_in != null and swap_in.is_pitcher == p.is_pitcher:
		return ""
	if p.is_pitcher and active_players(true).size() - 1 < RosterRules.MIN_PITCHERS:
		return "1軍の投手がいなくなります"
	if not p.is_pitcher and active_players(false).size() - 1 < RosterRules.MIN_FIELDERS:
		return "1軍の野手が%d人を下回るとスタメンを組めません" % RosterRules.MIN_FIELDERS
	return ""


## 2軍の p を1軍に上げる。投手は role の持ち場の index 番目（-1 は末尾）に入る。失敗なら理由を返す
func promote(p: SimPlayer, today: int, role: String = ROLE_RELIEF, index: int = -1) -> String:
	var err := promote_error(p, today)
	if not err.is_empty():
		return err
	active[p.id] = true
	if p.is_pitcher:
		_place_pitcher(p, role, index)
	_rebuild_bench()
	return ""


## 1軍の p を2軍に落とす（スタメンだった場合は控えから自動で埋める）。失敗なら理由を返す
func demote(p: SimPlayer, today: int) -> String:
	var err := demote_error(p)
	if not err.is_empty():
		return err
	_deactivate(p, today)
	_repair_lineups()
	return ""


## 1軍の out_p と2軍の in_p を入れ替える。in_p は out_p の持ち場（先発の枠・スタメンの打順と守備位置）に入る
func swap_registration(out_p: SimPlayer, in_p: SimPlayer, today: int) -> String:
	var err := demote_error(out_p, in_p)
	if err.is_empty():
		err = promote_error(in_p, today, out_p)
	if not err.is_empty():
		return err
	var role := pitcher_role(out_p)
	if not in_p.is_pitcher and not out_p.is_pitcher:
		for use_dh in [true, false]:
			for entry: Array in lineup(use_dh):
				if entry[0] == out_p:
					entry[0] = in_p
	_deactivate(out_p, today)
	active[in_p.id] = true
	if in_p.is_pitcher:
		if out_p.is_pitcher:
			_place_pitcher(in_p, role[0], role[1])
		else:
			_place_pitcher(in_p, ROLE_RELIEF, -1)
	_repair_lineups()
	return ""


func _deactivate(p: SimPlayer, today: int) -> void:
	active.erase(p.id)
	# 開幕日の試合前の入れ替えは登録抹消の扱いにしない
	if today > opening_day:
		if not (demoted_day.has(p.id) and int(demoted_day[p.id]) == today):
			demoted_day[p.id] = today
	if p.is_pitcher:
		_take_out_pitcher(p)


## スタメンに2軍の選手が残っていれば、その守備位置に最も合う控えで埋める
func _repair_lineups() -> void:
	for use_dh in [true, false]:
		var order: Array = lineup(use_dh)
		var in_lineup := {}
		for entry: Array in order:
			if entry[0] != null and is_active(entry[0]):
				in_lineup[entry[0].id] = true
		for entry: Array in order:
			if entry[0] == null or is_active(entry[0]):
				continue
			var best: SimPlayer = null
			for p in active_players(false):
				if in_lineup.has(p.id):
					continue
				if best == null or _starter_score(p, entry[1]) > _starter_score(best, entry[1]):
					best = p
			if best != null:
				entry[0] = best
				in_lineup[best.id] = true
	_rebuild_bench()


# --- 投手の持ち場 -----------------------------------------------------------------------

## [持ち場, 位置]。1軍でない投手は ["", -1]
func pitcher_role(p: SimPlayer) -> Array:
	if p == closer:
		return [ROLE_CLOSER, 0]
	var i := rotation.find(p)
	if i >= 0:
		return [ROLE_ROTATION, i]
	i = relievers.find(p)
	if i >= 0:
		return [ROLE_RELIEF, i]
	return ["", -1]


func _take_out_pitcher(p: SimPlayer) -> void:
	if closer == p:
		closer = null
	rotation.erase(p)
	relievers.erase(p)
	_rebuild_bullpen()


## p を持ち場 role の index 番目に置く。先発が6人を超えたら押し出された投手は中継ぎへ、
## 抑えがいれば元の抑えは中継ぎの先頭へ
func _place_pitcher(p: SimPlayer, role: String, index: int) -> void:
	match role:
		ROLE_ROTATION:
			rotation.insert(clampi(index, 0, rotation.size()) if index >= 0 else rotation.size(), p)
			while rotation.size() > ROTATION_SIZE:
				relievers.append(rotation.pop_back())
		ROLE_CLOSER:
			if closer != null:
				relievers.insert(0, closer)
			closer = p
		_:
			relievers.insert(clampi(index, 0, relievers.size()) if index >= 0 else relievers.size(), p)
	_rebuild_bullpen()


## 1軍の投手を別の持ち場の空き（末尾）へ移す
func move_pitcher(p: SimPlayer, role: String) -> void:
	if not is_active(p) or not p.is_pitcher:
		return
	_take_out_pitcher(p)
	_place_pitcher(p, role, -1)


## 1軍の投手2人の持ち場を入れ替える
func swap_pitcher_roles(a: SimPlayer, b: SimPlayer) -> void:
	var ra := pitcher_role(a)
	var rb := pitcher_role(b)
	if ra[0] == "" or rb[0] == "":
		return
	_set_pitcher_at(ra, b)
	_set_pitcher_at(rb, a)
	_rebuild_bullpen()


func _set_pitcher_at(role: Array, p: SimPlayer) -> void:
	match role[0]:
		ROLE_CLOSER:
			closer = p
		ROLE_ROTATION:
			rotation[role[1]] = p
		ROLE_RELIEF:
			relievers[role[1]] = p


# --- オーダー --------------------------------------------------------------------------

## 試合で使うスタメン：故障中の選手は、その守備位置に最も合う1軍の控え（故障していない）に代える。
## 保存しているオーダーは変えない（自球団は抹消するまで1軍に残るので）
func game_lineup(use_dh: bool) -> Array:
	var order: Array = []
	var used := {}
	for entry: Array in lineup(use_dh):
		order.append(entry.duplicate())
		if entry[0] != null:
			used[entry[0].id] = true
	for entry: Array in order:
		if entry[0] == null or not entry[0].injured:
			continue
		var best: SimPlayer = null
		for p in active_players(false):
			if used.has(p.id) or p.injured:
				continue
			if best == null or _starter_score(p, entry[1]) > _starter_score(best, entry[1]):
				best = p
		if best != null:
			entry[0] = best
			used[best.id] = true
	return order


## 試合で使う控え（故障中と、game_lineup で代わりにスタメンに入った選手を除く）
func game_bench(use_dh: bool, order: Array) -> Array[SimPlayer]:
	var used := {}
	for entry: Array in order:
		if entry[0] != null:
			used[entry[0].id] = true
	var result: Array[SimPlayer] = []
	for p in bench(use_dh):
		if not p.injured and not used.has(p.id):
			result.append(p)
	return result


## 主力（スタメン・先発ローテの5人・抑え・勝ちパターンの中継ぎ）か。故障のニュースに使う
func is_key_player(p: SimPlayer) -> bool:
	if not is_active(p):
		return false
	if p.is_pitcher:
		var i := rotation.find(p)
		return p == closer or (i >= 0 and i < ROTATION_SIZE - 1) or relievers.slice(0, SETUP_COUNT).has(p)
	for use_dh in [true, false]:
		for entry: Array in lineup(use_dh):
			if entry[0] == p:
				return true
	return false


## 1軍の故障中の選手
func injured_active() -> Array[SimPlayer]:
	var result: Array[SimPlayer] = []
	for p in players:
		if p.injured and is_active(p):
			result.append(p)
	return result


## 故障中の p の代わりに上げる2軍の選手（投手なら投手、野手は同じ守備位置に合う選手。いなければ null）
func injury_replacement(p: SimPlayer, today: int) -> SimPlayer:
	var best: SimPlayer = null
	var best_value := -INF
	var slot := ""
	for use_dh in [true, false]:
		for entry: Array in lineup(use_dh):
			if entry[0] == p:
				slot = entry[1]
	for c in players_where(false, p.is_pitcher):
		if c.injured or not promote_error(c, today, p).is_empty():
			continue
		if c.is_pitcher and not c.has_pitching:
			continue
		var v := _pitcher_value(c) if c.is_pitcher else (
				_starter_score(c, slot) if not slot.is_empty() else _experience_value(c))
		if v > best_value:
			best_value = v
			best = c
	return best


## 今の持ち場 {slots: スタメンの [DHあり, 打順の添字, 守備位置] の一覧, role: pitcher_role}。
## CPU球団が故障から戻った選手を元の持ち場に戻すのに使う（故障したときに Health の記録に残す）
func place_of(p: SimPlayer) -> Dictionary:
	var slots: Array = []
	for use_dh in [true, false]:
		var order: Array = lineup(use_dh)
		for i in order.size():
			if order[i][0] == p:
				slots.append([use_dh, i, order[i][1]])
	return {"slots": slots, "role": pitcher_role(p)}


## 故障から戻った2軍の p を1軍に戻す（CPU球団。auto_register は重いので使わない）：1軍の同じ種類で
## 控え（スタメン・先発・抑え以外）のいちばん劣る選手と入れ替え、place（place_of）の持ち場に戻す。
## 抹消から10日たっていなくて今日は戻せないときだけ false（翌日にまた試す）。戻す必要が無いときも true
func return_from_injury(p: SimPlayer, today: int, place: Dictionary) -> bool:
	if p.injured or is_active(p) or p.is_ikusei or not by_id.has(p.id):
		return true
	var in_lineup := {}
	for use_dh in [true, false]:
		for entry: Array in lineup(use_dh):
			if entry[0] != null:
				in_lineup[entry[0].id] = true
	var worst: SimPlayer = null
	for c in active_players(p.is_pitcher):
		if in_lineup.has(c.id) or c == closer or rotation.has(c):
			continue
		if worst == null or _auto_value(c) < _auto_value(worst):
			worst = c
	var slots: Array = place.get("slots", [])
	var role: Array = place.get("role", ["", -1])
	var was_key := not slots.is_empty() or str(role[0]) in [ROLE_ROTATION, ROLE_CLOSER]
	if worst == null or (not was_key and _auto_value(p) <= _auto_value(worst)):
		return true
	var err := swap_registration(worst, p, today)
	if not err.is_empty():
		return not err.contains("再登録")
	if p.is_pitcher:
		if str(role[0]) in [ROLE_ROTATION, ROLE_CLOSER]:
			_take_out_pitcher(p)
			_place_pitcher(p, str(role[0]), int(role[1]))
	else:
		for s: Array in slots:
			var order: Array = lineup(bool(s[0]))
			var i := int(s[1])
			var taken := order.any(func(e: Array) -> bool: return e[0] == p)
			if not taken and i < order.size() and str(order[i][1]) == str(s[2]):
				order[i][0] = p
		_rebuild_bench()
	return true


## 1軍の故障中の選手を抹消し、2軍の代わりの選手を上げる。[[抹消した, 上げた（いなければ null）], ...]
func swap_out_injured(today: int) -> Array:
	var done: Array = []
	for p in injured_active():
		var sub := injury_replacement(p, today)
		var err := swap_registration(p, sub, today) if sub != null else demote(p, today)
		if err.is_empty():
			done.append([p, sub])
	return done


func lineup(use_dh: bool) -> Array:
	return lineup_dh if use_dh else lineup_no_dh


func bench(use_dh: bool) -> Array[SimPlayer]:
	return bench_dh if use_dh else bench_no_dh


## 打順の i 番目と j 番目を入れ替える（守備位置は選手についていく）
func lineup_swap_order(use_dh: bool, i: int, j: int) -> void:
	var order := lineup(use_dh)
	var tmp: Array = order[i]
	order[i] = order[j]
	order[j] = tmp


## 打順の i 番目に控えの p を入れる（打順と守備位置を引き継ぎ、元の選手は控えへ）
func lineup_replace(use_dh: bool, i: int, p: SimPlayer) -> void:
	var order := lineup(use_dh)
	if order[i][0] == null or not is_active(p) or p.is_pitcher:
		return
	for entry: Array in order:
		if entry[0] == p:
			return
	order[i] = [p, order[i][1]]
	_rebuild_bench()


## 打順の i 番目の守備位置を pos にする（pos を守っていた選手とは守備位置を入れ替える）
func lineup_set_position(use_dh: bool, i: int, pos: String) -> void:
	var order := lineup(use_dh)
	var old: String = order[i][1]
	if old == "投手" or pos == "投手" or old == pos:
		return
	for entry: Array in order:
		if entry[1] == pos:
			entry[1] = old
	order[i][1] = pos


func set_tactic(key: String, level: int) -> void:
	tactics[key] = clampi(level, TACTIC_MIN, TACTIC_MAX)


# --- 試合ごとの起用 ----------------------------------------------------------------------

## その日の先発投手。ローテーション順に、中5日以上あいている投手を選ぶ
func pick_starter(day: int) -> SimPlayer:
	var healthy := func(p: SimPlayer) -> bool: return not p.injured
	var pool: Array[SimPlayer] = rotation.filter(healthy)
	if pool.is_empty():
		# 先発がいなければ、1軍の投手のうち最もスタミナのある投手を使う（故障中の投手は避ける）
		pool = bullpen.filter(healthy)
		if pool.is_empty():
			pool = active_players(true).filter(healthy)
		if pool.is_empty():
			pool = rotation.duplicate() if not rotation.is_empty() else active_players(true)
		pool.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.stamina > b.stamina)
	for i in pool.size():
		var p: SimPlayer = pool[(_rotation_index + i) % pool.size()]
		if day - int(last_pitched.get(p.id, -100)) > STARTER_REST_DAYS:
			_rotation_index = (_rotation_index + i + 1) % pool.size()
			return p
	# 全員詰まっているときは最も間隔のあいた投手
	var best: SimPlayer = pool[0]
	for p in pool:
		if int(last_pitched.get(p.id, -100)) < int(last_pitched.get(best.id, -100)):
			best = p
	return best


## その日に投げられるリリーフ（前日に多く投げた・3連投になる投手は除く）
func available_relievers(day: int) -> Array[SimPlayer]:
	var result: Array[SimPlayer] = []
	for p in bullpen:
		if p.injured:
			continue
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


# --- セーブ／ロード ----------------------------------------------------------------------

## 編成の状態（1軍登録・オーダー・ローテ・ブルペン・抹消日・登板間隔・方針）。選手は ID で持つ
func to_save() -> Dictionary:
	var ids := func(list: Array) -> Array:
		var result := []
		for p: SimPlayer in list:
			result.append(p.id)
		return result
	var lineup_ids := func(order: Array) -> Array:
		var result := []
		for entry: Array in order:
			result.append([entry[0].id if entry[0] != null else null, entry[1]])
		return result
	return {
		"players": ids.call(players), "active": active.keys(), "demoted_day": demoted_day,
		"opening_day": opening_day, "lineup_dh": lineup_ids.call(lineup_dh),
		"lineup_no_dh": lineup_ids.call(lineup_no_dh), "bench_dh": ids.call(bench_dh),
		"bench_no_dh": ids.call(bench_no_dh), "rotation": ids.call(rotation),
		"closer": closer.id if closer != null else null, "relievers": ids.call(relievers),
		"tactics": tactics, "last_pitched": last_pitched, "last_started": last_started,
		"recent_outings": recent_outings, "rotation_index": _rotation_index,
	}


## to_save() の中身を戻す（選手はこの編成にいる選手だけ。いない ID は飛ばす）
func from_save(d: Dictionary) -> void:
	var order: Array = d.get("players", [])
	var rank := {}
	for i in order.size():
		rank[str(order[i])] = i
	players.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
		return int(rank.get(a.id, 1 << 30)) < int(rank.get(b.id, 1 << 30)))
	active.clear()
	for id: Variant in d.get("active", []):
		if by_id.has(str(id)):
			active[str(id)] = true
	demoted_day = _int_values(d.get("demoted_day", {}))
	opening_day = int(d.get("opening_day", opening_day))
	lineup_dh = _lineup_from(d.get("lineup_dh", []))
	lineup_no_dh = _lineup_from(d.get("lineup_no_dh", []))
	bench_dh = _players_from(d.get("bench_dh", []))
	bench_no_dh = _players_from(d.get("bench_no_dh", []))
	rotation = _players_from(d.get("rotation", []))
	closer = by_id.get(str(d["closer"])) if d.get("closer") != null else null
	relievers = _players_from(d.get("relievers", []))
	_rebuild_bullpen()
	for key: String in d.get("tactics", {}):
		tactics[key] = int(d["tactics"][key])
	last_pitched = _int_values(d.get("last_pitched", {}))
	last_started = _int_values(d.get("last_started", {}))
	recent_outings.clear()
	var outings: Dictionary = d.get("recent_outings", {})
	for id: String in outings:
		var list: Array = []
		for o: Array in outings[id]:
			list.append([int(o[0]), int(o[1])])
		recent_outings[id] = list
	_rotation_index = int(d.get("rotation_index", 0))


func _players_from(ids: Array) -> Array[SimPlayer]:
	var result: Array[SimPlayer] = []
	for id: Variant in ids:
		if by_id.has(str(id)):
			result.append(by_id[str(id)])
	return result


func _lineup_from(entries: Array) -> Array:
	var result: Array = []
	for entry: Array in entries:
		var p: SimPlayer = by_id.get(str(entry[0])) if entry[0] != null else null
		if entry[0] != null and p == null:
			continue
		result.append([p, str(entry[1])])
	return result


static func _int_values(d: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in d:
		result[str(key)] = int(d[key])
	return result
