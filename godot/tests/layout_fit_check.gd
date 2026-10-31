extends SceneTree
## 画面のはみ出しの確認（ヘッドレス可、約3分）。docs/AUTORUN.md 作業11。
## 2008年から始めて最後の年のオフまで進めながら、ハブを開いたままで次の画面を開き、表示中の全 Control の
## 右端・下端（左端・上端も）が画面（1280x720）の内側か調べる。はみ出したものを列挙して NG にする。
## - 毎年の開幕・7月：ハブ、日程表、采配の一覧と全サブ画面（1軍登録は全選手を1人ずつ選ぶ）、新戦力、システム、選手詳細の4タブ
## - 毎年のオフの各段階：ハブ、采配（オフは「見るだけ」の文言が出る）、FA・契約更改・戦力外の画面（全タブ・選手を選ぶ）、
##   ドラフト（開幕の演出・候補を選んで入札・抽選（3Dの演出の途中と結果の場面）・指名一覧）、新戦力
## - 記録室の全タブ（打撃・投手は今季／通算・規定の切り替え、デプスは全球団・全並び順）：毎年の開幕・7月・オフの表彰の段階
## - 表彰の画面の全タブ（作業9）：毎年のオフの表彰の段階
## - 切り替えの演出の途中で開く・閉じるをくり返したあと（作業11の不具合の原因。最初と毎年の開幕・7月）
## スクロールの中（clip_contents の子）は親が画面内なら見えないので調べない。画面のルートの包み
## （UiTheme.fit_scroll）の中は、その枠からはみ出したもの（見えずに欠ける）と、スクロールバーが出た＝中身が枠に
## 収まっていない、も NG にする。
##
##   godot --headless --path godot -s res://tests/layout_fit_check.gd -- [自球団] [最後の年] [開始年] [出力先]
##   （既定はソフトバンク・2012・2008。出力先はウィンドウ付きのときだけ。はみ出した画面のスクショを保存）

const SCREEN := Vector2(1280, 720)
## 端の許容（ピクセル）。フォーカスしたボタンの拡大（1.045倍）などの小さな揺れは許す
const TOLERANCE := 1.0
## 画面を開いてから調べるまで（UiFx の切り替えの演出 0.16秒が終わるまで）
const SETTLE_SEC := 0.2
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const DETAIL_SCRIPT := "res://scenes/player_detail/player_detail.gd"
const TACTICS_PAGES := ["", "pitchers", "fielders", "practice", "order", "strategy", "rules", "info", "list"]

var _team := "福岡ソフトバンクホークス"
var _last_year := 2012
var _first_year := 2008
var _out := ""
var _failures := 0
var _checked := 0
## 抽選の3D演出を調べた回数（作業20。オフのドラフトで入札が競合したとき）
var _lottery_3d_seen := 0
var _gs: Node
var _hub: Node


func _initialize() -> void:
	# ヘッドレスのウィンドウは既定で 1280x1280 になるので、ユーザーの環境（1280x720）に合わせる
	root.size = Vector2i(SCREEN)
	if DisplayServer.get_name() != "headless":
		# ウィンドウ付き（スクショ）のときもフォーカスを奪わない（CLAUDE.md）
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_team = args[0]
	if args.size() > 1:
		_last_year = int(args[1])
	if args.size() > 2:
		_first_year = int(args[2])
	_out = args[3] if args.size() > 3 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	# ヘッドレスのウィンドウは 1280x1280 になり、aspect=expand だと縦に広がるので、比率を保って 1280x720 にする
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await _frames(2)
	print("== 画面のはみ出し（%s、%d〜%d年オフ、画面 %s） ==" % [_team, _first_year, _last_year,
		str(root.get_visible_rect().size)])
	if not root.get_node("GameData").TEAM_COLORS.has(_team):
		print("NG 球団名が違う：", _team)
		quit(1)
		return
	_gs.new_game(_team, _first_year)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	while true:
		var y: int = _gs.year
		await _check_season(y, "%d年開幕" % y)
		while _gs.phase == _gs.Phase.SEASON and _gs.month < 7:
			_gs.advance()
		await _check_season(y, "%d年%d月" % [y, _gs.month])
		_gs.advance_through(_gs.season_last_day())
		while _gs.phase != _gs.Phase.SEASON:
			await _check_offseason(y)
			if y == _last_year and _gs.phase == _gs.Phase.DRAFT:
				break
			_gs.advance()
		if y >= _last_year:
			break
	print("\n調べた画面：%d（うち抽選の3D演出が出た入札 %d回）" % [_checked, _lottery_3d_seen])
	if _lottery_3d_seen == 0:
		_failures += 1
		print("NG 抽選の3D演出を一度も調べていない（入札が一度も競合しなかった）")
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


