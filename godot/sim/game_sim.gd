class_name GameSim
extends RefCounted
## 1試合のシミュレーション（打席単位。docs/SPEC.md「試合シミュレーション」の8段階）。
##
##   1. 投球数カウント → スタミナの目安を超えると投手の能力（z 値）が下がる      _fatigue()
##   2. 四球判定：選球眼 × 制球 → シグモイド                                   _plate_appearance()
##   3. 打撃結果判定：ミート × 投手総合力 → 多項分布（三振・本塁打・打球）       _plate_appearance()
##   4. 打球の質判定（凡打球 / 鋭い当たり）                                     _ball_in_play()
##   5. 凡打球 → 内野守備力（範囲）でアウト判定、失敗なら内野安打、アウトは失策率判定  _weak_ball()
##   6. 鋭い当たり → 外野守備力（範囲・肩力）で長打抑制・進塁阻止                 _sharp_ball()
##   7. 走者進塁：走力を加味（生還可否）、盗塁も成功率から判定                    _advance_on_hit() / _try_steal()
##   8. 継投判断：スタミナの目安＋采配方針のしきい値でリリーフ交代                _check_pitching_change()
##
## 守備の記録（守備得点の元。Records.fielding_runs）：段階5・6・7で、守備位置ごとに打球の機会と処理、失策、
## 外野の肩（長打を単打に止めた・走者を止めた・刺した）、捕手の盗塁阻止と暴投・捕逸、守備のアウト数を _fld に数え、
## 結果の "fielding"（[ビジター, ホーム] の 選手ID → 守備位置 → {キー: 数}）で返す。キーは Records.FIELDING_PARTS。
## あわせて、その機会で平均的な野手（守備力・肩の z = 0）と比べた成功の確率の差 × 1000 を「見込み」のキー（〜d）に足す
## （作業44。守備得点はこちらで数える。実際に捕れたかで数えると運のぶれが能力の差より大きくなるため）
##
## 能力値は z 値（SimPlayer）で扱い、確率は「リーグ平均のロジット＋係数×z」をシグモイドで戻す。
## 係数・基準値（下の定数）は 2008年の史実のリーグ成績に合うように調整した（HANDOFF.md 参照）。

# --- 基準値（リーグ平均の打席あたり確率）と係数 -----------------------------------------
const P_HBP := 0.0102
const BASE_BB := 0.072
const BASE_K := 0.179
const BASE_HR := 0.0228
const A_EYE_BB := 0.40      ## 選球眼 → 四球（作業70で 0.30 から。選球眼の z と実際の四球率の関係）
const A_CTL_BB := 0.36      ## 制球 → 四球（減）（作業70で 0.18 から。能力値の BB9 の z と実際の四球率の関係に合わせる）
const A_MEET_K := 0.29      ## ミート → 三振（減）
const A_K9_K := 0.30        ## 奪三振 → 三振（作業70で 0.18 から。K9 の z と実際の三振率の関係）
const A_POW_HR := 0.60      ## パワー → 本塁打（作業70で 0.36 から。パワー99・弾道4で本塁打率 8%＝600打席で50本前後）
const A_TRAJ_HR := 0.08     ## 弾道 → 本塁打
const A_HR9_HR := 0.44      ## 被弾抑制 → 本塁打（減）（作業70で 0.20 から。HR9 の z と実際の被本塁打率の関係）

## 打球の質（鋭い当たりの割合）
const BASE_SHARP := 0.363
const A_MEET_SHARP := 0.15
const A_POW_SHARP := 0.08
const A_OVR_SHARP := 0.05   ## 投手総合力 → 鋭い当たり（減）

## 凡打球
const WEAK_GROUNDER := 0.62  ## 凡打球のうちゴロの割合（残りはフライ・ポップ）
const GROUNDER_OUT := 0.81
const A_IF_RANGE := 0.18    ## 内野守備力 → アウト（作業44で 0.15 から。守備得点の散らばりを DELTA の範囲に）
const A_SPEED_IF := 0.28    ## 走力 → 内野安打
const WEAK_FLY_OUT := 0.94
const BASE_ERROR := 0.064   ## アウトになる打球での失策率
const A_DEF_ERROR := 0.25
const FLY_ERROR := 0.012    ## 外野フライ・ライナーのアウトでの失策率
const BASE_DP := 0.44       ## 一塁走者あり・2アウト未満のゴロアウトが併殺になる割合

## 鋭い当たり
const SHARP_HIT := 0.66
const A_OF_RANGE := 0.13    ## 外野守備範囲 → 安打（減）（作業44で 0.10 から）
const SHARP_XBH := 0.35     ## 鋭い安打のうち長打の割合
const A_POW_XBH := 0.35
const A_SPEED_XBH := 0.15
const A_ARM_XBH := 0.10     ## 外野の肩 → 長打（減）
const TRIPLE_SHARE := 0.078  ## 長打のうち三塁打
const A_SPEED_TRIPLE := 0.55

## 走塁
const ADV_1_TO_3 := 0.28    ## 単打で一塁走者が三塁へ
const ADV_2_HOME := 0.62    ## 単打で二塁走者が生還
const ADV_1_HOME_ON_DOUBLE := 0.42
const A_SPEED_RUN := 0.55
const A_ARM_RUN := 0.30
const OUT_ON_BASES := 0.10  ## 進塁できなかった走者が次の塁を狙って刺される割合
const SAC_FLY_3RD := 0.72   ## 外野フライで三塁走者がタッチアップ生還（鋭い当たりのアウト）
const TAG_UP_WEAK := 0.45   ## 浅いフライでのタッチアップ
const GROUND_ADVANCE := 0.45  ## ゴロアウトで進塁（フォースでない走者）

