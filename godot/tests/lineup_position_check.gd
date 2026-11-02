extends SceneTree
## CPU の自動オーダーの守備位置（作業44）。2026年の開幕で全球団の DH ありのスタメンを組み、次を調べる：
## - スタメンの野手がみな、その位置に慣れている（SimPlayer.can_play。外野の3つは「外野手」。一塁は除く）
## - 本職でない位置に入っていた例（近藤＝中堅、筒香＝中堅、清宮＝二塁）が直り、西川史礁・周東（育成扱いだった）がスタメンに入る
##
##   godot --headless --path godot --script res://tests/lineup_position_check.gd

const YEAR := 2026
## 一塁は易しいので不慣れでも入ってよい（SimPlayer.UNFAMILIAR_Z_FIRST）
const EASY_SLOTS := ["一塁手"]
## 選手 → 入ってはいけない位置
const NOT_AT := {"近藤 健介": "中堅手", "筒香 嘉智": "中堅手", "清宮 幸太郎": "二塁手"}
const MUST_START := ["西川 史礁", "佐藤 輝明", "近藤 健介", "牧 秀悟", "周東 佑京"]

var _failures := 0
var _gd: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs: Node = root.get_node("GameState")
	_gd = root.get_node("GameData")
	gs.new_game("阪神タイガース", YEAR)
	var season: Season = gs.season
	var unfamiliar: Array[String] = []
	var where := {}
	for team_name: String in season.teams:
		var t: SimTeam = season.teams[team_name]
		var line: Array[String] = []
		for entry: Array in t.lineup(true):
			var p: SimPlayer = entry[0]
			var slot: String = entry[1]
			if p == null:
				continue
			where[p.name] = slot
			line.append("%s:%s" % [slot.substr(0, 1) if slot != "指名打者" else "DH", p.name])
			if slot != "指名打者" and slot not in EASY_SLOTS and not p.can_play(SimTeam.field_key(slot)):
				unfamiliar.append("%s %s（%s、慣れ %.2f）" % [_gd.short_name(team_name), p.name, slot,
					float(p.familiarity.get(SimTeam.field_key(slot), 0.0))])
		print("%s　%s" % [_gd.short_name(team_name), "　".join(line)])
	_check(unfamiliar.is_empty(), "スタメンの野手がみな慣れた位置（慣れていない：%s）" % "、".join(unfamiliar))
	for n: String in NOT_AT:
		_check(where.get(n, "") != NOT_AT[n], "%sは%sでない（%s）" % [n, NOT_AT[n], where.get(n, "スタメン外")])
	for n: String in MUST_START:
		_check(where.has(n), "%sがスタメン（%s）" % [n, where.get(n, "-")])
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failures += 1
