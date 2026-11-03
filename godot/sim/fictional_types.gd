class_name FictionalTypes
extends RefCounted
## 架空のドラフト候補の型・年の色・物語（docs/AUTORUN.md 作業67）。
## ユーザーの声（2026-11-03）：「みんな能力が同じぐらいすぎない？」（外野手はほとんど「走力だけ B〜A、残りは C〜D」）。
## - 型：守備位置ごとに10前後。型ごとに長所（B〜A）と短所（E〜F）の能力をはっきり決め、評価の高い選手ほど長所が多い。
##   入団時の総合（作業62の物差し。投手は総合、野手は FictionalDraft.entry_level）は変えずに、能力の形だけを作り直す
## - 年の色：年ごとに「投手の豊作年」などを1つ選び、候補の顔ぶれ（ひな形の選び方）と質（入団時の総合）を偏らせる
## - 物語：一部の候補に経歴の物語（無名校の隠し玉・元投手の野手など）。物語に合わせて能力も少し動かす
## 入団時の能力だけを動かす（ピークは入団時を下回らないようにだけする。報告・画面にピークは出さない）

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
## 投手の形を作る能力（velocity は km/h で別に扱う）
const PIT_KEYS := ["k9", "bb9", "hr9", "stamina"]
## 野手の入団時の総合の重み（FictionalDraft._bat_composite と同じ。守備は −13 の分を含めて1次）
const BAT_WEIGHT := {"meet": 0.35, "power": 0.35, "eye": 0.1, "speed": 0.1, "defense": 0.1}

## 型：名前 → {pos：守備位置の区分（投手・捕手・内野手・外野手。共通は "共通"）, w：選ばれやすさ, s：長所（強い順）, d：短所（弱い順）, 付け足し}
## 付け足し：bats（打席）・throws（投げる手）・role（投手の役割）・wild（長所1つを極端に・短所を3つ）・flat（短所なし・長所は控えめ）・
## utility（守れる位置を増やす）・velo（球速の長所・短所。km/h）
const TYPES := {
	# 投手
	"本格派の剛腕": {"pos": "投手", "w": 14, "s": ["k9", "velocity", "stamina"], "d": ["bb9"], "velo": 5},
	"技巧派": {"pos": "投手", "w": 11, "s": ["bb9", "hr9", "stamina"], "d": ["velocity", "k9"], "velo": -5},
	"制球職人": {"pos": "投手", "w": 9, "s": ["bb9", "stamina", "hr9"], "d": ["k9", "velocity"], "velo": -4},
	"荒れ球の豪腕": {"pos": "投手", "w": 7, "s": ["velocity", "k9", "hr9"], "d": ["bb9", "stamina"], "velo": 7},
	"サイドスロー": {"pos": "投手", "w": 6, "s": ["hr9", "bb9", "k9"], "d": ["velocity"], "velo": -5},
	"アンダースロー": {"pos": "投手", "w": 2, "s": ["hr9", "bb9", "stamina"], "d": ["velocity", "k9"], "velo": -9},
	"先発完投型": {"pos": "投手", "w": 11, "s": ["stamina", "bb9", "hr9"], "d": ["k9"], "role": "先発"},
	"リリーフ専任": {"pos": "投手", "w": 10, "s": ["k9", "velocity", "hr9"], "d": ["stamina"], "role": "救援", "velo": 3},
	"左のワンポイント": {"pos": "投手", "w": 5, "s": ["k9", "hr9"], "d": ["stamina", "velocity"], "role": "救援", "throws": "左",
		"velo": -3},
	"未完の大器（投手）": {"pos": "投手", "w": 4, "s": ["velocity", "k9"], "d": ["bb9", "hr9", "stamina"], "wild": true, "velo": 8,
		"label": "未完の大器"},
	"完成型（投手）": {"pos": "投手", "w": 0, "s": [], "d": [], "complete": true, "label": "完成型", "role": "先発"},
	# 捕手
	"強肩の守備型捕手": {"pos": "捕手", "w": 10, "s": ["arm", "defense", "eye"], "d": ["power", "speed"]},
	"打てる捕手": {"pos": "捕手", "w": 8, "s": ["meet", "power", "eye"], "d": ["defense", "speed"]},
	"大型捕手": {"pos": "捕手", "w": 6, "s": ["power", "arm", "defense"], "d": ["speed", "meet"]},
	"頭脳派の司令塔": {"pos": "捕手", "w": 6, "s": ["defense", "eye", "meet"], "d": ["power", "speed"]},
	# 内野手
	"守備職人": {"pos": "内野手", "w": 10, "s": ["defense", "arm", "speed"], "d": ["power", "meet"]},
	"内野の長距離砲": {"pos": "内野手", "w": 8, "s": ["power", "eye", "arm"], "d": ["speed", "defense"]},
	"巧打のリードオフ": {"pos": "内野手", "w": 9, "s": ["meet", "speed", "eye"], "d": ["power", "arm"]},
	"ユーティリティ": {"pos": "内野手", "w": 7, "s": ["defense", "speed", "meet"], "d": ["power"], "utility": true},
	"強打の三塁手": {"pos": "内野手", "w": 5, "s": ["power", "arm", "meet"], "d": ["speed"]},
	# 外野手
	"俊足巧打": {"pos": "外野手", "w": 10, "s": ["speed", "meet", "defense"], "d": ["power", "arm"]},
	"外野の長距離砲": {"pos": "外野手", "w": 9, "s": ["power", "eye", "meet"], "d": ["speed", "defense"]},
	"強肩外野手": {"pos": "外野手", "w": 7, "s": ["arm", "defense", "power"], "d": ["meet", "eye"]},
	"中距離ヒッター": {"pos": "外野手", "w": 9, "s": ["meet", "power", "eye"], "d": ["speed", "arm"]},
	"守備の名手": {"pos": "外野手", "w": 5, "s": ["defense", "speed", "arm"], "d": ["power", "eye"]},
	# 野手の共通
	"未完の大器": {"pos": "共通", "w": 4, "s": ["power"], "d": ["meet", "eye", "defense"], "wild": true},
	"万能型": {"pos": "共通", "w": 4, "s": ["meet", "power", "speed"], "d": [], "flat": true},
	"スイッチヒッター": {"pos": "共通", "w": 3, "s": ["meet", "speed", "eye"], "d": ["power"], "bats": "両"},
	"完成型（野手）": {"pos": "共通", "w": 0, "s": [], "d": [], "complete": true, "label": "完成型"},
}
## 完成型（ユーザー：「完成した選手はもう出ないんか？」）：大学・社会人などの評価 S・A・B だけ。どの能力も中央の近く（短所なし）、
## 入団時の総合を COMPLETE_BONUS 上乗せ（その年の上位）、伸びしろは小さめ（早熟。ピークは入団時 + COMPLETE_GROWTH）。
## 未完の大器（極端な長所と短所）と対にして、毎年どちらも MIN_EACH 人は出す（FictionalDraft.generate_year）
const COMPLETE_WEIGHT := {"S": 12.0, "A": 10.0, "B": 6.0}
const COMPLETE_BONUS := 3.0
const COMPLETE_SPREAD := 3.0
const COMPLETE_GROWTH := [2.0, 5.0]
const MIN_EACH := 2
## 一芸だけ S（ユーザー決定）：その年に、長所の能力1つだけが S（90以上。球速は158km以上）の選手が出る確率（年の色で上下）。
## 出ても1人、まれに2人（ONE_SKILL_SECOND）。総合は変えない（ほかの能力で戻す）。怪物とは別の枠（評価 A〜C の本指名の候補から。武器のある高卒の A は除く）
const ONE_SKILL_RATE := 0.6
const ONE_SKILL_THEME := {"投手の豊作年": 0.75, "大型野手の年": 0.75, "高校生の当たり年": 0.7, "大学生の当たり年": 0.7,
	"即戦力の社会人の年": 0.7, "捕手の当たり年": 0.65, "左腕の当たり年": 0.65, "俊足の野手が多い年": 0.7, "不作の年": 0.35}
