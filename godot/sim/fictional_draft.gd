class_name FictionalDraft
extends RefCounted
## 架空のドラフト候補（史実の無い年＝FIRST_YEAR〜。docs/AUTORUN.md 作業22）と転生選手（作業32）。
##
## ひな形は generated/fictional_draft.json（tools/fictional_draft.py が 2008〜2020年の実際の指名選手から作る）：
## 1人ずつの「区分（高校・大学・社会人・独立）・順位の帯・守備位置・入団時の能力・その後のピーク・ピークの年齢・将来性の点」。
## 1年分の候補は、直近10年のどれか1年の本指名・育成の人数だけ、区分×順位の帯の割合どおりにひな形を選んで作る
## （能力の分布・当たり外れの頻度が史実の指名選手と同じになる）。名前は架空、出身校・所属は実在（史実の指名の人数で重み付け）。
## - 「当時の評価」はひな形の順位（史実の指名順位＝ピークがぼやけて見えた評価）。「将来性」はひな形の点（ピーク）を
##   Draft が難易度のノイズ付きで見せる
## - 選手は能力値ファイルの選手と同じ形で、`growth`（{type, peak_age, peak}。作業27の Growth がピークへ育てる）と
##   `amateur`（{draft_year, intro, grade, as_round, bids, future_score, category, school, fictional, mlb_intent, reincarnation}）が付く
## - 当たりの頻度（GameState.fictional_hits）："historical"＝ひな形のまま／"dream"＝S級のピークの大物を年に DREAM_EXTRA 人足す
## - 無名校の掘り出し物：GEM_RATE の確率（5年に1人ほど）で、下位・育成級の候補1人を無名校の選手にして A 以上のピークを持たせる
## - 転生選手：引退した名選手（ひな形の legends。全盛期が将来性 A 以上）の生まれ変わりを REINCARNATION_ODDS の人数だけ混ぜる。
##   名前は元の選手と同じ、ピークは元の全盛期に近い（ノイズあり）。同じ選手は一度だけ（呼び出し側が除いて渡す）
## オートロードは参照しない（GameState.draft_class が呼ぶ）

const DATA_FILE := "fictional_draft.json"
const FIRST_YEAR := 2028
## 能力に足すゆらぎ（入団時・ピーク。能力値。球速は km/h）
const ENTRY_NOISE := 2.0
const PEAK_NOISE := 3.0
const VELOCITY_NOISE := 1.0
## 強豪校（史実の指名がこの人数以上の学校）は入団時・ピークを少しだけ高く（差は小さめ）
const STRONG_SCHOOL := 8
const STRONG_BONUS := 1.0
## 学校の重み＝史実の指名の人数^この値（強豪ほど多いが、差は小さめに）
const SCHOOL_WEIGHT_POWER := 0.6
## 1位の帯のうち、競合の目玉（格付け S）の割合と競合の球団数
const S_SHARE := 0.25
const S_BIDS := [2, 4]
## 無名校の掘り出し物
const GEM_RATE := 0.2
const GEM_MIN_SCORE := 1.1
const GEM_BANDS := ["6-", "育成"]
## 夢多め：S級（将来性の点 DREAM_MIN_SCORE 以上）のピークを持たせる候補の人数（年に）
const DREAM_EXTRA := [2, 3]
const DREAM_MIN_SCORE := 1.6
## メジャー志望を表明する上位の目玉の人数の確率（0人・1人・2人）
const MLB_INTENT_ODDS := [0.55, 0.33, 0.12]
## 転生選手の人数の確率（0人・1人・2人）と、ピークのゆらぎ・元の全盛期との近さ（平均からの差に掛ける幅）
const REINCARNATION_ODDS := [0.3, 0.45, 0.25]
const REINCARNATION_NOISE := 4.0
const REINCARNATION_SCALE := [0.8, 1.05]
const REINCARNATION_HIGH_SCHOOL := 0.7
const REINCARNATION_SAME_SCHOOL := 0.25
const HIT_MODES := {"historical": "史実どおり", "dream": "夢多め"}
const GROWTH_TYPES := {"早熟": 25, "普通": 28, "晩成": 31}
const GRADE_TEXT := {"高校": "3年", "大学": "4年"}

