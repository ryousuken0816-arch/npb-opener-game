# gdlint: disable=max-file-lines,max-public-methods
class_name DraftView
extends VBoxContainer
## オフの「ドラフト」の画面（ハブの可変ボタン「ドラフト会議」から開く。docs/references/draft_list_pawapuro.webp が参考）。
##
## 上に段階の見出し（第1巡選択希望選手／第N巡選択／育成）といまの番、その下にタブ（情報／投手能力／野手能力／指名一覧）と
## 絞り込み・候補の人数。左に候補の一覧（済マーク・名前札・守備位置・経歴・出身・年齢・各能力・当時の評価・予想）、
## 右に選んだ候補の要約と「入札する／指名する」。一覧の列の見出しを押すとその列で並び替え（もう一度押すと逆順）。
## 仕組みは Draft（GameState.draft()）。
## 進行：開幕の演出 → 1位入札（全球団同時。各球団の入札を1球団ずつ発表 → 重複は抽選の演出。3Dの Lottery3D、早送り中は2D）
## → 外れたら再入札 → 2位以降はウェーバー（指名を1つずつ中継風の札 PickAnnounce で発表し、読み上げる。作業28）
## （CPU球団の指名は自動で進み、「早送り」「自球団の番まで飛ばす」もできる。自球団の番で止まる）→ 育成 → 結果まとめ。
## 操作：札をⒶ／クリックで選び、もう一度Ⓐ／クリック（右クリック）で選手詳細。十字キーで右の「入札する」や上の見出しへ。
## LB/RB（Q/E）でタブ、Ⓑは選択の取り消し→ハブ（ドラフトは途中から再開できる）。
## 作戦会議（作業37・38、DraftBoard）：一覧の左端に印（◎○△☆✕）、絞り込み「目星だけ」、列「予想」（有識者の予想順位）。
## 自球団が入札・指名する番には、印の上の順（本命の順番 → ○ → ☆ → △）の候補を最初から選んでおく（おすすめ）。
## 開幕の演出に有識者の12球団の1位予想
## スカウトの手帳（作業51）：最初は「手帳」（左に候補1人ずつのページ ScoutNotebook、右に12球団の指名ボード PickBoard）。
## ページを左右にめくり（LB/RB・◀▶）、「この男でいく」で入札・指名。縦長の画面では手帳とボードを切り替えて1つずつ出す。
## 「表に切り替え」で今までの候補一覧（能力の表）。入団前に見えるのは今の能力だけ（1年目・将来性は出さない）

signal message_changed(text: String)
## ドラフトのあとの「次へ」を押した（ハブが次の段階へ進める。作業65）
signal advance_requested

const TABS := [["info", "情報", Color("1e88e5")], ["pitch", "投手能力", Color("e53935")],
	["bat", "野手能力", Color("2e9b48")], ["picks", "指名一覧", Color("8a5cc8")]]
## 列 [キー, 見出し, 幅]。キーは並び替えのキー（Draft.sort_value）
const COLUMNS := {
	"info": [["pos", "位置", 52], ["career", "経歴", 70], ["school", "出身", 150], ["age", "年齢", 50], ["type", "型", 90]],
	"pitch": [["pos", "位置", 52], ["velocity", "球速", 80], ["overall", "総合", 62], ["stamina", "スタミナ", 78],
		["k9", "奪三振", 70], ["bb9", "制球", 62]],
	"bat": [["pos", "位置", 52], ["meet", "ミート", 62], ["power", "パワー", 62], ["eye", "選球眼", 62],
		["speed", "走力", 56], ["arm", "肩力", 56], ["defense", "守備", 56]],
}
## 予想＝有識者の予想順位（作業38）。1年目・将来性の列は作業51で消した（入団前に見えるのは今の能力だけ）
const TAIL_COLUMNS := [["hyouka", "評価", 56], ["yosou", "予想", 48]]
## 並び替えのキー（テスト用にまとめて）。名前・出身校以外は大きい順が先
const SORT_KEYS := ["pos", "career", "age", "school", "type", "name", "velocity", "overall", "stamina", "k9", "bb9",
	"meet", "power", "eye", "speed", "arm", "defense", "hyouka", "yosou"]
## 小さい順が自然なキー（最初に押したとき小さい順）
const ASCENDING_FIRST := ["pos", "career", "age", "school", "type", "name"]
const FILTERS := [["all", "全選手"], ["left", "未指名"], ["marked", "目星だけ"], ["投手", "投手"], ["捕手", "捕手"], ["内野手", "内野手"],
	["外野手", "外野手"]]
const POS_SHORT := {"投手": "投", "捕手": "捕", "内野手": "内", "外野手": "外"}
const NAME_WIDTH := 150
const MARK_WIDTH := 56
## 済マークの欄のうち、作戦会議の印の幅
const BOARD_MARK_WIDTH := 22
const ROW_HEIGHT := 36
const RIGHT_WIDTH := 330
## 抽選の演出の封筒を1行に並べる数（それより多い競合は2行にする）
const LOTTERY_COLUMNS := 6
## 演出（開幕・抽選・発表）の後ろの色。透かさない（作業81）
const OVERLAY_BACKDROP := Color("0d1a33")
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
const MLB_COLOR := Color("0d47a1")
const REINCARNATION_COLOR := Color("8e24aa")
## 画面の形（作業51）："book"＝手帳と指名ボード、"board"＝指名ボードだけ（縦長の画面）、"table"＝今までの能力の表
const MODES := [["book", "手帳"], ["board", "ボード"], ["table", "表"]]

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
## ドラフトのあとの「次へ」（説得が残っていれば「説得せずに次へ」。作業65）と、その確かめの1回目を押したか
var _next_button: Button
var _skip_armed := false
## ドラフトのあと、説得が残っているときに上に出す帯（「メジャー志望の◯◯の説得が残っています」と「説得のページへ」。作業65）
var _talk_banner: PanelContainer
var _talk_label: Label
var _talk_button: Button
var _overlay: Control
var _overlay_box: VBoxContainer
var _overlay_next: Button
var _overlay_queue: Array = []
var _ids: Array[String] = []
var _tags := {}
## メジャー志望の選手の説得で約束する年数（0＝約束なし。作業26）
var _promise := 0
var _promise_option: OptionButton
var _recent: Array[String] = []
var _voice: DraftVoice
var _announce_elapsed := 0.0
var _announce_total := 0.0
## Ⓑで発表を飛ばした：自球団の番が来るまで他球団の指名は発表しない
var _announce_skip := false
var _mode := "book"
var _mode_buttons := {}
## 表のときだけ出すタブの部品（LB/RB の札・タブのボタン）
var _table_only: Array[Control] = []
var _book_body: BoxContainer
var _notebook: ScoutNotebook
var _board: PickBoard
## 手帳の印・メモを変えた回数（refresh の作り直しの合図）
var _board_version := 0
var _bottom_buttons: HFlowContainer
var _bottom_box: BoxContainer
## 表のときに「おまかせ」「選択終了」を置く右の欄の行（手帳のときは下の帯へ移す）
var _right_line: HBoxContainer


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 6)
	add_child(_build_top())
	add_child(_build_talk_banner())
	add_child(_build_tabs())
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_body.add_child(_build_list())
	_body.add_child(_build_right())
	add_child(_build_book())
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
	UiLayout.layout_changed.connect(_on_layout_changed)
	_apply_layout(UiLayout.is_portrait)


