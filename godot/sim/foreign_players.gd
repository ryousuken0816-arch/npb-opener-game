class_name ForeignPlayers
extends RefCounted
## 架空の外国人選手（史実の無い年の外国人市場の候補。docs/AUTORUN.md 作業31）。
##
## ひな形は generated/foreign.json（tools/foreign_players.py が 2009〜2025年の新外国人から作る）：
## 1人ずつの「出身・前の所属・年齢・1年目の能力（その年のシーズン後の能力値）」。作るときはひな形を1人選び、
## 能力に小さなゆらぎ（`NOISE`）を足し、名前・誕生日・経歴を出身に合わせて作る。人数は直近10年のどれかの年の人数。
## 能力の当たり外れ（大当たりも1年で帰る選手も）はひな形の分布そのまま。来日してからは作業27の `Growth` で育ち・衰え、
## 引退（退団）も `Growth.retire_probability`（外国人）に従う。
##
## 作った選手は能力値ファイルの選手と同じ形で、`import`（{country, prev, mlb_org, template_year}）が付く。
## `draft` は空・`career` は前の所属なので `RosterRules.is_foreign` は外国人と判定する。

const DATA_FILE := "foreign.json"
## 能力に足すゆらぎ（能力値。球速は km/h）
const NOISE := 3.0
const VELOCITY_NOISE := 1.0

## 名前（カタカナの姓は「名の頭文字.姓」、漢字は「姓 名」）
const INITIALS := ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "O", "P", "R", "S", "T", "V", "W", "Y"]
const LATIN_INITIALS := ["A", "C", "D", "E", "F", "G", "H", "J", "L", "M", "N", "O", "P", "R", "S", "V", "W", "Y"]
const US_SURNAMES := [
	"スミス", "ジョンソン", "ウィリアムズ", "ブラウン", "ミラー", "デービス", "ウィルソン", "アンダーソン", "テイラー", "トーマス",
	"ムーア", "ジャクソン", "マーティン", "トンプソン", "ホワイト", "ハリス", "クラーク", "ロビンソン", "ウォーカー", "ヤング",
	"アレン", "キング", "ライト", "スコット", "ヒル", "グリーン", "アダムス", "ベイカー", "ネルソン", "カーター", "ミッチェル",
	"ロバーツ", "ターナー", "フィリップス", "キャンベル", "パーカー", "エバンス", "エドワーズ", "コリンズ", "スチュワート",
	"モリス", "マーフィー", "クック", "ロジャース", "モーガン", "クーパー", "ピーターソン", "リード", "ベイリー", "ベル",
	"ケリー", "ハワード", "ワード", "コックス", "リチャードソン", "ウッド", "ワトソン", "ブルックス", "ベネット", "グレイ",
	"ヒューズ", "プライス", "サンダース", "ロング", "フォスター", "パウエル", "ジェンキンス", "ペリー", "ラッセル", "サリバン",
	"フィッシャー", "ヘイズ", "マイヤーズ", "フォード", "ハミルトン", "グラハム", "ウォレス", "ウェスト", "コール", "ショー",
	"ハント", "ブラック", "パーマー", "ウェルズ", "ハーパー", "ノリス", "ランドール", "ボイド", "ホルト", "ギブソン", "バーンズ",
	"ハドソン", "フレミング", "ウェバー", "リンド", "ケラー", "オコナー", "マクドナルド", "ホプキンス", "ローレンス", "ダンカン",
]
const LATIN_SURNAMES := [
	"ロドリゲス", "ヘルナンデス", "マルティネス", "ゴンザレス", "ペレス", "ロペス", "ガルシア", "サンチェス", "ラミレス",
	"トーレス", "フローレス", "リベラ", "ゴメス", "ディアス", "レイエス", "モラレス", "クルーズ", "オルティス", "グティエレス",
	"チャベス", "ラモス", "ゲレーロ", "メンドーサ", "アルバレス", "カスティーヨ", "ヒメネス", "モレノ", "ロメロ", "エレーラ",
	"メディナ", "バルガス", "カストロ", "フェルナンデス", "ソーサ", "バルデス", "ペーニャ", "サンタナ", "メヒア", "ベラスケス",
	"グスマン", "ヌニェス", "カブレラ", "ロサリオ", "ピネダ", "ソト", "メルセデス", "モンテロ", "アルモンテ", "ブランコ",
	"ブリトー", "ミランダ", "マルテ", "ロハス", "ペゲーロ", "ポランコ", "ベタンセス", "セペダ", "ピメンテル", "バティスタ",
	"ペラルタ", "アコスタ", "ドミンゲス", "サントス", "マチャド", "パディーヤ", "エスコバー", "オリベラ", "アキーノ", "ルナ",
]
const CUBA_SURNAMES := [
	"デスパイネ", "グラシアル", "モイネロ", "マルティネス", "ペレス", "アルフォンソ", "セペダ", "ボロト", "ガルシア", "サルディ",
	"ラソ", "マルモル", "ゴンサレス", "ベルナル", "トレス", "カスティーヨ", "モレホン", "アブレウ", "ピエドラ", "ベタンクール",
]
const KOREA_FAMILY := ["金", "李", "朴", "崔", "鄭", "姜", "趙", "尹", "張", "林", "韓", "呉", "申", "徐", "権", "黄", "安", "宋", "柳", "洪"]
const KOREA_GIVEN := ["民", "俊", "賢", "浩", "哲", "永", "成", "載", "鎮", "宇", "泰", "炫", "承", "東", "允", "赫", "錫", "煥",
	"秀", "在", "根", "勲", "圭", "範", "彬", "昊", "炳", "相", "基", "珉"]
