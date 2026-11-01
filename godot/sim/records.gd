class_name Records
extends RefCounted
## 記録室の計算（個人成績・セイバー指標・通算）。オートロードは参照しない（成績の辞書を受け取って計算するだけ）。
##
## 成績の辞書は Season.batting / Season.pitching の1人分（g・pa・ab・h・d・t・hr・rbi・r・bb・hbp・so・sb・cs・
## sh・sf・gdp、投手は g・gs・outs・bf・h・hr・bb・hbp・so・r・er・w・l・sv・hld・cg・sho。pos_g は守備位置ごとの先発出場）。
##
## 係数はその年のゲーム内のリーグ成績から毎年計算する（coefficients()。パークファクターは無し）：
## - 得点価値：各イベントの基準の得点価値 RUN_VALUES をリーグの1打席あたり得点の比で伸び縮みさせ、
##   アウトの価値 OUT_VALUE を足して生の重みにする。生の wOBA のリーグ平均がリーグの出塁率に一致するよう
##   全体を倍率（wOBA スケール）で合わせる（FanGraphs と同じ考え方）
## - wRAA ＝（wOBA − リーグ wOBA）÷ wOBA スケール × 打席、wRC+ ＝（wRAA/打席 ＋ リーグの得点/打席）÷ リーグの得点/打席 × 100
##   → リーグの打席で重み付けた平均がちょうど100
## - OPS+ ＝ 100 ×（出塁率/リーグ出塁率 ＋ 長打率/リーグ長打率 − 1）
## - FIP ＝（13×本塁打 ＋ 3×（四球＋死球）− 2×三振）÷ 投球回 ＋ 定数（リーグの防御率に合わせる）
## - 守備得点（UZR 風）：試合で数えた守備の記録（打撃成績の "fld"。GameSim が数える）を、同じ守備位置のリーグ平均の
##   成功率と比べ、平均より多く（少なく）処理した数 × 1つあたりの得点（FIELDING_RV）を足す。位置ごとのリーグ合計は0
## - 簡易 WAR：野手＝（wRAA ＋ 走塁 ＋ 守備得点 ＋ 守備位置の補正 ＋ 代替水準）÷ 1勝の得点、投手＝（代替水準の失点率 − FIP）× 投球回/9 ÷ 1勝の得点

## 基準の得点価値（NPB の近年のおおよその値。1打席あたり得点 BASE_RUNS_PER_PA のとき）
const RUN_VALUES := {"bb": 0.30, "hbp": 0.33, "1b": 0.46, "2b": 0.77, "3b": 1.05, "hr": 1.40}
const OUT_VALUE := 0.27
const BASE_RUNS_PER_PA := 0.115
## 走塁（盗塁・盗塁死の得点）
const SB_RUNS := 0.2
const CS_RUNS := -0.4
## 守備位置の補正（600打席あたりの得点。中堅・左右翼は外野手の内訳）
const POS_ADJ := {"捕手": 12.0, "遊撃手": 7.0, "二塁手": 3.0, "三塁手": 2.0, "中堅手": 2.5,
	"左翼手": -7.0, "右翼手": -7.0, "一塁手": -12.0, "指名打者": -17.0, "投手": 0.0}
## 代替水準：野手は600打席あたりの得点、投手はリーグの失点率（9回あたり）にこの倍率をかけた失点率
const REPLACEMENT_BAT := 16.5
const REPLACEMENT_PIT_RATE := 1.25
const REPLACEMENT_RELIEF_RATE := 1.12
## 1勝あたりの得点（リーグの1試合の得点（両チーム）に比例させる。9.0点で RUNS_PER_WIN_BASE）
const RUNS_PER_WIN_BASE := 9.5

