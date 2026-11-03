class_name FictionalTalent
extends RefCounted
## 架空ドラフト候補の能力生成エンジン（v2）
## 潜在因子モデル＋スコア拘束射影＋分位点較正により、
## 多様で魅力的な個性（ロマン砲、天才打者、俊足堅守、剛腕、精密機械、即戦力の怪物、二刀流）を
## 長期インフレゼロで生成する。

const MODEL_PATH := "res://../generated/fictional_model.json"

## 年の質（豊作・不作）パラメータ
const QUALITY_RHO := 0.20
const QUALITY_SD := 0.18
const QUALITY_JUMP := 0.35
const QUALITY_DIP := -0.30
const QUALITY_JUMP_RATE := 0.04

## 一芸スパイクの発生確率
const SPIKE_RATE := {
	"高校": 0.14,
	"大学": 0.10,
	"社会人": 0.08,
	"独立": 0.35,
}

## 二刀流の発生確率（ドラフト1年あたりの期待人数）
const TWO_WAY_A_RATE := 0.028  # 本格二刀流の怪物：約36年に1人
const TWO_WAY_B_RATE := 0.25   # 投手本職＋打撃優秀：4年に1人
const TWO_WAY_C_RATE := 0.15   # 野手本職＋投手可能：6〜7年に1人
const TWO_WAY_D_RATE := 0.55   # 未完の二刀流素材（高校生）：2年に1人強
const MAX_TWO_WAY_PER_CLASS := 2  # 豊作年でも最大2人

const _TWO_WAY_PLAN := [
	["A", TWO_WAY_A_RATE],
	["B", TWO_WAY_B_RATE],
	["C", TWO_WAY_C_RATE],
	["D", TWO_WAY_D_RATE],
]

## 怪物（opts.monster。FictionalDraft が年に0〜2人選ぶ）：才能の分位点の範囲と、入団時の完成度
const MONSTER_U := [0.990, 0.999]
const MONSTER_MATURITY := {"高校": [0.70, 0.82], "default": [0.78, 0.88]}
## 入団時の完成度（ピークに対する。高校生はふだん C〜D になる低さ）
const MATURITY := {"高校": [0.45, 0.60], "大学": [0.55, 0.85], "専門": [0.50, 0.80], "社会人": [0.75, 0.95], "default": [0.50, 0.85]}

## 投手の先発型・救援型（作業50）：先発型の割合は才能の分位点 u で START_SHARE[0]（u=0.5以下）→ [1]（u=1）
const START_SHARE := [0.40, 0.90]
const MONSTER_START_SHARE := 0.90
## ピークのスタミナ：先発型は C〜A、救援型は F〜E
const STARTER_STAMINA := [65, 84]
const RELIEVER_STAMINA := [28, 48]
## スタミナの伸びしろ（50を超えた分の割合。ほかの項目より伸びしろが小さく、先発型は入団時から C 以上）
const STAMINA_MARGIN_SCALE := 0.35

var model: Dictionary = {}
var ready: bool = false


func _init(m: Dictionary = {}) -> void:
	if not m.is_empty():
		model = m
		ready = true
	else:
		load_model()


func load_model() -> void:
	var bundled := "res://data/generated/fictional_model.json"
	if FileAccess.file_exists(bundled):
		var bp: Variant = JSON.parse_string(FileAccess.get_file_as_string(bundled))
		if bp is Dictionary:
			model = bp
			ready = true
			return
	var path := ProjectSettings.globalize_path(MODEL_PATH)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		model = parsed
		ready = true


## 年の質（Q_y）を前年の値から更新して生成
static func next_class_quality(prev: float, rng: RandomNumberGenerator) -> float:
	var q: float = QUALITY_RHO * prev + sqrt(1.0 - QUALITY_RHO * QUALITY_RHO) * QUALITY_SD * rng.randfn(0.0, 1.0)
	var roll := rng.randf()
	if roll < QUALITY_JUMP_RATE:
		q += QUALITY_JUMP  # 黄金世代
	elif roll < QUALITY_JUMP_RATE * 2.0:
		q += QUALITY_DIP   # 谷間の世代
	return clampf(q, -0.65, 0.75)


