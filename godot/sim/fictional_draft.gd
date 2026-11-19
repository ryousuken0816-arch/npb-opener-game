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
## 作業80（ユーザー 2026-11-09「もう少し低くてもいい」）：約半分に（1人以上いる年が約3割・約3年に1人）。そのぶん武器は入団時から S
const MONSTER_RATE := {"高校": 0.15, "大学": 0.10, "社会人": 0.06, "独立": 0.03}
const MAX_MONSTERS := 2
## 入団時の水準（作業62。tools/amateur_ratings.py の calibrate と同じ物差し）。投手は総合、野手は
## 0.35ミート＋0.35パワー＋0.1選球眼＋0.1走力＋0.1（守備−13）を投手の総合に換算（62＋1.875×（野手−60））
const BAT_MID := 60.0
const PITCH_MID := 62.0
const BAT_TO_PITCH := 1.875
## 評価ごとの入団時の総合 [上, 下]。同じ評価の中は見た目の評価の順に LEVEL_STEP ずつ下げる（下の値より下げない）
## 作業80：中位・下位（C・D）は2下げた（上位との差を広げる）。
## 作業83：B は2、C・D は5下げた（長所はそのままで、ほかの能力を FictionalTypes.FREE_RANGE の D〜F に。ピークはそのまま＝伸びしろが大きい）
const LEVEL_READY := {"S": [79, 74], "A": [75, 70], "B": [67, 62], "C": [56, 50], "D": [49, 43]}
const LEVEL_HS := {"S": [68, 64], "A": [64, 60], "B": [57, 53], "C": [47, 42], "D": [41, 36]}
const LEVEL_STEP := 1.0
## 高卒の S・A の武器 [上, 下]（投手は奪三振、野手はパワー・走力・肩のうち元の値がいちばん目立つもの）
const WEAPON := {"S": [86, 81], "A": [80, 75]}
## 怪物の入団時：大学・社会人・独立は総合 A（80〜84）、高校は総合 B（70〜75）＋武器 S（89〜93。作業80）
const MONSTER_LEVEL_READY := [80.0, 84.0]
const MONSTER_LEVEL_HS := [70.0, 75.0]
const MONSTER_WEAPON := [89.0, 93.0]
## 作業85（ユーザー 2026-11-16「これ怪物って感じしないな」「なんで高校生そんな弱くすんねん！佐々木朗希・大谷・ダル、みんな高校生じゃん」）：
## 怪物の入団時の能力は型・評価の水準のあとで直接決める（_monsterize）。高校生も大学・社会人と同じ（伸びしろだけ高校生が大きい）。
## 武器は花形（投手＝球速か奪三振、野手＝ミートかパワー）S、2番目・3番目は A、D 以下の弱点なし。範囲は [下限, 上限]
const MON_WEAPON := [92.0, 97.0]
const MON_SECOND := [84.0, 90.0]
const MON_THIRD := [82.0, 88.0]
const MON_THIRD_CAP := 90.0
const MON_FLOOR := [62.0, 70.0]
## 投手：武器が球速のとき（この確率）は奪三振も A（84〜90）、球速 160〜162。奪三振が武器のときの球速 155〜160
const MON_VELO_WEAPON_RATE := 0.40
const MON_VELO_WEAPON := [160.0, 162.0]
const MON_VELO_OTHER := [155.0, 160.0]
const MON_K9_OTHER := [88.0, 92.0]
## 投手の総合（奪三振・制球・被本塁打の平均）の範囲
const MON_OVERALL := [86.0, 92.0]
const MON_VELO_PEAK_MAX := 165.0
## ピーク：武器は 97〜99、2番目・3番目は 90〜97、ほかは入団時＋伸びしろ（高校生のほうが大きい）。元のピークより低くしない
const MON_PEAK_WEAPON := [97.0, 99.0]
const MON_PEAK_SECOND := [90.0, 97.0]
const MON_GROW_HS := [6.0, 10.0]
const MON_GROW := [3.0, 6.0]
const MON_VELO_GROW_HS := [2.0, 5.0]
const MON_VELO_GROW := [1.0, 3.0]
## 本格二刀流（型 A。作業86「二刀流でめっちゃ強いやつがたまに出るのがワクワクする」）：投手でエース級（球速 155km 以上・決め球あり）
## かつ打者で主軸級（ミートかパワーが A〜S）。怪物と同じ超目玉で何球団も競合。範囲は [下限, 上限]（元の値が高ければ残す）
const TW_K9 := [86.0, 93.0]
const TW_BB9 := [66.0, 80.0]
const TW_HR9 := [74.0, 84.0]
const TW_STAMINA := [64.0, 76.0]
const TW_VELO := [155.0, 160.0]
const TW_BAT_WEAPON := [82.0, 92.0]
const TW_BAT_SECOND := [70.0, 80.0]
const TW_BAT_FLOOR := [60.0, 72.0]
const TW_ARM := [82.0, 92.0]
const TW_DEFENSE := [58.0, 68.0]
## ピーク：奪三振・打撃の武器は 94〜99、ほかは入団時＋伸びしろ（怪物と同じ MON_GROW_HS・MON_GROW）
const TW_PEAK_TOP := [94.0, 99.0]
## 作業89：本格二刀流の決め球を怪物（作業85）にそろえる。持ち球は奪三振・球速から合わせて作り（PitchArsenal.fit。6・7 には罰がある）、
## 型 A は奪三振が下がって 82〜84・決め球が 4 になることがあった（two_way_check の NG）。決め球は TW_ACE_MOVE_MIN 以上、
## 奪三振が TW_K9 の下限より低ければ三振を取りやすい球から1つずつ上げる（TW_ACE_MOVE_MAX まで。PitchArsenal.lift_k）。怪物の投手の決め球は 6 が約65%・5 が約30%・奪三振 86〜98。
## いつも 6 にすると球速 158km 前後の型 A は奪三振が 99〜100（怪物より上）になるので、6 は必要なときだけ
const TW_ACE_MOVE_MIN := 5
const TW_ACE_MOVE_MAX := 6
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
## 守備位置・守備力・肩（作業66。fill_fielding。tools/amateur_ratings.py の同じ名前の定数と同じ値）
const FIELD_POS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手"]
## 能力値の fielding で肩がある位置（一塁・二塁は守備力だけ）
const ARM_POS := ["捕手", "三塁手", "遊撃手", "外野手"]
const INFIELD_SS_DEF := 60.0
const INFIELD_3B_ARM := 60.0
const INFIELD_2B_DEF := 52.0
const FIELD_HS_GAP := 5.0
## 近い位置（本職の守備力からの差）
const SUB_POS := {"遊撃手": {"二塁手": -3, "三塁手": -4}, "二塁手": {"遊撃手": -6, "一塁手": -2}, "三塁手": {"一塁手": -2}}
## 投手の守備力（評価ごと。高校は PITCH_FIELD_HS_GAP 下げる）と、選手ごとのゆらぎの幅
const PITCH_FIELD_LEVEL := {"S": 73, "A": 72, "B": 71, "C": 70, "D": 69}
const PITCH_FIELD_HS_GAP := 2.0
const FIELD_SPREAD := 4
## 入団時の弾道（set_trajectory。点の式は tools/amateur_ratings.py の rookie_trajectory と同じ）。区切りは架空の候補だけ別：
## 型（作業67）で長所・短所がはっきりした分、点が実在の新人より広がる（下位10% 29・下位15% 33・上位10% 84・上位3% 94）ので、
## 弾道1 が15%前後・3 が15%前後・4 が数%になるように決めた（史実の新人の1年目は 1 15%・3 4%・4 0.4%）。
## 作業89：作業83で長所でも短所でもない能力を下げてから点の上のほうが縮み（上位10% 77・上位3% 86）、5年分で 4 が0人・3 が約6%に
## なった（rookie_fielding_check の NG）。区切りを 94/80/31 → 86/75/30、4 のパワーを 78 → 74 にして、1 約10%・3 約15%・4 約3% に戻した
const TRAJ_SHAPE := 0.4
const TRAJ_CUTS := [[86.0, 4], [75.0, 3], [30.0, 2]]
const TRAJ_4_POWER := 74.0
## 転生選手の出現確率（人数分布）
const REINCARNATION_ODDS := [0.65, 0.25, 0.08, 0.02]
## 転生選手の高校／大学の割合
const REINCARNATION_HIGH_SCHOOL := 0.60
const REINCARNATION_SAME_SCHOOL := 0.40
## ピーク＝元の選手の全盛期の能力を中央（63）から何倍にするか（作業84：[0.85, 1.05] → [0.95, 1.02]。下限だけ上げて、
## 中堅の名選手が弱く出すぎないように。大物（全盛期に S が複数）は今とほぼ同じ強さ）。能力はピークも入団時も REINCARNATION_MAX で止める
const REINCARNATION_SCALE := [0.95, 1.02]
const REINCARNATION_NOISE := 2.5
const REINCARNATION_MAX := 99.0
## 入団時＝ピークからいくつ引くか（野手・投手）と、球速を何km/h 引くか（作業84：−15・−14・−4 → −12・−11・−2。作業80で目玉・怪物の入団時が強くなったぶん、中堅の転生選手が埋もれないように）
const REINCARNATION_ENTRY_GAP_BAT := 12.0
const REINCARNATION_ENTRY_GAP_PIT := 11.0
const REINCARNATION_ENTRY_GAP_VELO := 2.0
## 夢多め（作業22。hits == "dream" で S級の候補を増やす）
const DREAM_EXTRA := [2, 4]
const DREAM_MIN_SCORE := 1.6
## 無名校の掘り出し物（GEM_RATE で下位に A級の選手を1人混ぜる）
const GEM_RATE := 0.20
const GEM_MIN_SCORE := 0.8
## メジャー志望を表明する人数の確率（0人・1人・2人・3人。作業78：平均 約1人／年。もとは [0.80, 0.16, 0.04]＝平均0.24人）
const MLB_INTENT_ODDS := [0.36, 0.36, 0.20, 0.08]
## 表明する1人ごとに、目玉（当時の評価 S・A）ではなく中位（B・C の大学生・社会人・独立）から選ぶ確率（「メジャー一本」）
const MLB_INTENT_MID := 0.3
const MLB_MID_CATEGORIES := ["大学", "社会人", "独立"]
const MLB_MID_NOTES := ["{school}の{name}、「メジャー一本」を公言。NPB の指名は望まない構え",
	"{school}の{name}、マイナー契約からのメジャー挑戦を目指すと表明",
	"{school}の{name}がメジャー球団の入団テストへ。NPB 入りより海を渡る道を選ぶ意向"]