func _on_layout_changed(is_portrait: bool, _is_mobile: bool) -> void:
	_apply_layout(is_portrait)


func _apply_layout(is_portrait: bool) -> void:
	if _right_panel != null and is_instance_valid(_right_panel):
		if is_portrait:
			_right_panel.custom_minimum_size = Vector2(0, 180)
		else:
			_right_panel.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	if _notebook != null:
		_notebook.set_spread(not is_portrait)
		_board.set_rows_min_height(0.0)
		_board.set_compact(not is_portrait)
		_bottom_box.vertical = is_portrait
		if not is_portrait and _mode == "board":
			_mode = "book"
		_shown_key = ""
		if is_inside_tree():
			refresh()


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_selected = ""
	_message = ""
	_shown_key = ""
	_fast = false
	_skip_armed = false
	var d := GameState.draft()
	_tab = "picks" if d != null and d.stage == Draft.Stage.DONE else "info"
	if d != null and d.stage == Draft.Stage.DONE and not d.pending_talks().is_empty():
		_selected = d.pending_talks()[0]
		_mode = "book"  # 説得の待ちは手帳の説得のページから（作業65）
	if d != null:
		GameState.draft_predictions()
		GameState.draft_board.apply_to(d)
		_preselect(d)
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
	if _mode != "table":
		if _mode == "board":  # 縦長の画面でボードを見ていたら手帳へ戻る
			set_mode("book")
			return true
		return false
	if _selected.is_empty():
		return false
	_selected = ""
	_message = ""
	refresh()
	focus_first()
	return true


## LB/RB：手帳ならページをめくる、表ならタブ
func switch_tab(delta: int) -> void:
	if _overlay.visible:
		return
	if _mode != "table":
		flip(delta)
		return
	var keys: Array = []
	for t: Array in TABS:
		keys.append(t[0])
	_show_tab(keys[posmod(keys.find(_tab) + delta, keys.size())])


func focus_first() -> void:
	if _overlay.visible:
		_overlay_next.grab_focus()
		return
	if _mode == "board":
		UiInput.grab(_board.open_button() if not _board.open_button().disabled else _mode_buttons["book"])
		return
	if _mode == "book":
		var go := _notebook.go_button()
		UiInput.grab(go if not go.disabled else _mode_buttons["book"])
		return
	if _tab != "picks" and not _ids.is_empty():
		var target: Control = _tags.get(_selected, _tags.get(_ids[0]))
		if target != null:
			target.grab_focus()
			return
	UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	var d := GameState.draft()
	var key := "%s|%s|%s|%s|%s|%d|%s|%s|%s|%s|%d|%s" % [_tab, _filter, _sort_key, str(_sort_desc), _selected,
		d.picks.size() if d != null else -1, str(d.stage) if d != null else "", d.wave if d != null else 0,
		_message, _mode, _board_version, str(d.bids.get(GameState.team, "")) if d != null else ""]
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
	var table := _mode == "table"
	var picks_mode := table and _tab == "picks"
	_body.visible = table and not picks_mode
	_picks_scroll.visible = picks_mode
	_book_body.visible = not table
	_place_pick_buttons()
	# スマホの手帳のときは説明の1行を出さない（同じ文言は下の操作の帯に出る。縦の場所を手帳に回す）。
	# パソコンはドラフトの間ハブの下の帯を隠す（作業81：後ろを見せない）ので、手帳のときも1行を出す
	_status_label.visible = table or not UiLayout.is_mobile
	if not table:
		_render_book(d)
	elif picks_mode:
		_render_picks(d)
	else:
		_render_header()
		_render_list(d)
		_render_summary(d)
	_render_bottom(d)
	_render_talk_banner(d)
	if not focused_id.is_empty() and _tags.has(focused_id):
		_tags[focused_id].grab_focus()
	if d != null and d.stage == Draft.Stage.DONE:
		_reveal_done.call_deferred()


func _build_talk_banner() -> Control:
	_talk_banner = PanelContainer.new()
	var style := UiTheme.card(Color("b3261e"), 8, 3, 1.0)
	style.bg_color = Color("fdecea")
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_talk_banner.add_theme_stylebox_override("panel", style)
	_talk_banner.visible = false
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 10)
	_talk_banner.add_child(line)
	_talk_label = UiTheme.small_label("", 17, Color("b3261e"), 800)
	_talk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talk_label.custom_minimum_size = Vector2(260, 0)
	line.add_child(_talk_label)
	_talk_button = Button.new()
	_talk_button.text = "説得のページへ ▶"
	_talk_button.custom_minimum_size = Vector2(180, 40)
	_talk_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(_talk_button, Color("b3261e"), Color.WHITE, 8, 4)
	_talk_button.pressed.connect(show_talk)
	line.add_child(_talk_button)
	return _talk_banner


## 残っている交渉の案内（メジャー志望の説得・意中の球団が別の選手との入団交渉。作業26・77）
static func talk_notice(d: Draft, talks: Array[String]) -> String:
	var mlb: Array[String] = []
	var intent: Array[String] = []
	for id in talks:
		(mlb if d.talk_kind(id) == "mlb" else intent).append(str(d.by_id[id]["name"]))
	var parts: Array[String] = []
	if not mlb.is_empty():
		parts.append("メジャー志望の%sの説得が残っています。説得しないまま次へ進むと、期限切れでメジャーへ挑戦します"
			% "・".join(mlb))
	if not intent.is_empty():
		parts.append("意中の球団が別の%sとの入団交渉が残っています。交渉しないまま次へ進むと、通常の交渉で決まります（入団拒否もあります）"
			% "・".join(intent))
	return "\n".join(parts)


