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
## 区分ごとの学年表示（専門＝専門学校。2年で卒業して入団）
const GRADE_TEXT := {"高校": "高校3年", "大学": "大学4年", "専門": "専門学校2年"}
## 社会人の入社年数（大卒か高卒かで分ける）
const COMPANY_COLLEGE_SHARE := 0.6
const COMPANY_COLLEGE_YEARS := [2, 4]
const COMPANY_HS_YEARS := [3, 5]
## 独立リーグの年齢（19〜25歳）
const INDEPENDENT_AGE := [19, 25]
## 当時の評価（作業50）：S＝競合確実の目玉、A＝1位候補。見た目の評価がしきい値以上の人数を [最少, 最多] に収める
const S_EVAL := 1.40
const S_COUNT := [2, 4]
const A_EVAL := 0.98
const A_COUNT := [4, 10]
## 競合の球団数（格付け S）
const S_BIDS := [2, 5]
## 怪物（is_monster。入団時から飛び抜けていて、まだ伸びる）の区分ごとの1年あたりの確率。年に MAX_MONSTERS 人まで
## 高校生の化け物（佐々木朗希のような。ユーザー了承 2026-11-02）は数年に1人。大学・社会人・独立からもたまに
## （ユーザー 2026-11-03「たまの化け物もいるよね？高卒にも、どこにも」）
const MONSTER_RATE := {"高校": 0.30, "大学": 0.20, "社会人": 0.12, "独立": 0.06}
const MAX_MONSTERS := 2
## 入団時の水準（作業62。tools/amateur_ratings.py の calibrate と同じ物差し）。投手は総合、野手は
## 0.35ミート＋0.35パワー＋0.1選球眼＋0.1走力＋0.1（守備−13）を投手の総合に換算（62＋1.875×（野手−60））
const BAT_MID := 60.0
const PITCH_MID := 62.0
const BAT_TO_PITCH := 1.875
## 評価ごとの入団時の総合 [上, 下]。同じ評価の中は見た目の評価の順に LEVEL_STEP ずつ下げる（下の値より下げない）
const LEVEL_READY := {"S": [79, 74], "A": [75, 70], "B": [69, 64], "C": [63, 57], "D": [56, 50]}
const LEVEL_HS := {"S": [68, 64], "A": [64, 60], "B": [59, 55], "C": [54, 49], "D": [48, 43]}
const LEVEL_STEP := 1.0
## 高卒の S・A の武器 [上, 下]（投手は奪三振、野手はパワー・走力・肩のうち元の値がいちばん目立つもの）
const WEAPON := {"S": [80, 77], "A": [76, 72]}
## 怪物の入団時：大学・社会人・独立は総合 A（80〜84）、高校は総合 B（70〜75）＋武器 A（84〜88）
const MONSTER_LEVEL_READY := [80.0, 84.0]
const MONSTER_LEVEL_HS := [70.0, 75.0]
const MONSTER_WEAPON := [84.0, 88.0]
## 年の質（豊作・不作）→ その年の全員を quality × QUALITY_SHIFT（±QUALITY_SHIFT_MAX まで）上下。
## 評価 B 以下はその倍（豊作の年は中位の層も厚い）。S・A は不作の年でも −1 まで（その年の一番上を78前後に保つ）
const QUALITY_SHIFT := 8.0
const QUALITY_SHIFT_MAX := 2.0
## 個々の能力と総合の上限（入団時の A 以上は怪物だけ。上限の手前 CAP_KNEE から上は伸びを CAP_SOFTNESS に縮める）
const RATING_CAP := 79.0
const SPEED_CAP := 85.0
const CAP_KNEE := 7.0
const CAP_SOFTNESS := 0.4
## 高卒の野手の武器の選び方：元の値がこの中央よりいちばん上に出ているもの
const WEAPON_MEDIAN := {"power": 52.0, "speed": 57.0, "arm": 64.0}
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
## 名前はありふれた姓・下の名前だけ（作業50。実在のスター選手に特有の名前や、姓のような下の名前は使わない）。
## さらに実在の名選手（転生のもと）と同じ姓名は作らない（_unique_name）
const SURNAMES := [
	"佐藤", "鈴木", "高橋", "田中", "渡辺", "伊藤", "山本", "中村", "小林", "加藤",
	"吉田", "山田", "佐々木", "山口", "松本", "井上", "斉藤", "木村", "林", "清水",
	"山崎", "森", "池田", "橋本", "阿部", "石川", "山下", "中島", "石井", "小川",
	"前田", "岡田", "長谷川", "藤田", "後藤", "近藤", "村上", "遠藤", "青木", "坂本",
	"福田", "太田", "西村", "藤井", "岡本", "金子", "藤原", "三浦", "中野", "松田",
	"原田", "竹内", "小野", "田村", "柴田", "中山", "和田", "石田", "森田", "上田",
	"原", "内田", "酒井", "横山", "高木", "安藤", "宮崎", "工藤", "島田", "大野",
	"野口", "松井", "菅原", "久保", "千葉", "岩崎", "桜井", "野村", "杉山", "平野",
]
const GIVEN_NAMES := [
	"拓也", "健太", "大輝", "拓真", "航平", "蓮", "悠真", "湊", "大翔", "陽翔",
	"樹", "陸", "颯真", "悠人", "涼太", "優斗", "翼", "翔太", "隼人", "颯太",
	"大樹", "真一", "和也", "雄大", "直樹", "亮", "健司", "哲也", "誠", "剛",
	"勇気", "康平", "達也", "龍之介", "健太郎", "祐樹", "裕也", "光", "俊介", "海斗",
	"悠斗", "大和", "蒼", "結翔", "奏太", "瑛太", "匠", "智也", "圭太", "浩二",
	"一輝", "大地", "将太", "啓太", "春樹", "竜也", "晴人", "優希", "駿", "拓海",
	"遼", "雅人", "翔吾", "敦也", "陽介", "孝太", "健一", "直人", "亮太", "裕太",
]