## 経験分位点表から分位点 u (0.0〜1.0) に対応するスコアを補間
func quantile_score(key: String, u: float) -> float:
	var quantiles: Array = model.get("quantiles", {}).get(key, [])
	if quantiles.is_empty():
		quantiles = model.get("quantiles", {}).get("all_B" if key.ends_with("_B") else "all_P", [])
	if quantiles.is_empty():
		return 0.0
	var clamped_u := clampf(u, 0.0, 1.0)
	var idx_float := clamped_u * 100.0
	var i0 := clampi(int(floor(idx_float)), 0, 99)
	var i1 := clampi(i0 + 1, 0, 100)
	var frac := idx_float - float(i0)
	var v0 := float(quantiles[i0])
	var v1 := float(quantiles[i1])
	return lerpf(v0, v1, frac)


## 多変量正規分布から相関を持つベクトルを生成（コレスキー行列乗算）
func sample_correlated_z(chol: Array, rng: RandomNumberGenerator) -> Array[float]:
	var n := chol.size()
	var raw: Array[float] = []
	for i in n:
		raw.append(rng.randfn(0.0, 1.0))
	var out: Array[float] = []
	for i in n:
		var s := 0.0
		var row: Array = chol[i]
		for j in row.size():
			s += float(row[j]) * raw[j]
		out.append(s)
	return out


## 標準正規分布 CDF のロジスティック近似
static func normal_cdf(x: float) -> float:
	return 1.0 / (1.0 + exp(-1.702 * x))


## ソフト上限: 85を超えると100に向かって圧縮（カンスト過多を防ぐ）
static func soft_cap(val: float) -> float:
	if val <= 85.0:
		return val
	return 85.0 + 15.0 * tanh((val - 85.0) / 15.0)


