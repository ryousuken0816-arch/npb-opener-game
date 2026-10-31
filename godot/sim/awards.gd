class_name Awards
extends RefCounted
## シーズン終了時の表彰（オフの「シーズン終了・表彰」の段階）。ゲーム内の今季の成績（Season）から決める。
##
## - 各リーグ：MVP・新人王・ベストナイン（パはDHあり）・ゴールデングラブ・打撃/投手のタイトル
## - 両リーグから1人：沢村賞（7つの基準のうち満たした数が多い投手。3つ未満なら該当者なし）
## - 規定打席＝チームの試合数×3.1、規定投球回＝チームの試合数×1.0（実際のルール）
## - タイトルは同じ値なら複数人（史実でも同点で分け合う）
## - 選手の価値（MVP・ベストナイン）は wOBA の得点換算（リーグ平均との差）＋守備位置の補正＋代替水準、
##   投手は防御率と FIP の平均でリーグ平均と比べた失点の少なさ＋代替水準。係数は下の定数
## - ゴールデングラブは守備成績が無いので、その位置の守備力（能力値）と出場試合で決める
##
## オートロードは参照しない（選手データ・新人の資格は GameState から Callable で渡す）

const QUALIFY_PA_PER_GAME := 3.1
const QUALIFY_OUTS_PER_GAME := 3  ## 1試合につき1投球回
## ベストナイン・GGの候補：その位置の出場がチームの試合数のこの割合以上（いなければ出場の多い順に緩める）
const POSITION_GAMES_SHARE := 0.4
## 最高勝率の資格（13勝以上）
const WIN_PCT_MIN_WINS := 13
## 新人王：入団から5年以内、前年までの1軍が 60打席以内・30投球回（90アウト）以内、外国人は除く
const ROOKIE_YEARS := 5
const ROOKIE_MAX_PA := 60
const ROOKIE_MAX_OUTS := 90
## 新人王の候補として優先する今季の出場（打席・アウト）
const ROOKIE_MIN_PA := 100
const ROOKIE_MIN_OUTS := 90

## wOBA の重み（NPB の近年の値に近いもの）と得点への換算
const W_BB := 0.69
const W_HBP := 0.72
const W_1B := 0.89
const W_2B := 1.27
const W_3B := 1.62
const W_HR := 2.10
const WOBA_SCALE := 1.2
## 守備位置の補正（600打席あたりの得点）
const POS_ADJ := {"捕手": 12.0, "遊撃手": 7.0, "二塁手": 3.0, "三塁手": 2.0, "中堅手": 2.5,
	"左翼手": -7.0, "右翼手": -7.0, "一塁手": -12.0, "指名打者": -17.0}
## 代替水準（600打席・投手は9回あたりの得点）
const REPLACEMENT_BAT := 20.0
const REPLACEMENT_PIT_PER9 := 1.0
## 救援投手の価値の倍率（1イニングの重み。セーブ・ホールドの場面）
const RELIEF_LEVERAGE := 1.6
## MVP：優勝球団の選手に足す得点（2位はその半分）
const MVP_CHAMPION_BONUS := 12.0

## 沢村賞の基準
const SAWAMURA := {"w": 15, "so": 150, "cg": 10, "era": 2.50, "outs": 600, "g": 25, "pct": 0.600}
const SAWAMURA_MIN_MET := 3