## 説得が残っていれば上の帯に名前を出す（手帳・表・指名一覧のどれを見ていても目に入るように）
func _render_talk_banner(d: Draft) -> void:
	var talks: Array[String] = []
	if d != null and d.stage == Draft.Stage.DONE and not d.resolved:
		talks = d.pending_talks()
	_talk_banner.visible = not talks.is_empty()
	if talks.is_empty():
		return
	_talk_label.text = talk_notice(d, talks)
	# 手帳ですでに説得のページを開いていれば、ボタンは出さない（帯の文だけ）
	_talk_button.visible = not (_mode == "book" and talks.has(_selected))


## 説得の帯のボタン（テスト用）
func talk_banner_button() -> Button:
	return _talk_button


## ドラフトのあと：縦長の画面（ハブのサブ画面が縦に流れる）でも「次へ」と手帳の「説得する」が画面の中に来るよう流す（作業65）
func _reveal_done() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = null
	var n := get_parent()
	while n != null and scroll == null:
		scroll = n as ScrollContainer
		n = n.get_parent()
	if scroll == null or not is_visible_in_tree():
		return
	if _talk_banner.visible and _talk_button.visible:
		scroll.ensure_control_visible(_talk_banner)  # 説得のページを開いていなければ、上の帯（説得のページへ）を見せる
		return
	if _next_button.is_visible_in_tree():
		scroll.ensure_control_visible(_next_button)
	var go := _notebook.go_button()
	if _mode == "book" and go.is_visible_in_tree() and not go.disabled:
		scroll.ensure_control_visible(go)


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


## 候補を選ぶ（手帳ならそのページを開く。手帳では選んでいる候補をもう一度選んでも選手詳細は開かない）
func select_candidate(id: String) -> void:
	if _mode != "table" and _selected == id:
		return
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


## 抽選を3Dの演出で見せるか（早送り中は2Dの演出）。Web 版・スマホは重いので2Dの演出（当たりは同じ。作業63）
func use_3d_lottery() -> bool:
	return not _fast and not DraftVoice.web_like() and not UiLayout.is_mobile


## いま出ている抽選の3D演出（無ければ null。テスト用）
func lottery_3d() -> Node:
	var item: Dictionary = _overlay.get_meta("item", {}) if _overlay.visible else {}
	var node: Node = item.get("lottery3d")
	return node if node != null and is_instance_valid(node) else null


## 右の「入札する／指名する」（手帳の「この男でいく」）を押す（テスト用）
func press_action() -> void:
	_on_action_pressed()


## 画面の形（"book"・"board"・"table"）。縦長でない画面の "board" は "book" と同じ（手帳とボードを並べる）
func set_mode(mode: String) -> void:
	_mode = mode
	if _mode == "board" and not UiLayout.is_portrait:
		_mode = "book"
	_message = ""
	refresh()
	focus_first()


func mode() -> String:
	return _mode


## 説得の待ち（ドラフトのあと）：手帳のその選手のページを開く（ハブの可変ボタン「説得の交渉へ」。作業65）
func show_talk() -> void:
	var d := GameState.draft()
	if d == null or d.pending_talks().is_empty():
		return
	_selected = d.pending_talks()[0]
	set_mode("book")


## ドラフトのあとの「次へ」のボタン（テスト用）
func next_button() -> Button:
	return _next_button


func notebook() -> ScoutNotebook:
	return _notebook


func pick_board() -> PickBoard:
	return _board


## 手帳のページをめくる（めくる順は一覧と同じ絞り込み・並び替え）
func flip(delta: int) -> void:
	var d := GameState.draft()
	if d == null:
		return
	var ids := _book_ids(d)
	if ids.is_empty():
		return
	var i := ids.find(_selected)
	_selected = ids[posmod(i + delta, ids.size())] if i >= 0 else ids[0]
	_message = ""
	refresh()


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
			if not d.pending_talks().is_empty():
				_turn_label.text = "全球団の指名が終わりました。入団の交渉（説得）が残っています"
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
	for m: Array in MODES:
		var mb := Button.new()
		mb.text = m[1]
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(72, 42)
		mb.add_theme_font_size_override("font_size", 18)
		mb.add_theme_font_override("font", ScoutNotebook.hand_font(true))
		UiTheme.style_toggle(mb, ScoutNotebook.RED, 8)
		var mode_key: String = m[0]
		mb.pressed.connect(func() -> void: set_mode(mode_key))
		mb.tooltip_text = {"book": "スカウトの手帳（1人ずつめくる）と指名ボード", "board": "12球団の指名ボード",
			"table": "能力の表（候補を並べて比べる）"}[mode_key]
		row.add_child(mb)
		_mode_buttons[mode_key] = mb
	var lb := UiTheme.small_label("◀ LB", 17, UiTheme.TEXT, 800)
	row.add_child(lb)
	_table_only.append(lb)
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
		_table_only.append(b)
	var rb := UiTheme.small_label("RB ▶", 17, UiTheme.TEXT, 800)
	row.add_child(rb)
	_table_only.append(rb)
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
	for key: String in _mode_buttons:
		var mb: Button = _mode_buttons[key]
		mb.set_pressed_no_signal(key == _mode)
		mb.visible = key != "board" or UiLayout.is_portrait
	for c: Control in _table_only:
		c.visible = _mode == "table"
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
		if col[0] == "yosou":
			b.tooltip_text = "予想＝有識者3人の順位予想を合わせた順位（作戦会議で詳しく）\n" + b.tooltip_text
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
		if _filter == "marked" and GameState.draft_board.mark_of(d.year, DraftBoard.key_of(c)).is_empty():
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
	var display_name := NameTag.family_name(c["name"])
	var p := GameData.player(id)
	if p.is_empty():
		tag.setup_plain(display_name, NameTag.pos_color(c["pos"]))
	else:
		tag.setup_player(p, display_name)
	tag.selected = id == _selected
	tag.dimmed = not str(c["picked_by"]).is_empty()
	tag.tooltip_text = "%s（%s・%s）%s" % [c["name"], c["pos"], c["school"], _picked_text(c)]
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	for col: Array in _columns().slice(1):
		row.add_child(_cell(c, col[0], col[2]))
	return row


