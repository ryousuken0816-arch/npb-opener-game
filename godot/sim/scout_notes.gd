class_name ScoutNotes
extends RefCounted
## スカウトの手帳（docs/AUTORUN.md 作業51）に書く中身：採点表の色分け・スカウトの寸評・特徴の札・新聞の切り抜き・他球団の噂。
## 材料は入団前に見える「今の能力」（Draft の候補 c["ratings"]・球速）と当時の評価・経歴・アマのニュースだけ。
## 将来性（c["future"]・future_seen）やピーク・成長の型は使わない（入団して初めて全部が見える驚きを残す）。
## 他球団の噂だけは CPU 球団の目玉（Draft.cpu_targets）の数をぼかして使う（スカウトの噂話なので当たり外れがある）。
## 能力の良し悪しは、その年の候補のうち同じ区分（投手・野手）の中の順位（パーセンタイル）で決める。
## オートロードは GameState.news（切り抜き）だけを読む

## 採点表の項目 [キー, 見出し]。球速は数字、ほかはランク
## 作業79：投手は 奪三振・被本塁打 の代わりに 決め球（名前と変化量）・球種（持ち球の数）
const PITCH_SHEET := [["velocity", "球速"], ["best", "決め球"], ["bb9", "制球"], ["count", "球種"],
	["stamina", "スタミナ"], ["overall", "総合"]]
## 寸評の言葉を選ぶ能力（投手は持ち球から出した奪三振・被本塁打も使う。言葉は STRONG・WEAK）
const PITCH_COMMENT_KEYS := ["velocity", "k9", "bb9", "hr9", "stamina"]
const BAT_SHEET := [["meet", "ミート"], ["power", "パワー"], ["eye", "選球眼"], ["speed", "走力"],
	["defense", "守備"], ["arm", "肩"]]
## 良い（上位30%）・弱点（下位30%）のしきい値（パーセンタイル）
const GOOD_PCT := 0.70
const WEAK_PCT := 0.30
## 札の色 [地, 字]（参考画面 docs/references/draft_notebook_mock.html）
const MAGNET_COLORS := {
	"good": [Color("FAECE7"), Color("712B13")], "role": [Color("E6F1FB"), Color("0C447C")],
	"bad": [Color("F1EFE8"), Color("444441")], "special": [Color("F3E5F5"), Color("6A1B9A")],
	"mlb": [Color("0D47A1"), Color("FFFFFF")],
}
## 採点表の字の色：良い＝赤、ふつう＝青、弱点＝灰
const TIER_COLORS := {"good": Color("A32D2D"), "normal": Color("185FA5"), "weak": Color("5F5E5A"),
	"none": Color("8a8478")}
## 寸評の長所・弱点の言い回し（キー → 候補。名前で1つ選ぶ）
const STRONG := {
	"velocity": ["真っすぐは今すぐ一軍でも差し込める", "球威は世代でも指折り"],
	"k9": ["空振りを取れる決め球がある", "追い込んでから三振を奪える"],
	"bb9": ["制球がまとまり四球で崩れない", "コーナーに投げ分ける制球力"],
	"hr9": ["低めに集めて一発を浴びにくい", "長打を許さない粘りの投球"],
	"stamina": ["長い回を投げ切れるスタミナ", "球数を投げても球威が落ちない"],
	"overall": ["投球全体の完成度が高い", "試合をつくる安定感がある"],
	"meet": ["芯でとらえる確実性が光る", "広角に打ち分けるバットコントロール"],
	"power": ["打球の飛距離は世代屈指", "一振りで試合を変える長打力"],
	"eye": ["ボール球に手を出さない選球眼", "粘って四球を選べる"],
	"speed": ["足で稼げる。塁に出れば一つ先へ", "スピードは即一軍級"],
	"defense": ["守備は今すぐ一軍で通用する", "守備範囲が広く打球への反応が速い"],
	"arm": ["肩は世代一級", "遠投が光る強肩"],
}
const WEAK := {
	"velocity": ["球威はまだ物足りない", "真っすぐの力強さに欠ける"],
	"k9": ["決め球に欠け、三振が少ない", "空振りを取る球がほしい"],
	"bb9": ["変化球の制球はまだ粗い", "四球で自滅する場面がある"],
	"hr9": ["高めに浮くと一発がある", "長打を浴びやすい"],
	"stamina": ["長い回はまだ厳しい", "球数が増えると球威が落ちる"],
	"overall": ["全体にまだ粗削り", "投球の組み立てはこれから"],
	"meet": ["確実性はまだ課題", "変化球への対応に苦しむ"],
	"power": ["長打力は物足りない", "打球に力強さがほしい"],
	"eye": ["ボール球に手を出しがち", "早打ちで四球が少ない"],
	"speed": ["足は遅い", "走塁は期待できない"],
	"defense": ["守備には不安が残る", "守備はまだ一軍のレベルにない"],
	"arm": ["肩は強くない", "送球の強さに課題"],
}
## 候補ごとのパーセンタイルの表の作り置き（Draft ごと）
static var _cache := {}