## 盗塁
const STEAL_ATTEMPT := 0.055  ## 一塁走者（二塁が空き）が打席ごとに企図する確率（走力0のとき）
const A_SPEED_STEAL := 1.25
const STEAL_SUCCESS := 0.58
const A_SPEED_SB := 0.40
const A_ARM_SB := 0.35      ## 捕手の肩 → 盗塁成功（減）
const WILD_PITCH := 0.018   ## 走者ありの打席ごとの暴投・捕逸
const A_C_DEF_WP := 0.30    ## 捕手の守備力 → 暴投・捕逸（減）

## 送りバント（采配方針）
const BUNT_PITCHER := 0.85
const BUNT_HITTER := 0.55   ## 野手（打力が BUNT_MAX_VALUE より 1.0 低いとき）
const BUNT_MAX_VALUE := 0.7  ## これ以上の打力（batting_value）の打者はバントしない
const BUNT_SUCCESS := 0.80
const BUNT_HIT := 0.05

## 采配方針（SimTeam.tactics、-2〜+2）の効き方。配列は方針 -2, -1, 0, +1, +2 の順
const BUNT_TACTIC_HITTER := [0.0, 0.5, 1.0, 1.4, 1.8]    ## 野手の送りバントの頻度（倍率）
const BUNT_TACTIC_PITCHER := [0.5, 0.7, 0.85, 0.92, 0.97]  ## 投手が送りバントする確率
const BUNT_TACTIC_VALUE := 0.25  ## 1段階ごとに、バントさせる打者の打力の上限（BUNT_MAX_VALUE）をずらす
const STEAL_TACTIC_LOGIT := 0.5  ## 1段階ごとの盗塁企図率（ロジット）の上下
const RELIEF_TACTIC_PITCHES := 10  ## 継投：1段階ごとに先発を代える球数の目安を早める（+）/遅らせる（−）

## 疲労（段階1）：目安の球数を超えた 15球ごとに z 値を下げる
const FATIGUE_PER_15 := 0.45
## 継投（段階8）：先発を代える点数の目安、目安の球数への上乗せ（采配方針）
const STARTER_PULL_RUNS := 5
const STARTER_PULL_MARGIN := 5
const MAX_INNINGS := 12

## 打席結果ごとの球数の目安
const PITCHES := {"bb": 5.6, "k": 4.8, "hbp": 3.2, "hr": 3.3, "bip": 3.3, "bunt": 1.8}

## ゴロ・凡フライの捕球者の割合
const WEAK_GROUND_FIELDERS := [
	["投手", 0.06], ["一塁手", 0.13], ["二塁手", 0.26], ["三塁手", 0.22], ["遊撃手", 0.33],
]
const SHARP_FIELDERS := [
	["左翼手", 0.28], ["中堅手", 0.30], ["右翼手", 0.26],
	["三塁手", 0.05], ["遊撃手", 0.05], ["二塁手", 0.04], ["一塁手", 0.02],
]

var rng: RandomNumberGenerator
var day: int
var teams: Array[SimTeam] = []  ## [ビジター, ホーム]
var use_dh: bool

var _order: Array = [[], []]      ## [[SimPlayer or null, 守備位置], ...] ×9
var _bench: Array = [[], []]
var _bat_index := [0, 0]
var _fielders: Array = [{}, {}]   ## 守備位置 → SimPlayer（投手は _pitcher）
var _pitcher: Array = [null, null]
var _pitch_count := [0, 0]
var _starter: Array = [null, null]
var _pitchers_used: Array = [[], []]
var _used_ids: Array = [{}, {}]
var _must_change := [false, false]
var _entry_lead := [{}, {}]       ## 投手ID → 登板時のリード
var _entry_inning := [{}, {}]

var _bat_lines: Array = [{}, {}]
var _fld: Array = [{}, {}]        ## 守備の記録：選手ID → 守備位置 → {キー: 数}
var _pit_lines: Array = [{}, {}]
var _score := [0, 0]
var _line: Array = [[], []]

var _inning := 1
var _half := 0
var _outs := 0
var _virtual_outs := 0  ## 失策がなければ取れていたアウトを含む（自責点の判定用）
var _bases: Array = [null, null, null]  ## 走者 {p: SimPlayer, resp: SimPlayer, earned: bool}
var _lead_event := {}   ## 最後に勝ち越したときの {side, win, lose}
var _game_over := false
## 基準の確率（ロジット。set_env でその年のずれを足す）
var _base_bb := 0.0
var _base_k := 0.0
var _base_hr := 0.0
var _base_sharp := 0.0


func _init(away: SimTeam, home: SimTeam, game_day: int, dh: bool,
		random: RandomNumberGenerator) -> void:
	teams = [away, home]
	day = game_day
	use_dh = dh
	rng = random
	set_env({})


## その年の点の入りやすさ（RunEnv.for_year。基準の確率に足すロジットのずれ）
func set_env(env: Dictionary) -> void:
	_base_bb = _logit(BASE_BB) + float(env.get("bb", 0.0))
	_base_k = _logit(BASE_K) + float(env.get("k", 0.0))
	_base_hr = _logit(BASE_HR) + float(env.get("hr", 0.0))
	_base_sharp = _logit(BASE_SHARP) + float(env.get("sharp", 0.0))