const TAIWAN_FAMILY := ["陳", "林", "黄", "張", "李", "王", "呉", "劉", "蔡", "楊", "許", "鄭", "謝", "郭", "洪", "曽", "邱", "廖", "頼", "徐"]
const TAIWAN_GIVEN := ["冠", "宇", "柏", "融", "志", "豪", "偉", "傑", "建", "明", "俊", "宏", "翔", "博", "耀", "庭", "睿", "品",
	"家", "承", "祐", "廷", "哲", "安", "易", "磊", "錦", "峻", "銘", "鴻"]

## 前の所属 → 経歴に書く球団・リーグ（メジャー球団はひな形どおり1〜3球団）
const MLB_TEAMS := ["ヤンキース", "レッドソックス", "オリオールズ", "ブルージェイズ", "レイズ", "ホワイトソックス", "ガーディアンズ",
	"タイガース", "ロイヤルズ", "ツインズ", "アストロズ", "エンゼルス", "アスレチックス", "マリナーズ", "レンジャーズ", "ブレーブス",
	"マーリンズ", "メッツ", "フィリーズ", "ナショナルズ", "カブス", "レッズ", "ブルワーズ", "パイレーツ", "カージナルス",
	"ダイヤモンドバックス", "ロッキーズ", "ドジャース", "パドレス", "ジャイアンツ"]
const PREV_TEAMS := {
	"韓国": ["韓国・斗山", "韓国・LG", "韓国・SSG", "韓国・キウム", "韓国・KT", "韓国・NC", "韓国・起亜", "韓国・ロッテ", "韓国・三星", "韓国・ハンファ"],
	"台湾": ["台湾・統一", "台湾・楽天", "台湾・中信", "台湾・富邦", "台湾・味全", "台湾・台鋼"],
	"キューバ": ["キューバ・ハバナ", "キューバ・グランマ", "キューバ・ビジャクララ", "キューバ・サンティアゴ", "キューバ・シエゴデアビラ"],
	"メキシコ": ["メキシカンリーグ"],
	"ドミニカ": ["ドミニカ・ウインターリーグ"],
	"日本の独立リーグ": ["四国・徳島", "四国・香川", "BC・群馬", "BC・茨城", "BC・石川", "九州・火の国"],
	"米独立リーグ": ["米独立リーグ"],
	"米マイナー": ["米マイナー"],
	"その他": ["米マイナー"],
}
const AMATEUR := {"台湾": ["中国文化大", "台湾・国立体育大", "平鎮高", "穀保家商"], "韓国": ["檀国大", "慶南高"]}

