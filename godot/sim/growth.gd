class_name Growth
extends RefCounted
## 成長・衰え・引退（史実の能力値ファイルが無い年。docs/AUTORUN.md 作業27）。
##
## 係数は generated/growth.json（tools/growth_coefficients.py が 2008〜2025年の generated/ratings/ から作る）。
## 能力の項目ごと（野手：ミート・パワー・選球眼・走力・守備力・肩力、投手：総合・スタミナ・K/9・BB/9・HR/9・球速）に
##     来季の値 = 今の値 + a(年齢) + b(年齢) × (今の値 − 中心) + sd(年齢) × ゆらぎ
## （年齢は来季の4月1日時点の満年齢）。係数は前年までの出場が多い選手（keys）と少ない選手（keys_low：新人など）で別で、
## 入団して最初の1回は出場量に応じて混ぜ、2回目からは多い側を使う（ゲームは2軍の試合を行わず出場量が増えないため）。
## ゆらぎは史実の残差の分位点から引き、同じ選手の項目どうしは残差の相関行列（shock_cholesky）でつながる
## （総合が上がる年は K/9・HR/9 も良くなりやすい、など）。
## リーグ全体の平均・ばらつきは毎年 target（史実の開幕時点の全選手）に少し寄せる（`grow_league`）。
##
## 架空の選手（作業22）は選手データに `growth` を持ち、ピークの年齢まではピークに向かって育ち、
## そのあとは実在の選手と同じ衰え方（ピークの年齢の差だけ年齢をずらす）をする。項目は godot/README.md「成長・衰え・引退」。

const COEFF_FILE := "growth.json"
## この年の開幕から成長させる（2027年の開幕は 2027_pre.json＝2026年までの成績。2027年のシーズン後から毎オフ成長）
const FIRST_YEAR := 2028

## リーグ全体の平均・ばらつきを target に寄せる割合（1年あたり）と、1年で動かす上限
const NORMALIZE_RATE := 0.5
const NORMALIZE_MAX_SHIFT := 3.0
const NORMALIZE_SD_MIN := 0.94
const NORMALIZE_SD_MAX := 1.06
## 全員まとめては平均・ばらつきを寄せない項目（球速は実測のある1軍の投手だけの target なので全員の平均とずれる。
## スタミナは役割で2つの山に分かれるので役割ごとに寄せる：_normalize_stamina）
const NORMALIZE_SKIP := ["velocity", "stamina"]

## 架空の選手の育ち方 → ピークの年齢（`growth.peak_age` が無いときの既定）
const PEAK_AGE := {"早熟": 25, "普通": 28, "晩成": 31}
## 史実の年齢の曲線が前提にしている平均的なピークの年齢（ピークを過ぎた架空の選手は、この差だけ年齢をずらして衰える）
const TYPICAL_PEAK_AGE := 28
## 架空の選手がピークに向かって育つ間のゆらぎ（史実の sd に掛ける）
const FICTIONAL_NOISE := 0.6

## その年のゲーム内の成績の後押し（`season.bonus` の点数に掛ける割合と上限。SPEC：育成は史実成長の後押し程度）
const BONUS_WEIGHT := 1.0
const BONUS_MAX := 3.0
## 出場量（sample）の更新：来季 = 今季のゲーム内の打席・アウト数 + 今の値 × SAMPLE_DECAY
## （能力値の Marcel 加重 1.0/0.8/0.6 の近似）
const SAMPLE_DECAY := 0.7

## 先発になるスタミナ（role_of_stamina）
const STARTER_STAMINA := 62.5

const VALUE_MIN := 1
const VALUE_MAX := 100
const VELOCITY_MIN := 120
const VELOCITY_MAX := 168
const RANK_THRESHOLDS := [90, 80, 70, 60, 50, 40, 20, 0]
const RANK_LETTERS := ["S", "A", "B", "C", "D", "E", "F", "G"]
## 弾道の段（tools/compute_ratings.py の TRAJECTORY_CUTOFFS。パワーの z で近似）
const TRAJECTORY_CUTOFFS := [[1.0, 4], [0.0, 3], [-1.0, 2]]

const BATTING_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PITCHING_KEYS := ["overall", "stamina", "k9", "bb9", "hr9", "velocity"]

var coeff: Dictionary


func _init(coefficients: Dictionary = {}) -> void:
	coeff = coefficients if not coefficients.is_empty() else load_coefficients()