## 試合を最後まで進め、結果（スコア・勝敗投手・個人成績）を返す
func play() -> Dictionary:
	for side in 2:
		var team: SimTeam = teams[side]
		_order[side] = team.lineup(use_dh).duplicate()
		_bench[side] = team.bench(use_dh).duplicate()
		for entry: Array in _order[side]:
			if entry[0] != null:
				_fielders[side][entry[1]] = entry[0]
				_used_ids[side][entry[0].id] = true
		var starter := team.pick_starter(day)
		_starter[side] = starter
		_enter_pitcher(side, starter)
		_pit_lines[side][starter.id]["gs"] = 1

	while not _game_over:
		_play_half(0)
		if _inning >= 9 and _score[1] > _score[0]:
			_line[1].append(-1)  # 裏の攻撃なし（×）
			break
		_play_half(1)
		if _inning >= 9 and _score[0] != _score[1]:
			break
		if _inning >= MAX_INNINGS:
			break
		_inning += 1

	return _finish()


# --- 攻撃 ---------------------------------------------------------------------------

func _play_half(batting: int) -> void:
	_half = batting
	var fielding := 1 - batting
	_outs = 0
	_virtual_outs = 0
	_bases = [null, null, null]
	_line[batting].append(0)
	_check_pitching_change(fielding, true)
	while _outs < 3:
		_check_pitching_change(fielding, false)
		_try_steal(batting, fielding)
		if _outs >= 3:
			break
		_maybe_wild_pitch(fielding)
		if _walk_off():
			_game_over = true
			return
		_plate_appearance(batting, fielding)
		if _walk_off():
			_game_over = true
			return


func _walk_off() -> bool:
	return _half == 1 and _inning >= 9 and _score[1] > _score[0]


func _next_batter(batting: int) -> SimPlayer:
	var entry: Array = _order[batting][_bat_index[batting]]
	_bat_index[batting] = (_bat_index[batting] + 1) % _order[batting].size()
	if entry[0] != null:
		return entry[0]
	# 投手の打順（DHなし）：リリーフや降板間際の先発には代打を出す
	var pitcher: SimPlayer = _pitcher[batting]
	if _should_pinch_hit(batting, pitcher):
		var ph: SimPlayer = _bench[batting].pop_front()
		_used_ids[batting][ph.id] = true
		_must_change[batting] = true
		_bat_line(batting, ph, "代打")
		return ph
	return pitcher


func _should_pinch_hit(batting: int, pitcher: SimPlayer) -> bool:
	if _bench[batting].is_empty() or _inning < 5:
		return false
	var lead: int = _score[batting] - _score[1 - batting]
	if pitcher != _starter[batting]:
		return _inning >= 6
	var near_limit: bool = _pitch_count[batting] >= pitcher.pitch_limit() - 15
	return (_inning >= 7 and lead <= 0) or (_inning >= 6 and near_limit) \
			or (lead < -3 and _inning >= 5)


func _plate_appearance(batting: int, fielding: int) -> void:
	var batter := _next_batter(batting)
	var pitcher: SimPlayer = _pitcher[fielding]
	var line := _bat_line(batting, batter)
	var pline: Dictionary = _pit_lines[fielding][pitcher.id]
	line["pa"] += 1
	pline["bf"] += 1

	if _should_bunt(batting, batter):
		_bunt(fielding, batter, line, pline)
		return

	var fat := _fatigue(fielding)
	var bb_p := _sig(_base_bb + A_EYE_BB * batter.eye - A_CTL_BB * (pitcher.bb9 - fat))
	var k_p := _sig(_base_k - A_MEET_K * batter.meet + A_K9_K * (pitcher.k9 - fat))
	var hr_p := _sig(_base_hr + A_POW_HR * batter.power
			+ A_TRAJ_HR * (batter.trajectory - 2.5) - A_HR9_HR * (pitcher.hr9 - fat))
	var r := rng.randf()
	if r < P_HBP:
		_count_pitches(fielding, "hbp")
		line["hbp"] += 1
		pline["hbp"] += 1
		_force_advance(batting, batter, true, true)
	elif r < P_HBP + bb_p:
		_count_pitches(fielding, "bb")
		line["bb"] += 1
		pline["bb"] += 1
		_force_advance(batting, batter, true, true)
	elif r < P_HBP + bb_p + k_p:
		_count_pitches(fielding, "k")
		line["ab"] += 1
		line["so"] += 1
		pline["so"] += 1
		_record_out(fielding, 1)
	elif r < P_HBP + bb_p + k_p + hr_p:
		_count_pitches(fielding, "hr")
		line["ab"] += 1
		line["h"] += 1
		line["hr"] += 1
		pline["h"] += 1
		pline["hr"] += 1
		var runners := 0
		for i in 3:
			if _bases[i] != null:
				_score_runner(batting, _bases[i], true, batter)
				runners += 1
		_bases = [null, null, null]
		_score_runner(batting, _runner(batter, fielding, true), true, batter)
	else:
		_count_pitches(fielding, "bip")
		line["ab"] += 1
		_ball_in_play(batting, fielding, batter, line, pline, fat)


## 段階1：目安の球数を超えたぶんだけ投手の z 値を下げる
func _fatigue(fielding: int) -> float:
	var p: SimPlayer = _pitcher[fielding]
	var over: int = _pitch_count[fielding] - p.pitch_limit()
	return maxf(over, 0) / 15.0 * FATIGUE_PER_15


## 段階4：打球の質（凡打球／鋭い当たり）
func _ball_in_play(batting: int, fielding: int, batter: SimPlayer, line: Dictionary,
		pline: Dictionary, fat: float) -> void:
	var pitcher: SimPlayer = _pitcher[fielding]
	var sharp_p := _sig(_base_sharp + A_MEET_SHARP * batter.meet
			+ A_POW_SHARP * batter.power - A_OVR_SHARP * (pitcher.overall - fat))
	if rng.randf() < sharp_p:
		_sharp_ball(batting, fielding, batter, line, pline)
	else:
		_weak_ball(batting, fielding, batter, line, pline)


