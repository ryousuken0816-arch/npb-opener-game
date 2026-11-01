class_name AmateurNews
extends RefCounted
## ドラフト候補のアマ時代の活躍ニュース（docs/AUTORUN.md 作業21、docs/SPEC.md「ドラフト候補には甲子園・アマ時代の活躍ニュース」）。
##
## シーズン中の春（センバツ）・初夏（大学選手権）・夏（都市対抗・甲子園）・秋（大学の秋季リーグ＝ドラフト直前）に、
## その年の秋のドラフト候補の記事を号（"<年>-amateur-<段階>"）にまとめて載せる（種類 amateur。最初の記事は速報の帯にも出す）。
## 候補の情報：
## - 2026・2027年：data/amateur/<年>.json（実在の選手。主な大会の成績 highlights・紹介文・報道での評価・最速）
## - 2028年〜：架空の候補（GameState.draft_class、作業22）。大会の成績はピークの能力から作る（架空）。転生選手は「〇〇の再来」
## - 2008〜2025年：ドラフト会議の一覧（出身校・守備位置・史実の順位と1位の競合）からの簡単な紹介（大会の成績は無い）
## メジャー志望の表明（作業26）は秋の号に載せる。記事の選手は GameData.player で引ければ紙面から選手詳細を開ける

const STAGES := [
	{"key": "spring", "date": "03-31", "title": "%d年 センバツ号", "label": "センバツ", "categories": ["高校"], "count": 3},
	{"key": "college", "date": "06-15", "title": "%d年 大学選手権号", "label": "大学選手権", "categories": ["大学"], "count": 2},
	{"key": "shakai", "date": "07-28", "title": "%d年 都市対抗号", "label": "都市対抗", "categories": ["社会人", "独立"],
		"count": 2},
	{"key": "summer", "date": "08-23", "title": "%d年 夏の甲子園号", "label": "夏の甲子園", "categories": ["高校"], "count": 4},
	{"key": "fall", "date": "10-08", "title": "%d年 ドラフト直前号", "label": "秋季リーグ",
		"categories": ["大学", "社会人", "独立", "高校"], "count": 5},
]
## 実在の選手の主な成績（highlights）のうち、その段階の記事に使う言葉
const STAGE_WORDS := {
	"spring": ["センバツ", "春"], "college": ["選手権", "春", "リーグ"], "shakai": ["都市対抗", "日本選手権", "リーグ"],
	"summer": ["甲子園", "夏", "U-18", "代表"], "fall": ["秋", "神宮", "リーグ", "代表"],
}
const GRADE_ORDER := {"S": 4.0, "A": 3.0, "B": 2.0, "C": 1.0, "D": 0.0}
## 上位の候補ほど選ばれやすく（評価にこの幅の乱数を足して並べる）
const PICK_JITTER := 1.2

var gs: Node


func _init(game_state: Node) -> void:
	gs = game_state


## その段階の記事を載せる（GameState が日付を見て1回だけ呼ぶ）。載せた記事の数
func post_stage(year: int, stage: Dictionary) -> int:
	var all := prospects(year)
	if all.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("amateur:%d:%s:%s" % [year, stage["key"], gs.team])
	var pool: Array = []
	for c: Dictionary in all:
		if c["category"] in stage["categories"]:
			pool.append([c, float(GRADE_ORDER.get(c["grade"], 0.0)) + rng.randf() * PICK_JITTER
				+ (3.0 if not c["reincarnation"].is_empty() else 0.0)])
	pool.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var chosen: Array = []
	for item: Array in pool.slice(0, int(stage["count"])):
		chosen.append(item[0])
	var mlb: Array = []
	if stage["key"] == "fall":
		for c: Dictionary in all:
			if c["mlb"]:
				mlb.append(c)
	if chosen.is_empty() and mlb.is_empty():
		return 0
	var key := "%d-amateur-%s" % [year, stage["key"]]
	var date := "%d-%s" % [year, stage["date"]]
	gs.news.open_issue(key, stage["title"] % year, date, year)
	var n := 0
	for c: Dictionary in mlb:
		var body := "%s（%s）の%s。%s" % [c["name"], c["school"], c["pos"], c["mlb_note"] if not c["mlb_note"].is_empty()
			else "高卒・大卒からのメジャー挑戦を表明した"]
		body += "\nドラフトで指名した球団は、入団の説得に臨むことになる。"
		gs.post_news(News.article(date, "amateur", "%sの%s、メジャー挑戦を表明" % [c["school"], c["name"]], body,
			_ids(c)), key, n == 0)
		n += 1
	for c: Dictionary in chosen:
		var a := article(c, stage, year, rng)
		gs.post_news(News.article(date, "amateur", a[0], a[1], _ids(c)), key, n == 0)
		n += 1
	return n