var data: Dictionary
var _by_side := {"P": [], "B": []}
var _used_names := {}
var _serial := 0
var _derived: Dictionary = {}


## data: generated/foreign.json の中身（空なら読む）。growth: 投手の総合を内訳から出す式に使う（無ければ係数を読む）
func _init(foreign_data: Dictionary = {}, growth: Growth = null) -> void:
	data = foreign_data if not foreign_data.is_empty() else load_data()
	for t: Dictionary in data.get("templates", []):
		_by_side[t["side"]].append(t)
	var g := growth if growth != null else Growth.new()
	_derived = g.coeff.get("pitching", {}).get("derived", {}).get("overall", {})


static func load_data() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../generated").path_join(DATA_FILE).simplify_path()
	if not FileAccess.file_exists(path):
		push_error("外国人のひな形がありません: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func is_ready() -> bool:
	return not _by_side["P"].is_empty() and not _by_side["B"].is_empty()


static func is_fictional_foreign(p: Dictionary) -> bool:
	return p.get("import") is Dictionary


## その年の新外国人の人数 {p, b}（直近10年のどれか1年の人数）
func count_for_year(rng: RandomNumberGenerator) -> Dictionary:
	var years: Array = data.get("count_years", [])
	var c: Dictionary = data["counts"][str(int(years[rng.randi_range(0, years.size() - 1)]))]
	return {"p": int(c["p"]), "b": int(c["b"])}


## 新外国人のうち投手の割合（直近10年）
func pitcher_share() -> float:
	var p := 0
	var total := 0
	for y: Variant in data.get("count_years", []):
		var c: Dictionary = data["counts"][str(int(y))]
		p += int(c["p"])
		total += int(c["p"]) + int(c["b"])
	return float(p) / maxi(1, total)


## その年（year 年のシーズンに来る）の架空の外国人選手をまとめて作る
func generate_year(year: int, rng: RandomNumberGenerator) -> Array:
	var n := count_for_year(rng)
	var out: Array = []
	for side: String in ["P", "B"]:
		for i in int(n["p" if side == "P" else "b"]):
			out.append(make(side, year, rng))
	return out


## 1人作る（side は "P" か "B"）
func make(side: String, year: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = _by_side[side]
	var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var p: Dictionary = t["player"].duplicate(true)
	_serial += 1
	var country := _country(str(t["origin"]), rng)
	p["id"] = "fgn:%d:%d" % [year, _serial]
	p["provisional_id"] = false
	p["name"] = _unique_name(country, year, rng)
	p["birth"] = _birth(year, int(t["age"]), rng)
	p["draft"] = ""
	p["career"] = _career(country, str(t["prev"]), bool(t["mlb_org"]), rng)
	p["team"] = ""
	p["hist_team"] = ""
	p["league"] = null
	p["import"] = {"country": country, "prev": t["prev"], "mlb_org": t["mlb_org"], "template_year": t["year"]}
	_perturb(p, side, rng)
	return p


## ひな形の能力に小さなゆらぎを足す（ランク・弾道・守備位置ごとの値は Growth の書き込みで揃う）
func _perturb(p: Dictionary, side: String, rng: RandomNumberGenerator) -> void:
	if side == "B":
		for key: String in Growth.BATTING_KEYS:
			var v: Variant = Growth._value(p, "B", key)
			if v != null:
				Growth._set_value(p, "B", key, float(v) + rng.randfn(0.0, NOISE))
		return
	var before := {}
	for key: String in ["k9", "bb9", "hr9"]:
		var v: Variant = Growth._value(p, "P", key)
		if v != null:
			before[key] = float(v)
			Growth._set_value(p, "P", key, float(v) + rng.randfn(0.0, NOISE))
	var vel: Variant = Growth._value(p, "P", "velocity")
	if vel != null:
		Growth._set_value(p, "P", "velocity", float(vel) + rng.randfn(0.0, VELOCITY_NOISE))
	var st: Variant = Growth._value(p, "P", "stamina")
	var role := "先発" if p["pitching"].get("role") == "先発" else "救援"
	if st != null:
		var s := float(st) + rng.randfn(0.0, NOISE)
		s = maxf(s, Growth.STARTER_STAMINA) if role == "先発" else minf(s, Growth.STARTER_STAMINA - 1.0)
		Growth._set_value(p, "P", "stamina", s)
	# 総合は内訳の変化に合わせて動かす（総合は FIP から出した値なので）
	var ov: Variant = Growth._value(p, "P", "overall")
	var d: Dictionary = _derived.get(role, {})
	if ov != null and not d.is_empty():
		var nxt := float(ov)
		for k: String in before:
			nxt += float(d["from"].get(k, 0.0)) * (float(Growth._value(p, "P", k)) - float(before[k]))
		Growth._set_value(p, "P", "overall", nxt)


## 出身（推定の区分）→ 国。中南米は latin_split の割合で国を割り振る
func _country(origin: String, rng: RandomNumberGenerator) -> String:
	if origin != "中南米":
		return origin
	var split: Dictionary = data.get("latin_split", {"ドミニカ": 1.0})
	var u := rng.randf()
	var acc := 0.0
	for c: String in split:
		acc += float(split[c])
		if u < acc:
			return c
	return str(split.keys()[0])


func _unique_name(country: String, year: int, rng: RandomNumberGenerator) -> String:
	var name := ""
	for i in 20:
		name = _name(country, rng)
		if not _used_names.has(name):
			break
	_used_names[name] = year
	return name


func _name(country: String, rng: RandomNumberGenerator) -> String:
	match country:
		"韓国":
			return "%s %s%s" % [_pick(KOREA_FAMILY, rng), _pick(KOREA_GIVEN, rng), _pick(KOREA_GIVEN, rng)]
		"台湾":
			return "%s %s%s" % [_pick(TAIWAN_FAMILY, rng), _pick(TAIWAN_GIVEN, rng), _pick(TAIWAN_GIVEN, rng)]
		"キューバ":
			return "%s.%s" % [_pick(LATIN_INITIALS, rng), _pick(CUBA_SURNAMES, rng)]
		"米国", "その他":
			return "%s.%s" % [_pick(INITIALS, rng), _pick(US_SURNAMES, rng)]
	return "%s.%s" % [_pick(LATIN_INITIALS, rng), _pick(LATIN_SURNAMES, rng)]


## year 年の4月1日時点で age 歳になる誕生日
static func _birth(year: int, age: int, rng: RandomNumberGenerator) -> String:
	var month := rng.randi_range(1, 12)
	var day := rng.randi_range(1, 28)
	var after_april1 := month > 4 or (month == 4 and day > 1)
	return "%04d-%02d-%02d" % [year - age - (1 if after_april1 else 0), month, day]


func _career(country: String, prev: String, mlb_org: bool, rng: RandomNumberGenerator) -> String:
	var parts: Array[String] = []
	if mlb_org or prev == "メジャー球団":
		var teams := MLB_TEAMS.duplicate()
		for i in rng.randi_range(1, 3):
			parts.append(teams.pop_at(rng.randi_range(0, teams.size() - 1)))
	if prev == "アマチュア":
		parts.append(_pick(AMATEUR.get(country, ["米マイナー"]), rng))
	elif prev != "メジャー球団":
		parts.append(_pick(PREV_TEAMS.get(prev, ["米マイナー"]), rng))
	return " - ".join(parts)


static func _pick(list: Array, rng: RandomNumberGenerator) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)]