## 採点表の1マス {key, label, text（球速は数字・ほかはランク）, value, tier（good/normal/weak/none）}
static func sheet(d: Draft, c: Dictionary) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for k: Array in (PITCH_SHEET if c["pitcher"] else BAT_SHEET):
		var key: String = k[0]
		var value := value_of(c, key)
		var text := "-"
		if value >= 0:
			text = str(value) if key == "velocity" else DraftView.ability_rank(value)
		if key == "best" and not c.get("best_pitch", {}).is_empty():
			text = "%s%d" % [c["best_pitch"]["name"], int(c["best_pitch"]["move"])]
		elif key == "count" and value >= 0:
			text = "%d種" % value
		cells.append({"key": key, "label": k[1], "text": text, "value": value, "tier": tier(d, c, key),
			"small": key == "best"})
	return cells


## 能力の値（無ければ -1）。球速は km/h
static func value_of(c: Dictionary, key: String) -> int:
	if key == "velocity":
		var v := int(c.get("velocity", 0))
		return v if v > 0 else -1
	if key == "best":
		return roundi(float(c.get("best_value", -0.1)) * 10.0) if c.has("best_value") else -1
	if key == "count":
		return int(c.get("pitch_count", -1))
	return int(c.get("ratings", {}).get(key, -1))


## 良し悪し：その年の候補のうち同じ区分（投手・野手）の中の順位で、上位30%＝good・下位30%＝weak
static func tier(d: Draft, c: Dictionary, key: String) -> String:
	var value := value_of(c, key)
	if value < 0:
		return "none"
	var pct := percentile(d, c, key)
	if pct >= GOOD_PCT:
		return "good"
	if pct < WEAK_PCT:
		return "weak"
	return "normal"


## 同じ区分の候補の中で、この値より低い候補の割合（同じ値は半分に数える）。比べる相手がいなければ 0.5
static func percentile(d: Draft, c: Dictionary, key: String) -> float:
	var value := value_of(c, key)
	if value < 0:
		return 0.0
	var values: Array = _values(d, bool(c["pitcher"]), key)
	if values.is_empty():
		return 0.5
	var below := 0.0
	for v: int in values:
		if v < value:
			below += 1.0
		elif v == value:
			below += 0.5
	return below / float(values.size())


static func _values(d: Draft, pitcher: bool, key: String) -> Array:
	if d == null:
		return []
	var cache_key := "%d|%d|%d" % [d.get_instance_id(), d.year, d.candidates.size()]
	if not _cache.has(cache_key):
		if _cache.size() > 8:
			_cache.clear()
		_cache[cache_key] = {}
	var table: Dictionary = _cache[cache_key]
	var tkey := "%s|%s" % [str(pitcher), key]
	if not table.has(tkey):
		var values: Array = []
		for o: Dictionary in d.candidates:
			if bool(o["pitcher"]) == pitcher:
				var v := value_of(o, key)
				if v >= 0:
					values.append(v)
		table[tkey] = values
	return table[tkey]