## 済マーク（指名済みの球団の色）・自球団の入札。作戦会議の印があれば左に添える
func _mark_label(d: Draft, c: Dictionary) -> Control:
	var label := _status_label_of(d, c)
	var mark := GameState.draft_board.mark_of(d.year, DraftBoard.key_of(c)) if d != null else ""
	if mark.is_empty():
		return label
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(MARK_WIDTH, ROW_HEIGHT - 4)
	box.add_child(DraftMeetingView.mark_label(mark, BOARD_MARK_WIDTH, ROW_HEIGHT - 4,
		GameState.draft_board.memo_of(d.year, DraftBoard.key_of(c))))
	label.custom_minimum_size = Vector2(MARK_WIDTH - BOARD_MARK_WIDTH, ROW_HEIGHT - 4)
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 13)
	box.add_child(label)
	return box


func _status_label_of(d: Draft, c: Dictionary) -> Label:
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
	elif not c.get("reincarnation", {}).is_empty():
		label.text = "転生"
		label.tooltip_text = "転生選手：%sの生まれ変わり（全盛期 %d年・%s）" % [c["reincarnation"]["name"],
			int(c["reincarnation"]["peak_year"]), GameData.short_name(str(c["reincarnation"]["peak_team"]))]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.add_theme_color_override("font_color", REINCARNATION_COLOR)
	elif c.get("mlb_intent", false):
		label.text = "米志望"
		label.tooltip_text = "メジャー志望を表明（指名したら説得の交渉。成功率は低め）"
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.add_theme_color_override("font_color", MLB_COLOR)
	elif not c.get("intent", {}).is_empty():
		label.text = "意中"
		label.tooltip_text = "%s（意中ではない球団が指名すると入団の交渉。拒否されることも）" % DraftIntent.short_text(c["intent"])
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.add_theme_color_override("font_color", MLB_COLOR)
	return label


func _cell(c: Dictionary, key: String, width: int) -> Control:
	if key == "yosou":
		return DraftMeetingView.yosou_label(c, width)
	if key == "hyouka":
		var label := UiTheme.rank_label({"rank": c["hyouka_rank"], "value": 0}, 22)
		label.tooltip_text = "当時の評価（史実の指名順位・競合数から）"
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
		"type":
			text = str(c.get("type", ""))
		"age":
			text = ("%d歳" % int(c["age"])) if int(c["age"]) > 0 else "-"
		"velocity":
			text = ("%dkm" % int(c["velocity"])) if int(c["velocity"]) > 0 else "-"
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not key in ["school", "type"] else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override("font", UiTheme.font(800 if key == "pos" else 700))
	l.add_theme_font_size_override("font_size", 17 if not key in ["school", "type"] else 15)
	l.add_theme_color_override("font_color", NameTag.pos_color(c["pos"]).darkened(0.45) if key == "pos" \
		else UiTheme.TEXT)
	if key == "type" and not text.is_empty():
		l.tooltip_text = text  # 型の名前（作業67）が欄に入りきらないとき
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	if key == "age" and not c.get("age_known", false) and int(c["age"]) > 0:
		l.tooltip_text = "生年月日のデータが無いので経歴からの目安"
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


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
	# 要約は長くなる（能力・紹介文など）ので、枠を押し広げないようスクロールの中に入れる（作業8のスクショで見つけた）
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
	_right_line = line
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
	lines.append("列の見出しを押すと並び替えます。")
	var counts := GameState.draft_board.counts(d.year)
	var marked: Array[String] = []
	for mark: String in DraftBoard.MARKS:
		if int(counts.get(mark, 0)) > 0:
			marked.append("%s%d人" % [mark, int(counts[mark])])
	if not marked.is_empty():
		lines.append("作戦会議の印：%s（絞り込み「目星だけ」）。印の上の順におすすめを選んでおきます（おまかせも印を優先）。" \
			% "　".join(marked))
	if d.year >= FictionalDraft.FIRST_YEAR and not d.candidates.is_empty() and d.candidates[0].get("fictional", false):
		lines.append("※%d年は史実のドラフトがありません。候補は架空の選手（出身校・所属は実在）で、" % d.year
			+ "当時の評価は実在の選手と同じ見え方です。「転生」は引退した名選手の生まれ変わり。")
	elif d.year > Draft.LAST_HISTORY_YEAR:
		lines.append("※%d年は史実のドラフトがありません。候補は実在のアマ選手（報道での評価が当時の評価）です。" % d.year)
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

	# 二刀流バナー
	var tw: Dictionary = c.get("two_way", {})
	if bool(tw.get("active", false)):
		var banner := PanelContainer.new()
		banner.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
		var b_style := UiTheme.card(Color("9c27b0"), 6, 2, 0.95)
		b_style.bg_color = Color("f3e5f5")
		banner.add_theme_stylebox_override("panel", b_style)
		var b_box := VBoxContainer.new()
		b_box.add_theme_constant_override("separation", 1)
		var tw_desc: String = str(tw.get("desc", "二刀流候補"))
		var b_title := UiTheme.small_label("★ 二刀流選手［%s］" % tw_desc, 14, Color("6a1b9a"), 800)
		b_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b_box.add_child(b_title)
		var b_detail := UiTheme.small_label("投打両面で高い才能を持つ二刀流選手です。", 13, UiTheme.TEXT, 700)
		b_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b_box.add_child(b_detail)
		banner.add_child(b_box)
		_summary_box.add_child(banner)
	if c.get("mlb_intent", false):
		_summary_box.add_child(_mlb_box(d, c))  # 説得の約束を選ぶ欄が隠れないよう上のほうに
	elif not c.get("intent", {}).is_empty() or not c.get("refused", {}).is_empty():
		_summary_box.add_child(_intent_box(d, c))  # 意中の球団（作業77）
	var ranks := HBoxContainer.new()
	ranks.add_theme_constant_override("separation", 6)
	ranks.add_child(UiTheme.small_label("当時の評価", 16, UiTheme.TEXT, 800))
	ranks.add_child(UiTheme.rank_label({"rank": c["hyouka_rank"], "value": 0}, 30))
	_summary_box.add_child(ranks)
	var board_text := _board_text(d, c)
	if not board_text.is_empty():
		var board_label := UiTheme.small_label(board_text, 14, Color("b3261e"), 800)
		board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		board_label.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
		_summary_box.add_child(board_label)
	_summary_box.add_child(_ability_grid(c))
	if bool(c.get("two_way", {}).get("active", false)):
		_summary_box.add_child(_two_way_grid(c))
	var intro := UiTheme.small_label("「%s」" % c["intro"], 15, Color("1e63c8"), 700)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	_summary_box.add_child(intro)
	var state := ""
	if not str(c["picked_by"]).is_empty():
		state = "済：%s %s" % [GameData.short_name(c["picked_by"]), c["pick_label"]]
	else:
		state = "未指名"
	if not c.get("reincarnation", {}).is_empty():
		var rei: Dictionary = c["reincarnation"]
		state += "　（転生選手：%sの生まれ変わり。全盛期 %d年・%s）" % [rei["name"], int(rei["peak_year"]),
			GameData.short_name(str(rei["peak_team"]))]
	elif c.get("amateur", false):
		state += "　（%s）" % ("架空の選手" if c.get("fictional", false) else "実在のアマ選手・報道の評価から推定")
	else:
		state += "　（史実：%s %s）" % [GameData.short_name(c["hist_team"]), c["hist_label"]]
	if c.get("synthetic", false):
		state += "\n※能力値データが無いため、近い候補の能力を仮に使っています"
	var state_label := UiTheme.small_label(state, 14, UiTheme.TEXT_SUB, 700)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	_summary_box.add_child(state_label)