## ベストナイン・GGの位置（外野は3人）
const BEST_NINE_POS := ["投手", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手", "外野手", "外野手", "指名打者"]
const GOLD_GLOVE_POS := ["投手", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手", "外野手", "外野手"]

## タイトル：[キー, 名前, 打撃/投手, 規定が要るか, 小さいほど良いか]
const TITLES := [
	["avg", "首位打者", "b", true, false],
	["hr", "本塁打王", "b", false, false],
	["rbi", "打点王", "b", false, false],
	["sb", "盗塁王", "b", false, false],
	["obp", "最高出塁率", "b", true, false],
	["h", "最多安打", "b", false, false],
	["era", "最優秀防御率", "p", true, true],
	["w", "最多勝", "p", false, false],
	["so", "最多奪三振", "p", false, false],
	["sv", "最多セーブ", "p", false, false],
	["hp", "最優秀中継ぎ", "p", false, false],
	["pct", "最高勝率", "p", false, false],
]

## 賞の表示名（選手の受賞歴に使う）
const AWARD_NAMES := {"mvp": "MVP", "rookie": "新人王", "best_nine": "ベストナイン", "gold_glove": "ゴールデングラブ賞",
	"sawamura": "沢村賞"}

var _season: Season
var _player_of: Callable
var _team_games := {}
var _lg_woba := {}
var _lg_runs9 := {}


## season: 終わったペナント、player_of: 選手ID → 能力値データ（GameData.player）、
## is_rookie: 選手ID → 新人王の資格があるか（GameState が入団年・前年までの出場・外国人で判定）
## 戻り値は {year, leagues: {C/P: {mvp, rookie, best_nine, gold_glove, titles}}, sawamura}。
## 受賞者は {id, name, team, text}（text は成績の要約）。いなければ null
static func compute(season: Season, player_of: Callable, is_rookie: Callable) -> Dictionary:
	var a := Awards.new()
	a._season = season
	a._player_of = player_of
	return a._compute(is_rookie)


func _compute(is_rookie: Callable) -> Dictionary:
	for team: String in _season.records:
		var rec: Dictionary = _season.records[team]
		_team_games[team] = int(rec["w"]) + int(rec["l"]) + int(rec["d"])
	var result := {"year": _season.year, "leagues": {}, "sawamura": null}
	for lg: String in ["C", "P"]:
		_league_baselines(lg)
		var champ := _league_order(lg)
		result["leagues"][lg] = {
			"mvp": _mvp(lg, champ),
			"rookie": _rookie(lg, is_rookie),
			"best_nine": _best_nine(lg),
			"gold_glove": _gold_glove(lg),
			"titles": _titles(lg),
		}
	result["sawamura"] = _sawamura()
	return result


# --- 基準値 -------------------------------------------------------------------------------

func _league_baselines(lg: String) -> void:
	var num := 0.0
	var den := 0.0
	for id: String in _season.batting:
		if _league(id) != lg:
			continue
		var b: Dictionary = _season.batting[id]
		num += _woba_num(b)
		den += _woba_den(b)
	_lg_woba[lg] = num / den if den > 0.0 else 0.320
	var er := 0.0
	var outs := 0.0
	for id: String in _season.pitching:
		if _league(id) != lg:
			continue
		er += float(_season.pitching[id].get("er", 0))
		outs += float(_season.pitching[id].get("outs", 0))
	_lg_runs9[lg] = er * 27.0 / outs if outs > 0.0 else 3.8


## リーグの順位（球団 → 順位）
func _league_order(lg: String) -> Dictionary:
	var rows: Array = []
	for team: String in _season.records:
		if _season.leagues.get(team, "") == lg:
			var rec: Dictionary = _season.records[team]
			var dec := int(rec["w"]) + int(rec["l"])
			rows.append([team, float(rec["w"]) / dec if dec > 0 else 0.0])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	var order := {}
	for i in rows.size():
		order[rows[i][0]] = i + 1
	return order


func _league(id: String) -> String:
	var team: String = _season.players.get(id, {}).get("team", "")
	return _season.leagues.get(team, "")


func _team(id: String) -> String:
	return _season.players.get(id, {}).get("team", "")


func _games_of_team(id: String) -> int:
	return int(_team_games.get(_team(id), 143))


# --- 成績の計算 -------------------------------------------------------------------------

static func _woba_num(b: Dictionary) -> float:
	var h := int(b.get("h", 0))
	var d := int(b.get("d", 0))
	var t := int(b.get("t", 0))
	var hr := int(b.get("hr", 0))
	return W_BB * b.get("bb", 0) + W_HBP * b.get("hbp", 0) + W_1B * (h - d - t - hr) + W_2B * d + W_3B * t + W_HR * hr


static func _woba_den(b: Dictionary) -> float:
	return float(b.get("ab", 0) + b.get("bb", 0) + b.get("hbp", 0) + b.get("sf", 0))


static func obp(b: Dictionary) -> float:
	var den: int = b.get("ab", 0) + b.get("bb", 0) + b.get("hbp", 0) + b.get("sf", 0)
	return float(b.get("h", 0) + b.get("bb", 0) + b.get("hbp", 0)) / den if den > 0 else 0.0


static func slg(b: Dictionary) -> float:
	var ab: int = b.get("ab", 0)
	if ab <= 0:
		return 0.0
	var tb: int = b.get("h", 0) + b.get("d", 0) + 2 * b.get("t", 0) + 3 * b.get("hr", 0)
	return float(tb) / ab


static func win_pct(p: Dictionary) -> float:
	var dec: int = p.get("w", 0) + p.get("l", 0)
	return float(p.get("w", 0)) / dec if dec > 0 else 0.0


## 投手の FIP（定数はリーグの防御率に合わせる代わりに 3.1 で固定。比べるだけなので十分）
static func fip(p: Dictionary) -> float:
	var outs: int = p.get("outs", 0)
	if outs <= 0:
		return 9.99
	var ip := outs / 3.0
	return (13.0 * p.get("hr", 0) + 3.0 * (p.get("bb", 0) + p.get("hbp", 0)) - 2.0 * p.get("so", 0)) / ip + 3.1


## 最多の守備位置（"捕手" "左翼手" など。pos_g は Season が数えている先発出場の試合数）
static func main_pos(b: Dictionary) -> String:
	var best := ""
	var best_g := 0
	var pg: Dictionary = b.get("pos_g", {})
	for pos: String in pg:
		if int(pg[pos]) > best_g:
			best = pos
			best_g = int(pg[pos])
	return best


## その位置（外野手は左中右の合計）の先発出場
static func games_at(b: Dictionary, pos: String) -> int:
	var pg: Dictionary = b.get("pos_g", {})
	if pos == "外野手":
		return int(pg.get("左翼手", 0)) + int(pg.get("中堅手", 0)) + int(pg.get("右翼手", 0))
	return int(pg.get(pos, 0))


## 打者の価値（得点）：wOBA のリーグ平均との差＋守備位置の補正＋代替水準
func _bat_value(id: String) -> float:
	var b: Dictionary = _season.batting[id]
	var pa := float(b.get("pa", 0))
	if pa <= 0.0:
		return -99.0
	var den := _woba_den(b)
	var woba := _woba_num(b) / den if den > 0.0 else 0.0
	var runs := (woba - float(_lg_woba[_league(id)])) / WOBA_SCALE * pa
	var adj := 0.0
	var pg: Dictionary = b.get("pos_g", {})
	var total := 0
	for pos: String in pg:
		total += int(pg[pos])
	for pos: String in pg:
		adj += float(POS_ADJ.get(pos, 0.0)) * float(pg[pos]) / maxf(total, 1.0)
	runs += adj * pa / 600.0 + REPLACEMENT_BAT * pa / 600.0
	runs += float(b.get("sb", 0)) * 0.2 - float(b.get("cs", 0)) * 0.4
	return runs


## 投手の価値（得点）：防御率と FIP の平均でリーグ平均と比べた失点の少なさ＋代替水準（救援は場面の重み）
func _pit_value(id: String) -> float:
	var p: Dictionary = _season.pitching[id]
	var outs := float(p.get("outs", 0))
	if outs <= 0.0:
		return -99.0
	var ip := outs / 3.0
	var lg := float(_lg_runs9[_league(id)])
	var level := (Season.era(p) + fip(p)) / 2.0
	var runs := (lg - level) * ip / 9.0 + REPLACEMENT_PIT_PER9 * ip / 9.0
	var starts := int(p.get("gs", 0))
	if starts * 2 < int(p.get("g", 0)):
		runs *= RELIEF_LEVERAGE
	return runs


## 守備力（能力値 1〜100）。記録の無い位置は 0
func _defense_rating(id: String, pos: String) -> float:
	var data: Dictionary = _player_of.call(id)
	var fielding: Variant = data.get("fielding")
	if not (fielding is Dictionary):
		return 0.0
	var f: Variant = (fielding as Dictionary).get(SimTeam.field_key(pos))
	if not (f is Dictionary):
		return 0.0
	var d: Variant = (f as Dictionary).get("defense")
	if d is Dictionary and (d as Dictionary).get("value") != null:
		return float(d["value"])
	return 0.0


func _qualified_bat(id: String) -> bool:
	return float(_season.batting[id].get("pa", 0)) >= _games_of_team(id) * QUALIFY_PA_PER_GAME


func _qualified_pit(id: String) -> bool:
	return int(_season.pitching[id].get("outs", 0)) >= _games_of_team(id) * QUALIFY_OUTS_PER_GAME


# --- 受賞者の表示 -------------------------------------------------------------------------

func _entry(id: String, text: String) -> Dictionary:
	return {"id": id, "name": _season.player_name(id), "team": _team(id), "text": text}


static func ip_text(outs: int) -> String:
	var frac := outs % 3
	return "%d" % (outs / 3) if frac == 0 else "%d %d/3" % [outs / 3, frac]


static func rate_text(v: float) -> String:
	return ("%.3f" % v).trim_prefix("0")


func bat_line_text(id: String) -> String:
	var b: Dictionary = _season.batting[id]
	return "打率%s %d本 %d打点 %d盗塁" % [rate_text(Season.batting_avg(b)), int(b.get("hr", 0)),
		int(b.get("rbi", 0)), int(b.get("sb", 0))]


func pit_line_text(id: String) -> String:
	var p: Dictionary = _season.pitching[id]
	var text := "%d勝%d敗" % [int(p.get("w", 0)), int(p.get("l", 0))]
	if int(p.get("sv", 0)) > 0:
		text += "%dS" % int(p.get("sv", 0))
	if int(p.get("hld", 0)) > 0:
		text += "%dH" % int(p.get("hld", 0))
	return text + " 防御率%.2f %d奪三振" % [Season.era(p), int(p.get("so", 0))]


func _line_text(id: String) -> String:
	if _season.pitching.has(id) and (not _season.batting.has(id)
			or int(_season.pitching[id].get("outs", 0)) >= int(_season.batting[id].get("pa", 0))):
		return pit_line_text(id)
	return bat_line_text(id)


# --- 各賞 -------------------------------------------------------------------------------

func _mvp(lg: String, order: Dictionary) -> Variant:
	var best := ""
	var best_v := -INF
	var values := {}
	for id: String in _season.batting:
		if _league(id) == lg:
			values[id] = _bat_value(id)
	for id: String in _season.pitching:
		if _league(id) == lg:
			values[id] = maxf(values.get(id, -INF), _pit_value(id))
	for id: String in values:
		var rank := int(order.get(_team(id), 9))
		var v: float = values[id] + (MVP_CHAMPION_BONUS if rank == 1 else MVP_CHAMPION_BONUS * 0.5 if rank == 2 else 0.0)
		if v > best_v:
			best_v = v
			best = id
	return _entry(best, _line_text(best)) if not best.is_empty() else null


## 新人王：資格のある選手のうち、ある程度出場した選手（ROOKIE_MIN_PA 打席か ROOKIE_MIN_OUTS アウト）を優先して価値の最大
func _rookie(lg: String, is_rookie: Callable) -> Variant:
	var best := ""
	var best_key := [false, -INF]
	var checked := {}
	for src: Dictionary in [_season.batting, _season.pitching]:
		for id: String in src:
			if checked.has(id) or _league(id) != lg:
				continue
			checked[id] = true
			var v := maxf(_bat_value(id) if _season.batting.has(id) else -INF,
					_pit_value(id) if _season.pitching.has(id) else -INF)
			var enough := int(_season.batting.get(id, {}).get("pa", 0)) >= ROOKIE_MIN_PA 				or int(_season.pitching.get(id, {}).get("outs", 0)) >= ROOKIE_MIN_OUTS
			var better: bool = (enough and not best_key[0]) or (enough == best_key[0] and v > best_key[1])
			if better and is_rookie.call(id):
				best_key = [enough, v]
				best = id
	return _entry(best, _line_text(best)) if not best.is_empty() else null


## 位置ごとの候補（出場が足りる打者）。足りる選手がいなければ割合を下げてもう一度
func _candidates_at(lg: String, pos: String, need: int) -> Array[String]:
	var share := POSITION_GAMES_SHARE
	while share > 0.01:
		var result: Array[String] = []
		for id: String in _season.batting:
			if _league(id) == lg and games_at(_season.batting[id], pos) >= _games_of_team(id) * share:
				result.append(id)
		if result.size() >= need:
			return result
		share /= 2.0
	return []


func _pitcher_candidates(lg: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in _season.pitching:
		if _league(id) == lg and int(_season.pitching[id].get("outs", 0)) >= _games_of_team(id) * QUALIFY_OUTS_PER_GAME / 2:
			result.append(id)
	return result


## 値の大きい順に n 人（すでに選んだ選手は除く）
static func _top(ids: Array[String], value: Callable, n: int, taken: Dictionary) -> Array[String]:
	var rows: Array = []
	for id in ids:
		if not taken.has(id):
			rows.append([id, float(value.call(id))])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	var result: Array[String] = []
	for i in mini(n, rows.size()):
		result.append(rows[i][0])
	return result


func _best_nine(lg: String) -> Array:
	var result: Array = []
	var taken := {}
	for pos: String in ["投手", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手", "指名打者"]:
		if pos == "指名打者" and lg != "P":
			continue
		var n := 3 if pos == "外野手" else 1
		var picks: Array[String] = []
		if pos == "投手":
			picks = _top(_pitcher_candidates(lg), _pit_value, 1, taken)
		else:
			picks = _top(_candidates_at(lg, pos, n), _bat_value, n, taken)
		for id in picks:
			taken[id] = true
			var text := pit_line_text(id) if pos == "投手" else bat_line_text(id)
			var e := _entry(id, text)
			e["pos"] = pos
			result.append(e)
	return result


func _gold_glove(lg: String) -> Array:
	var result: Array = []
	var taken := {}
	for pos: String in ["投手", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手"]:
		var n := 3 if pos == "外野手" else 1
		var picks: Array[String] = []
		if pos == "投手":
			picks = _top(_pitcher_candidates(lg), func(id: String) -> float:
				return _defense_rating(id, "投手") + float(_season.pitching[id].get("outs", 0)) / 300.0, 1, taken)
		else:
			picks = _top(_candidates_at(lg, pos, n), func(id: String) -> float:
				var g := games_at(_season.batting[id], pos)
				return _defense_rating(id, pos) + 8.0 * g / maxf(_games_of_team(id), 1.0), n, taken)
		for id in picks:
			taken[id] = true
			var g := int(_season.pitching[id].get("g", 0)) if pos == "投手" else games_at(_season.batting[id], pos)
			var e := _entry(id, "%d試合　守備力%d" % [g, int(_defense_rating(id, pos))])
			e["pos"] = pos
			result.append(e)
	return result


## タイトルの値（規定・資格を満たさなければ null）
func _title_value(key: String, kind: String, id: String) -> Variant:
	if kind == "b":
		var b: Dictionary = _season.batting[id]
		match key:
			"avg":
				return Season.batting_avg(b) if _qualified_bat(id) else null
			"obp":
				return obp(b) if _qualified_bat(id) else null
			_:
				return int(b.get(key, 0))
	var p: Dictionary = _season.pitching[id]
	match key:
		"era":
			return Season.era(p) if _qualified_pit(id) else null
		"hp":
			# ホールドポイント＝ホールド＋救援勝利
			var relief_w := maxi(int(p.get("w", 0)) - _starts_won(p), 0)
			return int(p.get("hld", 0)) + relief_w
		"pct":
			return win_pct(p) if int(p.get("w", 0)) >= WIN_PCT_MIN_WINS else null
		_:
			return int(p.get(key, 0))


## 先発での勝ち（記録が無いので、先発した試合数を上限に勝ち星を先発に寄せる近似）
static func _starts_won(p: Dictionary) -> int:
	return mini(int(p.get("w", 0)), int(p.get("gs", 0)))


func _titles(lg: String) -> Array:
	var result: Array = []
	for t: Array in TITLES:
		var key: String = t[0]
		var kind: String = t[2]
		var lower: bool = t[4]
		var src: Dictionary = _season.batting if kind == "b" else _season.pitching
		var best: Variant = null
		var winners: Array[String] = []
		for id: String in src:
			if _league(id) != lg:
				continue
			var v: Variant = _title_value(key, kind, id)
			if v == null:
				continue
			if best == null or (v < best if lower else v > best):
				best = v
				winners = [id]
			elif is_equal_approx(float(v), float(best)):
				winners.append(id)
		var entries: Array = []
		if best != null and (float(best) > 0.0 or lower):
			for id in winners:
				entries.append(_entry(id, pit_line_text(id) if kind == "p" else bat_line_text(id)))
		result.append({"key": key, "name": t[1], "kind": kind, "value": best if entries.size() > 0 else null,
			"value_text": _value_text(key, best) if entries.size() > 0 else "", "winners": entries})
	return result


static func _value_text(key: String, v: Variant) -> String:
	match key:
		"avg", "obp", "pct":
			return rate_text(float(v))
		"era":
			return "%.2f" % float(v)
		"hr":
			return "%d本" % int(v)
		"rbi":
			return "%d打点" % int(v)
		"sb":
			return "%d盗塁" % int(v)
		"h":
			return "%d安打" % int(v)
		"w":
			return "%d勝" % int(v)
		"so":
			return "%d奪三振" % int(v)
		"sv":
			return "%dセーブ" % int(v)
		"hp":
			return "%dHP" % int(v)
	return str(v)


## 沢村賞の基準のうち満たした数
static func sawamura_met(p: Dictionary) -> int:
	var n := 0
	n += 1 if int(p.get("w", 0)) >= SAWAMURA["w"] else 0
	n += 1 if int(p.get("so", 0)) >= SAWAMURA["so"] else 0
	n += 1 if int(p.get("cg", 0)) >= SAWAMURA["cg"] else 0
	n += 1 if int(p.get("outs", 0)) > 0 and Season.era(p) <= SAWAMURA["era"] else 0
	n += 1 if int(p.get("outs", 0)) >= SAWAMURA["outs"] else 0
	n += 1 if int(p.get("g", 0)) >= SAWAMURA["g"] else 0
	n += 1 if win_pct(p) >= SAWAMURA["pct"] else 0
	return n


func _sawamura() -> Variant:
	var best := ""
	var best_key := [-1, -INF]
	for id: String in _season.pitching:
		var p: Dictionary = _season.pitching[id]
		if int(p.get("gs", 0)) * 2 < int(p.get("g", 0)):
			continue
		var met := sawamura_met(p)
		var v := _pit_value(id)
		if met > best_key[0] or (met == best_key[0] and v > best_key[1]):
			best_key = [met, v]
			best = id
	if best.is_empty() or int(best_key[0]) < SAWAMURA_MIN_MET:
		return null
	var e := _entry(best, pit_line_text(best))
	e["text"] += "　%d完投（基準%d/7）" % [int(_season.pitching[best].get("cg", 0)), int(best_key[0])]
	return e


# --- 受賞歴 -------------------------------------------------------------------------------

## 履歴（年の文字列 → compute() の結果）から、選手の受賞歴を [{year, name}] で（年の古い順）
static func history_of(history: Dictionary, id: String) -> Array:
	var result: Array = []
	var years: Array = history.keys()
	years.sort_custom(func(x: Variant, y: Variant) -> bool: return int(x) < int(y))
	for y: Variant in years:
		var res: Dictionary = history[y]
		for lg: String in res.get("leagues", {}):
			var a: Dictionary = res["leagues"][lg]
			for key: String in ["mvp", "rookie"]:
				if a.get(key) is Dictionary and a[key].get("id") == id:
					result.append({"year": int(y), "name": AWARD_NAMES[key]})
			for key: String in ["best_nine", "gold_glove"]:
				for e: Dictionary in a.get(key, []):
					if e.get("id") == id:
						result.append({"year": int(y), "name": "%s（%s）" % [AWARD_NAMES[key], pos_label(e.get("pos", ""))]})
			for t: Dictionary in a.get("titles", []):
				for e: Dictionary in t.get("winners", []):
					if e.get("id") == id:
						result.append({"year": int(y), "name": t["name"]})
		if res.get("sawamura") is Dictionary and res["sawamura"].get("id") == id:
			result.append({"year": int(y), "name": AWARD_NAMES["sawamura"]})
	return result


## 位置の短い表示（"一塁手" → "一塁"）
static func pos_label(pos: String) -> String:
	match pos:
		"投手", "捕手", "外野手":
			return pos.trim_suffix("手")
		"指名打者":
			return "DH"
	return pos.trim_suffix("手")
