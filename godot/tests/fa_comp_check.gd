extends SceneTree
## FA移籍の補償の確認（docs/AUTORUN.md 作業18。ヘッドレス可、約1分）。
## 2008〜2012年のオフ（阪神）：毎年、他球団の年俸上位の選手を自球団が獲る（自球団が獲得した側）・自球団の年俸上位の選手が
## 他球団へ移る（自球団が旧球団の側）ようにFA宣言させ、締め切ったあとの補償を画面（CompView）で操作する。
## - ランク（旧球団の日本人選手の年俸順位）・CPU球団どうしは自動で決まる・出来事に残る
## - 獲得した側：プロテクト28人（おまかせ・入れ替え・確定）→ 旧球団が人的補償か金銭を選ぶ
## - 旧球団の側：相手のプロテクト外の一覧から1人選んで獲る（年によっては金銭のみ）
## - 人的補償の選手が翌年の開幕で新しい球団にいる
## ルールの切り替え：2026年オフは35歳以上の移籍は補償なし、2027年オフからは指名権（A＝2巡目、B＝3巡目）か金銭。
## 指名権が移ると、そのドラフトで旧球団の本指名が1つ増え、その巡の獲得球団の番が旧球団の番になる（2010年のドラフトで確認）。
##
##   godot --headless --path godot -s res://tests/fa_comp_check.gd -- [出力先]
##   （出力先はウィンドウ付きのときだけ。2008年オフのプロテクトの画面をスクショ）

const USER := "阪神タイガース"
const FIRST_YEAR := 2008
const LAST_YEAR := 2012

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _hub: Node
var _shot_done := false


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_gs.new_game(USER, FIRST_YEAR)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	_hub = current_scene
	var totals := {"cases": 0, "player": 0, "cpu_done": 0, "acquired": 0, "lost": 0}
	var gained: Array[Dictionary] = []
	for y in range(FIRST_YEAR, LAST_YEAR + 1):
		await _check_year(y, totals, gained)
	_check(totals["cases"] > 0 and totals["player"] > 0 and totals["cpu_done"] > 0,
		"2008〜2012年：補償 %d件（人的補償 %d件、CPU球団どうし %d件）" % [totals["cases"], totals["player"],
			totals["cpu_done"]])
	_check(totals["acquired"] >= 3 and totals["lost"] >= 3,
		"自球団が獲得した側 %d回・旧球団の側 %d回を画面で操作" % [totals["acquired"], totals["lost"]])
	_check_rules()
	_check_pick_draft()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


