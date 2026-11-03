extends SceneTree
## 育成選手の扱いの確認（ヘッドレス。docs/AUTORUN.md 作業53）
## 1) 開始年ごとに、育成で入って支配下に上がった選手（周東・牧原大成・甲斐・千賀など）が、1軍に出た年からは
##    最初から支配下。まだ1軍に出ていない年は育成（2018年の周東）。2026年は名簿の育成の区別どおり
## 2) 2026年開始で YEARS 年進める（名簿の無い2027年〜・架空の候補の2028年〜）：毎年の戦力外の段階で自球団が
##    戦力外にする人数が少しで済み、開幕で各球団の支配下が70人以内、育成の人数もそれらしい。
##    オフの途中でセーブ→ロードしても支配下・育成の人数が変わらない
##    （以前は2027年以降・ロード後に入団の年を1軍初出場とみなして、育成が全員支配下に数えられていた）
##
##   godot --headless --path godot --script res://tests/ikusei_roster_check.gd -- [年数]

const USER := "福岡ソフトバンクホークス"
## 開始年 → {名前: 育成か}
const STARTS := {
	2008: {"山口 鉄也": false, "松本 哲也": false},
	2012: {"牧原 大成": false, "千賀 滉大": false, "岡田 幸文": false, "山口 鉄也": false},
	2018: {"牧原 大成": false, "甲斐 拓也": false, "千賀 滉大": false, "石川 柊太": false, "周東 佑京": true},
	2019: {"周東 佑京": false, "牧原 大成": false, "大竹 耕太郎": false},
	2026: {"周東 佑京": false, "牧原 大成": false, "甲斐 拓也": false, "大関 友久": false},
}
## 開幕の1球団の育成の人数・12球団の合計（史実の2026年は1球団10〜48人、合計232人）
const ROSTER_LIMIT := 70  ## LeagueRoster.ROSTER_LIMIT（テストはオートロードより先にコンパイルされるので写す）
const IKUSEI_TEAM_MAX := 70
const IKUSEI_TOTAL := [100, 500]
## 戦力外の段階で自球団が戦力外にする人数の上限（史実の1球団のオフの戦力外は10人前後）
const RELEASE_NEED_MAX := 20

var _years := 3
var _failures := 0
var _gs: Node
var _gd: Node
var _sg: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_years = int(args[0])
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_sg = load("res://scripts/save_game.gd")
	_sg.set("dir", _sg.call("test_dir", "user://test_saves_ikusei_roster"))
	_sg.set("autosave_enabled", false)
	print("\n-- 1) 開始年ごとの育成出身の選手 --")
	for y: int in STARTS:
		_check_start(y)
	print("\n-- 2) 2026年開始で%d年進める --" % _years)
	_gs.new_game(USER, 2026)
	_check_counts("2026年の開幕")
	for i in _years:
		var y: int = _gs.year
		_gs.skip_to_phase(_gs.Phase.CONTRACT)
		var need: int = _gs.release_need()
		_check(_gs.phase == _gs.Phase.CONTRACT and need <= RELEASE_NEED_MAX,
			"%d年オフ：自球団が戦力外にする人数 %d人（%d人以下）・支配下 %d人・育成 %d人" % [y, need, RELEASE_NEED_MAX,
				_gs.league.registered_count(USER), _gs.league.ikusei_of(USER).size()])
		if i == 1:
			_check_save_load(y)
		_gs.release_resolve()
		_gs.skip_to_phase(_gs.Phase.CAMP)
		_gs.advance()
		_check(_gs.phase == _gs.Phase.SEASON and _gs.year == y + 1, "%d年の開幕（%s）" % [y + 1, _gs.date_text()])
		_check_counts("%d年の開幕" % (y + 1))
	_sg.call("delete", "slot1")
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## 開始年 y の開幕で、決めた選手が支配下・育成のどちらか。2026年は名簿の育成の区別と全員一致する
func _check_start(y: int) -> void:
	_gs.new_game(USER, y)
	var league: Object = _gs.league
	var want: Dictionary = STARTS[y]
	var found := {}
	for id: String in league.team_of:
		var n := str(_gd.player(id).get("name", ""))
		if want.has(n):
			found[n] = true
			var ik: bool = league.ikusei_now(id)
			_check(ik == bool(want[n]), "%d年開始：%s（%s）が%s" % [y, n, _gd.short_name(league.team_of[id]),
				"育成" if ik else "支配下"])
			if not ik and _gs.season.teams.has(league.team_of[id]):
				var sp: Object = _gs.season.teams[league.team_of[id]].by_id.get(id)
				_check(sp != null and not sp.is_ikusei, "%d年開始：%sは1軍の編成でも育成の印が無い" % [y, n])
	for n: String in want:
		_check(found.has(n), "%d年開始：%sが所属している" % [y, n])
	if y == 2026:
		var flags: Dictionary = _gd.roster_ikusei(2026)
		var wrong: Array[String] = []
		for id: String in league.team_of:
			if flags.has(id) and bool(flags[id]) != league.ikusei_now(id):
				wrong.append(str(_gd.player(id).get("name", id)))
		_check(wrong.is_empty(), "2026年開始：名簿の育成の区別と全員一致 %s" % ", ".join(wrong.slice(0, 5)))
	var total := 0
	for t: String in _gd.teams():
		total += league.ikusei_of(t).size()
	print("  %d年開始：育成 %d人（12球団）" % [y, total])


