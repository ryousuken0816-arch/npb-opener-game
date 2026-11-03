extends SceneTree
## ドラフト前の作戦会議（docs/AUTORUN.md 作業37）と有識者の指名予想（作業38）の確認（ヘッドレス可。出力先を渡すとスクショ）。
## 1) 2024年開始（巨人）：開幕日は候補がまだ（春のアマ球界のニュースの前）→ 日付を進めると新戦力の「ドラフト候補」→
##    作戦会議に候補が並ぶ。補強ポイント3つ。印（◎2人・○・☆・✕）とメモ、本命の順番の並べ替え、絞り込み「目星だけ」。
##    7月まで進めても印が残る。セーブ／ロード（全状態の往復）で印・本命の順・予想が残る
## 2) 同じゲームで戦力外・引退を締める → 可変ボタンが「作戦会議」→ 作戦会議 →「ドラフト会議へ」でドラフトの画面。
##    1位入札の初期値が本命の1番目、一覧に印と予想の列、「目星だけ」。おまかせで入札すると本命の1番目に入札。
##    残りもおまかせ：自球団は✕の候補を指名しない
## 3) 有識者の予想：2024年・2026年で3人×（順位予想30人・12球団の1位予想）。予想の1位と実際の1回目の入札が
##    一部は一致し、一部は外れる。秋のドラフト直前号に予想の記事、翌年の春季キャンプへ進むとオフ号に答え合わせの記事
##
##   godot --headless --path godot --script res://tests/draft_meeting_check.gd -- [出力先]

const USER := "読売ジャイアンツ"
const MUNETAKA := "宗山 塁"

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
## class_name を型・静的呼び出しに書くとオートロードより先にコンパイルされるので、実行時に読む
var _dx: GDScript
var _db: GDScript
var _su: GDScript
var _first := 0
var _done := 3
## 2024年のゲームで付けた印 {印: 候補のキー}
var _marked := {}
var _fav: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_ds.lottery_seed = 1  # 抽選の当たりはテストのときだけ決めた種で引く（作業58。本番はその場で引く）
	_dx = load("res://sim/draft_experts.gd")
	_db = load("res://sim/draft_board.gd")
	_su = load("res://sim/save_util.gd")
	_first = _ds.Stage["FIRST"]
	_done = _ds.Stage["DONE"]
	await _check_season_meeting()
	await _check_pre_draft()
	_check_experts(2024)
	_check_experts(2026)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


# --- 1) シーズン中の作戦会議 --------------------------------------------------------------------

