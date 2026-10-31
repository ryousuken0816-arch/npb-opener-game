class_name Depth
extends RefCounted
## 記録室の「チームのデプス」と「守備位置ランク」の計算。オートロードは参照しない（選手データ・編成を受け取る）。
##
## 選手ごとに2つのランク（S〜G、ドラフト画面と同じ目盛り Draft.FUTURE_RANKS）：
## - 現在の能力：今の能力値から Salary.ability と同じ「実力z ＋ PLAYING_WEIGHT × 出場量」（tools/draft_future.py と同じ式）
## - 将来性：今年より後の年の史実の実力のピーク（generated/player_future.json、tools/player_future.py）に
##   ドラフトと同じノイズ（Draft.DIFFICULTY_NOISE）を足したもの。ノイズは選手ごとに固定（salt で決まる）。
##   史実の残りの年数が少ない（FUTURE_FULL_YEARS 未満）ときは今の実力で補う。史実で以後の年が無い（引退・海外）は低い値
##
## 守備位置：捕手・一塁手・二塁手・三塁手・遊撃手・外野手・先発・中継ぎ・抑え。スタメン（SimTeam の DH ありのオーダー）・
## 先発ローテ・中継ぎ・抑えを「正選手」、残りは能力値の守備位置（primary_pos）・投手の役割で振り分けて控え（2軍も含む）。
## チームの位置ランク＝正選手を重く（REGULAR_WEIGHT）、控えの上位を軽く（BACKUP_WEIGHT）、残りをごく軽く（DEPTH_WEIGHT）
## した平均を同じ目盛りでランクにしたもの

const POSITIONS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手", "先発", "中継ぎ", "抑え"]
const POS_SHORT := {"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "外野手": "外",
	"先発": "先", "中継ぎ": "中", "抑え": "抑"}
## 正選手の人数（外野3・先発6・中継ぎ6）
const REGULARS := {"捕手": 1, "一塁手": 1, "二塁手": 1, "三塁手": 1, "遊撃手": 1, "外野手": 3,
	"先発": 6, "中継ぎ": 6, "抑え": 1}
const REGULAR_WEIGHT := 1.0
const BACKUP_WEIGHT := 0.35
const DEPTH_WEIGHT := 0.1
## 控えの上位として BACKUP_WEIGHT を付ける人数（正選手の人数 × この倍、最低1人）
const BACKUP_SHARE := 1.0
const PLAYING_WEIGHT := 0.6
## 将来性：史実の以後の年が無いときの値・史実が何年分あれば今の実力で補わないか
const FUTURE_NONE := -1.2
const FUTURE_FULL_YEARS := 3.0
## 「若手の有望株」の印：この年齢以下で、将来性が現在より RISE_STEPS 段以上高い
const PROSPECT_AGE := 25
const RISE_STEPS := 2
## 層の厚さの表示：このランク以上の人数
const THICK_RANK := "B"

var _future: Dictionary = {}
var _data_through := 0
var _salt := ""
var _noise := 0.35


## future_data: generated/player_future.json の中身、salt: ノイズを選手ごとに固定する文字列（ゲームごと）
func _init(future_data: Dictionary, salt: String, noise: float) -> void:
	_future = future_data.get("players", {})
	_data_through = int(future_data.get("data_through", 0))
	_salt = salt
	_noise = noise


# --- ランク ----------------------------------------------------------------------------

static func now_score(p: Dictionary) -> float:
	var a := Salary.ability(p)
	return float(a[0]) + PLAYING_WEIGHT * float(a[1])


func future_score(id: String, year: int, now: float) -> float:
	var years: Dictionary = _future.get(id, {})
	var best := -INF
	for y: String in years:
		if int(y) > year:
			best = maxf(best, float(years[y]))
	var w := clampf(float(_data_through - year) / FUTURE_FULL_YEARS, 0.0, 1.0)
	var hist := best if best > -INF else FUTURE_NONE
	var v := lerpf(now, hist, w)
	if best > -INF and w < 1.0:
		v = maxf(v, best)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%s" % [id, _salt])
	return v + rng.randfn(0.0, _noise)


## スコア → ランクの文字（S〜G）
static func rank_of(score: float) -> String:
	for i in Draft.FUTURE_RANKS.size():
		if score >= Draft.FUTURE_RANKS[i]:
			return Draft.RANK_LETTERS[i]
	return Draft.RANK_LETTERS[-1]


static func rank_index(rank: String) -> int:
	return Draft.RANK_LETTERS.find(rank)


## 1人分 {id, name, age, now, future, now_rank, future_rank, prospect, active, pitcher}
func entry(p: Dictionary, year: int, age: int, active: bool) -> Dictionary:
	var id: String = p["id"]
	var now := now_score(p)
	var fut := future_score(id, year, now)
	var e := {"id": id, "name": str(p.get("name", "")), "age": age, "now": now, "future": fut,
		"now_rank": rank_of(now), "future_rank": rank_of(fut), "active": active,
		"pitcher": bool(p.get("is_pitcher", false))}
	e["prospect"] = age > 0 and age <= PROSPECT_AGE \
		and rank_index(e["now_rank"]) - rank_index(e["future_rank"]) >= RISE_STEPS
	return e