## スカウトの寸評（3〜4行）[{text, rumor}]：長所・2つ目の長所か経歴のひとこと・弱点・他球団の噂（rumor＝赤字）
static func comments(d: Draft, c: Dictionary) -> Array[Dictionary]:
	var keys: Array = []
	var keys_src: Array = PITCH_COMMENT_KEYS if c["pitcher"] else BAT_SHEET.map(func(k: Array) -> String: return k[0])
	for k: String in keys_src:
		if k != "overall" and value_of(c, k) >= 0:
			keys.append(k)
	var ranked: Array = []
	for key: String in keys:
		ranked.append([key, percentile(d, c, key)])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])
	var lines: Array[Dictionary] = []
	var seed_text: String = str(c["name"])
	if ranked.is_empty():
		lines.append({"text": "能力はまだ見えていない。実際に見て確かめたい", "rumor": false})
	else:
		var best: Array = ranked[0]
		if float(best[1]) >= 0.55:
			lines.append({"text": _phrase(STRONG[best[0]], seed_text), "rumor": false})
		else:
			lines.append({"text": "全体にまとまっているが、これという武器はまだ無い", "rumor": false})
		var bp: Dictionary = c.get("best_pitch", {})
		if c["pitcher"] and not bp.is_empty():
			# 作業79：投手の2行目は決め球（変化量の大きさで言い方を変える）
			var mv := int(bp.get("move", 0))
			var how := "プロでも一級品" if mv >= 6 else ("キレがあり勝負できる" if mv >= 4 else "まだ磨く余地がある")
			lines.append({"text": "決め球は%s。%s" % [bp["name"], how], "rumor": false})
		elif ranked.size() >= 2 and float(ranked[1][1]) >= GOOD_PCT:
			lines.append({"text": _phrase(STRONG[ranked[1][0]], seed_text + "2"), "rumor": false})
		else:
			lines.append({"text": career_line(c), "rumor": false})
		var worst: Array = ranked[-1]
		if float(worst[1]) < 0.4:
			lines.append({"text": _phrase(WEAK[worst[0]], seed_text), "rumor": false})
		else:
			lines.append({"text": "目立った穴は無い", "rumor": false})
	var rumor := rumor_text(d, c)
	if not rumor.is_empty():
		lines.append({"text": rumor, "rumor": true})
	return lines


## 寸評のひとこと（指名ボードの◎の候補の札）：一番の長所
static func one_liner(d: Draft, c: Dictionary) -> String:
	var list := comments(d, c)
	return str(list[0]["text"]) if not list.is_empty() else ""


## 経歴のひとこと（将来性ではなく区分・年齢から）
static func career_line(c: Dictionary) -> String:
	match str(c.get("career", "")):
		"高校生":
			return "体ができる前の高校生。素材をどう見るか"
		"大学生":
			return "大学で鍛えた。完成度はそれなり"
		"社会人":
			return "社会人で揉まれた即戦力候補"
	if int(c.get("age", 0)) >= 23:
		return "経験を積んだ年長の候補"
	return "独立の舞台で力を磨いてきた"


## 他球団の噂（赤字の1行。言うことが無ければ空）。CPU 球団の目玉の数を名前で決まるぶれでぼかす
static func rumor_text(d: Draft, c: Dictionary) -> String:
	if c.get("mlb_intent", false):
		return "メジャー志望を公言。指名には覚悟が要る（他球団スカウト談）"
	var it: Dictionary = c.get("intent", {})
	if not it.is_empty():
		var team := GameData.short_name(str(it["team"]))
		if bool(it.get("hard", false)):
			return "「%s」と公言。強行指名には覚悟が要る（他球団スカウト談）" % DraftIntent.short_text(it)
		return "%s志望らしい。ほかの球団なら交渉が要る（他球団スカウト談）" % team
	var ref: Dictionary = c.get("refused", {})
	if not ref.is_empty():
		return "%d年に%sの指名を拒否した経緯がある（他球団スカウト談）" % [int(ref["year"]), GameData.short_name(str(ref["team"]))]
	var n := 0
	if d != null:
		for t: String in d.cpu_targets:
			if c["id"] in d.cpu_targets[t]:
				n += 1
	var h := absi(hash("rumor:" + str(c["name"])))
	if n >= 1:
		var shown := maxi(1, n + (h % 3) - 1)
		return "%d球団は来る（他球団スカウト談）" % shown if shown >= 2 else "1位で狙う球団があるらしい（他球団スカウト談）"
	match str(c.get("hyouka_rank", "")):
		"S", "A":
			return "上位で消えるとの見方（他球団スカウト談）"
		"B":
			return "上位候補に名前を挙げる球団もある" if h % 2 == 0 else ""
		"C":
			return "中位で残っていれば、の声" if h % 3 == 0 else ""
	return "他球団はまだノーマークらしい" if h % 4 == 0 else ""