func _check_season_meeting() -> void:
	print("== 2024年開始・シーズン中の作戦会議（%s） ==" % USER)
	_gs.new_game(USER, 2024)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	var scout: Node = hub.get("_scout_view")
	scout.call("switch_tab", 3)
	hub.call("_on_menu_chosen", "scout")
	await _frames(2)
	scout.emit_signal("meeting_requested")
	await _frames(3)
	var view: Node = hub.get("_meeting_view")
	_check(hub.get("_open_key") == "meeting" and view.is_visible_in_tree(), "新戦力の「ドラフト候補」から作戦会議が開く")
	var date0: String = _gs.date_text()
	_check(view.call("source") == null and view.call("list_ids").is_empty(),
		"開幕日（%s）は候補がまだ（春のアマ球界のニュースの前）" % date0)
	hub.call("_close_sub_screen")
	_gs.advance_through(_gs.day + 5)
	hub.call("_on_menu_chosen", "scout")
	scout.emit_signal("meeting_requested")
	await _frames(3)
	var d: RefCounted = view.call("source")
	var ids: Array = view.call("list_ids")
	_check(d != null and ids.size() >= 60, "日付を進める（%s → %s）と候補が並ぶ：%d人" % [date0, _gs.date_text(), ids.size()])
	if d == null:
		return
	var needs: Array = view.call("needs")
	var need_text: Array[String] = []
	for n: Dictionary in needs:
		need_text.append("%s（%s）" % [n["pos"], n["why"]])
	_check(needs.size() == 3, "補強ポイント3つ：%s" % "／".join(need_text))
	var title: String = hub.get("_sub_title_label").text
	_check(title.contains("2024年"), "見出しが今年（%s）" % title)
	# 印を付ける：◎宗山・◎評価2番目・○・☆・✕
	var munetaka := _id_of(d, MUNETAKA)
	var by_hyouka: Array = d.candidates.duplicate()
	by_hyouka.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["hyouka"] > b["hyouka"])
	var others: Array[String] = []
	for c: Dictionary in by_hyouka:
		if c["id"] != munetaka:
			others.append(c["id"])
	var plan := [[munetaka, "◎"], [others[0], "◎"], [others[1], "○"], [others[20], "☆"], [others[2], "✕"]]
	for item: Array in plan:
		view.call("select_candidate", item[0])
		view.call("set_mark", item[1])
		_marked[item[1] + str(item[0])] = _key(d, item[0])
	view.call("select_candidate", others[20])
	view.call("set_memo", "球の回転が良い。下位で")
	var board: RefCounted = _gs.draft_board
	_fav = board.favorite_list(2024).duplicate()
	_check(_fav == [_key(d, munetaka), _key(d, others[0])], "本命の順番：%s" % str(_fav))
	view.call("move_favorite", _key(d, others[0]), -1)
	_check(board.favorite_list(2024)[0] == _key(d, others[0]), "▲で並べ替え：%s" % str(board.favorite_list(2024)))
	view.call("move_favorite", _key(d, munetaka), -1)
	_fav = board.favorite_list(2024).duplicate()
	_check(_fav[0] == _key(d, munetaka), "もう一度並べ替えて宗山が1番手：%s" % str(_fav))
	view.call("set_filter", "marked")
	await _frames(1)
	_check(view.call("list_ids").size() == 5, "絞り込み「目星だけ」で5人（%d）" % view.call("list_ids").size())
	_check(board.memo_of(2024, _key(d, others[20])) == "球の回転が良い。下位で", "メモが残る")
	view.call("set_filter", "all")
	view.call("set_mode", "table")  # 手帳（作業51）では LB/RB がページをめくるので表にしてから
	view.call("switch_tab", -1)  # 有識者の予想
	await _frames(2)
	var pred: Dictionary = board.prediction(2024)
	_check(pred.get("experts", []).size() == 3, "有識者の予想タブ：評論家3人の予想がある（%s 時点）" % pred.get("date", ""))
	await _shot("meeting_experts")
	view.call("switch_tab", 1)
	view.call("select_candidate", munetaka)
	await _frames(2)
	await _shot("meeting_season")
	# 日付を進めても残る
	hub.call("_close_sub_screen")
	_gs.advance_through(_gs.day + 100)
	hub.call("_on_menu_chosen", "scout")
	scout.emit_signal("meeting_requested")
	await _frames(3)
	var marks_now: Dictionary = board.marked(2024)
	_check(marks_now.size() == 5 and _gs.date_text().contains("7月"),
		"7月（%s）に進めても印が残る：%d人" % [_gs.date_text(), marks_now.size()])
	var scout_text: String = scout.get("_meeting_label").text
	_check(scout_text.contains("◎2人"), "新戦力の「ドラフト候補」に印の数")
	# セーブ／ロード（全状態の往復）
	var saved: Variant = _norm(_gs.to_save())
	var json := JSON.stringify(_gs.to_save(), "", false, true)
	_gs.new_game("阪神タイガース", 2010)
	_check(_gs.draft_board.marked(2024).is_empty(), "別のゲームでは印なし")
	_gs.load_state(_su.ints(JSON.parse_string(json)))
	_check(_gs.draft_board.marked(2024) == marks_now and _gs.draft_board.favorite_list(2024) == _fav \
		and _gs.draft_board.prediction(2024).get("experts", []).size() == 3,
		"セーブ／ロードで印・本命の順番・予想が残る")
	var diff := _diff(saved, _norm(_gs.to_save()), "")
	_check(diff.is_empty(), "ロード後に全状態（GameState.to_save()）が一致%s" % ("" if diff.is_empty() else "（違い：%s）" % diff))
	hub.call("_close_sub_screen")