## 段階5：凡打球。内野の守備範囲でアウトか内野安打か、アウトなら失策の判定
func _weak_ball(batting: int, fielding: int, batter: SimPlayer, line: Dictionary,
		pline: Dictionary) -> void:
	if rng.randf() >= WEAK_GROUNDER:
		# 凡フライ・ポップ
		if rng.randf() < WEAK_FLY_OUT:
			if rng.randf() < FLY_ERROR:
				_reach_on_error(batting, fielding, batter)
				return
			_record_out(fielding, 1)
			if _outs < 3 and _bases[2] != null and rng.randf() < _speed_p(TAG_UP_WEAK, _bases[2].p):
				var runner: Dictionary = _bases[2]
				_bases[2] = null
				line["sf"] += 1
				line["ab"] -= 1
				_score_runner(batting, runner, true, batter)
		else:
			_single(batting, fielding, batter, line, pline, "中堅手", false)
		return

	var pos := _pick(WEAK_GROUND_FIELDERS)
	var fielder := _fielder(fielding, pos)
	var is_pitcher: bool = fielder == _pitcher[fielding]
	var def: float = 0.0 if is_pitcher else fielder.defense_at(SimTeam.field_key(pos))
	var out_p := _sig(_logit(GROUNDER_OUT) + A_IF_RANGE * def - A_SPEED_IF * batter.speed)
	_fld_add(fielding, fielder, pos, "gb")
	_fld_exp(fielding, fielder, pos, "gbd", out_p - _sig(_logit(GROUNDER_OUT) - A_SPEED_IF * batter.speed))
	if rng.randf() >= out_p:
		_single(batting, fielding, batter, line, pline, pos, true)
		return
	_fld_add(fielding, fielder, pos, "gbo")
	var err_p := _sig(_logit(BASE_ERROR) - A_DEF_ERROR * def)
	_fld_exp(fielding, fielder, pos, "gbed", err_p - BASE_ERROR)
	if rng.randf() < err_p:
		_fld_add(fielding, fielder, pos, "gbe")
		_reach_on_error(batting, fielding, batter)
		return
	# 併殺
	if _bases[0] != null and _outs < 2:
		var dp_p := _sig(_logit(BASE_DP) - 0.35 * batter.speed - 0.2 * _bases[0].p.speed)
		if rng.randf() < dp_p:
			line["gdp"] += 1
			_bases[0] = null
			_record_out(fielding, 2)
			if _outs < 3:
				_advance_non_forced(batting, false, null)
			return
	_record_out(fielding, 1)
	if _outs < 3:
		_ground_out_advance(batting, batter)


## 段階6：鋭い当たり。外野の守備範囲で安打を減らし、肩で長打・進塁を抑える
func _sharp_ball(batting: int, fielding: int, batter: SimPlayer, line: Dictionary,
		pline: Dictionary) -> void:
	var pos := _pick(SHARP_FIELDERS)
	var fielder := _fielder(fielding, pos)
	var key := SimTeam.field_key(pos)
	var def := fielder.range_at(pos)
	var infield := key != "外野手"
	var hit_p := _sig(_logit(SHARP_HIT) - A_OF_RANGE * def - (0.9 if infield else 0.0))
	_fld_add(fielding, fielder, pos, "ln")
	_fld_exp(fielding, fielder, pos, "lnd", _sig(_logit(SHARP_HIT) - (0.9 if infield else 0.0)) - hit_p)
	if rng.randf() >= hit_p:
		# ライナー・外野フライのアウト
		_fld_add(fielding, fielder, pos, "lno")
		var err_p := _sig(_logit(FLY_ERROR) - A_DEF_ERROR * def)
		_fld_exp(fielding, fielder, pos, "lned", err_p - FLY_ERROR)
		if rng.randf() < err_p:
			_fld_add(fielding, fielder, pos, "lne")
			_reach_on_error(batting, fielding, batter)
			return
		_record_out(fielding, 1)
		if _outs < 3 and not infield:
			if _bases[2] != null:
				_fld_add(fielding, fielder, pos, "ah")
				var tag_p := _speed_p(SAC_FLY_3RD, _bases[2].p, fielder.arm_at(key))
				_fld_exp(fielding, fielder, pos, "ahhd", _speed_p(SAC_FLY_3RD, _bases[2].p) - tag_p)
				if rng.randf() < tag_p:
					var runner: Dictionary = _bases[2]
					_bases[2] = null
					line["sf"] += 1
					line["ab"] -= 1
					_score_runner(batting, runner, true, batter)
				else:
					_fld_add(fielding, fielder, pos, "ahh")
			if _bases[1] != null and _bases[2] == null and rng.randf() < 0.35:
				_bases[2] = _bases[1]
				_bases[1] = null
		return
	if infield:
		_single(batting, fielding, batter, line, pline, pos, false)
		return
	var arm := fielder.arm_at(key)
	var xbh_base := _logit(SHARP_XBH) + A_POW_XBH * batter.power + A_SPEED_XBH * batter.speed
	var xbh_p := _sig(xbh_base - A_ARM_XBH * arm - A_OF_RANGE * def)
	_fld_add(fielding, fielder, pos, "xh")
	# 長打を単打に止めた見込み：範囲の分（xsrd）と肩の分（xsad）に分ける
	var xbh_range := _sig(xbh_base - A_OF_RANGE * def)
	_fld_exp(fielding, fielder, pos, "xsrd", _sig(xbh_base) - xbh_range)
	_fld_exp(fielding, fielder, pos, "xsad", xbh_range - xbh_p)
	if rng.randf() >= xbh_p:
		_fld_add(fielding, fielder, pos, "xs")
		_single(batting, fielding, batter, line, pline, pos, false)
		return
	line["h"] += 1
	pline["h"] += 1
	if rng.randf() < _sig(_logit(TRIPLE_SHARE) + A_SPEED_TRIPLE * batter.speed):
		line["t"] += 1
		for i in 3:
			if _bases[i] != null:
				_score_runner(batting, _bases[i], true, batter)
		_bases = [null, null, null]
		_bases[2] = _runner(batter, fielding, true)
		return
	line["d"] += 1
	# 二塁打：二・三塁の走者は生還、一塁走者は走力と肩で生還か三塁止まり
	var first: Variant = _bases[0]
	for i in [2, 1]:
		if _bases[i] != null:
			_score_runner(batting, _bases[i], true, batter)
	_bases = [null, null, null]
	if first != null:
		_fld_add(fielding, fielder, pos, "ah")
		_arm_exp(fielding, fielder, pos, ADV_1_HOME_ON_DOUBLE, first.p, arm, "ahhd", "ahkd")
		if rng.randf() < _speed_p(ADV_1_HOME_ON_DOUBLE, first.p, arm):
			_score_runner(batting, first, true, batter)
		elif _outs < 2 and rng.randf() < _thrown_out_p(arm):
			_fld_add(fielding, fielder, pos, "ahk")
			_record_out(fielding, 1)  # 本塁で憤死
		else:
			_fld_add(fielding, fielder, pos, "ahh")
			_bases[2] = first
	_bases[1] = _runner(batter, fielding, true)


