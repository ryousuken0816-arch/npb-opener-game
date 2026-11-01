class_name DraftExperts
extends RefCounted
## 有識者の指名予想（docs/AUTORUN.md 作業38）。
##
## 架空の評論家3人（EXPERTS。名前は架空、好みに個性）が、ドラフトの前に
## (a) 全体の順位予想（上位 RANK_COUNT 人）と (b) 12球団の1位予想（同じ候補に複数球団＝競合の予想）を出す。
## もとは「当時の評価」（Draft の hyouka と同じ値：史実の指名順位・1位の競合数。2026年は data/amateur/ の有識者の
## 格付けを混ぜ、2027年は格付けそのもの、2028年〜は架空の候補の評価）に、評論家ごとの好み（高校生・即戦力・投手など）と
## 少しのノイズを足したもの。球団の1位予想は、その評論家の上位から球団の守備位置の不足（編成の人数）を少し見て選ぶ。
## 実際の CPU の指名は Draft のまま（将来性・目玉・守備位置の不足）なので、予想どおりにならないことが多い。
## 予想は作ったら DraftBoard.predictions に残す（セーブに入る）。候補は名前のキー（LeagueRoster.norm_name）で持つ

const EXPERTS := [
	{"name": "沢渡 一馬", "title": "元スカウト・野球評論家", "style": "高校生の素材型を高く買う",
		"career": {"高校生": 0.55, "社会人": -0.2}, "pitcher": 0.0, "noise": 0.35, "need": 0.4},
	{"name": "北条 恭平", "title": "スポーツ紙のドラフト担当デスク", "style": "即戦力の大学生・社会人の投手を重視",
		"career": {"高校生": -0.3, "大学生": 0.25, "社会人": 0.35}, "pitcher": 0.3, "noise": 0.3, "need": 0.8},
	{"name": "早瀬 みずき", "title": "アマ野球ライター", "style": "評判に忠実で、打てる野手を推す",
		"career": {}, "pitcher": -0.2, "noise": 0.2, "need": 0.6},
]
## 全体の順位予想の人数
const RANK_COUNT := 30
## 球団の1位予想を選ぶ範囲（その評論家の順位予想の上位から）
const FIRST_POOL := 10
## 1位予想：球団ごとの迷いと、先にその候補を予想した球団1つごとに引く値（実際の CPU の COMPETE_PENALTY より弱い）
const FIRST_NOISE := 0.35
const FIRST_COMPETE := 0.25
## 守備位置の不足の見方（Draft._need_bonus と同じ式・同じ目安の割合）
const NEED_MAX := 0.5
const NEED_MIN := -0.3


