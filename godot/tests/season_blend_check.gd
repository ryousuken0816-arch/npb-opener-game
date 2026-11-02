extends SceneTree
## シーズン中に能力を史実へ寄せる（作業40、SeasonBlend）の確認。2026年を開始年にして、次を調べる：
## - 開幕は 2026_pre のまま。月替わりごとに、消化した試合の割合だけ 2026_post へ寄る（7月1日・9月1日）
## - 佐藤輝明の打撃（ミート・パワー・選球眼の合計）が 開幕 → 夏 → シーズン後 と上がる（post が pre より上の選手）
## - 試合で使う能力（SimPlayer の z 値）が混ぜた能力値と一致する
## - 選手詳細の能力表示が日付に追従する（開幕と9月で、ミートの表示が能力値と一致）
## - セーブ／ロードで混ぜた能力・割合が一致する
## - 史実の無い年（2027年）は混ぜない（SeasonBlend.applies が false）
## - シーズン後の佐藤輝明のゲーム内の成績（OPS・本塁打）がリーグの上位
##
##   godot --headless --path godot --script res://tests/season_blend_check.gd

const TEAM := "阪神タイガース"
const YEAR := 2026
const SATO := "佐藤 輝明"
## 規定打席（143試合 × 3.1）
const QUALIFIED_PA := 443

var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	var t0 := Time.get_ticks_msec()
	_gs.new_game(TEAM, YEAR)
	var sato := _find(SATO)
	_check(not sato.is_empty(), "%sが %d_pre にいる" % [SATO, YEAR])
	if sato.is_empty():
		quit(1)
		return
	var post: Dictionary = _gd.peek_ratings(YEAR, "post")
	var post_sato := {}
	for q: Dictionary in post.get("players", []):
		if q["id"] == sato:
			post_sato = q
	_check(SeasonBlend.applies(_gd.ratings, post), "%d年は混ぜる年（pre は %s 年まで、post は %s 年まで）" % [
		YEAR, _gd.ratings.get("stats_through"), post.get("stats_through")])
	_check(not SeasonBlend.applies(_gd.peek_ratings(2027, "pre"), _gd.peek_ratings(2027, "post")),
		"2027年（史実の無い年）は混ぜない")
	var open := _bat(_gd.player(sato))
	var goal := _bat(post_sato)
	print("%s 開幕 %s → シーズン後 %s" % [SATO, open, goal])
	_check(_gd.season_blend == 0.0, "開幕は混ぜていない（割合 %.2f）" % _gd.season_blend)
	_check(_sum(goal) > _sum(open), "%sは post の打撃が pre より上（%d → %d）" % [SATO, _sum(open), _sum(goal)])
	_check_sim(sato, "開幕")
	var detail_open := await _detail_meet(sato)
	_check(detail_open == _gd.player(sato)["batting"]["ratings"]["meet"]["value"],
		"開幕：選手詳細のミート %d が能力値と一致" % detail_open)

	_gs.advance_through(Season.day_number("%d-07-01" % YEAR))
	var t_summer: float = _gd.season_blend
	var summer := _bat(_gd.player(sato))
	print("7月1日 割合 %.2f %s" % [t_summer, summer])
	_check(t_summer > 0.3 and t_summer < 0.6, "7月1日：割合が 0.3〜0.6（%.2f）" % t_summer)
	_check(_sum(summer) > _sum(open) and _sum(summer) < _sum(goal),
		"7月1日：%sの打撃が開幕と post の間（%d < %d < %d）" % [SATO, _sum(open), _sum(summer), _sum(goal)])
	_check_sim(sato, "7月1日")
	_check_save(sato)

	_gs.advance_through(Season.day_number("%d-09-01" % YEAR))
	var t_sep: float = _gd.season_blend
	var sep := _bat(_gd.player(sato))
	print("9月1日 割合 %.2f %s" % [t_sep, sep])
	_check(t_sep > t_summer and _sum(sep) >= _sum(summer), "9月1日：割合・打撃がさらに上がる（%.2f、%d）" % [t_sep, _sum(sep)])
	_check_sim(sato, "9月1日")
	var detail_sep := await _detail_meet(sato)
	_check(detail_sep == _gd.player(sato)["batting"]["ratings"]["meet"]["value"],
		"9月1日：選手詳細のミート %d が能力値と一致（開幕 %d）" % [detail_sep, detail_open])

	_gs.advance_through(_gs.season_last_day())
	_check(_gs.phase == _gs.Phase.AWARDS, "シーズン終了（表彰の段階）")
	var after := _bat(_gd.player(sato))
	_check(after == goal, "シーズン後：%sの能力が post と一致 %s" % [SATO, after])
	_check(_gd.season_blend == 0.0, "シーズン後は post を読み直して割合 0")
	_check_leaders(sato)
	print("（%d 秒）" % ((Time.get_ticks_msec() - t0) / 1000))
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _find(p_name: String) -> String:
	for p: Dictionary in _gd.ratings.get("players", []):
		if p["name"] == p_name:
			return p["id"]
	return ""


func _bat(p: Dictionary) -> Dictionary:
	var r: Dictionary = p.get("batting", {}).get("ratings", {})
	var out := {}
	for key in ["meet", "power", "eye"]:
		out[key] = int(r.get(key, {}).get("value", 0))
	return out


func _sum(b: Dictionary) -> int:
	return int(b.get("meet", 0)) + int(b.get("power", 0)) + int(b.get("eye", 0))