# --- シーズン中 ---------------------------------------------------------------------------

func _check_season(y: int, when: String) -> void:
	print("\n-- %s --" % when)
	await _check_screen("%s：ハブ" % when)
	for key in ["schedule", "scout", "system"]:
		await _open(key)
		await _check_screen("%s：%s" % [when, key])
		if key != "system":
			for i in 2:
				_hub.get("_" + ("schedule" if key == "schedule" else "scout") + "_view").switch_tab(1)
				await _check_screen("%s：%s タブ%d" % [when, key, i + 1])
		_hub.call("_close_sub_screen")
	await _check_tactics(when, TACTICS_PAGES, _gs.month >= 7)
	await _check_records(when)
	await _check_detail(when)
	await _check_quick_switch(when)
	await _settle()
	_check(y == _gs.year, "%s：年が変わっていない" % when)


## select_all：1軍登録で全選手を1人ずつ選ぶ（時間がかかるので年に2回だけ）
func _check_tactics(when: String, pages: Array, select_all: bool) -> void:
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	for page: String in pages:
		tactics.call("_show_page", page, true)
		await _check_screen("%s：采配 %s" % [when, page if not page.is_empty() else "一覧"])
		if page in ["pitchers", "fielders"] and select_all:
			await _select_all(tactics.get("_register_" + page), "%s：采配 %s" % [when, page])
		elif page == "list":
			var roster: Node = tactics.get("_roster")
			for i in roster.get_tab_count() - 1:
				roster.switch_tab(1)
				await _check_screen("%s：采配 選手一覧 タブ%d" % [when, i + 2], 0.0)
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")


## 画面の切り替えの演出（0.16秒）の途中で開く・閉じるをくり返す（Ⓐ・Ⓑの連打）。
## 作業11の不具合：演出が途中で止まった位置がサブ画面の右端の余白に残り、くり返すたびに右へはみ出していった
func _check_quick_switch(when: String) -> void:
	for i in 6:
		for key: String in ["schedule", "tactics", "scout"]:
			_hub.call("_open_sub_screen", key)
			await _frames(1 + i % 3)
			_hub.call("_close_sub_screen")
			await _frames(1)
	_hub.call("_open_sub_screen", "tactics")
	await _frames(2)
	_hub.call("_open_sub_screen", "tactics")
	await _settle()
	var tactics: Node = _hub.get("_tactics_view")
	tactics.call("_show_page", "pitchers", true)
	await _check_screen("%s：開く・閉じるの連打のあと 采配 pitchers" % when)
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")
	await _open("schedule")
	await _check_screen("%s：開く・閉じるの連打のあと 日程表" % when)
	_hub.call("_close_sub_screen")


## 1軍登録：全選手を1人ずつ選んで右の要約を出す（長い状態の文言・名前で広がらないか）
func _select_all(page: Node, label: String) -> void:
	var team: Variant = _gs.my_team()
	if team == null:
		return
	var worst := ""
	for p: Variant in team.players:
		if p.is_pitcher != page.get("pitchers"):
			continue
		page.set("_selected", p)
		page.refresh()
		await _frames(2)
		var over := _overflows()
		if not over.is_empty() and worst.is_empty():
			worst = "%s（%s を選んだとき）" % [label, p.name]
			_report(worst, over)
	_checked += 1
	if worst.is_empty():
		print("OK %s：全選手を選んでもはみ出さない" % label)
	page.clear_selection()