var data: Dictionary
var _pool: Dictionary = {}
var _by_band: Dictionary = {}
var _schools: Dictionary = {}
var _serial: int = 0
var _derived: Dictionary = {}
var _talent: FictionalTalent
var _last_quality: float = 0.0
## 実在の名選手の姓名（空白を除く）。架空の候補の名前に使わない
var _real_names: Dictionary = {}


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
	for l: Dictionary in data.get("legends", []):
		_real_names[str(l.get("name", "")).replace(" ", "").replace("　", "")] = true


static func load_data() -> Dictionary:
	var bundled := "res://data/generated".path_join(DATA_FILE)
	if FileAccess.file_exists(bundled):
		var bp: Variant = JSON.parse_string(FileAccess.get_file_as_string(bundled))
		if bp is Dictionary:
			return bp
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
	var monsters := _monster_slots(picks, rng)
	picks.append_array(_pick_templates(int(size["ikusei"]), true, rng))

	# 各候補を FictionalTalent で生成
	var raw_candidates: Array = []
	for i in picks.size():
		var c := _make_v2(picks[i], draft_year, quality, rng, taken, monsters.has(i))
		raw_candidates.append(c)

	# スカウトの見た目の評価（apparent_eval）順にソートして順位帯（1位、上位、中位、下位、育成）を決定
	# （真の才能 T が高くても、見た目評価で下位に落ちる「隠れた逸材」が自然発生する）。怪物はいちばん上
	var reg_count := int(size["reg"])
	raw_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["is_monster"]) != bool(b["is_monster"]):
			return bool(a["is_monster"])
		return float(a["_apparent_eval"]) > float(b["_apparent_eval"])
	)
	# 当時の評価 S・A の人数（しきい値以上の人数を範囲に収める。怪物は必ず S）
	var s_n := 0
	var a_n := 0
	for i in mini(reg_count, raw_candidates.size()):
		var c: Dictionary = raw_candidates[i]
		if bool(c["is_monster"]) or float(c["_apparent_eval"]) >= S_EVAL:
			s_n += 1
		elif float(c["_apparent_eval"]) >= A_EVAL:
			a_n += 1
	s_n = clampi(s_n, S_COUNT[0], S_COUNT[1])
	for i in raw_candidates.size():
		if bool(raw_candidates[i]["is_monster"]):
			s_n = maxi(s_n, i + 1)
	a_n = clampi(a_n, A_COUNT[0], A_COUNT[1])

	var level_seen := {}
	var ready_top := false
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
			grade = "S" if rank_in_reg <= s_n else ("A" if rank_in_reg <= s_n + a_n else "B")
			as_round = 1
			projected = "1位候補"
		elif rank_in_reg <= 36:
			band = "2-3"
			grade = "A" if rank_in_reg <= s_n + a_n else "B"
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

		# 入団時の水準。S が高卒だけの年は、大学・社会人などのいちばん上（A）を S の水準にする（その年の一番上を78前後に）
		var lv_grade := grade
		if p["category"] != "高校" and not is_ikusei:
			if not ready_top and grade == "A":
				lv_grade = "S"
			ready_top = true
		var lv_key := "%s/%s" % [p["category"] == "高校", lv_grade]
		_calibrate_entry(p, lv_grade, int(level_seen.get(lv_key, 0)), quality, rng)
		level_seen[lv_key] = int(level_seen.get(lv_key, 0)) + 1

		var bids := rng.randi_range(S_BIDS[0], S_BIDS[1]) if grade == "S" else 1

		# amateur 辞書に反映
		var am: Dictionary = p["amateur"]
		am["band"] = band
		am["grade"] = grade
		am["as_round"] = as_round
		am["as_ikusei"] = is_ikusei
		am["bids"] = bids
		am["projected"] = projected

		# 怪物の強調（高校生は「超目玉」、大学・社会人は「超目玉（即戦力）」）
		if bool(p.get("is_monster", false)) and not is_ikusei:
			am["projected"] = "超目玉" if p["category"] == "高校" else "超目玉（即戦力）"
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


