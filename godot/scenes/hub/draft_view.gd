# gdlint: disable=max-file-lines,max-public-methods
class_name DraftView
extends VBoxContainer
## オフの「ドラフト」の画面（ハブの可変ボタン「ドラフト会議」から開く。docs/references/draft_list_pawapuro.webp が参考）。
##
## 上に段階の見出し（第1巡選択希望選手／第N巡選択／育成）といまの番、その下にタブ（情報／投手能力／野手能力／指名一覧）と
## 絞り込み・候補の人数。左に候補の一覧（済マーク・名前札・守備位置・経歴・出身・年齢・各能力・当時の評価・将来性）、
## 右に選んだ候補の要約と「入札する／指名する」。一覧の列の見出しを押すとその列で並び替え（もう一度押すと逆順）。
## 仕組みは Draft（GameState.draft()）。
## 進行：開幕の演出 → 1位入札（全球団同時。各球団の入札を1球団ずつ発表 → 重複は抽選の演出。3Dの Lottery3D、早送り中は2D）
## → 外れたら再入札 → 2位以降はウェーバー（指名を1つずつ中継風の札 PickAnnounce で発表し、読み上げる。作業28）
## （CPU球団の指名は自動で進み、「早送り」「自球団の番まで飛ばす」もできる。自球団の番で止まる）→ 育成 → 結果まとめ。
## 操作：札をⒶ／クリックで選び、もう一度Ⓐ／クリック（右クリック）で選手詳細。十字キーで右の「入札する」や上の見出しへ。
## LB/RB（Q/E）でタブ、Ⓑは選択の取り消し→ハブ（ドラフトは途中から再開できる）。

signal message_changed(text: String)

const TABS := [["info", "情報", Color("1e88e5")], ["pitch", "投手能力", Color("e53935")],
	["bat", "野手能力", Color("2e9b48")], ["picks", "指名一覧", Color("8a5cc8")]]
## 列 [キー, 見出し, 幅]。キーは並び替えのキー（Draft.sort_value）
const COLUMNS := {
	"info": [["pos", "位置", 52], ["career", "経歴", 70], ["school", "出身", 210], ["age", "年齢", 58]],
	"pitch": [["pos", "位置", 52], ["velocity", "球速", 80], ["overall", "総合", 62], ["stamina", "スタミナ", 78],
		["k9", "奪三振", 70], ["bb9", "制球", 62]],
	"bat": [["pos", "位置", 52], ["meet", "ミート", 62], ["power", "パワー", 62], ["eye", "選球眼", 62],
		["speed", "走力", 56], ["arm", "肩力", 56], ["defense", "守備", 56]],
}
## 1年目＝入団1年目のシーズン後の総合（作業13。Draft._fill_first_years）
const TAIL_COLUMNS := [["first", "1年目", 60], ["hyouka", "評価", 52], ["future", "将来性", 62]]
## 並び替えのキー（テスト用にまとめて）。名前・出身校以外は大きい順が先
const SORT_KEYS := ["pos", "career", "age", "school", "name", "velocity", "overall", "stamina", "k9", "bb9",
	"meet", "power", "eye", "speed", "arm", "defense", "first", "hyouka", "future"]
## 小さい順が自然なキー（最初に押したとき小さい順）
const ASCENDING_FIRST := ["pos", "career", "age", "school", "name"]
const FILTERS := [["all", "全選手"], ["left", "未指名"], ["投手", "投手"], ["捕手", "捕手"], ["内野手", "内野手"],
	["外野手", "外野手"]]
const POS_SHORT := {"投手": "投", "捕手": "捕", "内野手": "内", "外野手": "外"}
const NAME_WIDTH := 150
const MARK_WIDTH := 56
const ROW_HEIGHT := 36
const RIGHT_WIDTH := 330
## 右の要約の中身の幅（要約のスクロールバーの分を空ける）
const SUMMARY_WIDTH := RIGHT_WIDTH - 40
## CPU球団の指名を自動で進める間隔（秒）。早送り中は FAST
const CPU_STEP_SEC := 0.45
const CPU_STEP_FAST_SEC := 0.06
## 抽選の演出（秒）：光が回る時間と、決まってから次へ進むまで（2Dの演出。早送り中に使う）
const LOTTERY_SPIN_SEC := 1.6
const LOTTERY_HOLD_SEC := 1.0
const OPENING_SEC := 1.8
## 抽選の3D演出（作業20）。早送り中でなければこちら。他球団どうしの抽選は少し速く流す
const LOTTERY_3D_SCENE := preload("res://scenes/draft/lottery_3d.tscn")
const LOTTERY_3D_OTHERS_SPEED := 1.5
## 指名の発表（作業28）：選手名が出るまで（読み上げなし／あり）・経歴が出るまでの間・出しておく秒（速さ「ふつう」）。
## 速さの設定の倍率を掛け、自球団は長め・他球団は少し短め・早送り中は短く読み上げなし。読み上げは終わるまで待つ（上限あり）
const ANNOUNCE_NAME_SEC := 0.9
const ANNOUNCE_NAME_VOICE_SEC := 2.2
const ANNOUNCE_SUB_GAP := 0.5
const ANNOUNCE_HOLD_SEC := 1.4
const ANNOUNCE_SPEEDS := [["ゆっくり", 1.4], ["ふつう", 1.0], ["速め", 0.6], ["自球団だけ", 0.6]]
const ANNOUNCE_MINE_SCALE := 1.5
const ANNOUNCE_OTHERS_SCALE := 0.85
const ANNOUNCE_FAST_SCALE := 0.3
const ANNOUNCE_VOICE_WAIT := 6.0
const VOLUMES := [100, 80, 60, 40, 20]
const DONE_COLOR := Color("8a9199")
const MINE_COLOR := Color("ff6d00")
const BID_COLOR := Color("e53935")

var _palette: UiTheme.Palette
var _tab := "info"
var _filter := "all"
var _sort_key := "hyouka"
var _sort_desc := true
var _selected := ""
var _message := ""
var _shown_key := ""
var _fast := false
var _auto_timer := 0.0
var _shown_opening_year := -1
## 演出を飛ばす（テスト用）
var instant := false

var _stage_label: Label
var _turn_label: Label
var _count_label: Label
var _filter_label: Label
var _tab_buttons := {}
var _header_box: HBoxContainer
var _header_buttons := {}
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _body: HBoxContainer
var _right_panel: PanelContainer
var _summary_box: VBoxContainer
var _action_button: Button
var _finish_button: Button
var _auto_pick_button: Button
var _log_label: Label
var _picks_scroll: ScrollContainer
var _picks_grid: GridContainer
var _status_label: Label
var _fast_button: Button
var _skip_button: Button
var _complete_button: Button
var _overlay: Control
var _overlay_box: VBoxContainer
var _overlay_next: Button
var _overlay_queue: Array = []
var _ids: Array[String] = []
var _tags := {}
var _recent: Array[String] = []
var _voice: DraftVoice
var _announce_elapsed := 0.0
var _announce_total := 0.0
## Ⓑで発表を飛ばした：自球団の番が来るまで他球団の指名は発表しない
var _announce_skip := false


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 6)
	add_child(_build_top())
	add_child(_build_tabs())
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_body.add_child(_build_list())
	_body.add_child(_build_right())
	_picks_scroll = ScrollContainer.new()
	_picks_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picks_scroll.visible = false
	add_child(_picks_scroll)
	_picks_grid = GridContainer.new()
	_picks_grid.columns = 4
	_picks_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picks_grid.add_theme_constant_override("h_separation", 10)
	_picks_grid.add_theme_constant_override("v_separation", 10)
	_picks_scroll.add_child(_picks_grid)
	add_child(_build_bottom())
	_build_overlay()
	_voice = DraftVoice.new()
	add_child(_voice)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_selected = ""
	_message = ""
	_shown_key = ""
	_fast = false
	var d := GameState.draft()
	_tab = "picks" if d != null and d.stage == Draft.Stage.DONE else "info"
	refresh()
	focus_first()
	if d != null and d.picks.is_empty() and d.wave == 1 and _shown_opening_year != d.year:
		_shown_opening_year = d.year
		_show_opening(d)
	elif not _overlay.visible:
		_continue_first()  # 外れ1位の途中でセーブ・画面を閉じたとき