const MLB_TOP_NOTES := ["{school}の{name}、高校・大学からのメジャー挑戦を表明",
	"{school}の{name}、プロ入りの舞台にメジャーを選ぶと表明。複数のメジャー球団が視察",
	"{school}の{name}が直接のメジャー挑戦を明言。NPB 球団は指名するか難しい判断に"]
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
	# その年の色（作業67。投手の豊作年など。顔ぶれと質を偏らせる）
	var theme := FictionalTypes.pick_theme(rng)

	# ひな形から区分・守備位置の構成をサンプリング
	var picks := _pick_templates(int(size["reg"]), false, rng, theme)
	var monsters := _monster_slots(picks, rng)
	picks.append_array(_pick_templates(int(size["ikusei"]), true, rng, theme))

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
	# 完成型・未完の大器は毎年どちらも何人か（作業67）
	var n_complete := 0
	var n_wild := 0
	var used_types := {}
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
		# 型（作業67）：守備位置・評価・年の色から選び、入団時の総合を変えずに能力の形を作る（_calibrate_entry の中）
		var lefty := float(FictionalTypes.THEMES[theme].get("lefty", 0.0))
		if p["is_pitcher"] and lefty > 0.0 and p["throws"] != "左" and rng.randf() < lefty:
			p["throws"] = "左"
		# 作業89：3〜4割は型なし（空）、同じ型は1年に2人まで（used_types）
		var type_key := FictionalTypes.pick_type(p, grade, theme, rng, used_types)
		var ready_pick: bool = p["category"] != "高校" and not is_ikusei and not bool(p.get("is_monster", false))
		if ready_pick and grade in ["A", "B"] and rank_in_reg >= 20 and n_complete < FictionalTypes.MIN_EACH \
				and FictionalTypes.type_room(used_types, FictionalTypes.complete_type(p)):
			type_key = FictionalTypes.complete_type(p)
		elif not is_ikusei and rank_in_reg >= 45 and n_wild < FictionalTypes.MIN_EACH and grade in ["C", "D"] \
				and FictionalTypes.type_room(used_types, FictionalTypes.wild_type(p)):
			type_key = FictionalTypes.wild_type(p)
		n_complete += 1 if FictionalTypes.is_complete(type_key) else 0
		n_wild += 1 if FictionalTypes.is_wild(type_key) else 0
		if not type_key.is_empty():
			var lb := FictionalTypes.label_of(type_key)
			used_types[lb] = int(used_types.get(lb, 0)) + 1
		p["_type"] = type_key
		p["_grade"] = grade
		p["_theme_bonus"] = (FictionalTypes.level_bonus(theme, p) if grade in ["B", "C", "D"] else 0.0) \
			+ (FictionalTypes.COMPLETE_BONUS if FictionalTypes.is_complete(type_key) else 0.0)
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

		# 型の名前（二刀流は最後に二刀流の名前にする）。型なしは空（表・紹介文に型の名前を出さない。作業89）
		am["type_key"] = str(p["_type"])
		am["type"] = FictionalTypes.label_of(str(p["_type"]))
		am["intro"] = intro_of(p)

		# 作業用キーを削除
		for k: String in ["_apparent_eval", "_type", "_grade", "_theme_bonus"]:
			p.erase(k)
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
	# 物語（作業67）：一部の候補に経歴の物語。紹介文に足す
	FictionalTypes.assign_stories(out, rng)

	# クラス全体から二刀流候補を年間枠（ポアソン分布・上限2人）で適性に基づき選出して副次能力を付与
	_talent.assign_two_way_for_class(out, rng)
	for p: Dictionary in out:
		var tw: Dictionary = p.get("two_way", {})
		if bool(tw.get("active", false)):
			p["amateur"]["type"] = FictionalTalent.decide_player_type(p)
		if bool(tw.get("active", false)) or not str(p["amateur"].get("story", "")).is_empty():
			p["amateur"]["intro"] = intro_of(p)
		p["amateur"]["year_theme"] = theme
	# 一芸だけ S（作業67。確率で年に0〜2人。紹介文に「◯◯は世代随一」）
	FictionalTypes.assign_one_skill(out, theme, rng)
	for p: Dictionary in out:
		if bool(p.get("is_monster", false)) and not bool(p["amateur"].get("as_ikusei", false)):
			_monsterize(p, rng)  # 怪物の入団時・ピーク（作業85）
		var two_way_ace := str(p.get("two_way", {}).get("type", "")) == "A" and bool(p["two_way"].get("active", false))
		if two_way_ace:
			_two_way_ace(p, rng)  # 本格二刀流の入団時・ピーク（作業86）
		FictionalTypes.untie(p, rng)  # 同じ選手の中で同じ数字が並ばないように（作業73）
		if two_way_ace:
			_ace_pitch(p, draft_year + 1)  # 決め球・奪三振を怪物にそろえる（作業89）
		fill_fielding(p)
		if two_way_ace:
			var br: Dictionary = p["batting"]["ratings"]
			p["fielding"]["外野手"] = _field_entry("外野手", _rv(br, "defense", 60.0), _rv(br, "arm", 85.0))
		set_trajectory(p)
		_sync_peak(p)

	return out


