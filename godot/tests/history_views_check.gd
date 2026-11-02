extends SceneTree
## 記録室の「歴代メンバー」「歴代ドラフト」（docs/AUTORUN.md 作業48・49）の確認（ヘッドレス）。
## 2021年開幕で始め（2008〜2020年は史実の年）、5月末まで進めて次を調べる：
## - 歴代メンバー：2008年の巨人（史実）＝スタメン8人（9番は投手）・捕手は阿部・4番はスタメンで本塁打が最多・先発ローテ5人以上・
##   抑えはクルーン。2020年のソフトバンク（史実）＝DH制で9人・抑えは森。史実の年の本塁打1位に「本塁打王」の ☆。
##   2021年（ゲーム内）＝打順ごとにその打順で先発した選手、1週間進めると試合数が増える
## - 歴代ドラフト：2008年の巨人1位 大田（いまは日本ハム＝移籍が反映、通算成績あり）、2016年の巨人1位 吉川尚輝（現役・巨人）、
##   育成は本指名の下、引退した選手がいる
## - 画面：ハブの記録室で両タブを開き、野手／投手・年・球団の切り替えでエラーが出ない・右にはみ出さない。
##   1週間進めて開き直すと今季の成績が追従する
##
##   godot --headless --path godot --script res://tests/history_views_check.gd -- [スクショの出力先]
## 出力先を渡してウィンドウ付きで流すと各画面を撮る（--position で画面の隅に置き、フォーカスを奪わない）

const TEAM := "読売ジャイアンツ"
const START := 2021

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
## オートロードを参照するクラスは型として書かずに読み込む（テストのスクリプトはオートロードより先にコンパイルされるため）
var _rh: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
		DirAccess.make_dir_recursive_absolute(_out)
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_rh = load("res://scenes/hub/records_history.gd")
	_gs.new_game(TEAM, START)
	_gs.advance_through(Season.day_number("%d-05-31" % START))
	_check_members()
	_check_drafts()
	await _check_ui()
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _names(list: Array) -> String:
	var names: Array[String] = []
	for x: Dictionary in list:
		var e: Dictionary = x.get("e", x)
		names.append(str(e["name"]))
	return ",".join(PackedStringArray(names))


func _check_members() -> void:
	var years: Array = _rh.member_years()
	_check(years.has(2008) and years.has(2020) and years.has(START), "歴代メンバーの年は2008〜%d（%s〜%s）" % [START,
		str(years.front()), str(years.back())])
	# 2008年 巨人（史実）
	var m: Dictionary = _rh.members(2008, TEAM)
	var lineup: Array = m["lineup"]
	print("2008 巨人 スタメン：", _names(lineup))
	print("2008 巨人 ローテ：", _names(m["rotation"]), " 抑え：", _names(m["closer"]), " 中継ぎ：", _names(m["relief"]))
	_check(not m["game"] and lineup.size() == 8 and not m["dh"], "2008年の巨人は史実・スタメン8人（%d人）" % lineup.size())
	var catcher := ""
	var max_hr := 0
	var fourth_hr := -1
	for s: Dictionary in lineup:
		if s["pos"] == "捕手":
			catcher = s["e"]["id"]
		max_hr = maxi(max_hr, int(s["e"]["line"].get("hr", 0)))
		if int(s["slot"]) == 4:
			fourth_hr = int(s["e"]["line"].get("hr", 0))
	_check(catcher == "21125113", "2008年の巨人の捕手は阿部（%s）" % catcher)
	_check(fourth_hr == max_hr and max_hr > 0, "4番はスタメンで本塁打が最多（%d本）" % fourth_hr)
	_check(m["rotation"].size() >= 5, "先発ローテ5人以上（%d人）" % m["rotation"].size())
	_check(m["closer"].size() == 1 and str(m["closer"][0]["name"]).contains("クルーン"), "2008年の抑えはクルーン")
	_check(m["bench"].size() >= 3, "控えが出る（%d人）" % m["bench"].size())
	# 2020年 ソフトバンク（史実・DH制）
	var h: Dictionary = _rh.members(2020, "福岡ソフトバンクホークス")
	print("2020 ソフトバンク スタメン：", _names(h["lineup"]), " 抑え：", _names(h["closer"]))
	var dh_count := 0
	for s: Dictionary in h["lineup"]:
		if s["pos"] == "指名打者":
			dh_count += 1
	_check(h["dh"] and h["lineup"].size() == 9 and dh_count == 1, "2020年のソフトバンクはDH制で9人（%d人・DH %d）" % [
		h["lineup"].size(), dh_count])
	_check(h["closer"].size() == 1 and str(h["closer"][0]["name"]).contains("森"), "2020年の抑えは森")
	# 史実の年の本塁打1位に ☆
	var d: Dictionary = _rh.year_data(2008)
	var king := {}
	for e: Dictionary in d["bat"]:
		if d["leagues"].get(e["team"], "") == "C" and int(e["rank"].get("hr", 0)) == 1:
			king = e
	_check(not king.is_empty() and "本塁打王" in king["stars"], "2008年のセの本塁打1位に「本塁打王」（%s）" % king.get("name", ""))
	# 2021年（ゲーム内）
	var g: Dictionary = _rh.members(START, TEAM)
	print("%d 巨人 スタメン：" % START, _names(g["lineup"]))
	_check(g["game"] and g["lineup"].size() == 8, "%d年はゲーム内の成績・スタメン8人（%d人）" % [START, g["lineup"].size()])
	var slot_ok := true
	for s: Dictionary in g["lineup"]:
		if int(s["e"]["orders"].get(str(s["slot"]), 0)) <= 0:
			slot_ok = false
	_check(slot_ok, "スタメンの選手はその打順で先発している")
	_check(g["rotation"].size() >= 5, "%d年の先発ローテ5人以上（%d人）" % [START, g["rotation"].size()])


