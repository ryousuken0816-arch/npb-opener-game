class_name Salary
extends RefCounted
## 年俸の計算（単位：万円）。docs/SPEC.md「決定事項：FA・ポスティング」。
##
## 史実の年俸データは使わず、能力値と成績から計算する。
## - 開幕時点（ゲーム開始年・途中加入）：過去数年の成績（能力値の Marcel 加重＝直近3年）・在籍年数・年齢から
##   「市場価値」＝ BASE × exp(K × 実力) × 出場量^EXP を出し、在籍年数の係数を掛ける
## - 新人：ドラフト順位と出身区分（高校／大学・社会人）の表
## - 外国人：市場価値に上乗せ（最低額あり）。外国人市場の提示額にも使う
## - 契約更改（オフ）：今季のゲーム内成績と能力値から目標額を出し、史実の減額制限（1億円超40%・以下25%）と
##   上げ幅の上限の範囲で近づける
## 係数は 2008年開幕時点で相場（スター3〜5億、レギュラー5千万〜1億、若手1千万前後、平均3千万前後）に
## 合うよう調整した（godot/tests/roster_year_check.gd で分布を表示）。

## 高額になりすぎないように：SOFT_CAP を超えた分は SOFT_CAP_RATE の割合だけ伸び、MAX で頭打ち
const SOFT_CAP := 30000.0
const SOFT_CAP_RATE := 0.35
const MAX := 65000.0
## 平均的なレギュラー（実力 z=0・フル出場）の市場価値
const BASE := 8500.0
## 実力 z が1上がると市場価値が何倍になるか（exp(K)）
const K := 1.45
## 出場量（0〜1）の効き方
const PLAYING_EXP := 1.4
## 実力 z の上限（能力値100の選手が青天井にならないように）
const Z_MAX := 2.0
## 投手の実力は先発・救援別の母集団で正規化されているので控えめに
const PITCHER_Z_SCALE := 0.85
## 救援投手：実力の効きと市場価値の割合（先発より安い）
const RELIEVER_Z_SCALE := 0.65
const RELIEVER_VALUE := 0.6
## 1年のフル出場の目安（能力値の sample は直近3年を 1.0/0.8/0.6 で加重した合計なので SAMPLE_YEARS で割る）
const FULL_PA := 480.0
const FULL_OUTS_STARTER := 450.0
const FULL_OUTS_RELIEVER := 170.0
const SAMPLE_YEARS := 2.4
## 在籍年数の係数：1年目 SENIORITY_MIN → SENIORITY_FULL_YEARS 年目で 1.0、以降は1年ごとに +SENIORITY_VETERAN（上限あり）
const SENIORITY_MIN := 0.3
const SENIORITY_FULL_YEARS := 7
const SENIORITY_VETERAN := 0.04
const SENIORITY_MAX := 1.4
## 実績の少ない選手の下限：最低年俸＋在籍1年ごとに FLOOR_PER_YEAR（上限 FLOOR_MAX）
const FLOOR_PER_YEAR := 180
const FLOOR_MAX := 2200
## 外国人：市場価値の倍率と最低額
const FOREIGN_PREMIUM := 1.3
const FOREIGN_MIN := 3000
## 外国人市場の提示額に評価の誤差をどれだけ効かせるか（exp(この値 × 誤差z) 倍）
const ASKING_NOISE_SCALE := 0.5
## 新人の年俸 [社会人・大学, 高校]（キーはドラフト順位。自由枠・希望枠は1位扱い、7位以下は最後の値）
const ROOKIE := {
	1: [1500, 1200], 2: [1200, 900], 3: [1000, 800], 4: [900, 700], 5: [800, 600], 6: [700, 550],
}
const ROOKIE_IKUSEI := [400, 300]
## 契約更改
const CUT_LIMIT_HIGH := 0.40  ## 1億円を超える選手の減額制限
const CUT_LIMIT_LOW := 0.25
const CUT_LIMIT_BORDER := 10000
const RAISE_MAX := 3.0  ## 1回の更改で上がる上限（倍）
const RAISE_MAX_AMOUNT := 15000  ## 1回の更改で上がる上限（額）
## 目標額：今季のゲーム内成績と能力値の配分、出場量の配分
const SEASON_WEIGHT := 0.5
const SEASON_PLAYING_WEIGHT := 0.6
## 今季成績の実力 z：OPS・防御率の平均的なレギュラーとの差をこの幅で割る（打席・投球回が少ないほど0へ縮める）
const SEASON_OPS_MEAN := 0.760
const SEASON_OPS_SD := 0.110
const SEASON_ERA_MEAN := 3.60
const SEASON_ERA_SD := 1.00