## 1本分 [見出し, 本文]
func article(c: Dictionary, stage: Dictionary, year: int, rng: RandomNumberGenerator) -> Array:
	var hl := _highlight(c, stage, rng)
	var rei: Dictionary = c["reincarnation"]
	var headline := ""
	if not rei.is_empty():
		headline = "「%sの再来」%sの%s、%s" % [rei["name"], c["school"], _family(c["name"]), hl if not hl.is_empty()
			else "スカウトの熱視線"]
	elif not hl.is_empty():
		headline = "%sの%s、%s" % [c["school"], c["name"], hl]
	else:
		headline = "%sの注目株　%sの%s" % [stage["label"], c["school"], c["name"]]
	var lines: Array[String] = []
	var who := "%s（%s%s）の%s" % [c["school"], c["category"], c["grade_text"], c["pos"]]
	lines.append(who + ("。" + c["intro"] if not c["intro"].is_empty() else "。"))
	if not rei.is_empty():
		lines.append("投げ方・打ち方が全盛期の%s（%d年・%s）にそっくりだと話題に。" % [rei["name"], int(rei["peak_year"]),
			GameData.short_name(str(rei["peak_team"]))])
	if not c["evaluation"].is_empty():
		lines.append(c["evaluation"])
	if not c["highlights"].is_empty() and c["fictional"] == false:
		lines.append("主な実績：" + "／".join(c["highlights"].slice(0, 3)))
	lines.append("%d年秋のドラフトの%s。" % [year, c["projected"]])
	return [headline, "\n".join(lines)]