## 守備得点の内訳：[成功の数のキー, 機会の数のキー, 得点の種類（FIELDING_RV）, 区分]。
## 区分は rng＝範囲（打球を処理したか）、err＝失策（処理した打球での失策）、arm＝外野の肩（長打を単打に止めた・
## 走者の本塁／三塁への進塁を止めた・刺した）、cs＝捕手の盗塁阻止、wp＝捕手の暴投・捕逸
## 守備の記録のキー：gb ゴロの機会・gbo 処理・gbe 失策、ln 鋭い当たりの機会・lno 捕球・lne 失策、xh 外野の安打・
## xs 単打に止めた、ah 本塁を狙える走者・ahh 止めた・ahk 刺した、a3 一塁→三塁を狙える走者・a3h・a3k、
## sba 盗塁企図・cs 盗塁刺、wpo 走者ありの打席・wp 暴投・捕逸、outs 守備のアウト数（守備イニング×3）
const FIELDING_PARTS := [
	["gbo", "gb", "range", "rng"], ["lno", "ln", "range", "rng"],
	["gbe", "gbo", "error", "err"], ["lne", "lno", "error", "err"],
	["xs", "xh", "xbh", "arm"], ["ahh", "ah", "hold_home", "arm"], ["ahk", "ah", "kill_home", "arm"],
	["a3h", "a3", "hold_3b", "arm"], ["a3k", "a3", "kill_3b", "arm"],
	["cs", "sba", "cs", "cs"], ["wp", "wpo", "wp", "wp"],
]
## 1つあたりの得点（平均より1つ多いと何点防いだか）。範囲は内野（ゴロ・ライナーのアウト↔単打）と外野
## （鋭い当たりのアウト↔安打。長打を含む）で分ける。失策・暴投は1つ多いと失点が増える（−）
const FIELDING_RV := {
	"range_if": 0.75, "range_of": 0.85, "error": -0.75, "xbh": 0.32,
	"hold_home": 0.55, "kill_home": 0.95, "hold_3b": 0.20, "kill_3b": 0.60,
	"cs": 0.60, "wp": -0.28,
}
const FIELDING_CATEGORIES := ["rng", "err", "arm", "cs", "wp"]
const OUTFIELD := ["左翼手", "中堅手", "右翼手"]

## 打撃の列：[キー, 見出し, 種類（int/rate3/rate2/pct/plus/war）, 小さいほど良いか]
const BAT_COLUMNS := [
	["g", "試合", "int", false], ["pa", "打席", "int", false], ["avg", "打率", "rate3", false],
	["hr", "本", "int", false], ["rbi", "打点", "int", false], ["h", "安打", "int", false],
	["sb", "盗塁", "int", false], ["obp", "出塁率", "rate3", false], ["slg", "長打率", "rate3", false],
	["ops", "OPS", "rate3", false], ["woba", "wOBA", "rate3", false], ["wrc_plus", "wRC+", "plus", false],
	["ops_plus", "OPS+", "plus", false], ["iso", "ISO", "rate3", false], ["bb_pct", "BB%", "pct", false],
	["k_pct", "K%", "pct", true], ["babip", "BABIP", "rate3", false], ["fld", "守備", "runs", false],
	["war", "WAR", "war", false],
]
const PIT_COLUMNS := [
	["g", "登板", "int", false], ["ip", "投球回", "ip", false], ["era", "防御率", "rate2", true],
	["w", "勝", "int", false], ["l", "敗", "int", true], ["sv", "S", "int", false], ["hp", "HP", "int", false],
	["so", "奪三振", "int", false], ["fip", "FIP", "rate2", true], ["whip", "WHIP", "rate2", true],
	["k9", "K/9", "rate2", false], ["bb9", "BB/9", "rate2", true], ["k_bb_pct", "K-BB%", "pct", false],
	["war", "WAR", "war", false],
]


# --- 係数 ---------------------------------------------------------------------------------