func _check_year(y: int, totals: Dictionary, gained: Array[Dictionary]) -> void:
	print("\n== %d年オフ ==" % y)
	_gs.skip_to_phase(_gs.Phase.FA_TRADE)
	var league: RefCounted = _gs.league
	var f: RefCounted = _gs.fa()
	if f == null:
		_check(false, "%d年：FAの段階に入れる" % y)
		return
	var debut: Dictionary = _gd.load_debut_years(y)
	# 自球団が獲る：他球団の年俸2〜8位の日本人（CPU の入札を消して自球団だけが提示）
	var target := ""
	for team: String in _gd.teams():
		if team == USER or not target.is_empty():
			continue
		for id: String in _top_japanese(league, team, y, debut).slice(1, 8):
			if id in f.declared:
				continue
			f.declare(league, id)
			f.cpu_bids[id] = []
			if _gs.fa_offer(id, f.bid_range(id)[0], 2).is_empty():
				target = id
				break
	# 自球団の選手が出ていく：自球団の年俸2〜6位（CPU の入札が無ければ1球団の入札を足す）
	var leaving := ""
	for id: String in _top_japanese(league, USER, y, debut).slice(1, 6):
		if id in f.declared:
			continue
		f.declare(league, id)
		if f.cpu_bids[id].is_empty():
			f.cpu_bids[id] = [{"team": "読売ジャイアンツ", "amount": f.info[id]["asking"], "years": 2}]
		leaving = id
		break
	_gs.fa_resolve()
	var comp: RefCounted = _gs.comp()
	_check(comp != null and not target.is_empty() and not leaving.is_empty(),
		"%d年：補償が作られる（自球団が獲る %s・出ていく %s）" % [y, _name(target), _name(leaving)])
	if comp == null:
		return
	totals["cases"] += comp.cases.size()
	var mine := -1
	var lost := -1
	for i in comp.cases.size():
		var c: Dictionary = comp.cases[i]
		if c["id"] == target:
			mine = i
		elif c["id"] == leaving:
			lost = i
		elif c["state"] == "done" and c["kind"] != "none":
			totals["cpu_done"] += 1
			_check(c["result"] in ["player", "money"], "%d年 CPU球団どうし：%s（%sランク）→ %s" % [y, c["name"],
				c["rank"], c["result"]])
	_check(mine >= 0 and comp.cases[mine]["rank"] in ["A", "B"] and comp.cases[mine]["state"] == "protect",
		"%d年：自球団が獲った %s は %sランクで、プロテクト待ち" % [y, _name(target),
			comp.cases[mine]["rank"] if mine >= 0 else "?"])
	_check(lost >= 0 and comp.cases[lost]["rank"] in ["A", "B"] and comp.cases[lost]["state"] == "choose",
		"%d年：出ていった %s は %sランクで、自球団が選ぶ" % [y, _name(leaving),
			comp.cases[lost]["rank"] if lost >= 0 else "?"])
	_check(_gs.comp_open() and _gs.button_text() == "FAの補償", "可変ボタンは「%s」" % _gs.button_text())
	# 画面：可変ボタンで補償の画面が開く
	_hub.call("_on_menu_chosen", "advance")
	await _frames(3)
	var view: Node = _hub.get("_comp_view")
	_check(_hub.get("_open_key") == "comp" and view.is_visible_in_tree(), "可変ボタンで補償の画面が開く")
	if mine >= 0:
		await _protect_side(view, comp, mine, y)
		totals["acquired"] += 1
	if lost >= 0:
		var got := await _choose_side(view, comp, lost, y)
		totals["lost"] += 1
		if not got.is_empty():
			gained.append({"id": got, "year": y})
	# ほかにも自球団が関わる補償があれば（自然にFA宣言した自球団の選手など）おまかせで決める
	for i in comp.cases.size():
		if comp.cases[i]["state"] != "done":
			view.call("select_case", i)
			view.call("press_auto")
			if comp.cases[i]["state"] == "protect":
				view.call("press_action")
	for c: Dictionary in comp.cases:
		if c["result"] == "player":
			totals["player"] += 1
	_check(not _gs.comp_open(), "%d年：自球団の補償が決まった" % y)
	var logged: int = league.events(y, "fa_comp").size()
	_check(logged == comp.cases.size(), "%d年：出来事に補償 %d件（移籍 %d件）" % [y, logged, comp.cases.size()])
	_hub.call("_close_sub_screen")
	# 翌年の開幕：人的補償の選手が新しい球団にいる
	_gs.skip_to_phase(_gs.Phase.CAMP)
	_gs.advance()
	var moved_ok := true
	var names: Array[String] = []
	for c: Dictionary in comp.cases:
		if c["result"] == "player":
			names.append("%s→%s" % [_name(c["player"]), _gd.short_name(c["from"])])
			# 2012年に横浜は DeNA に変わる（LeagueRoster.TEAM_SUCCESSOR）
			var now_from: String = league.TEAM_SUCCESSOR.get(c["from"], c["from"])
			var pid: String = c["player"]
			if pid.begins_with("tmp:") and not league.team_of.has(pid):
				# 仮IDの選手（1軍出場の無い新人）は、能力値ファイルに出てくると本当の選手IDに付け替わる
				for other: String in league.team_of:
					if league.names.get(other, "") == league.names.get(pid, "-") and other != pid:
						pid = other
			if league.team_of.get(pid, "") not in [c["from"], now_from] and not league.retired.has(pid):
				moved_ok = false
	for g: Dictionary in gained:
		if g["year"] == y and not league.retired.has(g["id"]):
			moved_ok = moved_ok and _gs.my_team() != null and _gs.my_team().by_id.has(g["id"])
	_check(_gs.phase == _gs.Phase.SEASON and moved_ok,
		"%d年の開幕：人的補償の選手が新しい球団にいる（%s）" % [y + 1, "、".join(names) if not names.is_empty() else "人的補償なし"])