## 単打と段階7の走者進塁（走力と外野の肩で、一塁→三塁・二塁→本塁を判定）
func _single(batting: int, fielding: int, batter: SimPlayer, line: Dictionary, pline: Dictionary,
		pos: String, infield_hit: bool) -> void:
	line["h"] += 1
	pline["h"] += 1
	var fielder := _fielder(fielding, pos)
	var arm: float = fielder.arm_at(SimTeam.field_key(pos)) if fielder != _pitcher[fielding] else 0.0
	var outfield := SimTeam.field_key(pos) == "外野手"
	if _bases[2] != null:
		_score_runner(batting, _bases[2], true, batter)
		_bases[2] = null
	if _bases[1] != null:
		var runner: Dictionary = _bases[1]
		_bases[1] = null
		if outfield:
			_fld_add(fielding, fielder, pos, "ah")
			_arm_exp(fielding, fielder, pos, ADV_2_HOME, runner.p, arm, "ahhd", "ahkd")
		if outfield and rng.randf() < _speed_p(ADV_2_HOME, runner.p, arm):
			_score_runner(batting, runner, true, batter)
		elif outfield and _outs < 2 and rng.randf() < _thrown_out_p(arm):
			_fld_add(fielding, fielder, pos, "ahk")
			_record_out(fielding, 1)  # 本塁で憤死
		else:
			if outfield:
				_fld_add(fielding, fielder, pos, "ahh")
			_bases[2] = runner
	if _bases[0] != null:
		var runner: Dictionary = _bases[0]
		_bases[0] = null
		var chance := outfield and _bases[2] == null and not infield_hit
		if chance:
			_fld_add(fielding, fielder, pos, "a3")
			_arm_exp(fielding, fielder, pos, ADV_1_TO_3, runner.p, arm, "a3hd", "a3kd")
		if chance and rng.randf() < _speed_p(ADV_1_TO_3, runner.p, arm):
			_bases[2] = runner
		elif chance and _outs < 2 and rng.randf() < _thrown_out_p(arm):
			_fld_add(fielding, fielder, pos, "a3k")
			_record_out(fielding, 1)  # 三塁で憤死
		else:
			if chance:
				_fld_add(fielding, fielder, pos, "a3h")
			_bases[1] = runner
	_bases[0] = _runner(batter, fielding, true)


func _reach_on_error(batting: int, fielding: int, batter: SimPlayer) -> void:
	_virtual_outs += 1
	_bat_line(batting, batter)["roe"] += 1
	for i in [2, 1, 0]:
		if _bases[i] == null:
			continue
		if i == 2:
			_score_runner(batting, _bases[2], false, null)
		else:
			_bases[i + 1] = _bases[i]
		_bases[i] = null
	_bases[0] = _runner(batter, fielding, false)


## 四死球など：押し出しのみ進塁
func _force_advance(batting: int, batter: SimPlayer, earned: bool, rbi: bool) -> void:
	var fielding := 1 - batting
	if _bases[0] != null:
		if _bases[1] != null:
			if _bases[2] != null:
				_score_runner(batting, _bases[2], rbi, batter)
			_bases[2] = _bases[1]
		_bases[1] = _bases[0]
	_bases[0] = _runner(batter, fielding, earned)


## ゴロアウト（打者がアウト）：フォースの走者は進み、そうでない走者は一定確率で進塁
func _ground_out_advance(batting: int, batter: SimPlayer) -> void:
	var forced_1 := _bases[0] != null
	var forced_2 := forced_1 and _bases[1] != null
	var forced_3 := forced_2 and _bases[2] != null
	if _bases[2] != null and (forced_3 or rng.randf() < _speed_p(GROUND_ADVANCE, _bases[2].p)):
		_score_runner(batting, _bases[2], true, batter)
		_bases[2] = null
	if _bases[1] != null and _bases[2] == null and (forced_2 or rng.randf() < GROUND_ADVANCE):
		_bases[2] = _bases[1]
		_bases[1] = null
	if forced_1 and _bases[1] == null:
		_bases[1] = _bases[0]
		_bases[0] = null