const SURNAMES := [
	"佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤", "吉田", "山田", "佐々木", "山口", "松本",
	"井上", "木村", "林", "斎藤", "清水", "山崎", "森", "池田", "橋本", "阿部", "石川", "山下", "中島", "石井", "小川",
	"前田", "岡田", "長谷川", "藤田", "後藤", "近藤", "村上", "遠藤", "青木", "坂本", "斉藤", "福田", "太田", "西村", "藤井",
	"岡本", "藤原", "中川", "松田", "原田", "中野", "小野", "田村", "竹内", "金子", "和田", "中山", "石田", "上田", "森田",
	"原", "柴田", "酒井", "工藤", "横山", "宮崎", "宮本", "内田", "高木", "安藤", "谷口", "大野", "丸山", "今井", "高田",
	"藤本", "武田", "村田", "上野", "杉山", "増田", "平野", "大塚", "千葉", "久保", "松井", "小島", "岩崎", "桜井", "野口",
	"松尾", "野村", "木下", "菊地", "佐野", "大西", "杉本", "新井", "浜田", "菅原", "市川", "水野", "小松", "島田", "古川",
	"小山", "高野", "西田", "菊池", "山内", "西川", "五十嵐", "北村", "安田", "中田", "川口", "平田", "川崎", "飯田", "吉川",
	"本田", "久保田", "沢田", "辻", "関", "吉村", "渡部", "岩田", "中西", "服部", "樋口", "福島", "川上", "永井", "松岡",
	"田口", "山中", "森本", "土屋", "矢野", "広瀬", "秋山", "石原", "松下", "大橋", "松浦", "吉岡", "小池", "馬場", "浅野",
	"荒木", "大久保", "野田", "小沢", "田辺", "川村", "星野", "黒田", "堀", "尾崎", "望月", "永田", "熊谷", "内藤", "松村",
	"西山", "大谷", "平井", "大島", "岩本", "片山", "本間", "早川", "横田", "岡崎", "荒井", "大石", "鎌田", "成田", "宮田",
	"小田", "石橋", "篠原", "須藤", "河野", "大沢", "小西", "南", "高山", "栗原", "伊東", "松原", "三浦", "宮下", "奥村",
	"桑原", "江口", "東", "柳田", "杉浦", "白石", "長田", "根本", "湯浅", "堤", "瀬戸", "芦田", "唐沢", "稲垣", "梶原",
	"新垣", "比嘉", "金城", "宮城", "玉城", "大城", "知念", "嶺井", "仲宗根", "照屋", "上原", "当山", "神里", "具志堅",
]
const GIVEN_NAMES := [
	"陽翔", "湊", "蓮", "大和", "悠真", "颯太", "蒼", "樹", "律", "陽向", "朝陽", "大翔", "悠人", "結翔", "奏太", "陸",
	"湊斗", "颯真", "蒼空", "晴", "碧", "暖", "新", "柊", "伊吹", "陽太", "瑛太", "海斗", "悠斗", "颯", "壮真", "陽", "隼",
	"遥斗", "優斗", "陽斗", "航", "大雅", "琉生", "蒼真", "晴翔", "智也", "一輝", "翔太", "拓海", "大輝", "雄大", "健太",
	"翼", "光", "隼人", "優真", "将吾", "康介", "亮太", "龍之介", "虎太郎", "琥太郎", "慶太", "直樹", "優希", "勇斗",
	"春樹", "孝太", "勝利", "誠", "仁", "剛", "豪", "武蔵", "創", "雅也", "太陽", "空", "陽生", "凌", "恭平", "大地",
	"広大", "泰成", "敦也", "啓太", "竜也", "健斗", "颯斗", "怜", "響", "奏", "綾人", "陽介", "悠希", "大和", "瑞樹",
	"丈", "嵐", "風雅", "櫂", "絢斗", "健吾", "秀斗", "恒星", "昂", "侑真", "崇", "友哉", "耕平", "圭吾", "修平", "将太",
	"光希", "倖太", "暁", "紘", "司", "迅", "蒼介", "晃大", "歩夢", "結人", "冬馬", "夏輝", "千尋", "勇吾", "颯汰",
	"龍生", "隆之介", "叶多", "那由多", "瑛人", "惟吹", "陽色", "旭", "凪", "楓", "唯人", "碧斗", "葵", "陽一", "誠也",
]
## 高校の大会の見出しに使う言葉（架空の候補の紹介文・ニュース）
const TYPE_WORDS := {
	"P_power": "本格派", "P_control": "技巧派", "P_fast": "剛腕", "P_lefty": "左腕", "P_righty": "右腕",
	"B_power": "スラッガー", "B_contact": "巧打者", "B_speed": "俊足", "B_defense": "守備の名手", "B_catcher": "強肩捕手",
}