## リーグ（league_of(選手ID) == lg、lg が空なら全体）の係数。batting/pitching は選手ID → 成績
static func coefficients(batting: Dictionary, pitching: Dictionary, league_of: Callable, lg: String) -> Dictionary:
	var t := {"pa": 0.0, "ab": 0.0, "h": 0.0, "d": 0.0, "t": 0.0, "hr": 0.0, "bb": 0.0, "hbp": 0.0, "sf": 0.0,
		"so": 0.0, "r": 0.0}
	for id: String in batting:
		if not lg.is_empty() and league_of.call(id) != lg:
			continue
		var b: Dictionary = batting[id]
		for key: String in t:
			t[key] += float(b.get(key, 0))
	var pt := {"outs": 0.0, "er": 0.0, "r": 0.0, "hr": 0.0, "bb": 0.0, "hbp": 0.0, "so": 0.0, "gs": 0.0}
	for id: String in pitching:
		if not lg.is_empty() and league_of.call(id) != lg:
			continue
		var p: Dictionary = pitching[id]
		for key: String in pt:
			pt[key] += float(p.get(key, 0))
	var c := {}
	var pa := maxf(t["pa"], 1.0)
	c["runs_per_pa"] = t["r"] / pa
	var scale_rv: float = c["runs_per_pa"] / BASE_RUNS_PER_PA if c["runs_per_pa"] > 0.0 else 1.0
	var out_v := OUT_VALUE * scale_rv
	var raw := {}
	for key: String in RUN_VALUES:
		raw[key] = RUN_VALUES[key] * scale_rv + out_v
	var one_b: float = t["h"] - t["d"] - t["t"] - t["hr"]
	var den: float = t["ab"] + t["bb"] + t["hbp"] + t["sf"]
	var raw_num: float = raw["bb"] * t["bb"] + raw["hbp"] * t["hbp"] + raw["1b"] * one_b + raw["2b"] * t["d"] \
		+ raw["3b"] * t["t"] + raw["hr"] * t["hr"]
	var lg_obp: float = (t["h"] + t["bb"] + t["hbp"]) / den if den > 0.0 else 0.320
	var raw_woba := raw_num / den if den > 0.0 else 0.320
	var scale := lg_obp / raw_woba if raw_woba > 0.0 else 1.0
	var weights := {}
	for key: String in raw:
		weights[key] = raw[key] * scale
	c["weights"] = weights
	c["woba_scale"] = scale
	c["lg_woba"] = lg_obp
	c["lg_obp"] = lg_obp
	c["lg_slg"] = (one_b + 2 * t["d"] + 3 * t["t"] + 4 * t["hr"]) / t["ab"] if t["ab"] > 0.0 else 0.380
	var ip: float = pt["outs"] / 3.0
	c["lg_era"] = pt["er"] * 9.0 / ip if ip > 0.0 else 3.8
	c["lg_ra9"] = pt["r"] * 9.0 / ip if ip > 0.0 else 4.1
	var raw_fip: float = (13.0 * pt["hr"] + 3.0 * (pt["bb"] + pt["hbp"]) - 2.0 * pt["so"]) / ip if ip > 0.0 else 0.0
	c["fip_const"] = c["lg_era"] - raw_fip
	# 1試合の得点（両チーム）＝ 失点 ÷ 試合数（先発は1試合に両チーム1人ずつなので 試合数 ＝ 先発 ÷ 2）
	var runs_per_game: float = pt["r"] * 2.0 / pt["gs"] if pt["gs"] > 0.0 else 8.2
	c["runs_per_win"] = RUNS_PER_WIN_BASE * runs_per_game / 9.0
	# 守備得点の基準は両リーグを合わせた守備位置ごとの合計（lg に関係なく全員）
	c["fielding"] = fielding_baseline(batting)
	return c


# --- 守備得点 -------------------------------------------------------------------------------

## 守備位置 → 守備の記録の合計（全選手）。fielding_runs() の基準（リーグ平均の成功率）に使う
static func fielding_baseline(batting: Dictionary) -> Dictionary:
	var base := {}
	for id: String in batting:
		add_fielding(base, batting[id].get("fld", {}))
	return base


## 守備の記録を足し合わせる（守備位置 → {キー: 数}）
static func add_fielding(total: Dictionary, fld: Dictionary) -> void:
	for pos: String in fld:
		var t: Dictionary = total.get_or_add(pos, {})
		var line: Dictionary = fld[pos]
		for key: String in line:
			t[key] = int(t.get(key, 0)) + int(line[key])


