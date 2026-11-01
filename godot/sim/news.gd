class_name News
extends RefCounted
## ニュース（新聞・速報）の共通の部品（docs/AUTORUN.md 作業25。作業21 アマのニュース・作業24 史実との分岐ニュースも使う）。
##
## 記事は Dictionary：{id, date, year, kind, headline, body, players, teams, flash, mine, issue}
## - date：ゲーム内の日付 "YYYY-MM-DD"（オフは "YYYY-12-01" のような目安の日付でよい）。year：その年（シーズンの年）
## - kind：種類（KINDS のキー。新しい種類を足すときは KINDS に名前を足す）
## - headline：見出し（1行）、body：本文（複数行可）
## - players：関係する選手ID（新聞の画面で名前から選手詳細を開ける）、teams：関係する球団（正式名）
## - flash：速報（その場でハブの帯に出す）、mine：自球団の話題（GameState.post_news が自動で付ける）
## - issue：載った号のキー（号に載らない速報は空）
## 号（issue）は {key, title, date, year, ids}。月ごとの新聞（"2008-05"）、日本シリーズ号（"2008-js"）、史実との比較（"2008-history"）など。
##
## 書き方（ほかの作業から）：
##   GameState.post_news(News.article(日付, "amateur", "見出し", "本文", [選手ID], [球団]), 号のキー, 速報か)
##   号を作るとき：GameState.news.open_issue(キー, "表題", 日付, 年) のあとに post_news(…, キー)
## オートロードは参照しない

## 種類 → 画面に出す名前
const KINDS := {
	"mvp": "月間MVP", "race": "優勝争い", "streak": "連勝・連敗", "milestone": "記録達成", "feat": "快挙",
	"team": "自球団", "pennant": "優勝", "awards": "表彰", "postseason": "ポストシーズン", "standings": "順位",
	"divergence": "史実との違い", "history": "史実との比較", "amateur": "アマ球界", "draft": "ドラフト", "misc": "話題",
}
## 速報の上限（古いものから消す。号に載った記事は消さない）
const FLASH_LIMIT := 400

var articles: Array[Dictionary] = []
var issues: Array[Dictionary] = []
## 月ごとの新聞が次に扱う期間の最初の日（通し日数。月の試合が少ないときは翌月とまとめる）
var period_from := -1
var _next_id := 1


## 記事を作る（まだ載せない）。post() で載せる
static func article(date: String, kind: String, headline: String, body := "", players: Array = [],
		teams: Array = []) -> Dictionary:
	return {"id": 0, "date": date, "year": int(date.substr(0, 4)), "kind": kind, "headline": headline,
		"body": body, "players": players.duplicate(), "teams": teams.duplicate(), "flash": false, "mine": false,
		"issue": ""}


## 記事を載せる（号のキーがあればその号に足す）。載せた記事を返す
func post(a: Dictionary, issue_key := "") -> Dictionary:
	a["id"] = _next_id
	_next_id += 1
	a["issue"] = issue_key
	articles.append(a)
	if not issue_key.is_empty():
		var issue := get_issue(issue_key)
		if not issue.is_empty():
			issue["ids"].append(a["id"])
	_trim_flashes()
	return a


## 号を作る（同じキーがあればそれを返す）
func open_issue(key: String, title: String, date: String, year: int) -> Dictionary:
	var found := get_issue(key)
	if not found.is_empty():
		return found
	var issue := {"key": key, "title": title, "date": date, "year": year, "ids": []}
	issues.append(issue)
	return issue


func get_issue(key: String) -> Dictionary:
	for i in range(issues.size() - 1, -1, -1):
		if issues[i]["key"] == key:
			return issues[i]
	return {}


## 号の記事（載せた順）
func of_issue(key: String) -> Array[Dictionary]:
	var issue := get_issue(key)
	var result: Array[Dictionary] = []
	if issue.is_empty():
		return result
	var wanted := {}
	for id: Variant in issue["ids"]:
		wanted[int(id)] = true
	for a in articles:
		if wanted.has(int(a["id"])):
			result.append(a)
	return result


## 新しい順に n 件（kind が空でなければその種類だけ。flash_only で速報だけ）
func latest(n: int, kind := "", flash_only := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(articles.size() - 1, -1, -1):
		var a := articles[i]
		if (not kind.is_empty() and a["kind"] != kind) or (flash_only and not a["flash"]):
			continue
		result.append(a)
		if result.size() >= n:
			break
	return result


## その年のある種類の記事（古い順）
func of_kind(kind: String, year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for a in articles:
		if a["kind"] == kind and int(a["year"]) == year:
			result.append(a)
	return result


## 選手に関係する記事（新しい順に n 件）
func for_player(id: String, n := 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(articles.size() - 1, -1, -1):
		if id in articles[i]["players"]:
			result.append(articles[i])
			if result.size() >= n:
				break
	return result


## 日付の範囲（"YYYY-MM-DD" の文字列で、from 以上 to 未満）の記事
func between(from_date: String, to_date: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for a in articles:
		if a["date"] >= from_date and a["date"] < to_date:
			result.append(a)
	return result


static func kind_name(kind: String) -> String:
	return KINDS.get(kind, kind)


## "2008-05-01" → "5月1日"
static func date_label(date: String) -> String:
	if date.length() < 10:
		return date
	return "%d月%d日" % [int(date.substr(5, 2)), int(date.substr(8, 2))]


func _trim_flashes() -> void:
	var n := 0
	for a in articles:
		if a["issue"].is_empty():
			n += 1
	var i := 0
	while n > FLASH_LIMIT and i < articles.size():
		if articles[i]["issue"].is_empty():
			articles.remove_at(i)
			n -= 1
		else:
			i += 1


# --- セーブ／ロード ----------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"articles": articles, "issues": issues, "period_from": period_from, "next_id": _next_id}


## d は SaveUtil.ints() で整数を戻したもの
static func from_save(d: Dictionary) -> News:
	var n := News.new()
	n.articles.assign(d.get("articles", []))
	n.issues.assign(d.get("issues", []))
	n.period_from = int(d.get("period_from", -1))
	n._next_id = int(d.get("next_id", n.articles.size() + 1))
	return n
