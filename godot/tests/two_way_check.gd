extends SceneTree
## 二刀流（docs/AUTORUN.md 作業86）の確認（ヘッドレス、約1分）。
## 1. 実在の大谷 翔平（2016年）が二刀流とみなされ、ほかの投手はみなされない
## 2. 阪神（セ・リーグ＝DH なしが多い）の先発投手を手で本格二刀流（型 A）にして2016年を1シーズン流す：
##    投打の両方の成績が付く・先発した翌日は打たない・DH なしの試合で投げて打つ・DH ありの試合で投手兼 DH。
##    日本ハムの大谷は DH の試合で投手兼 DH。リーグの成績の水準が崩れない
## 3. 起用の切り替え（二刀流／投手に専念／野手に専念）・SimTeam のセーブ／ロード
## 4. ゲーム（GameState）で起用設定の画面から切り替え、日付を進めても試合が回る。年俸の査定・MVP の価値・節目のニュース
##
##   godot --headless --path godot -s res://tests/two_way_check.gd

const YEAR := 2016
const TIGERS := "阪神タイガース"
const FIGHTERS := "北海道日本ハムファイターズ"

var _failures := 0
var _gd: Node
var _gs: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gd = root.get_node("GameData")
	_gs = root.get_node("GameState")
	var t0 := Time.get_ticks_msec()
	_check_real()
	_check_season()
	_check_modes()
	await _check_game()
	_check_units()
	print("\n（%.1f秒）" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if _failures == 0:
		print("二刀流のテスト: すべてOK")
	else:
		print("二刀流のテスト: NG %d件" % _failures)
	quit(1 if _failures > 0 else 0)


# --- 1. 実在の選手 ---------------------------------------------------------------------------

func _check_real() -> void:
	print("\n== 実在の選手の二刀流 ==")
	var found := []
	for y: int in [2012, 2016, 2026]:
		_gd.load_ratings(y, "pre")
		for p: Dictionary in _gd.ratings["players"]:
			if TwoWay.is_two_way(p):
				found.append("%d %s（%s）" % [y, p["name"], TwoWay.type_of(p)])
	print("  ", found)
	_check(found == ["2016 大谷 翔平（実）"], "2012・2016・2026年の開幕で二刀流は 2016年の大谷 翔平だけ")
	# 2014年の大谷は能力値では野手が本職。本格二刀流なので投手として登録し、先発ローテーションに入る
	_gd.load_ratings(2014, "pre")
	var members: Array = _gd.ratings["players"].filter(func(p: Dictionary) -> bool: return p["team"] == FIGHTERS)
	var team := SimTeam.new(FIGHTERS, "P", members, 2014)
	var o: SimPlayer = null
	for p: SimPlayer in team.players:
		if p.name == "大谷 翔平":
			o = p
	_check(o != null and not o.primary_pos.is_empty() and o.is_pitcher and o.both() and o in team.rotation and team.can_bat(o),
		"2014年の大谷（能力値では%s）も投手として先発ローテーションに入り、打者の候補にもなる" % (o.primary_pos if o != null else "?"))


# --- 2. 1シーズン ------------------------------------------------------------------------------

## 阪神の先発投手のいちばん良い選手を本格二刀流（型 A）にする。その選手の能力値を返す
func _make_two_way() -> Dictionary:
	_gd.load_ratings(YEAR, "pre")
	var best: Dictionary = {}
	for p: Dictionary in _gd.ratings["players"]:
		if p["team"] != TIGERS or not p["is_pitcher"] or not p.get("pitching") is Dictionary:
			continue
		if p["pitching"].get("role") != "先発":
			continue
		if best.is_empty() or _ovr(p) > _ovr(best):
			best = p
	best["two_way"] = {"active": true, "type": "A", "desc": "本格二刀流の怪物"}
	best["batting"] = {"ratings": {"meet": {"value": 84}, "power": {"value": 90}, "eye": {"value": 72},
		"speed": {"value": 64}}, "trajectory": 4, "sample": {"pa_1": 0.0}}
	best["fielding"] = {"外野手": {"defense": {"value": 62}, "arm": {"value": 88}}}
	return best


static func _ovr(p: Dictionary) -> float:
	return float(p["pitching"]["ratings"]["overall"]["value"])


func _check_season() -> void:
	print("\n== 1シーズン（%d年、阪神の先発を型 A に） ==" % YEAR)
	var a := _make_two_way()
	var aid: String = a["id"]
	var season := Season.new(YEAR, _gd.ratings, _gd.load_schedule(YEAR), 86, _gd.load_debut_years(YEAR))
	var tigers: SimTeam = season.teams[TIGERS]
	var sp: SimPlayer = tigers.by_id[aid]
	_check(sp.both() and sp.is_pitcher and sp.two_way == "A", "%s は二刀流（型 A）で起用・本職は投手" % a["name"])
	_check(sp in tigers.rotation, "先発ローテーションに入っている")
	_check(tigers.can_bat(sp) and sp.meet > 0.5 and sp.power > 1.0, "スタメン・控えの候補に入り、本当の打撃で打つ（ミート z %.2f・パワー z %.2f）" % [sp.meet, sp.power])
	var in_dh := false
	for e: Array in tigers.lineup_dh:
		in_dh = in_dh or e[0] == sp
	_check(in_dh, "DH ありのスタメンに入っている")
	var ohtani := ""
	for p: SimPlayer in season.teams[FIGHTERS].players:
		if p.name == "大谷 翔平":
			ohtani = p.id
	_check(not ohtani.is_empty() and (season.teams[FIGHTERS].by_id[ohtani] as SimPlayer).both(), "日本ハムの大谷も二刀流で起用")

	season.sim_all()
	var st := {"gs": 0, "start_bat": 0, "start_bat_dh": 0, "start_bat_p": 0, "bat_only": 0, "rest_ok": 0, "rest_ng": 0}
	var o_st := {"gs": 0, "start_dh": 0}
	var by_day := {}  # 阪神の試合の日 → [試合, 阪神の側]
	for g: Dictionary in season.games:
		if g["result"].is_empty():
			continue
		for side in 2:
			if (g["home"] if side == 1 else g["away"]) == TIGERS:
				by_day[int(g["day"])] = [g, side]
			if (g["home"] if side == 1 else g["away"]) == FIGHTERS:
				var started := _started(g, side, ohtani)
				o_st["gs"] += 1 if started else 0
				if started and _bat_pos(g, side, ohtani) == "指名打者":
					o_st["start_dh"] += 1
	for day: int in by_day:
		var g: Dictionary = by_day[day][0]
		var side: int = by_day[day][1]
		var pos := _bat_pos(g, side, aid)
		if _started(g, side, aid):
			st["gs"] += 1
			if not pos.is_empty():
				st["start_bat"] += 1
				st["start_bat_dh" if pos == "指名打者" else "start_bat_p"] += 1
			if by_day.has(day + 1):
				var ng: Dictionary = by_day[day + 1][0]
				if _bat_pos(ng, by_day[day + 1][1], aid).is_empty():
					st["rest_ok"] += 1
				else:
					st["rest_ng"] += 1
		elif not pos.is_empty():
			st["bat_only"] += 1
	var b: Dictionary = season.batting.get(aid, {})
	var pt: Dictionary = season.pitching.get(aid, {})
	print("  型 A：", st, "  打撃 %d打席 打率%s %d本塁打 %d打点／投手 %d登板 %d勝%d敗 防御率%.2f %d奪三振" % [
		int(b.get("pa", 0)), Awards.rate_text(Season.batting_avg(b)), int(b.get("hr", 0)), int(b.get("rbi", 0)),
		int(pt.get("g", 0)), int(pt.get("w", 0)), int(pt.get("l", 0)), Season.era(pt), int(pt.get("so", 0))])
	_check(int(pt.get("gs", 0)) >= 18 and int(pt.get("outs", 0)) >= 300, "投手の成績が付く（先発 %d・%d回）" % [int(pt.get("gs", 0)), int(pt.get("outs", 0)) / 3])
	_check(int(b.get("pa", 0)) >= 300, "打撃の成績も付く（%d打席）" % int(b.get("pa", 0)))
	_check(st["start_bat_p"] >= 10, "DH なしの試合で投げて打つ（%d試合）" % st["start_bat_p"])
	_check(st["start_bat_dh"] >= 1, "DH ありの試合（交流戦）で投手兼 DH（%d試合）" % st["start_bat_dh"])
	_check(st["bat_only"] >= 50, "投げない日は野手で打つ（%d試合）" % st["bat_only"])
	_check(st["rest_ok"] >= 5 and st["rest_ng"] == 0, "先発した翌日は打たない（休み %d回・出た %d回）" % [st["rest_ok"], st["rest_ng"]])
	var ob: Dictionary = season.batting.get(ohtani, {})
	var op: Dictionary = season.pitching.get(ohtani, {})
	print("  大谷：", o_st, "  %d打席 %d本塁打／%d登板 %d勝" % [int(ob.get("pa", 0)), int(ob.get("hr", 0)), int(op.get("g", 0)), int(op.get("w", 0))])
	_check(o_st["start_dh"] >= 5, "大谷は DH の試合で投手兼 DH（%d試合）" % o_st["start_dh"])
	_check(int(ob.get("pa", 0)) >= 150 and int(op.get("gs", 0)) >= 15, "大谷も投打の両方の成績が付く")
	var tot := season.league_totals()
	var avg := Season.batting_avg(tot)
	var era := float(tot["er"]) * 27.0 / float(tot["outs"])
	print("  リーグ：打率%s 防御率%.2f 本塁打%d" % [Awards.rate_text(avg), era, int(tot["hr"])])
	_check(avg > 0.240 and avg < 0.275 and era > 2.8 and era < 4.2, "リーグの打率・防御率がいつもの範囲（史実 2016年 打率.256・防御率3.65）")
	# 今季の価値：二刀流の MVP の価値は投打の足し算
	var aw := Awards.new()
	aw._season = season
	aw._player_of = _gd.player
	aw._league_baselines("C")
	var bv: float = aw._bat_value(aid)
	var pv: float = aw._pit_value(aid)
	print("  価値：打 %.1f 点・投 %.1f 点 → 合わせて %.1f" % [bv, pv, Awards.combined_value(bv, pv)])
	_check(is_equal_approx(Awards.combined_value(bv, pv), maxf(bv, pv) + maxf(minf(bv, pv), 0.0)), "MVP の価値は投打を合わせる")
	# 年俸の査定：投打の両方の額を足す
	var one := Salary.renew(30000, a, pt, 8, false, YEAR + 1)
	var both := Salary.renew(30000, a, pt, 8, false, YEAR + 1, b)
	print("  年俸の査定（今 3億円）：投手だけ %s → 投打 %s" % [Salary.text(one), Salary.text(both)])
	_check(both > one, "年俸の査定は投打の両方を足す")


## その試合で id が先発したか
static func _started(g: Dictionary, side: int, id: String) -> bool:
	var lines: Array = g["result"]["pitching"][side]
	return not lines.is_empty() and str(lines[0]["id"]) == id


## その試合で id が打った守備位置（打っていなければ ""）
static func _bat_pos(g: Dictionary, side: int, id: String) -> String:
	for line: Dictionary in g["result"]["batting"][side]:
		if str(line["id"]) == id:
			return str(line.get("pos", "?"))
	return ""


# --- 3. 起用の切り替え ---------------------------------------------------------------------------

func _check_modes() -> void:
	print("\n== 起用の切り替え ==")
	var a := _make_two_way()
	var season := Season.new(YEAR, _gd.ratings, _gd.load_schedule(YEAR), 1, _gd.load_debut_years(YEAR))
	var team: SimTeam = season.teams[TIGERS]
	var sp: SimPlayer = team.by_id[a["id"]]
	var pitchers := team.active_players(true).size()
	team.set_two_way_mode(sp, TwoWay.MODE_PITCH)
	_check(sp.is_pitcher and not sp.both() and not team.can_bat(sp) and sp.meet < -3.0, "投手に専念：打たない（投手の打撃）")
	_check(not _in_lineups(team, sp) and sp in team.rotation, "投手に専念：スタメン・控えから外れ、ローテーションに残る")
	team.set_two_way_mode(sp, TwoWay.MODE_BAT)
	_check(not sp.is_pitcher and team.can_bat(sp) and sp.meet > 0.5, "野手に専念：野手として打つ")
	_check(not sp in team.rotation and not sp in team.bullpen and team.active_players(true).size() == pitchers - 1,
		"野手に専念：投手の持ち場から外れ、1軍の投手が1人減る")
	team.set_two_way_mode(sp, TwoWay.MODE_BOTH)
	_check(sp.both() and sp in team.rotation and team.can_bat(sp), "二刀流に戻すと、ローテーションに入って打者の候補にも戻る")
	_check(_in_dh(team, sp), "二刀流に戻すと、今の指名打者より良ければ DH ありの指名打者に入る")
	team.set_two_way_mode(sp, TwoWay.MODE_PITCH)
	var saved := team.to_save()
	var again := SimTeam.new(TIGERS, "C", _members(TIGERS), YEAR)
	again.from_save(saved)
	var sp2: SimPlayer = again.by_id[a["id"]]
	_check(sp2.mode == TwoWay.MODE_PITCH and not again.can_bat(sp2) and str(again.two_way_modes.get(sp2.id)) == TwoWay.MODE_PITCH,
		"起用（投手に専念）がセーブ／ロードで残る")
	var fresh := SimTeam.new(TIGERS, "C", _members(TIGERS), YEAR)
	fresh.apply_two_way_modes({a["id"]: TwoWay.MODE_BAT})
	var sp3: SimPlayer = fresh.by_id[a["id"]]
	_check(not sp3.is_pitcher and fresh.can_bat(sp3) and not sp3 in fresh.rotation, "シーズンの初めに起用（野手に専念）を当てられる")
	# 先発の日のオーダー：DH ありは投手兼 DH、DH なしは自分の打順で投げる。翌日は休み
	var team2 := SimTeam.new(TIGERS, "C", _members(TIGERS), YEAR)
	var p2: SimPlayer = team2.by_id[a["id"]]
	var day := 100
	var dh_plan: Array = team2.game_order(true, day, p2)
	_check(_pos_in(dh_plan[0], p2) == "指名打者" and _count_null(dh_plan[0]) == 0 and dh_plan[0].size() == 9,
		"先発の日・DH あり：投手兼指名打者で9人")
	var no_dh: Array = team2.game_order(false, day, p2)
	var batting_slot := _null_index(no_dh[0])
	print("  DH なしの先発の日の打順：", _order_text(no_dh[0]))
	_check(_count_null(no_dh[0]) == 1 and no_dh[0].size() == 9 and not _pos_in(no_dh[0], p2).length() > 0,
		"先発の日・DH なし：投手の打順は1つ（%d番）" % (batting_slot + 1))
	if _pos_in(team2.lineup_no_dh, p2) != "":
		_check(batting_slot != 8, "スタメンの二刀流はいつもの打順で投げて打つ（9番ではない）")
	team2.last_started[p2.id] = day
	var rest: Array = team2.game_order(true, day + 1, team2.rotation[1])
	_check(_pos_in(rest[0], p2) == "" and not p2 in rest[1] and rest[0].size() == 9, "先発の翌日は休み（スタメン・控えにいない）")
	var next2: Array = team2.game_order(true, day + 2, team2.rotation[1])
	_check(_pos_in(next2[0], p2) != "", "2日後はまた打つ")


func _members(team_name: String) -> Array:
	return _gd.ratings["players"].filter(func(p: Dictionary) -> bool: return p["team"] == team_name)


func _in_lineups(team: SimTeam, p: SimPlayer) -> bool:
	for dh in [true, false]:
		if _pos_in(team.lineup(dh), p) != "" or p in team.bench(dh):
			return true
	return false


func _in_dh(team: SimTeam, p: SimPlayer) -> bool:
	return _pos_in(team.lineup_dh, p) == "指名打者"


static func _pos_in(order: Array, p: SimPlayer) -> String:
	for e: Array in order:
		if e[0] == p:
			return str(e[1])
	return ""


static func _count_null(order: Array) -> int:
	var n := 0
	for e: Array in order:
		n += 1 if e[0] == null else 0
	return n


static func _null_index(order: Array) -> int:
	for i in order.size():
		if order[i][0] == null:
			return i
	return -1


static func _order_text(order: Array) -> String:
	var parts := []
	for e: Array in order:
		parts.append("%s(%s)" % [(e[0] as SimPlayer).name if e[0] != null else "投手", e[1]])
	return " ".join(parts)


# --- 4. ゲームの中で ---------------------------------------------------------------------------

func _check_game() -> void:
	print("\n== ゲームの中（%d年の日本ハム、起用設定の画面） ==" % YEAR)
	_gs.new_game(FIGHTERS, YEAR)
	var mine: SimTeam = _gs.my_team()
	var ohtani: SimPlayer = null
	for p: SimPlayer in mine.players:
		if p.name == "大谷 翔平":
			ohtani = p
	_check(ohtani != null and ohtani.both(), "自球団の大谷は二刀流")
	var slot_before := _pos_in(mine.lineup_dh, ohtani)
	print("  開幕の DH ありの打順での大谷：", slot_before)
	var page: Control = (load("res://scenes/hub/order_page.gd") as GDScript).new()
	page.size = Vector2(1000, 600)
	root.add_child(page)
	page.setup((load("res://scripts/ui_theme.gd") as GDScript).neutral_palette())
	page.refresh(true)
	await process_frame
	var picks: Array = page._two_way_box.find_children("*", "OptionButton", true, false)
	_check(picks.size() == 1, "起用設定の左に二刀流の欄（%d人）" % picks.size())
	if picks.is_empty():
		return
	var pick: OptionButton = picks[0]
	_check(pick.selected == 0 and pick.get_item_text(0) == "二刀流", "はじめは「二刀流」")
	pick.select(1)
	pick.item_selected.emit(1)
	await process_frame
	_check(str(_gs.two_way_modes.get(ohtani.id)) == TwoWay.MODE_PITCH and ohtani.mode == TwoWay.MODE_PITCH
		and not mine.can_bat(ohtani), "「投手に専念」を選ぶと GameState と今季の編成に入る")
	_check(str(_gs.to_save().get("two_way_modes", {}).get(ohtani.id)) == TwoWay.MODE_PITCH, "セーブに入る")
	pick = page._two_way_box.find_children("*", "OptionButton", true, false)[0]
	pick.select(0)
	pick.item_selected.emit(0)
	await process_frame
	_check(ohtani.both() and mine.can_bat(ohtani), "「二刀流」に戻せる")
	_check(slot_before.is_empty() or _pos_in(mine.lineup_dh, ohtani) == slot_before, "戻すと元の打順・守備位置に入る（%s）" % _pos_in(mine.lineup_dh, ohtani))
	var badges := page.find_children("*", "Label", true, false).filter(func(l: Label) -> bool:
		return l.text == "二" and l.tooltip_text.begins_with("二刀流"))
	_check(badges.size() == (0 if slot_before.is_empty() else 1), "二刀流の選手の札の横に「二」（%d）" % badges.size())
	page.queue_free()
	# 日付を進めても試合が回り、投打の成績が付く
	var target: int = _gs.day + 30
	_gs.advance_through(target)
	var b: Dictionary = _gs.season.batting.get(ohtani.id, {})
	var pt: Dictionary = _gs.season.pitching.get(ohtani.id, {})
	print("  30日後：%d打席 %d本塁打／%d登板 %d勝" % [int(b.get("pa", 0)), int(b.get("hr", 0)), int(pt.get("g", 0)), int(pt.get("w", 0))])
	_check(_gs.day >= target and int(b.get("pa", 0)) > 20 and int(pt.get("gs", 0)) >= 2, "日付を進めると大谷に投打の成績が付く")


# --- 5. 小さな関数 ---------------------------------------------------------------------------

func _check_units() -> void:
	print("\n== 節目の判定 ==")
	_check(TwoWay.feat_crossed(9, 12, 10, 12) == "二桁勝利・二桁本塁打", "10勝目で 二桁勝利・二桁本塁打")
	_check(TwoWay.feat_crossed(10, 19, 10, 20) == "10勝・20本塁打", "20本目で 10勝・20本塁打")
	_check(TwoWay.feat_crossed(10, 12, 10, 13) == "", "越えていなければ出ない")
	_check(TwoWay.feat_crossed(9, 9, 10, 10) == "二桁勝利・二桁本塁打", "同じ日に両方越えても1つ")


func _check(ok: bool, label: String) -> void:
	print(("  OK  " if ok else "  NG  ") + label)
	if not ok:
		_failures += 1