## 1人の守備得点 {total, outs, pos: {守備位置: {outs, rng, err, arm, cs, wp, total}}}。base は fielding_baseline()
static func fielding_runs(b: Dictionary, base: Dictionary) -> Dictionary:
	var result := {"total": 0.0, "outs": 0, "pos": {}}
	var fld: Dictionary = b.get("fld", {})
	for pos: String in fld:
		var line: Dictionary = fld[pos]
		var lg: Dictionary = base.get(pos, {})
		var r := {"outs": int(line.get("outs", 0)), "total": 0.0}
		for cat: String in FIELDING_CATEGORIES:
			r[cat] = 0.0
		for part: Array in FIELDING_PARTS:
			var chances := float(line.get(part[1], 0))
			var lg_chances := float(lg.get(part[1], 0))
			if chances <= 0.0 or lg_chances <= 0.0:
				continue
			var rate := float(lg.get(part[0], 0)) / lg_chances
			var kind: String = part[2]
			if kind == "range":
				kind = "range_of" if pos in OUTFIELD else "range_if"
			var runs: float = (float(line.get(part[0], 0)) - chances * rate) * float(FIELDING_RV[kind])
			r[part[3]] += runs
			r["total"] += runs
		result["pos"][pos] = r
		result["total"] += r["total"]
		result["outs"] += r["outs"]
	return result


# --- 1人分 ---------------------------------------------------------------------------------

static func singles(b: Dictionary) -> int:
	return int(b.get("h", 0)) - int(b.get("d", 0)) - int(b.get("t", 0)) - int(b.get("hr", 0))


static func woba(b: Dictionary, c: Dictionary) -> float:
	var den: float = float(b.get("ab", 0) + b.get("bb", 0) + b.get("hbp", 0) + b.get("sf", 0))
	if den <= 0.0:
		return 0.0
	var w: Dictionary = c["weights"]
	return (w["bb"] * b.get("bb", 0) + w["hbp"] * b.get("hbp", 0) + w["1b"] * singles(b) + w["2b"] * b.get("d", 0)
		+ w["3b"] * b.get("t", 0) + w["hr"] * b.get("hr", 0)) / den


## 打撃の指標の辞書（BAT_COLUMNS のキー）。c は coefficients()
static func batting_row(b: Dictionary, c: Dictionary) -> Dictionary:
	var pa := float(b.get("pa", 0))
	var ab := float(b.get("ab", 0))
	var r := {}
	for key: String in ["g", "pa", "hr", "rbi", "h", "sb"]:
		r[key] = int(b.get(key, 0))
	r["avg"] = float(b.get("h", 0)) / ab if ab > 0.0 else 0.0
	var obp_den := float(b.get("ab", 0) + b.get("bb", 0) + b.get("hbp", 0) + b.get("sf", 0))
	r["obp"] = float(b.get("h", 0) + b.get("bb", 0) + b.get("hbp", 0)) / obp_den if obp_den > 0.0 else 0.0
	var tb := float(singles(b) + 2 * b.get("d", 0) + 3 * b.get("t", 0) + 4 * b.get("hr", 0))
	r["slg"] = tb / ab if ab > 0.0 else 0.0
	r["ops"] = r["obp"] + r["slg"]
	r["iso"] = r["slg"] - r["avg"]
	r["woba"] = woba(b, c)
	var wraa: float = (r["woba"] - float(c["lg_woba"])) / float(c["woba_scale"]) * pa
	var rpa := float(c["runs_per_pa"])
	r["wraa"] = wraa
	r["wrc_plus"] = (wraa / pa + rpa) / rpa * 100.0 if pa > 0.0 and rpa > 0.0 else 0.0
	r["ops_plus"] = 100.0 * (r["obp"] / c["lg_obp"] + r["slg"] / c["lg_slg"] - 1.0) if pa > 0.0 else 0.0
	r["bb_pct"] = float(b.get("bb", 0)) / pa if pa > 0.0 else 0.0
	r["k_pct"] = float(b.get("so", 0)) / pa if pa > 0.0 else 0.0
	var babip_den := float(b.get("ab", 0) - b.get("so", 0) - b.get("hr", 0) + b.get("sf", 0))
	r["babip"] = float(b.get("h", 0) - b.get("hr", 0)) / babip_den if babip_den > 0.0 else 0.0
	r["fld"] = fielding_runs(b, c["fielding"])["total"] if c.has("fielding") else 0.0
	r["war"] = batting_war(b, wraa, c, r["fld"])
	return r