## 戻る：演出中は飛ばす（指名の発表中は発表をまとめて飛ばす）、選択中なら取り消す（true）。何もなければ false（ハブへ戻る）
func back() -> bool:
	if _overlay.visible:
		if announcing():
			skip_announcements()
		else:
			_skip_overlay()
		return true
	if _selected.is_empty():
		return false
	_selected = ""
	_message = ""
	refresh()
	focus_first()
	return true


func switch_tab(delta: int) -> void:
	if _overlay.visible:
		return
	var keys: Array = []
	for t: Array in TABS:
		keys.append(t[0])
	_show_tab(keys[posmod(keys.find(_tab) + delta, keys.size())])


func focus_first() -> void:
	if _overlay.visible:
		_overlay_next.grab_focus()
		return
	if _tab != "picks" and not _ids.is_empty():
		var target: Control = _tags.get(_selected, _tags.get(_ids[0]))
		if target != null:
			target.grab_focus()
			return
	UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	var d := GameState.draft()
	var key := "%s|%s|%s|%s|%s|%d|%s|%s|%s" % [_tab, _filter, _sort_key, str(_sort_desc), _selected,
		d.picks.size() if d != null else -1, str(d.stage) if d != null else "", d.wave if d != null else 0,
		_message]
	if key == _shown_key:
		return
	_shown_key = key
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_id := ""
	for id: String in _tags:
		if _tags[id] == owner:
			focused_id = id
	_render_top(d)
	_render_tabs()
	var picks_mode := _tab == "picks"
	_body.visible = not picks_mode
	_picks_scroll.visible = picks_mode
	if picks_mode:
		_render_picks(d)
	else:
		_render_header()
		_render_list(d)
		_render_summary(d)
	_render_bottom(d)
	if not focused_id.is_empty() and _tags.has(focused_id):
		_tags[focused_id].grab_focus()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _overlay.visible:
		_tick_announce(delta)
		return
	var d := GameState.draft()
	if d == null or d.resolved or (d.stage != Draft.Stage.WAIVER and d.stage != Draft.Stage.IKUSEI):
		return
	if d.is_user_turn():
		return
	_auto_timer += delta
	if _auto_timer < (CPU_STEP_FAST_SEC if _fast else CPU_STEP_SEC):
		return
	_auto_timer = 0.0
	_cpu_step(d)


# --- テスト用 ------------------------------------------------------------------------------

func selected_id() -> String:
	return _selected


func list_ids() -> Array[String]:
	return _ids


func select_candidate(id: String) -> void:
	_on_tag_pressed(id)


## 並び替えを指定する（テスト用。画面では列の見出しを押す）
func set_sort(key: String, desc: bool) -> void:
	_sort_key = key
	_sort_desc = desc
	refresh()


func set_filter(key: String) -> void:
	_filter = key
	refresh()


## 演出を最後まで飛ばす（テスト用）
func finish_overlays() -> void:
	while _overlay.visible:
		_skip_overlay()


func overlay_visible() -> bool:
	return _overlay.visible


## 指名の発表を出しているか
func announcing() -> bool:
	return _overlay.visible and _overlay.get_meta("item", {}).get("kind", "") == "announce"


## いま出ている発表の札（無ければ null。テスト用）
func announce_card() -> PickAnnounce:
	if not announcing():
		return null
	var card: PickAnnounce = _overlay.get_meta("item").get("card")
	return card if card != null and is_instance_valid(card) else null


## 発表を飛ばす（Ⓑ）：待っている発表をすべて消す。ウェーバー・育成の途中なら、自球団の番が来るまで他球団の指名は発表しない
func skip_announcements() -> void:
	_overlay_queue = _overlay_queue.filter(func(it: Dictionary) -> bool: return it["kind"] != "announce")
	_voice.stop()
	var d := GameState.draft()
	if d != null and (d.stage == Draft.Stage.WAIVER or d.stage == Draft.Stage.IKUSEI) and not d.is_user_turn():
		_announce_skip = true
	if announcing():
		_next_overlay()


## 読み上げ（テスト用）
func voice() -> DraftVoice:
	return _voice


## 抽選を3Dの演出で見せるか（早送り中は2Dの演出）
func use_3d_lottery() -> bool:
	return not _fast


## いま出ている抽選の3D演出（無ければ null。テスト用）
func lottery_3d() -> Node:
	var item: Dictionary = _overlay.get_meta("item", {}) if _overlay.visible else {}
	var node: Node = item.get("lottery3d")
	return node if node != null and is_instance_valid(node) else null


## 右の「入札する／指名する」を押す（テスト用）
func press_action() -> void:
	_on_action_pressed()


# --- 上の見出し ----------------------------------------------------------------------------

func _build_top() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(Color("eadfc6"), 10, 3, 0, Color("a88a5c"))
	style.gloss = 0.0
	style.gradient = 0.08
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	_stage_label = Label.new()
	UiTheme.heading(_stage_label, 28, Color("b3261e"), Color.WHITE, 8)
	row.add_child(_stage_label)
	_turn_label = Label.new()
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(_turn_label, 20, UiTheme.TEXT, Color.WHITE, 5, false)
	# 長い説明で画面の右がはみ出さないよう折り返す
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_turn_label.custom_minimum_size = Vector2(200, 0)
	row.add_child(_turn_label)
	var count_panel := PanelContainer.new()
	count_panel.add_theme_stylebox_override("panel", UiTheme.card(Color("2f7fd8"), 8, 3, 1.0))
	count_panel.custom_minimum_size = Vector2(220, 0)
	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(_count_label, 22, UiTheme.TEXT, Color.WHITE, 5, false)
	count_panel.add_child(_count_label)
	row.add_child(count_panel)
	return panel


func _render_top(d: Draft) -> void:
	if d == null:
		_stage_label.text = "ドラフト会議"
		_turn_label.text = "ドラフトはオフの「ドラフト」の段階で行います。"
		_count_label.text = ""
		return
	_stage_label.text = "%d年 %s" % [d.year, d.stage_text()]
	var left := d.remaining().size()
	_count_label.text = "候補 %d人（残り%d）" % [d.candidates.size(), left]
	match d.stage:
		Draft.Stage.FIRST:
			var mine := d.first_pick_of(GameState.team)
			if not mine.is_empty():
				_turn_label.text = "1位は %s に決まりました。ほかの球団の入札を待っています" % d.by_id[mine]["name"]
			elif d.bids.has(GameState.team):
				_turn_label.text = "入札：%s" % d.by_id[d.bids[GameState.team]]["name"]
			else:
				_turn_label.text = "全球団が同時に1位を入札します。候補を選んで「1位で入札する」" if d.wave == 1 \
					else "抽選に外れました。外れ1位を入札してください"
		Draft.Stage.WAIVER, Draft.Stage.IKUSEI:
			var team := d.current_team()
			if d.is_user_turn():
				_turn_label.text = "▶ %sの指名の番です（%s）" % [GameData.short_name(team), _pick_word(d)]
			else:
				_turn_label.text = "%sが指名中…" % GameData.short_name(team) if not team.is_empty() else ""
		_:
			_turn_label.text = "全球団の指名が終わりました。指名した選手は来季、各球団に入団します"
	var ink: Color = MINE_COLOR if d.is_user_turn() else UiTheme.TEXT
	_turn_label.label_settings.font_color = ink


func _pick_word(d: Draft) -> String:
	if d.stage == Draft.Stage.IKUSEI:
		return "育成%d位" % d.round
	if d.stage == Draft.Stage.WAIVER:
		return "%d位" % d.round
	return "1位"