## 最低年俸（支配下）。2025年から600万円
static func minimum(year: int) -> int:
	return 600 if year >= 2025 else 440


## 能力値の平均からの差（z）。63＋17z のスケールを戻す
static func _z(rating: Variant, fallback: float = 45.0) -> float:
	return SimPlayer.z_of(rating, fallback)


## 能力値から実力 z と出場量（0〜1）[z, playing, is_reliever]
static func ability(p: Dictionary) -> Array:
	var pitching: Variant = p.get("pitching")
	if p.get("is_pitcher", false) and pitching is Dictionary:
		var r: Dictionary = pitching["ratings"] if pitching.get("ratings") is Dictionary else {}
		var z := PITCHER_Z_SCALE * (0.75 * _z(r.get("overall")) + 0.25 * _z(r.get("k9")))
		var outs := float(pitching.get("sample", {}).get("outs_1", 0.0)) / SAMPLE_YEARS
		if pitching.get("role") == "先発":
			return [z, minf(1.0, outs / FULL_OUTS_STARTER), false]
		return [z * RELIEVER_Z_SCALE, minf(1.0, outs / FULL_OUTS_RELIEVER), true]
	var batting: Variant = p.get("batting")
	var br: Dictionary = {}
	var pa := 0.0
	if batting is Dictionary:
		br = batting.get("ratings", {})
		pa = float(batting.get("sample", {}).get("pa_1", 0.0)) / SAMPLE_YEARS
	var z := 0.35 * _z(br.get("meet")) + 0.35 * _z(br.get("power")) + 0.1 * _z(br.get("eye")) \
		+ 0.1 * _z(br.get("speed")) + 0.1 * _z(br.get("defense"), 63.0)
	return [z, minf(1.0, pa / FULL_PA), false]


## 市場価値（在籍年数・最低額を考える前の額）
static func market_value(z: float, playing: float, reliever: bool) -> float:
	var value := BASE * exp(K * minf(z, Z_MAX)) * pow(maxf(playing, 0.0), PLAYING_EXP)
	return value * (RELIEVER_VALUE if reliever else 1.0)


## 高額の伸びを抑える（SOFT_CAP 超は緩やかに、MAX で頭打ち）
static func cap(value: float) -> float:
	if value > SOFT_CAP:
		value = SOFT_CAP + (value - SOFT_CAP) * SOFT_CAP_RATE
	return minf(value, MAX)


static func seniority(years: int) -> float:
	var ramp := minf(1.0, (years - 1) / float(SENIORITY_FULL_YEARS - 1))
	var s := SENIORITY_MIN + (1.0 - SENIORITY_MIN) * ramp
	s += SENIORITY_VETERAN * maxi(0, years - SENIORITY_FULL_YEARS - 1)
	return minf(s, SENIORITY_MAX)


static func floor_for(years: int, year: int) -> int:
	return mini(minimum(year) + FLOOR_PER_YEAR * maxi(0, years - 1), maxi(FLOOR_MAX, minimum(year)))


## 開幕時点・途中加入の年俸。years は在籍年数（1年目=1）
static func initial(p: Dictionary, years: int, foreign: bool, year: int) -> int:
	var a := ability(p)
	var value := market_value(a[0], a[1], a[2])
	if foreign:
		return round_amount(maxf(FOREIGN_MIN, cap(value * FOREIGN_PREMIUM)))
	return round_amount(maxf(floor_for(years, year), cap(value * seniority(years))))