# --- 2) ドラフト直前の作戦会議 → ドラフト会議 ------------------------------------------------------

func _check_pre_draft() -> void:
	print("== 2024年オフ：ドラフト直前の作戦会議 → ドラフト会議 ==")
	# 作業54：契約更改・戦力外がひとつの段階（CONTRACT）
	_gs.skip_to_phase(_gs.Phase.CONTRACT)
	_gs.contract_resolve()
	_gs.release_resolve()
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	_check(_gs.button_text() == "作戦会議", "戦力外・引退を締めると可変ボタンは「作戦会議」（%s）" % _gs.button_text())
	hub.call("_on_menu_chosen", "advance")
	await _frames(3)
	var view: Node = hub.get("_meeting_view")
	_check(hub.get("_open_key") == "meeting" and _gs.phase == _gs.Phase.CONTRACT,
		"可変ボタンで作戦会議が開く（段階はまだ%s）" % _gs.phase_name())
	_check(view.get("_draft_button").visible, "作戦会議に「ドラフト会議へ」")
	_check(_gs.draft_board.marked(2024).size() == 5, "シーズン中に付けた印が並ぶ")
	view.emit_signal("draft_requested")
	await _frames(3)
	var d: RefCounted = _gs.draft()
	var dv: Node = hub.get("_draft_view")
	_check(d != null and hub.get("_open_key") == "draft", "「ドラフト会議へ」でドラフトの画面（%s）" % _gs.phase_name())
	if d == null:
		return
	dv.call("finish_overlays")
	await _frames(2)
	var fav_id := _id_by_key(d, str(_fav[0]))
	_check(dv.call("selected_id") == fav_id, "1位入札の初期値が本命の1番目（%s）" % d.by_id.get(fav_id, {}).get("name", "?"))
	_check(d.user_recommend() == fav_id, "おすすめ＝本命の1番目")
	dv.call("set_filter", "marked")
	await _frames(1)
	_check(dv.call("list_ids").size() == 5, "ドラフト画面の絞り込み「目星だけ」で5人（%d）" % dv.call("list_ids").size())
	dv.call("set_filter", "all")
	dv.call("set_sort", "yosou", true)
	await _frames(1)
	var top: Dictionary = d.by_id[dv.call("list_ids")[0]]
	_check(int(top.get("yosou", 0)) == 1, "予想の列で並び替え：1位予想 %s" % top["name"])
	await _shot("draft_marks")
	# おまかせで入札：本命の1番目に入札する
	var avoid := _id_by_key(d, str(_marked.values()[4]))
	dv.call("_on_auto_pick_pressed")
	dv.call("finish_overlays")
	await _frames(2)
	var bid := str(_dx.actual_first_bids(d).get(USER, ""))
	_check(bid == str(_fav[0]), "おまかせの1位入札は本命の1番目（%s）" % bid)
	_gs.draft_resolve()
	var mine: Array[String] = []
	var avoided := false
	for rec: Dictionary in d.picks_of(USER):
		mine.append("%s %s" % [rec["label"], rec["name"]])
		if rec["id"] == avoid:
			avoided = true
	_check(not avoided, "おまかせで✕（%s）は指名しない：%s" % [d.by_id[avoid]["name"], "、".join(mine)])
	hub.call("_close_sub_screen")
	var guard := 0
	while _gs.phase != _gs.Phase.CAMP and guard < 10:  # 作業54：ドラフトのあとに FA・現役ドラフト
		guard += 1
		_gs.advance()
	var review: Array = _gs.news.of_kind("draft", 2024)
	var found := false
	for a: Dictionary in review:
		if a["issue"] == "2024-off" and a["headline"].contains("予想"):
			found = true
			print("  答え合わせ：%s\n  %s" % [a["headline"], a["body"].replace("\n", "\n  ")])
	_check(found and _gs.phase == _gs.Phase.CAMP, "春季キャンプへ進むとオフ号に答え合わせの記事")