## 選手詳細：自球団の先頭の選手と名前の長い選手の4タブ
func _check_detail(when: String) -> void:
	var ids: Array = load(DETAIL_SCRIPT).team_order(_gs.team)
	if ids.is_empty():
		return
	var longest: String = ids[0]
	for id: String in ids:
		if str(root.get_node("GameData").player(id).get("name", "")).length() \
				> str(root.get_node("GameData").player(longest).get("name", "")).length():
			longest = id
	for id: String in [ids[0], longest]:
		var detail: Node = load(DETAIL_SCRIPT).open(_hub, id, ids)
		await _frames(2)
		for i in 4:
			detail.show_tab(i)
			await _check_screen("%s：選手詳細（%s）タブ%d" % [when, detail.get("_data").get("name", id), i + 1])
		detail.close()
		await _frames(2)


## 記録室（作業10）：全タブ。打撃・投手は今季／通算と規定の有無、デプスは12球団と3つの並び順
func _check_records(when: String) -> void:
	await _open("records")
	var view: Node = _hub.get("_records_view")
	for t: Array in view.TABS:
		view.set_tab(t[0])
		await _check_screen("%s：記録室 %s" % [when, t[1]], 0.0)
		if t[0] in ["bat", "pit"]:
			for mode: Array in [[false, false], [true, true], [true, false]]:
				view.set("_career", mode[0])
				view.set("_qualified", mode[1])
				view.refresh()
				await _check_screen("%s：記録室 %s（%s・%s）" % [when, t[1], "通算" if mode[0] else "今季",
					"規定以上" if mode[1] else "全員"], 0.0)
			view.set("_career", false)
			view.set("_qualified", true)
		elif t[0] == "depth":
			for team: String in root.get_node("GameData").teams():
				view.set_team(team)
				for sort: String in ["now", "future", "age"]:
					view.set("_depth_sort", sort)
					view.refresh()
					await _frames(2)
					var over := _overflows()
					_checked += 1
					if not over.is_empty():
						_report("%s：記録室 デプス（%s・%s）" % [when, team, sort], over)
			view.set("_depth_sort", "now")
			view.set_team(_gs.team)
		elif t[0] == "awards":
			# 表彰の画面を記録室の中に入れたもの（高さが表彰の段階より狭い）
			var inner: Node = view.get("_awards_view")
			for a: Array in inner.TABS:
				inner.set_tab(a[0])
				await _check_screen("%s：記録室 表彰の歴代 %s" % [when, a[1]], 0.0)
	_hub.call("_close_sub_screen")


## 表彰（作業9）：全タブ
func _check_awards(when: String) -> void:
	await _open("awards")
	var view: Node = _hub.get("_awards_view")
	for t: Array in view.TABS:
		view.set_tab(t[0])
		await _check_screen("%s：表彰 %s" % [when, t[1]], 0.0)
	_hub.call("_close_sub_screen")


# --- オフ ---------------------------------------------------------------------------------

func _check_offseason(y: int) -> void:
	var when := "%d年オフ %s" % [y, _gs.phase_name()]
	print("\n-- %s --" % when)
	await _check_screen("%s：ハブ" % when)
	# オフの采配は「見るだけ」の文言が出る（作業11の報告の画面）。全選手を選ぶのは最初の段階だけ
	await _check_tactics(when, ["", "pitchers", "fielders", "order"], _gs.phase == _gs.Phase.AWARDS)
	if y == _last_year and _gs.phase == _gs.Phase.AWARDS:
		await _shot_register()
	await _open("scout")
	await _check_screen("%s：新戦力" % when)
	_hub.call("_close_sub_screen")
	if _gs.phase == _gs.Phase.AWARDS:
		await _check_awards(when)
		await _check_records(when)
	if _gs.fa_open():
		await _check_phase_view("fa", "_fa_view", when)
	elif _gs.contract_open():
		await _check_phase_view("contract", "_contract_view", when)
	elif _gs.release_open():
		await _check_phase_view("release", "_release_view", when)
	elif _gs.draft_open():
		await _check_draft(when)


