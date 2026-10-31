extends SceneTree
## 2026年（史実の最終年）と2027年（史実なし）の確認（docs/AUTORUN.md 作業16・17。ヘッドレスで数分）：
##   1) 2026年開始：日程が史実どおり（12球団すべて143試合）。日付を進めると日付・成績が追従する
##   2) 2026年開始 → すぐドラフトへ：2026年秋の史実の指名選手が候補（1位の競合も史実どおり）。CPU球団は史実の人数
##   3) 次へ → 2027年の春季キャンプ → 開幕：2026年秋の新人が指名した球団にいる。2027年の日程は2026年の写し
##      （同じ曜日・143試合）。日付を進めると追従する
##   4) 2027年のシーズン → ドラフト：候補は実在のアマ選手（data/amateur/2027.json）。1年目は「未来」。
##      CPU球団は AMATEUR_QUOTA の人数を指名し、次へ進むと2028年の春季キャンプで指名選手が所属している
##   5) 2027年開始 → すぐドラフトへ：アマ選手が候補に並ぶ
##
##   godot --headless --path godot --script res://tests/history_2026_check.gd
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

const USER := "北海道日本ハムファイターズ"

var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_check_2026_season()
	_check_2026_draft_and_2027()
	_check_2027_start()
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


# --- 1) 2026年の日程 -----------------------------------------------------------------------

func _check_2026_season() -> void:
	print("== 2026年開始（%s） ==" % USER)
	_gs.new_game(USER, 2026)
	var season: Season = _gs.season
	_check(season != null and _gs.date_text().begins_with("2026年 3月27日"), "2026年は3月27日に開幕（%s）" % _gs.date_text())
	_check(_all_143(season), "2026年：12球団すべて143試合（%s）" % _games_text(season))
	_check_follow("2026年")


# --- 2〜4) 2026年のドラフト → 2027年 → 2027年のドラフト ---------------------------------------

func _check_2026_draft_and_2027() -> void:
	print("== 2026年開始・すぐドラフトへ ==")
	_gs.new_game(USER, 2026)
	var ok: bool = _gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: Draft = _gs.draft()
	_check(ok and d != null and d.year == 2026, "2026年オフのドラフトに飛べる")
	if d == null:
		return
	var reg := 0
	var ikusei := 0
	for c: Dictionary in d.candidates:
		if c["hist_ikusei"]:
			ikusei += 1
		else:
			reg += 1
	_check(reg == 76 and ikusei == 51, "2026年秋の史実の指名選手が候補（本指名 %d・育成 %d）" % [reg, ikusei])
	var amateur := 0
	var multi: Array[String] = []
	for c: Dictionary in d.candidates:
		if c.get("amateur", false):
			amateur += 1
		if int(c["bids"]) >= 2:
			multi.append("%s %d球団" % [c["name"], int(c["bids"])])
	_check(amateur == 0, "2026年の候補はアマ選手の扱いではない（史実の指名）")
	var lottery := _expected_lottery()
	_check(multi.size() == lottery, "1位の競合が史実どおり（%s／史実 %d人）" % [", ".join(multi), lottery])
	var intro := 0
	for c: Dictionary in d.candidates:
		if str(c["intro"]) != Draft.intro_text(c):
			intro += 1
	_check(intro > 60, "紹介文に集めた選手情報が使われる（出身校と守備位置だけでない %d人）" % intro)
	_gs.advance()
	_check(d.resolved and _gs.phase == _gs.Phase.CAMP and _gs.year == 2027, "次へ進むと2027年の春季キャンプ")
	_check_quota(d, "2026年")
	var present := 0
	for rec: Dictionary in d.picks_of(USER):
		if _gs.league.team_of.get(rec["id"], "") == USER:
			present += 1
	_check(present == d.picks_of(USER).size() and present > 0, "2027年：自球団の指名選手 %d人が所属" % present)

	_gs.advance()
	var season: Season = _gs.season
	_check(_gs.phase == _gs.Phase.SEASON and season != null and _gs.date_text().begins_with("2027年 3月26日"),
		"2027年の開幕は3月26日（%s）" % _gs.date_text())
	_check(_all_143(season), "2027年：12球団すべて143試合（2026年の写し。%s）" % _games_text(season))
	var same_weekday := true
	for g: Dictionary in _gd.call("load_schedule", 2027):
		var a := Time.get_datetime_dict_from_datetime_string(str(g["date"]), false)
		var b := Time.get_datetime_dict_from_datetime_string(str(g["copied_from"]), false)
		if a["weekday"] != b["weekday"]:
			same_weekday = false
			break
	_check(same_weekday, "2027年の日程は2026年と同じ曜日")
	_check_follow("2027年")

	print("== 2027年のシーズン → ドラフト ==")
	ok = _gs.skip_to_phase(_gs.Phase.DRAFT)
	d = _gs.draft()
	_check(ok and d != null and d.year == 2027, "2027年オフのドラフトに進める")
	if d == null:
		return
	_check_amateur_draft(d)
	_gs.advance()
	_check(d.resolved and _gs.phase == _gs.Phase.CAMP and _gs.year == 2028, "次へ進むと2028年の春季キャンプ")
	_check_quota(d, "2027年")
	present = 0
	for rec: Dictionary in d.picks_of(USER):
		if _gs.league.team_of.get(rec["id"], "") == USER and not _gd.call("player", rec["id"]).is_empty():
			present += 1
	_check(present == d.picks_of(USER).size() and present > 0, "2028年：自球団が指名したアマ選手 %d人が所属" % present)