## 自球団が獲得した側：おまかせ → 1人外して別の1人を入れる → 確定
func _protect_side(view: Node, comp: RefCounted, index: int, y: int) -> void:
	view.call("select_case", index)
	await _frames(2)
	view.call("press_auto")
	var protect: Array = (view.call("protect_ids") as Array).duplicate()
	var ids: Array = (view.call("list_ids") as Array).duplicate()
	_check(protect.size() == 28 and ids.size() > 28, "%d年：プロテクトのおまかせで28人（候補 %d人）" % [y, ids.size()])
	var outside := ""
	for id: String in ids:
		if id not in protect:
			outside = id
			break
	view.call("select_player", protect[0])
	view.call("select_player", outside)
	protect = (view.call("protect_ids") as Array).duplicate()
	_check(protect.size() == 28 and outside in protect, "%d年：プロテクトを入れ替えられる（%s を入れた）" % [y, _name(outside)])
	if not _shot_done:
		_shot_done = true
		await _shot("comp_protect")
	view.call("press_action")
	await _frames(2)
	var c: Dictionary = comp.cases[index]
	var ok: bool = c["state"] == "done" and c["result"] in ["player", "money"]
	if c["result"] == "player":
		ok = ok and c["player"] not in protect and _gs.league.team_of[c["player"]] == c["from"]
	_check(ok, "%d年：プロテクトを確定 → 旧球団（%s）が選んだ：%s" % [y, _gd.short_name(c["from"]),
		_name(c["player"]) if c["result"] == "player" else c["result"]])


## 自球団が旧球団の側：相手のプロテクト外からいちばん上の選手を獲る。獲った選手ID
func _choose_side(view: Node, comp: RefCounted, index: int, y: int) -> String:
	view.call("select_case", index)
	await _frames(2)
	var c: Dictionary = comp.cases[index]
	var ids: Array = (view.call("list_ids") as Array).duplicate()
	var protected_ok := true
	for id: String in ids:
		if id in c["protect"]:
			protected_ok = false
	_check(not ids.is_empty() and protected_ok and c["protect"].size() == 28,
		"%d年：%sのプロテクト外 %d人（プロテクト28人は出ない）" % [y, _gd.short_name(c["to"]), ids.size()])
	if ids.is_empty():
		view.call("press_money")
		return ""
	view.call("select_player", ids[0])
	view.call("press_action")
	await _frames(2)
	var got: String = ids[0]
	_check(c["state"] == "done" and c["result"] == "player" and _gs.league.team_of[got] == USER,
		"%d年：人的補償で %s を獲った（＋金銭%s）" % [y, _name(got), _salary_text(c["amount"])])
	return got


## 年ごとのルール（2025年まで・2026年・2027年から）
func _check_rules() -> void:
	print("\n== ルールの切り替え ==")
	var comp_script: GDScript = load("res://sim/fa_compensation.gd")
	var r2025: Dictionary = comp_script.rule(2025)
	var r2026: Dictionary = comp_script.rule(2026)
	var r2027: Dictionary = comp_script.rule(2027)
	_check(r2025["kind"] == "player" and int(r2025["b_max"]) == 10 and int(r2025["age_limit"]) == 0,
		"2025年オフ：人的補償、B＝4〜10位、年齢の制限なし")
	_check(r2026["kind"] == "player" and int(r2026["age_limit"]) == 35, "2026年オフ：35歳以上は補償なし")
	_check(r2027["kind"] == "pick" and int(r2027["b_max"]) == 8 and int(r2027["pick_round"]["A"]) == 2
		and int(r2027["pick_round"]["B"]) == 3, "2027年オフ：指名権（A＝2巡目・B＝3巡目）、B＝4〜8位")
	var league: RefCounted = _gs.league
	var teams: Array = _gd.teams()
	var a_team: String = teams[0] if teams[0] != USER else teams[1]
	var b_team: String = teams[2] if teams[2] != USER else teams[3]
	var p1: String = league.players_of(a_team)[0]
	var p2: String = league.players_of(a_team)[1]
	# 2026年オフ：36歳と30歳の移籍（どちらもAランク、CPU球団どうし）
	var c26: RefCounted = _fake_comp(2026, [[p1, a_team, b_team, "A", 36], [p2, a_team, b_team, "A", 30]])
	_check(c26.cases[0]["kind"] == "none" and str(c26.cases[0]["reason"]).contains("35")
		and c26.cases[1]["kind"] == "player" and c26.cases[1]["state"] == "done",
		"2026年オフ：36歳は補償なし（%s）、30歳は補償あり（%s）" % [c26.cases[0]["reason"], c26.cases[1]["result"]])
	# 2027年オフ：Aランクの移籍（CPU球団どうし）は指名権、旧球団が自球団なら金銭も選べる
	var before: int = league.draft_pick_comp.size()
	var c27: RefCounted = _fake_comp(2027, [[p1, a_team, b_team, "A", 30], [p2, USER, b_team, "B", 30]])
	var move: Dictionary = league.draft_pick_comp[-1] if league.draft_pick_comp.size() > before else {}
	_check(c27.cases[0]["result"] == "pick" and int(move.get("round", 0)) == 2 and move.get("from") == b_team
		and move.get("to") == a_team, "2027年オフ：Aランクは%sの2巡目の指名権が%sへ" % [_gd.short_name(b_team),
			_gd.short_name(a_team)])
	_check(c27.cases[1]["state"] == "choose" and c27.cases[1]["protect"].is_empty(),
		"2027年オフ：自球団が旧球団ならプロテクトなしで選ぶ")
	c27.choose(league, c27.cases[1], "money")
	_check(c27.cases[1]["result"] == "money" and int(c27.cases[1]["amount"]) == roundi(30000 * 0.8 / 10.0) * 10,
		"2027年オフ：Bランクを金銭で解決（年俸3億円の80%%＝%s）" % _salary_text(c27.cases[1]["amount"]))
	league.draft_pick_comp.resize(before)