# --- タブ・絞り込み ------------------------------------------------------------------------

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiTheme.small_label("◀ LB", 17, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(124, 42)
		b.add_theme_font_size_override("font_size", 19)
		UiTheme.style_button(b, t[2], Color.WHITE, 10, 6)
		var key: String = t[0]
		b.pressed.connect(func() -> void: _show_tab(key))
		row.add_child(b)
		_tab_buttons[key] = b
	row.add_child(UiTheme.small_label("RB ▶", 17, UiTheme.TEXT, 800))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiTheme.small_label("絞り込み", 17, UiTheme.TEXT, 800))
	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(44, 40)
	UiTheme.style_button(prev, Color("2f7fd8"), Color.WHITE, 8, 4)
	prev.pressed.connect(func() -> void: _turn_filter(-1))
	row.add_child(prev)
	var filter_panel := PanelContainer.new()
	filter_panel.add_theme_stylebox_override("panel", UiTheme.card(Color("2f7fd8"), 8, 3, 1.0))
	filter_panel.custom_minimum_size = Vector2(110, 40)
	_filter_label = Label.new()
	_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_filter_label, 19, UiTheme.TEXT, Color.WHITE, 4, false)
	filter_panel.add_child(_filter_label)
	row.add_child(filter_panel)
	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(44, 40)
	UiTheme.style_button(next, Color("2f7fd8"), Color.WHITE, 8, 4)
	next.pressed.connect(func() -> void: _turn_filter(1))
	row.add_child(next)
	return row


func _render_tabs() -> void:
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.set_pressed_no_signal(key == _tab)
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	for f: Array in FILTERS:
		if f[0] == _filter:
			_filter_label.text = f[1]


func _show_tab(key: String) -> void:
	_tab = key
	_message = ""
	refresh()
	focus_first()


func _turn_filter(delta: int) -> void:
	var keys: Array = []
	for f: Array in FILTERS:
		keys.append(f[0])
	_filter = keys[posmod(keys.find(_filter) + delta, keys.size())]
	refresh()


# --- 一覧 ----------------------------------------------------------------------------------

func _build_list() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(Color("2f7fd8"), 10, 4, 0.97)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_header_box = HBoxContainer.new()
	_header_box.add_theme_constant_override("separation", 2)
	box.add_child(_header_box)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list_box)
	return panel


func _columns() -> Array:
	var cols: Array = [["name", "名前", NAME_WIDTH]]
	cols.append_array(COLUMNS.get(_tab, COLUMNS["info"]))
	cols.append_array(TAIL_COLUMNS)
	return cols


## 列の見出し（押すとその列で並び替え）
func _render_header() -> void:
	for child in _header_box.get_children():
		_header_box.remove_child(child)
		child.queue_free()
	_header_buttons.clear()
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(MARK_WIDTH, 0)
	_header_box.add_child(mark)
	for col: Array in _columns():
		var key: String = col[0]
		var b := Button.new()
		var arrow := ""
		if key == _sort_key:
			arrow = "▼" if _sort_desc else "▲"
		b.text = col[1] + arrow
		b.custom_minimum_size = Vector2(col[2], 32)
		b.add_theme_font_size_override("font_size", 15)
		var color := Color("ff8a3d") if key == _sort_key else Color("4f86d6")
		UiTheme.style_button(b, color, Color.WHITE, 6, 4)
		# 見出しの文字で列が広がらないように（1年目の列を足して画面からはみ出した。作業13）
		b.clip_text = true
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := b.get_theme_stylebox(state)
			sb.content_margin_left = 3
			sb.content_margin_right = 3
		b.tooltip_text = "%sで並び替え（もう一度押すと逆順）" % col[1]
		if col[0] == "first":
			b.tooltip_text = "1年目＝入団1年目のシーズン後の総合（史実の成績から。ノイズなし）\n" + b.tooltip_text
		b.pressed.connect(_on_header_pressed.bind(key))
		_header_box.add_child(b)
		_header_buttons[key] = b


func _on_header_pressed(key: String) -> void:
	if _sort_key == key:
		_sort_desc = not _sort_desc
	else:
		_sort_key = key
		_sort_desc = key not in ASCENDING_FIRST
	_message = ""
	refresh()
	if _header_buttons.has(key):
		_header_buttons[key].grab_focus()


## 一覧に出す候補（絞り込み・並び替え後）
func sorted_candidates(d: Draft) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if d == null:
		return rows
	for c in d.candidates:
		if _filter == "left" and not str(c["picked_by"]).is_empty():
			continue
		if _filter in POS_SHORT and c["pos"] != _filter:
			continue
		rows.append(c)
	var key := _sort_key
	var desc := _sort_desc
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: Variant = Draft.sort_value(a, key)
		var vb: Variant = Draft.sort_value(b, key)
		if va != vb:
			return va > vb if desc else va < vb
		if a["hyouka"] != b["hyouka"]:
			return a["hyouka"] > b["hyouka"]
		return a["id"] < b["id"])
	return rows


func _render_list(d: Draft) -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_tags.clear()
	_ids.clear()
	var rows := sorted_candidates(d)
	if rows.is_empty():
		_list_box.add_child(UiTheme.small_label("候補はいません。" if d != null \
			else "ドラフトはオフの「ドラフト」の段階で行います。", 18, UiTheme.TEXT, 700))
		return
	for c in rows:
		_ids.append(c["id"])
		_list_box.add_child(_row(d, c))


func _row(d: Draft, c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var id: String = c["id"]
	var mark := _mark_label(d, c)
	row.add_child(mark)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(NAME_WIDTH, ROW_HEIGHT - 2)
	tag.font_size = 18
	var p := GameData.player(id)
	if p.is_empty():
		tag.setup_plain(NameTag.family_name(c["name"]), NameTag.pos_color(c["pos"]))
	else:
		tag.setup_player(p, NameTag.family_name(c["name"]))
	tag.selected = id == _selected
	tag.dimmed = not str(c["picked_by"]).is_empty()
	tag.tooltip_text = "%s（%s・%s）%s" % [c["name"], c["pos"], c["school"], _picked_text(c)]
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	for col: Array in _columns().slice(1):
		row.add_child(_cell(c, col[0], col[2]))
	return row


## 済マーク（指名済みの球団の色）・自球団の入札
func _mark_label(d: Draft, c: Dictionary) -> Control:
	var label := Label.new()
	label.custom_minimum_size = Vector2(MARK_WIDTH, ROW_HEIGHT - 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.font(800))
	label.add_theme_font_size_override("font_size", 15)
	var team: String = c["picked_by"]
	if not team.is_empty():
		var colors := GameData.team_colors(team)
		label.text = "済 " + GameData.short_name(team).substr(0, 1)
		label.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
		label.add_theme_stylebox_override("normal", UiTheme.gloss(colors[0], 6, 1, 1))
	elif d != null and d.bids.get(GameState.team, "") == c["id"]:
		label.text = "入札"
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_stylebox_override("normal", UiTheme.gloss(BID_COLOR, 6, 1, 1))
	return label


func _cell(c: Dictionary, key: String, width: int) -> Control:
	if key == "first":
		return _first_cell(c, width)
	if key in ["hyouka", "future"]:
		var rank: String = c["hyouka_rank"] if key == "hyouka" else c["future_rank"]
		var label := UiTheme.rank_label({"rank": rank, "value": 0}, 22)
		label.tooltip_text = "当時の評価（史実の指名順位・競合数から）" if key == "hyouka" \
			else "将来性（入団後の史実の活躍＋ノイズ）"
		label.custom_minimum_size = Vector2(width, 0)
		return label
	if key in ["overall", "stamina", "k9", "bb9", "meet", "power", "eye", "speed", "arm", "defense"]:
		var value := int(c["ratings"].get(key, -1))
		var box := HBoxContainer.new()
		box.custom_minimum_size = Vector2(width, 0)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 2)
		if value < 0:
			box.add_child(UiTheme.small_label("-", 16, UiTheme.TEXT_SUB, 700))
			return box
		box.add_child(UiTheme.rank_label({"rank": ability_rank(value), "value": value}, 19))
		box.add_child(UiTheme.small_label(str(value), 14, UiTheme.TEXT_SUB, 700))
		return box
	var text := ""
	match key:
		"pos":
			text = POS_SHORT.get(c["pos"], "-")
		"career":
			text = c["career"]
		"school":
			text = c["school"]
		"age":
			text = ("%d歳" % int(c["age"])) if int(c["age"]) > 0 else "-"
		"velocity":
			text = ("%dkm" % int(c["velocity"])) if int(c["velocity"]) > 0 else "-"
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if key != "school" else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override("font", UiTheme.font(800 if key == "pos" else 700))
	l.add_theme_font_size_override("font_size", 17 if key != "school" else 15)
	l.add_theme_color_override("font_color", NameTag.pos_color(c["pos"]).darkened(0.45) if key == "pos" \
		else UiTheme.TEXT)
	if key == "age" and not c.get("age_known", false) and int(c["age"]) > 0:
		l.tooltip_text = "生年月日のデータが無いので経歴からの目安"
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## 一覧の「1年目」の列：1年目の総合のランク（2軍の成績だけで動いた値は小さく「2軍」、出場なしは「-」）
func _first_cell(c: Dictionary, width: int) -> Control:
	var first: Dictionary = c.get("first", {})
	var value := int(first.get("overall", -1))
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.tooltip_text = _first_text(c)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	if value < 0:
		box.add_child(UiTheme.small_label("-", 16, UiTheme.TEXT_SUB, 700))
		return box
	box.add_child(UiTheme.rank_label({"rank": ability_rank(value), "value": value}, 19))
	if first.get("status") == "2軍":
		box.add_child(UiTheme.small_label("2軍", 12, UiTheme.TEXT_SUB, 700))
	return box