func _check_amateur_draft(d: Draft) -> void:
	var amateur := 0
	var future := 0
	var synthetic := 0
	for c: Dictionary in d.candidates:
		if c.get("amateur", false):
			amateur += 1
		if c.get("first", {}).get("status") == "未来":
			future += 1
		if c.get("synthetic", false):
			synthetic += 1
	_check(amateur == d.candidates.size() and amateur >= 100, "2027年の候補は実在のアマ選手（%d人）" % amateur)
	_check(future == d.candidates.size(), "2027年の候補の1年目は「未来」（%d人）" % future)
	_check(synthetic == 0, "2027年の候補はすべて能力値ファイルにいる（仮の選手 %d人）" % synthetic)
	var best: Dictionary = {}
	for c: Dictionary in d.candidates:
		if best.is_empty() or float(c["hyouka"]) > float(best["hyouka"]):
			best = c
	_check(best.get("hyouka_rank", "") == "S", "報道の目玉は当時の評価 S（%s %s）" % [best.get("name", ""),
		best.get("hyouka_rank", "")])
	for t: String in d.teams:
		_check(int(d.quota[t]["reg"]) == Draft.AMATEUR_QUOTA["reg"], "%s：指名人数は定数どおり" % _gd.short_name(t))
		break


# --- 5) 2027年開始 -----------------------------------------------------------------------

func _check_2027_start() -> void:
	print("== 2027年開始・すぐドラフトへ ==")
	_gs.new_game(USER, 2027)
	_check(_gs.season != null and _gs.date_text().begins_with("2027年 3月26日"), "2027年から始められる（%s）" % _gs.date_text())
	var ok: bool = _gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: Draft = _gs.draft()
	_check(ok and d != null and d.year == 2027, "2027年開始：すぐドラフトへ")
	if d != null:
		var amateur := 0
		for c: Dictionary in d.candidates:
			if c.get("amateur", false):
				amateur += 1
		_check(amateur >= 100, "2027年開始：アマ選手が候補に並ぶ（%d人）" % amateur)


# --- 共通 ----------------------------------------------------------------------------

## 1日・1週間と進めると日付と自球団の試合数が増える
func _check_follow(label: String) -> void:
	var before: String = _gs.date_text()
	var played: int = _gs.games_played()
	for i in 10:
		_gs.call("_advance_one_day")
	_check(_gs.date_text() != before and _gs.games_played() > played,
		"%s：日付を進めると追従（%s → %s、%d → %d試合）" % [label, before, _gs.date_text(), played, _gs.games_played()])


func _all_143(season: Season) -> bool:
	var counts := _game_counts(season)
	if counts.size() != 12:
		return false
	for t: String in counts:
		if counts[t] != 143:
			return false
	return true


func _game_counts(season: Season) -> Dictionary:
	var counts := {}
	if season == null:
		return counts
	for g: Dictionary in season.games:
		if g["status"] != "played":
			continue
		for t: String in [g["home"], g["away"]]:
			counts[t] = int(counts.get(t, 0)) + 1
	return counts


func _games_text(season: Season) -> String:
	var counts := _game_counts(season)
	var parts: Array[String] = []
	for t: String in counts:
		parts.append("%s%d" % [_gd.short_name(t), counts[t]])
	return " ".join(parts)


## data/draft_first_round.json で2026年に2球団以上が入札した選手の数
func _expected_lottery() -> int:
	var n := 0
	for r: Dictionary in _gd.call("read_data", "draft_first_round.json"):
		if int(r["draft_year"]) == 2026 and int(r["bids"]) >= 2:
			n += 1
	return n


func _check_quota(d: Draft, label: String) -> void:
	var bad: Array[String] = []
	for t: String in d.teams:
		if t == d.user_team:
			continue
		var reg := 0
		var ik := 0
		for rec: Dictionary in d.picks_of(t):
			if rec["ikusei"]:
				ik += 1
			else:
				reg += 1
		if reg != int(d.quota[t]["reg"]) or ik != int(d.quota[t]["ikusei"]):
			bad.append("%s %d/%d 育成%d/%d" % [_gd.short_name(t), reg, d.quota[t]["reg"], ik, d.quota[t]["ikusei"]])
	_check(bad.is_empty(), "%s：CPU球団はそれぞれ決まった人数を指名（本指名・育成）%s" % [label, " ".join(bad)])


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