## generated/growth.json を読む（無ければ空）
static func load_coefficients() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../generated").path_join(COEFF_FILE).simplify_path()
	if not FileAccess.file_exists(path):
		push_error("成長の係数がありません: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func is_ready() -> bool:
	return coeff.has("batting") and coeff.has("pitching")


## アマ選手（tools/amateur_ratings.py。誕生日が無い）の入団した年の4月1日時点の年齢（区分ごとの目安）
const AMATEUR_ENTRY_AGE := {"高校": 18, "大学": 22, "社会人": 24, "独立": 23}


## その年の4月1日時点の満年齢（誕生日が無ければ、アマ選手はドラフトの年と区分からの目安、ほかは -1）
static func age_at(p: Dictionary, year: int) -> int:
	var birth: Variant = p.get("birth")
	if not (birth is String) or birth.length() < 10:
		var am: Variant = p.get("amateur")
		if am is Dictionary and am.get("draft_year") != null:
			return year - int(am["draft_year"]) - 1 + int(AMATEUR_ENTRY_AGE.get(str(am.get("category", "")), 22))
		return -1
	var parts: PackedStringArray = birth.split("-")
	if parts.size() < 3 or not parts[0].is_valid_int():
		return -1
	var age := year - int(parts[0])
	if int(parts[1]) > 4 or (int(parts[1]) == 4 and int(parts[2]) > 1):
		age -= 1
	return age


static func rank_of(value: float) -> String:
	for i in RANK_THRESHOLDS.size():
		if value >= float(RANK_THRESHOLDS[i]):
			return RANK_LETTERS[i]
	return RANK_LETTERS[-1]


static func is_fictional(p: Dictionary) -> bool:
	return p.get("growth") is Dictionary


## 架空の選手のピークの年齢
static func peak_age_of(p: Dictionary) -> int:
	var g: Dictionary = p.get("growth", {})
	if g.get("peak_age") != null:
		return int(g["peak_age"])
	return int(PEAK_AGE.get(g.get("type", "普通"), TYPICAL_PEAK_AGE))


# --- 1人の1年分 ---------------------------------------------------------------------

## p の来季（year 年）の能力値を返す（p は変えない）。
## season（任意）：今季のゲーム内の成績 {"pa_1", "pa_2", "outs_1", "outs_2"}（出場量の更新）と
## "bonus"（項目 → 点数。好成績の後押し）
func grow(p: Dictionary, year: int, rng: RandomNumberGenerator, season: Dictionary = {}) -> Dictionary:
	var q: Dictionary = p.duplicate(true)
	var side := _side(q)
	if side.is_empty() or not is_ready():
		return q
	var block: Dictionary = coeff["batting" if side == "B" else "pitching"]
	var age := age_at(q, year)
	if age < 0:
		age = TYPICAL_PEAK_AGE
	var shocks := _shocks(block, rng)
	var regular := _regular_weight(q, side, block)
	var bonus: Dictionary = season.get("bonus", {})
	var derived: Dictionary = block.get("derived", {})
	var order: Array = block["order"]
	var before := {}
	# 投手の役割：来季に先発になるかを先に決め、スタミナはその移り変わり（先発>救援 など）の回帰で動かす
	var old_role := ""
	var new_role := ""
	if side == "P":
		old_role = "先発" if q["pitching"].get("role") == "先発" else "救援"
		new_role = _next_role(q, block, old_role, age, regular, rng)
	for i in order.size():
		var key: String = order[i]
		var cur: Variant = _value(q, side, key)
		if cur == null:
			continue
		before[key] = float(cur)
		if derived.has(key) and not _toward_peak(q, key, age):
			continue
		var nxt := float(cur)
		if key == "stamina" and not _toward_peak(q, key, age):
			var fit: Dictionary = block["stamina_by_role"]["%s>%s" % [old_role, new_role]]
			nxt += _fit_delta(fit, nxt, age) + _at(fit, "sd", age) * float(shocks[i])
			# 役割とスタミナが食い違わないように（史実の能力値は役割をスタミナと同じ指標で決めている）
			nxt = maxf(nxt, STARTER_STAMINA) if new_role == "先発" else minf(nxt, STARTER_STAMINA - 1.0)
		else:
			nxt += _mean_delta(q, block, key, nxt, age, regular) + _sd(q, block, key, age, regular) * float(shocks[i])
		if bonus.has(key):
			nxt += clampf(float(bonus[key]) * BONUS_WEIGHT, -BONUS_MAX, BONUS_MAX)
		_set_value(q, side, key, nxt)
	if side == "P":
		if before.has("stamina") and _toward_peak(q, "stamina", age):
			new_role = role_of_stamina(float(_value(q, side, "stamina")))
		q["pitching"]["role"] = new_role
	# 投手の総合は役割ごとに K/9・BB/9・HR/9 の値から出す（総合は FIP から出した値なので、内訳と一緒に動かす）。
	# 選手ごとのずれ（今の総合 − 今の役割の式の値）は翌年 rho 倍に縮み、ゆらぎが足される
	for key: String in derived:
		if not before.has(key) or _toward_peak(q, key, age):
			continue
		var by_role: Dictionary = derived[key]
		var d: Dictionary = by_role[new_role]
		var r: float = before[key] - _formula(by_role[old_role], before)
		var after := {}
		for k: String in d["from"]:
			after[k] = _value(q, side, k)
		var rho := float(d["rho"])
		var nxt := _formula(d, after) + rho * r + float(d["sd"]) * sqrt(1.0 - rho * rho) * rng.randfn(0.0, 1.0)
		if bonus.has(key):
			nxt += clampf(float(bonus[key]) * BONUS_WEIGHT, -BONUS_MAX, BONUS_MAX)
		_set_value(q, side, key, nxt)
	if side == "B" and _no_fielding(q):
		_assign_rookie_fielding(q, block, rng)
	_update_sample(q, side, season)
	q["growth_year"] = year
	return q


## 来季の役割（先発になる確率は今の役割ごとのロジスティック回帰：年齢・スタミナ・総合・出場の少なさ）
func _next_role(p: Dictionary, block: Dictionary, role: String, age: int, regular: float,
		rng: RandomNumberGenerator) -> String:
	var model: Dictionary = block.get("role", {}).get(role, {})
	if model.is_empty():
		return role
	var st: Variant = _value(p, "P", "stamina")
	var ov: Variant = _value(p, "P", "overall")
	var x := [1.0, age - 27.0, ((float(st) if st != null else 40.0) - SimPlayer.SCALE_MEAN) / SimPlayer.SCALE_SD,
		((float(ov) if ov != null else 45.0) - SimPlayer.SCALE_MEAN) / SimPlayer.SCALE_SD, 1.0 - regular]
	var t := 0.0
	for i in x.size():
		t += float(model["weights"][i]) * x[i]
	return "先発" if rng.randf() < 1.0 / (1.0 + exp(-t)) else "救援"


## スタミナ（1登板あたりのアウト数を正規化した値）→ 役割（架空の選手がピークへ育つ間に使う）。史実の能力値は1登板12アウト以上を先発とし、
## スタミナでは 62〜63 が境目（2018・2022年の開幕時点で先発の最小 62〜63、救援の最大 61〜62）
static func role_of_stamina(stamina: float) -> String:
	return "先発" if stamina >= STARTER_STAMINA else "救援"


## const + Σ from[k] × values[k]（values に無い項目は中心の値）
static func _formula(d: Dictionary, values: Dictionary) -> float:
	var v := float(d["const"])
	for k: String in d["from"]:
		var x: Variant = values.get(k)
		v += float(d["from"][k]) * (float(x) if x != null else SimPlayer.SCALE_MEAN)
	return v


## 架空の選手で、その項目のピークへ向かって育っている最中か
static func _toward_peak(p: Dictionary, key: String, age: int) -> bool:
	return is_fictional(p) and p["growth"].get("peak", {}).get(key) != null and age <= peak_age_of(p)


static func _no_fielding(p: Dictionary) -> bool:
	var f: Variant = p.get("fielding")
	return not (f is Dictionary) or f.is_empty()


## 守備の記録が無い野手なら、守備位置・守備力を付ける（入ったばかりの新人用。付けたら true）
func assign_fielding_if_missing(p: Dictionary, rng: RandomNumberGenerator) -> bool:
	if _side(p) != "B" or not _no_fielding(p) or not is_ready():
		return false
	_assign_rookie_fielding(p, coeff["batting"], rng)
	return not _no_fielding(p)


## 守備の記録が無い新人の野手（primary_pos が「内野手」など）に、史実の新人の2年目の守備位置・守備力の例
## （rookie_fielding。primary_pos ごと）から1つ選んで付ける（ゲームは2軍の試合を行わず、守備位置が付かないため）
func _assign_rookie_fielding(p: Dictionary, block: Dictionary, rng: RandomNumberGenerator) -> void:
	var by_pos: Dictionary = block.get("rookie_fielding", {})
	var pool: Array = by_pos.get(str(p.get("primary_pos", "")), [])
	if pool.is_empty():
		for k: String in by_pos:
			pool.append_array(by_pos[k])
	if pool.is_empty():
		return
	var sample: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var fielding := {}
	for pos: String in sample["fielding"]:
		var f: Dictionary = sample["fielding"][pos]
		var entry := {"games": 0, "defense": {}, "gold_glove": false}
		_write(entry["defense"], float(f["defense"]))
		if f.has("arm"):
			entry["arm"] = {}
			_write(entry["arm"], float(f["arm"]))
		fielding[pos] = entry
	p["fielding"] = fielding
	p["primary_pos"] = sample["primary_pos"]
	var primary: Dictionary = fielding[sample["primary_pos"]]
	var br: Dictionary = p["batting"].get("ratings", {})
	br["defense"] = primary["defense"].duplicate()
	if primary.has("arm"):
		br["arm"] = primary["arm"].duplicate()
	p["batting"]["ratings"] = br


## 出場の多い側の係数を使う割合（0〜1）。入団して最初の成長だけ、前年までの出場量（2軍は半分）で混ぜる
static func _regular_weight(p: Dictionary, side: String, block: Dictionary) -> float:
	# 架空の外国人（ForeignPlayers）・有識者の評価から能力を決めたアマ選手（tools/amateur_ratings.py の amateur）は
	# 新人の側の係数（史実のドラフト順位からの事前値が1年目に下がる動き）を使わない
	if p.has("growth_year") or p.get("import") is Dictionary or p.get("amateur") is Dictionary:
		return 1.0
	var s: Variant = p["pitching" if side == "P" else "batting"].get("sample")
	if not (s is Dictionary):
		return 0.0
	var k1 := "outs_1" if side == "P" else "pa_1"
	var k2 := "outs_2" if side == "P" else "pa_2"
	var w := float(s.get(k1, 0.0)) + 0.5 * float(s.get(k2, 0.0))
	return clampf(w / float(block.get("full_sample", 100.0)), 0.0, 1.0)


## 1年での変化の平均（実在の選手は史実の回帰、架空の選手はピークの年齢まではピークへ向かう）
func _mean_delta(p: Dictionary, block: Dictionary, key: String, cur: float, age: int, regular: float) -> float:
	if is_fictional(p):
		var peak_age := peak_age_of(p)
		var peak: Variant = p["growth"].get("peak", {}).get(key)
		if peak != null and age <= peak_age:
			return (float(peak) - cur) / float(peak_age - age + 1)
		age += TYPICAL_PEAK_AGE - peak_age
		regular = 1.0
	var reg := _fit_delta(block["keys"][key], cur, age)
	if regular >= 1.0:
		return reg
	return lerpf(_fit_delta(block["keys_low"][key], cur, age), reg, regular)


func _fit_delta(fit: Dictionary, cur: float, age: int) -> float:
	return _at(fit, "a", age) + _at(fit, "b", age) * (cur - float(fit["center"]))


func _sd(p: Dictionary, block: Dictionary, key: String, age: int, regular: float) -> float:
	if is_fictional(p):
		var sd := _at(block["keys"][key], "sd", age)
		return sd * FICTIONAL_NOISE if age <= peak_age_of(p) else sd
	return lerpf(_at(block["keys_low"][key], "sd", age), _at(block["keys"][key], "sd", age), regular)


func _at(fit: Dictionary, field: String, age: int) -> float:
	var i := clampi(age - int(coeff["age_min"]), 0, fit[field].size() - 1)
	return float(fit[field][i])


## 項目ごとの標準化したゆらぎ（block["order"] の順）。相関した正規乱数（コレスキー分解）を
## 確率に直し、史実の残差の分位点に当てはめる（相関を保ったまま、裾の重さは史実どおり）
func _shocks(block: Dictionary, rng: RandomNumberGenerator) -> Array[float]:
	var low: Array = block["shock_cholesky"]
	var n := low.size()
	var z: Array[float] = []
	for i in n:
		z.append(rng.randfn(0.0, 1.0))
	var out: Array[float] = []
	for i in n:
		var x := 0.0
		for j in i + 1:
			x += float(low[i][j]) * z[j]
		out.append(_quantile(block, _normal_cdf(x)))
	return out


## 標準正規分布の累積分布（Abramowitz & Stegun 7.1.26、誤差 1.5e-7）
static func _normal_cdf(x: float) -> float:
	var t := 1.0 / (1.0 + 0.3275911 * absf(x) / sqrt(2.0))
	var poly := ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
	var y := 1.0 - poly * exp(-x * x / 2.0)
	return 0.5 * (1.0 + (y if x >= 0.0 else -y))


## 確率 u の標準化したゆらぎ（史実の残差の分位点の間を線形補間）
func _quantile(block: Dictionary, u: float) -> float:
	var probs: Array = coeff["quantile_probs"]
	var qs: Array = block["shock_quantiles"]
	if u <= float(probs[0]):
		return float(qs[0])
	for i in range(1, probs.size()):
		if u <= float(probs[i]):
			var t := (u - float(probs[i - 1])) / (float(probs[i]) - float(probs[i - 1]))
			return lerpf(float(qs[i - 1]), float(qs[i]), t)
	return float(qs[-1])


static func _update_sample(p: Dictionary, side: String, season: Dictionary) -> void:
	var keys := ["outs_1", "outs_2"] if side == "P" else ["pa_1", "pa_2"]
	if not (season.has(keys[0]) or season.has(keys[1])):
		return
	var block: Dictionary = p["pitching" if side == "P" else "batting"]
	var sample: Dictionary = block.get("sample", {}) if block.get("sample") is Dictionary else {}
	for k: String in keys:
		sample[k] = snappedf(float(season.get(k, 0.0)) + SAMPLE_DECAY * float(sample.get(k, 0.0)), 0.1)
	block["sample"] = sample


# --- リーグ全体 -----------------------------------------------------------------------

## 全選手を来季（year 年）へ進める。fresh（選手ID → true）は今オフに入ったばかりの選手（新人など）で、
## 成長させずに平均・ばらつきの計算にだけ入れる。seasons は 選手ID → grow() の season。
## 戻り値は新しい選手データの配列（入力は変えない）
func grow_league(players: Array, year: int, rng: RandomNumberGenerator, fresh: Dictionary = {},
		seasons: Dictionary = {}) -> Array:
	var out: Array = []
	var grown: Array = []
	for p: Dictionary in players:
		if fresh.has(p.get("id", "")):
			out.append(p.duplicate(true))
			continue
		var q := grow(p, year, rng, seasons.get(p.get("id", ""), {}))
		out.append(q)
		grown.append(q)
	if is_ready():
		_normalize(out, grown, "B", BATTING_KEYS, coeff["batting"]["target"])
		_normalize(out, grown, "P", PITCHING_KEYS, coeff["pitching"]["target"])
		_normalize_roles(out, grown, float(coeff["pitching"]["target"].get("starter_share", 0.0)), year)
		_normalize_stamina(out, grown, coeff["pitching"]["target"])
	return out


## 投手のうち先発の割合を target に少し寄せる（足りなければスタミナと総合の高い救援を先発に、
## 多すぎればスタミナの低い先発を救援に。成長させた選手だけ動かす）
func _normalize_roles(all: Array, grown: Array, share: float, year: int) -> void:
	if share <= 0.0:
		return
	var pitchers := 0
	var starters := 0
	for p: Dictionary in all:
		if _side(p) == "P":
			pitchers += 1
			if p["pitching"].get("role") == "先発":
				starters += 1
	var need := roundi((share * pitchers - starters) * NORMALIZE_RATE)
	if need == 0:
		return
	var to_starter := need > 0
	var pool: Array = grown.filter(func(p: Dictionary) -> bool:
		return _side(p) == "P" and (p["pitching"].get("role") == "先発") != to_starter and _value(p, "P", "stamina") != null)
	var score := func(p: Dictionary) -> float:
		var ov: Variant = _value(p, "P", "overall")
		return float(_value(p, "P", "stamina")) + 0.5 * (float(ov) if ov != null else 45.0)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return score.call(a) > score.call(b) if to_starter else score.call(a) < score.call(b))
	# スタミナは役割が変わったときの回帰（救援>先発・先発>救援）の平均の値にする
	var fit: Dictionary = coeff["pitching"]["stamina_by_role"]["救援>先発" if to_starter else "先発>救援"]
	for p: Dictionary in pool.slice(0, absi(need)):
		var st := float(_value(p, "P", "stamina"))
		var age := age_at(p, year)
		st += _fit_delta(fit, st, age if age >= 0 else TYPICAL_PEAK_AGE)
		p["pitching"]["role"] = "先発" if to_starter else "救援"
		_set_value(p, "P", "stamina", maxf(st, STARTER_STAMINA) if to_starter else minf(st, STARTER_STAMINA - 1.0))


