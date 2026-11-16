class_name GrowthDiff
extends RefCounted
## 前の年からの能力の変化（docs/AUTORUN.md 作業83「成長が見える」。HANDOFF 4.87）。
## ユーザーの声：「選手の成長を見るのが楽しい」。選手詳細の能力に ↑ と差、春季キャンプのニュースに「この1年でいちばん伸びた選手」と覚醒。
## - 比べる相手は「前の年の開幕時点」の能力（_gd().growth_prev）。開幕時点の能力値（<年>_pre）を読むたびに写しを取り（snapshot）、
##   次の年の開幕時点を読んだときに前の年の写しへ回す（_gd().load_ratings）。シーズン中に混ぜた能力（SeasonBlend）も今の値として比べる
## - 写しはセーブに入る（GameState の growth_prev）。無いとき（古いセーブ・新しく始めた年）は前の年の開幕時点の能力値を読んで作る（prev_values）
## - 写しの形：選手ID → {"b": {ミート…}, "p": {総合・制球・スタミナ・奪三振・被弾抑制}, "v": 球速, "m": {球種: 変化量}}（ある分だけ）

## GameData（自動読み込み）は名前で直接書かない（GameData がこのクラスを使うので、読み込みの順で名前が見つからなくなる）
static func _gd() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameData")


const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["overall", "bb9", "stamina", "k9", "hr9"]
## 能力の見出し（ニュースの文）
const LABELS := {"meet": "ミート", "power": "パワー", "eye": "選球眼", "speed": "走力", "defense": "守備", "arm": "肩",
	"overall": "総合", "bb9": "制球", "stamina": "スタミナ", "k9": "奪三振", "hr9": "打たれ強さ", "kmh": "球速"}
## 伸びの点（ニュースで比べる）：野手は6つの能力の上がった分の和、投手は総合の上がり × PIT_OVERALL_W ＋ 球速 1km/h あたり VELO_W
const PIT_OVERALL_W := 2.0
const VELO_W := 1.0
## 史実の能力値の年（成績から作った能力）は、出場の少ない選手の数字が大きく揺れるので、ニュースは出場量（写しの "s"：
## 野手は打席、投手はアウト数。1軍＋2軍の半分。前の年と今の両方）がこれ以上の選手だけ比べる。架空の年（成長の式で動く）は絞らない
const NEWS_MIN_PA := 250
const NEWS_MIN_OUTS := 180
## 覚醒：AWAKEN_AGE 歳以下で、伸びの点が AWAKEN_SCORE 以上か、1つの能力が AWAKEN_ONE 以上上がった（作業83）
const AWAKEN_AGE := 27
const AWAKEN_SCORE := 24.0
const AWAKEN_ONE := 12


## 選手1人の写し（能力値ファイルの選手データから）
static func of(p: Dictionary) -> Dictionary:
	var out := {}
	var bat: Variant = p.get("batting")
	if bat is Dictionary and bat.get("ratings") is Dictionary:
		var b := {}
		for k: String in BAT_KEYS:
			var v: Variant = _value(bat["ratings"].get(k))
			if v != null:
				b[k] = v
		if not b.is_empty():
			out["b"] = b
		var bs: Variant = bat.get("sample")
		if bs is Dictionary and not bool(p.get("is_pitcher", false)):
			out["s"] = int(float(bs.get("pa_1", 0.0)) + 0.5 * float(bs.get("pa_2", 0.0)))
	var pit: Variant = p.get("pitching")
	if bool(p.get("is_pitcher", false)) and pit is Dictionary:
		var ps: Variant = pit.get("sample")
		if ps is Dictionary:
			out["s"] = int(float(ps.get("outs_1", 0.0)) + 0.5 * float(ps.get("outs_2", 0.0)))
		if pit.get("ratings") is Dictionary:
			var q := {}
			for k: String in PIT_KEYS:
				var v: Variant = _value(pit["ratings"].get(k))
				if v != null:
					q[k] = v
			if not q.is_empty():
				out["p"] = q
		var velo: Variant = pit.get("velocity")
		if velo is Dictionary and velo.get("kmh") != null:
			out["v"] = int(round(float(velo["kmh"])))
		if pit.get("pitches") is Array:
			var m := {}
			for x: Dictionary in pit["pitches"]:
				m[str(x["name"])] = int(x["move"])
			out["m"] = m
	return out


static func _value(r: Variant) -> Variant:
	return int(round(float(r["value"]))) if r is Dictionary and r.get("value") != null else null


## 選手の一覧（能力値ファイルの players）の写し
static func snapshot(players: Array) -> Dictionary:
	var out := {}
	for p: Dictionary in players:
		var s := of(p)
		if not s.is_empty():
			out[str(p["id"])] = s
	return out


