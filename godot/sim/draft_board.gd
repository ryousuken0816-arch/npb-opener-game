class_name DraftBoard
extends RefCounted
## ドラフト前の作戦会議（docs/AUTORUN.md 作業37）の印・本命の順番と、有識者の指名予想（作業38、DraftExperts）の置き場。
## GameState.draft_board（セーブに入る）。画面は DraftMeetingView（作戦会議）と DraftView（印・おすすめ・予想の列）。
##
## - 印：年 → {候補のキー（LeagueRoster.norm_name）: {mark, memo}}。印は MARKS（◎本命・○上位候補・△中位・☆掘り出し物・✕回避）。
##   シーズン中（ドラフト会議の前）は候補の ID が決まっていない（来季の能力値ファイルで結びつく）ので名前のキーで持つ
## - 本命の順番：年 → [◎の候補のキー]（1位入札・外れ1位の順。◎を付けた順に後ろへ足し、作戦会議で並べ替える）
## - held：その年のドラフト直前の作戦会議を開いたか（ハブの可変ボタンが一度だけ「作戦会議」になる）
## - predictions：年 → DraftExperts.predict の結果（一度作ったら変えない）
## ドラフト会議（Draft）には apply_to で候補 ID ごとの印・本命の順と予想順位（c["yosou"]）を渡す。
## 自球団のおまかせ・おすすめは印の順（Draft.user_recommend）。CPU球団の指名は変わらない

const MARKS := ["◎", "○", "△", "☆", "✕"]
const MARK_NAMES := {"◎": "本命", "○": "上位候補", "△": "中位", "☆": "掘り出し物", "✕": "回避"}
const MARK_COLORS := {"◎": Color("e53935"), "○": Color("f57c00"), "△": Color("2e9b48"), "☆": Color("8e24aa"),
	"✕": Color("6d7680")}
## セーブに残す年（今年からこの年数前まで）
const KEEP_YEARS := 2

var marks := {}
var favorites := {}
var held := {}
var predictions := {}


static func key_of(c: Dictionary) -> String:
	return LeagueRoster.norm_name(str(c.get("name", "")))


func mark_of(year: int, key: String) -> String:
	return str(marks.get(str(year), {}).get(key, {}).get("mark", ""))


func memo_of(year: int, key: String) -> String:
	return str(marks.get(str(year), {}).get(key, {}).get("memo", ""))


## 印を付ける（空で外す）。◎を付けると本命の順番の最後に入り、外すと抜ける
func set_mark(year: int, key: String, mark: String) -> void:
	var y := str(year)
	var m: Dictionary = marks.get_or_add(y, {})
	var e: Dictionary = m.get(key, {"mark": "", "memo": ""})
	e["mark"] = mark
	var favs: Array = favorites.get_or_add(y, [])
	if mark == "◎":
		if key not in favs:
			favs.append(key)
	else:
		favs.erase(key)
	_store(m, key, e)


func set_memo(year: int, key: String, memo: String) -> void:
	var m: Dictionary = marks.get_or_add(str(year), {})
	var e: Dictionary = m.get(key, {"mark": "", "memo": ""})
	e["memo"] = memo.strip_edges()
	_store(m, key, e)


func _store(m: Dictionary, key: String, e: Dictionary) -> void:
	if str(e["mark"]).is_empty() and str(e["memo"]).is_empty():
		m.erase(key)
	else:
		m[key] = e


## 本命（◎）の順番 [キー]
func favorite_list(year: int) -> Array:
	return favorites.get(str(year), [])


## 本命の順番を1つ動かす（delta：−1で上へ）。動いたら true
func move_favorite(year: int, key: String, delta: int) -> bool:
	var favs: Array = favorites.get(str(year), [])
	var i := favs.find(key)
	var j := i + delta
	if i < 0 or j < 0 or j >= favs.size():
		return false
	favs[i] = favs[j]
	favs[j] = key
	return true


## 印を付けた候補 {キー: 印}
func marked(year: int) -> Dictionary:
	var result := {}
	var m: Dictionary = marks.get(str(year), {})
	for key: String in m:
		if not str(m[key]["mark"]).is_empty():
			result[key] = m[key]["mark"]
	return result


## 印ごとの人数 {印: 人数}
func counts(year: int) -> Dictionary:
	var result := {}
	for mark: String in MARKS:
		result[mark] = 0
	var m := marked(year)
	for key: String in m:
		result[m[key]] = int(result.get(m[key], 0)) + 1
	return result


## その年のドラフト直前の作戦会議をまだ開いていないか
func meeting_due(year: int) -> bool:
	return not held.has(str(year))


func hold(year: int) -> void:
	held[str(year)] = true


# --- 有識者の予想 -----------------------------------------------------------------------------

func prediction(year: int) -> Dictionary:
	return predictions.get(str(year), {})


## 予想が無ければ作る（counts：球団 → {守備位置の4区分: 人数}）。final：ドラフト直前（秋のドラフト直前号の日から）の
## 予想か。それより前に作った予想は途中経過で、直前にもう一度作り直す（直前の予想は変えない）。作った予想
func ensure_predictions(year: int, date: String, team_counts: Dictionary, teams: Array, final: bool) -> Dictionary:
	var y := str(year)
	var old: Dictionary = predictions.get(y, {})
	if old.get("experts", []).is_empty() or (final and not bool(old.get("final", false))):
		predictions[y] = DraftExperts.predict(year, date, team_counts, teams)
		predictions[y]["final"] = final
	return predictions[y]


## 球団ごとの守備位置の4区分の人数（今の所属。予想の守備位置の不足に使う）
static func pos_counts(team_of: Dictionary) -> Dictionary:
	var result := {}
	for id: String in team_of:
		var team: String = team_of[id]
		var group := LeagueRoster.pos_group(GameData.player(id))
		var c: Dictionary = result.get_or_add(team, {})
		c[group] = int(c.get(group, 0)) + 1
	return result


# --- ドラフト会議へ ---------------------------------------------------------------------------

## ドラフト会議（または作戦会議の候補一覧）に、候補 ID ごとの印・本命の順と予想順位（c["yosou"]、0＝圏外）を渡す
func apply_to(d: Draft) -> void:
	if d == null:
		return
	var y := str(d.year)
	var by_key := {}
	for c in d.candidates:
		by_key[key_of(c)] = c["id"]
	var m := marked(d.year)
	var mark_ids := {}
	for key: String in m:
		if by_key.has(key):
			mark_ids[by_key[key]] = m[key]
	var fav_ids: Array = []
	for key: String in favorites.get(y, []):
		if by_key.has(key):
			fav_ids.append(by_key[key])
	d.set_user_board(mark_ids, fav_ids)
	var cons := DraftExperts.consensus(predictions.get(y, {}))
	for c in d.candidates:
		c["yosou"] = int(cons.get(key_of(c), 0))


# --- セーブ／ロード ----------------------------------------------------------------------

func to_save(year: int) -> Dictionary:
	var out := {"marks": {}, "favorites": {}, "held": {}, "predictions": {}}
	for part: String in out:
		var src: Dictionary = get(part)
		for y: String in src:
			if int(y) >= year - KEEP_YEARS:
				out[part][y] = src[y]
	return out


static func from_save(d: Variant) -> DraftBoard:
	var board := DraftBoard.new()
	if d is Dictionary:
		board.marks = d.get("marks", {})
		board.favorites = d.get("favorites", {})
		board.held = d.get("held", {})
		board.predictions = d.get("predictions", {})
	return board