## 1年目の説明の1行（要約・一覧のヒント）
func _first_text(c: Dictionary) -> String:
	var first: Dictionary = c.get("first", {})
	var d := GameState.draft()
	var entry_year: int = (d.year + 1) if d != null else 0
	var text := "1年目（%d年）" % entry_year
	match first.get("status", "なし"):
		"1軍":
			text += "のシーズン後の能力"
		"2軍":
			text += "：1軍出場なし（2軍の成績での能力）"
		_:
			text += "：出場なし"
	if first.get("partial", false):
		text += "　※%d年はシーズン途中のデータ" % entry_year
	return text


## 能力値のランク（tools/compute_ratings.py と同じしきい値）
static func ability_rank(value: int) -> String:
	if value >= 90:
		return "S"
	if value >= 80:
		return "A"
	if value >= 70:
		return "B"
	if value >= 60:
		return "C"
	if value >= 50:
		return "D"
	if value >= 40:
		return "E"
	if value >= 20:
		return "F"
	return "G"


func _picked_text(c: Dictionary) -> String:
	var team: String = c["picked_by"]
	if team.is_empty():
		return ""
	return "　%s %s" % [GameData.short_name(team), c["pick_label"]]


# --- 右の要約 ------------------------------------------------------------------------------

func _build_right() -> Control:
	_right_panel = PanelContainer.new()
	var style := UiTheme.card(Color("8ecae6"), 10, 3, 0.97)
	style.bg_color = Color("dff1fb")
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_right_panel.add_theme_stylebox_override("panel", style)
	_right_panel.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_right_panel.add_child(box)
	# 要約は長くなる（1年目の能力など）ので、枠を押し広げないようスクロールの中に入れる（作業8のスクショで見つけた）
	var summary_scroll := ScrollContainer.new()
	summary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(summary_scroll)
	_summary_box = VBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 4)
	_summary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_scroll.add_child(_summary_box)
	_action_button = Button.new()
	_action_button.text = "1位で入札する"
	_action_button.custom_minimum_size = Vector2(0, 50)
	_action_button.add_theme_font_size_override("font_size", 22)
	UiTheme.style_button(_action_button, Color("e53935"))
	_action_button.pressed.connect(_on_action_pressed)
	box.add_child(_action_button)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	_auto_pick_button = Button.new()
	_auto_pick_button.text = "おまかせ"
	_auto_pick_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_pick_button.custom_minimum_size = Vector2(0, 40)
	UiTheme.style_button(_auto_pick_button, Color("ff8a3d"), Color.WHITE, 8, 4)
	_auto_pick_button.pressed.connect(_on_auto_pick_pressed)
	line.add_child(_auto_pick_button)
	_finish_button = Button.new()
	_finish_button.text = "選択終了"
	_finish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_finish_button.custom_minimum_size = Vector2(0, 40)
	UiTheme.style_button(_finish_button, Color("6d7680"), Color.WHITE, 8, 4)
	_finish_button.pressed.connect(_on_finish_pressed)
	line.add_child(_finish_button)
	# 直近の指名（4行まで。長い行は「…」で省いて折り返さない）
	_log_label = UiTheme.small_label("", 14, UiTheme.TEXT_SUB, 700)
	_log_label.clip_text = true
	_log_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_log_label.custom_minimum_size = Vector2(RIGHT_WIDTH - 20, 0)
	box.add_child(_log_label)
	return _right_panel


func _render_summary(d: Draft) -> void:
	for child in _summary_box.get_children():
		_summary_box.remove_child(child)
		child.queue_free()
	var c: Dictionary = d.by_id.get(_selected, {}) if d != null else {}
	if c.is_empty():
		var hint := UiTheme.small_label(_hint_text(d), 16, UiTheme.TEXT, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
		_summary_box.add_child(hint)
	else:
		_fill_summary(d, c)
	_render_actions(d, c)
	_log_label.text = "\n".join(_recent.slice(maxi(0, _recent.size() - 4)))


func _hint_text(d: Draft) -> String:
	if d == null:
		return "ドラフトはオフの「ドラフト」の段階で行います。"
	var lines: Array[String] = ["候補を選ぶと、ここに要約が出ます（もう一度Ⓐで選手詳細）。"]
	lines.append("評価＝当時の評価（史実の指名順位・1位の競合数）")
	lines.append("将来性＝入団後の史実の活躍（ノイズあり。CPU球団も同じ見立てで指名します）")
	lines.append("列の見出しを押すと並び替えます。")
	if d.year >= d.data_through - 2:
		lines.append("※%d年のドラフトは入団後の成績がまだ少ないため、将来性は当てになりません（当時の評価で補っています）。" \
			% d.year)
	if d.year + 1 >= Draft.IN_PROGRESS_YEAR:
		lines.append("※%d年秋の新人の1年目（%d年）はシーズン途中のデータです。" % [d.year, d.year + 1])
	return "\n".join(lines)


func _fill_summary(d: Draft, c: Dictionary) -> void:
	var id: String = c["id"]
	var p := GameData.player(id)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(170, 42)
	tag.font_size = 24
	if p.is_empty():
		tag.setup_plain(NameTag.family_name(c["name"]), NameTag.pos_color(c["pos"]))
	else:
		tag.setup_player(p, NameTag.family_name(c["name"]))
	tag.tooltip_text = "Ⓐ／クリックで選手詳細"
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, _ids))
	line.add_child(tag)
	var pos := Label.new()
	pos.text = c["pos"]
	UiTheme.heading(pos, 22, NameTag.pos_color(c["pos"]).darkened(0.45), Color.WHITE, 6)
	line.add_child(pos)
	_summary_box.add_child(line)
	var hand := ""
	if p.get("throws") != null and p.get("bats") != null:
		hand = "　%s投%s打" % [p["throws"], p["bats"]]
	var age := ("%d歳" % int(c["age"])) if int(c["age"]) > 0 else "年齢不明"
	var info := UiTheme.small_label("%s　%s　%s%s\n%s" % [c["name"], c["career"], age, hand, c["school"]], 16,
		UiTheme.TEXT, 700)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	_summary_box.add_child(info)
	var ranks := HBoxContainer.new()
	ranks.add_theme_constant_override("separation", 6)
	ranks.add_child(UiTheme.small_label("当時の評価", 16, UiTheme.TEXT, 800))
	ranks.add_child(UiTheme.rank_label({"rank": c["hyouka_rank"], "value": 0}, 30))
	ranks.add_child(UiTheme.small_label("　将来性", 16, UiTheme.TEXT, 800))
	ranks.add_child(UiTheme.rank_label({"rank": c["future_rank"], "value": 0}, 30))
	_summary_box.add_child(ranks)
	_summary_box.add_child(_ability_grid(c))
	_summary_box.add_child(_first_grid(c))
	var intro := UiTheme.small_label("「%s」" % c["intro"], 15, Color("1e63c8"), 700)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	_summary_box.add_child(intro)
	var state := ""
	if not str(c["picked_by"]).is_empty():
		state = "済：%s %s" % [GameData.short_name(c["picked_by"]), c["pick_label"]]
	else:
		state = "未指名"
	state += "　（史実：%s %s）" % [GameData.short_name(c["hist_team"]), c["hist_label"]]
	if c.get("synthetic", false):
		state += "\n※能力値データが無いため、近い候補の能力を仮に使っています"
	var state_label := UiTheme.small_label(state, 14, UiTheme.TEXT_SUB, 700)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	_summary_box.add_child(state_label)