const ONE_SKILL_SECOND := 0.12
## 一芸にしやすい能力（型の長所の上から2つのうちにあれば7割で選ぶ）
const ONE_SKILL_FAVORED := ["velocity", "power", "speed", "arm"]
const ONE_SKILL_VALUE := [90.0, 94.0]
const ONE_SKILL_KMH := [158, 161]
## 能力の呼び名（紹介文）
const KEY_WORD := {"meet": "ミート", "power": "パワー", "eye": "選球眼", "speed": "走力", "defense": "守備", "arm": "肩",
	"k9": "奪三振", "bb9": "制球", "hr9": "球威", "stamina": "スタミナ", "velocity": "球速"}
## 未完の大器（野手）の長所は、パワーか走力か肩（どれか1つを極端に）
const WILD_BAT_KEYS := ["power", "speed", "arm"]
## 長所の上乗せ（中央からの差。強い順）。短所の下げ幅（弱い順）。wild は長所1つを WILD_STRENGTH、flat は FLAT_STRENGTH
const STRENGTH := [16.0, 12.0, 9.0]
const WEAKNESS := [16.0, 13.0, 11.0]
const WILD_STRENGTH := 24.0
const FLAT_STRENGTH := [8.0, 7.0, 6.0]
## 総合を戻すときの許容のずれ（野手の物差し。投手の物差しで約0.3）
const SETTLE_TOL := 0.15
## 総合の重い能力（野手）と、長所を両方に置ける中央（野手の物差し）の下限
const HEAVY_KEYS := ["meet", "power"]
const HEAVY_BOTH_GOAL := 62.0
## 長所は B 以上（70）、短所は E 以下（49）。怪物以外の上限は FictionalDraft.RATING_CAP（走力は SPEED_CAP）、短所の下限
const STRENGTH_MIN := 70.0
const WEAKNESS_MAX := 49.0
const WEAKNESS_MIN := 30.0
## 怪物の長所の上限
const MONSTER_CAP := 90.0
## 長所の数（評価ごと [最小, 最大]）と短所の数の上限。評価の高い選手ほど長所が多く、短所が少ない
const STRENGTH_COUNT := {"S": [3, 3], "A": [2, 3], "B": [2, 2], "C": [1, 2], "D": [1, 1]}
const WEAKNESS_COUNT := {"S": 1, "A": 1, "B": 2, "C": 2, "D": 2}
## 長所・短所でない能力に、元の能力の個性をどれだけ残すか（中央からの差の割合）と、ゆらぎの幅
const KEEP_SHAPE := 0.35
const NOISE := 3.0
## 作業73（ユーザー：「まだちょとDB BDみたいなの多いな」）：同じ選手の中で同じ数字が並ばないように、
## 得意・不得意の幅を選手ごとにばらつかせる倍率・長所でも短所でもない能力のぶれ（標準偏差）・
## 能力ごとに境目（長所の下限と上限・短所の上限・ほかの能力の範囲）をずらす幅
const AMP_SCALE := [0.7, 1.2]
const FREE_SPREAD := 6.0
const EDGE_JITTER := 3.0
## 評価 B〜D の2つ目からの長所・短所は、SOFT_RATE の確率で「ゆるい長所・短所」にする（中央からの上乗せ・下げ幅はそのまま、
## B 以上・E 以下に収めない。長所でも短所でもない能力の範囲で C の高め・D の低めになる）。1つ目の長所・短所はそのまま
const SOFT_RATE := 0.35
## 長所でも短所でもない能力が下限を下回ったときに、下限から上へ跳ね返す割合（下限に同じような数字が固まらないように）
const FREE_REFLECT := 0.6
const SOFT_GRADES := ["B", "C", "D"]
## それでも並んだ数字は、同じランクの中で UNTIE_STEP ずらす。総合の重みが同じ能力どうしを逆向きに同じだけ動かす
## （重みの無い肩・スタミナは1つだけ）ので総合は変わらない
const UNTIE_STEP := [1, 3]
const UNTIE_ROUNDS := 12
const UNTIE_KEEP := 80
const UNTIE_PARTNERS := {"meet": ["power"], "power": ["meet"], "eye": ["speed", "defense"], "speed": ["eye", "defense"],
	"defense": ["eye", "speed"], "arm": [], "k9": ["bb9", "hr9"], "bb9": ["k9", "hr9"], "hr9": ["k9", "bb9"], "stamina": []}
## 球速（km/h）の上限・下限（怪物以外）
const VELO_MAX := 157
const VELO_MAX_MONSTER := 165
const VELO_MIN := 132
## 投手の役割：スタミナがこれ以上なら先発（Growth.STARTER_STAMINA と同じ境目）
## 当時の評価 S・A の投手は先発型が中心（作業50）。S・A では救援の型を選びにくくする
const SA_RELIEF_WEIGHT := 0.25
## 評価ごとの型の選ばれやすさ：未完の大器は高校生・評価の低い選手に多く、万能型は評価の高い選手に多い
const WILD_HS_WEIGHT := 2.0
const FLAT_SA_WEIGHT := 2.5

