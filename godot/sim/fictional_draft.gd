class_name FictionalDraft
extends RefCounted
## 2028年以降の架空のドラフト候補を作る（docs/AUTORUN.md 作業22）。
## v2: FictionalTalent（潜在因子モデル＋スコア拘束射影＋分位点較正）により、
## 多様な個性（ロマン砲、天才打者、俊足堅守、剛腕、精密機械、即戦力の怪物、二刀流）を
## 長期インフレゼロで生成する。

const DATA_FILE := "fictional_draft.json"
const FIRST_YEAR := 2028
const HIT_MODES := {"historical": "史実どおり", "dream": "夢多め"}
## 高校の大会の見出しに使う言葉（架空の候補の紹介文・ニュース）
const TYPE_WORDS := {
	"P_power": "本格派", "P_control": "技巧派", "P_fast": "剛腕", "P_lefty": "左腕", "P_righty": "右腕",
	"B_power": "スラッガー", "B_contact": "巧打者", "B_speed": "俊足", "B_defense": "守備の名手", "B_catcher": "強肩捕手",
}
## 区分ごとの学年表示
const GRADE_TEXT := {"高校": "高校3年", "大学": "大学4年"}
## 社会人の入社年数（大卒か高卒かで分ける）
const COMPANY_COLLEGE_SHARE := 0.6
const COMPANY_COLLEGE_YEARS := [2, 4]
const COMPANY_HS_YEARS := [3, 5]
## 独立リーグの年齢（19〜25歳）
const INDEPENDENT_AGE := [19, 25]
## 1位の帯のうち、競合の目玉（格付け S）の割合と競合の球団数
const S_SHARE := 0.25
const S_BIDS := [2, 5]
## 転生選手の出現確率（人数分布）
const REINCARNATION_ODDS := [0.65, 0.25, 0.08, 0.02]
## 転生選手の高校／大学の割合
const REINCARNATION_HIGH_SCHOOL := 0.60
const REINCARNATION_SAME_SCHOOL := 0.40
const REINCARNATION_SCALE := [0.85, 1.05]
const REINCARNATION_NOISE := 2.5
## 夢多め（作業22。hits == "dream" で S級の候補を増やす）
const DREAM_EXTRA := [2, 4]
const DREAM_MIN_SCORE := 1.6
## 無名校の掘り出し物（GEM_RATE で下位に A級の選手を1人混ぜる）
const GEM_RATE := 0.20
const GEM_MIN_SCORE := 0.8
## 上位の目玉がメジャー志望を表明する確率
const MLB_INTENT_ODDS := [0.80, 0.16, 0.04]
## 強豪校判定
const STRONG_SCHOOL := 8
const SCHOOL_WEIGHT_POWER := 0.6

const GROWTH_TYPES := {"早熟": 25, "普通": 27, "晩成": 29}
const SURNAMES := [
	"佐藤", "鈴木", "高橋", "田中", "渡辺", "伊藤", "山本", "中村", "小林", "加藤",
	"吉田", "山田", "佐々木", "山口", "松本", "井上", "斉藤", "木村", "林", "清水",
	"山崎", "森", "池田", "橋本", "阿部", "石川", "山下", "中島", "石井", "小川",
	"前田", "岡田", "長谷川", "藤田", "後藤", "近藤", "村上", "遠藤", "青木", "坂本",
	"斉藤", "福田", "太田", "西村", "藤井", "岡本", "金子", "藤原", "三浦", "中野",
	"原田", "竹内", "小野", "田村", "柴田", "中山", "和田", "石田", "森田", "上田",
	"原", "内田", "柴田", "酒井", "横山", "高木", "安藤", "宮崎", "工藤", "島田",
]
const GIVEN_NAMES := [
	"翔平", "大谷", "由伸", "朗希", "宗佑磨", "宗隆", "輝明", "晃平", "拓也", "健太",
	"大輝", "拓真", "航平", "蓮", "悠真", "湊", "大翔", "陽翔", "朝陽", "樹",
	"陸", "颯真", "悠人", "蒼空", "涼太", "優斗", "翼", "翔太", "隼人", "颯太",
	"大樹", "真一", "和也", "雄大", "直樹", "亮", "健司", "哲也", "誠", "剛",
	"勇気", "慎太郎", "康平", "達也", "龍之介", "健太郎", "祐樹", "裕也", "光", "俊介",
]