func _check_drafts() -> void:
	var years: Array = _rh.draft_years()
	_check(years.has(2001) and years.has(START - 1) and not years.has(START), "歴代ドラフトの年は2001〜%d" % (START - 1))
	var p: Dictionary = _rh.draft_picks(2008, TEAM)
	var rows: Array = p["rows"]
	_check(not p["game"] and rows.size() >= 3, "2008年の巨人の指名（史実・%d人）" % rows.size())
	if not rows.is_empty():
		var first: Dictionary = rows[0]
		print("2008 巨人 1位：", first["name"], " ", first["status"], " ", first["now_team"], " ", first["career"])
		_check(str(first["name"]).contains("大田") and first["status"] == "active"
				and first["now_team"] == "北海道日本ハムファイターズ", "2008年1位の大田はいま日本ハム（移籍が反映）")
		_check(int(first["career"].get("b", {}).get("g", 0)) > 100, "大田の通算試合が出る")
		_check(not str(first["rank"]).is_empty(), "大田の評価ランクが出る（%s）" % first["rank"])
	var retired := 0
	for r: Dictionary in rows:
		if r["status"] == "retired":
			retired += 1
	_check(retired >= 1, "2008年の巨人の指名に引退した選手がいる（%d人）" % retired)
	var q: Dictionary = _rh.draft_picks(2016, TEAM)
	var rows16: Array = q["rows"]
	if not rows16.is_empty():
		_check(str(rows16[0]["name"]).contains("吉川") and rows16[0]["status"] == "active"
				and rows16[0]["now_team"] == TEAM, "2016年1位の吉川尚輝は現役・巨人")
	var seen_ikusei := false
	var order_ok := true
	for r: Dictionary in rows16:
		if r["ikusei"]:
			seen_ikusei = true
		elif seen_ikusei:
			order_ok = false
	_check(seen_ikusei and order_ok, "2016年の育成指名は本指名の下")
	# 名簿に一度も載らなかった育成の選手（髙井・山川・高山）は記録なし。ドラフトの経歴が無い仮IDの松澤も名前で結び付く
	var matched := 0
	var regular := 0
	var regular_matched := 0
	for r: Dictionary in rows16:
		if not str(r["id"]).is_empty():
			matched += 1
		if not r["ikusei"]:
			regular += 1
			if not str(r["id"]).is_empty():
				regular_matched += 1
	_check(regular_matched == regular and matched >= rows16.size() - 3,
		"2016年の巨人の本指名は全員が選手と結び付く（本指名 %d/%d、全体 %d/%d）" % [regular_matched, regular, matched,
		rows16.size()])