## 特徴の札 [{text, kind（good/role/bad/special）}]（多くて5枚）
static func traits(d: Draft, c: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c.get("mlb_intent", false):
		out.append({"text": "メジャー志望", "kind": "mlb"})  # いちばん前に（作業57）
	elif not c.get("intent", {}).is_empty():
		out.append({"text": DraftIntent.short_text(c["intent"]), "kind": "mlb"})  # 意中の球団（作業77）
	if not c.get("refused", {}).is_empty():
		out.append({"text": "%d年 指名拒否" % int(c["refused"]["year"]), "kind": "special"})
	if bool(c.get("two_way", {}).get("active", false)):
		out.append({"text": "二刀流", "kind": "special"})
	if not c.get("reincarnation", {}).is_empty():
		out.append({"text": "%sの再来" % NameTag.family_name(str(c["reincarnation"]["name"])), "kind": "special"})
	var p := _player(c)
	if c["pitcher"]:
		if value_of(c, "velocity") >= 150 or percentile(d, c, "velocity") >= 0.85:
			out.append({"text": "剛球", "kind": "good"})
		if percentile(d, c, "k9") >= 0.75:
			out.append({"text": "奪三振", "kind": "good"})
		if percentile(d, c, "bb9") >= 0.75:
			out.append({"text": "制球力", "kind": "good"})
		if value_of(c, "stamina") >= 0:
			out.append({"text": "先発向き" if percentile(d, c, "stamina") >= 0.5 else "リリーフ向き", "kind": "role"})
		if str(p.get("throws", "")) == "左":
			out.append({"text": "左腕", "kind": "role"})
		if value_of(c, "bb9") >= 0 and percentile(d, c, "bb9") < 0.25:
			out.append({"text": "制球難", "kind": "bad"})
		if value_of(c, "hr9") >= 0 and percentile(d, c, "hr9") < 0.2:
			out.append({"text": "一発に注意", "kind": "bad"})
	else:
		for k: Array in [["meet", "巧打"], ["power", "長打力"], ["eye", "選球眼"], ["speed", "俊足"], ["arm", "強肩"],
				["defense", "守備職人"]]:
			if value_of(c, k[0]) >= 0 and percentile(d, c, k[0]) >= 0.8:
				out.append({"text": k[1], "kind": "good"})
		var bats := str(p.get("bats", ""))
		if bats == "左":
			out.append({"text": "左打ち", "kind": "role"})
		elif bats == "両":
			out.append({"text": "スイッチ", "kind": "role"})
		if value_of(c, "defense") >= 0 and percentile(d, c, "defense") < 0.2:
			out.append({"text": "守備に難", "kind": "bad"})
		if value_of(c, "speed") >= 0 and percentile(d, c, "speed") < 0.15:
			out.append({"text": "鈍足", "kind": "bad"})
	# 悪い札を最後まで残す（多いときは良い札・役割の札から削る）
	while out.size() > 5:
		var drop := -1
		for i in range(out.size() - 1, -1, -1):
			if out[i]["kind"] in ["good", "role"]:
				drop = i
				break
		out.remove_at(drop if drop >= 0 else out.size() - 1)
	return out


## 新聞の切り抜き {source, date, headline}：その年のアマ球界の記事のうち、この候補の最新の1本。
## 無ければスカウトのメモ（紹介文の1行目）
static func clipping(c: Dictionary, year: int) -> Dictionary:
	var news: News = GameState.news if GameState.news != null else null
	if news != null:
		var cid: String = str(c["id"])
		var name: String = str(c["name"])
		for i in range(news.articles.size() - 1, -1, -1):
			var a: Dictionary = news.articles[i]
			if a["kind"] != "amateur" or int(a["year"]) != year:
				continue
			if cid in a["players"] or name in str(a["headline"]):
				return {"source": "スポーツ紙", "date": _short_date(str(a["date"])), "headline": str(a["headline"])}
	var intro: String = str(c.get("intro", "")).get_slice("\n", 0)
	if intro.is_empty():
		return {}
	return {"source": "スカウトのメモ", "date": "", "headline": intro}


## 選手（能力値ファイルの選手か仮の選手。投打・身長を引く）
static func _player(c: Dictionary) -> Dictionary:
	var p := GameData.player(str(c["id"]))
	if p.is_empty() and c.get("player") is Dictionary:
		p = c["player"]
	return p


## 見出しの2行目：守備位置・投打・年齢・身長（分からないものは省く）
static func profile_line(c: Dictionary) -> String:
	var p := _player(c)
	var parts: Array[String] = [str(c["pos"])]
	if p.get("throws") != null and p.get("bats") != null and not str(p["throws"]).is_empty():
		parts.append("%s投%s打" % [p["throws"], p["bats"]])
	if int(c.get("age", 0)) > 0:
		parts.append("%d歳" % int(c["age"]))
	if p.get("height") != null and int(p["height"]) > 0:
		parts.append("%dcm" % int(p["height"]))
	return "・".join(parts)


static func _phrase(options: Array, seed_text: String) -> String:
	return str(options[absi(hash(seed_text)) % options.size()])


static func _short_date(date: String) -> String:
	if date.length() < 10:
		return ""
	return "%d/%d" % [int(date.substr(5, 2)), int(date.substr(8, 2))]