## 前の年の開幕時点の写し（選手ID → 写し）。year は今の能力値の年。無ければ前の年の開幕時点の能力値を読んで作る（1回だけ）
static func prev_values(year: int) -> Dictionary:
	var gp: Dictionary = _gd().growth_prev
	if int(gp.get("year", -1)) == year - 1:
		return gp.get("values", {})
	var before: Dictionary = _gd().peek_ratings(year - 1, "pre", false)
	if before.is_empty() or is_same(before, _gd().ratings):
		_gd().growth_prev = {"year": year - 1, "values": {}}
		return {}
	var players: Array = before.get("players", [])
	if not _gd().synthetic.has(year - 1):
		PitchArsenal.ensure_all(players, year - 1)  # 能力値ファイルには持ち球が無い（_gd().load_ratings と同じ）
	_gd().growth_prev = {"year": year - 1, "values": snapshot(players)}
	return _gd().growth_prev["values"]


## 前の年の開幕時点からの差。kind は "b"（野手の能力）・"p"（投手の能力）・"v"（球速。key は無視）。比べられなければ null
static func delta(p: Dictionary, kind: String, key := "") -> Variant:
	var id := str(p.get("id", ""))
	if id.is_empty() or _gd().ratings.is_empty():
		return null
	var prev: Dictionary = prev_values(int(_gd().ratings.get("year", -1))).get(id, {})
	if not prev.has(kind):
		return null
	var now := of(p)
	if not now.has(kind):
		return null
	if kind == "v":
		return int(now["v"]) - int(prev["v"])
	if not now[kind].has(key) or not prev[kind].has(key):
		return null
	return int(now[kind][key]) - int(prev[kind][key])


## 持ち球の変化：[[球種, 前の変化量（新しい球種は 0）, 今の変化量], ...]（変わった球種だけ）。比べられなければ []。
## 新しい球種は、前の年の球種が全部残っているときだけ（覚えた＝足された）
static func pitch_changes(p: Dictionary) -> Array:
	var id := str(p.get("id", ""))
	if id.is_empty() or _gd().ratings.is_empty():
		return []
	var prev: Dictionary = prev_values(int(_gd().ratings.get("year", -1))).get(id, {})
	var now := of(p)
	if not prev.has("m") or not now.has("m"):
		return []
	# 前の年の球種が消えているとき（実在の選手は毎年の能力から持ち球を作り直すので、球種が入れ替わることがある）は、
	# 「新しい球種」とは言えないので、両方の年にある球種の変化量だけにする
	var replaced := false
	for name: String in prev["m"]:
		replaced = replaced or not now["m"].has(name)
	var out: Array = []
	for name: String in now["m"]:
		if replaced and not prev["m"].has(name):
			continue
		var a := int(prev["m"].get(name, 0))
		var b := int(now["m"][name])
		if a != b:
			out.append([name, a, b])
	return out


## 1人の伸び：{"score": 伸びの点, "ups": [[見出し, 前, 今], ...]（上がった能力。大きい順）, "best": いちばん上がった差}。
## 前の写しが無ければ {}
static func growth_of(prev: Dictionary, now: Dictionary, is_pitcher: bool) -> Dictionary:
	if prev.is_empty() or now.is_empty():
		return {}
	var ups: Array = []
	var score := 0.0
	var best := 0
	if is_pitcher:
		var a: Dictionary = prev.get("p", {})
		var b: Dictionary = now.get("p", {})
		for k: String in PIT_KEYS:
			if a.has(k) and b.has(k) and int(b[k]) > int(a[k]):
				ups.append([LABELS[k], int(a[k]), int(b[k])])
				if k != "overall":
					best = maxi(best, int(b[k]) - int(a[k]))
		if a.has("overall") and b.has("overall"):
			score += PIT_OVERALL_W * float(int(b["overall"]) - int(a["overall"]))
		if prev.has("v") and now.has("v") and int(now["v"]) > int(prev["v"]):
			ups.append([LABELS["kmh"], int(prev["v"]), int(now["v"])])
			score += VELO_W * float(int(now["v"]) - int(prev["v"]))
	else:
		var a: Dictionary = prev.get("b", {})
		var b: Dictionary = now.get("b", {})
		if a.is_empty() or b.is_empty():
			return {}
		for k: String in BAT_KEYS:
			if a.has(k) and b.has(k) and int(b[k]) > int(a[k]):
				var d := int(b[k]) - int(a[k])
				ups.append([LABELS[k], int(a[k]), int(b[k])])
				score += float(d)
				best = maxi(best, d)
	ups.sort_custom(func(x: Array, y: Array) -> bool: return int(x[2]) - int(x[1]) > int(y[2]) - int(y[1]))
	return {"score": score, "ups": ups, "best": best}