## 併殺の後：残った二・三塁の走者（打点なし）
func _advance_non_forced(batting: int, rbi: bool, batter: SimPlayer) -> void:
	if _bases[2] != null and rng.randf() < 0.5:
		_score_runner(batting, _bases[2], rbi, batter)
		_bases[2] = null
	if _bases[1] != null and _bases[2] == null and rng.randf() < 0.5:
		_bases[2] = _bases[1]
		_bases[1] = null


# --- 采配（送りバント・盗塁）-----------------------------------------------------------

func _should_bunt(batting: int, batter: SimPlayer) -> bool:
	if _outs != 0 or (_bases[0] == null and _bases[1] == null) or _bases[2] != null:
		return false
	var lead: int = _score[batting] - _score[1 - batting]
	if absi(lead) > 3:
		return false
	var level := _tactic(batting, "bunt")
	var p := 0.0
	if batter == _pitcher[batting]:
		p = BUNT_TACTIC_PITCHER[level + 2]
	else:
		# 中軸以外は、打力が低いほど・終盤の接戦ほど送りバントをしやすい（采配方針で頻度と対象を変える）
		var value := batter.batting_value()
		var max_value := BUNT_MAX_VALUE + BUNT_TACTIC_VALUE * level
		if value >= max_value:
			return false
		p = BUNT_HITTER * clampf((max_value - value) / 1.0, 0.0, 1.0) * BUNT_TACTIC_HITTER[level + 2]
		if _inning >= 7 and absi(lead) <= 1:
			p *= 1.6
	return rng.randf() < p


func _bunt(fielding: int, batter: SimPlayer, line: Dictionary, pline: Dictionary) -> void:
	_count_pitches(fielding, "bunt")
	var r := rng.randf()
	if r < BUNT_HIT:
		line["ab"] += 1
		line["h"] += 1
		pline["h"] += 1
		if _bases[1] != null:
			_bases[2] = _bases[1]
		_bases[1] = _bases[0]
		_bases[0] = _runner(batter, fielding, true)
		return
	if r < BUNT_HIT + BUNT_SUCCESS:
		line["sh"] += 1
		if _bases[1] != null:
			_bases[2] = _bases[1]
		_bases[1] = _bases[0]
		_bases[0] = null
		_record_out(fielding, 1)
		return
	# 失敗：先の走者がアウトになり打者は一塁へ
	line["ab"] += 1
	if _bases[1] != null:
		_bases[1] = _bases[0] if _bases[0] != null else null
	else:
		_bases[0] = null
	_bases[0] = _runner(batter, fielding, true)
	_record_out(fielding, 1)


## 段階7：盗塁（一塁走者の二盗、まれに三盗）。企図率は走力、成功率は走力と捕手の肩
func _try_steal(batting: int, fielding: int) -> void:
	var lead: int = _score[batting] - _score[fielding]
	if absi(lead) >= 5:
		return
	var base := -1
	if _bases[0] != null and _bases[1] == null:
		base = 0
	elif _bases[1] != null and _bases[2] == null and _outs < 2:
		base = 1
	if base < 0:
		return
	var runner: Dictionary = _bases[base]
	var runner_p: SimPlayer = runner.p
	var attempt := _sig(_logit(STEAL_ATTEMPT) + A_SPEED_STEAL * runner_p.speed
			+ STEAL_TACTIC_LOGIT * _tactic(batting, "steal"))
	if base == 1:
		attempt *= 0.12
	if rng.randf() >= attempt:
		return
	var catcher := _fielder(fielding, "捕手")
	var success_base := _logit(STEAL_SUCCESS) + A_SPEED_SB * runner_p.speed
	var success := _sig(success_base - A_ARM_SB * catcher.arm_at("捕手"))
	var line := _bat_line(batting, runner_p)
	_bases[base] = null
	_fld_add(fielding, catcher, "捕手", "sba")
	_fld_exp(fielding, catcher, "捕手", "csd", _sig(success_base) - success)
	if rng.randf() < success:
		line["sb"] += 1
		_bases[base + 1] = runner
	else:
		_fld_add(fielding, catcher, "捕手", "cs")
		line["cs"] += 1
		_record_out(fielding, 1)


func _maybe_wild_pitch(fielding: int) -> void:
	if _bases[0] == null and _bases[1] == null and _bases[2] == null:
		return
	# 暴投・捕逸：捕手の守備力で上下（守備の記録は捕手に付ける）
	var catcher := _fielder(fielding, "捕手")
	var c_def: float = 0.0 if catcher == _pitcher[fielding] else catcher.defense_at("捕手")
	_fld_add(fielding, catcher, "捕手", "wpo")
	var wp_p := _sig(_logit(WILD_PITCH) - A_C_DEF_WP * c_def)
	_fld_exp(fielding, catcher, "捕手", "wpd", wp_p - WILD_PITCH)
	if rng.randf() >= wp_p:
		return
	_fld_add(fielding, catcher, "捕手", "wp")
	var batting := 1 - fielding
	if _bases[2] != null:
		_score_runner(batting, _bases[2], false, null)
	_bases[2] = _bases[1]
	_bases[1] = _bases[0]
	_bases[0] = null


# --- 守備側（継投）--------------------------------------------------------------------

