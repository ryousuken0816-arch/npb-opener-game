extends SceneTree
## 新人・ドラフト候補の守備（docs/AUTORUN.md 作業66）。アマの選手には守備の記録が無いので、tools/amateur_ratings.py（実在）と
## FictionalDraft.fill_fielding（架空）が守備位置・守備力・肩を作る。次を調べる：
## - 能力値ファイル（2026_pre・2027_pre・2027_post・2028_pre）の2025〜2027年秋の新人・候補：野手は本職の位置（SimPlayer.POSITIONS）の
##   守備力（捕手・三塁・遊撃・外野は肩も）と batting の defense・arm を持つ。投手は投手の守備力を持つ
## - 2027年を開始年にすると、2026年秋の新人の野手は試合で本職の位置を守れる（不慣れの扱いにならない）。オーダーに入った新人も同じ
## - 2028年以降の架空の候補も同じ（「内野手」のままの守備位置が無い）
##
##   godot --headless --path godot --script res://tests/rookie_fielding_check.gd

const FILES := ["2026_pre", "2027_pre", "2027_post", "2028_pre"]
const DRAFT_YEARS := [2025, 2026, 2027]
const ARM_POS := ["捕手", "三塁手", "遊撃手", "外野手"]
const TEAM := "阪神タイガース"

var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_check_files()
	_check_game()
	_check_draft()
	_check_fictional()
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failures += 1


## 1人の守備の誤り（無ければ空）
func _problem(p: Dictionary) -> String:
	var f: Variant = p.get("fielding")
	if bool(p.get("is_pitcher", false)):
		if not f is Dictionary or not f.get("投手") is Dictionary or not f["投手"].get("defense") is Dictionary:
			return "投手の守備力なし"
		return ""
	var pos := str(p.get("primary_pos", ""))
	if not pos in SimPlayer.POSITIONS:
		return "本職が %s" % pos
	if not f is Dictionary or not f.get(pos) is Dictionary or not f[pos].get("defense") is Dictionary:
		return "%s の守備力なし" % pos
	if pos in ARM_POS and not f[pos].get("arm") is Dictionary:
		return "%s の肩なし" % pos
	var br: Dictionary = p.get("batting", {}).get("ratings", {})
	# 打撃の側の肩は、史実の選手と同じく肩のある位置が本職のときだけ要る
	if not br.get("defense") is Dictionary or (pos in ARM_POS and not br.get("arm") is Dictionary):
		return "打撃の側の守備力・肩なし"
	# 史実の守備の記録がある選手（detail あり）の慣れは作業44の仕組み（1軍の守備の量）なので、ここでは見ない
	var s := SimPlayer.from_rating(p)
	if not f[pos].has("detail") and (not s.can_play(pos) or s.defense_at(pos) <= SimPlayer.UNFAMILIAR_Z):
		return "試合で %s が不慣れ" % pos
	return ""


func _check_files() -> void:
	print("== 能力値ファイルの新人・候補 ==")
	for name: String in FILES:
		var f := FileAccess.open("res://../generated/ratings/%s.json" % name, FileAccess.READ)
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		for y: int in DRAFT_YEARS:
			var n := 0
			var bat := 0
			var bad: Array = []
			var pos := {}
			for p: Dictionary in data["players"]:
				if not str(p.get("draft", "")).begins_with("%d年" % y):
					continue
				n += 1
				var why := _problem(p)
				if not why.is_empty():
					bad.append("%s（%s）" % [p["name"], why])
				if not bool(p.get("is_pitcher", false)):
					bat += 1
					pos[p["primary_pos"]] = int(pos.get(p["primary_pos"], 0)) + 1
			if n == 0:
				continue
			_check(bad.is_empty(), "%s の%d年秋の新人・候補 %d人（野手 %d人 %s）が守備位置・守備力・肩を持つ（足りない %s）"
				% [name, y, n, bat, pos, bad.slice(0, 5)])