## 平均・ばらつきを target に少し寄せる（全員で測り、成長させた選手だけ動かす）
func _normalize(all: Array, grown: Array, side: String, keys: Array, target: Dictionary) -> void:
	for key: String in keys:
		if key in NORMALIZE_SKIP or not target.has(key):
			continue
		_normalize_key(all, grown, side, key, target[key], func(_p: Dictionary) -> bool: return true)


## スタミナは役割ごとに平均・ばらつきを寄せる（役割とスタミナが食い違わないよう境目で止める）
func _normalize_stamina(all: Array, grown: Array, target: Dictionary) -> void:
	for role: String in ["先発", "救援"]:
		var t: Variant = target.get("stamina:" + role)
		if not (t is Dictionary):
			continue
		var in_role := func(p: Dictionary) -> bool: return p["pitching"].get("role") == role
		_normalize_key(all, grown, "P", "stamina", t, in_role)
		for p: Dictionary in grown:
			if _side(p) == "P" and in_role.call(p) and _value(p, "P", "stamina") != null:
				var st := float(_value(p, "P", "stamina"))
				_set_value(p, "P", "stamina", maxf(st, STARTER_STAMINA) if role == "先発" else minf(st, STARTER_STAMINA - 1.0))


## filter に合う選手の key の平均・ばらつきを t（{mean, sd}）に NORMALIZE_RATE だけ寄せる（全員で測り、grown だけ動かす）
func _normalize_key(all: Array, grown: Array, side: String, key: String, t: Dictionary, filter: Callable) -> void:
	var vals: Array[float] = []
	for p: Dictionary in all:
		if _side(p) == side and filter.call(p) and _value(p, side, key) != null:
			vals.append(float(_value(p, side, key)))
	if vals.size() < 30:
		return
	var stats := mean_sd(vals)
	var mean: float = stats[0]
	var sd: float = stats[1]
	var shift := clampf((float(t["mean"]) - mean) * NORMALIZE_RATE, -NORMALIZE_MAX_SHIFT, NORMALIZE_MAX_SHIFT)
	var factor := 1.0
	if sd > 0.0:
		factor = clampf(pow(float(t["sd"]) / sd, NORMALIZE_RATE), NORMALIZE_SD_MIN, NORMALIZE_SD_MAX)
	for p: Dictionary in grown:
		if _side(p) != side or not filter.call(p) or _value(p, side, key) == null:
			continue
		var v := float(_value(p, side, key))
		_set_value(p, side, key, mean + (v - mean) * factor + shift)