var data: Dictionary
var _pool: Dictionary = {}
var _by_band: Dictionary = {}
var _schools: Dictionary = {}
var _serial: int = 0
var _derived: Dictionary = {}
var _talent: FictionalTalent
var _last_quality: float = 0.0


func _init(fictional_data: Dictionary = {}, growth: Growth = null) -> void:
	data = fictional_data if not fictional_data.is_empty() else load_data()
	for t: Dictionary in data.get("templates", []):
		var key := "%s|%s|%s" % [t["category"], t["band"], t["side"]]
		if not _pool.has(key):
			_pool[key] = []
		_pool[key].append(t)
		var bkey := "%s|%s" % [t["band"], t["side"]]
		if not _by_band.has(bkey):
			_by_band[bkey] = []
		_by_band[bkey].append(t)
	for s: Dictionary in data.get("schools", []):
		var cat: String = s["category"]
		if not _schools.has(cat):
			_schools[cat] = []
		_schools[cat].append([str(s["name"]), pow(float(s["count"]), SCHOOL_WEIGHT_POWER), int(s["count"])])
	var g := growth if growth != null else Growth.new()
	_derived = g.coeff.get("pitching", {}).get("derived", {}).get("overall", {})
	_talent = FictionalTalent.new()


static func load_data() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../generated").path_join(DATA_FILE).simplify_path()
	if not FileAccess.file_exists(path):
		push_error("架空のドラフト候補のひな形がありません: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func is_ready() -> bool:
	return not data.get("templates", []).is_empty()


static func is_fictional_amateur(p: Dictionary) -> bool:
	var am: Variant = p.get("amateur")
	return am is Dictionary and bool(am.get("fictional", false))


static func reincarnation_of(p: Dictionary) -> Dictionary:
	var am: Variant = p.get("amateur")
	if am is Dictionary and am.get("reincarnation") is Dictionary:
		return am["reincarnation"]
	return {}


## draft_year 年秋のドラフト候補をまとめて作る
func generate_year(draft_year: int, rng: RandomNumberGenerator, opts: Dictionary = {}) -> Array:
	var sizes: Dictionary = data.get("class_sizes", {})
	var keys: Array = sizes.keys()
	var size: Dictionary = sizes[keys[rng.randi_range(0, keys.size() - 1)]] if not keys.is_empty() \
		else {"reg": 75, "ikusei": 40}
	var taken: Dictionary = opts.get("taken_names", {}).duplicate()
	var out: Array = []

	# 年の質（豊作・不作の波）を更新
	_last_quality = FictionalTalent.next_class_quality(_last_quality, rng)
	var quality := _last_quality

	# ひな形から区分・守備位置の構成をサンプリング
	var picks := _pick_templates(int(size["reg"]), false, rng)
	picks.append_array(_pick_templates(int(size["ikusei"]), true, rng))

	# 各候補を FictionalTalent で生成
	var raw_candidates: Array = []
	for t: Dictionary in picks:
		var c := _make_v2(t, draft_year, quality, rng, taken)
		raw_candidates.append(c)

	# スカウトの見た目の評価（apparent_eval）順にソートして順位帯（1位、上位、中位、下位、育成）を決定
	# （真の才能 T が高くても、見た目評価で下位に落ちる「隠れた逸材」が自然発生する）
	var reg_count := int(size["reg"])
	raw_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["_apparent_eval"]) > float(b["_apparent_eval"])
	)

	for i in raw_candidates.size():
		var p: Dictionary = raw_candidates[i]
		var is_ikusei := (i >= reg_count)
		var rank_in_reg := i + 1

		var band: String
		var grade: String
		var as_round: int
		var projected: String

		if is_ikusei:
			band = "育成"
			grade = "D"
			as_round = 1
			projected = "育成枠"
		elif rank_in_reg <= 12:
			band = "1"
			grade = "S" if (float(p["_apparent_eval"]) >= 1.2 or (rank_in_reg <= 3 and rng.randf() < 0.5)) else "A"
			as_round = 1
			projected = "1位候補"
		elif rank_in_reg <= 36:
			band = "2-3"
			grade = "B"
			as_round = rng.randi_range(2, 3)
			projected = "上位候補"
		elif rank_in_reg <= 60:
			band = "4-5"
			grade = "C"
			as_round = rng.randi_range(4, 5)
			projected = "中位候補"
		else:
			band = "6-"
			grade = "C" if rng.randf() < 0.3 else "D"
			as_round = rng.randi_range(6, 8)
			projected = "下位候補"

		var bids := rng.randi_range(S_BIDS[0], S_BIDS[1]) if grade == "S" else 1

		# amateur 辞書に反映
		var am: Dictionary = p["amateur"]
		am["band"] = band
		am["grade"] = grade
		am["as_round"] = as_round
		am["as_ikusei"] = is_ikusei
		am["bids"] = bids
		am["projected"] = projected

		# 即戦力の怪物の強調
		if bool(p.get("is_monster", false)) and not is_ikusei:
			am["grade"] = "S"
			am["projected"] = "超目玉（即戦力）"
			am["bids"] = maxi(am["bids"], rng.randi_range(3, 6))

		# 二刀流の二つ名反映
		am["type"] = FictionalTalent.decide_player_type(p)
		am["intro"] = intro_of(p)

		# 作業用キーを削除
		p.erase("_apparent_eval")
		out.append(p)

	# 夢多め・掘り出し物の追加処理（旧オプション互換）
	if str(opts.get("hits", "historical")) == "dream":
		_add_dream(out, rng)
	if rng.randf() < GEM_RATE:
		_add_gem(out, rng)

	# 転生選手
	var legends: Array = opts.get("legends", [])
	if not legends.is_empty():
		var n := _count_from(REINCARNATION_ODDS, rng)
		var pool := legends.duplicate()
		for i in mini(n, pool.size()):
			var j := rng.randi_range(0, pool.size() - 1)
			out.append(make_reincarnation(pool[j], draft_year, rng))
			pool.remove_at(j)

	_mark_mlb_intent(out, rng)

	# クラス全体から二刀流候補を年間枠（ポアソン分布・上限2人）で適性に基づき選出して副次能力を付与
	_talent.assign_two_way_for_class(out, rng)
	for p: Dictionary in out:
		var tw: Dictionary = p.get("two_way", {})
		if bool(tw.get("active", false)):
			p["amateur"]["type"] = FictionalTalent.decide_player_type(p)
			p["amateur"]["intro"] = intro_of(p)

	return out