## 候補選手1人の能力とプロファイルを生成
func generate_player(category: String, pos: String, side: String, quality: float,
		rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	if not ready:
		load_model()
	var is_p := (side == "P")

	# 1. 真の才能 T の決定
	var is_monster := bool(opts.get("monster", false))
	var u: float
	if is_monster:
		u = rng.randf_range(MONSTER_U[0], MONSTER_U[1])  # 本当に飛び抜けた才能
	else:
		# 分位点モデルに基づく才能＋年の質 Q_y
		var z_val := rng.randfn(0.0, 1.0) + quality
		u = clampf(normal_cdf(z_val), 0.001, 0.999)

	var q_key := "%s_%s" % [category, side]
	var true_talent: float = quantile_score(q_key, u)

	# 2. ピーク能力の生成（野手 または 投手）
	var peak_dict := {}
	if is_p:
		peak_dict = _generate_pitcher_peak(true_talent, category, rng, is_monster, u)
	else:
		peak_dict = _generate_batter_peak(true_talent, category, pos, rng, is_monster)

	# 3. 入団時能力の生成（peak - 伸びしろ）
	var entry_dict := _generate_entry_abilities(peak_dict, category, side, rng, is_monster)

	# 4. ピーク年齢・成長タイプの決定
	var growth_info := _generate_growth_info(category, entry_dict["maturity"], rng)

	# 5. スカウトの見た目の評価（Ŝ）の算出（観測ノイズ）
	var scout_noise: float = rng.randfn(0.0, 0.28 if category == "高校" else 0.18)
	var apparent_eval: float = true_talent * 0.7 + entry_dict["entry_score"] * 0.3 + scout_noise

	return {
		"side": side,
		"pos": pos,
		"category": category,
		"true_talent": true_talent,
		"apparent_eval": apparent_eval,
		"is_monster": is_monster,
		"peak": peak_dict,
		"player": entry_dict["player"],
		"growth": {
			"type": growth_info["type"],
			"peak_age": growth_info["peak_age"],
			"peak": peak_dict["ratings"],
		},
		"two_way": {"active": false, "type": "", "desc": ""},
		"maturity": entry_dict["maturity"],
	}


## 野手のピーク能力生成
func _generate_batter_peak(target_t: float, category: String, pos: String,
		rng: RandomNumberGenerator, is_monster: bool) -> Dictionary:
	var m_bat: Dictionary = model.get("batting", {})
	var keys: Array = m_bat.get("keys", ["meet", "power", "eye", "speed", "defense", "arm"])
	var means: Dictionary = m_bat.get("means", {})
	var stds: Dictionary = m_bat.get("stds", {})
	var chol: Array = m_bat.get("chol", [])
	var weights: Dictionary = m_bat.get("weights", {})
	var beta0: float = float(m_bat.get("beta0", 0.0))
	var pos_bias: Dictionary = m_bat.get("pos_bias", {}).get(pos, {})

	# 相関つき z スコア
	var z_list := sample_correlated_z(chol, rng)
	var z_map := {}
	for i in keys.size():
		var k: String = keys[i]
		z_map[k] = z_list[i]

	# 一芸スパイク（ロマン砲、韋駄天、守備職人など）
	var spike_chance: float = float(SPIKE_RATE.get(category, 0.10))
	if rng.randf() < spike_chance or (is_monster and rng.randf() < 0.4):
		var spike_key: String = keys[rng.randi_range(0, keys.size() - 1)]
		var spike_size: float = rng.randf_range(1.0, 2.0)
		z_map[spike_key] += spike_size
		# 他の項目を少し削ってトレードオフ（無茶なインフレを防ぎ尖りを強調）
		for k: String in keys:
			if k != spike_key:
				z_map[k] -= spike_size * 0.22

	# 守備位置ごとの偏り
	for k: String in keys:
		var bias_val: float = float(pos_bias.get(k, 0.0))
		var sd_val: float = float(stds.get(k, 12.0))
		if sd_val > 0.0:
			z_map[k] += bias_val / sd_val

	# スコア拘束射影: 現在の予測スコア c を計算し、target_t との差を w 方向に射影
	var current_score: float = beta0
	var sum_w2 := 0.0
	for k: String in keys:
		var w: float = float(weights.get(k, 0.16))
		current_score += w * z_map[k]
		sum_w2 += w * w

	if sum_w2 > 0.0:
		var diff: float = target_t - current_score
		var step: float = diff / sum_w2
		for k: String in keys:
			var w: float = float(weights.get(k, 0.16))
			z_map[k] += w * step

	# z スコアから実数値への変換 ＆ ソフト上限
	var ratings := {}
	for k: String in keys:
		var mu: float = float(means.get(k, 50.0))
		var sig: float = float(stds.get(k, 12.0))
		var raw_val: float = mu + z_map[k] * sig
		ratings[k] = clampi(roundi(soft_cap(raw_val)), 15, 99)

	return {"ratings": ratings, "score": target_t}


## 投手のピーク能力生成
func _generate_pitcher_peak(target_t: float, category: String,
		rng: RandomNumberGenerator, is_monster: bool, u: float = 0.5) -> Dictionary:
	var m_pit: Dictionary = model.get("pitching", {})
	var keys: Array = m_pit.get("keys", ["stamina", "k9", "bb9", "hr9", "velocity"])
	var means: Dictionary = m_pit.get("means", {})
	var stds: Dictionary = m_pit.get("stds", {})
	var chol: Array = m_pit.get("chol", [])
	var weights: Dictionary = m_pit.get("weights", {})
	var beta0: float = float(m_pit.get("beta0", 0.0))

	var z_list := sample_correlated_z(chol, rng)
	var z_map := {}
	for i in keys.size():
		var k: String = keys[i]
		z_map[k] = z_list[i]

	# 一芸スパイク（剛腕速球派、精密機械など）
	var spike_chance: float = float(SPIKE_RATE.get(category, 0.10))
	if rng.randf() < spike_chance or (is_monster and rng.randf() < 0.4):
		var spike_key: String = keys[rng.randi_range(0, keys.size() - 1)]
		var spike_size: float = rng.randf_range(1.0, 1.8)
		z_map[spike_key] += spike_size
		# 球速が突出した場合、四球(bb9)が少し荒れやすくなるリアルな相関
		if spike_key == "velocity":
			z_map["bb9"] -= spike_size * 0.35
			z_map["k9"] += spike_size * 0.40
		elif spike_key == "bb9":
			z_map["velocity"] -= spike_size * 0.20

	# スコア拘束射影
	var current_score: float = beta0
	var sum_w2 := 0.0
	for k: String in keys:
		var w: float = float(weights.get(k, 0.20))
		current_score += w * z_map[k]
		sum_w2 += w * w

	if sum_w2 > 0.0:
		var diff: float = target_t - current_score
		var step: float = diff / sum_w2
		for k: String in keys:
			var w: float = float(weights.get(k, 0.20))
			z_map[k] += w * step

	var ratings := {}
	for k: String in keys:
		var mu: float = float(means.get(k, 50.0))
		var sig: float = float(stds.get(k, 12.0))
		var raw_val: float = mu + z_map[k] * sig
		if k == "velocity":
			ratings[k] = clampi(roundi(raw_val), 133, 163)
		else:
			ratings[k] = clampi(roundi(soft_cap(raw_val)), 15, 99)

	# 先発型・救援型（上位の才能ほど先発型が多い）。スタミナは実力の点にほとんど効かないので型で決める
	var start_share: float = MONSTER_START_SHARE if is_monster \
		else lerpf(START_SHARE[0], START_SHARE[1], clampf((u - 0.5) / 0.5, 0.0, 1.0))
	if rng.randf() < start_share:
		ratings["stamina"] = maxi(int(ratings["stamina"]), rng.randi_range(STARTER_STAMINA[0], STARTER_STAMINA[1]))
	else:
		ratings["stamina"] = mini(int(ratings["stamina"]), rng.randi_range(RELIEVER_STAMINA[0], RELIEVER_STAMINA[1]))

	# 投手の総合力（overall）の算出
	var k9_v := float(ratings.get("k9", 50))
	var bb9_v := float(ratings.get("bb9", 50))
	var hr9_v := float(ratings.get("hr9", 50))
	var ovr: float = 0.45 * k9_v + 0.35 * bb9_v + 0.20 * hr9_v
	ratings["overall"] = clampi(roundi(ovr), 15, 99)

	return {"ratings": ratings, "score": target_t}


## 入団時能力（entry）の生成
func _generate_entry_abilities(peak_dict: Dictionary, category: String, side: String,
		rng: RandomNumberGenerator, is_monster: bool) -> Dictionary:
	var peak_ratings: Dictionary = peak_dict.get("ratings", {})
	var is_p := (side == "P")

	# 成熟度 R: 高校生は低め、社会人は高め。怪物は入団時から主力級だが、まだ伸びる
	var range_m: Array = MONSTER_MATURITY.get(category, MONSTER_MATURITY["default"]) if is_monster \
		else MATURITY.get(category, MATURITY["default"])
	var maturity: float = rng.randf_range(range_m[0], range_m[1])

	var entry_ratings := {}
	var entry_vel := 140

	if is_p:
		for k: String in ["stamina", "k9", "bb9", "hr9", "overall"]:
			var pk: float = float(peak_ratings.get(k, 50))
			# 伸びしろ: 成熟度に応じてピークから減算（スタミナは小さい）
			var margin := (pk - 35.0) * (1.0 - maturity) * rng.randf_range(0.85, 1.15)
			if k == "stamina":
				margin = maxf(0.0, pk - 50.0) * (1.0 - maturity) * STAMINA_MARGIN_SCALE * rng.randf_range(0.85, 1.15)
			entry_ratings[k] = clampi(roundi(pk - margin), 20, roundi(pk))
		# 球速の伸びしろ
		var pk_vel: float = float(peak_ratings.get("velocity", 145))
		var vel_margin := (pk_vel - 130.0) * (1.0 - maturity) * 0.7
		entry_vel = clampi(roundi(pk_vel - vel_margin), 130, roundi(pk_vel))
	else:
		for k: String in ["meet", "power", "eye", "speed", "defense", "arm"]:
			var pk: float = float(peak_ratings.get(k, 50))
			# 走力や肩は若い頃から完成度が高く、パワーや選球眼は後から伸びる特性
			var trait_scale: float = 1.0
			if k == "speed" or k == "arm":
				trait_scale = 0.5
			elif k == "power" or k == "eye":
				trait_scale = 1.25
			var margin := (pk - 35.0) * (1.0 - maturity) * trait_scale * rng.randf_range(0.85, 1.15)
			entry_ratings[k] = clampi(roundi(pk - margin), 20, roundi(pk))

	# 選手データ構造の作成（SimPlayer, GameData と互換）
	var player_dict := {"ratings": {}}
	for k: String in entry_ratings:
		player_dict["ratings"][k] = {"value": entry_ratings[k], "rank": _ability_rank(entry_ratings[k])}
	if is_p:
		player_dict["velocity"] = {"kmh": entry_vel, "source": "fictional"}
		player_dict["role"] = "先発" if entry_ratings.get("stamina", 50) >= 55 else "救援"

	# 入団時スコアの概算
	var entry_score := 0.0
	if is_p:
		entry_score = (float(entry_ratings.get("overall", 50)) - 50.0) / 12.0
	else:
		entry_score = (float(entry_ratings.get("meet", 50)) * 0.4 + float(entry_ratings.get("power", 50)) * 0.35 + float(entry_ratings.get("speed", 50)) * 0.25 - 50.0) / 12.0

	return {
		"player": player_dict,
		"maturity": maturity,
		"entry_score": entry_score,
	}


## ピーク年齢と成長タイプ
func _generate_growth_info(category: String, maturity: float, rng: RandomNumberGenerator) -> Dictionary:
	var base_age: int = 27
	match category:
		"高校": base_age = 28
		"大学", "専門": base_age = 27
		"社会人": base_age = 26
		"独立": base_age = 27

	# 成熟度が低い（伸びしろ大）ほど晩成にシフト
	var shift := roundi((0.7 - maturity) * 3.0) + rng.randi_range(-1, 1)
	var peak_age: int = clampi(base_age + shift, 24, 32)

	var gtype := "普通"
	if peak_age <= 25:
		gtype = "早熟"
	elif peak_age >= 29:
		gtype = "晩成"

	return {"peak_age": peak_age, "type": gtype}


## ドラフトクラス単位での二刀流選手の割り当て（年あたり期待人数を忠実に守る）
## 候補全員が生成された後に1回だけ呼び出す
func assign_two_way_for_class(candidates: Array, rng: RandomNumberGenerator) -> Array:
	var assigned: Array = []
	var used := {}

	for entry in _TWO_WAY_PLAN:
		var type: String = str(entry[0])
		var rate: float = float(entry[1])
		var count: int = _poisson(rng, rate)

		for i in count:
			if assigned.size() >= MAX_TWO_WAY_PER_CLASS:
				return assigned
			var idx: int = _pick_weighted_two_way(candidates, type, used, rng)
			if idx < 0:
				break
			used[idx] = true
			var c: Dictionary = candidates[idx]
			_apply_two_way(c, type, rng)
			assigned.append(c)

	return assigned


static func _poisson(rng: RandomNumberGenerator, lambda: float) -> int:
	if lambda <= 0.0:
		return 0
	var limit := exp(-lambda)
	var k := 0
	var p := rng.randf()
	while p > limit:
		k += 1
		p *= rng.randf()
	return k


func _pick_weighted_two_way(candidates: Array, type: String, used: Dictionary, rng: RandomNumberGenerator) -> int:
	var weights := PackedFloat32Array()
	weights.resize(candidates.size())
	var total := 0.0
	for i in candidates.size():
		var w := 0.0
		if not used.has(i):
			w = _two_way_weight(candidates[i], type)
		weights[i] = w
		total += w

	if total <= 0.0:
		return -1

	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0 and weights[i] > 0.0:
			return i
	for i in range(weights.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return i
	return -1


func _two_way_weight(c: Dictionary, type: String) -> float:
	var side: String = c.get("side", "")
	var cat: String = c.get("category", "")
	var t: float = float(c.get("amateur", {}).get("future_score", 0.0))
	var peak: Dictionary = c.get("growth", {}).get("peak", {})

	match type:
		"A":
			# 本格二刀流の怪物：高校・大学の上位才能
			if cat in ["高校", "大学"] and t >= 0.5:
				return maxf(t + 1.0, 0.1)
			return 0.0
		"B":
			# 投手本職＋打撃優秀：投手のみ
			if side == "P":
				return maxf(t + 2.0, 0.1)
			return 0.0
		"C":
			# 野手本職＋投手可能：野手で強肩（arm >= 58）
			if side == "B":
				var arm_v: float = float(peak.get("arm", 50))
				return maxf(arm_v - 55.0, 0.1) if arm_v >= 58.0 else 0.0
			return 0.0
		"D":
			# 未完の素材：高校生のみ
			if cat == "高校":
				return maxf(t + 1.5, 0.1)
			return 0.0
	return 0.0


func _apply_two_way(p: Dictionary, type: String, rng: RandomNumberGenerator) -> void:
	var side: String = p.get("side", "")
	var category: String = p.get("category", "高校")
	var t: float = float(p.get("amateur", {}).get("future_score", 0.0))

	var desc := ""
	match type:
		"A": desc = "本格二刀流の怪物"
		"B": desc = "強打の本格派投手"
		"C": desc = "マウンドにも立てる強肩野手"
		"D": desc = "投打に可能性を秘めた二刀流原石"

	p["two_way"] = {"active": true, "type": type, "desc": desc}
	if p.has("amateur") and p["amateur"] is Dictionary:
		p["amateur"]["two_way"] = p["two_way"]

	# 副次能力の付与
	if side == "P":
		# 投手本職の場合、打撃能力を生成して付与
		var target_t: float = t * 0.8
		if type == "A":
			target_t = maxf(t, 1.2)
		var bat_gen: Dictionary = _generate_batter_peak(target_t, category, "外野手", rng, type == "A")
		var bat_ent: Dictionary = _generate_entry_abilities(bat_gen, category, "B", rng, type == "A")
		p["batting"] = bat_ent["player"]
		var pwr: float = float(bat_gen["ratings"].get("power", 50))
		p["batting"]["trajectory"] = 3 if pwr >= 65.0 else 2
		# peak にも野手能力をマージ
		var p_peak: Dictionary = p.get("growth", {}).get("peak", {})
		for k in bat_gen["ratings"]:
			p_peak[k] = bat_gen["ratings"][k]
	else:
		# 野手本職の場合、投球能力を生成して付与
		var target_t: float = t * 0.8
		if type == "A":
			target_t = maxf(t, 1.2)
		var pit_gen: Dictionary = _generate_pitcher_peak(target_t, category, rng, type == "A")
		var pit_ent: Dictionary = _generate_entry_abilities(pit_gen, category, "P", rng, type == "A")
		p["pitching"] = pit_ent["player"]
		var p_peak: Dictionary = p.get("growth", {}).get("peak", {})
		for k in pit_gen["ratings"]:
			p_peak[k] = pit_gen["ratings"][k]
		if pit_gen.has("velocity"):
			p_peak["velocity"] = pit_gen["velocity"]


## 能力値からタイプ名（二つ名・寸評）を判定
static func decide_player_type(p: Dictionary) -> String:
	var two_way: Dictionary = p.get("two_way", {})
	if bool(two_way.get("active", false)):
		match str(two_way.get("type", "")):
			"A": return "本格二刀流の怪物"
			"B": return "強打の本格派右腕" if p.get("throws", "") == "右" else "強打の本格派左腕"
			"C": return "剛腕兼業の強肩野手"
			"D": return "投打二刀流の原石"

	var side: String = p.get("side", "")
	var peak: Dictionary = p.get("growth", {}).get("peak", {})

	if side == "P":
		var vel := int(peak.get("velocity", 145))
		var k9_v := float(peak.get("k9", 50))
		var bb9_v := float(peak.get("bb9", 50))
		var sta := float(peak.get("stamina", 50))

		if vel >= 156 and k9_v >= 70:
			return "超剛腕"
		if bb9_v >= 75 and k9_v >= 65:
			return "精密機械"
		if vel <= 142 and bb9_v >= 70:
			return "軟投派の技巧派"
		if sta >= 75 and k9_v >= 65:
			return "本格派大黒柱"
		if k9_v >= 75:
			return "奪三振マシン"
		return "本格派投手"
	else:
		var pwr := float(peak.get("power", 50))
		var meet := float(peak.get("meet", 50))
		var spd := float(peak.get("speed", 50))
		var df := float(peak.get("defense", 50))
		var eye := float(peak.get("eye", 50))

		if pwr >= 76 and meet <= 48:
			return "ロマン砲スラッガー"
		if pwr >= 75 and meet >= 65:
			return "三冠王候補の大砲"
		if meet >= 72 and eye >= 68:
			return "天才打者"
		if spd >= 78 and df >= 72:
			return "韋駄天の守備職人"
		if spd >= 80:
			return "韋駄天スピードスター"
		if df >= 78:
			return "守備の名手"
		if pwr >= 68 and meet >= 65 and spd >= 68 and df >= 65:
			return "走攻守揃った万能選手"
		if p.get("category", "") == "高校" and float(p.get("true_talent", 0.0)) >= 1.0:
			return "将来大化けの超大器"
		return "巧打の野手" if meet >= pwr else "強打の野手"


static func _ability_rank(val: int) -> String:
	if val >= 90: return "S"
	if val >= 80: return "A"
	if val >= 70: return "B"
	if val >= 60: return "C"
	if val >= 50: return "D"
	if val >= 40: return "E"
	if val >= 20: return "F"
	return "G"