static func mean_sd(vals: Array) -> Array:
	var m := 0.0
	for v: float in vals:
		m += v
	m /= maxf(1.0, vals.size())
	var s := 0.0
	for v: float in vals:
		s += (v - m) * (v - m)
	return [m, sqrt(s / maxf(1.0, vals.size()))]


# --- 引退 -------------------------------------------------------------------------

## p が今季かぎりで引退する確率（year は来季。foreign は RosterRules.is_foreign）。
## playing を渡すと出場量（0〜1）をそれで置き換える（ゲーム内の今季の出場から決めるとき）
func retire_probability(p: Dictionary, year: int, foreign: bool, playing: float = -1.0) -> float:
	if not coeff.has("retire"):
		return 0.0
	var ab := Salary.ability(p)
	var age := age_at(p, year)
	if age < 0:
		age = TYPICAL_PEAK_AGE
	var pl: float = ab[1] if playing < 0.0 else playing
	var f := 1.0 if foreign else 0.0
	# 特徴量の並びは generated/growth.json の retire.features（外国人は実力・出場との掛け算も）
	var x := [1.0, age - 30.0, maxf(0.0, age - 33.0), maxf(0.0, 26.0 - age), float(ab[0]), pl,
		f, 1.0 if p.get("is_pitcher", false) else 0.0, f * float(ab[0]), f * pl]
	var w: Array = coeff["retire"]["weights"]
	var t := 0.0
	for i in w.size():
		t += float(w[i]) * x[i]
	return 1.0 / (1.0 + exp(-t))