func _ability_grid(c: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	var keys: Array = [["velocity", "球速"], ["overall", "総合"], ["stamina", "スタミナ"], ["bb9", "制球"],
		["k9", "奪三振"]] if c["pitcher"] else [["meet", "ミート"], ["power", "パワー"], ["eye", "選球眼"],
		["speed", "走力"], ["arm", "肩力"], ["defense", "守備"]]
	for k: Array in keys:
		grid.add_child(UiTheme.small_label(k[1], 15, UiTheme.TEXT, 800))
		if k[0] == "velocity":
			var v := int(c["velocity"])
			grid.add_child(UiTheme.small_label("%dkm/h" % v if v > 0 else "-", 16, UiTheme.TEXT, 800))
			continue
		var value := int(c["ratings"].get(k[0], -1))
		if value < 0:
			grid.add_child(UiTheme.small_label("-", 16, UiTheme.TEXT_SUB, 700))
		else:
			grid.add_child(UiTheme.rank_label({"rank": ability_rank(value), "value": value}, 20))
	return grid


## 要約の1年目の能力：見出しの1行と主要能力のランク（3組ずつ）
func _first_grid(c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var first: Dictionary = c.get("first", {})
	var title := UiTheme.small_label(_first_text(c), 14, Color("8a5cc8"), 800)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	box.add_child(title)
	if int(first.get("overall", -1)) < 0:
		return box
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 0)
	var keys: Array = [["overall", "総合"], ["stamina", "スタミナ"], ["bb9", "制球"], ["k9", "奪三振"]] 		if c["pitcher"] else [["overall", "総合"], ["meet", "ミート"], ["power", "パワー"], ["eye", "選球眼"],
		["speed", "走力"], ["defense", "守備"]]
	for k: Array in keys:
		var value := int(first["overall"]) if k[0] == "overall" and not c["pitcher"] 			else int(first.get("ratings", {}).get(k[0], -1))
		grid.add_child(UiTheme.small_label(k[1], 14, UiTheme.TEXT, 800))
		if value < 0:
			grid.add_child(UiTheme.small_label("-", 15, UiTheme.TEXT_SUB, 700))
		else:
			grid.add_child(UiTheme.rank_label({"rank": ability_rank(value), "value": value}, 17))
	if c["pitcher"] and int(first.get("velocity", 0)) > 0:
		grid.add_child(UiTheme.small_label("球速", 14, UiTheme.TEXT, 800))
		grid.add_child(UiTheme.small_label("%dkm" % int(first["velocity"]), 14, UiTheme.TEXT, 800))
	box.add_child(grid)
	return box


func _render_actions(d: Draft, c: Dictionary) -> void:
	var can_pick := false
	var text := "指名する"
	var user_turn := false
	if d != null:
		match d.stage:
			Draft.Stage.FIRST:
				user_turn = d.first_pick_of(GameState.team).is_empty()
				text = "1位で入札する"
				can_pick = user_turn and not c.is_empty() and str(c["picked_by"]).is_empty()
			Draft.Stage.WAIVER, Draft.Stage.IKUSEI:
				user_turn = d.is_user_turn()
				text = "%sで指名する" % _pick_word(d)
				can_pick = user_turn and not c.is_empty() and str(c["picked_by"]).is_empty()
			_:
				text = "ドラフトは終了しました"
	_action_button.text = text
	_action_button.disabled = not can_pick
	_auto_pick_button.disabled = not user_turn
	_auto_pick_button.text = "おまかせで入札" if d != null and d.stage == Draft.Stage.FIRST else "おまかせ"
	_finish_button.disabled = not (user_turn and d.stage != Draft.Stage.FIRST)


# --- 指名一覧 ------------------------------------------------------------------------------

func _render_picks(d: Draft) -> void:
	for child in _picks_grid.get_children():
		_picks_grid.remove_child(child)
		child.queue_free()
	_tags.clear()
	_ids.clear()
	if d == null:
		return
	var order: Array[String] = [GameState.team]
	for t in d.teams:
		if t != GameState.team:
			order.append(t)
	for t in order:
		_picks_grid.add_child(_team_card(d, t))


func _team_card(d: Draft, team: String) -> Control:
	var panel := PanelContainer.new()
	var colors := GameData.team_colors(team)
	var style := UiTheme.card(colors[0], 8, 3 if team == GameState.team else 2, 0.97)
	style.content_margin_left = 6
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var band := PanelContainer.new()
	var band_style := UiTheme.gloss(colors[0], 5, 1, 1)
	band_style.content_margin_top = 1
	band_style.content_margin_bottom = 2
	band.add_theme_stylebox_override("panel", band_style)
	var title := Label.new()
	var picks := d.picks_of(team)
	var reg := picks.filter(func(x: Dictionary) -> bool: return not x["ikusei"]).size()
	title.text = "%s　%d人＋育成%d" % [GameData.short_name(team), reg, picks.size() - reg]
	var ink := UiTheme.text_on(colors[0])
	UiTheme.heading(title, 16, ink, UiTheme.outline_for(ink, colors[0]), 4, false)
	band.add_child(title)
	box.add_child(band)
	for rec in picks:
		var c: Dictionary = d.by_id[rec["id"]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var label_w := UiTheme.small_label(rec["label"], 13, UiTheme.TEXT_SUB, 800)
		label_w.custom_minimum_size = Vector2(54, 0)
		row.add_child(label_w)
		var tag := NameTag.new()
		tag.custom_minimum_size = Vector2(96, 24)
		tag.font_size = 14
		var p := GameData.player(rec["id"])
		if p.is_empty():
			tag.setup_plain(NameTag.family_name(c["name"]), NameTag.pos_color(c["pos"]))
		else:
			tag.setup_player(p, NameTag.family_name(c["name"]))
		var pid: String = rec["id"]
		tag.tooltip_text = "%s（%s・%s）評価%s 将来性%s" % [c["name"], c["pos"], c["school"], c["hyouka_rank"],
			c["future_rank"]]
		tag.pressed.connect(func() -> void: PlayerDetail.open(tag, pid, _ids))
		row.add_child(tag)
		_tags[pid] = tag
		_ids.append(pid)
		row.add_child(UiTheme.rank_label({"rank": c["future_rank"], "value": 0}, 15))
		box.add_child(row)
	if picks.is_empty():
		box.add_child(UiTheme.small_label("（まだ指名なし）", 13, UiTheme.TEXT_SUB, 700))
	return panel


# --- 下の帯 --------------------------------------------------------------------------------

func _build_bottom() -> Control:
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	_status_label = UiTheme.small_label("", 16, UiTheme.TEXT, 700)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status_label)
	_fast_button = Button.new()
	_fast_button.text = "早送り"
	_fast_button.toggle_mode = true
	_fast_button.custom_minimum_size = Vector2(110, 42)
	UiTheme.style_button(_fast_button, Color("2f7fd8"), Color.WHITE, 8, 4)
	_fast_button.toggled.connect(func(on: bool) -> void: _fast = on)
	bottom.add_child(_fast_button)
	_skip_button = Button.new()
	_skip_button.text = "自球団の番まで飛ばす"
	_skip_button.custom_minimum_size = Vector2(210, 42)
	UiTheme.style_button(_skip_button, Color("2e9b48"), Color.WHITE, 8, 4)
	_skip_button.pressed.connect(_on_skip_pressed)
	bottom.add_child(_skip_button)
	_complete_button = Button.new()
	_complete_button.text = "残りをおまかせで終える"
	_complete_button.custom_minimum_size = Vector2(230, 42)
	UiTheme.style_button(_complete_button, Color("8a5cc8"), Color.WHITE, 8, 4)
	_complete_button.pressed.connect(_on_complete_pressed)
	bottom.add_child(_complete_button)
	return bottom


func _render_bottom(d: Draft) -> void:
	var waiting := d != null and (d.stage == Draft.Stage.WAIVER or d.stage == Draft.Stage.IKUSEI) \
		and not d.is_user_turn()
	_fast_button.disabled = not waiting
	_skip_button.disabled = not waiting
	_complete_button.disabled = d == null or d.resolved
	if not _message.is_empty():
		_status_label.text = _message
	elif d == null:
		_status_label.text = ""
	elif d.resolved:
		var mine := d.picks_of(GameState.team)
		var names: Array[String] = []
		for rec in mine:
			names.append("%s %s" % [rec["label"], rec["name"]])
		_status_label.text = "%sの指名：%s。可変ボタン「春季キャンプへ」で翌年へ進みます。" % [
			GameData.short_name(GameState.team), "、".join(names) if not names.is_empty() else "なし"]
	elif d.stage == Draft.Stage.FIRST:
		_status_label.text = "候補を選んで「1位で入札する」。重複したら抽選です。支配下の空き：あと%d人" % maxi(0, d.user_room)
	elif d.is_user_turn():
		_status_label.text = "候補を選んで「%sで指名する」。指名を終えるときは「選択終了」。支配下の空き：あと%d人" % [
			_pick_word(d), maxi(0, d.user_room - d.user_reg_count())]
	else:
		_status_label.text = "他球団が指名しています（早送り・自球団の番まで飛ばすこともできます）。"
	message_changed.emit(_status_label.text)


# --- 操作 ----------------------------------------------------------------------------------

func _on_tag_pressed(id: String) -> void:
	if _selected == id:
		PlayerDetail.open(_tags.get(id, self), id, _ids)
		return
	_selected = id
	_message = ""
	refresh()


func _on_action_pressed() -> void:
	var d := GameState.draft()
	if d == null or _selected.is_empty():
		return
	if d.stage == Draft.Stage.FIRST:
		var error := d.user_bid(_selected)
		if not error.is_empty():
			_message = error
			refresh()
			return
		_run_wave(d)
		return
	var c: Dictionary = d.by_id[_selected]
	var error := d.user_pick(_selected)
	if not error.is_empty():
		_message = error
		refresh()
		return
	_note_pick(d, d.picks[-1])
	_announce_pick(d.picks[-1])
	_message = "%sを%sで指名しました。" % [c["name"], d.picks[-1]["label"]]
	_after_change(d)


func _on_auto_pick_pressed() -> void:
	var d := GameState.draft()
	if d == null:
		return
	if d.stage == Draft.Stage.FIRST:
		if d.first_pick_of(GameState.team).is_empty():
			_run_wave(d)
		return
	var rec := d.user_auto_pick()
	if rec.is_empty():
		_message = "%sの指名を終えました。" % ("育成" if d.stage == Draft.Stage.IKUSEI else "本指名")
	else:
		_note_pick(d, rec)
		_message = "おまかせで%sを%sで指名しました。" % [rec["name"], rec["label"]]
	_after_change(d)


func _on_finish_pressed() -> void:
	var d := GameState.draft()
	if d == null or not d.is_user_turn():
		return
	var ikusei := d.stage == Draft.Stage.IKUSEI
	d.user_finish()
	_message = "%sの指名を終えました。" % ("育成" if ikusei else "本指名")
	_after_change(d)


func _on_skip_pressed() -> void:
	var d := GameState.draft()
	if d == null:
		return
	for rec in d.run_until_user():
		_note_pick(d, rec)
	_message = ""
	_after_change(d)


func _on_complete_pressed() -> void:
	var d := GameState.draft()
	if d == null or d.resolved:
		return
	var before := d.picks.size()
	GameState.draft_resolve()
	_message = "残り%d人をおまかせで指名し、ドラフトを終えました。" % (d.picks.size() - before)
	_selected = ""
	_show_tab("picks")


func _cpu_step(d: Draft) -> void:
	var rec := d.cpu_step()
	if not rec.is_empty():
		_note_pick(d, rec)
		_announce_pick(rec)
	_after_change(d)
	if d.is_user_turn():
		_announce_skip = false
		UiFx.bump(_turn_label, 1.08)
		focus_first()


func _note_pick(d: Draft, rec: Dictionary) -> void:
	var c: Dictionary = d.by_id[rec["id"]]
	_recent.append("%s %s：%s（%s・%s）" % [rec["label"], GameData.short_name(rec["team"]), c["name"],
		POS_SHORT.get(c["pos"], ""), c["career"]])
	if _recent.size() > 30:
		_recent = _recent.slice(_recent.size() - 30)


## 指名が進んだあと：終われば入団させて指名一覧へ
func _after_change(d: Draft) -> void:
	if d.stage == Draft.Stage.DONE and not d.resolved:
		GameState.draft_sync()
		_message = "ドラフト会議が終わりました。"
		_selected = ""
		_show_tab("picks")
		return
	if not _selected.is_empty() and not str(d.by_id.get(_selected, {}).get("picked_by", "")).is_empty() \
			and (d.is_user_turn() or d.stage == Draft.Stage.FIRST):
		_selected = ""
	GameState.draft_sync()
	refresh()


## 自球団の1位が決まっていて、CPU球団にだけ外れが残っているときは、次の入札（外れ1位）を自動で締める。
## 締めたら true（演出が出る）。これが無いと入札のボタンがすべて押せず「おまかせ」でしか進めなかった（作業12）
func _continue_first() -> bool:
	var d := GameState.draft()
	if d == null or d.stage != Draft.Stage.FIRST or d.first_pick_of(GameState.team).is_empty():
		return false
	_run_wave(d)
	return true


## 1位の入札を締める：抽選の演出 → 結果の一覧
func _run_wave(d: Draft) -> void:
	var results := d.run_first_wave()
	var lots := d.last_lotteries()
	lots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (GameState.team in a["teams"]) and not (GameState.team in b["teams"]))
	_overlay_queue.clear()
	# 各球団の入札を1球団ずつ発表（2巡目の指名順）→ 抽選 → 結果の一覧
	var wave_no := d.wave - 1
	var bids := results.duplicate()
	bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return d.order.find(a["team"]) < d.order.find(b["team"]))
	for r: Dictionary in bids:
		if _announce_on(r["team"] == GameState.team):
			_overlay_queue.append({"kind": "announce", "rec": {"team": r["team"], "id": r["id"], "round": 1,
				"ikusei": false}, "note": "" if wave_no <= 1 else "外れ1位（%d回目の入札）" % wave_no})
	for lot in lots:
		_overlay_queue.append({"kind": "lottery", "lot": lot})
	_overlay_queue.append({"kind": "wave", "results": results, "wave": d.wave - 1})
	for r in results:
		if r["won"]:
			_note_pick(d, {"label": "1位", "team": r["team"], "id": r["id"]})
	_selected = ""
	_message = ""
	GameState.draft_sync()
	refresh()
	_next_overlay()