var data: Dictionary
var _pool := {}           ## "区分|帯|side" → ひな形の配列
var _by_band := {}        ## "帯|side" → ひな形の配列（区分の組が無いとき）
var _schools := {}        ## 区分 → [[学校名, 重み, 人数], ...]
var _derived: Dictionary = {}
var _serial := 0


## fictional_data: generated/fictional_draft.json の中身（空なら読む）。growth：投手の総合を内訳から出す式に使う
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


## draft_year 年秋のドラフト候補をまとめて作る。opts：{hits: "historical"|"dream", legends: 転生のもとにできる
## legends の配列（ゲーム内で引退していて、まだ転生していない選手。空なら転生なし）, taken_names: 使えない名前}
func generate_year(draft_year: int, rng: RandomNumberGenerator, opts: Dictionary = {}) -> Array:
	var sizes: Dictionary = data.get("class_sizes", {})
	var keys: Array = sizes.keys()
	var size: Dictionary = sizes[keys[rng.randi_range(0, keys.size() - 1)]] if not keys.is_empty() \
		else {"reg": 75, "ikusei": 40}
	var taken: Dictionary = opts.get("taken_names", {}).duplicate()
	var out: Array = []
	var picks := _pick_templates(int(size["reg"]), false, rng)
	picks.append_array(_pick_templates(int(size["ikusei"]), true, rng))
	for t: Dictionary in picks:
		out.append(make(t, draft_year, rng, taken))
	if str(opts.get("hits", "historical")) == "dream":
		_add_dream(out, rng)
	if rng.randf() < GEM_RATE:
		_add_gem(out, rng)
	var legends: Array = opts.get("legends", [])
	if not legends.is_empty():
		var n := _count_from(REINCARNATION_ODDS, rng)
		var pool := legends.duplicate()
		for i in mini(n, pool.size()):
			var j := rng.randi_range(0, pool.size() - 1)
			out.append(make_reincarnation(pool[j], draft_year, rng))
			pool.remove_at(j)
	_mark_mlb_intent(out, rng)
	return out


## 区分×順位の帯の割合どおりに n 人分のひな形を選ぶ（本指名か育成か）
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


## ひな形から1人作る
func make(t: Dictionary, draft_year: int, rng: RandomNumberGenerator, taken: Dictionary) -> Dictionary:
	var p: Dictionary = t["player"].duplicate(true)
	var side: String = t["side"]
	_serial += 1
	var category: String = t["category"]
	var school := _school(category, rng)
	var strong := int(school[1]) >= STRONG_SCHOOL
	p["id"] = "fic:%d:%03d" % [draft_year, _serial]
	p["provisional_id"] = false
	p["name"] = _unique_name(rng, taken)
	_fill_common(p, draft_year, school[0])
	_perturb(p, side, ENTRY_NOISE, rng)
	if strong:
		_shift_all(p, side, STRONG_BONUS)
	var peak := _peak_from(t["peak"], PEAK_NOISE + 0.0, rng)
	if strong:
		for k: String in peak:
			if k != "velocity":
				peak[k] = float(peak[k]) + STRONG_BONUS
	var gtype := _growth_type(t.get("peak_age"))
	p["growth"] = {"type": gtype, "peak_age": _peak_age(t.get("peak_age"), gtype), "peak": peak}
	var band: String = t["band"]
	var grade := _grade_of(band, rng)
	var bids := rng.randi_range(S_BIDS[0], S_BIDS[1]) if grade == "S" else 1
	p["amateur"] = {
		"draft_year": draft_year, "category": category, "school": school[0], "grade": grade,
		"grade_text": GRADE_TEXT.get(category, "入社%d年目" % rng.randi_range(2, 4) if category == "社会人" else "1年目"),
		"as_round": int(t["round"]), "as_ikusei": bool(t["ikusei"]), "bids": bids,
		"future_score": float(t["score"]) + rng.randfn(0.0, 0.1), "fictional": true, "strong_school": strong,
		"projected": _projected(band), "template_year": int(t["year"]),
	}
	p["amateur"]["type"] = type_word(p)
	p["amateur"]["intro"] = intro_of(p)
	return p


