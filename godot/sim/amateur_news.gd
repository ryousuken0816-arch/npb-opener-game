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
		"categories": ["大学", "社会人", "独立", "専門", "高校"], "count": 5},
]
## 実在の選手の主な成績（highlights）のうち、その段階の記事に使う言葉
const STAGE_WORDS := {
	"spring": ["センバツ", "春"], "college": ["選手権", "春", "リーグ"], "shakai": ["都市対抗", "日本選手権", "リーグ"],
	"summer": ["甲子園", "夏", "U-18", "代表"], "fall": ["秋", "神宮", "リーグ", "代表"],
}
const GRADE_ORDER := {"S": 4.0, "A": 3.0, "B": 2.0, "C": 1.0, "D": 0.0}
## 上位の候補ほど選ばれやすく（評価にこの幅の乱数を足して並べる）
const PICK_JITTER := 1.2

## 見出し・導入は号の中で重ねず、特徴・区分・評価ごとの文を組み合わせる。
const HEADLINES := ["{school}・{name}に熱視線！{hook}", "{hook}――{school}の{name}、秋への切り札",
	"主役候補はこの男　{school}・{name}、{hook}", "{school}に光る原石！{name}の{feature}",
	"ドラフト戦線に名乗り　{school}・{name}、{hook}", "見逃すな、この才能！{school}・{name}の{feature}",
	"{name}を追え！{school}が送り出す{role}", "秋の一票を引き寄せろ　{school}・{name}の{feature}"]
const LEADS := ["{context}。{school}の{name}（{category}{grade_text}・{pos}）を取り上げる。",
	"{school}からプロへの道をうかがう{name}。{context}、{pos}としての持ち味を整理した。",
	"{name}の名前を覚えておきたい。{context}、{school}の{pos}に焦点を当てる。",
	"秋の指名まで、何を見極めるか。{context}に合わせ、{school}・{name}の可能性を探る。",
	"候補の横顔を追う今回の主役は、{school}の{name}。{context}を入り口に、持ち味に迫る。",
	"{context}。{school}の{name}が目指すのは、{category}から次の舞台へ進む道だ。",
	"スカウトの見立ては一つではない。{context}、{school}・{name}に求められる役割を探る。",
	"指名の決め手はどこにあるのか。{context}、{school}の{name}をチェックする。"]