## 段階8：継投判断
func _check_pitching_change(fielding: int, inning_start: bool) -> void:
	var p: SimPlayer = _pitcher[fielding]
	var pc: int = _pitch_count[fielding]
	var line: Dictionary = _pit_lines[fielding][p.id]
	var lead: int = _score[fielding] - _score[1 - fielding]
	var change: bool = _must_change[fielding]
	if not change and p == _starter[fielding]:
		# 采配方針の継投：+ は早めに・− は先発を引っ張る
		var relief := _tactic(fielding, "relief")
		var pull_runs := maxi(STARTER_PULL_RUNS - relief, 2)
		var margin := STARTER_PULL_MARGIN - RELIEF_TACTIC_PITCHES * relief \
				+ (10 if lead >= 1 and _inning >= 7 and line["r"] <= 2 else 0)
		change = pc >= p.pitch_limit() + margin \
				or (line["r"] >= pull_runs and pc >= 50) \
				or line["r"] >= pull_runs + 3
		# 終盤の勝ちパターン：7回以降の僅差リードは、球数が近ければ継投する
		if not change and inning_start and _inning >= 8 and lead in [1, 2, 3] \
				and pc >= p.pitch_limit() - 15 - RELIEF_TACTIC_PITCHES * relief:
			change = true
	elif not change:
		change = pc >= p.pitch_limit()
		if not change and inning_start and line["outs"] >= 3:
			var closer_like := teams[fielding].bullpen.find(p) in [0, 1, 2]
			change = closer_like or (_inning >= 7 and lead in [1, 2, 3])
	if not change:
		return
	var next := _choose_reliever(fielding, lead)
	if next == null:
		_must_change[fielding] = false
		return
	_enter_pitcher(fielding, next)


func _choose_reliever(fielding: int, lead: int) -> SimPlayer:
	var team: SimTeam = teams[fielding]
	var available: Array[SimPlayer] = []
	for p in team.available_relievers(day):
		if not _used_ids[fielding].has(p.id):
			available.append(p)
	if available.is_empty():
		for p in team.bullpen:
			if not _used_ids[fielding].has(p.id):
				available.append(p)
	if available.is_empty():
		return null
	var close := lead >= 1 and lead <= 3
	var tied_late := lead == 0 and _inning >= 8
	var wanted := -1
	if (close and _inning >= 9) or (tied_late and _inning >= 9 and fielding == 1):
		wanted = 0
	elif close and _inning == 8 or tied_late:
		wanted = 1
	elif close and _inning == 7:
		wanted = 2
	if wanted >= 0:
		for i in range(wanted, 3):
			if i < team.bullpen.size() and team.bullpen[i] in available:
				return team.bullpen[i]
	# 勝ちパターン以外：接戦なら残りの上位から、大差なら下位から
	var others := available.filter(func(p: SimPlayer) -> bool: return team.bullpen.find(p) >= 3)
	if others.is_empty():
		others = available
	if absi(lead) >= 4:
		return others[-1]
	return others[0]


func _enter_pitcher(side: int, p: SimPlayer) -> void:
	_pitcher[side] = p
	_pitch_count[side] = 0
	_must_change[side] = false
	_pitchers_used[side].append(p)
	_used_ids[side][p.id] = true
	_entry_lead[side][p.id] = _score[side] - _score[1 - side]
	_entry_inning[side][p.id] = _inning
	_pit_lines[side][p.id] = {
		"id": p.id, "outs": 0, "bf": 0, "h": 0, "hr": 0, "bb": 0, "hbp": 0, "so": 0,
		"r": 0, "er": 0, "np": 0, "gs": 0, "w": 0, "l": 0, "sv": 0, "hld": 0,
	}


func _count_pitches(fielding: int, kind: String) -> void:
	var n := int(round(PITCHES[kind] + rng.randf_range(-1.2, 1.2)))
	n = maxi(n, 1)
	_pitch_count[fielding] += n
	_pit_lines[fielding][_pitcher[fielding].id]["np"] += n


func _record_out(fielding: int, n: int) -> void:
	var add := mini(n, 3 - _outs)
	_outs += add
	_virtual_outs += add
	_pit_lines[fielding][_pitcher[fielding].id]["outs"] += add


## 守備の記録を1つ数える（投手・指名打者は数えない）
func _fld_add(fielding: int, p: SimPlayer, pos: String, key: String, n := 1) -> void:
	if p == null or p == _pitcher[fielding] or pos == "投手" or pos == "指名打者":
		return
	var d: Dictionary = _fld[fielding].get_or_add(p.id, {}).get_or_add(pos, {})
	d[key] = int(d.get(key, 0)) + n


## 守備の見込みの記録：平均的な野手と比べた確率の差 delta × 1000 を key に足す
func _fld_exp(fielding: int, p: SimPlayer, pos: String, key: String, delta: float) -> void:
	_fld_add(fielding, p, pos, key, roundi(delta * 1000.0))


## 外野からの返球の見込み：走者が次の塁を狙う機会で、止めた（hold_key）・刺した（kill_key）見込みを肩 z = 0 の野手と比べて足す
func _arm_exp(fielding: int, p: SimPlayer, pos: String, base: float, runner: SimPlayer, arm: float,
		hold_key: String, kill_key: String) -> void:
	var can_kill := _outs < 2
	var s1 := _speed_p(base, runner, arm)
	var s0 := _speed_p(base, runner)
	var k1 := _thrown_out_p(arm) if can_kill else 0.0
	var k0 := _thrown_out_p(0.0) if can_kill else 0.0
	_fld_exp(fielding, p, pos, hold_key, (1.0 - s1) * (1.0 - k1) - (1.0 - s0) * (1.0 - k0))
	_fld_exp(fielding, p, pos, kill_key, (1.0 - s1) * k1 - (1.0 - s0) * k0)


func _fielder(fielding: int, pos: String) -> SimPlayer:
	if pos == "投手":
		return _pitcher[fielding]
	var p: Variant = _fielders[fielding].get(pos)
	return p if p != null else _pitcher[fielding]