## 転生選手を1人作る（legend：ひな形の legends の1人）
func make_reincarnation(legend: Dictionary, draft_year: int, rng: RandomNumberGenerator) -> Dictionary:
	var side: String = legend["side"]
	var category := "高校" if rng.randf() < REINCARNATION_HIGH_SCHOOL else "大学"
	var key := "%s|1|%s" % [category, side]
	var pool: Array = _pool.get(key, _by_band.get("1|%s" % side, []))
	var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var p: Dictionary = t["player"].duplicate(true)
	_serial += 1
	var school := _school(category, rng)
	for s: Variant in legend.get("schools", []):
		var known := _school_count(category, str(s))
		if known > 0 and rng.randf() < REINCARNATION_SAME_SCHOOL:
			school = [str(s), known]
	p["id"] = "rei:%d:%s" % [draft_year, legend["id"]]
	p["provisional_id"] = false
	p["name"] = legend["name"]
	for k: String in ["throws", "bats", "height", "weight"]:
		if legend.get(k) != null:
			p[k] = legend[k]
	_fill_common(p, draft_year, school[0])
	_perturb(p, side, ENTRY_NOISE, rng)
	var scale := rng.randf_range(REINCARNATION_SCALE[0], REINCARNATION_SCALE[1])
	var peak := {}
	for k: String in legend["peak"]:
		var v := float(legend["peak"][k])
		if k == "velocity":
			peak[k] = v + rng.randfn(0.0, 2.0)
		else:
			peak[k] = SimPlayer.SCALE_MEAN + (v - SimPlayer.SCALE_MEAN) * scale + rng.randfn(0.0, REINCARNATION_NOISE)
	if side == "B":
		_copy_position(p, legend, t)
		if legend.get("trajectory") != null:
			p["batting"]["trajectory"] = clampi(int(legend["trajectory"]) - 1, 1, 4)
	else:
		p["pitching"]["role"] = "先発" if legend.get("role") == "先発" else "救援"
	var gtype := _growth_type(legend.get("peak_age"))
	p["growth"] = {"type": gtype, "peak_age": _peak_age(legend.get("peak_age"), gtype), "peak": peak}
	var grade := "S" if float(legend["score"]) >= DREAM_MIN_SCORE or rng.randf() < 0.5 else "A"
	p["amateur"] = {
		"draft_year": draft_year, "category": category, "school": school[0], "grade": grade,
		"grade_text": GRADE_TEXT[category], "as_round": 1, "as_ikusei": false,
		"bids": rng.randi_range(S_BIDS[0], S_BIDS[1]) if grade == "S" else 1,
		"future_score": float(legend["score"]) * scale + rng.randfn(0.0, 0.15), "fictional": true,
		"strong_school": int(school[1]) >= STRONG_SCHOOL, "projected": "1位候補", "template_year": int(t["year"]),
		"reincarnation": {"id": legend["id"], "name": legend["name"], "peak_year": int(legend["peak_year"]),
			"peak_team": str(legend.get("peak_team", "")), "school": "・".join(legend.get("schools", []))},
	}
	p["amateur"]["type"] = type_word(p)
	p["amateur"]["intro"] = "「%sの再来」と話題の%s" % [legend["name"], p["amateur"]["type"]]
	return p