const CONTEXTS := {
	"spring": ["センバツの季節、今年の高校生候補を展望する", "春の聖地に注目が集まる時期", "春から始まる高校球界の候補探し"],
	"college": ["大学日本一を争う季節", "大学選手権の時期、大学生の実力を見極める", "春の大学球界を振り返る候補特集"],
	"shakai": ["都市対抗の季節、社会人の即戦力に目を向ける", "黒獅子旗を争う季節", "社会人球界の候補を点検する夏"],
	"summer": ["夏の甲子園をめぐる話題が尽きない時期", "高校球界の夏を振り返る候補特集", "最後の夏から秋の指名へ目が移る季節"],
	"fall": ["運命のドラフトが近づく秋", "各球団の指名方針が問われるドラフト直前", "入札と指名順の駆け引きが始まる季節"],
}
const CATEGORY_LINES := {
	"高校": ["完成度だけでなく、プロで育つ余地まで追いたい高校生だ。", "次の舞台でどこまで伸びるか。高校生ならではの成長の余白も選考のポイントになる。", "進路と育成方針を重ねて考えたい高校生候補。目先の結果だけでは測れない。"],
	"大学": ["大学からプロへ。技術の完成度と、一軍で通用する武器の両方が問われる。", "大学で培った技術を、プロの速さの中で再現できるかに注目だ。", "同世代との比較に加え、入団後の役割まで描けるかが指名の鍵になる。"],
	"社会人": ["社会人で積んだ経験を、プロの勝負にどう生かすか。即戦力としての役割に注目だ。", "企業チームからプロへ。持ち味の明確さが編成の判断を左右する。", "短期決戦と日々の鍛錬で磨く技術。必要な戦力に合致すれば、指名が近づく。"],
	"専門": ["専門学校の2年間で力を伸ばした候補。数少ない実戦の機会で示した持ち味に注目だ。", "大学とも企業チームとも違う道からプロを目指す。素材の伸びしろをどう見るか。", "専門学校から指名を待つ候補。限られた舞台での評価が、指名の鍵を握る。"],
	"独立": ["独立リーグから支配下への道を狙う。所属リーグでの経験と、一芸の使い道を追いたい。", "全国大会の看板に頼らず、独立の舞台からプロを目指す候補。持ち味が指名の扉を開くか。", "独立リーグで挑むもう一つのプロへの道。役割を絞った獲得も選択肢になる。"],
}
const POSITION_LINES := {
	"投手": ["直球と変化球の組み合わせ、そして制球が評価の分かれ目になる。", "先発で長い回を任せるか、短い回で持ち味を生かすか。起用のイメージも大切だ。", "球速だけでなく、打者との勝負の組み立てにも注目したい。"],
	"捕手": ["打つだけでなく、捕球・送球と投手を支える役割も背負うポジションだ。", "扇の要としての守りと打力。その両立ができれば編成上の価値は高い。", "捕手を育てたい球団にとって、長い目で見ておきたい存在だ。"],
	"内野手": ["内野のどこを任せるか。打力と守備範囲を合わせて獲得後の配置を考えたい。", "打席での持ち味に加え、内野を守る確かさが出場機会につながる。", "二遊間か、打力を生かすコーナーか。適性の見極めが編成の腕の見せどころになる。"],
	"外野手": ["打力と走力、守備での貢献。外野の一角を任せるための武器が問われる。", "広い外野を守れるか、打線の核を担うか。球団ごとに期待する役割は変わる。", "バットだけでなく、走塁と外野守備も含めて一軍への道を探りたい。"],
}
const OUTLOOKS := {
	"S": ["今秋の目玉候補。1位入札が重なれば、交渉権は抽選に委ねられる。", "複数球団が1位で狙う可能性を持つ候補。競合を覚悟して踏み込む球団が出るか。", "世代を代表する存在として、1位の入札先を左右しそうだ。競合の読みも難しくなる。"],
	"A": ["1位候補の一角。単独指名を狙うか、競合へ踏み込むか、球団の判断が注目される。", "1位指名を視野に置く存在。ほかの目玉候補との兼ね合いで入札が動きそうだ。", "1巡目から名前が挙がる候補。指名順と補強ポイントが鍵を握る。"],
	"B": ["上位指名が視野に入る。2巡目以降の指名順が、縁のある球団を分けるかもしれない。", "上位をうかがう候補。先に確保するか、次の巡目まで待つかは悩ましい。", "上位の補強リストに入る存在。同じ守備位置を欲する球団の動向に注意したい。"],
	"C": ["中位以降で光る候補。目玉が消えたあとの指名で、編成の目利きが試される。", "中位から下位の指名で、持ち味に賭ける球団を待つ。", "順位の看板より、チームに足りない武器があるか。中位以降の候補として追いたい。"],
	"D": ["下位・育成からの挑戦も視野に入る。磨く武器を絞れれば、掘り出し物になる可能性がある。", "大きな評判がなくても、編成に合う一芸があれば指名の余地はある。育成も含めた判断だ。", "掘り出し物を探すなら見ておきたい一人。入団後の伸びを見越した下位・育成指名に注目が集まる。"],
}
const SCOUT_LINES := {
	"投手": ["直球は打者の手元で伸びる", "腕の振りに迫力がある", "勝負球で空振りを奪える", "マウンド度胸が光る", "低めへ投げ切れる", "長い回を任せたくなる", "変化球の切れが魅力", "打者に向かう姿勢がいい", "投げるたびに良くなっている"],
	"捕手": ["送球の強さに目を奪われる", "投手を引っ張る声がいい", "捕ってからが速い", "打席でも勝負強い", "守りの要になれる", "捕球の柔らかさが魅力", "肩だけでなく判断もいい", "投手を支える姿が頼もしい", "攻守でチームを動かせる"],
	"内野手": ["打球への一歩が速い", "スイングに迷いがない", "送球までの動きが滑らか", "難しい打球にも食らいつく", "広い守備範囲が魅力", "打席での対応力が光る", "堅実な守りが頼もしい", "鋭い打球を飛ばせる", "勝負どころで目が離せない"],
	"外野手": ["打球を追う一歩が速い", "思い切りのいいスイングだ", "広い外野を駆け回れる", "送球の強さが魅力", "走塁で相手を揺さぶれる", "打球の伸びが素晴らしい", "攻守にスピードがある", "一瞬で流れを変えられる", "外野から強い送球を見せる"],
}

