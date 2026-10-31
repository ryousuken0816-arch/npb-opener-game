extends SceneTree
## 新加入選手の投手判定の確認（ヘッドレス）。前年までに成績のない新加入投手（由規＝2008年、新外国人など）が
## 投手として能力値ファイルにあり、編成に入ってブルペン・先発に登録できること（作業14）。
## 全年の pre/post で「投手なのに野手扱い」「守備位置なし」の選手が（既知の1人を除いて）いないことも調べる。
##
##   godot --headless --path godot --script res://tests/new_pitcher_check.gd

const YOSHINORI := "由規"

var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_check_files()
	_check_yoshinori()
	print("\n%s（失敗 %d件）" % ["すべてOK" if _failures == 0 else "失敗あり", _failures])
	quit(1 if _failures > 0 else 0)


func _check_files() -> void:
	print("== 全年の能力値ファイル ==")
	var no_pos := 0
	var no_pitching := 0
	for year in range(2008, 2027):
		for phase: String in ["pre", "post"]:
			var data: Dictionary = _gd.peek_ratings(year, phase)
			if data.is_empty():
				_check(false, "%d年%sの能力値ファイルを読める" % [year, phase])
			for e: Dictionary in data.get("players", []):
				if e["primary_pos"] == null:
					no_pos += 1
				if e["is_pitcher"] and e["pitching"] == null:
					no_pitching += 1
				if e["primary_pos"] == "投手" and not e["is_pitcher"]:
					_check(false, "%d年%s %s: 守備位置が投手なのに is_pitcher=false" % [year, phase, e["name"]])
	_check(no_pos == 0, "守備位置なし（primary_pos が null）の選手が0人（%d人）" % no_pos)
	_check(no_pitching == 0, "投手で pitching が無い選手が0人（%d人）" % no_pitching)


func _check_yoshinori() -> void:
	print("== 由規（2008年ヤクルト） ==")
	_gs.new_game("東京ヤクルトスワローズ", 2008)
	var yuki: Dictionary = {}
	for id: String in _gs.league.team_of:
		var p: Dictionary = _gd.player(id)
		if p.get("name", "") == YOSHINORI:
			yuki = p
	_check(not yuki.is_empty(), "由規が2008年の選手にいる")
	if yuki.is_empty():
		return
	_check(yuki["is_pitcher"] and yuki["primary_pos"] == "投手" and yuki["pitching"] != null,
			"由規は投手（is_pitcher・primary_pos・pitching）")
	var sim: SimTeam = _gs.season.teams["東京ヤクルトスワローズ"]
	var sp: SimPlayer = sim.by_id.get(yuki["id"])
	_check(sp != null and sp.is_pitcher, "編成（SimTeam）に投手として入っている")
	if sp == null:
		return
	if not sim.is_active(sp):
		var out_p: SimPlayer = null
		for r: Variant in sim.active_players(true):
			if sim.pitcher_role(r)[0] == "relief":
				out_p = r
				break
		var err := "入れ替える中継ぎなし" if out_p == null else sim.swap_registration(out_p, sp, _gs.day)
		_check(str(err).is_empty(), "ブルペンに入れ替えで登録できる（%s）" % err)
	_check(sim.is_active(sp) and not sim.pitcher_role(sp)[0].is_empty(), "1軍の投手の持ち場に入る（%s）" % [
		sim.pitcher_role(sp)])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s" % ["OK" if ok else "NG", label])