# --- 得点・記録 -----------------------------------------------------------------------

func _runner(p: SimPlayer, fielding: int, earned: bool) -> Dictionary:
	return {"p": p, "resp": _pitcher[fielding], "earned": earned}


func _score_runner(batting: int, runner: Dictionary, rbi: bool, batter: SimPlayer) -> void:
	var fielding := 1 - batting
	var before: int = _score[batting] - _score[fielding]
	_score[batting] += 1
	_line[batting][-1] += 1
	_bat_line(batting, runner.p)["r"] += 1
	if rbi and batter != null:
		_bat_line(batting, batter)["rbi"] += 1
	var resp: SimPlayer = runner.resp
	var rline: Dictionary = _pit_lines[fielding][resp.id]
	rline["r"] += 1
	if runner.earned and _virtual_outs < 3:
		rline["er"] += 1
	if before == 0:
		# 勝ち越し：勝利投手の候補は攻撃側のその時点の投手、敗戦投手はこの走者の責任投手
		_lead_event = {"side": batting, "win": _pitcher[batting], "lose": resp}


func _bat_line(side: int, p: SimPlayer, pos: String = "") -> Dictionary:
	var lines: Dictionary = _bat_lines[side]
	if not lines.has(p.id):
		var slot := pos
		if slot.is_empty():
			slot = "投手" if p == _pitcher[side] else ""
			for entry: Array in _order[side]:
				if entry[0] == p:
					slot = entry[1]
		lines[p.id] = {
			"id": p.id, "pos": slot, "order": lines.size(),
			"pa": 0, "ab": 0, "h": 0, "d": 0, "t": 0, "hr": 0, "rbi": 0, "r": 0,
			"bb": 0, "hbp": 0, "so": 0, "sb": 0, "cs": 0, "sh": 0, "sf": 0, "gdp": 0, "roe": 0,
		}
	return lines[p.id]


func _finish() -> Dictionary:
	var result := {
		"away_score": _score[0], "home_score": _score[1],
		"innings": _inning, "line": _line,
		"win": "", "lose": "", "save": "",
		"batting": [_bat_lines[0].values(), _bat_lines[1].values()],
		"pitching": [[], []],
	}
	var winner := -1
	if _score[0] != _score[1]:
		winner = 0 if _score[0] > _score[1] else 1
	if winner >= 0:
		var win_p: SimPlayer = _lead_event["win"]
		var lose_p: SimPlayer = _lead_event["lose"]
		# 先発は5回（15アウト）以上投げないと勝利投手にならない
		if win_p == _starter[winner] and _pit_lines[winner][win_p.id]["outs"] < 15:
			var best: SimPlayer = null
			for p: SimPlayer in _pitchers_used[winner]:
				if p == win_p:
					continue
				if best == null or _pit_lines[winner][p.id]["outs"] > _pit_lines[winner][best.id]["outs"]:
					best = p
			if best != null:
				win_p = best
		_pit_lines[winner][win_p.id]["w"] = 1
		_pit_lines[1 - winner][lose_p.id]["l"] = 1
		result["win"] = win_p.id
		result["lose"] = lose_p.id
		var last: SimPlayer = _pitchers_used[winner][-1]
		var last_line: Dictionary = _pit_lines[winner][last.id]
		var entry_lead: int = _entry_lead[winner][last.id]
		if last != win_p and last != _starter[winner] \
				and ((entry_lead in [1, 2, 3] and last_line["outs"] >= 3) or last_line["outs"] >= 9):
			last_line["sv"] = 1
			result["save"] = last.id
		# ホールド：勝ちパターンの場面で登板し、リードを保って降板した救援投手
		for p: SimPlayer in _pitchers_used[winner]:
			var pl: Dictionary = _pit_lines[winner][p.id]
			if p == _starter[winner] or p == last or pl["w"] == 1 or pl["outs"] == 0:
				continue
			if _entry_lead[winner][p.id] in [1, 2, 3]:
				pl["hld"] = 1

	for side in 2:
		var team: SimTeam = teams[side]
		var outs := 0
		for p: SimPlayer in _pitchers_used[side]:
			var pl: Dictionary = _pit_lines[side][p.id]
			result["pitching"][side].append(pl)
			outs += int(pl["outs"])
			team.record_outing(p, day, pl["np"], p == _starter[side])
		# 守備のアウト数（守備イニング×3）。スタメンの野手は最後まで守る
		for pos: String in _fielders[side]:
			_fld_add(side, _fielders[side][pos], pos, "outs", outs)
	result["fielding"] = _fld
	return result


# --- 確率の道具 ------------------------------------------------------------------------

## side の球団の采配方針（-2〜+2）
func _tactic(side: int, key: String) -> int:
	return clampi(int(teams[side].tactics.get(key, 0)), SimTeam.TACTIC_MIN, SimTeam.TACTIC_MAX)


## 走者が次の塁を狙って成功する確率（走力と外野の肩で基準値を上下させる）
func _speed_p(base: float, runner: SimPlayer, arm: float = 0.0) -> float:
	return _sig(_logit(base) + A_SPEED_RUN * runner.speed - A_ARM_RUN * arm)


## 次の塁を狙えなかった走者が、狙って刺される確率（外野の肩が強いほど高い）
func _thrown_out_p(arm: float) -> float:
	return _sig(_logit(OUT_ON_BASES) + A_ARM_RUN * arm)


func _pick(table: Array) -> String:
	var r := rng.randf()
	for entry: Array in table:
		r -= entry[1]
		if r < 0.0:
			return entry[0]
	return table[-1][0]


static func _logit(p: float) -> float:
	return log(p / (1.0 - p))


static func _sig(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))