## 野手の簡易 WAR（打撃 wRAA ＋ 走塁 ＋ 守備得点 fld ＋ 守備位置の補正 ＋ 代替水準）
static func batting_war(b: Dictionary, wraa: float, c: Dictionary, fld := 0.0) -> float:
	var pa := float(b.get("pa", 0))
	if pa <= 0.0:
		return 0.0
	var run: float = SB_RUNS * b.get("sb", 0) + CS_RUNS * b.get("cs", 0)
	var pg: Dictionary = b.get("pos_g", {})
	var total := 0.0
	var adj := 0.0
	for pos: String in pg:
		total += float(pg[pos])
	for pos: String in pg:
		adj += float(POS_ADJ.get(pos, 0.0)) * float(pg[pos]) / total
	var runs := wraa + run + fld + (adj + REPLACEMENT_BAT) * pa / 600.0
	return runs / float(c["runs_per_win"])


## 投手の指標の辞書（PIT_COLUMNS のキー）
static func pitching_row(p: Dictionary, c: Dictionary) -> Dictionary:
	var outs := float(p.get("outs", 0))
	var ip: float = outs / 3.0
	var r := {}
	for key: String in ["g", "w", "l", "sv", "so", "outs"]:
		r[key] = int(p.get(key, 0))
	r["ip"] = outs
	r["hp"] = int(p.get("hld", 0)) + maxi(int(p.get("w", 0)) - int(p.get("gs", 0)), 0)
	r["era"] = p.get("er", 0) * 9.0 / ip if ip > 0.0 else 99.99
	r["fip"] = (13.0 * p.get("hr", 0) + 3.0 * (p.get("bb", 0) + p.get("hbp", 0)) - 2.0 * p.get("so", 0)) / ip \
		+ float(c["fip_const"]) if ip > 0.0 else 99.99
	r["whip"] = float(p.get("h", 0) + p.get("bb", 0)) / ip if ip > 0.0 else 99.99
	r["k9"] = p.get("so", 0) * 9.0 / ip if ip > 0.0 else 0.0
	r["bb9"] = p.get("bb", 0) * 9.0 / ip if ip > 0.0 else 99.99
	var bf := float(p.get("bf", 0))
	r["k_bb_pct"] = float(p.get("so", 0) - p.get("bb", 0)) / bf if bf > 0.0 else 0.0
	r["war"] = pitching_war(p, r["fip"], c)
	return r


## 投手の簡易 WAR（代替水準の失点率 − FIP）。先発が半分未満の投手は救援の代替水準
static func pitching_war(p: Dictionary, fip_value: float, c: Dictionary) -> float:
	var ip: float = float(p.get("outs", 0)) / 3.0
	if ip <= 0.0:
		return 0.0
	var relief := int(p.get("gs", 0)) * 2 < int(p.get("g", 0))
	var repl := float(c["lg_era"]) * (REPLACEMENT_RELIEF_RATE if relief else REPLACEMENT_PIT_RATE)
	return (repl - fip_value) * ip / 9.0 / float(c["runs_per_win"])


## 表示用の文字
static func format(kind: String, v: Variant) -> String:
	match kind:
		"int":
			return str(int(v))
		"rate3":
			var f := float(v)
			return ("%.3f" % f).trim_prefix("0") if f < 1.0 else "%.3f" % f
		"rate2":
			return "-" if float(v) >= 99.0 else "%.2f" % float(v)
		"pct":
			return "%.1f%%" % (float(v) * 100.0)
		"plus":
			return str(roundi(float(v)))
		"war":
			return "%.1f" % float(v)
		"runs":
			return "%+.1f" % float(v) if absf(float(v)) >= 0.05 else "0.0"
		"ip":
			var outs := int(v)
			return "%d" % (outs / 3) if outs % 3 == 0 else "%d.%d" % [outs / 3, outs % 3]
	return str(v)