## 試合で使う能力（SimPlayer）が今の能力値と一致するか
func _check_sim(id: String, when: String) -> void:
	var season: Season = _gs.season
	var team: SimTeam = season.teams.get(season.players.get(id, {}).get("team", ""))
	var sp: SimPlayer = team.by_id.get(id) if team != null else null
	_check(sp != null, "%s：%sが試合の編成にいる" % [when, SATO])
	if sp == null:
		return
	var expect := SimPlayer.from_rating(_gd.player(id))
	_check(is_equal_approx(sp.meet, expect.meet) and is_equal_approx(sp.power, expect.power)
		and is_equal_approx(sp.eye, expect.eye), "%s：試合で使う能力（z）が能力値と一致（ミート z %.2f）" % [when, sp.meet])
	# CPU 球団の選手も
	var other: SimTeam = season.teams.get("読売ジャイアンツ")
	var bad := 0
	for p: SimPlayer in other.players:
		var e := SimPlayer.from_rating(_gd.player(p.id))
		if not is_equal_approx(p.meet, e.meet) or not is_equal_approx(p.overall, e.overall):
			bad += 1
	_check(bad == 0, "%s：巨人の全選手の試合の能力が能力値と一致（ずれ %d人）" % [when, bad])


func _check_save(id: String) -> void:
	var before: Dictionary = _norm(_gs.to_save())
	var ratings_before := JSON.stringify(_gd.player(id))
	var t_before: float = _gd.season_blend
	var sim_before: float = _sim_meet(id)
	var parsed: Variant = JSON.parse_string(JSON.stringify(_gs.to_save()))
	_gs.new_game("読売ジャイアンツ", 2010)
	_gs.load_state(SaveUtil.ints(parsed))
	_check(is_equal_approx(_gd.season_blend, t_before), "ロード：割合が一致（%.3f）" % _gd.season_blend)
	_check(JSON.stringify(_gd.player(id)) == ratings_before, "ロード：%sの混ぜた能力値が一致" % SATO)
	_check(is_equal_approx(_sim_meet(id), sim_before), "ロード：試合で使う能力が一致")
	_check(JSON.stringify(_norm(_gs.to_save())) == JSON.stringify(before), "ロード：全状態（GameState.to_save()）が一致")


func _sim_meet(id: String) -> float:
	var season: Season = _gs.season
	var team: SimTeam = season.teams.get(season.players.get(id, {}).get("team", ""))
	return team.by_id[id].meet if team != null and team.by_id.has(id) else -99.0


func _norm(v: Variant) -> Variant:
	return SaveUtil.ints(JSON.parse_string(JSON.stringify(v)))


## 選手詳細を開いて、能力のタブのミートの表示（数値）を読む
func _detail_meet(id: String) -> int:
	var detail: Node = load("res://scenes/player_detail/player_detail.gd").call("open", root, id, [id])
	await process_frame
	await process_frame
	var value := -1
	for box: Node in detail.find_children("*", "HBoxContainer", true, false):
		var has_title := false
		for l: Node in box.find_children("*", "Label", true, false):
			if (l as Label).text == "ミート":
				has_title = true
		if not has_title:
			continue
		for c: Node in box.get_children():
			if c is Label and (c as Label).text.is_valid_int():
				value = int((c as Label).text)
		if value >= 0:
			break
	detail.call("close")
	await process_frame
	return value


## シーズン後：佐藤輝明の OPS・本塁打のリーグ内の順位（規定打席以上）
func _check_leaders(id: String) -> void:
	var st: Dictionary = _gs.season_stats(YEAR)
	var rows: Array = []
	for pid: String in st["batting"]:
		var b: Dictionary = st["batting"][pid]
		if int(b.get("pa", 0)) >= QUALIFIED_PA:
			rows.append({"id": pid, "ops": _ops(b), "hr": int(b.get("hr", 0)), "b": b})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ops"] > b["ops"])
	var ops_rank := -1
	for i in rows.size():
		if rows[i]["id"] == id:
			ops_rank = i + 1
	print("OPS 上位：")
	for r: Dictionary in rows.slice(0, 8):
		print("  %s OPS %.3f 打率 %.3f %d本" % [_gd.player(r["id"]).get("name", r["id"]), r["ops"],
			Season.batting_avg(r["b"]), r["hr"]])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["hr"] > b["hr"])
	var hr_rank := -1
	for i in rows.size():
		if rows[i]["id"] == id:
			hr_rank = i + 1
	_check(ops_rank >= 1 and ops_rank <= 5, "%sの OPS がリーグ5位以内（%d位／%d人）" % [SATO, ops_rank, rows.size()])
	_check(hr_rank >= 1 and hr_rank <= 3, "%sの本塁打がリーグ3位以内（%d位）" % [SATO, hr_rank])


func _ops(b: Dictionary) -> float:
	var ab := int(b.get("ab", 0))
	var pa := int(b.get("pa", 0))
	if ab <= 0 or pa <= 0:
		return 0.0
	var h := int(b.get("h", 0))
	var tb := h + int(b.get("d", 0)) + 2 * int(b.get("t", 0)) + 3 * int(b.get("hr", 0))
	var obp := float(h + int(b.get("bb", 0)) + int(b.get("hbp", 0))) / pa
	return obp + float(tb) / ab


func _check(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failures += 1