## 夢多め：上位の候補から DREAM_EXTRA 人に S級のピークを持たせる
func _add_dream(out: Array, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(DREAM_EXTRA[0], DREAM_EXTRA[1])
	var upper: Array = []
	for p: Dictionary in out:
		if p["amateur"]["grade"] in ["S", "A", "B"] and float(p["amateur"]["future_score"]) < DREAM_MIN_SCORE:
			upper.append(p)
	for i in mini(n, upper.size()):
		var j := rng.randi_range(0, upper.size() - 1)
		_give_peak(upper[j], DREAM_MIN_SCORE, rng)
		upper[j]["amateur"]["dream"] = true
		upper.remove_at(j)


## 無名校の掘り出し物：下位・育成級の候補1人を無名校（史実の指名1人の学校）の選手にし、A 以上のピークを持たせる
func _add_gem(out: Array, rng: RandomNumberGenerator) -> void:
	var low: Array = []
	for p: Dictionary in out:
		var am: Dictionary = p["amateur"]
		if (bool(am["as_ikusei"]) or int(am["as_round"]) >= 6) and am["category"] in ["高校", "大学", "社会人", "独立"]:
			low.append(p)
	if low.is_empty():
		return
	var p: Dictionary = low[rng.randi_range(0, low.size() - 1)]
	var am: Dictionary = p["amateur"]
	var minor: Array = []
	for s: Array in _schools.get(am["category"], []):
		if int(s[2]) <= 1:
			minor.append(s[0])
	if not minor.is_empty():
		am["school"] = minor[rng.randi_range(0, minor.size() - 1)]
		p["career"] = am["school"]
		am["strong_school"] = false
	_give_peak(p, GEM_MIN_SCORE, rng)
	p["growth"]["type"] = "晩成"
	p["growth"]["peak_age"] = GROWTH_TYPES["晩成"]
	am["gem"] = true
	am["type"] = type_word(p)
	am["intro"] = intro_of(p)


## 将来性の点が min_score 以上のひな形のピークを持たせる（同じ投手・野手の中から）
func _give_peak(p: Dictionary, min_score: float, rng: RandomNumberGenerator) -> void:
	var side := Growth._side(p)
	var best: Array = []
	for t: Dictionary in data.get("templates", []):
		if t["side"] == side and float(t["score"]) >= min_score:
			best.append(t)
	if best.is_empty():
		return
	var t: Dictionary = best[rng.randi_range(0, best.size() - 1)]
	p["growth"]["peak"] = _peak_from(t["peak"], PEAK_NOISE, rng)
	p["amateur"]["future_score"] = float(t["score"]) + rng.randfn(0.0, 0.1)
	if side == "P" and t["peak"].get("stamina") != null:
		p["pitching"]["role"] = "先発" if float(t["peak"]["stamina"]) >= Growth.STARTER_STAMINA else p["pitching"]["role"]


## 上位の目玉（格付け S・A）の0〜2人がメジャー志望を表明
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


# --- 部品 ------------------------------------------------------------------------------

func _fill_common(p: Dictionary, draft_year: int, school: String) -> void:
	p["birth"] = null
	p["draft"] = "%d年ドラフト候補" % draft_year
	p["career"] = school
	p["team"] = ""
	p["hist_team"] = ""
	p["team_id"] = null
	p["league"] = null
	for side: String in ["batting", "pitching"]:
		if p.get(side) is Dictionary:
			p[side]["sample"] = {"outs_1": 0.0, "outs_2": 0.0} if side == "pitching" else {"pa_1": 0.0, "pa_2": 0.0}


func _peak_from(src: Dictionary, noise: float, rng: RandomNumberGenerator) -> Dictionary:
	var peak := {}
	for k: String in src:
		var sd := VELOCITY_NOISE if k == "velocity" else noise
		peak[k] = float(src[k]) + rng.randfn(0.0, sd)
	return peak


## 能力に小さなゆらぎ（ForeignPlayers._perturb と同じ考え方。投手の総合は内訳の変化に合わせる）
func _perturb(p: Dictionary, side: String, noise: float, rng: RandomNumberGenerator) -> void:
	if side == "B":
		for key: String in Growth.BATTING_KEYS:
			var v: Variant = Growth._value(p, "B", key)
			if v != null:
				Growth._set_value(p, "B", key, float(v) + rng.randfn(0.0, noise))
		return
	var before := {}
	for key: String in ["k9", "bb9", "hr9"]:
		var v: Variant = Growth._value(p, "P", key)
		if v != null:
			before[key] = float(v)
			Growth._set_value(p, "P", key, float(v) + rng.randfn(0.0, noise))
	var vel: Variant = Growth._value(p, "P", "velocity")
	if vel != null:
		Growth._set_value(p, "P", "velocity", float(vel) + rng.randfn(0.0, VELOCITY_NOISE))
	var ov: Variant = Growth._value(p, "P", "overall")
	var role := "先発" if p["pitching"].get("role") == "先発" else "救援"
	var d: Dictionary = _derived.get(role, {})
	if ov != null and not d.is_empty():
		var nxt := float(ov)
		for k: String in before:
			nxt += float(d["from"].get(k, 0.0)) * (float(Growth._value(p, "P", k)) - float(before[k]))
		Growth._set_value(p, "P", "overall", nxt)


func _shift_all(p: Dictionary, side: String, amount: float) -> void:
	var keys: Array = Growth.BATTING_KEYS if side == "B" else ["overall", "k9", "bb9", "hr9"]
	for key: String in keys:
		var v: Variant = Growth._value(p, side, key)
		if v != null:
			Growth._set_value(p, side, key, float(v) + amount)


## 転生した野手：元の選手の守備位置（全盛期の守備の記録の位置）を、入団時の守備力で付ける
func _copy_position(p: Dictionary, legend: Dictionary, t: Dictionary) -> void:
	var fielding := {}
	var base := float(Growth._value(t["player"], "B", "defense") if Growth._value(t["player"], "B", "defense") != null \
		else 50.0)
	var src: Dictionary = legend.get("fielding", {})
	for pos: String in src:
		var entry := {"games": 0, "defense": {}, "gold_glove": false}
		Growth._write(entry["defense"], base)
		if src[pos].get("arm") is Dictionary:
			entry["arm"] = {}
			Growth._write(entry["arm"], base)
		fielding[pos] = entry
	if fielding.is_empty():
		return
	p["fielding"] = fielding
	if legend.get("primary_pos") != null and fielding.has(str(legend["primary_pos"])):
		p["primary_pos"] = legend["primary_pos"]
	else:
		p["primary_pos"] = fielding.keys()[0]


## 区分の学校を重み付きで1つ [名前, 史実の指名の人数]
func _school(category: String, rng: RandomNumberGenerator) -> Array:
	var list: Array = _schools.get(category, _schools.get("社会人", []))
	if list.is_empty():
		return ["（不明）", 0]
	var total := 0.0
	for s: Array in list:
		total += float(s[1])
	var u := rng.randf() * total
	for s: Array in list:
		u -= float(s[1])
		if u <= 0.0:
			return [s[0], s[2]]
	return [list[-1][0], list[-1][2]]


func _school_count(category: String, name: String) -> int:
	for s: Array in _schools.get(category, []):
		if s[0] == name:
			return int(s[2])
	return 0


func _unique_name(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for i in 200:
		var n := "%s %s" % [SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)],
			GIVEN_NAMES[rng.randi_range(0, GIVEN_NAMES.size() - 1)]]
		if not taken.has(LeagueRoster.norm_name(n)):
			taken[LeagueRoster.norm_name(n)] = true
			return n
	return "%s %s%d" % [SURNAMES[0], GIVEN_NAMES[0], rng.randi_range(2, 99)]