## 成績の辞書を足し合わせる（通算。pos_g・fld も足す）
static func add_into(total: Dictionary, line: Dictionary) -> void:
	for key: String in line:
		if key == "fld":
			add_fielding(total.get_or_add("fld", {}), line["fld"])
		elif key == "pos_g":
			var pg: Dictionary = total.get_or_add("pos_g", {})
			for pos: String in line["pos_g"]:
				pg[pos] = int(pg.get(pos, 0)) + int(line["pos_g"][pos])
		elif line[key] is int or line[key] is float:
			total[key] = total.get(key, 0) + line[key]


## 選手ページ（data/<年>/players.json）の年度別1軍成績の1行 → 成績の辞書（打撃）
static func from_page_batting(row: Dictionary) -> Dictionary:
	return {"g": _n(row.get("試合")), "pa": _n(row.get("打席")), "ab": _n(row.get("打数")),
		"r": _n(row.get("得点")), "h": _n(row.get("安打")), "d": _n(row.get("二塁打")),
		"t": _n(row.get("三塁打")), "hr": _n(row.get("本塁打")), "rbi": _n(row.get("打点")),
		"sb": _n(row.get("盗塁")), "cs": _n(row.get("盗塁刺")), "sh": _n(row.get("犠打")),
		"sf": _n(row.get("犠飛")), "bb": _n(row.get("四球")), "hbp": _n(row.get("死球")),
		"so": _n(row.get("三振")), "gdp": _n(row.get("併殺打"))}


static func from_page_pitching(row: Dictionary) -> Dictionary:
	return {"g": _n(row.get("登板")), "w": _n(row.get("勝利")), "l": _n(row.get("敗北")),
		"sv": _n(row.get("セーブ")), "hld": _n(row.get("H")), "cg": _n(row.get("完投")),
		"sho": _n(row.get("完封勝")), "bf": _n(row.get("打者")), "outs": _n(row.get("outs")),
		"h": _n(row.get("安打")), "hr": _n(row.get("本塁打")), "bb": _n(row.get("四球")),
		"hbp": _n(row.get("死球")), "so": _n(row.get("三振")), "r": _n(row.get("失点")),
		"er": _n(row.get("自責点"))}


## 選手ページの数値（数でない・空のときは 0）
static func _n(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	if v is String and (v as String).is_valid_float():
		return int(float(v))
	return 0


# --- 達成記録（試合の結果から） --------------------------------------------------------------

## その年の全試合からノーヒットノーラン（完全試合を含む）・サイクル安打を探す。
## [{date, kind, id, name, team, text}]。games は Season.games、name_of/team_of は選手ID → 名前・球団
static func feats(games: Array, name_of: Callable, team_of: Callable) -> Array:
	var result: Array = []
	for g: Dictionary in games:
		var res: Dictionary = g.get("result", {})
		if res.is_empty():
			continue
		for side in 2:
			var pitchers: Array = res["pitching"][side]
			var opp_bat: Array = res["batting"][1 - side]
			var hits := 0
			var walks := 0
			var reached_err := 0
			for line: Dictionary in opp_bat:
				hits += int(line.get("h", 0))
				walks += int(line.get("bb", 0)) + int(line.get("hbp", 0))
				reached_err += int(line.get("roe", 0))
			if hits == 0 and pitchers.size() == 1:
				var pid: String = pitchers[0]["id"]
				var perfect := walks == 0 and reached_err == 0
				result.append({"date": g["date"], "kind": "完全試合" if perfect else "ノーヒットノーラン", "id": pid,
					"name": name_of.call(pid), "team": team_of.call(pid),
					"text": "%s戦" % (g["away"] if side == 1 else g["home"])})
			for line: Dictionary in res["batting"][side]:
				if singles(line) > 0 and int(line.get("d", 0)) > 0 and int(line.get("t", 0)) > 0 \
						and int(line.get("hr", 0)) > 0:
					var bid: String = line["id"]
					result.append({"date": g["date"], "kind": "サイクル安打", "id": bid, "name": name_of.call(bid),
						"team": team_of.call(bid), "text": "%s戦" % (g["home"] if side == 0 else g["away"])})
	return result