# --- 演出（開幕・抽選・入札の結果） --------------------------------------------------------

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.top_level = true
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.1, 0.2, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(Color("fff6dc"), 16, 4, 0, Color("c8a14b"))
	style.gloss = 0.0
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 10)
	box.add_child(_overlay_box)
	_overlay_next = Button.new()
	_overlay_next.text = "次へ"
	_overlay_next.custom_minimum_size = Vector2(220, 48)
	_overlay_next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(_overlay_next, Color("e53935"))
	_overlay_next.pressed.connect(_skip_overlay)
	box.add_child(_overlay_next)


func _place_overlay() -> void:
	_overlay.global_position = get_viewport_rect().position
	_overlay.size = get_viewport_rect().size


func _clear_overlay() -> void:
	for child in _overlay_box.get_children():
		_overlay_box.remove_child(child)
		child.queue_free()


func _show_opening(d: Draft) -> void:
	_overlay_queue.push_front({"kind": "opening", "draft": d})
	_next_overlay()


## 次の演出を出す（無ければ閉じる）
func _next_overlay() -> void:
	if _overlay_queue.is_empty():
		_voice.stop()
		_overlay.visible = false
		if _continue_first():
			return
		refresh()
		focus_first()
		return
	var item: Dictionary = _overlay_queue.pop_front()
	_clear_overlay()
	_place_overlay()
	_overlay.visible = true
	_overlay.set_meta("item", item)
	match item["kind"]:
		"opening":
			_render_opening(item["draft"])
		"lottery":
			_render_lottery(item["lot"])
		"announce":
			_render_announce(item)
		"wave":
			_render_wave(item["results"], item["wave"])
	_overlay_next.grab_focus()
	UiFx.fade_in(_overlay_box)