## 年の色：名前 → {w：選ばれやすさ, pick：ひな形の選ばれやすさ（投手・野手・区分・守備位置ごとの倍率）, lv：入団時の総合の上乗せ,
## types：型の選ばれやすさの倍率, lefty：左投げの割合, news：ニュースの一文}
## 上乗せは評価 B 以下（deep）だけに足す（作業62の物差し：その年の一番上は78〜82のまま）
const THEMES := {
	"例年並み": {"w": 16, "pick": {}, "lv": {}, "news": ""},
	"投手の豊作年": {"w": 10, "pick": {"投手": 1.4}, "lv": {"投手": 2.0},
		"news": "今年は投手の豊作年。上位候補に好投手がずらりと並び、各球団の1位入札は投手に集まりそうだ"},
	"大型野手の年": {"w": 8, "pick": {"野手": 1.3}, "lv": {"野手": 2.0},
		"types": {"内野の長距離砲": 3.0, "外野の長距離砲": 3.0, "大型捕手": 3.0, "強打の三塁手": 3.0, "未完の大器": 2.0},
		"news": "今年は大型野手の年。長打力が売りの野手がそろい、和製大砲を狙う球団には絶好の年になる"},
	"俊足の野手が多い年": {"w": 6, "pick": {"野手": 1.15},
		"types": {"俊足巧打": 3.0, "巧打のリードオフ": 3.0, "守備職人": 2.0, "守備の名手": 2.0, "スイッチヒッター": 2.0},
		"news": "今年は俊足の野手が多い年。足でかき回せるリードオフ型・守備の名手が上位にも名を連ねる"},
	"高校生の当たり年": {"w": 9, "pick": {"高校": 1.4}, "lv": {"高校": 2.0},
		"news": "今年は高校生の当たり年。甲子園を沸かせた逸材がそろい、将来を見据えた指名が増えそうだ"},
	"大学生の当たり年": {"w": 7, "pick": {"大学": 1.4}, "lv": {"大学": 2.0},
		"news": "今年は大学生の当たり年。即戦力の4年生が多く、1年目からの活躍が期待される"},
	"即戦力の社会人の年": {"w": 6, "pick": {"社会人": 1.6, "独立": 1.4}, "lv": {"社会人": 2.0, "独立": 2.0},
		"news": "今年は即戦力の社会人の年。都市対抗で鍛えられた実戦派が多く、戦力の上積みを狙う球団に人気だ"},
	"捕手の当たり年": {"w": 5, "pick": {"捕手": 2.0}, "lv": {"捕手": 2.0},
		"news": "今年は捕手の当たり年。強肩・好打の捕手がそろい、正捕手候補を求める球団の争奪戦になりそうだ"},
	"左腕の当たり年": {"w": 5, "pick": {"投手": 1.15}, "lv": {"投手": 1.0}, "lefty": 0.5,
		"types": {"左のワンポイント": 2.0},
		"news": "今年は左腕の当たり年。先発・中継ぎともに好左腕が多く、左投手の補強を狙う球団には好機だ"},
	"不作の年": {"w": 7, "pick": {}, "lv": {"全員": -2.0},
		"news": "今年は不作の年との声が多い。目玉の数は例年並みでも、中位以下の層が薄く、各球団のスカウトは頭を抱える"},
}

## 物語：キー → {text：紹介文（{school}・{other}・{age} を埋める）, 条件, 能力の動き}
## 1年に STORY_COUNT 人ほど（本指名の候補から。条件に合う候補がいなければ付けない）
const STORY_COUNT := [5, 9]
const STORIES := {
	"rival": {"label": "甲子園で投げ合った2人", "text": "2年の夏の甲子園で{other}（{other_school}）と投げ合ったライバル"},
	"hidden": {"label": "無名校の隠し玉", "text": "甲子園の出場経験の無い{school}で、スカウトが通い続けた隠し玉"},
	"comeback": {"label": "けがから復活した大学生", "text": "高校3年で{injury}を痛め、大学で復活を遂げた"},
	"convert_bat": {"label": "元投手から野手に転向", "text": "高校時代はエース。野手に転向して強肩を生かす"},
	"convert_pit": {"label": "野手から投手に転向", "text": "内野手から投手に転向して2年。荒削りだが伸びしろは大きい"},
	"indie": {"label": "独立リーグの苦労人", "text": "大学を中退し、独立リーグで腕を磨いてきた{age}歳の苦労人"},
	"late": {"label": "社会人で花開いた遅咲き", "text": "高卒で入社して{years}年目、{age}歳で花開いた遅咲き"},
	"captain": {"label": "名門の主将", "text": "名門{school}で主将を務めたリーダー"},
	"family": {"label": "野球一家", "text": "父も兄も社会人野球の選手だった野球一家に育つ"},
}
const INJURIES := ["肘", "肩", "腰"]
## 物語の選ばれやすさ（甲子園で投げ合った2人は別に、半分ほどの年に1組）
const STORY_WEIGHT := {"hidden": 3, "comeback": 3, "convert_bat": 3, "convert_pit": 2, "indie": 3, "late": 3, "captain": 2,
	"family": 1}


## その年の色のニュース [見出し, 本文]（例年並みは空）
static func theme_article(theme: String) -> Array:
	var text := str(THEMES.get(theme, {}).get("news", ""))
	if text.is_empty():
		return []
	var head := "今年は%s？ スカウトの声" % theme if theme == "不作の年" else "今年は%s" % theme
	return [head, text + "。"]


## 型の表示名（手帳の札・表・作戦会議）
static func label_of(type_name: String) -> String:
	return str(TYPES.get(type_name, {}).get("label", type_name))


static func is_complete(type_name: String) -> bool:
	return bool(TYPES.get(type_name, {}).get("complete", false))


static func is_wild(type_name: String) -> bool:
	return bool(TYPES.get(type_name, {}).get("wild", false))