var gs: Node


func _init(game_state: Node) -> void:
	gs = game_state


## 決勝の前に結果を載せない。候補を紹介する従来の号とは別の「大会結果号」にする。
func post_results_through(year: int, date: String) -> void:
	var events: Array = AmateurTournament.EVENTS.keys()
	events.sort_custom(func(a: String, b: String) -> bool:
		return str(AmateurTournament.EVENTS[a]["date"]) < str(AmateurTournament.EVENTS[b]["date"]))
	for event: String in events:
		var info: Dictionary = AmateurTournament.EVENTS[event]
		var done_key := "%d-%s-result" % [year, event]
		if gs.amateur_news_done.has(done_key) or date < "%d-%s" % [year, info["date"]]:
			continue
		var result := AmateurTournament.historical(year, event) if year <= 2027 else {}
		if year <= 2027:
			if result.is_empty() or result.get("cancelled", false):
				gs.amateur_news_done[done_key] = true
				continue
			if date < str(result["publish_after"]):
				continue
		else:
			result = AmateurTournament.simulate(year, event, prospects(year), hash("tournament:%d:%s:%d:%s" % [year, event, gs.first_year, gs.team]))
			if result.is_empty():
				gs.amateur_news_done[done_key] = true
				continue
		# 春夏連覇は同じ年の春と夏の勝者が一致したときだけ。
		if result.get("fictional", false) and event == "summer":
			var spring: Dictionary = gs.amateur_results.get("%d-spring" % year, {})
			if spring.get("winner", "") == result["winner"]:
				result["notes"].append({"text": "春夏連覇", "source_url": ""})
		gs.amateur_results["%d-%s" % [year, event]] = result
		gs.amateur_news_done[done_key] = true
		_post_result(year, event, result)