func _skip_overlay() -> void:
	var item: Dictionary = _overlay.get_meta("item", {})
	if item.get("kind", "") == "announce":
		var card: PickAnnounce = item.get("card")
		if card != null and is_instance_valid(card) and not card.is_revealed():
			card.reveal_all()
			return
		_voice.stop()
	if item.get("kind", "") == "lottery" and not item.get("revealed", false):
		_reveal_lottery(item)
		return
	_next_overlay()


func _render_opening(d: Draft) -> void:
	var title := Label.new()
	title.text = "%d年 プロ野球ドラフト会議" % d.year
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(title, 44, Color("b3261e"), Color.WHITE, 10)
	_overlay_box.add_child(title)
	var sub := Label.new()
	sub.text = "新人選手選択会議・育成選手選択会議　候補 %d人" % d.candidates.size()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(sub, 22, UiTheme.TEXT, Color.WHITE, 5, false)
	_overlay_box.add_child(sub)
	var order := Label.new()
	var names: Array[String] = []
	for t in d.order:
		names.append(GameData.short_name(t))
	order.text = "2巡目の指名順：" + " → ".join(names)
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order.custom_minimum_size = Vector2(840, 0)
	UiTheme.heading(order, 16, UiTheme.TEXT_SUB, Color.WHITE, 3, false)
	_overlay_box.add_child(order)
	var hint := UiTheme.small_label("まずは全球団が同時に1位を入札します。重複したら抽選で交渉権を決めます。", 17,
		UiTheme.TEXT, 700)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(hint)
	_overlay_next.text = "開始"
	title.pivot_offset = Vector2(420, 30)
	title.scale = Vector2(0.6, 0.6)
	var tw := title.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "scale", Vector2.ONE, 0.35)


# --- 指名の発表（作業28） ------------------------------------------------------------------

## 指名を発表するか：演出を飛ばすとき（テスト）はしない。自球団はいつも、他球団は Ⓑで飛ばした間と「自球団だけ」の設定ではしない
func _announce_on(mine: bool) -> bool:
	if instant:
		return false
	if mine:
		return true
	return not _announce_skip and int(GameSettings.get_value("draft", "announce_speed")) != ANNOUNCE_SPEEDS.size() - 1


func _announce_pick(rec: Dictionary) -> void:
	if not _announce_on(rec["team"] == GameState.team):
		return
	_overlay_queue.append({"kind": "announce", "rec": rec, "note": ""})
	if not _overlay.visible:
		_next_overlay()


## 発表の札：球団の帯 → 選手名 → 守備位置・出身校。読み上げ（自球団はチャイムも）。時間が来て読み上げが終われば次へ
func _render_announce(item: Dictionary) -> void:
	var d := GameState.draft()
	var info := PickAnnounce.info_for(d, item["rec"], GameState.team, str(item.get("note", "")))
	var mine: bool = info["mine"]
	var fast := _fast and not mine
	var voice_on := bool(GameSettings.get_value("voice", "enabled")) and not fast
	var speed: Array = ANNOUNCE_SPEEDS[clampi(int(GameSettings.get_value("draft", "announce_speed")), 0,
		ANNOUNCE_SPEEDS.size() - 1)]
	var k: float = float(speed[1]) * (ANNOUNCE_MINE_SCALE if mine else ANNOUNCE_OTHERS_SCALE) \
		* (ANNOUNCE_FAST_SCALE if fast else 1.0)
	var name_at := (ANNOUNCE_NAME_VOICE_SEC if voice_on else ANNOUNCE_NAME_SEC) * k
	var sub_at := name_at + ANNOUNCE_SUB_GAP * k
	_announce_total = sub_at + ANNOUNCE_HOLD_SEC * k
	_announce_elapsed = 0.0
	var card := PickAnnounce.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_skip_overlay())
	_overlay_box.add_child(card)
	card.play(info, name_at, sub_at)
	item["card"] = card
	_overlay_box.add_child(_announce_settings_row())
	_overlay_next.text = "次へ"
	if voice_on:
		_voice.speak(PickAnnounce.voice_parts(info))
	else:
		_voice.stop()
	if mine:
		_voice.chime()


func _tick_announce(delta: float) -> void:
	if not announcing():
		return
	_announce_elapsed += delta
	var voice_done := not _voice.is_busy() or _announce_elapsed >= _announce_total + ANNOUNCE_VOICE_WAIT
	if _announce_elapsed >= _announce_total and voice_done:
		_voice.stop()
		_next_overlay()


## 発表の下の操作：早送り・発表の速さ・読み上げのオンオフ・音量・発表を飛ばす（設定は user://settings.cfg に残る）
func _announce_settings_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var fast := _small_button("早送り", Color("2f7fd8"))
	fast.toggle_mode = true
	fast.button_pressed = _fast
	fast.toggled.connect(func(on: bool) -> void:
		_fast = on
		_fast_button.set_pressed_no_signal(on))
	row.add_child(fast)
	var speed := _small_button("", Color("6d7680"))
	var show_speed := func() -> void:
		speed.text = "発表：%s" % ANNOUNCE_SPEEDS[int(GameSettings.get_value("draft", "announce_speed"))][0]
	show_speed.call()
	speed.pressed.connect(func() -> void:
		GameSettings.set_value("draft", "announce_speed",
			(int(GameSettings.get_value("draft", "announce_speed")) + 1) % ANNOUNCE_SPEEDS.size())
		show_speed.call())
	row.add_child(speed)
	var voice_button := _small_button("", Color("6d7680"))
	var show_voice := func() -> void:
		voice_button.text = "読み上げ：%s" % ("オン" if bool(GameSettings.get_value("voice", "enabled")) else "オフ")
	show_voice.call()
	voice_button.pressed.connect(func() -> void:
		var on := not bool(GameSettings.get_value("voice", "enabled"))
		GameSettings.set_value("voice", "enabled", on)
		if not on:
			_voice.stop()
		show_voice.call())
	row.add_child(voice_button)
	var volume := _small_button("", Color("6d7680"))
	var show_volume := func() -> void:
		volume.text = "音量：%d%%" % int(GameSettings.get_value("voice", "volume"))
	show_volume.call()
	volume.pressed.connect(func() -> void:
		var i := VOLUMES.find(int(GameSettings.get_value("voice", "volume")))
		GameSettings.set_value("voice", "volume", VOLUMES[(i + 1) % VOLUMES.size()])
		show_volume.call())
	row.add_child(volume)
	var skip := _small_button("発表を飛ばす（Ⓑ）", Color("8a5cc8"))
	skip.pressed.connect(skip_announcements)
	row.add_child(skip)
	return row