## 怪物の入団時の能力・球速とピークを決める（作業85。MON_*）。型・評価の水準で作った能力は、高いほうを残して下限・範囲にそろえる。
## 投手：奪三振が武器（92〜97）か球速が武器（160〜162）、制球・被本塁打は A（84〜90）、スタミナは C 以上、総合＝奪三振・制球・被本塁打の平均。
## 野手：ミートかパワーが武器（92〜97）、もう一方が A（84〜90）、選球眼・走力・守備のうち元がいちばん高いものも A（82〜90）、ほかは C 以上
func _monsterize(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var hs := str(p["category"]) == "高校"
	var grow: Array = MON_GROW_HS if hs else MON_GROW
	var peak: Dictionary = p["growth"]["peak"]
	var entry: Dictionary = {}  # 能力名 → 入団時の値
	var tops: Dictionary = {}  # 能力名 → ピークの下限（武器・2番目・3番目）
	if bool(p["is_pitcher"]):
		var pr: Dictionary = p["pitching"]["ratings"]
		var velo_weapon := rng.randf() < MON_VELO_WEAPON_RATE
		if velo_weapon:
			entry["k9"] = clampf(maxf(_rv(pr, "k9", 0.0), rng.randf_range(MON_K9_OTHER[0], MON_K9_OTHER[1])), MON_K9_OTHER[0], MON_K9_OTHER[1])
		else:
			entry["k9"] = rng.randf_range(MON_WEAPON[0], MON_WEAPON[1])
			tops["k9"] = rng.randf_range(MON_PEAK_WEAPON[0], MON_PEAK_WEAPON[1])
		for k: String in ["bb9", "hr9"]:
			entry[k] = clampf(maxf(_rv(pr, k, 0.0), rng.randf_range(MON_SECOND[0], MON_SECOND[1])), MON_SECOND[0], MON_SECOND[1])
			tops[k] = rng.randf_range(MON_PEAK_SECOND[0], MON_PEAK_SECOND[1])
		if velo_weapon:
			tops["k9"] = rng.randf_range(MON_PEAK_SECOND[0], MON_PEAK_SECOND[1])
		entry["stamina"] = maxf(_rv(pr, "stamina", 0.0), rng.randf_range(MON_FLOOR[0], MON_FLOOR[1]))
		for k: String in entry:
			_set_rating(pr, k, entry[k])
		_set_rating(pr, "overall", clampf((float(entry["k9"]) + float(entry["bb9"]) + float(entry["hr9"])) / 3.0, MON_OVERALL[0], MON_OVERALL[1]))
		var velo: Dictionary = p["pitching"]["velocity"]
		var kmh := rng.randf_range(MON_VELO_WEAPON[0], MON_VELO_WEAPON[1]) if velo_weapon 			else rng.randf_range(MON_VELO_OTHER[0], MON_VELO_OTHER[1])
		velo["kmh"] = roundi(kmh)
		var vg: Array = MON_VELO_GROW_HS if hs else MON_VELO_GROW
		peak["velocity"] = minf(MON_VELO_PEAK_MAX, maxf(float(peak.get("velocity", 0.0)), kmh + rng.randf_range(vg[0], vg[1])))
		entry["overall"] = _rv(pr, "overall", 0.0)
	else:
		var br: Dictionary = p["batting"]["ratings"]
		var meet := _rv(br, "meet", 0.0)
		var power := _rv(br, "power", 0.0)
		var weapon := "power" if power > meet + 10.0 else ("meet" if meet > power + 10.0 else ("power" if rng.randf() < 0.5 else "meet"))
		var other := "meet" if weapon == "power" else "power"
		entry[weapon] = rng.randf_range(MON_WEAPON[0], MON_WEAPON[1])
		tops[weapon] = rng.randf_range(MON_PEAK_WEAPON[0], MON_PEAK_WEAPON[1])
		entry[other] = clampf(maxf(_rv(br, other, 0.0), rng.randf_range(MON_SECOND[0], MON_SECOND[1])), MON_SECOND[0], MON_SECOND[1])
		tops[other] = rng.randf_range(MON_PEAK_SECOND[0], MON_PEAK_SECOND[1])
		var third := "eye"
		for k: String in ["speed", "defense"]:
			if _rv(br, k, 0.0) > _rv(br, third, 0.0):
				third = k
		entry[third] = clampf(maxf(_rv(br, third, 0.0), rng.randf_range(MON_THIRD[0], MON_THIRD[1])), MON_THIRD[0], MON_THIRD_CAP)
		tops[third] = rng.randf_range(MON_PEAK_SECOND[0], MON_PEAK_SECOND[1])
		for k: String in ["eye", "speed", "defense", "arm"]:
			if not entry.has(k):
				entry[k] = maxf(_rv(br, k, 0.0), rng.randf_range(MON_FLOOR[0], MON_FLOOR[1]))
		for k: String in entry:
			_set_rating(br, k, entry[k])
		var f: Dictionary = p.get("fielding", {}).get(p["primary_pos"], {})
		for k: String in ["defense", "arm"]:
			if not f.is_empty() and br.get(k) is Dictionary:
				f[k] = br[k].duplicate()
	for k: String in entry:
		var pk := minf(99.0, float(entry[k]) + rng.randf_range(grow[0], grow[1]))
		if tops.has(k):
			pk = maxf(pk, float(tops[k]))
		peak[k] = maxf(float(peak.get(k, 0.0)), pk)


## 本格二刀流（型 A。作業86）の入団時の能力・球速とピーク、超目玉の扱い。投手として登録し（先発）、打撃・外野の守備も持つ。
## 投手：奪三振 86〜93（決め球が付く）・制球 66〜80・被本塁打 74〜84・スタミナ 64〜76・球速 155〜160km。
## 打者：ミートかパワーが 82〜92（A〜S）、もう一方 70〜80、選球眼・走力 60〜72、肩 82〜92・守備 58〜68
func _two_way_ace(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var hs := str(p["category"]) == "高校"
	var grow: Array = MON_GROW_HS if hs else MON_GROW
	if not p.get("pitching") is Dictionary or not p.get("batting") is Dictionary:
		return
	var peak: Dictionary = p["growth"]["peak"]
	var pit: Dictionary = p["pitching"]
	if not pit.get("ratings") is Dictionary:
		pit["ratings"] = {}
	var pr: Dictionary = pit["ratings"]
	var bat: Dictionary = p["batting"]
	if not bat.get("ratings") is Dictionary:
		bat["ratings"] = {}
	var br: Dictionary = bat["ratings"]
	var entry := {}  # [ratings, 能力名, 値]
	var up := func(r: Dictionary, k: String, range_: Array) -> void:
		var v := clampf(maxf(_rv(r, k, 0.0), rng.randf_range(range_[0], range_[1])), range_[0], maxf(range_[1], _rv(r, k, 0.0)))
		_set_rating(r, k, v)
		entry[k] = v
	up.call(pr, "k9", TW_K9)
	up.call(pr, "bb9", TW_BB9)
	up.call(pr, "hr9", TW_HR9)
	up.call(pr, "stamina", TW_STAMINA)
	_set_rating(pr, "overall", (_rv(pr, "k9", 80.0) + _rv(pr, "bb9", 70.0) + _rv(pr, "hr9", 75.0)) / 3.0)
	entry["overall"] = _rv(pr, "overall", 0.0)
	if not pit.get("velocity") is Dictionary:
		pit["velocity"] = {"kmh": 150, "source": "fictional"}
	var kmh := maxf(float(pit["velocity"].get("kmh", 0)), rng.randf_range(TW_VELO[0], TW_VELO[1]))
	pit["velocity"]["kmh"] = roundi(kmh)
	var vg: Array = MON_VELO_GROW_HS if hs else MON_VELO_GROW
	peak["velocity"] = minf(MON_VELO_PEAK_MAX, maxf(float(peak.get("velocity", 0.0)), kmh + rng.randf_range(vg[0], vg[1])))
	pit["role"] = "先発"
	var meet := _rv(br, "meet", 0.0)
	var power := _rv(br, "power", 0.0)
	var weapon := "power" if power > meet + 10.0 else ("meet" if meet > power + 10.0 else ("power" if rng.randf() < 0.65 else "meet"))
	up.call(br, weapon, TW_BAT_WEAPON)
	up.call(br, "meet" if weapon == "power" else "power", TW_BAT_SECOND)
	up.call(br, "eye", TW_BAT_FLOOR)
	up.call(br, "speed", TW_BAT_FLOOR)
	up.call(br, "arm", TW_ARM)
	up.call(br, "defense", TW_DEFENSE)
	for k: String in entry:
		var pk := minf(99.0, float(entry[k]) + rng.randf_range(grow[0], grow[1]))
		if k == "k9" or k == weapon:
			pk = maxf(pk, rng.randf_range(TW_PEAK_TOP[0], TW_PEAK_TOP[1]))
		peak[k] = maxf(float(peak.get(k, 0.0)), pk)
	# 投手として登録する（野手が本職の候補でも先発する。打撃・外野の守備は持ったまま）
	p["is_pitcher"] = true
	p["side"] = "P"
	p["primary_pos"] = "投手"
	var am: Dictionary = p["amateur"]
	if not bool(am.get("as_ikusei", false)):
		am["grade"] = "S"
		am["band"] = "1"
		am["as_round"] = 1
		am["projected"] = "超目玉（二刀流）"
		am["bids"] = maxi(int(am.get("bids", 1)), rng.randi_range(3, 6))


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


## 守備位置・守備力・肩（作業66。tools/amateur_ratings.py の assign_fielding と同じ決め方）。
## 区分の守備位置（内野手）は守備力・肩から遊撃手・三塁手・二塁手・一塁手に分け（SimPlayer は「内野手」の位置を知らず、
## 試合で本職の位置が不慣れの扱いになっていた）、近い位置も少し下げて守れるようにする。投手にも投手の守備力を付ける。
## 選手ごとのゆらぎは id から決める（乱数を使わない。あとの抽選・指名の乱数をずらさない）
static func fill_fielding(p: Dictionary) -> void:
	var am: Dictionary = p.get("amateur", {})
	var hs := str(am.get("category", p.get("category", ""))) == "高校"
	if bool(p.get("is_pitcher", false)):
		var e := {"games": 0, "defense": {}, "gold_glove": false}
		_set_rating(e, "defense", float(PITCH_FIELD_LEVEL.get(str(am.get("grade", "C")), 70))
			- (PITCH_FIELD_HS_GAP if hs else 0.0) + _field_spread(p))
		p["fielding"] = {"投手": e}
		return
	var br: Dictionary = p["batting"]["ratings"]
	var d := _rv(br, "defense", 50.0)
	var arm := _rv(br, "arm", 50.0)
	var primary := str(p.get("primary_pos", ""))
	if not primary in FIELD_POS:
		primary = infield_pos(d, arm, hs)
	var out := {primary: _field_entry(primary, d, arm)}
	var subs: Dictionary = SUB_POS.get(primary, {})
	for x: String in subs:
		out[x] = _field_entry(x, d + float(subs[x]), arm)
	# ユーティリティ（作業67の型）は内野のどこでも・外野も守れる
	if str(am.get("type", "")) == "ユーティリティ":
		for x: String in ["二塁手", "三塁手", "遊撃手", "一塁手", "外野手"]:
			if not out.has(x):
				out[x] = _field_entry(x, d - 4.0, arm)
	p["primary_pos"] = primary
	p["fielding"] = out


## 入団時の弾道（作業66の続き。tools/amateur_ratings.py の rookie_trajectory と同じ式。架空の候補には評判の言葉が無いので評判は0）：
## 点 = パワー + TRAJ_SHAPE ×（パワー − ミート）が TRAJ_CUTS 以上なら 4・3・2、ほかは1（4 はパワー TRAJ_4_POWER 以上だけ）。
## 投手は1のまま（二刀流の投手は打撃の能力から決める）
static func set_trajectory(p: Dictionary) -> void:
	var two_way: Variant = p.get("two_way")
	var bats := not bool(p.get("is_pitcher", false)) or (two_way is Dictionary and bool(two_way.get("active", false)))
	var bat: Variant = p.get("batting")
	if not bats or not bat is Dictionary or not bat.get("ratings") is Dictionary or not bat["ratings"].has("power"):
		return
	var r: Dictionary = bat["ratings"]
	var pw := _rv(r, "power", 50.0)
	var score := pw + TRAJ_SHAPE * (pw - _rv(r, "meet", 50.0))
	var t := 1
	for c: Array in TRAJ_CUTS:
		if score >= float(c[0]) and (int(c[1]) < 4 or pw >= TRAJ_4_POWER):
			t = int(c[1])
			break
	bat["trajectory"] = t


## 作業66より前に作った架空の選手（古いセーブの候補・架空の年の能力値）を今の形にする（作業69）：守備位置が「内野手」などの区分のまま
## （試合では本職でも不慣れの扱い）・投手の守備力なし・弾道なし（選手詳細で「－」）。直したら true
static func upgrade_old(p: Dictionary) -> bool:
	if not is_fictional_amateur(p) and not str(p.get("id", "")).begins_with("fic:") and not str(p.get("id", "")).begins_with("rei:"):
		return false
	var changed := false
	var f: Variant = p.get("fielding")
	if bool(p.get("is_pitcher", false)):
		if not f is Dictionary or not f.has("投手"):
			fill_fielding(p)
			changed = true
		return changed
	if not p.get("batting") is Dictionary or not p["batting"].get("ratings") is Dictionary:
		return false
	var old_pos := not str(p.get("primary_pos", "")) in FIELD_POS
	if f is Dictionary:
		for k: String in f:
			old_pos = old_pos or not k in FIELD_POS
	if old_pos or not f is Dictionary or f.is_empty():
		# 守備力・肩は今の値（区分の守備位置の値か打撃の側の値）のまま、具体的な守備位置に分ける
		var br: Dictionary = p["batting"]["ratings"]
		var cur: Dictionary = f.get(str(p.get("primary_pos", "")), {}) if f is Dictionary else {}
		for k: String in ["defense", "arm"]:
			if cur.get(k) is Dictionary and not br.get(k) is Dictionary:
				br[k] = cur[k].duplicate()
		fill_fielding(p)
		changed = true
	if p["batting"].get("trajectory") == null:
		set_trajectory(p)
		changed = true
	return changed


## ピーク（growth.peak）は入団時を下回らないようにだけする（型・物語で入団時の能力を動かしたあと）
static func _sync_peak(p: Dictionary) -> void:
	var peak: Variant = p.get("growth", {}).get("peak")
	if not peak is Dictionary:
		return
	for part: String in ["batting", "pitching"]:
		var block: Variant = p.get(part)
		if not block is Dictionary or not block.get("ratings") is Dictionary:
			continue
		for k: String in block["ratings"]:
			var r: Variant = block["ratings"][k]
			if peak.has(k) and r is Dictionary and r.get("value") != null:
				peak[k] = maxf(float(peak[k]), float(r["value"]))


## 本格二刀流（型 A）の持ち球を作り、決め球を TW_ACE_MOVE_MIN 以上・奪三振を TW_K9 の下限以上にする（作業89。奪三振・被弾抑制は
## 持ち球から計算し直す）。year・型の名前（球種の選びやすさ）は候補の持ち球を作るとき（GameData.set_draft_class の ensure_all）と
## 同じにして、あとで作り直されないように
func _ace_pitch(p: Dictionary, year: int) -> void:
	var hint := str(p.get("amateur", {}).get("type_key", ""))
	PitchArsenal.raise_best(p, TW_ACE_MOVE_MIN, year, hint)
	PitchArsenal.lift_k(p, float(TW_K9[0]), TW_ACE_MOVE_MAX, year, hint)


## 書き方の無い内野手の位置（守備力 → 遊撃手、肩 → 三塁手、守備力 → 二塁手、ほかは一塁手。高校は FIELD_HS_GAP 下げる）
static func infield_pos(d: float, arm: float, hs: bool) -> String:
	var gap := FIELD_HS_GAP if hs else 0.0
	if d >= INFIELD_SS_DEF - gap:
		return "遊撃手"
	if arm >= INFIELD_3B_ARM - gap:
		return "三塁手"
	return "二塁手" if d >= INFIELD_2B_DEF - gap else "一塁手"


static func _field_entry(pos: String, d: float, arm: float) -> Dictionary:
	var e := {"games": 0, "defense": {}, "gold_glove": false}
	_set_rating(e, "defense", d)
	if pos in ARM_POS:
		_set_rating(e, "arm", arm)
	return e


static func _field_spread(p: Dictionary) -> float:
	return float(posmod(str(p.get("id", p.get("name", ""))).hash(), 2 * FIELD_SPREAD + 1) - FIELD_SPREAD)


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
		target = minf(RATING_CAP, maxf(lv[1], lv[0] - LEVEL_STEP * i) + (2.0 * shift if deep else maxf(shift, -1.0))
			+ float(p.get("_theme_bonus", 0.0)))
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
	if p.has("_type"):
		FictionalTypes.apply_shape(p, str(p["_type"]), str(p.get("_grade", grade)), target, weapon, cap, rng)
	if not bool(p["is_pitcher"]):
		var br2: Dictionary = part["ratings"]
		var f: Dictionary = p.get("fielding", {}).get(p["primary_pos"], {})
		for k: String in ["defense", "arm"]:
			if not f.is_empty() and br2.get(k) is Dictionary:
				f[k] = br2[k].duplicate()
	var peak: Dictionary = p.get("growth", {}).get("peak", {})
	for k: String in part["ratings"]:
		if peak.has(k) and part["ratings"][k] is Dictionary:
			peak[k] = maxf(float(peak[k]), float(part["ratings"][k]["value"]))
	if not bool(p.get("is_monster", false)):
		# 候補の乱数（rng）の並びを変えないよう、選手ごとの乱数で決める（ほかの候補の能力が前と同じになる）
		var room_rng := RandomNumberGenerator.new()
		room_rng.seed = ("room#%s" % str(p.get("id", ""))).hash() ^ rng.seed
		_ensure_room(p, part["ratings"], peak, room_rng)


## 作業83（伸びしろ）：ピークが入団時とほとんど同じ候補（司令塔の見本：社会人の投手 総合B75→B75）を無くす。
## 区分ごとに [伸びる能力の数, 伸びの下限, 上限]。足りなければ、今いちばん伸びる能力から順にピークを入団時＋伸びまで上げる
## （投手は総合のピークも奪三振・制球・被弾抑制の上げた分の 1/3 ずつ上げる）。社会人・独立の完成型は小さいままでよい（ユーザー決定）
const ROOM := {"高校": [2, 6.0, 12.0], "大学": [1, 5.0, 10.0], "専門": [1, 5.0, 10.0], "社会人": [1, 3.0, 7.0], "独立": [1, 3.0, 7.0]}
const ROOM_BAT_KEYS := ["meet", "power", "eye", "defense", "speed"]
const ROOM_PIT_KEYS := ["k9", "bb9", "hr9"]
## ピークの上限（怪物でない候補）
const ROOM_PEAK_CAP := 95.0


func _ensure_room(p: Dictionary, r: Dictionary, peak: Dictionary, rng: RandomNumberGenerator) -> void:
	var cat := str(p.get("category", ""))
	var rule: Array = ROOM.get(cat, [])
	if rule.is_empty() or peak.is_empty():
		return
	if cat in ["社会人", "独立"] and FictionalTypes.is_complete(str(p.get("_type", ""))):
		return
	var pit := bool(p["is_pitcher"])
	var keys: Array = (ROOM_PIT_KEYS if pit else ROOM_BAT_KEYS).filter(func(k: String) -> bool:
		return peak.has(k) and r.get(k) is Dictionary)
	var gain := func(k: String) -> float: return float(peak[k]) - float(r[k]["value"])
	keys.sort_custom(func(a: String, b: String) -> bool: return float(gain.call(a)) > float(gain.call(b)))
	var need := int(rule[0])
	var lo := float(rule[1])
	var have := keys.filter(func(k: String) -> bool: return float(gain.call(k)) >= lo).size()
	var raised := 0.0
	for k: String in keys:
		if have >= need:
			break
		if float(gain.call(k)) >= lo:
			continue
		var v := float(r[k]["value"])
		var to := minf(ROOM_PEAK_CAP, v + rng.randf_range(lo, float(rule[2])))
		if to <= float(peak[k]):
			continue
		raised += to - float(peak[k])
		peak[k] = to
		have += 1
	if pit and raised > 0.0 and peak.has("overall"):
		peak["overall"] = minf(ROOM_PEAK_CAP, float(peak["overall"]) + raised / 3.0)


func _pick_templates(n: int, ikusei: bool, rng: RandomNumberGenerator, theme := "例年並み") -> Array:
	var pool: Array = []
	var w_max := 0.0
	for t: Dictionary in data.get("templates", []):
		if bool(t["ikusei"]) == ikusei:
			pool.append(t)
			w_max = maxf(w_max, FictionalTypes.template_weight(theme, t))
	var out: Array = []
	if pool.is_empty():
		return out
	# 年の色の倍率で選び直す（倍率の高いひな形ほど残りやすい）
	for i in n:
		var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		for _try in 8:
			if rng.randf() * w_max <= FictionalTypes.template_weight(theme, t):
				break
			t = pool[rng.randi_range(0, pool.size() - 1)]
		out.append(t)
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
			peak[k] = minf(SimPlayer.SCALE_MEAN + (v - SimPlayer.SCALE_MEAN) * scale + rng.randfn(0.0, REINCARNATION_NOISE), REINCARNATION_MAX)

	if side == "B":
		p["batting"] = {"ratings": {}, "sample": {"pa_1": 0.0, "pa_2": 0.0}, "trajectory": 3}
		for k: String in ["meet", "power", "eye", "speed", "defense", "arm"]:
			var pk: float = float(peak.get(k, 50))
			var ent: int = clampi(roundi(pk - REINCARNATION_ENTRY_GAP_BAT + rng.randfn(0.0, 3.0)), 20, 99)
			p["batting"]["ratings"][k] = {"value": ent, "rank": FictionalTalent._ability_rank(ent)}
		p["pitching"] = null
		p["fielding"] = {}
		var def_val: int = int(p["batting"]["ratings"]["defense"]["value"])
		var arm_val: int = int(p["batting"]["ratings"]["arm"]["value"])
		p["fielding"][p["primary_pos"]] = {"games": 0, "defense": {"value": def_val, "rank": FictionalTalent._ability_rank(def_val)}, "arm": {"value": arm_val, "rank": FictionalTalent._ability_rank(arm_val)}}
	else:
		p["pitching"] = {"ratings": {}, "velocity": {"kmh": roundi(float(peak.get("velocity", 145)) - REINCARNATION_ENTRY_GAP_VELO), "source": "fictional"}, "role": legend.get("role", "先発"), "sample": {"outs_1": 0.0, "outs_2": 0.0}}
		for k: String in ["overall", "stamina", "k9", "bb9", "hr9"]:
			var pk: float = float(peak.get(k, 50))
			var ent: int = clampi(roundi(pk - REINCARNATION_ENTRY_GAP_PIT + rng.randfn(0.0, 3.0)), 20, 99)
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
	var mid: Array = []
	for p: Dictionary in out:
		var am: Dictionary = p["amateur"]
		if bool(am.get("as_ikusei", false)):
			continue
		if am["grade"] in ["S", "A"]:
			top.append(p)
		elif am["grade"] in ["B", "C"] and str(am.get("category", "")) in MLB_MID_CATEGORIES:
			mid.append(p)
	for i in n:
		var from_mid := (rng.randf() < MLB_INTENT_MID and not mid.is_empty()) or top.is_empty()
		var pool: Array = mid if from_mid else top
		if pool.is_empty():
			break
		var j := rng.randi_range(0, pool.size() - 1)
		var p: Dictionary = pool[j]
		var notes: Array = MLB_MID_NOTES if from_mid else MLB_TOP_NOTES
		var note := str(notes[rng.randi_range(0, notes.size() - 1)]).format({"school": p["amateur"]["school"],
			"name": p["name"]})
		p["amateur"]["mlb_intent"] = {"stated": true, "note": note}
		pool.remove_at(j)


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


## 型なしの候補の紹介文の言葉（右腕・左腕・捕手・内野手・外野手。作業89）
static func plain_word(p: Dictionary) -> String:
	if bool(p.get("is_pitcher", false)):
		return "左腕" if str(p.get("throws", "")) == "左" else "右腕"
	return FictionalTypes.pos_group(p)


static func type_word(p: Dictionary) -> String:
	var t := str(p.get("amateur", {}).get("type", ""))
	return t if not t.is_empty() else FictionalTalent.decide_player_type(p)


static func intro_of(p: Dictionary) -> String:
	var am: Dictionary = p.get("amateur", {})
	var sch: String = str(am.get("school", ""))
	var t_word: String = str(am.get("type", type_word(p)))
	if t_word.is_empty():
		t_word = plain_word(p)  # 型なし（作業89）
	var story := str(am.get("story", ""))
	return "%sの%s" % [sch, t_word] + ("。%s" % story if not story.is_empty() else "")