## スクショ（ウィンドウ付きで出力先を渡したときだけ）：作業11の報告と同じ、オフの采配 → 投手1軍登録で先発の2番手を選んだ画面
func _shot_register() -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	tactics.call("_show_page", "pitchers", true)
	var team: Variant = _gs.my_team()
	var page: Node = tactics.get("_register_pitchers")
	page.set("_selected", team.rotation[1] if team.rotation.size() > 1 else team.rotation[0])
	page.refresh()
	await _settle()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join("layout_fixed_%d_off.png" % _last_year))
	print("  スクショ: layout_fixed_%d_off.png" % _last_year)
	page.clear_selection()
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")


## FA・契約更改・戦力外：全タブを開き、各タブの先頭の選手を選ぶ
func _check_phase_view(key: String, prop: String, when: String) -> void:
	await _open(key)
	var view: Node = _hub.get(prop)
	await _check_screen("%s：%s" % [when, key])
	for i in 4:
		var ids: Array = view.list_ids()
		if not ids.is_empty():
			view.select_player(ids[-1])
			await _check_screen("%s：%s タブ%d 選択" % [when, key, i + 1], 0.0)
			view.select_player(ids[0])
			await _check_screen("%s：%s タブ%d 選択" % [when, key, i + 1], 0.0)
		view.switch_tab(1)
		await _check_screen("%s：%s タブ%d" % [when, key, i + 2], 0.0)
	while view.back():
		pass
	_hub.call("_close_sub_screen")


func _check_draft(when: String) -> void:
	await _open("draft")
	var view: Node = _hub.get("_draft_view")
	await _check_screen("%s：ドラフト 開幕の演出" % when)
	view.finish_overlays()
	await _check_screen("%s：ドラフト 候補一覧" % when)
	for i in 3:
		view.switch_tab(1)
		await _check_screen("%s：ドラフト タブ%d" % [when, i + 2], 0.0)
	# 指名一覧のタブでは候補の一覧が空なので、最初のタブ（情報）に戻してから入札する
	view.switch_tab(1)
	await _frames(1)
	var ids: Array = view.list_ids()
	if not ids.is_empty():
		view.select_candidate(_most_bid(ids))
		await _check_screen("%s：ドラフト 候補を選ぶ" % when, 0.0)
		view.press_action()
		await _check_screen("%s：ドラフト 入札" % when)
		# 抽選の3D演出（作業20）：途中と、飛ばしたあとの結果の場面
		var lot3d: Node = view.lottery_3d()
		if lot3d != null:
			_lottery_3d_seen += 1
			await _check_screen("%s：ドラフト 抽選の3D演出" % when)
			view.back()
			await _check_screen("%s：ドラフト 抽選の3D演出の結果" % when)
		view.finish_overlays()
		await _check_screen("%s：ドラフト 入札のあと" % when)
	while view.back():
		pass
	_hub.call("_close_sub_screen")


## 1位の入札の段階なら CPU球団の入札が最も多い候補（競合して抽選の3D演出が出るように）。ほかは一覧の先頭
func _most_bid(ids: Array) -> String:
	var d: RefCounted = _gs.draft()
	if d == null or d.stage != load("res://sim/draft.gd").Stage["FIRST"] or not d.first_pick_of(_team).is_empty():
		return ids[0]
	var count := {}
	var bids: Dictionary = d.cpu_first_bids()
	for t: String in bids:
		count[bids[t]] = int(count.get(bids[t], 0)) + 1
	var best: String = ids[0]
	for id: String in ids:
		if int(count.get(id, 0)) > int(count.get(best, 0)):
			best = id
	return best


# --- 調べる -------------------------------------------------------------------------------

func _open(key: String) -> void:
	_hub.call("_open_sub_screen", key)
	await _settle()


func _check_screen(label: String, wait := SETTLE_SEC) -> void:
	if wait > 0.0:
		await create_timer(wait).timeout
	await _frames(2)
	_checked += 1
	var over := _overflows()
	if not over.is_empty():
		_report(label, over)


func _report(label: String, over: Array[String]) -> void:
	_failures += 1
	print("NG %s：画面からはみ出す %d件" % [label, over.size()])
	for line in over.slice(0, 8):
		print("    ", line)
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("overflow_%d.png" % _failures))


## 表示中の Control で画面からはみ出すもの（はみ出した枝の一番上だけ。中身の最小幅の内訳を添える）
func _overflows() -> Array[String]:
	var result: Array[String] = []
	_walk(root, result, Rect2(Vector2.ZERO, SCREEN))
	return result