func _small_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 15)
	UiTheme.style_button(b, color, Color.WHITE, 8, 4)
	return b


func _render_lottery(lot: Dictionary) -> void:
	var d := GameState.draft()
	var c: Dictionary = d.by_id[lot["id"]]
	var use_3d := use_3d_lottery()
	var title := Label.new()
	title.text = "1位 抽選（%d球団競合）" % lot["teams"].size()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(title, 26 if use_3d else 30, Color("b3261e"), Color.WHITE, 8)
	_overlay_box.add_child(title)
	var who := Label.new()
	who.text = "%s（%s・%s）" % [c["name"], c["pos"], c["school"]]
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(who, 28 if use_3d else 34, UiTheme.TEXT, Color.WHITE, 8)
	_overlay_box.add_child(who)
	if use_3d:
		_render_lottery_3d(lot)
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_overlay_box.add_child(row)
	var boxes: Array[PanelContainer] = []
	for t: String in lot["teams"]:
		var env := PanelContainer.new()
		var colors := GameData.team_colors(t)
		env.add_theme_stylebox_override("panel", UiTheme.gloss(colors[0], 10, 3, 4))
		env.custom_minimum_size = Vector2(118, 120)
		var label := Label.new()
		label.text = GameData.short_name(t) + ("\n（自球団）" if t == GameState.team else "")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var ink := UiTheme.text_on(colors[0])
		UiTheme.heading(label, 20, ink, UiTheme.outline_for(ink, colors[0]), 5, false)
		env.add_child(label)
		env.set_meta("team", t)
		row.add_child(env)
		boxes.append(env)
	var result := Label.new()
	result.name = "LotteryResult"
	result.text = "抽選中…"
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(result, 30, Color("1e63c8"), Color.WHITE, 8)
	_overlay_box.add_child(result)
	_overlay_next.text = "結果を見る"
	var item: Dictionary = _overlay.get_meta("item")
	item["boxes"] = boxes
	item["result"] = result
	if instant:
		_reveal_lottery(item)
		return
	# 光が封筒を順に回り、だんだん遅くなって当たりの球団で止まる
	var winner_index: int = lot["teams"].find(lot["winner"])
	var steps := boxes.size() * 3 + winner_index
	var tw := create_tween()
	item["tween"] = tw
	for i in steps + 1:
		var k := i % boxes.size()
		var dt := 0.04 + 0.16 * pow(float(i) / float(steps), 2.0) * LOTTERY_SPIN_SEC / 1.6
		tw.tween_callback(_highlight.bind(boxes, k)).set_delay(dt)
	tw.tween_callback(func() -> void: _reveal_lottery(item)).set_delay(0.25)



## 3Dの演出（Lottery3D）：宴会場で各球団の代表者が順にくじを引き、同時に開けて、当たりが喜ぶ（作業20・29）。
## 当たりは lot["winner"] をそのまま渡す。当選の瞬間に結果の文言を出す。Ⓐ（「結果を見る」）・Ⓑ（back）・演出のクリックで飛ばせる
func _render_lottery_3d(lot: Dictionary) -> void:
	var item: Dictionary = _overlay.get_meta("item")
	var view := LOTTERY_3D_SCENE.instantiate() as Lottery3D
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay_box.add_child(view)
	var result := Label.new()
	result.name = "LotteryResult"
	result.text = "抽選中…"
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(result, 28, Color("1e63c8"), Color.WHITE, 8)
	_overlay_box.add_child(result)
	_overlay_next.text = "結果を見る"
	item["lottery3d"] = view
	item["result"] = result
	view.revealed.connect(func(_winner: String) -> void: _reveal_lottery(item))
	view.clicked.connect(_skip_overlay)
	var mine: bool = GameState.team in lot["teams"]
	var d := GameState.draft()
	view.play(lot, {"user_team": GameState.team, "speed": 1.0 if mine else LOTTERY_3D_OTHERS_SPEED,
		"year": d.year, "all_teams": d.teams})
	if instant:
		_reveal_lottery(item)


func _highlight(boxes: Array[PanelContainer], index: int) -> void:
	for i in boxes.size():
		var b := boxes[i]
		if not is_instance_valid(b):
			return
		b.modulate = Color(1.25, 1.25, 1.25) if i == index else Color(0.7, 0.7, 0.7)
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(1.08, 1.08) if i == index else Vector2.ONE


func _reveal_lottery(item: Dictionary) -> void:
	if item.get("revealed", false):
		return
	item["revealed"] = true
	var tw: Tween = item.get("tween")
	if tw != null and tw.is_valid():
		tw.kill()
	var view: Lottery3D = item.get("lottery3d")
	if view != null and is_instance_valid(view):
		view.skip()
	var lot: Dictionary = item["lot"]
	var boxes: Array = item.get("boxes", [])
	for b: PanelContainer in boxes:
		if not is_instance_valid(b):
			continue
		var won: bool = b.get_meta("team") == lot["winner"]
		b.modulate = Color(1.15, 1.15, 1.15) if won else Color(0.55, 0.55, 0.55)
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(1.18, 1.18) if won else Vector2(0.92, 0.92)
	var result: Label = item.get("result")
	if result != null and is_instance_valid(result):
		var mine: bool = lot["winner"] == GameState.team
		var lost: bool = not mine and GameState.team in lot["teams"]
		result.text = "%s が交渉権を獲得！%s" % [GameData.short_name(lot["winner"]),
			"" if not lost else "（自球団は外れ）"]
		result.label_settings.font_color = MINE_COLOR if mine else (Color("6d7680") if lost else Color("1e63c8"))
		UiFx.bump(result, 1.2)
	_overlay_next.text = "次へ"


func _render_wave(results: Array, wave_no: int) -> void:
	var d := GameState.draft()
	var title := Label.new()
	title.text = "1位入札の結果" if wave_no == 1 else "外れ1位（%d回目）の入札の結果" % wave_no
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(title, 28, Color("b3261e"), Color.WHITE, 8)
	_overlay_box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	_overlay_box.add_child(grid)
	var rows: Array = results.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return d.teams.find(a["team"]) < d.teams.find(b["team"]))
	for r: Dictionary in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var chip := Label.new()
		var colors := GameData.team_colors(r["team"])
		chip.text = GameData.short_name(r["team"])
		chip.custom_minimum_size = Vector2(110, 30)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
		chip.add_theme_font_override("font", UiTheme.font(800))
		chip.add_theme_font_size_override("font_size", 16)
		chip.add_theme_stylebox_override("normal", UiTheme.gloss(colors[0], 6, 1, 1))
		line.add_child(chip)
		var c: Dictionary = d.by_id[r["id"]]
		var name_label := UiTheme.small_label("%s（%s）" % [c["name"], POS_SHORT.get(c["pos"], "")], 17,
			UiTheme.TEXT, 800)
		name_label.custom_minimum_size = Vector2(190, 0)
		line.add_child(name_label)
		var res := "交渉権獲得" if r["won"] else "抽選で外れ"
		if r["won"] and r["lottery"]:
			res += "（%d球団の抽選）" % r["rivals"]
		elif r["won"]:
			res += "（単独）"
		var res_label := UiTheme.small_label(res, 15, MINE_COLOR if r["won"] and r["team"] == GameState.team \
			else (Color("2e9b48") if r["won"] else Color("8a9199")), 800)
		line.add_child(res_label)
		grid.add_child(line)
	var foot := ""
	if d.stage == Draft.Stage.FIRST:
		foot = "外れた球団はもう一度入札します（外れ1位）。" + ("自球団も外れ1位を選んでください。" \
			if d.first_pick_of(GameState.team).is_empty() else "")
	else:
		foot = "全球団の1位が決まりました。2位からはウェーバー（下位の球団から）で指名します。"
	var foot_label := UiTheme.small_label(foot, 17, UiTheme.TEXT, 700)
	foot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(foot_label)
	_overlay_next.text = "次へ"