func _pick_templates(n: int, ikusei: bool, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for t: Dictionary in data.get("templates", []):
		if bool(t["ikusei"]) == ikusei:
			pool.append(t)
	var out: Array = []
	if pool.is_empty():
		return out
	for i in n:
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


## 新世代生成エンジンによる1人の生成
func _make_v2(t: Dictionary, draft_year: int, quality: float,
		rng: RandomNumberGenerator, taken: Dictionary) -> Dictionary:
	_serial += 1
	var category: String = t["category"]
	var pos: String = t["pos"]
	var side: String = t["side"]

	# FictionalTalent で能力とプロファイルを生成
	var gen: Dictionary = _talent.generate_player(category, pos, side, quality, rng)

	var p: Dictionary = {}
	p["id"] = "fic:%d:%03d" % [draft_year, _serial]
	p["provisional_id"] = false
	p["name"] = _unique_name(rng, taken)
	p["is_pitcher"] = (side == "P")
	p["primary_pos"] = pos
	p["side"] = side
	p["category"] = category
	p["is_monster"] = gen.get("is_monster", false)
	p["two_way"] = gen.get("two_way", {})

	# 投打の利き腕、体格
	p["throws"] = "左" if rng.randf() < (0.28 if side == "P" else 0.12) else "右"
	p["bats"] = "左" if (rng.randf() < 0.45 or p["throws"] == "左") else "右"
	p["height"] = rng.randi_range(175, 192) if side == "P" else rng.randi_range(172, 188)
	p["weight"] = roundi(float(p["height"]) * rng.randf_range(0.44, 0.52))

	var school := _school(category, rng)
	var strong := int(school[1]) >= STRONG_SCHOOL
	_fill_common(p, draft_year, school[0])

	var entry := _entry_of(category, rng)
	p["birth"] = _birth(draft_year + 1, int(entry["age"]), rng)

	# 能力値の格納
	var player_data: Dictionary = gen["player"]
	if side == "P":
		p["pitching"] = player_data
		p["batting"] = {"ratings": {}, "trajectory": 1, "sample": {"pa_1": 0.0, "pa_2": 0.0}}
	else:
		p["batting"] = player_data
		p["pitching"] = null
		p["fielding"] = {}
		# 守備適性
		var def_val: int = int(player_data.get("ratings", {}).get("defense", {}).get("value", 50))
		var arm_val: int = int(player_data.get("ratings", {}).get("arm", {}).get("value", 50))
		p["fielding"][pos] = {"games": 0, "defense": {"value": def_val, "rank": FictionalTalent._ability_rank(def_val)}, "arm": {"value": arm_val, "rank": FictionalTalent._ability_rank(arm_val)}}

	# 成長情報
	p["growth"] = gen["growth"]

	# アマチュア情報（ドラフト画面用）
	p["amateur"] = {
		"draft_year": draft_year, "category": category, "school": school[0],
		"grade_text": entry["text"], "entry_age": entry["age"],
		"future_score": float(gen["true_talent"]), "fictional": true, "strong_school": strong,
		"template_year": int(t["year"]), "two_way": p["two_way"],
	}

	p["_apparent_eval"] = float(gen["apparent_eval"])
	return p


## 転生選手を1人作る
func make_reincarnation(legend: Dictionary, draft_year: int, rng: RandomNumberGenerator) -> Dictionary:
	var side: String = legend["side"]
	var category := "高校" if rng.randf() < REINCARNATION_HIGH_SCHOOL else "大学"
	var key := "%s|1|%s" % [category, side]
	var pool: Array = _pool.get(key, _by_band.get("1|%s" % side, []))
	var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else {"year": 2010}
	var p: Dictionary = {}
	_serial += 1
	var school := _school(category, rng)
	for s: Variant in legend.get("schools", []):
		var known := _school_count(category, str(s))
		if known > 0 and rng.randf() < REINCARNATION_SAME_SCHOOL:
			school = [str(s), known]
	p["id"] = "rei:%d:%s" % [draft_year, legend["id"]]
	p["provisional_id"] = false
	p["name"] = legend["name"]
	p["is_pitcher"] = (side == "P")
	p["primary_pos"] = legend.get("primary_pos", "投手" if side == "P" else "外野手")
	p["side"] = side
	p["category"] = category
	p["throws"] = str(legend.get("throws", "右"))
	p["bats"] = str(legend.get("bats", "右"))
	p["height"] = int(legend.get("height", 180))
	p["weight"] = int(legend.get("weight", 80))

	var entry := _entry_of(category, rng)
	_fill_common(p, draft_year, school[0])
	p["birth"] = _birth(draft_year + 1, int(entry["age"]), rng)

	var scale := rng.randf_range(REINCARNATION_SCALE[0], REINCARNATION_SCALE[1])
	var peak := {}
	for k: String in legend["peak"]:
		var v := float(legend["peak"][k])
		if k == "velocity":
			peak[k] = v + rng.randfn(0.0, 2.0)
		else:
			peak[k] = SimPlayer.SCALE_MEAN + (v - SimPlayer.SCALE_MEAN) * scale + rng.randfn(0.0, REINCARNATION_NOISE)

	if side == "B":
		p["batting"] = {"ratings": {}, "sample": {"pa_1": 0.0, "pa_2": 0.0}, "trajectory": 3}
		for k: String in ["meet", "power", "eye", "speed", "defense", "arm"]:
			var pk: float = float(peak.get(k, 50))
			var ent: int = clampi(roundi(pk - 15.0 + rng.randfn(0.0, 3.0)), 20, 99)
			p["batting"]["ratings"][k] = {"value": ent, "rank": FictionalTalent._ability_rank(ent)}
		p["pitching"] = null
		p["fielding"] = {}
		var def_val: int = int(p["batting"]["ratings"]["defense"]["value"])
		var arm_val: int = int(p["batting"]["ratings"]["arm"]["value"])
		p["fielding"][p["primary_pos"]] = {"games": 0, "defense": {"value": def_val, "rank": FictionalTalent._ability_rank(def_val)}, "arm": {"value": arm_val, "rank": FictionalTalent._ability_rank(arm_val)}}
	else:
		p["pitching"] = {"ratings": {}, "velocity": {"kmh": roundi(float(peak.get("velocity", 145)) - 4.0), "source": "fictional"}, "role": legend.get("role", "先発"), "sample": {"outs_1": 0.0, "outs_2": 0.0}}
		for k: String in ["overall", "stamina", "k9", "bb9", "hr9"]:
			var pk: float = float(peak.get(k, 50))
			var ent: int = clampi(roundi(pk - 14.0 + rng.randfn(0.0, 3.0)), 20, 99)
			p["pitching"]["ratings"][k] = {"value": ent, "rank": FictionalTalent._ability_rank(ent)}
		p["batting"] = {"ratings": {}, "trajectory": 1, "sample": {"pa_1": 0.0, "pa_2": 0.0}}

	var gtype := _growth_type(legend.get("peak_age"))
	p["growth"] = {"type": gtype, "peak_age": _peak_age(legend.get("peak_age"), gtype), "peak": peak}
	var grade := "S" if float(legend["score"]) >= DREAM_MIN_SCORE or rng.randf() < 0.5 else "A"
	p["amateur"] = {
		"draft_year": draft_year, "category": category, "school": school[0], "grade": grade,
		"grade_text": entry["text"], "entry_age": entry["age"], "as_round": 1, "as_ikusei": false,
		"bids": rng.randi_range(S_BIDS[0], S_BIDS[1]) if grade == "S" else 1,
		"future_score": float(legend["score"]) * scale + rng.randfn(0.0, 0.15), "fictional": true,
		"strong_school": int(school[1]) >= STRONG_SCHOOL, "projected": "1位候補", "template_year": int(t.get("year", 2010)),
		"reincarnation": {"id": legend["id"], "name": legend["name"], "peak_year": int(legend["peak_year"]),
			"peak_team": str(legend.get("peak_team", "")), "school": "・".join(legend.get("schools", []))},
	}
	p["amateur"]["type"] = type_word(p)
	p["amateur"]["intro"] = "「%sの再来」と話題の%s" % [legend["name"], p["amateur"]["type"]]
	return p


func _add_dream(out: Array, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(DREAM_EXTRA[0], DREAM_EXTRA[1])
	var upper: Array = []
	for p: Dictionary in out:
		if p["amateur"]["grade"] in ["S", "A", "B"] and float(p["amateur"]["future_score"]) < DREAM_MIN_SCORE:
			upper.append(p)
	for i in mini(n, upper.size()):
		var j := rng.randi_range(0, upper.size() - 1)
		var p: Dictionary = upper[j]
		p["amateur"]["future_score"] = DREAM_MIN_SCORE + rng.randf_range(0.1, 0.4)
		p["amateur"]["dream"] = true
		upper.remove_at(j)


func _add_gem(out: Array, rng: RandomNumberGenerator) -> void:
	var low: Array = []
	for p: Dictionary in out:
		var am: Dictionary = p["amateur"]
		if (bool(am.get("as_ikusei", false)) or int(am.get("as_round", 1)) >= 6):
			low.append(p)
	if low.is_empty():
		return
	var p: Dictionary = low[rng.randi_range(0, low.size() - 1)]
	var am: Dictionary = p["amateur"]
	am["future_score"] = float(am.get("future_score", 0.0)) + rng.randf_range(0.8, 1.4)
	p["growth"]["type"] = "晩成"
	p["growth"]["peak_age"] = 30
	am["gem"] = true
	am["type"] = type_word(p)
	am["intro"] = "「隠れた逸材」とプロ注目の%s" % am["type"]


func _mark_mlb_intent(out: Array, rng: RandomNumberGenerator) -> void:
	var n := _count_from(MLB_INTENT_ODDS, rng)
	var top: Array = []
	for p: Dictionary in out:
		if p["amateur"]["grade"] in ["S", "A"]:
			top.append(p)
	for i in mini(n, top.size()):
		var j := rng.randi_range(0, top.size() - 1)
		var am: Dictionary = top[j]["amateur"]
		am["mlb_intent"] = {"stated": true, "note": "%sの%s、高校・大学からのメジャー挑戦を表明" % [am["school"], top[j]["name"]]}
		top.remove_at(j)


func _entry_of(category: String, rng: RandomNumberGenerator) -> Dictionary:
	match category:
		"高校", "大学":
			return {"age": int(Growth.AMATEUR_ENTRY_AGE[category]), "text": GRADE_TEXT[category]}
		"社会人":
			var college := rng.randf() < COMPANY_COLLEGE_SHARE
			var years := rng.randi_range(COMPANY_COLLEGE_YEARS[0], COMPANY_COLLEGE_YEARS[1]) if college \
				else rng.randi_range(COMPANY_HS_YEARS[0], COMPANY_HS_YEARS[1])
			return {"age": (22 if college else 18) + years, "text": "入社%d年目" % years}
	return {"age": rng.randi_range(INDEPENDENT_AGE[0], INDEPENDENT_AGE[1]), "text": "1年目"}


static func _birth(year: int, age: int, rng: RandomNumberGenerator) -> String:
	var month := rng.randi_range(1, 12)
	var day := rng.randi_range(1, 28)
	var after_april1 := month > 4 or (month == 4 and day > 1)
	return "%04d-%02d-%02d" % [year - age - (1 if after_april1 else 0), month, day]


func _fill_common(p: Dictionary, draft_year: int, school: String) -> void:
	p["birth"] = null
	p["draft"] = "%d年ドラフト候補" % draft_year
	p["career"] = school
	p["team"] = ""
	p["team_id"] = null
	p["hist_team"] = ""
	p["salary_man"] = 1000
	p["years_pro"] = 0
	p["service_days"] = 0


func _school(category: String, rng: RandomNumberGenerator) -> Array:
	var list: Array = _schools.get(category, _schools.get("社会人", []))
	if list.is_empty():
		return ["無名校", 1]
	var total := 0.0
	for s: Array in list:
		total += float(s[1])
	var roll := rng.randf() * total
	var cum := 0.0
	for s: Array in list:
		cum += float(s[1])
		if roll <= cum:
			return [str(s[0]), int(s[2])]
	return [str(list[0][0]), int(list[0][2])]


func _school_count(category: String, name: String) -> int:
	for s: Array in _schools.get(category, []):
		if s[0] == name:
			return int(s[2])
	return 0


func _unique_name(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for i in 200:
		var n := "%s %s" % [SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)],
			GIVEN_NAMES[rng.randi_range(0, GIVEN_NAMES.size() - 1)]]
		if not taken.has(n):
			taken[n] = true
			return n
	return "架空 %d" % rng.randi_range(1000, 9999)


static func _growth_type(peak_age: Variant) -> String:
	if peak_age == null:
		return "普通"
	var a := int(peak_age)
	if a <= 25:
		return "早熟"
	if a >= 29:
		return "晩成"
	return "普通"


static func _peak_age(peak_age: Variant, gtype: String) -> int:
	if peak_age == null:
		return GROWTH_TYPES[gtype]
	return int(peak_age)


static func _count_from(odds: Array, rng: RandomNumberGenerator) -> int:
	var u := rng.randf()
	for i in odds.size():
		u -= float(odds[i])
		if u < 0.0:
			return i
	return odds.size() - 1


static func type_word(p: Dictionary) -> String:
	return FictionalTalent.decide_player_type(p)


static func intro_of(p: Dictionary) -> String:
	var am: Dictionary = p.get("amateur", {})
	var sch: String = str(am.get("school", ""))
	var t_word: String = str(am.get("type", type_word(p)))
	return "%sの%s" % [sch, t_word]