## その年のドラフト候補（記事の材料）。{name, school, category, grade_text, pos, pitcher, kmh, grade, intro,
## evaluation, highlights, projected, mlb, mlb_note, id, fictional, reincarnation, peak}
func prospects(year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var fic: Array = gs.draft_class(year)
	if not fic.is_empty():
		for p: Dictionary in fic:
			result.append(_from_fictional(p))
		return result
	var ama: Variant = GameData.read_data("amateur/%d.json" % year)
	if ama is Dictionary:
		for a: Dictionary in ama.get("players", []):
			result.append(_from_amateur(a, year))
		return result
	var first := {}
	var fr: Variant = GameData.read_data("draft_first_round.json")
	if fr is Array:
		for d: Dictionary in fr:
			if int(d.get("draft_year", 0)) == year:
				first[LeagueRoster.norm_name(str(d.get("name", "")))] = int(d.get("bids", 1))
	for d: Dictionary in Draft.draft_rows(year):
		result.append(_from_history(d, int(first.get(LeagueRoster.norm_name(d["name"]), 1))))
	return result


func _from_fictional(p: Dictionary) -> Dictionary:
	var am: Dictionary = p["amateur"]
	var kmh: Variant = Growth._value(p, "P", "velocity") if Growth._side(p) == "P" else null
	var mi: Variant = am.get("mlb_intent")
	return {"name": p["name"], "school": am["school"], "category": am["category"], "grade_text": am.get("grade_text", ""),
		"pos": Draft._pos_of(p), "pitcher": Growth._side(p) == "P", "kmh": roundi(float(kmh)) + 3 if kmh != null else 0,
		"grade": am["grade"], "intro": am.get("intro", ""), "evaluation": _fictional_eval(am), "highlights": [],
		"projected": am.get("projected", ""), "mlb": mi is Dictionary and bool(mi.get("stated", false)),
		"mlb_note": str(mi.get("note", "")) if mi is Dictionary else "", "id": p["id"], "fictional": true,
		"reincarnation": am.get("reincarnation", {}), "peak": p.get("growth", {}).get("peak", {}),
		"type": am.get("type", "")}


func _from_amateur(a: Dictionary, year: int) -> Dictionary:
	var scout: Dictionary = a.get("scout", {}) if a.get("scout") is Dictionary else {}
	var mi: Variant = a.get("mlb_intent")
	var category := str(a.get("category", ""))
	return {"name": a["name"], "school": a.get("school", ""), "category": category,
		"grade_text": str(a.get("grade", "")) if a.get("grade") != null else "", "pos": a.get("pos", ""),
		"pitcher": a.get("pos", "") == "投手", "kmh": int(a.get("max_kmh", 0)) if a.get("max_kmh") != null else 0,
		"grade": str(scout.get("grade", a.get("eval_rank", "C"))), "intro": str(a.get("intro", "")),
		"evaluation": str(a.get("evaluation", "")), "highlights": a.get("highlights", []),
		"projected": str(a.get("projected", "") if a.get("projected") != null else _projected_of(str(a.get("round", "")))),
		"mlb": mi is Dictionary and bool(mi.get("stated", false)), "mlb_note": str(mi.get("note", "")) if mi is Dictionary else "",
		"id": "ama%d:%s" % [year, LeagueRoster.norm_name(a["name"])], "fictional": bool(a.get("fictional", false)),
		"reincarnation": {}, "peak": {}, "type": str(scout.get("type", ""))}


func _from_history(d: Dictionary, bids: int) -> Dictionary:
	var rnd := Draft.round_number(str(d.get("round", "")))
	var ikusei := bool(d.get("ikusei", false))
	var grade := "D"
	if not ikusei:
		grade = ("S" if bids >= 2 else "A") if rnd == 1 else ("B" if rnd <= 3 else "C")
	var school := str(d.get("school", ""))
	var category := Draft.career_of(school).trim_suffix("生")
	var eval_text := ""
	if grade == "S":
		eval_text = "複数球団の1位指名が確実視される世代の目玉。"
	elif grade == "A":
		eval_text = "1位指名の候補に名前が挙がる。"
	return {"name": d["name"], "school": school, "category": category, "grade_text": "", "pos": d.get("pos", ""),
		"pitcher": d.get("pos", "") == "投手", "kmh": 0, "grade": grade, "intro": "", "evaluation": eval_text,
		"highlights": [], "projected": _projected_of(("育成" if ikusei else "") + str(rnd)), "mlb": false, "mlb_note": "",
		"id": "", "fictional": false, "reincarnation": {}, "peak": {}, "type": ""}


static func _projected_of(round_text: String) -> String:
	if round_text.begins_with("育成"):
		return "育成候補"
	var r := Draft.round_number(round_text) if not round_text.is_empty() else 3
	if r == 1:
		return "1位候補"
	return "上位候補" if r <= 3 else "中位〜下位候補"


static func _fictional_eval(am: Dictionary) -> String:
	match str(am.get("grade", "")):
		"S":
			return "複数球団の1位競合が確実視される、世代の目玉。"
		"A":
			return "1位指名の候補として、各球団のスカウトが視察を重ねる。"
		"B":
			return "上位指名が有力。"
	return ""


## 記事の見出しに使う成績（実在の選手は集めた実績から、架空の選手は能力から作る。無ければ空）
func _highlight(c: Dictionary, stage: Dictionary, rng: RandomNumberGenerator) -> String:
	if not c["fictional"] or c["peak"].is_empty():
		var words: Array = STAGE_WORDS.get(stage["key"], [])
		for h: Variant in c["highlights"]:
			var text := str(h)
			for w: String in words:
				if w in text:
					return _short(text)
		return "最速%dkmの快速球" % int(c["kmh"]) if c["pitcher"] and int(c["kmh"]) >= 150 else ""
	var label: String = stage["label"]
	var peak: Dictionary = c["peak"]
	if c["pitcher"]:
		var kmh := int(c["kmh"])
		var options := ["%sで最速%dkm" % [label, kmh], "%sで%d奪三振の快投" % [label, rng.randi_range(9, 16)],
			"%sで完封勝利" % label]
		if float(peak.get("bb9", 0.0)) >= 70.0:
			options.append("%sで無四球完投" % label)
		return options[rng.randi_range(0, options.size() - 1)]
	var options := ["%sで%d安打" % [label, rng.randi_range(6, 11)]]
	if float(peak.get("power", 0.0)) >= 65.0:
		options.append("%sで%d本塁打" % [label, rng.randi_range(2, 4)])
		options.append("%sで特大の一発" % label)
	if float(peak.get("speed", 0.0)) >= 68.0:
		options.append("%sで%d盗塁" % [label, rng.randi_range(3, 6)])
	if float(peak.get("meet", 0.0)) >= 65.0:
		options.append("%sで打率.%d" % [label, rng.randi_range(450, 650)])
	return options[rng.randi_range(0, options.size() - 1)]


## 実績の文を見出し向けに短く（括弧の中と年の前置きを省く）
static func _short(text: String) -> String:
	var t := text
	var k := t.find("（")
	if k > 0:
		t = t.substr(0, k)
	var parts := t.split(" ", false)
	if parts.size() >= 2 and "年" in parts[0] and parts[0].length() <= 8:
		t = " ".join(parts.slice(1))
	return t.substr(0, 28)


static func _family(full_name: String) -> String:
	return full_name.get_slice(" ", 0)


func _ids(c: Dictionary) -> Array:
	var id: String = c["id"]
	if id.is_empty() or GameData.player(id).is_empty():
		return []
	return [id]