func _post_result(year: int, event: String, result: Dictionary) -> void:
	var label: String = AmateurTournament.EVENTS[event]["label"]
	var date: String = result["publish_after"]
	var key := "%d-amateur-%s-result" % [year, event]
	gs.news.open_issue(key, "%d年 %s・大会結果号" % [year, label], date, year)
	var note := ""
	for entry: Dictionary in result.get("notes", []):
		note += "、" + str(entry["text"])
	var headline := "%sが%s制覇%s！準優勝は%s" % [result["winner"], label, note, result["runner_up"]]
	var body := "%d年%sは%sが優勝、%sが準優勝。" % [year, label, result["winner"], result["runner_up"]]
	if not str(result.get("score", "")).is_empty():
		body += "決勝は%s。" % result["score"]
	var ids: Array = []
	var all := prospects(year)
	for p: Dictionary in result.get("players", []):
		body += "\n%s（%s）：%s%s。" % [p["name"], p["school"], str(p["title"]).replace("（ゲーム内）", "").replace("（ゲーム内選出）", ""), "・" + str(p["stat"]) if not str(p.get("stat", "")).is_empty() else ""]
		for c: Dictionary in all:
			if LeagueRoster.norm_name(c["name"]) == LeagueRoster.norm_name(p["name"]):
				for id: String in _ids(c):
					if id not in ids:
						ids.append(id)
	if result.get("fictional", false):
		body += "\n頂点をつかんだ選手たちが、秋のドラフト戦線を熱くする。"
	else:
		var urls: Array[String] = []
		for url: String in result.get("sources", {}).values():
			if url not in urls:
				urls.append(url)
		for p: Dictionary in result.get("players", []):
			if str(p["source_url"]) not in urls:
				urls.append(str(p["source_url"]))
		for entry: Dictionary in result.get("notes", []):
			if str(entry["source_url"]) not in urls:
				urls.append(str(entry["source_url"]))
		body += "\n出典：" + "\n".join(urls)
	gs.post_news(News.article(date, "amateur", headline, body, ids), key, true)


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
				+ (3.0 if not c["reincarnation"].is_empty() else 0.0)
				+ AmateurTournament.bonus(gs.amateur_results, year, c["name"], c["school"]) * 4.0])
	pool.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var chosen: Array = []
	for item: Array in pool.slice(0, int(stage["count"])):
		chosen.append(item[0])
	# 目玉だけの紙面にせず、最後の1枠は中位・育成級の候補にも光を当てる。
	for item: Array in pool:
		if item[0]["grade"] in ["C", "D"] and item[0] not in chosen:
			if chosen.size() >= int(stage["count"]):
				chosen.pop_back()
			chosen.append(item[0])
			break
	var mlb: Array = []
	var intents: Array = []  # 意中の球団・指名を拒否して戻ってきた候補（作業77）
	if stage["key"] == "fall":
		for c: Dictionary in all:
			if c["mlb"]:
				mlb.append(c)
			elif not c.get("intent", {}).is_empty() or not c.get("refused", {}).is_empty():
				intents.append(c)
	if chosen.is_empty() and mlb.is_empty() and intents.is_empty():
		return 0
	var key := "%d-amateur-%s" % [year, stage["key"]]
	var date := "%d-%s" % [year, stage["date"]]
	gs.news.open_issue(key, stage["title"] % year, date, year)
	var n := 0
	# その年の色（作業67。架空の候補の年）：センバツ号とドラフト直前号のはじめに「今年は◯◯の豊作年」
	if stage["key"] in ["spring", "fall"] and not all.is_empty():
		var ta := FictionalTypes.theme_article(str(all[0].get("theme", "")))
		if not ta.is_empty():
			gs.post_news(News.article(date, "amateur", ta[0], ta[1]), key, true)
			n += 1
	for c: Dictionary in mlb:
		var body := "%s（%s）の%s。%s" % [c["name"], c["school"], c["pos"], c["mlb_note"] if not c["mlb_note"].is_empty()
			else "高卒・大卒からのメジャー挑戦を表明した"]
		body += "\nドラフトで指名した球団は、入団の説得に臨むことになる。"
		gs.post_news(News.article(date, "amateur", "%sの%s、メジャー挑戦を表明" % [c["school"], c["name"]], body,
			_ids(c)), key, n == 0)
		n += 1
	for c: Dictionary in intents:
		var ia := intent_article(c)
		gs.post_news(News.article(date, "amateur", ia[0], ia[1], _ids(c)), key, n == 0)
		n += 1
	# 全文は選手と号の固定シード。見出し・導入の型は号内で重複させない。
	var styles: Array[int] = []
	for i in HEADLINES.size():
		styles.append(i)
	for i in range(styles.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var old := styles[i]
		styles[i] = styles[j]
		styles[j] = old
	var used_quotes := {}
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var a := article(c, stage, year, rng, styles[i % styles.size()], used_quotes)
		gs.post_news(News.article(date, "amateur", a[0], a[1], _ids(c)), key, n == 0)
		n += 1
	if stage["key"] == "fall":
		# ドラフト直前号に有識者の指名予想（作業38）
		for a: Array in DraftExperts.preview_articles(gs.draft_predictions()):
			gs.post_news(News.article(date, "draft", a[0], a[1]), key)
			n += 1
	return n


## 意中の球団・指名を拒否して戻ってきた候補の記事 [見出し, 本文]（作業77。ドラフト直前号）
static func intent_article(c: Dictionary) -> Array:
	var it: Dictionary = c.get("intent", {})
	var ref: Dictionary = c.get("refused", {})
	var head := ""
	var body := "%s（%s）の%s。" % [c["name"], c["school"], c["pos"]]
	if not ref.is_empty():
		var gap := int(c.get("year", 0)) - int(ref["year"])
		head = "%sの%s、%d年越しのプロ入りへ" % [c["school"], c["name"], gap] if gap > 1 \
			else "%sの%s、再びドラフト候補に" % [c["school"], c["name"]]
		body += "%d年秋に%sの%s指名を拒否してから、%sで力を磨いてきた。" % [int(ref["year"]),
			GameData.short_name(str(ref["team"])), str(ref.get("label", "")), c["school"]]
	if not it.is_empty():
		if head.is_empty():
			head = "%sの%s、%s" % [c["school"], c["name"], DraftIntent.short_text(it)]
		body += str(it.get("note", "")) + "。"
		body += "\n意中ではない球団が強行指名すれば、入団拒否もありうる。" if bool(it.get("hard", false)) \
			else "\nほかの球団の指名なら、交渉が難航する可能性もある。"
	return [head, body]


## 1本分 [見出し, 本文]
func article(c: Dictionary, stage: Dictionary, year: int, _rng: RandomNumberGenerator, style := -1, used_quotes := {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("article:%d:%s:%s:%s" % [year, stage["key"], c["school"], c["name"]])
	var form := style if style >= 0 else rng.randi_range(0, HEADLINES.size() - 1)
	var pos := _position(c)
	var feature := _feature(c)
	var hl := _highlight(c, stage, year, rng)
	var honors := AmateurTournament.summary(gs.amateur_results, year, c["name"], c["school"], "%d-%s" % [year, stage["date"]])
	var hook := hl if not hl.is_empty() else feature
	if "1本塁打" in hook or "１本塁打" in hook:
		hook = feature
	var context := str(_pick(CONTEXTS[stage["key"]], rng))
	if c["category"] == "独立":
		context = "独立リーグからプロを目指す候補を追う" if stage["key"] != "fall" else "ドラフトを前に独立リーグの候補を点検する"
	var words := {"school": c["school"], "name": c["name"], "category": c["category"],
		"grade_text": c["grade_text"], "pos": c["pos"], "hook": hook, "feature": feature,
		"context": context, "role": "注目の" + pos}
	var headline := str(HEADLINES[form % HEADLINES.size()]).format(words)
	var lines: Array[String] = [str(LEADS[form % LEADS.size()]).format(words)]
	if not c["reincarnation"].is_empty():
		var rei: Dictionary = c["reincarnation"]
		headline = "「%sの再来」" % rei["name"] + headline
		lines.append("全盛期の%s（%d年・%s）を思わせるプレースタイルも話題だ。" % [rei["name"], int(rei["peak_year"]), GameData.short_name(str(rei["peak_team"]))])
	if not hl.is_empty():
		lines.append("注目の材料は「%s」。" % hl)
	elif not c["intro"].is_empty():
		lines.append(c["intro"])
	else:
		lines.append("武器は%s。" % feature)
	lines.append(str(_pick(POSITION_LINES[pos], rng)))
	lines.append(str(_pick(CATEGORY_LINES.get(c["category"], CATEGORY_LINES["社会人"]), rng)))
	if not honors.is_empty():
		lines.append("今季の足跡：" + honors.replace("（ゲーム内）", "").replace("（ゲーム内選出）", "") + "。")
	# 実在の発言と誤認しないよう、寸評がゲーム内の演出であることを明記する。
	var quotes: Array = SCOUT_LINES[pos]
	var available: Array = quotes.filter(func(q: String) -> bool: return not used_quotes.has(q))
	var quote: String = str(_pick(available if not available.is_empty() else quotes, rng))
	used_quotes[quote] = true
	var category_words := {"高校": "高校生らしい伸びしろもある", "大学": "大学で磨いた技術が光る", "社会人": "社会人での経験が生きる", "独立": "独立の舞台で力を磨いてきた", "専門": "専門学校で力を磨いてきた"}
	var grade_words := {"S": "競合を覚悟しても欲しい", "A": "１位で名前が挙がる逸材だ", "B": "上位で狙いたい", "C": "指名後が楽しみだ", "D": "磨けば面白い"}
	quote += "。" + str(category_words.get(c["category"], "経験を力に変えてきた")) + "。" + str(grade_words.get(c["grade"], grade_words["D"]))
	lines.append("ある球団のスカウト「%s」。" % quote)
	lines.append(str(_pick(OUTLOOKS.get(c["grade"], OUTLOOKS["D"]), rng)))
	return [headline, "\n".join(lines)]


static func _pick(options: Array, rng: RandomNumberGenerator) -> Variant:
	return options[rng.randi_range(0, options.size() - 1)]


static func _position(c: Dictionary) -> String:
	if c["pitcher"]:
		return "投手"
	if "捕" in str(c["pos"]):
		return "捕手"
	return "外野手" if "外" in str(c["pos"]) or c["pos"] in ["左翼手", "中堅手", "右翼手"] else "内野手"


static func _feature(c: Dictionary) -> String:
	if c["pitcher"] and int(c["kmh"]) > 0:
		return "最速%dキロの直球" % int(c["kmh"])
	if not str(c.get("type", "")).is_empty():
		return str(c["type"])
	return {"投手": "マウンドでの可能性", "捕手": "攻守を担う可能性", "内野手": "内野から挑むプロへの道", "外野手": "外野から挑むプロへの道"}[_position(c)]


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
		"pos": Draft._pos_of(p), "pitcher": Growth._side(p) == "P", "kmh": roundi(float(kmh)) if kmh != null else 0,
		"grade": am["grade"], "intro": am.get("intro", ""), "evaluation": _fictional_eval(am), "highlights": [],
		"projected": am.get("projected", ""), "mlb": mi is Dictionary and bool(mi.get("stated", false)),
		"mlb_note": str(mi.get("note", "")) if mi is Dictionary else "", "id": p["id"], "fictional": true,
		"reincarnation": am.get("reincarnation", {}), "peak": p.get("growth", {}).get("peak", {}),
		"type": am.get("type", ""), "theme": am.get("year_theme", ""), "story": am.get("story", ""),
		"intent": am.get("team_intent", {}), "refused": am.get("refused", {}), "year": int(am.get("draft_year", 0))}


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
func _highlight(c: Dictionary, stage: Dictionary, year: int, rng: RandomNumberGenerator) -> String:
	if not c["fictional"]:
		var words: Array = STAGE_WORDS.get(stage["key"], [])
		var facts: Array[String] = []
		for h: Variant in c["highlights"]:
			var text := str(h)
			for w: String in words:
				if w in text:
					facts.append(text)
					break
		if not facts.is_empty():
			# 数字や出来事の範囲を切り落とさず、収集済みの事実をそのまま使う。
			return str(_pick(facts, rng))
		return "最速%dkmの快速球" % int(c["kmh"]) if c["pitcher"] and int(c["kmh"]) >= 150 else ""
	# 架空の出来事も、保存済みの大会結果からだけ引用する。
	var honors := AmateurTournament.honors(gs.amateur_results, year, c["name"], c["school"], "%d-%s" % [year, stage["date"]])
	if not honors.is_empty():
		var h: Dictionary = honors[-1]
		# 見出しには最も大切な肩書を一つ。全実績は本文・候補紹介で読める。
		var title := "躍進"
		for word: String in ["橋戸賞", "優勝投手", "大会MVP", "準優勝", "優勝", "大会最多奪三振", "大会最多本塁打"]:
			if word in str(h["title"]):
				title = word
				break
		var moment := str(h.get("moment", ""))
		if not moment.is_empty():
			return "%s、%s" % [h["label"], moment]
		var stat := str(h["stat"])
		if "1本塁打" in stat:
			return "%sで存在感" % h["label"]
		return "%s%s！%s" % [h["label"], title, stat]
	return ""


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