## 要約の作戦会議の1行：印（本命なら何番手）・メモ・有識者の予想順位（どれも無ければ空）
func _board_text(d: Draft, c: Dictionary) -> String:
	var key := DraftBoard.key_of(c)
	var board := GameState.draft_board
	var parts: Array[String] = []
	var mark := board.mark_of(d.year, key)
	if not mark.is_empty():
		var text: String = "%s%s" % [mark, DraftBoard.MARK_NAMES[mark]]
		if mark == "◎":
			text += "（%d番手）" % (board.favorite_list(d.year).find(key) + 1)
		parts.append(text)
	var memo := board.memo_of(d.year, key)
	if not memo.is_empty():
		parts.append("メモ：" + memo)
	if int(c.get("yosou", 0)) > 0:
		parts.append("有識者の予想 %d位" % int(c["yosou"]))
	if d.user_recommend() == c["id"] and str(c["picked_by"]).is_empty():
		parts.push_front("おすすめ")
	return "作戦会議：" + "　".join(parts) if not parts.is_empty() else ""


## 作戦会議のおすすめ（印の上の順。Draft.user_recommend）を選んでおく：自球団が入札・指名できる番で、まだ何も選んで
## いない（または選んでいた候補が指名された）とき（作業37）
func _preselect(d: Draft) -> void:
	if d == null or (not _selected.is_empty() and str(d.by_id.get(_selected, {}).get("picked_by", "")).is_empty()):
		return
	if (d.stage == Draft.Stage.FIRST and d.first_pick_of(GameState.team).is_empty()) or d.is_user_turn():
		_selected = d.user_recommend()