## clip：いま見えている範囲（画面、または画面のルートの包みの枠）。その外へ出たものを数える
func _walk(node: Node, result: Array[String], clip: Rect2) -> void:
	if node is Window and node != root:
		return  # ツールチップ・ポップアップは別のウィンドウ
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return
	# 別の層・top_level（ドラフトの演出など）は親の枠に切り取られず、画面全体に描かれる
	if node is CanvasLayer or (node is CanvasItem and (node as CanvasItem).top_level):
		clip = Rect2(Vector2.ZERO, SCREEN)
	if node is Control:
		var c := node as Control
		var r := _layout_rect(c)
		if r.size.x > 0.0 and r.size.y > 0.0 and _outside(r, clip):
			var where := "画面" if clip.size == SCREEN else "枠 %s" % _rect_text(clip)
			result.append("%s %s が%sの外（最小 %s）%s" % [_name(c), _rect_text(r), where,
				str(c.get_combined_minimum_size()), _widest(c)])
			return
		# 画面のルートの包み（UiTheme.fit_scroll）：はみ出しは防げるが、スクロールバーが出たら枠に収まっていない
		if c is ScrollContainer and c.has_meta("fit_guard"):
			var sc := c as ScrollContainer
			if sc.get_h_scroll_bar().visible or sc.get_v_scroll_bar().visible:
				result.append("%s 中身が枠 %s に収まらずスクロールになった（中身の最小 %s）%s" % [_name(c),
					_rect_text(r), str(sc.get_child(0).get_combined_minimum_size()), _widest(c)])
				return
			# 中身はこの枠で切り取られる。枠からはみ出した部分は見えない（右の要約が欠けるなど）ので、ここから先は枠と比べる
			clip = clip.intersection(r)
		elif c.clip_contents:
			return  # スクロールの中など：親の枠で切り取られる
	for child in node.get_children():
		_walk(child, result, clip)


## 画面上の矩形。選択中のボタンの拡大（UiFx、1.045倍）などの演出の拡大縮小は除く（配置そのものを調べる）
func _layout_rect(c: Control) -> Rect2:
	if c.scale == Vector2.ONE:
		return c.get_global_rect()
	var parent_xform := c.get_global_transform() * c.get_transform().affine_inverse()
	return parent_xform * Rect2(c.position, c.size)


func _outside(r: Rect2, clip: Rect2) -> bool:
	return r.position.x < clip.position.x - TOLERANCE or r.position.y < clip.position.y - TOLERANCE \
		or r.end.x > clip.end.x + TOLERANCE or r.end.y > clip.end.y + TOLERANCE


## 最小幅がいちばん大きい子をたどる（どこで広がったかの手がかり）
func _widest(c: Control) -> String:
	var chain: Array[String] = []
	var node: Control = c
	for depth in 8:
		var best: Control = null
		for child in node.get_children():
			if child is Control and (child as Control).visible:
				if best == null or child.get_combined_minimum_size().x > best.get_combined_minimum_size().x:
					best = child
		if best == null:
			break
		node = best
		var text := ""
		if node is Label:
			text = "「%s」" % (node as Label).text.left(30)
		elif node is Button:
			text = "「%s」" % (node as Button).text.left(30)
		chain.append("%s%s:%d" % [node.get_class(), text, int(node.get_combined_minimum_size().x)])
	return "\n        ← " + " > ".join(chain) if not chain.is_empty() else ""


func _name(c: Control) -> String:
	var parts: Array[String] = []
	var node: Node = c
	while node != null and node != root and parts.size() < 4:
		var n := str(node.name)
		parts.push_front(node.get_class() if n.begins_with("@") else n)
		node = node.get_parent()
	return "/".join(parts)


func _rect_text(r: Rect2) -> String:
	return "(%d,%d)-(%d,%d)" % [int(r.position.x), int(r.position.y), int(r.end.x), int(r.end.y)]


func _check(ok: bool, label: String) -> void:
	if not ok:
		print("NG ", label)
		_failures += 1


func _settle() -> void:
	await create_timer(SETTLE_SEC).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