func should_retire(p: Dictionary, year: int, foreign: bool, rng: RandomNumberGenerator,
		playing: float = -1.0) -> bool:
	return rng.randf() < retire_probability(p, year, foreign, playing)


# --- 値の読み書き ------------------------------------------------------------------

static func _side(p: Dictionary) -> String:
	if p.get("is_pitcher", false) and p.get("pitching") is Dictionary:
		return "P"
	if not p.get("is_pitcher", false) and p.get("batting") is Dictionary:
		return "B"
	return ""


## 項目の今の値（無ければ null）。野手の守備力・肩力は batting.ratings（主な守備位置）、無ければ最初の守備位置
static func _value(p: Dictionary, side: String, key: String) -> Variant:
	if side == "P":
		var pit: Dictionary = p["pitching"]
		if key == "velocity":
			var v: Variant = pit.get("velocity")
			return float(v["kmh"]) if v is Dictionary and v.get("kmh") != null else null
		var r: Variant = pit.get("ratings", {}).get(key) if pit.get("ratings") is Dictionary else null
		return float(r["value"]) if r is Dictionary and r.get("value") != null else null
	var bat: Dictionary = p["batting"]
	var br: Variant = bat.get("ratings", {}).get(key) if bat.get("ratings") is Dictionary else null
	if br is Dictionary and br.get("value") != null:
		return float(br["value"])
	if key in ["defense", "arm"] and p.get("fielding") is Dictionary:
		for pos: String in p["fielding"]:
			var f: Variant = p["fielding"][pos].get(key)
			if f is Dictionary and f.get("value") != null:
				return float(f["value"])
	return null