## その年の候補の要点（予想の材料）[{key, name, pos, career, school, hyouka, ikusei}]。Draft.setup と同じ当時の評価
static func prospects(year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rows := Draft.draft_rows(year)
	if rows.is_empty():
		return result
	var amateur_year := bool(rows[0].get("amateur", false))
	var first := Draft._first_round_info(year)
	var scout := {}
	if not amateur_year:
		for a in Draft.amateur_rows(year):
			scout[LeagueRoster.norm_name(a["name"])] = a["grade"]
	var seen := {}
	for d: Dictionary in rows:
		var key := LeagueRoster.norm_name(d["name"])
		if seen.has(key):
			continue
		seen[key] = true
		var r := Draft.round_number(d.get("round", ""))
		var ikusei := bool(d.get("ikusei", false))
		var hyouka := 0.0
		if bool(d.get("amateur", false)):
			hyouka = Draft.grade_value(str(d.get("grade", "")))
			if d.has("as_round"):
				hyouka = Draft.hyouka_value(int(d["as_round"]), bool(d["as_ikusei"]), maxi(1, int(d["bids"])), false)
				ikusei = bool(d["as_ikusei"])
		else:
			var fr: Dictionary = first.get(key, {})
			var bids := int(fr.get("bids", 1)) if r == 1 and not ikusei else 0
			hyouka = Draft.hyouka_value(r, ikusei, bids, int(fr.get("wave", 1)) >= 2)
			if scout.has(key):
				hyouka = lerpf(hyouka, Draft.grade_value(str(scout[key])), Draft.SCOUT_HYOUKA_WEIGHT)
		var school := str(d.get("school", ""))
		result.append({"key": key, "name": d["name"], "pos": str(d.get("pos", "")), "school": school,
			"career": Draft.career_of(school), "hyouka": hyouka, "ikusei": ikusei})
	return result


## 予想を作る。counts：球団 → {守備位置の4区分: 人数}（今の編成）、teams：12球団。
## {year, date, names: {key: 名前}, info: {key: {school, pos, career}}, experts: [{ranking: [key], firsts: {球団: key}}]}
static func predict(year: int, date: String, counts: Dictionary, teams: Array) -> Dictionary:
	var pros := prospects(year)
	var result := {"year": year, "date": date, "names": {}, "info": {}, "experts": []}
	if pros.is_empty():
		return result
	for c in pros:
		result["names"][c["key"]] = c["name"]
		result["info"][c["key"]] = {"school": c["school"], "pos": c["pos"], "career": c["career"]}
	for i in EXPERTS.size():
		var ex: Dictionary = EXPERTS[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("experts:%d:%d" % [year, i])
		var scored: Array = []
		for c in pros:
			if c["ikusei"]:
				continue
			var s: float = float(c["hyouka"]) + float(ex["career"].get(c["career"], 0.0)) \
				+ (float(ex["pitcher"]) if c["pos"] == "投手" else 0.0) + rng.randfn(0.0, float(ex["noise"]))
			scored.append([c["key"], s, c["pos"]])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[1] == b[1] else a[1] > b[1])
		var ranking: Array = []
		for item: Array in scored.slice(0, RANK_COUNT):
			ranking.append(item[0])
		var pool: Array = scored.slice(0, FIRST_POOL)
		var firsts := {}
		var taken := {}
		for t: String in teams:
			var best := ""
			var best_v := -INF
			for item: Array in pool:
				var v: float = float(item[1]) + float(ex["need"]) * need_bonus(counts.get(t, {}), item[2]) \
					+ rng.randfn(0.0, FIRST_NOISE) - FIRST_COMPETE * int(taken.get(item[0], 0))
				if v > best_v:
					best_v = v
					best = item[0]
			if not best.is_empty():
				firsts[t] = best
				taken[best] = int(taken.get(best, 0)) + 1
		result["experts"].append({"ranking": ranking, "firsts": firsts})
	return result


## 守備位置の不足（Draft._need_bonus と同じ式。重みは掛けない）
static func need_bonus(team_counts: Dictionary, group: String) -> float:
	var total := 0
	for g: String in team_counts:
		total += int(team_counts[g])
	if total <= 0:
		return 0.0
	var target: float = total * float(Draft.NEED_SHARE.get(group, 0.2))
	if target <= 0.0:
		return 0.0
	return clampf((target - float(team_counts.get(group, 0))) / target, NEED_MIN, NEED_MAX)


## 3人の順位予想を合わせた順位（キー → 1〜RANK_COUNT）。平均の順位（予想に入っていなければ RANK_COUNT＋10 位とみなす）の順
static func consensus(pred: Dictionary) -> Dictionary:
	var total := {}
	var experts: Array = pred.get("experts", [])
	for ex: Dictionary in experts:
		for key: String in ex["ranking"]:
			total[key] = 0.0
	for key: String in total:
		for ex: Dictionary in experts:
			var i: int = ex["ranking"].find(key)
			total[key] += float(i + 1 if i >= 0 else RANK_COUNT + 10)
	var keys: Array = total.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a < b if total[a] == total[b] else total[a] < total[b])
	var result := {}
	for i in mini(keys.size(), RANK_COUNT):
		result[keys[i]] = i + 1
	return result


## 球団の1位予想を評論家ごとに [key]（EXPERTS の順）
static func firsts_of(pred: Dictionary, team: String) -> Array:
	var result: Array = []
	for ex: Dictionary in pred.get("experts", []):
		result.append(str(ex["firsts"].get(team, "")))
	return result


## 評論家の1位予想で、その候補に入札すると予想した球団 [球団]
static func predicted_bidders(pred: Dictionary, expert_index: int, key: String) -> Array:
	var result: Array = []
	var ex: Dictionary = pred["experts"][expert_index]
	for t: String in ex["firsts"]:
		if ex["firsts"][t] == key:
			result.append(t)
	return result


## 実際の1回目の入札（球団 → 候補のキー）。抽選で外れた球団の入札も含む（Draft の指名の記録と抽選の記録から）
static func actual_first_bids(d: Draft) -> Dictionary:
	var result := {}
	if d == null:
		return result
	for rec in d.picks:
		if int(rec["round"]) == 1 and not rec["ikusei"] and int(rec.get("wave", 0)) == 1:
			result[rec["team"]] = LeagueRoster.norm_name(str(d.by_id[rec["id"]]["name"]))
	for lot in d.lotteries:
		if int(lot["wave"]) != 1:
			continue
		for t: String in lot["teams"]:
			result[t] = LeagueRoster.norm_name(str(d.by_id[lot["id"]]["name"]))
	return result


## 1回目の入札が締まった後か（予想の答え合わせを出せる）
static func first_wave_done(d: Draft) -> bool:
	return d != null and (d.wave > 1 or d.stage != Draft.Stage.FIRST)


# --- 記事 ----------------------------------------------------------------------------------

