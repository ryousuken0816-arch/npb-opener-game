class_name AmateurTournament
extends RefCounted
## 史実は出典付きの事実だけ。架空年は候補の所属と学校の実績による抽選。結果は GameState が保存する。

const EVENTS := {
	"spring": {"label": "センバツ", "category": "高校", "date": "04-10"},
	"college": {"label": "大学選手権", "category": "大学", "date": "06-30"},
	"shakai": {"label": "都市対抗", "category": "社会人", "date": "09-30"},
	"summer": {"label": "夏の甲子園", "category": "高校", "date": "08-31"},
	"jingu": {"label": "明治神宮大会（大学）", "category": "大学", "date": "11-30"},
}
static var _history: Dictionary = {}
static var _school_counts: Dictionary = {}


static func historical(year: int, event: String) -> Dictionary:
	if _history.is_empty():
		var data: Variant = GameData.read_data("amateur/tournaments.json")
		if data is Dictionary:
			_history = data
	return _history.get("years", {}).get(str(year), {}).get(event, {}).duplicate(true)


static func simulate(year: int, event: String, prospects: Array, seed_value: int) -> Dictionary:
	var info: Dictionary = EVENTS[event]
	var schools := {}
	if _school_counts.is_empty():
		var source: Variant = GameData.read_generated("fictional_draft.json")
		if source is Dictionary:
			for s: Dictionary in source.get("schools", []):
				_school_counts[s["name"]] = int(s["count"])
	for c: Dictionary in prospects:
		if _eligible(c, info["category"]):
			schools[c["school"]] = 1.0 + sqrt(float(_school_counts.get(c["school"], 1)))
	if schools.size() < 2:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# 指数競争による重み付き・重複なしの抽選。弱小校も必ず勝つ可能性を持つ。
	var ranking: Array = []
	for school: String in schools:
		ranking.append([school, -log(maxf(rng.randf(), 0.000001)) / float(schools[school])])
	ranking.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	var result := {"winner": ranking[0][0], "runner_up": ranking[1][0], "fictional": true,
		"publish_after": "%d-%s" % [year, info["date"]], "players": [], "notes": [], "sources": []}
	var runner_score := rng.randi_range(0, 5)
	result["score"] = "%d-%d" % [runner_score + rng.randi_range(1, 4), runner_score]
	var champion_pitcher := false
	var mvp := false
	var best_k := {"value": -1, "row": {}}
	var best_hr := {"value": 0, "row": {}}
	for c: Dictionary in prospects:
		if not _eligible(c, info["category"]):
			continue
		var champion: bool = c["school"] == result["winner"]
		var runner: bool = c["school"] == result["runner_up"]
		var title := "優勝メンバー" if champion else ("準優勝メンバー" if runner else "大会出場")
		if c["pitcher"] and champion and not champion_pitcher:
			title = "優勝投手"
			champion_pitcher = true
		if champion and not mvp:
			title += "・" + ("橋戸賞" if event == "shakai" else "大会MVP")
			mvp = true
		var stat := ""
		var peak: Dictionary = c.get("peak", {})
		var rounds := 4 if champion or runner else rng.randi_range(1, 3)
		var strikeouts := 0
		var hr := 0
		if c["pitcher"]:
			strikeouts = rounds * rng.randi_range(3, 6) + roundi(maxf(0.0, float(peak.get("k9", 50)) - 50.0) / 4.0)
			stat = "大会通算%d奪三振" % strikeouts
		else:
			var power := float(peak.get("power", 40.0))
			hr = rng.randi_range(1, mini(3, rounds)) if power >= 65.0 else (rng.randi_range(0, 1) if power >= 45.0 else 0)
			stat = "大会通算%d本塁打" % hr if hr > 0 else "大会通算%d安打" % rng.randi_range(rounds, rounds * 3)
		var row := {"name": c["name"], "school": c["school"], "title": title, "stat": stat,
			"boost": 0.12 if champion else (0.06 if runner else 0.0), "source_url": "", "moment": ""}
		if champion:
			if c["pitcher"] and "優勝投手" in title:
				row["moment"] = "決勝で完投勝利" if runner_score > 0 else "決勝で完封勝利"
			elif not c["pitcher"]:
				row["moment"] = "決勝打で頂点へ"
		if strikeouts > int(best_k["value"]) and c["pitcher"]:
			best_k = {"value": strikeouts, "row": row}
		if hr > int(best_hr["value"]):
			best_hr = {"value": hr, "row": row}
		result["players"].append(row)
	for record: Dictionary in [best_k, best_hr]:
		if record["row"].is_empty():
			continue
		var row: Dictionary = record["row"]
		row["title"] += "・" + ("大会最多奪三振" if record == best_k else "大会最多本塁打")
		row["boost"] = maxf(float(row["boost"]), 0.08)
	# 記事・候補の紹介には優勝・準優勝と個人賞だけ。無名の出場候補を一律に持ち上げない。
	result["players"] = result["players"].filter(func(p: Dictionary) -> bool: return float(p["boost"]) > 0.0)
	return result


static func _eligible(c: Dictionary, category: String) -> bool:
	if not c["fictional"] or c["category"] != category:
		return false
	# 元の所属一覧には「○○高卒」のような経歴の断片もある。企業チームとして扱わない。
	var school: String = c["school"]
	if school.ends_with("卒") or school.is_empty():
		return false
	if category != "社会人":
		return true
	# 社会人の元一覧には大学・独立・海外プロも混在するため、都市対抗の出場を出典で
	# 確認できる所属だけを使う。対象外の候補にも通常の候補紹介記事は出せる。
	historical(2008, "shakai")
	for competitions: Dictionary in _history.get("years", {}).values():
		var r: Dictionary = competitions.get("shakai", {})
		for key: String in ["winner", "runner_up"]:
			if school_key(school) == school_key(str(r.get(key, ""))):
				return true
	return false


## その年、その選手に実際に掲載済みの実績だけ（未来の大会は含めない）。
static func honors(results: Dictionary, year: int, full_name: String, school := "", through := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: String in EVENTS:
		var r: Dictionary = results.get("%d-%s" % [year, event], {})
		if not through.is_empty() and str(r.get("publish_after", "")) > through:
			continue
		for p: Dictionary in r.get("players", []):
			if LeagueRoster.norm_name(str(p["name"])) == LeagueRoster.norm_name(full_name) \
					and (school.is_empty() or school_key(p["school"]) == school_key(school)):
				var row := p.duplicate(true)
				row["event"] = event
				row["label"] = EVENTS[event]["label"]
				row["year"] = year
				row["fictional"] = r.get("fictional", false)
				out.append(row)
	return out


static func school_key(school: String) -> String:
	return school.replace("大学", "大").replace("高等学校", "").trim_suffix("高校").trim_suffix("高").replace("慶応", "慶應").replace("智辯", "智弁")


static func summary(results: Dictionary, year: int, full_name: String, school := "", through := "") -> String:
	var lines: Array[String] = []
	for h: Dictionary in honors(results, year, full_name, school, through):
		lines.append("%d年%s%s%s" % [year, h["label"], h["title"], "・" + str(h["stat"]) if not str(h.get("stat", "")).is_empty() else ""])
	return "／".join(lines)


static func bonus(results: Dictionary, year: int, full_name: String, school := "") -> float:
	var value := 0.0
	for h: Dictionary in honors(results, year, full_name, school):
		# 史実の順位に実績は織り込み済み。新しい評価の上乗せは架空年だけ。
		if h["fictional"]:
			value += float(h.get("boost", 0.0))
	return minf(value, 0.24)