func _check_ui() -> void:
	var hub: Control = load("res://scenes/hub/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.call("_on_menu_chosen", "records")
	await process_frame
	var view: Control = hub.get("_records_view")
	view.call("set_tab", "members")
	_check(view.get("_mem_year") == START and not view.call("list_ids").is_empty(), "歴代メンバーは今季（%d年）から" % START)
	var g0 := _first_games(view)
	await _capture(hub, "members_bat_%d" % START)
	view.set("_mem_pitch", true)
	view.call("refresh")
	_check(not view.call("list_ids").is_empty(), "歴代メンバー（投手）に選手がいる")
	await _capture(hub, "members_pit_%d" % START)
	view.set("_mem_year", 2008)
	view.set("_mem_pitch", false)
	view.call("refresh")
	await _capture(hub, "members_bat_2008")
	view.set("_mem_pitch", true)
	view.call("refresh")
	await _capture(hub, "members_pit_2008")
	# 球団のマークで切り替え・年の◀▶
	var opts: Control = view.get("_sub_options")
	for c: Node in opts.get_children():
		if c.has_meta("team") and c.get_meta("team") == "福岡ソフトバンクホークス":
			(c as Button).emit_signal("pressed")
	_check(view.get("_mem_team") == "福岡ソフトバンクホークス", "球団のマークでソフトバンクに")
	view.set("_mem_year", 2020)
	view.set("_mem_pitch", false)
	view.call("refresh")
	await _capture(hub, "members_bat_2020_hawks")
	view.call("set_tab", "drafts")
	view.set("_dr_team", TEAM)
	view.set("_dr_year", 2008)
	view.call("refresh")
	_check(not view.call("list_ids").is_empty(), "歴代ドラフト（2008年）に選手がいる")
	await _capture(hub, "drafts_2008")
	view.set("_dr_year", 2016)
	view.call("refresh")
	await _capture(hub, "drafts_2016")
	# 1週間進めて開き直すと今季が追従する
	hub.call("_close_sub_screen")
	await process_frame
	_gs.advance_through(_gs.day + 7)
	hub.call("_on_menu_chosen", "records")
	await process_frame
	view.call("set_tab", "members")
	var g1 := _first_games(view)
	_check(g1 > g0, "1週間進めると今季の試合数が増える（%d → %d）" % [g0, g1])
	hub.queue_free()
	await process_frame


## 歴代メンバーの1番打者の試合数
func _first_games(view: Control) -> int:
	var m: Dictionary = _rh.members(view.get("_mem_year"), view.get("_mem_team"))
	if m["lineup"].is_empty():
		return 0
	return int(m["lineup"][0]["e"]["line"].get("g", 0))


## 右にはみ出す部品がないか（スクロールの中は下に伸びてよい）を調べ、出力先があればスクショ
func _capture(hub: Control, file_name: String) -> void:
	await process_frame
	await process_frame
	var view: Control = hub.get("_records_view")
	var over: Array[String] = []
	for c: Node in view.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if not ctrl.is_visible_in_tree():
			continue
		var r := ctrl.get_global_rect()
		if r.end.x > 1281.0:
			over.append("%s%s" % [ctrl.name, r])
	_check(over.is_empty(), "%s：右にはみ出さない %s" % [file_name, " ".join(over.slice(0, 3))])
	# 文字が枠で切れていない（出身校のように説明のツールチップがあるものは除く）。タブのボタンも
	var cut: Array[String] = []
	for c: Node in view.find_children("*", "Label", true, false):
		var l := c as Label
		if not l.is_visible_in_tree() or not l.clip_text or not l.tooltip_text.is_empty() or l.text.is_empty():
			continue
		var w := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			l.get_theme_font_size("font_size")).x
		if w > l.size.x + 1.0:
			cut.append("%s(%.0f>%.0f)" % [l.text, w, l.size.x])
	for b: Button in (view.get("_tab_buttons") as Dictionary).values():
		var sb := b.get_theme_stylebox("normal")
		var w := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			b.get_theme_font_size("font_size")).x
		if w > b.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) + 1.0:
			cut.append("タブ %s" % b.text)
	_check(cut.is_empty(), "%s：文字が切れない %s" % [file_name, " ".join(cut.slice(0, 4))])
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(file_name + ".png"))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("NG ", label)
	else:
		print("OK ", label)