## ドラフト直前号の記事 [[見出し, 本文], ...]（12球団の1位予想・評論家ごとの順位予想）
static func preview_articles(pred: Dictionary) -> Array:
	var names: Dictionary = pred.get("names", {})
	var experts: Array = pred.get("experts", [])
	if experts.is_empty():
		return []
	var votes := {}
	var lines: Array[String] = []
	var teams: Array = experts[0]["firsts"].keys()
	for t: String in teams:
		var parts: Array[String] = []
		var by_key := {}
		for i in experts.size():
			var key := str(experts[i]["firsts"].get(t, ""))
			if key.is_empty():
				continue
			votes[key] = int(votes.get(key, 0)) + 1
			if not by_key.has(key):
				by_key[key] = []
			by_key[key].append(_family(EXPERTS[i]["name"]))
		for key: String in by_key:
			parts.append("%s（%s）" % [names.get(key, key), "・".join(by_key[key])])
		lines.append("%s：%s" % [GameData.short_name(t), "／".join(parts)])
	var top_key := ""
	for key: String in votes:
		if top_key.is_empty() or int(votes[key]) > int(votes[top_key]):
			top_key = key
	var most := 0
	for i in experts.size():
		most = maxi(most, predicted_bidders(pred, i, top_key).size())
	var year := int(pred.get("year", 0))
	var headline := "有識者3人の12球団1位予想　%s" % names.get(top_key, top_key)
	headline += "に最大%d球団の競合か" % most if most >= 2 else "が軸"
	var body := "%d年のドラフト会議を前に、評論家3人が12球団の1位指名を予想した（カッコ内は予想した評論家）。\n" % year
	body += "\n".join(lines)
	body += "\n※予想は評判（当時の評価）が中心。実際の指名は各球団の補強ポイントや将来性の見立てで変わることも多い。"
	var result: Array = [[headline, body]]
	var rank_lines: Array[String] = []
	for i in experts.size():
		var ex: Dictionary = EXPERTS[i]
		var top: Array[String] = []
		for j in mini(5, experts[i]["ranking"].size()):
			top.append("%d.%s" % [j + 1, names.get(experts[i]["ranking"][j], "")])
		rank_lines.append("■%s（%s。%s）\n%s" % [ex["name"], ex["title"], ex["style"], "　".join(top)])
	result.append(["評論家3人のドラフト順位予想　上位5人", "\n".join(rank_lines)])
	return result


## ドラフトのあとの答え合わせの記事 [見出し, 本文]（評論家ごとの1位予想の的中・順位予想の上位が1位で消えたか・
## 予想を覆した入札）。自球団の予想と実際も書く
static func review_article(pred: Dictionary, d: Draft, user_team: String) -> Array:
	var actual := actual_first_bids(d)
	var names: Dictionary = pred.get("names", {})
	var experts: Array = pred.get("experts", [])
	if experts.is_empty() or actual.is_empty():
		return []
	var first_final := {}
	for rec in d.picks:
		if int(rec["round"]) == 1 and not rec["ikusei"]:
			first_final[LeagueRoster.norm_name(str(d.by_id[rec["id"]]["name"]))] = rec["team"]
	var lines: Array[String] = []
	var best := -1
	var best_hits := -1
	for i in experts.size():
		var hits: Array[String] = []
		for t: String in actual:
			if str(experts[i]["firsts"].get(t, "")) == actual[t]:
				hits.append(GameData.short_name(t))
		var top12 := 0
		for key: String in experts[i]["ranking"].slice(0, 12):
			if first_final.has(key):
				top12 += 1
		if hits.size() > best_hits:
			best_hits = hits.size()
			best = i
		var ex: Dictionary = EXPERTS[i]
		lines.append("■%s（%s）：1位予想は%d球団的中%s。順位予想の上位12人のうち%d人が1位で指名された" % [
			ex["name"], ex["title"], hits.size(), "（%s）" % "・".join(hits) if not hits.is_empty() else "", top12])
	var cons := consensus(pred)
	var upsets: Array[String] = []
	for t: String in actual:
		var key: String = actual[t]
		var rank := int(cons.get(key, 0))
		if rank == 0 or rank > 12:
			upsets.append("%sの%s（予想%s）" % [GameData.short_name(t), names.get(key, key), "%d位" % rank if rank > 0
				else "圏外"])
	if not upsets.is_empty():
		lines.append("予想を覆した1位入札：" + "、".join(upsets.slice(0, 5)))
	if actual.has(user_team):
		var mine: Array[String] = []
		for key: String in firsts_of(pred, user_team):
			if not key.is_empty() and str(names.get(key, key)) not in mine:
				mine.append(names.get(key, key))
		lines.append("%sの1位：予想 %s → 実際の入札 %s" % [GameData.short_name(user_team), "・".join(mine),
			names.get(actual[user_team], actual[user_team])])
	var headline := ""
	if best_hits <= 0:
		headline = "評論家の1位予想、的中ゼロ　各球団の事情で波乱のドラフト"
	else:
		headline = "評論家%s氏の1位予想が%d球団的中　%d年ドラフトの答え合わせ" % [EXPERTS[best]["name"], best_hits, d.year]
	return [headline, "\n".join(lines)]


static func _family(full_name: String) -> String:
	return full_name.get_slice(" ", 0)