## メジャー志望の欄：交渉期限・説得の条件（約束の年数）・結果
func _mlb_box(d: Draft, c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var id: String = c["id"]
	var text := "メジャー志望（交渉期限：%s）" % MlbPersuasion.deadline_text(d.year, c.get("mlb_overseas", false))
	var talk: Dictionary = d.talks.get(id, {})
	if not talk.is_empty():
		var cond := "・%d年後のポスティングを約束" % int(talk["promise"]) if int(talk["promise"]) > 0 else ""
		text += "
説得：%s（成功率 %d%%%s）" % ["成功・入団" if talk["ok"] else "失敗・メジャーへ",
			roundi(float(talk["chance"]) * 100.0), cond]
	var label := UiTheme.small_label(text, 14, MLB_COLOR, 800)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(RIGHT_WIDTH - 20, 0)
	label.tooltip_text = str(c.get("mlb_note", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(label)
	if d.can_persuade(id):
		var warn := UiTheme.small_label("説得しないまま次の段階へ進むと、期限切れでメジャーへ挑戦します", 13,
			Color("b3261e"), 800)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(RIGHT_WIDTH - 20, 0)
		box.add_child(warn)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(UiTheme.small_label("約束", 14, UiTheme.TEXT, 800))
		_promise_option = OptionButton.new()
		_promise_option.add_item("約束なし", 0)
		for y: int in MlbPersuasion.PROMISE_YEARS:
			_promise_option.add_item("%d年後にポスティングを認める" % y, y)
		if _promise_option.get_item_index(_promise) < 0:
			_promise = 0
		_promise_option.select(maxi(0, _promise_option.get_item_index(_promise)))
		_promise_option.add_theme_font_size_override("font_size", 14)
		_promise_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_promise_option.item_selected.connect(func(index: int) -> void:
			_promise = _promise_option.get_item_id(index)
			_render_actions(d, c))
		line.add_child(_promise_option)
		box.add_child(line)
	return box


## 意中の球団の欄（作業77）：意中の球団・指名を拒否した経緯・入団交渉の誠意・結果
func _intent_box(d: Draft, c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var id: String = c["id"]
	var it: Dictionary = c.get("intent", {})
	var lines: Array[String] = []
	if not it.is_empty():
		lines.append("意中の球団：%s" % DraftIntent.short_text(it))
	var ref: Dictionary = c.get("refused", {})
	if not ref.is_empty():
		lines.append("%d年に%sの%s指名を拒否" % [int(ref["year"]), GameData.short_name(str(ref["team"])), str(ref.get("label", ""))])
	var talk: Dictionary = d.talks.get(id, {})
	if not talk.is_empty():
		lines.append("入団交渉：%s（成功率 %d%%・%s）" % ["成功・入団" if talk["ok"] else "入団拒否",
			roundi(float(talk["chance"]) * 100.0), DraftIntent.offer_of(int(talk.get("offer", 0)))["label"]])
	elif not it.is_empty() and str(c["picked_by"]) == str(it["team"]):
		lines.append("意中の球団の指名。交渉なしで入団")
	var label := UiTheme.small_label("\n".join(lines), 14, MLB_COLOR, 800)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(RIGHT_WIDTH - 20, 0)
	label.tooltip_text = str(it.get("note", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(label)
	if d.can_persuade(id):
		var warn := UiTheme.small_label("交渉しないまま次の段階へ進むと、通常の交渉で決まります（入団拒否もあります）", 13,
			Color("b3261e"), 800)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(RIGHT_WIDTH - 20, 0)
		box.add_child(warn)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(UiTheme.small_label("誠意", 14, UiTheme.TEXT, 800))
		_promise_option = OptionButton.new()
		for o: Dictionary in d.talk_options(id):
			_promise_option.add_item("%s（成功率 %d%%）" % [o["label"], roundi(float(o["chance"]) * 100.0)], int(o["value"]))
		if _promise_option.get_item_index(_promise) < 0:
			_promise = 0
		_promise_option.select(maxi(0, _promise_option.get_item_index(_promise)))
		_promise_option.add_theme_font_size_override("font_size", 14)
		_promise_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_promise_option.item_selected.connect(func(index: int) -> void:
			_promise = _promise_option.get_item_id(index)
			_render_actions(d, c))
		line.add_child(_promise_option)
		box.add_child(line)
	return box


## 選んでいる条件（約束・誠意）での説得の成功率
static func talk_chance(d: Draft, id: String, value: int) -> float:
	var opts := d.talk_options(id)
	for o: Dictionary in opts:
		if int(o["value"]) == value:
			return float(o["chance"])
	return float(opts[0]["chance"]) if not opts.is_empty() else 0.0


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


## 二刀流の副次能力グリッド（投手の打撃、または野手の投球）
func _two_way_grid(c: Dictionary) -> Control:
	var tw: Dictionary = c.get("two_way", {})
	if not bool(tw.get("active", false)):
		return Control.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var is_p := bool(c.get("pitcher", false))
	var title_text := "★【二刀流】打撃能力" if is_p else "★【二刀流】投球能力"
	var title := UiTheme.small_label(title_text, 14, Color("6a1b9a"), 800)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)

	if is_p:
		var b_rat: Dictionary = c.get("two_way_bat", {})
		var keys: Array = [["meet", "ミート"], ["power", "パワー"], ["eye", "選球眼"],
			["speed", "走力"], ["arm", "肩力"], ["defense", "守備"]]
		for k: Array in keys:
			grid.add_child(UiTheme.small_label(k[1], 14, UiTheme.TEXT, 800))
			var value := int(b_rat.get(k[0], -1))
			if value < 0:
				grid.add_child(UiTheme.small_label("-", 15, UiTheme.TEXT_SUB, 700))
			else:
				grid.add_child(UiTheme.rank_label({"rank": ability_rank(value), "value": value}, 18))
	else:
		var p_rat: Dictionary = c.get("two_way_pit", {})
		var keys: Array = [["velocity", "球速"], ["overall", "総合"], ["stamina", "スタミナ"],
			["bb9", "制球"], ["k9", "奪三振"]]
		for k: Array in keys:
			grid.add_child(UiTheme.small_label(k[1], 14, UiTheme.TEXT, 800))
			if k[0] == "velocity":
				var v := int(p_rat.get("velocity", 0))
				grid.add_child(UiTheme.small_label("%dkm/h" % v if v > 0 else "-", 15, UiTheme.TEXT, 800))
				continue
			var value := int(p_rat.get(k[0], -1))
			if value < 0:
				grid.add_child(UiTheme.small_label("-", 15, UiTheme.TEXT_SUB, 700))
			else:
				grid.add_child(UiTheme.rank_label({"rank": ability_rank(value), "value": value}, 18))

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
				if not c.is_empty() and d.can_persuade(c["id"]):
					var chance := talk_chance(d, c["id"], _promise)
					text = "説得する　%s" % MlbPersuasion.star_text(chance)
					can_pick = true
	_action_button.text = text
	_action_button.disabled = not can_pick
	if _notebook != null:
		var go := text
		if d != null and d.stage != Draft.Stage.DONE:
			go = "この男でいく（%s）" % _pick_word(d)
			if not c.is_empty() and not str(c["picked_by"]).is_empty():
				go = "指名済み"
			elif not user_turn:
				go = "この男でいく"
		_notebook.set_action(go, can_pick)
	_auto_pick_button.disabled = not user_turn
	_auto_pick_button.text = "おまかせで入札" if d != null and d.stage == Draft.Stage.FIRST else "おまかせ"
	_finish_button.disabled = not (user_turn and d.stage != Draft.Stage.FIRST)


# --- スカウトの手帳・指名ボード（作業51） ----------------------------------------------------

func _build_book() -> Control:
	_book_body = BoxContainer.new()
	_book_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_book_body.add_theme_constant_override("separation", 10)
	_book_body.visible = false
	_notebook = ScoutNotebook.new()
	_notebook.size_flags_stretch_ratio = 1.55
	_notebook.flip_requested.connect(flip)
	_notebook.go_pressed.connect(_on_action_pressed)
	_notebook.mark_requested.connect(_on_book_mark)
	_notebook.memo_changed.connect(_on_book_memo)
	_notebook.detail_requested.connect(func() -> void:
		if not _selected.is_empty():
			PlayerDetail.open(_notebook, _selected, _ids))
	_notebook.table_requested.connect(func() -> void: set_mode("table"))
	_book_body.add_child(_notebook)
	_board = PickBoard.new()
	_board.candidate_pressed.connect(_on_board_candidate)
	_board.notebook_requested.connect(_on_board_open)
	_book_body.add_child(_board)
	return _book_body


## 手帳でめくる候補（一覧と同じ絞り込み・並び替え）
func _book_ids(d: Draft) -> Array[String]:
	var ids: Array[String] = []
	for c in sorted_candidates(d):
		ids.append(c["id"])
	return ids


func _render_book(d: Draft) -> void:
	var portrait := UiLayout.is_portrait
	_notebook.visible = not (portrait and _mode == "board")
	_board.visible = not portrait or _mode == "board"
	_board.show_board(d, GameState.team, _pick_word(d) if d != null else "1位")
	_tags.clear()
	_ids = _book_ids(d)
	_notebook.clear_extra()
	var talks: Array[String] = []
	if d != null:
		talks = d.pending_talks()
	if not talks.is_empty():
		# 自球団が指名したメジャー志望の選手の説得（作業57）：絞り込みで隠れていても、そのページを開いておく
		if not talks.has(_selected):
			_selected = talks[0]
		if not _ids.has(_selected):
			_ids.push_front(_selected)
	elif d != null and d.talks.has(_selected) and not _ids.has(_selected):
		_ids.push_front(_selected)  # 説得したあとも、その結果のページを出したままにする
	if d == null or _ids.is_empty():
		_notebook.show_empty("ドラフトはオフの「ドラフト」の段階で行います。" if d == null \
			else "この絞り込みの候補はいません。上の「絞り込み」を変えてください。")
		_render_actions(d, {})
		return
	if not _ids.has(_selected):
		var rec := d.user_recommend()
		_selected = rec if _ids.has(rec) else _ids[0]
	var c: Dictionary = d.by_id[_selected]
	_notebook.show_page(d, c, _ids.find(_selected), _ids.size())
	if c.get("mlb_intent", false):
		_notebook.extra_box().add_child(_mlb_box(d, c))
	_render_actions(d, c)


## 手帳の◎○△☆✕（同じ印をもう一度押すと外す）。作戦会議と同じ DraftBoard に残り、おすすめ・おまかせにすぐ効く
func _on_book_mark(mark: String) -> void:
	var d := GameState.draft()
	if d == null or not d.by_id.has(_selected):
		return
	var c: Dictionary = d.by_id[_selected]
	var key := DraftBoard.key_of(c)
	var board := GameState.draft_board
	var next := "" if board.mark_of(d.year, key) == mark else mark
	board.set_mark(d.year, key, next)
	GameState.draft_board_changed()
	_board_version += 1
	_message = "%sの印を外しました。" % c["name"] if next.is_empty() \
		else "%sに%s（%s）を付けました。" % [c["name"], next, DraftBoard.MARK_NAMES[next]]
	refresh()


func _on_book_memo(text: String) -> void:
	var d := GameState.draft()
	if d == null or not d.by_id.has(_selected):
		return
	GameState.draft_board.set_memo(d.year, DraftBoard.key_of(d.by_id[_selected]), text)


## ボードの札・◎の候補を押した：その候補のページを開く（縦長なら手帳へ切り替える）
func _on_board_candidate(id: String) -> void:
	var d := GameState.draft()
	if d == null or not d.by_id.has(id):
		return
	if not _book_ids(d).has(id):
		_filter = "all"
	_selected = id
	_message = ""
	if _mode == "board":
		_mode = "book"
	refresh()
	focus_first()


## 「手帳を開いて N位を選ぶ」：おすすめ（印の上の順）のページを開く
func _on_board_open() -> void:
	var d := GameState.draft()
	if d == null:
		return
	var rec := d.user_recommend()
	if not rec.is_empty():
		_selected = rec
	_mode = "book"
	refresh()
	focus_first()


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
		tag.tooltip_text = "%s（%s・%s）当時の評価%s" % [c["name"], c["pos"], c["school"], c["hyouka_rank"]]
		tag.pressed.connect(func() -> void: PlayerDetail.open(tag, pid, _ids))
		row.add_child(tag)
		_tags[pid] = tag
		_ids.append(pid)
		row.add_child(UiTheme.rank_label({"rank": c["hyouka_rank"], "value": 0}, 15))
		box.add_child(row)
	if picks.is_empty():
		box.add_child(UiTheme.small_label("（まだ指名なし）", 13, UiTheme.TEXT_SUB, 700))
	return panel


# --- 下の帯 --------------------------------------------------------------------------------

## 下の帯：説明の1行と、早送り・自球団の番まで飛ばす・残りをおまかせ（手帳のときは「おまかせ」「選択終了」も）。
## 縦長の画面では説明の下にボタンを折り返して並べる
func _build_bottom() -> Control:
	_bottom_box = BoxContainer.new()
	_bottom_box.add_theme_constant_override("separation", 8)
	_status_label = UiTheme.small_label("", 16, UiTheme.TEXT, 700)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_box.add_child(_status_label)
	_bottom_buttons = HFlowContainer.new()
	_bottom_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_buttons.size_flags_stretch_ratio = 2.0
	_bottom_buttons.alignment = FlowContainer.ALIGNMENT_END
	_bottom_buttons.add_theme_constant_override("h_separation", 8)
	_bottom_buttons.add_theme_constant_override("v_separation", 6)
	_bottom_box.add_child(_bottom_buttons)
	_fast_button = Button.new()
	_fast_button.text = "早送り"
	_fast_button.toggle_mode = true
	_fast_button.custom_minimum_size = Vector2(96, 42)
	UiTheme.style_button(_fast_button, Color("2f7fd8"), Color.WHITE, 8, 4)
	_fast_button.toggled.connect(func(on: bool) -> void: _fast = on)
	_bottom_buttons.add_child(_fast_button)
	_skip_button = Button.new()
	_skip_button.text = "自球団の番まで飛ばす"
	_skip_button.custom_minimum_size = Vector2(190, 42)
	UiTheme.style_button(_skip_button, Color("2e9b48"), Color.WHITE, 8, 4)
	_skip_button.pressed.connect(_on_skip_pressed)
	_bottom_buttons.add_child(_skip_button)
	_complete_button = Button.new()
	_complete_button.text = "残りをおまかせで終える"
	_complete_button.custom_minimum_size = Vector2(210, 42)
	UiTheme.style_button(_complete_button, Color("8a5cc8"), Color.WHITE, 8, 4)
	_complete_button.pressed.connect(_on_complete_pressed)
	_bottom_buttons.add_child(_complete_button)
	_next_button = Button.new()
	_next_button.custom_minimum_size = Vector2(220, 46)
	_next_button.add_theme_font_size_override("font_size", 17)
	UiTheme.style_button(_next_button, Color("e53935"), Color.WHITE, 8, 4)
	_next_button.pressed.connect(_on_next_pressed)
	_next_button.visible = false
	_bottom_buttons.add_child(_next_button)
	return _bottom_box


## 「おまかせ」「選択終了」を、表なら右の欄、手帳なら下の帯へ
func _place_pick_buttons() -> void:
	var target: Container = _right_line if _mode == "table" else _bottom_buttons
	for b: Button in [_auto_pick_button, _finish_button]:
		if b.get_parent() != target:
			b.get_parent().remove_child(b)
			target.add_child(b)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _mode == "table" else Control.SIZE_FILL
		b.custom_minimum_size = Vector2(0, 40) if _mode == "table" else Vector2(110, 42)


func _render_bottom(d: Draft) -> void:
	var waiting := d != null and (d.stage == Draft.Stage.WAIVER or d.stage == Draft.Stage.IKUSEI) \
		and not d.is_user_turn()
	_fast_button.disabled = not waiting
	_skip_button.disabled = not waiting
	_complete_button.disabled = d == null or d.resolved or d.stage == Draft.Stage.DONE
	# ドラフトのあとは押せないボタンを隠して、「次へ」（説得が残っていれば「説得せずに次へ」）を出す（作業65）
	var done := d != null and d.stage == Draft.Stage.DONE
	for b: Button in [_fast_button, _skip_button, _complete_button, _auto_pick_button, _finish_button]:
		b.visible = not done
	_next_button.visible = done
	if done:
		if d.resolved:
			_next_button.text = "次へ：%s ▶" % GameState.button_text()
		elif _skip_armed:
			_next_button.text = "もう一度押すと説得せずに次へ"
		else:
			var mlb_left := false
			for id in d.pending_talks():
				mlb_left = mlb_left or d.talk_kind(id) == "mlb"
			# メジャー志望は期限切れで渡米、意中の球団が別の選手は通常の交渉で決まる（作業77）
			_next_button.text = "説得せずに次へ（渡米）" if mlb_left else "説得せずに次へ（通常の交渉）"
	if not _message.is_empty():
		_status_label.text = _message
	elif d == null:
		_status_label.text = ""
	elif d.stage == Draft.Stage.DONE and not d.pending_talks().is_empty():
		_status_label.text = talk_notice(d, d.pending_talks()) + "。条件を選んで「説得する」"
	elif d.resolved:
		var mine := d.picks_of(GameState.team)
		var names: Array[String] = []
		for rec in mine:
			names.append("%s %s" % [rec["label"], rec["name"]])
		_status_label.text = "%sの指名：%s。「次へ」（可変ボタン「%s」）で次の段階へ進みます。" % [
			GameData.short_name(GameState.team), "、".join(names) if not names.is_empty() else "なし",
			GameState.button_text()]
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
	if d.stage == Draft.Stage.DONE:
		if d.can_persuade(_selected):
			var result := d.persuade(_selected, _promise)
			_message = "%s（成功率 %d%%）" % [result["text"], roundi(float(result["chance"]) * 100.0)]
			GameState.draft_sync()
			refresh()
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
	_preselect(d)
	_after_change(d)


## ドラフトのあとの「次へ」：次の段階（FA）へ。説得が残っていれば、もう一度押したら期限切れ（渡米）にして次へ（作業65）
func _on_next_pressed() -> void:
	var d := GameState.draft()
	if d == null or d.stage != Draft.Stage.DONE:
		return
	if not d.resolved:
		if not _skip_armed:
			_skip_armed = true
			var names: Array[String] = []
			for id in d.pending_talks():
				names.append(d.by_id[id]["name"])
			_message = "説得しないまま次へ進むと、%sは期限切れでメジャーへ挑戦します（入団しません）。もう一度押すと次へ進みます。" \
				% "・".join(names)
			refresh()
			return
		GameState.draft_resolve()
	_skip_armed = false
	advance_requested.emit()


func _on_complete_pressed() -> void:
	var d := GameState.draft()
	if d == null or d.resolved:
		return
	var before := d.picks.size()
	d.auto_complete()
	var done := "残り%d人をおまかせで指名しました。" % (d.picks.size() - before)
	_selected = ""
	# 終われば入団。自球団が指名したメジャー志望の選手の説得が残っていれば、その選手のページで説得へ（作業57）
	_after_change(d)
	_message = done + _message
	refresh()


func _cpu_step(d: Draft) -> void:
	var rec := d.cpu_step()
	if not rec.is_empty():
		_note_pick(d, rec)
		_announce_pick(rec)
	_after_change(d)
	if d.is_user_turn():
		_announce_skip = false
		_preselect(d)
		refresh()
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
		var talks := d.pending_talks()
		if not talks.is_empty():
			# メジャー志望・意中の球団が別の選手を指名していれば、手帳のその選手のページで説得へ（表・ボードを見ていても。作業65・77）
			_selected = talks[0]
			_mode = "book"
			_message += "%sを説得してください（%sを選んで「説得する」）。" % [d.by_id[talks[0]]["name"],
				"約束" if d.talk_kind(talks[0]) == "mlb" else "誠意"]
		_tab = "picks"  # _show_tab は案内の文を消すので使わない
		refresh()
		focus_first()
		return
	if not _selected.is_empty() and not str(d.by_id.get(_selected, {}).get("picked_by", "")).is_empty() \
			and (d.is_user_turn() or d.stage == Draft.Stage.FIRST):
		_selected = ""
	_preselect(d)
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
	# 後ろ（候補の表の「済」＋入団先・手帳・ボード）が透けると、発表の前にネタバレになる（作業81）。透かさずに塗りつぶす
	var dim := ColorRect.new()
	dim.color = OVERLAY_BACKDROP
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
		_clear_overlay()  # 抽選の3Dの場面・発表の札などを、閉じたらすぐ解放する（作業63）
		_overlay.remove_meta("item")
		if _continue_first():
			return
		_preselect(GameState.draft())
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
	_overlay_box.add_child(_experts_grid(d))
	var hint := UiTheme.small_label("まずは全球団が同時に1位を入札します。重複したら抽選で交渉権を決めます。", 17,
		UiTheme.TEXT, 700)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(hint)
	_overlay_next.text = "開始"
	title.pivot_offset = Vector2(420, 30)
	title.scale = Vector2(0.6, 0.6)
	var tw := title.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "scale", Vector2.ONE, 0.35)


## 開幕の演出の、有識者の12球団の1位予想（作業38）：球団ごとに、評論家3人の予想（同じ選手なら「2人」など）
func _experts_grid(d: Draft) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var pred := GameState.draft_board.prediction(d.year)
	if pred.get("experts", []).is_empty():
		return box
	var title := UiTheme.small_label("有識者3人の1位予想（%s）" % "・".join(PackedStringArray(
		DraftExperts.EXPERTS.map(func(e: Dictionary) -> String: return e["name"]))), 16, Color("8a5cc8"), 800)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(grid)
	var names: Dictionary = pred.get("names", {})
	for t in d.order:
		var votes := {}
		for key: String in DraftExperts.firsts_of(pred, t):
			if not key.is_empty():
				votes[key] = int(votes.get(key, 0)) + 1
		var parts: Array[String] = []
		for key: String in votes:
			parts.append(str(names.get(key, key)) + ("（%d人）" % int(votes[key]) if int(votes[key]) >= 2 else ""))
		var line := UiTheme.small_label("%s：%s" % [GameData.short_name(t), "／".join(parts)], 14,
			MINE_COLOR if t == GameState.team else UiTheme.TEXT, 700)
		line.custom_minimum_size = Vector2(270, 0)
		line.clip_text = true
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		grid.add_child(line)
	return box


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
	# Web 版は読み上げの終わりを待たない（声が出なくても・止まっても発表は進む。作業63）
	var voice_done := not _voice.is_busy() or _announce_elapsed >= _announce_total + ANNOUNCE_VOICE_WAIT \
		or DraftVoice.web_like()
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
	# 封筒は1行に LOTTERY_COLUMNS 個まで（9球団以上の競合で画面からはみ出していた。layout_fit_check）
	var center := CenterContainer.new()
	_overlay_box.add_child(center)
	var row := GridContainer.new()
	row.columns = mini(lot["teams"].size(), LOTTERY_COLUMNS)
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 10)
	center.add_child(row)
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