func _check_game() -> void:
	print("== 2027年を開始年にした試合 ==")
	_gs.new_game(TEAM, 2027)
	var rookies := 0
	var bad: Array = []
	var in_lineup := 0
	var bad_lineup: Array = []
	for t: String in _gd.call("teams"):
		var team: SimTeam = _gs.sim_team_of(t)
		if team == null:
			continue
		for s: SimPlayer in team.players:
			var p: Dictionary = _gd.player(s.id)
			if s.is_pitcher or not str(p.get("draft", "")).begins_with("2026年"):
				continue
			rookies += 1
			if not s.primary_pos in SimPlayer.POSITIONS or not s.can_play(s.primary_pos):
				bad.append("%s %s" % [s.name, s.primary_pos])
		for use_dh: bool in [true, false]:
			for entry: Array in team.lineup(use_dh):
				var s: SimPlayer = entry[0]
				if s == null or not str(_gd.player(s.id).get("draft", "")).begins_with("2026年"):
					continue
				var slot := str(entry[1])
				if slot == "指名打者":
					continue
				in_lineup += 1
				if s.defense_at(SimTeam.field_key(slot)) <= SimPlayer.UNFAMILIAR_Z:
					bad_lineup.append("%s %s" % [s.name, slot])
	_check(rookies >= 40 and bad.is_empty(),
		"2026年秋の新人の野手 %d人が本職の位置を守れる（守れない %s）" % [rookies, bad.slice(0, 5)])
	_check(bad_lineup.is_empty(), "オーダーに入った2026年秋の新人 %d人が守備位置で不慣れにならない（%s）" % [in_lineup, bad_lineup])


## ドラフトの候補の時点（候補一覧・手帳の採点表・作戦会議は Draft の候補の ratings を読む）でも守備力・肩が見える
func _check_draft() -> void:
	print("== ドラフトの候補（2026年・2027年） ==")
	var teams: Array[String] = []
	teams.assign(_gd.call("teams"))
	for y: int in [2026, 2027]:
		var f := FileAccess.open("res://../generated/ratings/%d_pre.json" % (y + 1), FileAccess.READ)
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		var entries := {}
		for p: Dictionary in data["players"]:
			entries[p["id"]] = p
		var d: RefCounted = (load("res://sim/draft.gd") as GDScript).new()
		d.call("setup", y, TEAM, teams, entries, {}, teams, 66)
		var bat := 0
		var bad: Array = []
		for c: Dictionary in d.get("candidates"):
			if c["pitcher"]:
				continue
			bat += 1
			var r: Dictionary = c.get("ratings", {})
			if not r.has("defense") or not r.has("arm"):
				bad.append("%s %s" % [c["name"], r.keys()])
		_check(bat >= 30 and bad.is_empty(), "%d年のドラフトの野手の候補 %d人が守備力・肩を持つ（無い %s）" % [y, bat, bad.slice(0, 5)])


func _check_fictional() -> void:
	print("== 2028年以降の架空の候補 ==")
	var fd := FictionalDraft.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	var n := 0
	var bad: Array = []
	var pos := {}
	for y in range(2028, 2033):
		for p: Dictionary in fd.generate_year(y, rng):
			n += 1
			var why := _problem(p)
			if not why.is_empty():
				bad.append("%s（%s）" % [p["name"], why])
			if not bool(p.get("is_pitcher", false)):
				pos[p["primary_pos"]] = int(pos.get(p["primary_pos"], 0)) + 1
	print("  野手の本職 %s" % pos)
	_check(bad.is_empty(), "架空の候補 %d人が守備位置・守備力・肩を持つ（足りない %s）" % [n, bad.slice(0, 5)])
	_check(int(pos.get("遊撃手", 0)) > 0 and int(pos.get("二塁手", 0)) > 0 and int(pos.get("三塁手", 0)) > 0,
		"内野手は二塁手・三塁手・遊撃手などに分かれる")