## 開幕：各球団の支配下が70人以内、育成の人数がそれらしい、1軍に育成選手がいない
func _check_counts(when: String) -> void:
	var league: Object = _gs.league
	var total := 0
	var over: Array[String] = []
	var line := ""
	for t: String in _gd.teams():
		var reg: int = league.registered_count(t)
		var ik: int = league.ikusei_of(t).size()
		total += ik
		line += " %s %d/%d" % [_gd.short_name(t), reg, ik]
		# 2026年の開幕は史実の名簿のまま（DeNA 73人）。上限はオフの戦力外から
		if reg > ROSTER_LIMIT and when != "2026年の開幕":
			over.append("%s %d人" % [_gd.short_name(t), reg])
		if ik > IKUSEI_TEAM_MAX:
			over.append("%s 育成%d人" % [_gd.short_name(t), ik])
	print("  %s（支配下/育成）:%s" % [when, line])
	_check(over.is_empty(), "%s：各球団の支配下が%d人以内・育成が%d人以内 %s" % [when, ROSTER_LIMIT,
		IKUSEI_TEAM_MAX, ", ".join(over)])
	_check(total >= IKUSEI_TOTAL[0] and total <= IKUSEI_TOTAL[1], "%s：育成が12球団で%d〜%d人（%d人）" % [when,
		IKUSEI_TOTAL[0], IKUSEI_TOTAL[1], total])
	var active: Array[String] = []
	for t: String in _gs.season.teams:
		var team: Object = _gs.season.teams[t]
		for p: Object in team.players:
			if p.is_ikusei and team.is_active(p):
				active.append("%s %s" % [_gd.short_name(t), p.name])
	_check(active.is_empty(), "%s：1軍に育成選手がいない %s" % [when, ", ".join(active.slice(0, 3))])


## 戦力外の段階でセーブ→ロードしても、支配下・育成の人数が変わらない
func _check_save_load(y: int) -> void:
	var before := _counts()
	_check(_sg.call("save", "slot1").is_empty(), "%d年オフ：セーブ" % y)
	_gs.new_game("阪神タイガース", 2010)
	_check(_sg.call("load_slot", "slot1").is_empty(), "%d年オフ：ロード" % y)
	var after := _counts()
	_check(before == after, "%d年オフ：ロードしても支配下・育成の人数が同じ（%s → %s）" % [y, before, after])


func _counts() -> Array:
	var result := []
	for t: String in _gd.teams():
		result.append([_gs.league.registered_count(t), _gs.league.ikusei_of(t).size()])
	return result


func _check(ok: bool, label: String) -> void:
	print(("  OK  " if ok else "  NG  ") + label)
	if not ok:
		_failures += 1