# --- チーム -------------------------------------------------------------------------------

## 球団のデプス {位置: [entry（正選手が先、"regular" が true）]}。
## members: その球団の選手データ（GameData.players_of）、sim: その球団の SimTeam（無ければ null）、
## age_of: 選手データ → 年齢
func team_depth(members: Array, sim: SimTeam, year: int, age_of: Callable) -> Dictionary:
	var result := {}
	for pos: String in POSITIONS:
		result[pos] = []
	var placed := {}
	var regular_ids := {}
	if sim != null:
		for slot: Array in sim.lineup_dh:
			if slot[0] == null:
				continue
			var pos := SimTeam.field_key(slot[1])
			if result.has(pos):
				regular_ids[(slot[0] as SimPlayer).id] = pos
		for sp: SimPlayer in sim.rotation:
			regular_ids[sp.id] = "先発"
		for sp: SimPlayer in sim.relievers:
			regular_ids[sp.id] = "中継ぎ"
		if sim.closer != null:
			regular_ids[sim.closer.id] = "抑え"
	for p: Dictionary in members:
		var id: String = p["id"]
		if placed.has(id):
			continue
		placed[id] = true
		var active := sim != null and sim.active.has(id)
		var e := entry(p, year, int(age_of.call(p)), active)
		var pos: String = regular_ids.get(id, "")
		e["regular"] = not pos.is_empty()
		if pos.is_empty():
			pos = _natural_pos(p)
		if pos.is_empty():
			continue
		result[pos].append(e)
	for pos: String in result:
		sort_entries(result[pos], "now")
	return result


## 並び替え：正選手が先、その中と控えはそれぞれ key（now / future / age）の順（年齢は若い順）
static func sort_entries(list: Array, key: String) -> void:
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("regular", false) != b.get("regular", false):
			return a.get("regular", false)
		if key == "age":
			return a["age"] < b["age"] if a["age"] != b["age"] else a["now"] > b["now"]
		return a[key] > b[key])


## 正選手以外の振り分け：投手は役割（先発／それ以外は中継ぎ）、野手は能力値の守備位置（無ければ守備の試合が多い位置）
static func _natural_pos(p: Dictionary) -> String:
	if p.get("is_pitcher", false):
		var pit: Variant = p.get("pitching")
		var role: String = pit.get("role", "") if pit is Dictionary and pit.get("role") != null else ""
		return "先発" if role == "先発" else "中継ぎ"
	var pos: Variant = p.get("primary_pos")
	if pos is String and pos in POSITIONS:
		return pos
	var best := ""
	var best_g := -1
	var fielding: Variant = p.get("fielding")
	if fielding is Dictionary:
		for key: String in fielding:
			var g := int(fielding[key].get("games", 0)) if fielding[key] is Dictionary else 0
			if key in POSITIONS and g > best_g:
				best = key
				best_g = g
	return best if not best.is_empty() else "外野手"


## 位置ごとのチームのランク {位置: {now, future, now_rank, future_rank, thick}}（thick は THICK_RANK 以上の人数）
static func team_ranks(depth: Dictionary) -> Dictionary:
	var result := {}
	for pos: String in POSITIONS:
		var list: Array = depth.get(pos, [])
		var n := int(REGULARS[pos])
		var backups := maxi(1, int(n * BACKUP_SHARE))
		result[pos] = {}
		for key: String in ["now", "future"]:
			# 正選手は編成どおり、控えはそのランクの高い順に重みを付ける
			var regs: Array = list.filter(func(e: Dictionary) -> bool: return e.get("regular", false))
			var rest: Array = list.filter(func(e: Dictionary) -> bool: return not e.get("regular", false))
			rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a[key] > b[key])
			if key == "future":
				# 将来は今の正選手とは限らないので、全員を将来性の高い順に並べ直して上から正選手の枠に入れる
				regs = []
				rest = list.duplicate()
				rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a[key] > b[key])
			var total := 0.0
			var weight := 0.0
			var slots := n - regs.size()
			for e: Dictionary in regs:
				total += REGULAR_WEIGHT * float(e[key])
				weight += REGULAR_WEIGHT
			for i in rest.size():
				var w := DEPTH_WEIGHT
				if i < slots:
					w = REGULAR_WEIGHT
				elif i < slots + backups:
					w = BACKUP_WEIGHT
				total += w * float(rest[i][key])
				weight += w
			var score := total / weight if weight > 0.0 else FUTURE_NONE
			result[pos][key] = score
			result[pos][key + "_rank"] = rank_of(score)
		var thick := 0
		for e: Dictionary in list:
			if rank_index(e["now_rank"]) <= rank_index(THICK_RANK):
				thick += 1
		result[pos]["thick"] = thick
		result[pos]["count"] = list.size()
	return result