static func _growth_type(peak_age: Variant) -> String:
	if peak_age == null:
		return "普通"
	if int(peak_age) <= 25:
		return "早熟"
	if int(peak_age) >= 31:
		return "晩成"
	return "普通"


static func _peak_age(peak_age: Variant, gtype: String) -> int:
	if peak_age == null:
		return GROWTH_TYPES[gtype]
	return clampi(int(peak_age), 23, 33)


func _grade_of(band: String, rng: RandomNumberGenerator) -> String:
	match band:
		"1":
			return "S" if rng.randf() < S_SHARE else "A"
		"2-3":
			return "B"
		"4-5", "6-":
			return "C"
	return "D"


static func _projected(band: String) -> String:
	match band:
		"1":
			return "1位候補"
		"2-3":
			return "上位候補"
		"4-5", "6-":
			return "中位〜下位"
	return "育成候補"


static func _count_from(odds: Array, rng: RandomNumberGenerator) -> int:
	var u := rng.randf()
	for i in odds.size():
		u -= float(odds[i])
		if u < 0.0:
			return i
	return odds.size() - 1


## タイプの言葉（ピークの形から。紹介文・ニュースの見出し）
static func type_word(p: Dictionary) -> String:
	var peak: Dictionary = p.get("growth", {}).get("peak", {})
	if Growth._side(p) == "P":
		var hand := "左腕" if p.get("throws") == "左" else "右腕"
		if float(peak.get("velocity", 0.0)) >= 154.0:
			return "剛腕" + ("左腕" if hand == "左腕" else "")
		if float(peak.get("bb9", 0.0)) >= 70.0 and float(peak.get("k9", 0.0)) < 65.0:
			return "技巧派" + hand
		return "本格派" + hand
	if p.get("primary_pos") == "捕手":
		return "強肩捕手" if float(peak.get("arm", 0.0)) >= 65.0 else "捕手"
	var power := float(peak.get("power", 0.0))
	var meet := float(peak.get("meet", 0.0))
	var speed := float(peak.get("speed", 0.0))
	if power >= 70.0 and power >= meet:
		return "スラッガー"
	if speed >= 72.0:
		return "俊足の" + ("外野手" if str(p.get("primary_pos", "")).contains("外野") else "内野手")
	if meet >= 66.0:
		return "巧打者"
	return "外野手" if str(p.get("primary_pos", "")).contains("外野") else "内野手"


## 紹介文（30字以内。「〇〇高の本格派右腕、最速150km」）
static func intro_of(p: Dictionary) -> String:
	var am: Dictionary = p["amateur"]
	var text := "%sの%s" % [am["school"], am.get("type", "")]
	if Growth._side(p) == "P":
		var kmh: Variant = Growth._value(p, "P", "velocity")
		if kmh != null:
			text += "、最速%dkm" % roundi(float(kmh) + 3.0)
	return text