## 指名権が移ったドラフト：旧球団の本指名が1つ増え、その巡の獲得球団の番が旧球団の番になる
func _check_pick_draft() -> void:
	print("\n== 指名権の移動とドラフト ==")
	var league: RefCounted = _gs.league
	var y: int = _gs.year
	var teams: Array = _gd.teams()
	var from: String = teams[4] if teams[4] != USER else teams[5]
	var to: String = teams[6] if teams[6] != USER else teams[7]
	league.draft_pick_comp.append({"year": y, "round": 2, "from": from, "to": to, "id": ""})
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	if d == null:
		_check(false, "%d年オフのドラフトに入れる" % y)
		return
	var quota_to: int = d.quota[to]["reg"]
	_gs.draft_resolve()
	var r2 := {}
	var reg := {}
	for p: Dictionary in d.picks:
		if not p["ikusei"]:
			reg[p["team"]] = int(reg.get(p["team"], 0)) + 1
			if int(p["round"]) == 2:
				r2[p["team"]] = int(r2.get(p["team"], 0)) + 1
	_check(int(r2.get(to, 0)) == 2 and int(r2.get(from, 0)) == 0,
		"%d年のドラフト：2巡目は%sが2回・%sは0回" % [y, _gd.short_name(to), _gd.short_name(from)])
	_check(int(reg.get(to, 0)) == quota_to, "%sの本指名は補償の分を足した%d人（指名 %d人）" % [_gd.short_name(to),
		quota_to, int(reg.get(to, 0))])


## FAの結果を作って補償を開く（ルールの確認用）。rows：[[選手ID, 旧球団, 獲得球団, ランク, 年齢]]
func _fake_comp(at_year: int, rows: Array) -> RefCounted:
	var f: RefCounted = load("res://sim/free_agency.gd").new()
	f.year = at_year
	for r: Array in rows:
		f.info[r[0]] = {"from": r[1], "age": r[4], "salary": 30000}
		f.results.append({"id": r[0], "from": r[1], "to": r[2], "rank": r[3], "amount": 30000, "years": 2})
	var comp: RefCounted = load("res://sim/fa_compensation.gd").new()
	var saved: Dictionary = _gs.league.team_of.duplicate()
	comp.open(_gs.league, f)
	_gs.league.team_of = saved  # 人的補償で動いた所属は戻す（確認だけ）
	return comp


## 球団の日本人選手を年俸の高い順に
func _top_japanese(league: RefCounted, team: String, y: int, debut: Dictionary) -> Array:
	var rules: GDScript = load("res://sim/roster_rules.gd")
	var ids: Array = []
	for id: String in league.players_of(team):
		if not rules.is_foreign(_gd.player(id), y, debut.get(id)):
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return league.salary_of(a) > league.salary_of(b))
	return ids


func _name(id: String) -> String:
	return str(_gs.league.names.get(id, id)) if not id.is_empty() else "なし"


func _salary_text(amount: int) -> String:
	return load("res://sim/salary.gd").text(amount)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