## 本指名のひな形 picks のうち、怪物にする添字（高校生の化け物・大学／社会人の即戦力の怪物を、それぞれの確率で0〜1人）
func _monster_slots(picks: Array, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for cat: String in MONSTER_RATE:
		if rng.randf() >= float(MONSTER_RATE[cat]):
			continue
		var idx: Array = []
		for i in picks.size():
			if str(picks[i]["category"]) == cat:
				idx.append(i)
		if not idx.is_empty():
			out[idx[rng.randi_range(0, idx.size() - 1)]] = true
	while out.size() > MAX_MONSTERS:
		out.erase(out.keys()[rng.randi_range(0, out.size() - 1)])
	return out


## 入団時の総合（投手の総合の物差し。野手は換算。tools/amateur_ratings.py の entry_level と同じ）
static func entry_level(p: Dictionary) -> float:
	if bool(p.get("is_pitcher", false)) and p.get("pitching") is Dictionary:
		return _rv(p["pitching"]["ratings"], "overall", 45.0)
	var r: Dictionary = p["batting"]["ratings"] if p.get("batting") is Dictionary else {}
	return PITCH_MID + BAT_TO_PITCH * (_bat_composite(r) - BAT_MID)


static func _rv(r: Dictionary, k: String, fallback: float) -> float:
	var x: Variant = r.get(k)
	return float(x["value"]) if x is Dictionary and x.get("value") != null else fallback


static func _bat_composite(r: Dictionary) -> float:
	return 0.35 * _rv(r, "meet", 45.0) + 0.35 * _rv(r, "power", 45.0) + 0.1 * _rv(r, "eye", 45.0) \
		+ 0.1 * _rv(r, "speed", 45.0) + 0.1 * (_rv(r, "defense", 63.0) - 13.0)


static func _set_rating(r: Dictionary, k: String, v: float) -> void:
	var iv := clampi(roundi(v), 1, 100)
	r[k] = {"value": iv, "rank": FictionalTalent._ability_rank(iv)}


static func _soft_cap(v: float, cap: float) -> float:
	var knee := cap - CAP_KNEE
	return minf(cap, v if v <= knee else knee + (v - knee) * CAP_SOFTNESS)


static func _shift_ratings(r: Dictionary, keys: Array, delta: float, cap: float) -> void:
	if absf(delta) < 0.5:
		return
	for k: String in keys:
		if r.get(k) is Dictionary:
			var lim := SPEED_CAP if k == "speed" else cap
			_set_rating(r, k, maxf(20.0, _soft_cap(float(r[k]["value"]) + delta, lim)))


## keys（走力は半分）を動かして野手の値を target（投手の物差し）に合わせる
static func _fit_batter(r: Dictionary, target: float, keys: Array, cap: float) -> void:
	var goal := BAT_MID + (target - PITCH_MID) / BAT_TO_PITCH
	var weight := {"meet": 0.35, "power": 0.35, "eye": 0.1, "speed": 0.05}
	for _i in 12:
		var d := goal - _bat_composite(r)
		if absf(d) < 0.3:
			break
		var w := 0.0
		var main: Array = []
		for k: String in keys:
			w += float(weight.get(k, 0.0))
			if k != "speed":
				main.append(k)
		var step := d / maxf(0.2, w)
		_shift_ratings(r, main, step, cap)
		if "speed" in keys:
			_shift_ratings(r, ["speed"], step / 2.0, cap)


## 入団時の能力を評価の水準にそろえる（作業62）。能力の形は残して全体を上下し、高卒の上位には武器を1つ付ける。
## i は同じ区分（高校／それ以外）・同じ評価の中の順（見た目の評価の順）。ピークは入団時を下回らないようにだけする
func _calibrate_entry(p: Dictionary, grade: String, i: int, quality: float, rng: RandomNumberGenerator) -> void:
	var hs := str(p["category"]) == "高校"
	var shift := clampf(quality * QUALITY_SHIFT, -QUALITY_SHIFT_MAX, QUALITY_SHIFT_MAX)
	var target: float
	var weapon := -1.0
	if bool(p.get("is_monster", false)):
		var mlv: Array = MONSTER_LEVEL_HS if hs else MONSTER_LEVEL_READY
		target = rng.randf_range(mlv[0], mlv[1])
		if hs:
			weapon = rng.randf_range(MONSTER_WEAPON[0], MONSTER_WEAPON[1])
	else:
		var lv: Array = (LEVEL_HS if hs else LEVEL_READY)[grade]
		var deep := grade in ["B", "C", "D"]
		target = minf(RATING_CAP, maxf(lv[1], lv[0] - LEVEL_STEP * i) + (2.0 * shift if deep else maxf(shift, -1.0)))
		if hs and WEAPON.has(grade):
			weapon = maxf(WEAPON[grade][1], WEAPON[grade][0] - LEVEL_STEP * i) + shift
	target = roundf(target)
	var cap := maxf(RATING_CAP, target)
	var part: Dictionary
	if bool(p["is_pitcher"]):
		part = p["pitching"]
		var pr: Dictionary = part["ratings"]
		_shift_ratings(pr, ["overall", "k9", "bb9", "hr9"], target - _rv(pr, "overall", 45.0), cap)
		_set_rating(pr, "overall", target)
		if weapon > 0.0:
			_set_rating(pr, "k9", maxf(_rv(pr, "k9", 0.0), weapon))
	else:
		part = p["batting"]
		var br: Dictionary = part["ratings"]
		var keys: Array = ["meet", "power", "eye", "speed"]
		_fit_batter(br, target, keys, cap)
		if weapon > 0.0:
			var wk := "power"
			for k: String in WEAPON_MEDIAN:
				if _rv(br, k, 0.0) - float(WEAPON_MEDIAN[k]) > _rv(br, wk, 0.0) - float(WEAPON_MEDIAN[wk]):
					wk = k
			_set_rating(br, wk, maxf(_rv(br, wk, 0.0), weapon))
			keys.erase(wk)
			_fit_batter(br, target, keys, cap)
		var f: Dictionary = p.get("fielding", {}).get(p["primary_pos"], {})
		for k: String in ["defense", "arm"]:
			if not f.is_empty() and br.get(k) is Dictionary:
				f[k] = br[k].duplicate()
	var peak: Dictionary = p.get("growth", {}).get("peak", {})
	for k: String in part["ratings"]:
		if peak.has(k) and part["ratings"][k] is Dictionary:
			peak[k] = maxf(float(peak[k]), float(part["ratings"][k]["value"]))


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
		rng: RandomNumberGenerator, taken: Dictionary, monster: bool = false) -> Dictionary:
	_serial += 1
	var category: String = t["category"]
	var pos: String = t["pos"]
	var side: String = t["side"]

	# FictionalTalent で能力とプロファイルを生成
	var gen: Dictionary = _talent.generate_player(category, pos, side, quality, rng, {"monster": monster})

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
		"高校", "大学", "専門":
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
		if not taken.has(n) and not _real_names.has(n.replace(" ", "")):
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