## 外国人市場の提示額：来季の見立て（p）での外国人の年俸に、評価の誤差（noise、z）を反映する
static func foreign_asking(p: Dictionary, noise: float, year: int) -> int:
	return round_amount(maxf(FOREIGN_MIN, initial(p, 1, true, year) * exp(ASKING_NOISE_SCALE * noise)))


## 新人の年俸。draft: {round: int（自由枠などは1）, high_school: bool, ikusei: bool}
static func rookie(draft: Dictionary, year: int) -> int:
	var col := 1 if draft.get("high_school", false) else 0
	if draft.get("ikusei", false):
		return ROOKIE_IKUSEI[col]
	var r := clampi(int(draft.get("round", 6)), 1, 6)
	return maxi(minimum(year), ROOKIE[r][col])


## 契約更改。current：今の年俸、p：能力値（シーズン後）、season_stats：今季のゲーム内成績
## （打者は Season.batting、投手は Season.pitching の1人分。無ければ空）、years：来季の在籍年数
static func renew(current: int, p: Dictionary, season_stats: Dictionary, years: int, foreign: bool,
		year: int) -> int:
	var a := ability(p)
	var season := season_ability(p, season_stats)
	var z: float = lerpf(a[0], season[0], SEASON_WEIGHT)
	var playing: float = lerpf(a[1], season[1], SEASON_PLAYING_WEIGHT)
	var value := market_value(z, playing, a[2])
	var target := cap(value * (FOREIGN_PREMIUM if foreign else seniority(years)))
	target = maxf(target, FOREIGN_MIN if foreign else floor_for(years, year))
	var cut := CUT_LIMIT_HIGH if current > CUT_LIMIT_BORDER else CUT_LIMIT_LOW
	var upper := minf(current * RAISE_MAX, current + RAISE_MAX_AMOUNT)
	return round_amount(clampf(target, current * (1.0 - cut), maxf(upper, current)))


## 今季のゲーム内成績から [実力 z, 出場量]（打者は OPS、投手は防御率。少ないほど z を0へ縮める）
static func season_ability(p: Dictionary, s: Dictionary) -> Array:
	var pitching: Variant = p.get("pitching")
	if p.get("is_pitcher", false) and pitching is Dictionary:
		var outs := float(s.get("outs", 0))
		var full := FULL_OUTS_STARTER if pitching.get("role") == "先発" else FULL_OUTS_RELIEVER
		var playing := minf(1.0, outs / full)
		if outs <= 0.0:
			return [0.0, 0.0]
		var era := float(s.get("er", 0)) * 27.0 / outs
		var z := (SEASON_ERA_MEAN - era) / SEASON_ERA_SD * PITCHER_Z_SCALE
		if pitching.get("role") != "先発":
			z *= RELIEVER_Z_SCALE
		return [z * playing, playing]
	var pa := float(s.get("pa", 0))
	if pa <= 0.0:
		return [0.0, 0.0]
	var playing := minf(1.0, pa / FULL_PA)
	var ab := float(s.get("ab", 0))
	var on_base_den: float = ab + s.get("bb", 0) + s.get("hbp", 0) + s.get("sf", 0)
	var on_base: float = s.get("h", 0) + s.get("bb", 0) + s.get("hbp", 0)
	var obp := on_base / on_base_den if on_base_den > 0 else 0.0
	var tb := float(s.get("h", 0) + s.get("d", 0) + 2 * s.get("t", 0) + 3 * s.get("hr", 0))
	var slg := tb / ab if ab > 0 else 0.0
	return [(obp + slg - SEASON_OPS_MEAN) / SEASON_OPS_SD * playing, playing]


## 10万円単位に丸める
static func round_amount(value: float) -> int:
	return int(round(value / 10.0)) * 10


## 表示用（例: "1億2000万円" "850万円"）
static func text(amount: int) -> String:
	if amount >= 10000:
		var oku := amount / 10000
		var man := amount % 10000
		return "%d億円" % oku if man == 0 else "%d億%d万円" % [oku, man]
	return "%d万円" % amount