# --- 3) 有識者の予想 -------------------------------------------------------------------------

func _check_experts(year: int) -> void:
	print("== %d年：有識者の予想と実際の1位入札 ==" % year)
	_gs.new_game("北海道日本ハムファイターズ", year)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var pred: Dictionary = _gs.draft_board.prediction(year)
	var experts: Array = pred.get("experts", [])
	_check(experts.size() == 3, "%d年：評論家3人の予想（%s 時点）" % [year, pred.get("date", "")])
	if experts.size() != 3:
		return
	var ok := true
	for ex: Dictionary in experts:
		ok = ok and ex["ranking"].size() == 30 and ex["firsts"].size() == 12
	_check(ok, "順位予想30人・12球団の1位予想")
	var preview := false
	for a: Dictionary in _gs.news.of_issue("%d-amateur-fall" % year):
		if a["kind"] == "draft":
			preview = true
	_check(preview, "ドラフト直前号に予想の記事")
	var d: RefCounted = _gs.draft()
	var hits := 0
	var misses := 0
	var lines: Array[String] = []
	d.run_first_wave()
	var actual: Dictionary = _dx.actual_first_bids(d)
	for t: String in actual:
		var hit_by: Array[String] = []
		for i in experts.size():
			if str(experts[i]["firsts"].get(t, "")) == actual[t]:
				hits += 1
				hit_by.append(_dx.EXPERTS[i]["name"].get_slice(" ", 0))
			else:
				misses += 1
		lines.append("%s：%s%s" % [_gd.short_name(t), pred["names"].get(actual[t], actual[t]),
			"（的中：%s）" % "・".join(hit_by) if not hit_by.is_empty() else ""])
	print("  実際の1回目の入札：" + "　".join(lines))
	_check(hits > 0 and misses > 0, "%d年：予想の1位と実際の入札は一部一致・一部外れ（的中%d／外れ%d）" % [year, hits, misses])
	var cons: Dictionary = _dx.consensus(pred)
	var with_rank := 0
	for c: Dictionary in d.candidates:
		if int(c.get("yosou", 0)) > 0:
			with_rank += 1
	_check(with_rank >= 25 and cons.size() == 30, "ドラフトの候補に予想順位（%d人）" % with_rank)


# --- 共通 ---------------------------------------------------------------------------------

func _id_of(d: RefCounted, player_name: String) -> String:
	for c: Dictionary in d.candidates:
		if c["name"] == player_name:
			return c["id"]
	return ""


func _key(d: RefCounted, id: String) -> String:
	return _db.key_of(d.by_id[id])


func _id_by_key(d: RefCounted, key: String) -> String:
	for c: Dictionary in d.candidates:
		if _db.key_of(c) == key:
			return c["id"]
	return ""


## JSON にしてから戻し、整数をそろえた形（比べる用。save_check と同じ）
func _norm(v: Variant) -> Variant:
	return _su.ints(JSON.parse_string(JSON.stringify(v, "", false, true)))


## 最初に違うところのパス（同じなら空）
func _diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s 型 %s / %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		if a.size() != b.size():
			return "%s 項目数 %d / %d" % [path, a.size(), b.size()]
		for key: Variant in a:
			if not b.has(key):
				return "%s キー %s が無い" % [path, key]
			var d := _diff(a[key], b[key], "%s.%s" % [path, key])
			if not d.is_empty():
				return d
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s 要素数 %d / %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _diff(a[i], b[i], "%s[%d]" % [path, i])
			if not d.is_empty():
				return d
		return ""
	return "" if a == b else "%s %s / %s" % [path, str(a).left(60), str(b).left(60)]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.35) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
