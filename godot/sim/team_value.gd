class_name TeamValue
extends RefCounted
## 球団×位置の得失点（記録室の「位置別の戦力」、docs/AUTORUN.md 作業34）。オートロードは参照しない。
##
## その年の成績（GameState.season_stats）から、位置ごとに「リーグ平均（12球団の平均）＝0」の得失点（点）を出す：
## - 野手の位置（捕手〜右翼・指名打者）：打撃（Records の wRAA）＋走塁（盗塁0.2・盗塁死−0.4）を、その選手の先発出場の
##   守備位置の割合（pos_g）で振り分け、守備得点（作業33、守備位置ごとの記録 fld）はその位置にそのまま足す。
##   先発出場の無い選手（代打だけ）は能力値の守備位置（primary_pos_of）に入れる（外野手は左・中・右に3等分）。投手の打撃は入れない
## - 先発・救援：投手の失点の少なさ＝（リーグの防御率 − FIP）× 投球回/9（FIP ベース）。先発が登板の半分以上の投手は先発、それ以外は救援
## - 最後に位置ごとに12球団の平均を引く（各位置の12球団の合計がちょうど0）。合計は全位置の和、順位は合計の大きい順
##
## 能力から見込む値（estimate、昨季がゲームより前の年のとき）：Depth.team_ranks の「現在」のスコアの12球団の平均との差 ×
## ESTIMATE_RUNS（1.0 あたりの点。外野手は左・中・右に同じ値、指名打者は0）

const COLUMNS := ["先発", "救援", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手", "指名打者"]
const SHORT := {"先発": "先発", "救援": "救援", "捕手": "捕手", "一塁手": "一塁", "二塁手": "二塁", "三塁手": "三塁",
	"遊撃手": "遊撃", "左翼手": "左翼", "中堅手": "中堅", "右翼手": "右翼", "指名打者": "DH"}
const FIELD_COLUMNS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手", "指名打者"]
const OUTFIELD := ["左翼手", "中堅手", "右翼手"]
## 能力から見込む値：スコア 1.0 の差あたりの点（野手の1位置・先発陣・救援陣）
const ESTIMATE_RUNS := {"fielder": 18.0, "先発": 45.0, "救援": 22.0}


## {球団: {位置: {bat, fld, pit, total}, "total": 点, "rank": 順位}}。st は GameState.season_stats()
static func from_stats(st: Dictionary, primary_pos_of: Callable) -> Dictionary:
	var raw := {}
	if st.is_empty():
		return raw
	for team: String in st["records"]:
		raw[team] = {}
		for col: String in COLUMNS:
			raw[team][col] = {"bat": 0.0, "fld": 0.0, "pit": 0.0}
	var league_of := func(id: String) -> String:
		return st["leagues"].get(st["players"].get(id, {}).get("team", ""), "")
	var coef := {}
	for lg: String in ["C", "P"]:
		coef[lg] = Records.coefficients(st["batting"], st["pitching"], league_of, lg)
	for id: String in st["batting"]:
		var b: Dictionary = st["batting"][id]
		var team: String = st["players"].get(id, {}).get("team", "")
		var lg: String = league_of.call(id)
		if not raw.has(team) or not coef.has(lg):
			continue
		# 守備得点はその位置へ
		var fr := Records.fielding_runs(b, coef[lg]["fielding"])
		for pos: String in fr["pos"]:
			if raw[team].has(pos):
				raw[team][pos]["fld"] += float(fr["pos"][pos]["total"])
		if int(b.get("pa", 0)) <= 0:
			continue
		var shares := _shares(b, primary_pos_of.call(id))
		if shares.is_empty():
			continue
		var row := Records.batting_row(b, coef[lg])
		var runs: float = float(row["wraa"]) + Records.SB_RUNS * b.get("sb", 0) + Records.CS_RUNS * b.get("cs", 0)
		for pos: String in shares:
			raw[team][pos]["bat"] += runs * float(shares[pos])
	for id: String in st["pitching"]:
		var p: Dictionary = st["pitching"][id]
		var team: String = st["players"].get(id, {}).get("team", "")
		var lg: String = league_of.call(id)
		var outs := int(p.get("outs", 0))
		if not raw.has(team) or not coef.has(lg) or outs <= 0:
			continue
		var row := Records.pitching_row(p, coef[lg])
		var col := "先発" if int(p.get("gs", 0)) * 2 >= int(p.get("g", 0)) else "救援"
		raw[team][col]["pit"] += (float(coef[lg]["lg_era"]) - float(row["fip"])) * outs / 27.0
	return _finish(raw)


## 能力から見込んだ値（from_stats と同じ形）。ranks は 球団 → Depth.team_ranks()
static func estimate(ranks: Dictionary) -> Dictionary:
	var raw := {}
	for team: String in ranks:
		raw[team] = {}
		var r: Dictionary = ranks[team]
		for col: String in COLUMNS:
			var v := 0.0
			match col:
				"先発":
					v = float(r["先発"]["now"]) * ESTIMATE_RUNS["先発"]
				"救援":
					v = (6.0 * float(r["中継ぎ"]["now"]) + float(r["抑え"]["now"])) / 7.0 * ESTIMATE_RUNS["救援"]
				"指名打者":
					v = 0.0
				_:
					var key: String = "外野手" if col in OUTFIELD else col
					v = float(r[key]["now"]) * ESTIMATE_RUNS["fielder"]
			raw[team][col] = {"bat": v if not col in ["先発", "救援"] else 0.0, "fld": 0.0,
				"pit": v if col in ["先発", "救援"] else 0.0}
	return _finish(raw)


## 先発出場の守備位置の割合 {位置: 割合}（投手は除く。先発出場が無ければ能力値の守備位置）
static func _shares(b: Dictionary, primary: String) -> Dictionary:
	var pg: Dictionary = b.get("pos_g", {})
	var total := 0
	for pos: String in pg:
		if pos in FIELD_COLUMNS:
			total += int(pg[pos])
	var shares := {}
	if total > 0:
		for pos: String in pg:
			if pos in FIELD_COLUMNS:
				shares[pos] = float(pg[pos]) / total
		return shares
	if primary == "外野手":
		for pos: String in OUTFIELD:
			shares[pos] = 1.0 / 3.0
	elif primary in FIELD_COLUMNS:
		shares[primary] = 1.0
	return shares


## 位置ごとに12球団の平均を引き、合計と順位を付ける
static func _finish(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return raw
	var n := float(raw.size())
	for col: String in COLUMNS:
		var mean := {"bat": 0.0, "fld": 0.0, "pit": 0.0}
		for team: String in raw:
			for k: String in mean:
				mean[k] += float(raw[team][col][k]) / n
		for team: String in raw:
			var cell: Dictionary = raw[team][col]
			for k: String in mean:
				cell[k] = float(cell[k]) - float(mean[k])
			cell["total"] = cell["bat"] + cell["fld"] + cell["pit"]
	var teams: Array = raw.keys()
	for team: String in teams:
		var sum := 0.0
		for col: String in COLUMNS:
			sum += float(raw[team][col]["total"])
		raw[team]["total"] = sum
	teams.sort_custom(func(a: String, b: String) -> bool: return raw[a]["total"] > raw[b]["total"])
	for i in teams.size():
		raw[teams[i]]["rank"] = i + 1
	return raw