## 年の色を選ぶ
static func pick_theme(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in THEMES:
		total += float(THEMES[k]["w"])
	var x := rng.randf() * total
	for k: String in THEMES:
		x -= float(THEMES[k]["w"])
		if x <= 0.0:
			return k
	return "例年並み"


## ひな形の選ばれやすさ（年の色の倍率）
static func template_weight(theme: String, t: Dictionary) -> float:
	var pick: Dictionary = THEMES.get(theme, {}).get("pick", {})
	var w := 1.0
	var side := "投手" if str(t.get("side", "")) == "P" else "野手"
	for k: String in [side, str(t.get("category", "")), str(t.get("pos", ""))]:
		w *= float(pick.get(k, 1.0))
	return w


## 年の色による入団時の総合の上乗せ（評価 B 以下に足す）
static func level_bonus(theme: String, p: Dictionary) -> float:
	var lv: Dictionary = THEMES.get(theme, {}).get("lv", {})
	var side := "投手" if bool(p.get("is_pitcher", false)) else "野手"
	var b := float(lv.get("全員", 0.0))
	for k: String in [side, str(p.get("category", "")), str(p.get("primary_pos", ""))]:
		b += float(lv.get(k, 0.0))
	return b


## 型を選ぶ（守備位置・評価・年の色で重み付け）
static func pick_type(p: Dictionary, grade: String, theme: String, rng: RandomNumberGenerator) -> String:
	var pitcher := bool(p.get("is_pitcher", false))
	var group := "投手" if pitcher else pos_group(p)
	var mult: Dictionary = THEMES.get(theme, {}).get("types", {})
	var hs := str(p.get("category", "")) == "高校"
	var names: Array = []
	var ws: Array = []
	var total := 0.0
	for name: String in TYPES:
		var t: Dictionary = TYPES[name]
		if t["pos"] != group and not (t["pos"] == "共通" and not pitcher):
			continue
		var w := float(t["w"]) * float(mult.get(name, 1.0))
		if bool(t.get("complete", false)):
			w = 0.0 if hs or bool(p.get("is_monster", false)) else float(COMPLETE_WEIGHT.get(grade, 0.0))
		if bool(t.get("wild", false)) and (hs or grade in ["C", "D"]):
			w *= WILD_HS_WEIGHT
		if bool(t.get("flat", false)) and grade in ["S", "A"]:
			w *= FLAT_SA_WEIGHT
		if str(t.get("role", "")) == "救援" and grade in ["S", "A"]:
			w *= SA_RELIEF_WEIGHT
		names.append(name)
		ws.append(w)
		total += w
	var x := rng.randf() * total
	for i in names.size():
		x -= float(ws[i])
		if x <= 0.0:
			return names[i]
	return names[-1] if not names.is_empty() else ""


## 守備位置の4区分（Draft._pos_of と同じ。Draft は GameData に頼るので使わない）
static func pos_group(p: Dictionary) -> String:
	if bool(p.get("is_pitcher", false)):
		return "投手"
	var pos := str(p.get("primary_pos", ""))
	if pos == "捕手":
		return "捕手"
	return "外野手" if pos.contains("外野") or pos in ["左翼手", "中堅手", "右翼手"] else "内野手"


## 守備位置に合う完成型・未完の大器の型の名前
static func complete_type(p: Dictionary) -> String:
	return "完成型（投手）" if bool(p.get("is_pitcher", false)) else "完成型（野手）"


static func wild_type(p: Dictionary) -> String:
	return "未完の大器（投手）" if bool(p.get("is_pitcher", false)) else "未完の大器"


## 型の能力の形を入れる。入団時の総合（target）は変えない。weapon：高卒の S・A の武器（FictionalDraft._calibrate_entry）
static func apply_shape(p: Dictionary, type_name: String, grade: String, target: float, weapon: float, cap: float,
		rng: RandomNumberGenerator) -> void:
	var t: Dictionary = TYPES.get(type_name, {})
	if t.is_empty():
		return
	var monster := bool(p.get("is_monster", false))
	var cnt: Array = STRENGTH_COUNT.get(grade, [1, 2])
	var n_s := 3 if monster else rng.randi_range(int(cnt[0]), int(cnt[1]))
	var n_d := 0 if monster else int(WEAKNESS_COUNT.get(grade, 2))
	if bool(t.get("complete", false)):
		_shape_complete(p, t, target, cap, rng)
		return
	var strong: Array = (t["s"] as Array).duplicate()
	var weak: Array = (t["d"] as Array).duplicate()
	var amp: Array = STRENGTH
	if bool(t.get("wild", false)):
		if not bool(p["is_pitcher"]):
			strong = [WILD_BAT_KEYS[rng.randi_range(0, WILD_BAT_KEYS.size() - 1)]]
			weak.erase(strong[0])
			p["amateur"]["wild_key"] = strong[0]
		amp = [WILD_STRENGTH, STRENGTH[1]]
		n_s = mini(n_s, strong.size())
		n_d = 3
	elif bool(t.get("flat", false)):
		amp = FLAT_STRENGTH
		n_d = 0
	if not bool(p["is_pitcher"]):
		# 総合の重い能力（ミート・パワー）：評価 S・A は短所にしない（総合が届かなくなる）。
		# 総合の低い選手は長所を両方にしない（ほかの能力が下限まで削られる）
		if grade in ["S", "A"] or monster:
			weak = weak.filter(func(k: String) -> bool: return not k in HEAVY_KEYS)
		var goal := FictionalDraft.BAT_MID + (target - FictionalDraft.PITCH_MID) / FictionalDraft.BAT_TO_PITCH
		if goal < HEAVY_BOTH_GOAL and "meet" in strong.slice(0, n_s) and "power" in strong.slice(0, n_s):
			strong.erase("meet" if strong.find("meet") > strong.find("power") else "power")
	strong = strong.slice(0, mini(n_s, strong.size()))
	weak = weak.slice(0, mini(n_d, weak.size()))
	var soft: Array = []
	if grade in SOFT_GRADES and not monster and not bool(t.get("wild", false)) and not bool(t.get("flat", false)):
		for k: String in strong.slice(1) + weak.slice(1):
			if k != "velocity" and rng.randf() < SOFT_RATE:
				soft.append(k)
	if bool(p["is_pitcher"]):
		_shape_pitcher(p, t, strong, weak, amp, target, weapon, cap, monster, rng, soft)
	else:
		_shape_batter(p, t, strong, weak, amp, target, weapon, cap, monster, rng, soft)


static func _cap_of(k: String, cap: float, monster: bool, is_strength: bool) -> float:
	if monster and is_strength:
		return MONSTER_CAP
	return FictionalDraft.SPEED_CAP if k == "speed" else cap


static func _shape_batter(p: Dictionary, t: Dictionary, strong: Array, weak: Array, amp: Array, target: float,
		weapon: float, cap: float, monster: bool, rng: RandomNumberGenerator, soft: Array = []) -> void:
	var br: Dictionary = p["batting"]["ratings"]
	var goal := FictionalDraft.BAT_MID + (target - FictionalDraft.PITCH_MID) / FictionalDraft.BAT_TO_PITCH
	var orig_mean := 0.0
	for k: String in BAT_KEYS:
		orig_mean += FictionalDraft._rv(br, k, 50.0) / BAT_KEYS.size()
	# 中央 0 のときの形（得意・不得意の幅は選手ごとに scale 倍。作業73）
	var scale := rng.randf_range(AMP_SCALE[0], AMP_SCALE[1])
	var jit := _edge_jitter(BAT_KEYS, rng)
	var off := {}
	for k: String in BAT_KEYS:
		var i := strong.find(k)
		var j := weak.find(k)
		if i >= 0:
			off[k] = float(amp[mini(i, amp.size() - 1)]) * scale + rng.randf_range(-NOISE, NOISE)
		elif j >= 0:
			off[k] = -float(WEAKNESS[mini(j, WEAKNESS.size() - 1)]) * scale - rng.randf_range(-NOISE, NOISE)
		else:
			off[k] = KEEP_SHAPE * (FictionalDraft._rv(br, k, 50.0) - orig_mean) + rng.randfn(0.0, FREE_SPREAD)
	# ゆるい長所・短所：上乗せ・下げ幅は付けたまま、範囲は長所でも短所でもない能力と同じ
	for k: String in soft:
		strong.erase(k)
		weak.erase(k)
	# 総合（重みの合計は1）が goal になる中央
	var base := goal - _bat_score(off)
	var val := {}
	for k: String in BAT_KEYS:
		val[k] = base + float(off[k])
	# 長所は B 以上・短所は E 以下に収め、ずれた総合は長所でも短所でもない能力で戻す（無ければ武器のほかの全体で）
	var wk := ""
	for _round in 3:
		for k: String in strong + weak:
			var lh := _range_of(k, strong, weak, cap, monster, false, jit)
			val[k] = clampf(float(val[k]), lh[0], lh[1])
		if weapon > 0.0:
			wk = _weapon_up(val, ["power", "speed", "arm"], weapon, strong)
		var diff := goal - _bat_score(val)
		var free: Array = []
		for k: String in BAT_WEIGHT:
			if not k in strong and not k in weak:
				free.append(k)
		if absf(diff) < 0.3:
			break
		var wsum := 0.0
		for k: String in free:
			wsum += float(BAT_WEIGHT[k])
		if wsum < 0.15:
			free = BAT_WEIGHT.keys().filter(func(k: String) -> bool: return k != wk)
		# 戻す量は能力ごとにばらばらに配る（同じだけ動かすと下限に張り付いた能力が同じ数字で並ぶ。作業73）
		var share := _random_share(free, rng)
		for k: String in free:
			val[k] = float(val[k]) + diff * float(share[k])
	for k: String in BAT_KEYS:
		# 長所は B 以上、短所は E 以下、どちらでもない能力は B と E の間（長所・短所の区別をはっきりさせる）。境目は能力ごとに少しずらす
		var lh := _range_of(k, strong, weak, cap, monster, false, jit)
		if k == wk:
			lh[1] = maxf(lh[1], minf(weapon, _cap_of(k, cap, monster, true)))
		var v := float(val[k])
		if not k in strong and not k in weak:
			# 長所でも短所でもない能力：肩（総合に入らない）は元の能力のまま。ほかは下限に張り付かずに跳ね返す（作業73）
			if k == "arm":
				v = FictionalDraft._rv(br, "arm", 55.0) + rng.randfn(0.0, NOISE)
			elif v < lh[0]:
				v = lh[0] + (lh[0] - v) * FREE_REFLECT
		FictionalDraft._set_rating(br, k, clampf(v, lh[0], lh[1]))
	_settle_batter(br, goal, strong, weak, cap, monster, false, jit, rng, wk)
	_settle_batter(br, goal, strong, weak, cap, monster, true, jit, rng, wk)
	if t.has("bats"):
		p["bats"] = str(t["bats"])


static func _shape_pitcher(p: Dictionary, t: Dictionary, strong: Array, weak: Array, amp: Array, target: float,
		weapon: float, cap: float, monster: bool, rng: RandomNumberGenerator, soft: Array = []) -> void:
	var pit: Dictionary = p["pitching"]
	var pr: Dictionary = pit["ratings"]
	# 得意・不得意の幅は選手ごとに scale 倍、境目は能力ごとにずらす（作業73）
	var scale := rng.randf_range(AMP_SCALE[0], AMP_SCALE[1])
	var jit := _edge_jitter(PIT_KEYS, rng)
	var off := {}
	for k: String in PIT_KEYS:
		var i := strong.find(k)
		var j := weak.find(k)
		if i >= 0:
			off[k] = float(amp[mini(i, amp.size() - 1)]) * scale + rng.randf_range(-NOISE, NOISE)
		elif j >= 0:
			off[k] = -float(WEAKNESS[mini(j, WEAKNESS.size() - 1)]) * scale - rng.randf_range(-NOISE, NOISE)
		else:
			off[k] = KEEP_SHAPE * (FictionalDraft._rv(pr, k, target) - target) + rng.randfn(0.0, FREE_SPREAD)
	for k: String in soft:
		strong.erase(k)
		weak.erase(k)
	# 奪三振・制球・被本塁打の平均が総合になる中央（スタミナは別。先発・救援の目安）
	var base := target - (float(off["k9"]) + float(off["bb9"]) + float(off["hr9"])) / 3.0
	var val := {}
	for k: String in ["k9", "bb9", "hr9"]:
		val[k] = base + float(off[k])
	val["stamina"] = FictionalDraft._rv(pr, "stamina", 55.0) * (1.0 - KEEP_SHAPE) + target * KEEP_SHAPE + float(off["stamina"])
	if str(t.get("role", "")) == "先発" or "stamina" in strong:
		val["stamina"] = maxf(float(val["stamina"]), 72.0)
	elif str(t.get("role", "")) == "救援" or "stamina" in weak:
		val["stamina"] = minf(float(val["stamina"]), 45.0)
	for k: String in strong + weak:
		if k != "velocity":
			var lh := _range_of(k, strong, weak, cap, monster, false, jit)
			val[k] = clampf(float(val[k]), lh[0], lh[1])
	if weapon > 0.0:
		val["k9"] = maxf(float(val["k9"]), weapon)
	for k: String in PIT_KEYS:
		var lo := WEAKNESS_MIN if k in weak else 30.0
		var hi := _cap_of(k, cap, monster, k in strong) - (float(jit[k][1]) if k in strong else 0.0)
		if k == "k9" and weapon > 0.0:
			hi = maxf(hi, weapon)  # 高卒の武器（怪物は84〜88）は上限で削らない
		FictionalDraft._set_rating(pr, k, clampf(float(val[k]), lo, hi))
	FictionalDraft._set_rating(pr, "overall", target)
	# 球速：型の長所・短所の分だけ動かす
	var velo: Variant = pit.get("velocity")
	if velo is Dictionary:
		var kmh := float(velo.get("kmh", 145)) + float(t.get("velo", 0)) + rng.randf_range(-1.0, 1.0)
		velo["kmh"] = clampi(roundi(kmh), VELO_MIN, VELO_MAX_MONSTER if monster else VELO_MAX)
	if t.has("throws"):
		p["throws"] = str(t["throws"])
	var st := FictionalDraft._rv(pr, "stamina", 50.0)
	pit["role"] = str(t["role"]) if t.has("role") else Growth.role_of_stamina(st)


## 上限・下限で丸めたあとに残った総合のずれを、範囲の中で動かせる能力で戻す（長所は B〜上限、短所は E 以下、ほかは C〜D）
## jit・rng（作業73）：能力ごとの境目のずらし、戻す量をばらばらに配る乱数（無ければ同じだけ）。keep：動かさない能力（高卒の武器）
static func _settle_batter(br: Dictionary, goal: float, strong: Array, weak: Array, cap: float, monster: bool,
		loose := false, jit := {}, rng: RandomNumberGenerator = null, keep := "") -> void:
	for _round in 8:
		var cur := {}
		for k: String in BAT_WEIGHT:
			cur[k] = FictionalDraft._rv(br, k, 50.0)
		var diff := goal - _bat_score(cur)
		if absf(diff) < SETTLE_TOL:
			return
		var movable: Array = []
		for k: String in BAT_WEIGHT:
			if k == keep:
				continue
			var lo_hi := _range_of(k, strong, weak, cap, monster, loose, jit)
			if (diff > 0.0 and float(cur[k]) < lo_hi[1]) or (diff < 0.0 and float(cur[k]) > lo_hi[0]):
				movable.append(k)
		if movable.is_empty():
			return
		var share := _random_share(movable, rng)
		for k: String in movable:
			var lo_hi := _range_of(k, strong, weak, cap, monster, loose, jit)
			FictionalDraft._set_rating(br, k, clampf(float(cur[k]) + diff * float(share[k]), lo_hi[0], lo_hi[1]))


## 総合のずれ1あたりに各能力を動かす量（重み × 量の合計が1）。rng があれば能力ごとにばらつかせる（作業73）
static func _random_share(keys: Array, rng: RandomNumberGenerator) -> Dictionary:
	var f := {}
	var wsum := 0.0
	for k: String in keys:
		f[k] = rng.randf_range(0.4, 1.6) if rng != null else 1.0
		wsum += float(BAT_WEIGHT.get(k, 0.0)) * float(f[k])
	var out := {}
	for k: String in keys:
		out[k] = float(f[k]) / wsum if wsum > 0.0 else 0.0
	return out


## 能力ごとの境目のずらし（作業73）：[下の境目を上げる幅, 上の境目を下げる幅]
static func _edge_jitter(keys: Array, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for k: String in keys:
		out[k] = [rng.randf_range(0.0, EDGE_JITTER), rng.randf_range(0.0, EDGE_JITTER)]
	return out


## loose：総合が届かないとき（型の形より入団時の総合を優先する）の広い範囲。jit：能力ごとの境目のずらし（作業73）
static func _range_of(k: String, strong: Array, weak: Array, cap: float, monster: bool, loose := false, jit := {}) -> Array:
	var j: Array = jit.get(k, [0.0, 0.0])
	if k in strong:
		return [STRENGTH_MIN + float(j[0]), _cap_of(k, cap, monster, true) - float(j[1])]
	if k in weak:
		return [WEAKNESS_MIN, STRENGTH_MIN - 1.0 if loose else WEAKNESS_MAX - float(j[1])]
	if loose:
		return [WEAKNESS_MIN, _cap_of(k, cap, monster, false)]
	return [WEAKNESS_MAX + 1.0 + float(j[0]), STRENGTH_MIN - 1.0 - float(j[1])]


## 完成型：どの能力も中央の近く（短所なし）。伸びしろは小さめ（早熟。ピークは入団時 + COMPLETE_GROWTH）
static func _shape_complete(p: Dictionary, t: Dictionary, target: float, cap: float, rng: RandomNumberGenerator) -> void:
	var keys: Array
	var r: Dictionary
	if bool(p["is_pitcher"]):
		r = p["pitching"]["ratings"]
		keys = ["k9", "bb9", "hr9"]
		var vals := {}
		var mean := 0.0
		for k: String in keys:
			vals[k] = target + rng.randf_range(-COMPLETE_SPREAD, COMPLETE_SPREAD)
			mean += float(vals[k]) / 3.0
		for k: String in keys:
			FictionalDraft._set_rating(r, k, clampf(float(vals[k]) + target - mean, 50.0, cap))
		FictionalDraft._set_rating(r, "stamina", clampf(maxf(FictionalDraft._rv(r, "stamina", 60.0), 66.0), 50.0, cap))
		FictionalDraft._set_rating(r, "overall", target)
		p["pitching"]["role"] = "先発"
		keys.append("stamina")
	else:
		r = p["batting"]["ratings"]
		var goal := FictionalDraft.BAT_MID + (target - FictionalDraft.PITCH_MID) / FictionalDraft.BAT_TO_PITCH
		keys = BAT_KEYS.duplicate()
		var vals := {}
		for k: String in keys:
			vals[k] = goal + rng.randf_range(-COMPLETE_SPREAD, COMPLETE_SPREAD)
		var base := goal - _bat_score(vals) + 0.0
		for k: String in keys:
			FictionalDraft._set_rating(r, k, clampf(float(vals[k]) + base, 50.0, cap))
		_settle_batter(r, goal, [], [], cap, false, false, {}, rng)
	# 伸びしろは小さめ
	var g: Dictionary = p.get("growth", {})
	var peak: Dictionary = g.get("peak", {})
	for k: String in keys:
		if peak.has(k):
			peak[k] = minf(float(peak[k]), FictionalDraft._rv(r, k, 50.0) + rng.randf_range(COMPLETE_GROWTH[0], COMPLETE_GROWTH[1]))
	if not g.is_empty():
		g["type"] = "早熟"
		g["peak_age"] = maxi(int(FictionalDraft.GROWTH_TYPES["早熟"]), int(p.get("amateur", {}).get("entry_age", 22)) + 1)


## 同じ選手の中で同じ数字が並ばないようにする（作業73。候補を作り終えたあと）。ランク（長所・短所の区別・一芸 S）と
## 総合は変えない。上限（RATING_CAP・走力は SPEED_CAP）を超えない。先発・救援の境目と物語の条件（元投手の肩・元野手の制球）も守る
static func untie(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var parts: Array = []
	var tw: Variant = p.get("two_way")
	var bats := not bool(p.get("is_pitcher", false)) or (tw is Dictionary and bool(tw.get("active", false)))
	if bats and p.get("batting") is Dictionary and p["batting"].get("ratings") is Dictionary:
		parts.append([p["batting"]["ratings"], BAT_KEYS])
	if bool(p.get("is_pitcher", false)) and p.get("pitching") is Dictionary and p["pitching"].get("ratings") is Dictionary:
		parts.append([p["pitching"]["ratings"], PIT_KEYS])
	var story := str(p.get("amateur", {}).get("story_key", ""))
	for part: Array in parts:
		var r: Dictionary = part[0]
		var keys: Array = (part[1] as Array).filter(func(k: String) -> bool: return r.get(k) is Dictionary)
		for _round in UNTIE_ROUNDS:
			var count := {}
			for k: String in keys:
				var v := int(r[k]["value"])
				count[v] = int(count.get(v, 0)) + 1
			var tied: Array = keys.filter(func(k: String) -> bool: return int(count[int(r[k]["value"])]) >= 2)
			if tied.is_empty():
				break
			_shuffle(tied, rng)
			var moved := false
			for k: String in tied:
				if _nudge(r, k, keys, story, rng):
					moved = true
					break
			if not moved:
				break


## k を ±UNTIE_STEP ずらす（相手がいれば相手を逆向きに同じだけ）。ずらした先がほかの能力と並ばないときだけ。動かせたら true
static func _nudge(r: Dictionary, k: String, keys: Array, story: String, rng: RandomNumberGenerator) -> bool:
	var v := int(r[k]["value"])
	var steps: Array = []
	for s in range(int(UNTIE_STEP[0]), int(UNTIE_STEP[1]) + 1):
		steps.append(s)
		steps.append(-s)
	_shuffle(steps, rng)
	var partners: Array = (UNTIE_PARTNERS.get(k, []) as Array).filter(func(x: String) -> bool: return x in keys)
	_shuffle(partners, rng)
	for s: int in steps:
		var nv := v + s
		if not _untie_ok(k, v, nv, story) or _clashes(r, keys, nv, [k]):
			continue
		if partners.is_empty():
			FictionalDraft._set_rating(r, k, nv)
			return true
		for q: String in partners:
			var qv := int(r[q]["value"])
			var nq := qv - s
			if nq == nv or not _untie_ok(q, qv, nq, story) or _clashes(r, keys, nq, [k, q]):
				continue
			FictionalDraft._set_rating(r, k, nv)
			FictionalDraft._set_rating(r, q, nq)
			return true
	return false


static func _clashes(r: Dictionary, keys: Array, v: int, skip: Array) -> bool:
	for x: String in keys:
		if not x in skip and int(r[x]["value"]) == v:
			return true
	return false


## ずらしてよいか：A 以上でない・ランクが同じ・上限を超えない・下限（短所の下限）を下回らない・先発と救援の境目をまたがない・物語の条件
static func _untie_ok(k: String, v: int, nv: int, story: String) -> bool:
	# A 以上（怪物の武器・一芸 S・俊足）は動かさない
	if v >= UNTIE_KEEP or FictionalTalent._ability_rank(nv) != FictionalTalent._ability_rank(v):
		return false
	var cap := FictionalDraft.SPEED_CAP if k == "speed" else FictionalDraft.RATING_CAP
	if nv > maxf(v, cap) or nv < minf(v, WEAKNESS_MIN):
		return false
	if k == "stamina" and (nv >= Growth.STARTER_STAMINA) != (v >= Growth.STARTER_STAMINA):
		return false
	if story == "convert_bat" and k == "arm" and nv < 74:
		return false
	if story == "convert_pit" and k == "bb9" and nv > 48:
		return false
	return true


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## 一芸だけ S：確率でその年に1人（まれに2人）。長所の能力1つだけを S にし、総合はほかの能力で戻す。付けた人数
static func assign_one_skill(cls: Array, theme: String, rng: RandomNumberGenerator) -> int:
	var rate := float(ONE_SKILL_THEME.get(theme, ONE_SKILL_RATE))
	if rng.randf() >= rate:
		return 0
	var want := 2 if rng.randf() < ONE_SKILL_SECOND else 1
	var pool: Array = cls.filter(func(p: Dictionary) -> bool:
		var am: Dictionary = p["amateur"]
		return (not bool(p.get("is_monster", false)) and not bool(am.get("as_ikusei", false))
			and str(am.get("grade", "")) in ["A", "B", "C"] and not is_complete(str(am.get("type_key", "")))
			and not (str(am.get("category", "")) == "高校" and str(am.get("grade", "")) == "A")
			and not p.has("reincarnation") and not bool(p.get("two_way", {}).get("active", false))))
	var n := 0
	while n < want and not pool.is_empty():
		var p: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(p)
		var t: Dictionary = TYPES.get(str(p["amateur"].get("type_key", "")), {})
		var key := ""
		var ss: Array = t.get("s", [])
		if not ss.is_empty():
			key = str(ss[0])
			for k: String in ss.slice(0, 2):
				if k in ONE_SKILL_FAVORED and rng.randf() < 0.7:
					key = k
		if bool(t.get("wild", false)) and not bool(p["is_pitcher"]):
			key = str(p["amateur"].get("wild_key", key))
		if key.is_empty():
			continue
		_one_skill(p, key, rng)
		n += 1
	return n


static func _one_skill(p: Dictionary, key: String, rng: RandomNumberGenerator) -> void:
	var am: Dictionary = p["amateur"]
	am["one_skill"] = key
	if key == "velocity":
		p["pitching"]["velocity"]["kmh"] = rng.randi_range(ONE_SKILL_KMH[0], ONE_SKILL_KMH[1])
	elif bool(p["is_pitcher"]):
		var pr: Dictionary = p["pitching"]["ratings"]
		var before := FictionalDraft._rv(pr, key, 50.0)
		var v := rng.randf_range(ONE_SKILL_VALUE[0], ONE_SKILL_VALUE[1])
		FictionalDraft._set_rating(pr, key, v)
		# 奪三振・制球・被本塁打の平均は総合のまま（ほかの2つで戻す）
		if key in ["k9", "bb9", "hr9"]:
			var others: Array = ["k9", "bb9", "hr9"].filter(func(k: String) -> bool: return k != key)
			for k: String in others:
				FictionalDraft._set_rating(pr, k, maxf(WEAKNESS_MIN, FictionalDraft._rv(pr, k, 50.0) - (v - before) / 2.0))
	else:
		var br: Dictionary = p["batting"]["ratings"]
		var goal := 0.0
		var cur := {}
		for k: String in BAT_WEIGHT:
			cur[k] = FictionalDraft._rv(br, k, 50.0)
		goal = _bat_score(cur)
		FictionalDraft._set_rating(br, key, rng.randf_range(ONE_SKILL_VALUE[0], ONE_SKILL_VALUE[1]))
		# 総合はほかの能力で戻す（S にした能力は動かさない）
		var weak: Array = []
		var strong: Array = [key]
		for k: String in BAT_WEIGHT:
			if FictionalDraft._rv(br, k, 50.0) < 50.0:
				weak.append(k)
			elif FictionalDraft._rv(br, k, 50.0) >= 70.0 and k != key:
				strong.append(k)
		_settle_one(br, goal, key, weak, strong)
	var word := str(KEY_WORD.get(key, key))
	am["intro"] = str(am.get("intro", "")) + "。%sは世代随一" % word


## 一芸を S にしたあと、S の能力は動かさずに総合を戻す（長所は B 以上、短所は E 以下、ほかは C〜D の範囲で）
static func _settle_one(br: Dictionary, goal: float, key: String, weak: Array, strong: Array) -> void:
	for _round in 8:
		var cur := {}
		for k: String in BAT_WEIGHT:
			cur[k] = FictionalDraft._rv(br, k, 50.0)
		var diff := goal - _bat_score(cur)
		if absf(diff) < SETTLE_TOL:
			return
		var movable: Array = []
		var wsum := 0.0
		for k: String in BAT_WEIGHT:
			if k == key:
				continue
			var lo := WEAKNESS_MIN if k in weak else (STRENGTH_MIN if k in strong else WEAKNESS_MAX + 1.0)
			if (diff < 0.0 and float(cur[k]) > lo) or diff > 0.0:
				movable.append(k)
				wsum += float(BAT_WEIGHT[k])
		if movable.is_empty():
			return
		for k: String in movable:
			var lo := WEAKNESS_MIN if k in weak else (STRENGTH_MIN if k in strong else WEAKNESS_MAX + 1.0)
			FictionalDraft._set_rating(br, k, maxf(lo, float(cur[k]) + diff / wsum))


static func _bat_score(v: Dictionary) -> float:
	var s := 0.0
	for k: String in BAT_WEIGHT:
		s += float(BAT_WEIGHT[k]) * float(v[k])
	return s - 1.3  # 守備の −13 × 0.1


## 武器（パワー・走力・肩）のうち長所にあるもの（無ければいちばん高いもの）を weapon まで上げる
static func _weapon_up(val: Dictionary, keys: Array, weapon: float, strong: Array) -> String:
	var wk := ""
	for k: String in keys:
		if k in strong and (wk.is_empty() or float(val[k]) > float(val[wk])):
			wk = k
	if wk.is_empty():
		for k: String in keys:
			if wk.is_empty() or float(val[k]) > float(val[wk]):
				wk = k
		strong.append(wk)
	val[wk] = maxf(float(val[wk]), weapon)
	return wk


## 物語を付ける（本指名の候補から数人。物語に合わせて能力を少し動かす）。付けた人数
static func assign_stories(cls: Array, rng: RandomNumberGenerator) -> int:
	var want := rng.randi_range(STORY_COUNT[0], STORY_COUNT[1])
	var pool: Array = []
	for p: Dictionary in cls:
		var am: Dictionary = p.get("amateur", {})
		if not bool(am.get("as_ikusei", false)) and not p.has("reincarnation") and not bool(am.get("gem", false)) \
				and str(am.get("story", "")).is_empty():
			pool.append(p)
	var n := 0
	# 甲子園で投げ合った2人（高校生の投手2人）
	var hs_p: Array = pool.filter(func(p: Dictionary) -> bool: return p["is_pitcher"] and p["category"] == "高校")
	if hs_p.size() >= 2 and rng.randf() < 0.5:
		var a: Dictionary = hs_p[rng.randi_range(0, hs_p.size() - 1)]
		var b: Dictionary = a
		while b == a:
			b = hs_p[rng.randi_range(0, hs_p.size() - 1)]
		if a["amateur"]["school"] != b["amateur"]["school"]:
			_set_story(a, "rival", {"other": b["name"], "other_school": b["amateur"]["school"]})
			_set_story(b, "rival", {"other": a["name"], "other_school": a["amateur"]["school"]})
			pool.erase(a)
			pool.erase(b)
			n += 2
	var total := 0.0
	for k: String in STORY_WEIGHT:
		total += float(STORY_WEIGHT[k])
	var tries := 0
	while n < want and not pool.is_empty() and tries < 60:
		tries += 1
		var x := rng.randf() * total
		var key := ""
		for k: String in STORY_WEIGHT:
			x -= float(STORY_WEIGHT[k])
			if x <= 0.0:
				key = k
				break
		var fits: Array = pool.filter(func(q: Dictionary) -> bool: return _story_fits(q, key))
		if fits.is_empty():
			continue
		var p: Dictionary = fits[rng.randi_range(0, fits.size() - 1)]
		_set_story(p, key, {"injury": INJURIES[rng.randi_range(0, INJURIES.size() - 1)]})
		_story_effect(p, key)
		pool.erase(p)
		n += 1
	return n


static func _story_fits(p: Dictionary, key: String) -> bool:
	var am: Dictionary = p["amateur"]
	var cat := str(am.get("category", ""))
	var pitcher := bool(p["is_pitcher"])
	match key:
		"hidden":
			return cat == "高校" and not bool(am.get("strong_school", false))
		"comeback":
			return cat == "大学"
		"convert_bat":
			return not pitcher and cat in ["高校", "大学"]
		"convert_pit":
			return pitcher and cat in ["大学", "社会人", "独立"]
		"indie":
			return cat == "独立" and int(am.get("entry_age", 0)) >= 22
		"late":
			return cat == "社会人" and int(am.get("entry_age", 0)) >= 24
		"captain":
			return not pitcher and bool(am.get("strong_school", false))
		"family":
			return true
	return false


static func _set_story(p: Dictionary, key: String, extra: Dictionary) -> void:
	var am: Dictionary = p["amateur"]
	var age := int(am.get("entry_age", 22))
	var words := {"school": str(am.get("school", "")), "age": age, "years": maxi(1, age - 18)}
	words.merge(extra, true)
	am["story_key"] = key
	am["story"] = str(STORIES[key]["text"]).format(words)


## 物語に合わせた能力（元投手の野手は肩が強い、野手から転向した投手は球が荒い など）
static func _story_effect(p: Dictionary, key: String) -> void:
	match key:
		"convert_bat":
			var br: Dictionary = p["batting"]["ratings"]
			FictionalDraft._set_rating(br, "arm", clampf(maxf(FictionalDraft._rv(br, "arm", 50.0), 74.0), 30.0, FictionalDraft.RATING_CAP))
		"convert_pit":
			var pr: Dictionary = p["pitching"]["ratings"]
			FictionalDraft._set_rating(pr, "bb9", minf(FictionalDraft._rv(pr, "bb9", 50.0), 48.0))
			var velo: Variant = p["pitching"].get("velocity")
			if velo is Dictionary:
				velo["kmh"] = mini(VELO_MAX, int(velo.get("kmh", 145)) + 3)