## 上がった能力の短い書き方（例「ミート 62→71・パワー 70→78」。多くても n 個）
static func ups_text(ups: Array, n := 3) -> String:
	var parts: Array = []
	for u: Array in ups.slice(0, n):
		parts.append("%s %d→%d" % [u[0], int(u[1]), int(u[2])])
	return "・".join(parts)


## 覚醒か（若くて大きく伸びた）
static func is_awakening(g: Dictionary, age: int) -> bool:
	if g.is_empty() or age > AWAKEN_AGE:
		return false
	return float(g["score"]) >= AWAKEN_SCORE or int(g["best"]) >= AWAKEN_ONE


## 春季キャンプのニュース（作業83）：この1年でいちばん伸びた選手（野手・投手。自球団でいちばんの選手も添える）と、覚醒した若手。
## team_of：選手ID → 球団（いま所属している選手だけ比べる）。my_team：自球団。News.article の配列を返す（前の写しが無ければ空）
## 覚醒の記事は伸びの点の高い順に、自球団は AWAKEN_NEWS_MINE 人・ほかの球団は AWAKEN_NEWS_OTHERS 人まで
const AWAKEN_NEWS_MINE := 2
const AWAKEN_NEWS_OTHERS := 2


static func camp_articles(year: int, team_of: Dictionary, my_team: String) -> Array:
	var prev := prev_values(year)
	if prev.is_empty():
		return []
	var rows: Array = []
	var real_year: bool = not _gd().synthetic.has(year)
	for id: String in team_of:
		if not prev.has(id):
			continue
		var p: Dictionary = _gd().player(id)
		if p.is_empty():
			continue
		var pitcher := bool(p.get("is_pitcher", false))
		var now := of(p)
		if real_year:
			var need := NEWS_MIN_OUTS if pitcher else NEWS_MIN_PA
			if int(prev[id].get("s", 0)) < need or int(now.get("s", 0)) < need:
				continue
		var g := growth_of(prev[id], now, pitcher)
		if g.is_empty() or float(g["score"]) <= 0.0:
			continue
		rows.append({"p": p, "team": str(team_of[id]), "pitcher": pitcher, "g": g, "age": Growth.age_at(p, year)})
	if rows.is_empty():
		return []
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["g"]["score"]) > float(b["g"]["score"]))
	var date := "%d-02-01" % year
	var out: Array = []
	var tops: Array = []
	for want_pitcher: bool in [false, true]:
		for r: Dictionary in rows:
			if bool(r["pitcher"]) == want_pitcher:
				tops.append(r)
				break
	var mine: Dictionary = {}
	for r: Dictionary in rows:
		if r["team"] == my_team:
			mine = r
			break
	var lines: Array = []
	for r: Dictionary in tops:
		lines.append("%sは%s：%s。" % ["投手" if r["pitcher"] else "野手", _who(r), ups_text(r["g"]["ups"])])
	if not mine.is_empty() and not tops.has(mine):
		lines.append("自球団では%s：%s。" % [_who(mine), ups_text(mine["g"]["ups"])])
	var names: Array = tops.map(func(r: Dictionary) -> String: return "%s（%s）" % [r["p"]["name"], _gd().short_name(r["team"])])
	var ids: Array = tops.map(func(r: Dictionary) -> String: return str(r["p"]["id"]))
	var teams: Array = tops.map(func(r: Dictionary) -> String: return str(r["team"]))
	if not mine.is_empty() and not tops.has(mine):
		ids.append(str(mine["p"]["id"]))
		teams.append(my_team)
	out.append(News.article(date, "camp", "この1年でいちばん伸びたのは%s" % "と".join(names),
		"前の年の開幕時点と比べて、能力がいちばん伸びた選手。" + "".join(lines), ids, teams))
	var others := 0
	var mine_n := 0
	for r: Dictionary in rows:
		if not is_awakening(r["g"], int(r["age"])) or tops.has(r):
			continue
		if r["team"] == my_team:
			if mine_n >= AWAKEN_NEWS_MINE:
				continue
			mine_n += 1
		else:
			if others >= AWAKEN_NEWS_OTHERS:
				continue
			others += 1
		out.append(News.article(date, "camp", "%s（%s）、覚醒の1年" % [r["p"]["name"], _gd().short_name(r["team"])],
			"%d歳の%sが大きく化けた。%s。" % [int(r["age"]), "投手" if r["pitcher"] else "野手", ups_text(r["g"]["ups"], 4)],
			[r["p"]["id"]], [r["team"]]))
	return out


static func _who(r: Dictionary) -> String:
	var age := int(r["age"])
	return "%s（%s%s）" % [r["p"]["name"], _gd().short_name(r["team"]), "、%d歳" % age if age > 0 else ""]