## 項目の値を書き換える（ランク・弾道・守備位置ごとの値も合わせる）
static func _set_value(p: Dictionary, side: String, key: String, value: float) -> void:
	var old: Variant = _value(p, side, key)
	if old == null:
		return
	if side == "P":
		var pit: Dictionary = p["pitching"]
		if key == "velocity":
			pit["velocity"] = {"kmh": clampi(roundi(value), VELOCITY_MIN, VELOCITY_MAX), "source": "growth"}
		else:
			_write(pit["ratings"][key], value)
		return
	var v := clampi(roundi(value), VALUE_MIN, VALUE_MAX)
	var delta := v - roundi(float(old))
	var br: Dictionary = p["batting"].get("ratings", {})
	if br.get(key) is Dictionary:
		if key == "power":
			_shift_trajectory(p["batting"], float(old), float(v))
		_write(br[key], v)
	# 守備力・肩力は守備位置ごとの値も同じだけ動かす（位置どうしの差を保つ）
	if key in ["defense", "arm"] and p.get("fielding") is Dictionary and delta != 0:
		for pos: String in p["fielding"]:
			var f: Variant = p["fielding"][pos].get(key)
			if f is Dictionary and f.get("value") != null:
				_write(f, float(f["value"]) + delta)


static func _write(r: Dictionary, value: float) -> void:
	var v := clampi(roundi(value), VALUE_MIN, VALUE_MAX)
	r["value"] = v
	r["rank"] = rank_of(v)


## 弾道はパワーの段が変わった分だけ動かす（選手ごとの元の差は保つ）
static func _shift_trajectory(batting: Dictionary, old_power: float, new_power: float) -> void:
	var traj: Variant = batting.get("trajectory")
	if traj == null:
		return
	var step := _trajectory_class(new_power) - _trajectory_class(old_power)
	if step != 0:
		batting["trajectory"] = clampi(int(traj) + step, 1, 4)


static func _trajectory_class(power: float) -> int:
	var z := (power - SimPlayer.SCALE_MEAN) / SimPlayer.SCALE_SD
	for c: Array in TRAJECTORY_CUTOFFS:
		if z >= float(c[0]):
			return int(c[1])
	return 1
