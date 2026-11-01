# gdlint: disable=max-file-lines
class_name DraftMeetingView
extends VBoxContainer
## ドラフト前の作戦会議（docs/AUTORUN.md 作業37）と有識者の指名予想（作業38）の画面。
## 新戦力の「ドラフト候補」タブ（シーズン中・オフ）と、戦力外・引退を締めたあとの可変ボタン「作戦会議」から開く（広げて表示）。
##
## - 左：自球団の補強ポイント（記録室のデプスの守備位置ランクを12球団と比べ、手薄・将来が弱い・正選手が高齢の位置に、
##   今季の位置別の戦力（作業34、TeamValue の得失点）を足した上位3つ。押すとその守備位置で絞り込み）と、印を付けた人数
## - 中央：候補の一覧（ドラフト画面と同じ列・並び替え・絞り込み。タブ：情報／投手能力／野手能力）か、有識者の予想（タブ）
## - 右：選んだ候補の要約・印（◎本命・○上位候補・△中位・☆掘り出し物・✕回避）・メモ、1位入札の本命の順番（◎を▲▼で並べ替え。
##   外れ1位の順にもなる）
## 候補：ドラフトの段階は Draft（GameState.draft()）。それより前は来季の能力値ファイル（架空の候補の年は作った候補）から
## ドラフトと同じ作り方の仮の Draft（将来性のノイズはドラフト当日と少し違う）。印は名前のキーで DraftBoard に残る
## 操作：札をⒶ／クリックで選び、十字キーで右の印のボタンへ。LB/RB（Q/E）でタブ、Ⓑでハブへ戻る

signal message_changed(text: String)
## 「ドラフト会議へ」を押した（ハブが可変ボタンと同じ処理で進める）
signal draft_requested

const TABS := [["info", "情報", Color("1e88e5")], ["pitch", "投手能力", Color("e53935")],
	["bat", "野手能力", Color("2e9b48")], ["experts", "有識者の予想", Color("8a5cc8")]]
const TAIL_COLUMNS := [["first", "1年目", 38], ["hyouka", "評価", 38], ["future", "将来性", 42], ["yosou", "予想", 36]]
const FILTERS := [["all", "全選手"], ["marked", "目星だけ"], ["left", "未指名"], ["投手", "投手"], ["捕手", "捕手"],
	["内野手", "内野手"], ["外野手", "外野手"]]
## 一覧の幅（ドラフト画面より細め：左右に補強ポイントと印の欄があるため）
const NAME_WIDTH := 102
const MARK_WIDTH := 32
const ROW_HEIGHT := 34
const LEFT_WIDTH := 195
const RIGHT_WIDTH := 280
const COLUMN_WIDTH := {"school": 128, "career": 54, "age": 44, "pos": 38}
## 能力の列の幅の上限
const ABILITY_WIDTH := 38
## 有識者の予想の表の名前の幅
const EXPERT_NAME_WIDTH := 150
const MINE_INK := Color("ff6d00")
## 補強ポイント：守備位置 → 候補の守備位置の4区分
const NEED_GROUP := {"捕手": "捕手", "一塁手": "内野手", "二塁手": "内野手", "三塁手": "内野手", "遊撃手": "内野手",
	"外野手": "外野手", "先発": "投手", "中継ぎ": "投手", "抑え": "投手"}
## 補強ポイントの点：今・将来の12球団平均との差の重み、正選手の平均年齢がこれを超えた1歳ごと、B以上がいない
const NEED_NOW_WEIGHT := 0.5
const NEED_FUTURE_WEIGHT := 0.8
const NEED_AGE_FROM := 30.0
const NEED_AGE_WEIGHT := 0.07
const NEED_THIN := 0.15
const NEED_COUNT := 3
## 位置別の戦力（得失点）：1点のマイナスあたりの点と、満額で効かせる今季の試合数（それより少なければ割合で弱める）
const NEED_RUNS_WEIGHT := 0.015
const NEED_RUNS_FULL_GAMES := 72.0
## デプスの守備位置 → 位置別の戦力の列（外野手は3つの和、抑えは救援の半分）
const NEED_RUNS_COLUMNS := {"捕手": ["捕手"], "一塁手": ["一塁手"], "二塁手": ["二塁手"], "三塁手": ["三塁手"],
	"遊撃手": ["遊撃手"], "外野手": ["左翼手", "中堅手", "右翼手"], "先発": ["先発"], "中継ぎ": ["救援"], "抑え": ["救援"]}
const NEED_RUNS_SHARE := {"抑え": 0.5}
## シーズン中は春のアマ球界のニュース（センバツ号）の日から候補が出そろう
const OPEN_DATE := "03-31"

var _palette: UiTheme.Palette
var _tab := "info"
var _filter := "all"
var _sort_key := "hyouka"
var _sort_desc := true
var _selected := ""
var _message := ""
var _shown_key := ""
var _preview: Draft = null
var _preview_key := ""
var _needs: Array = []
var _needs_key := ""

var _title_label: Label
var _tab_buttons := {}
var _filter_label: Label
var _draft_button: Button
var _needs_box: VBoxContainer
var _count_label: Label
var _center: PanelContainer
var _header_box: HBoxContainer
var _list_box: VBoxContainer
var _list_scroll: ScrollContainer
var _experts_scroll: ScrollContainer
var _experts_box: VBoxContainer
var _summary_box: VBoxContainer
var _mark_buttons := {}
var _memo_edit: LineEdit
var _fav_box: VBoxContainer
var _status_label: Label
var _ids: Array[String] = []
var _tags := {}


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 6)
	add_child(_build_top())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_center())
	body.add_child(_build_right())
	_status_label = UiTheme.small_label("", 15, UiTheme.TEXT, 700)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_message = ""
	_shown_key = ""
	var d := source()
	if d != null:
		GameState.draft_predictions()
		GameState.draft_board.apply_to(d)
	if _selected.is_empty() or d == null or not d.by_id.has(_selected):
		_selected = _first_favorite(d)
	refresh()
	focus_first()


func refresh() -> void:
	var d := source()
	var board := GameState.draft_board
	var key := "%s|%s|%s|%s|%s|%s|%d|%d|%s" % [_tab, _filter, _sort_key, str(_sort_desc), _selected, _message,
		GameState.year, GameState.phase, JSON.stringify(board.marks.get(str(GameState.year), {})) \
		+ JSON.stringify(board.favorite_list(GameState.year)) + str(d.picks.size() if d != null else -1)]
	if key == _shown_key:
		return
	_shown_key = key
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_id := ""
	for id: String in _tags:
		if _tags[id] == owner:
			focused_id = id
	_render_top(d)
	_render_needs()
	var experts := _tab == "experts"
	_list_scroll.get_parent().visible = not experts
	_experts_scroll.visible = experts
	if experts:
		_render_experts(d)
	else:
		_render_header()
		_render_list(d)
	_render_summary(d)
	_render_favorites(d)
	_render_status(d)
	if not focused_id.is_empty() and _tags.has(focused_id):
		_tags[focused_id].grab_focus()


func focus_first() -> void:
	if _tab != "experts" and not _ids.is_empty():
		var target: Control = _tags.get(_selected, _tags.get(_ids[0]))
		if target != null:
			target.grab_focus()
			return
	UiInput.grab(_tab_buttons[_tab])


func switch_tab(delta: int) -> void:
	var keys: Array = []
	for t: Array in TABS:
		keys.append(t[0])
	_show_tab(keys[posmod(keys.find(_tab) + delta, keys.size())])


## 候補の一覧の元（ドラフトの段階は Draft、それより前は仮の Draft。候補が出そろう前・候補の無い年は null）
func source() -> Draft:
	var d := GameState.draft()
	if d != null:
		return d
	if GameState.league == null or not available():
		return null
	var key := "%d|%s" % [GameState.year, GameState.team]
	if _preview == null or _preview_key != key:
		_preview_key = key
		_preview = _build_preview(GameState.year)
	return _preview


## 今年の候補を見られるか（シーズン中は春のアマ球界のニュースの日から）
func available() -> bool:
	if GameState.phase == GameState.Phase.CAMP:
		return false
	if GameState.phase == GameState.Phase.SEASON and GameState.season != null \
			and Season.date_of_day(GameState.day) < "%d-%s" % [GameState.year, OPEN_DATE]:
		return false
	return not Draft.draft_rows(GameState.year).is_empty() or not GameState.draft_class(GameState.year).is_empty()


# --- テスト用 ------------------------------------------------------------------------------

func list_ids() -> Array[String]:
	return _ids


func selected_id() -> String:
	return _selected


func select_candidate(id: String) -> void:
	_on_tag_pressed(id)


## 選んでいる候補に印を付ける（空で外す）
func set_mark(mark: String) -> void:
	_on_mark_pressed(mark)


func set_memo(text: String) -> void:
	_memo_edit.text = text
	_on_memo_changed(text)


func set_filter(key: String) -> void:
	_filter = key
	refresh()


func needs() -> Array:
	return _needs


func move_favorite(key: String, delta: int) -> void:
	_on_move_favorite(key, delta)


# --- 候補の元 ----------------------------------------------------------------------------

## ドラフトの段階より前の候補：来季の開幕時点の能力値（シーズン中は能力値ファイル、オフは来季の準備の分）と
## 架空の候補から、ドラフトと同じ Draft.setup で作る（今どこかに所属している選手は除く）
func _build_preview(year: int) -> Draft:
	var entries := {}
	var next := GameData.peek_ratings(year + 1, "pre")
	for p: Dictionary in next.get("players", []):
		entries[p["id"]] = p
	for p: Dictionary in GameState.draft_class(year):
		if not entries.has(p["id"]):
			entries[p["id"]] = p
	var teams := GameData.teams()
	var d := Draft.new()
	d.setup(year, GameState.team, teams, entries, GameState.league.team_of, teams, hash("meeting:%d" % year))
	return d


func _first_favorite(d: Draft) -> String:
	if d == null:
		return ""
	var by_key := _by_key(d)
	for key: Variant in GameState.draft_board.favorite_list(d.year):
		if by_key.has(str(key)):
			return by_key[str(key)]
	return ""


func _by_key(d: Draft) -> Dictionary:
	var result := {}
	if d != null:
		for c in d.candidates:
			result[DraftBoard.key_of(c)] = c["id"]
	return result


# --- 上 ------------------------------------------------------------------------------------

func _build_top() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	box.add_child(line)
	_title_label = Label.new()
	UiTheme.heading(_title_label, 24, Color("b3261e"), Color.WHITE, 6)
	UiTheme.fit_label(_title_label)
	line.add_child(_title_label)
	_draft_button = Button.new()
	_draft_button.text = "ドラフト会議へ ▶"
	_draft_button.custom_minimum_size = Vector2(220, 42)
	_draft_button.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(_draft_button, Color("e53935"))
	_draft_button.pressed.connect(func() -> void: draft_requested.emit())
	line.add_child(_draft_button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	row.add_child(UiTheme.small_label("◀ LB", 16, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(128 if t[0] == "experts" else 104, 38)
		b.add_theme_font_size_override("font_size", 18)
		UiTheme.style_button(b, t[2], Color.WHITE, 10, 6)
		var key: String = t[0]
		b.pressed.connect(func() -> void: _show_tab(key))
		row.add_child(b)
		_tab_buttons[key] = b
	row.add_child(UiTheme.small_label("RB ▶", 16, UiTheme.TEXT, 800))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiTheme.small_label("絞り込み", 16, UiTheme.TEXT, 800))
	for delta: int in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if delta < 0 else "▶"
		b.custom_minimum_size = Vector2(42, 38)
		UiTheme.style_button(b, Color("2f7fd8"), Color.WHITE, 8, 4)
		b.pressed.connect(_turn_filter.bind(delta))
		if delta < 0:
			row.add_child(b)
			var panel := PanelContainer.new()
			panel.add_theme_stylebox_override("panel", UiTheme.card(Color("2f7fd8"), 8, 3, 1.0))
			panel.custom_minimum_size = Vector2(110, 38)
			_filter_label = Label.new()
			_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UiTheme.heading(_filter_label, 18, UiTheme.TEXT, Color.WHITE, 4, false)
			panel.add_child(_filter_label)
			row.add_child(panel)
		else:
			row.add_child(b)
	return box


func _render_top(d: Draft) -> void:
	var y := GameState.year
	_title_label.text = "%d年秋のドラフト候補" % y
	if d != null:
		_title_label.text += "　%d人" % d.candidates.size()
		if GameState.draft() == null:
			_title_label.text += "（ドラフト会議の前）"
	_draft_button.visible = GameState.draft_open() or (GameState.phase == GameState.Phase.RELEASE \
		and not GameState.release_open() and GameState.next_phase() == GameState.Phase.DRAFT)
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


# --- 左：補強ポイント ------------------------------------------------------------------------

func _build_left() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(Color("f0a830"), 10, 3, 0.97)
	style.bg_color = Color("fff4dc")
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	# 補強ポイントの説明が長くなっても画面の縦に収まるようにスクロールの中へ
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(UiTheme.small_label("印を付けた選手", 16, Color("b3261e"), 800))
	_count_label = UiTheme.small_label("", 15, UiTheme.TEXT, 700)
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count_label.custom_minimum_size = Vector2(LEFT_WIDTH - 20, 0)
	box.add_child(_count_label)
	box.add_child(UiTheme.small_label("補強ポイント", 19, Color("b3261e"), 800))
	_needs_box = VBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 4)
	box.add_child(_needs_box)
	var hint := UiTheme.small_label("押すとその守備位置で絞り込み。将来は12球団での順位、年齢は正選手の平均、" \
		+ "今季は位置別の戦力（得失点）", 12, UiTheme.TEXT_SUB, 700)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(LEFT_WIDTH - 20, 0)
	box.add_child(hint)
	return panel


func _render_needs() -> void:
	var key := "%d|%d|%d|%s" % [GameState.year, GameState.phase, GameState.roster_version, GameState.team]
	if key != _needs_key:
		_needs_key = key
		_needs = compute_needs(GameState.team)
	for child in _needs_box.get_children():
		_needs_box.remove_child(child)
		child.queue_free()
	if _needs.is_empty():
		_needs_box.add_child(UiTheme.small_label("（デプスを計算できません）", 14, UiTheme.TEXT_SUB, 700))
	for i in _needs.size():
		var n: Dictionary = _needs[i]
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, n["pos"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(LEFT_WIDTH - 20, 34)
		b.add_theme_font_size_override("font_size", 18)
		UiTheme.style_button(b, Color("e8413c") if i == 0 else Color("f57c00"), Color.WHITE, 8, 4)
		b.tooltip_text = n["why"]
		b.pressed.connect(func() -> void:
			_filter = NEED_GROUP[n["pos"]]
			_message = "補強ポイント「%s」：%s" % [n["pos"], n["why"]]
			refresh())
		_needs_box.add_child(b)
		var why := UiTheme.small_label(n["why"], 13, UiTheme.TEXT, 700)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(LEFT_WIDTH - 20, 0)
		_needs_box.add_child(why)
	var counts := GameState.draft_board.counts(GameState.year)
	var parts: Array[String] = []
	for mark: String in DraftBoard.MARKS:
		parts.append("%s%d人" % [mark, int(counts.get(mark, 0))])
	_count_label.text = "　".join(parts)


## 補強ポイント（上位 NEED_COUNT 位置）[{pos, score, why}]。デプスの守備位置ランク（今・将来）を12球団の平均と比べ、
## 正選手の平均年齢（高いほど）と、B以上の選手がいないことを足す
static func compute_needs(team: String) -> Array:
	var all := {}
	for t: String in GameData.teams():
		all[t] = Depth.team_ranks(GameState.depth_of(t))
	if not all.has(team):
		return []
	var depth := GameState.depth_of(team)
	var values := _team_values(team)
	var runs_share := clampf(float(GameState.games_played()) / NEED_RUNS_FULL_GAMES, 0.0, 1.0)
	var result: Array = []
	for pos: String in Depth.POSITIONS:
		var now_sum := 0.0
		var fut_sum := 0.0
		var fut_order: Array = []
		for t: String in all:
			now_sum += float(all[t][pos]["now"])
			fut_sum += float(all[t][pos]["future"])
			fut_order.append(float(all[t][pos]["future"]))
		var n := float(all.size())
		var mine: Dictionary = all[team][pos]
		var score := NEED_NOW_WEIGHT * (now_sum / n - float(mine["now"])) \
			+ NEED_FUTURE_WEIGHT * (fut_sum / n - float(mine["future"]))
		var age := _regular_age(depth.get(pos, []), int(Depth.REGULARS[pos]))
		score += NEED_AGE_WEIGHT * maxf(0.0, age - NEED_AGE_FROM)
		if int(mine["thick"]) == 0:
			score += NEED_THIN
		var runs := NAN
		if not values.is_empty():
			runs = 0.0
			for col: String in NEED_RUNS_COLUMNS[pos]:
				runs += float(values.get(col, {}).get("total", 0.0))
			runs *= float(NEED_RUNS_SHARE.get(pos, 1.0))
			score += NEED_RUNS_WEIGHT * runs_share * -runs
		fut_order.sort()
		fut_order.reverse()
		var rank := fut_order.find(float(mine["future"])) + 1
		var why := "今%s・将来%s（12球団で%d位）" % [mine["now_rank"], mine["future_rank"], rank]
		if age > 0.0:
			why += "・%.0f歳" % age
		if int(mine["thick"]) == 0:
			why += "・%s以上なし" % Depth.THICK_RANK
		if not is_nan(runs) and runs_share > 0.0:
			why += "・今季%+d点" % roundi(runs)
		result.append({"pos": pos, "score": score, "why": why})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return result.slice(0, NEED_COUNT)


## 今季の自球団の位置別の戦力（TeamValue.from_stats の {位置: {total}}）。今季の成績が無ければ空
static func _team_values(team: String) -> Dictionary:
	var st := GameState.season_stats(GameState.year)
	if st.is_empty():
		return {}
	var all := TeamValue.from_stats(st, func(id: String) -> String:
		var pos: Variant = GameData.player(id).get("primary_pos")
		return str(pos) if pos != null else "")
	return all.get(team, {})


## 正選手（編成どおり。いなければ今の能力の上位）の平均年齢（不明は0）
static func _regular_age(list: Array, slots: int) -> float:
	var regs: Array = list.filter(func(e: Dictionary) -> bool: return e.get("regular", false))
	if regs.is_empty():
		regs = list.slice(0, slots)
	var total := 0.0
	var count := 0
	for e: Dictionary in regs:
		if int(e["age"]) > 0:
			total += float(e["age"])
			count += 1
	return total / count if count > 0 else 0.0


# --- 中央：一覧 ------------------------------------------------------------------------------

func _build_center() -> Control:
	_center = PanelContainer.new()
	var style := UiTheme.card(Color("2f7fd8"), 10, 4, 0.97)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_center.add_theme_stylebox_override("panel", style)
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	_center.add_child(stack)
	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	stack.add_child(list)
	_header_box = HBoxContainer.new()
	_header_box.add_theme_constant_override("separation", 2)
	list.add_child(_header_box)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(_list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	_list_scroll.add_child(_list_box)
	_experts_scroll = ScrollContainer.new()
	_experts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_experts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_experts_scroll.visible = false
	stack.add_child(_experts_scroll)
	_experts_box = VBoxContainer.new()
	_experts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_experts_box.add_theme_constant_override("separation", 6)
	_experts_scroll.add_child(_experts_box)
	return _center


func _columns() -> Array:
	var cols: Array = [["name", "名前", NAME_WIDTH]]
	for col: Array in DraftView.COLUMNS.get(_tab, DraftView.COLUMNS["info"]):
		cols.append([col[0], col[1], int(COLUMN_WIDTH.get(col[0], mini(int(col[2]), ABILITY_WIDTH)))])
	cols.append_array(TAIL_COLUMNS)
	return cols


func _render_header() -> void:
	for child in _header_box.get_children():
		_header_box.remove_child(child)
		child.queue_free()
	var mark := UiTheme.small_label("印", 15, UiTheme.TEXT, 800)
	mark.custom_minimum_size = Vector2(MARK_WIDTH, 0)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_box.add_child(mark)
	for col: Array in _columns():
		var key: String = col[0]
		var b := Button.new()
		b.text = str(col[1]) + (("▼" if _sort_desc else "▲") if key == _sort_key else "")
		b.custom_minimum_size = Vector2(col[2], 30)
		b.add_theme_font_size_override("font_size", 14)
		UiTheme.style_button(b, Color("ff8a3d") if key == _sort_key else Color("4f86d6"), Color.WHITE, 6, 4)
		b.clip_text = true
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := b.get_theme_stylebox(state)
			sb.content_margin_left = 2
			sb.content_margin_right = 2
		b.tooltip_text = "%sで並び替え（もう一度押すと逆順）" % col[1]
		if key == "yosou":
			b.tooltip_text = "有識者3人の順位予想を合わせた順位（上位%d人）\n" % DraftExperts.RANK_COUNT + b.tooltip_text
		b.pressed.connect(_on_header_pressed.bind(key))
		_header_box.add_child(b)


func _on_header_pressed(key: String) -> void:
	if _sort_key == key:
		_sort_desc = not _sort_desc
	else:
		_sort_key = key
		_sort_desc = key not in DraftView.ASCENDING_FIRST
	refresh()


func _rows(d: Draft) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if d == null:
		return rows
	var marked := GameState.draft_board.marked(d.year)
	for c in d.candidates:
		if _filter == "left" and not str(c["picked_by"]).is_empty():
			continue
		if _filter == "marked" and not marked.has(DraftBoard.key_of(c)):
			continue
		if _filter in DraftView.POS_SHORT and c["pos"] != _filter:
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
	var rows := _rows(d)
	if rows.is_empty():
		var text := "候補はいません。"
		if d == null:
			text = "%d年の候補は、春のアマ球界のニュース（3月31日）から出そろいます。" % GameState.year \
				if GameState.phase in [GameState.Phase.SEASON, GameState.Phase.CAMP] else "今年はドラフトの候補がいません。"
		elif _filter == "marked":
			text = "まだ印を付けた選手はいません。候補を選んで右の◎○△☆✕で印を付けます。"
		var label := UiTheme.small_label(text, 17, UiTheme.TEXT, 700)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(500, 0)
		_list_box.add_child(label)
		return
	for c in rows:
		_ids.append(c["id"])
		_list_box.add_child(_row(d, c))


func _row(d: Draft, c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var id: String = c["id"]
	row.add_child(_mark_button(d, c))
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(NAME_WIDTH, ROW_HEIGHT - 2)
	tag.font_size = 17
	var display_name: String = NameTag.family_name(c["name"])
	if is_breakout_rookie(c):
		display_name = "★" + display_name
	var p := GameData.player(id)
	if p.is_empty():
		tag.setup_plain(display_name, NameTag.pos_color(c["pos"]))
	else:
		tag.setup_player(p, display_name)
	tag.selected = id == _selected
	tag.dimmed = not str(c["picked_by"]).is_empty()
	var tips: Array[String] = ["%s（%s・%s）" % [c["name"], c["pos"], c["school"]]]
	if is_breakout_rookie(c):
		var first: Dictionary = c.get("first", {})
		tips.append("★【史実1年目ブレイク・即戦力】1年目シーズン後総合: %d（%s）" % [
			int(first.get("overall", -1)), DraftView.ability_rank(int(first.get("overall", -1)))])
	for n: Dictionary in _needs:
		if n.get("pos") == c["pos"] or NEED_GROUP.get(n.get("pos")) == c["pos"]:
			tips.append("🎯自球団の補強ポイント【%s】に合致します！" % n.get("pos"))
			break
	tag.tooltip_text = "\n".join(tips)
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	for col: Array in _columns().slice(1):
		row.add_child(_cell(c, col[0], col[2]))
	return row


## ワンクリックで印を切り替えられるボタンスタイル
func _mark_button(d: Draft, c: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MARK_WIDTH, ROW_HEIGHT - 4)
	var key := DraftBoard.key_of(c)
	var mark := GameState.draft_board.mark_of(d.year, key)
	var memo := GameState.draft_board.memo_of(d.year, key)
	if not mark.is_empty():
		b.text = mark
		var color: Color = DraftBoard.MARK_COLORS.get(mark, UiTheme.TEXT)
		UiTheme.style_button(b, color, Color.WHITE, 6, 2)
		b.add_theme_font_override("font", UiTheme.font(900))
		b.add_theme_font_size_override("font_size", 20)
		b.tooltip_text = "作戦会議：%s%s\n【クリックで印変更（◎→○→△→☆→✕→解除）／右クリックで逆順】" \
			% [DraftBoard.MARK_NAMES.get(mark, ""), "\n" + memo if not memo.is_empty() else ""]
	else:
		b.text = "＋"
		UiTheme.style_button(b, Color(0.88, 0.91, 0.95, 0.7), Color(0.45, 0.5, 0.58), 6, 2)
		b.add_theme_font_override("font", UiTheme.font(700))
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = "クリックで印をつける（◎→○→△→☆→✕）"
	b.pressed.connect(func() -> void: _cycle_mark_for(c, 1))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_cycle_mark_for(c, -1))
	return b


func _cycle_mark_for(c: Dictionary, delta: int = 1) -> void:
	var d := source()
	if d == null:
		return
	var key := DraftBoard.key_of(c)
	var board := GameState.draft_board
	var now := board.mark_of(d.year, key)
	var cycle: Array[String] = [""] + DraftBoard.MARKS
	var idx := cycle.find(now)
	if idx < 0:
		idx = 0
	var next_idx := posmod(idx + delta, cycle.size())
	var next := cycle[next_idx]
	_selected = c["id"]
	board.set_mark(d.year, key, next)
	GameState.draft_board_changed()
	if next.is_empty():
		_message = "%sの印を外しました。" % c["name"]
	else:
		_message = "%sに%s（%s）を付けました。" % [c["name"], next, DraftBoard.MARK_NAMES[next]]
		if next == "◎":
			_message += "本命の%d番手です。" % (board.favorite_list(d.year).find(key) + 1)
	refresh()


## 史実1年目から活躍した選手判定
static func is_breakout_rookie(c: Dictionary) -> bool:
	var first: Dictionary = c.get("first", {})
	var overall: int = int(first.get("overall", -1))
	if overall >= 65:
		return true
	if first.get("status") == "1軍" and overall >= 55:
		return true
	return false


## 印の札（ドラフト画面の一覧でも使う）。memo があれば札に浮かぶ説明に出す
static func mark_label(mark: String, width: int, height: int, memo := "") -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(width, height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.font(900))
	label.add_theme_font_size_override("font_size", 22)
	if not mark.is_empty():
		label.text = mark
		var color: Color = DraftBoard.MARK_COLORS.get(mark, UiTheme.TEXT)
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_outline_color", Color.WHITE)
		label.add_theme_constant_override("outline_size", 4)
		label.tooltip_text = "作戦会議：%s%s" % [DraftBoard.MARK_NAMES.get(mark, ""), "\n" + memo if not memo.is_empty() else ""]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


func _cell(c: Dictionary, key: String, width: int) -> Control:
	if key == "first":
		return _first_cell(c, width)
	if key in ["hyouka", "future"]:
		var rank: String = c["hyouka_rank"] if key == "hyouka" else c["future_rank"]
		var label := UiTheme.rank_label({"rank": rank, "value": 0}, 21)
		label.custom_minimum_size = Vector2(width, 0)
		return label
	if key == "yosou":
		return yosou_label(c, width)
	if key in ["overall", "stamina", "k9", "bb9", "meet", "power", "eye", "speed", "arm", "defense"]:
		var value := int(c["ratings"].get(key, -1))
		var box := HBoxContainer.new()
		box.custom_minimum_size = Vector2(width, 0)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 1)
		if value < 0:
			box.add_child(UiTheme.small_label("-", 15, UiTheme.TEXT_SUB, 700))
		else:
			box.add_child(UiTheme.rank_label({"rank": DraftView.ability_rank(value), "value": value}, 18))
			box.add_child(UiTheme.small_label(str(value), 12, UiTheme.TEXT_SUB, 700))
		return box
	var text := ""
	match key:
		"pos":
			text = DraftView.POS_SHORT.get(c["pos"], "-")
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
	l.add_theme_font_size_override("font_size", 16 if key != "school" else 14)
	l.add_theme_color_override("font_color", NameTag.pos_color(c["pos"]).darkened(0.45) if key == "pos" \
		else UiTheme.TEXT)
	return l


func _first_cell(c: Dictionary, width: int) -> Control:
	var first: Dictionary = c.get("first", {})
	var overall: int = int(first.get("overall", -1))
	var status: String = str(first.get("status", "なし"))
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	if overall <= 0:
		var l := UiTheme.small_label("-" if status != "未来" else "未来", 14, UiTheme.TEXT_SUB, 700)
		l.custom_minimum_size = Vector2(width, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l
	var rank_val := DraftView.ability_rank(overall)
	var rank_label := UiTheme.rank_label({"rank": rank_val, "value": overall}, 18)
	if overall >= 65:
		rank_label.add_theme_color_override("font_color", Color("e65100"))
	box.add_child(rank_label)
	var num_label := UiTheme.small_label(str(overall), 12, UiTheme.TEXT if overall < 65 else Color("e65100"), 700)
	box.add_child(num_label)
	box.tooltip_text = "史実1年目のシーズン後能力（総合 %d / %sランク・%s）\n1年目から即戦力として活躍するかどうかの目安です" \
		% [overall, rank_val, status]
	return box


## 予想順位の札（ドラフト画面の一覧でも使う）。予想に入っていなければ「-」
static func yosou_label(c: Dictionary, width: int) -> Label:
	var rank := int(c.get("yosou", 0))
	var l := Label.new()
	l.text = "%d位" % rank if rank > 0 else "-"
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.font(800))
	l.add_theme_font_size_override("font_size", 15)
	var color := Color("b3261e") if rank > 0 and rank <= 12 else (UiTheme.TEXT if rank > 0 else UiTheme.TEXT_SUB)
	l.add_theme_color_override("font_color", color)
	l.tooltip_text = "有識者3人の順位予想を合わせた順位" if rank > 0 else "有識者の順位予想（上位%d人）に入っていない" \
		% DraftExperts.RANK_COUNT
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


# --- 中央：有識者の予想 ----------------------------------------------------------------------

func _render_experts(d: Draft) -> void:
	for child in _experts_box.get_children():
		_experts_box.remove_child(child)
		child.queue_free()
	_tags.clear()
	_ids.clear()
	var pred := GameState.draft_predictions() if d != null else {}
	var experts: Array = pred.get("experts", [])
	if experts.is_empty():
		_experts_box.add_child(UiTheme.small_label("まだ予想はありません（候補が出そろってから）。", 17, UiTheme.TEXT, 700))
		return
	var names: Dictionary = pred.get("names", {})
	var by_key := _by_key(d)
	var head := UiTheme.small_label("評論家3人の予想（%s 時点）。もとは評判（当時の評価）。実際の指名は各球団の補強ポイントや" \
		% str(pred.get("date", "")) + "将来性の見立てで変わることも多い。名前を押すと右に要約", 14, UiTheme.TEXT, 700)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(560, 0)
	_experts_box.add_child(head)
	var real := GameState.draft()
	var actual := DraftExperts.actual_first_bids(real) if DraftExperts.first_wave_done(real) else {}
	var first_title := UiTheme.small_label("12球団の1位予想（カッコの数＝その評論家が同じ選手に予想した球団の数＝競合の予想）",
		16, Color("b3261e"), 800)
	first_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	first_title.custom_minimum_size = Vector2(560, 0)
	_experts_box.add_child(first_title)
	var grid := GridContainer.new()
	grid.columns = experts.size() + (2 if not actual.is_empty() else 1)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	_experts_box.add_child(grid)
	grid.add_child(UiTheme.small_label("球団", 14, UiTheme.TEXT, 800))
	for i in experts.size():
		var ex: Dictionary = DraftExperts.EXPERTS[i]
		var h := UiTheme.small_label(str(ex["name"]), 14, UiTheme.TEXT, 800)
		h.tooltip_text = "%s。%s" % [ex["title"], ex["style"]]
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(h)
	if not actual.is_empty():
		grid.add_child(UiTheme.small_label("実際の1位入札", 14, Color("1e63c8"), 800))
	var teams: Array = experts[0]["firsts"].keys()
	for t: String in teams:
		var team_label := UiTheme.small_label(GameData.short_name(t), 15, MINE_INK if t == GameState.team else UiTheme.TEXT, 800)
		team_label.custom_minimum_size = Vector2(56, 0)
		grid.add_child(team_label)
		for i in experts.size():
			var key := str(experts[i]["firsts"].get(t, ""))
			var rivals := DraftExperts.predicted_bidders(pred, i, key).size()
			var text := str(names.get(key, "-")) + ("（%d）" % rivals if rivals >= 2 else "")
			var hit := not actual.is_empty() and str(actual.get(t, "")) == key
			grid.add_child(_name_button(text, by_key.get(key, ""), d, key, hit, not actual.is_empty() and not hit))
		if not actual.is_empty():
			var akey := str(actual.get(t, ""))
			grid.add_child(_name_button(str(names.get(akey, d.by_id.get(by_key.get(akey, ""), {}).get("name", "-"))),
				by_key.get(akey, ""), d, akey, false, false))
	_experts_box.add_child(UiTheme.small_label("全体の順位予想（上位%d人）" % DraftExperts.RANK_COUNT, 17, Color("b3261e"), 800))
	var styles: Array[String] = []
	for ex: Dictionary in DraftExperts.EXPERTS:
		styles.append("%s＝%s（%s）" % [ex["name"], ex["style"], ex["title"]])
	var style_label := UiTheme.small_label("\n".join(styles), 13, UiTheme.TEXT_SUB, 700)
	style_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_label.custom_minimum_size = Vector2(560, 0)
	_experts_box.add_child(style_label)
	var ranks := GridContainer.new()
	ranks.columns = experts.size() + 1
	ranks.add_theme_constant_override("h_separation", 6)
	ranks.add_theme_constant_override("v_separation", 2)
	_experts_box.add_child(ranks)
	ranks.add_child(UiTheme.small_label("順位", 14, UiTheme.TEXT, 800))
	for i in experts.size():
		var ex: Dictionary = DraftExperts.EXPERTS[i]
		var h := UiTheme.small_label(str(ex["name"]), 14, UiTheme.TEXT, 800)
		h.tooltip_text = "%s。%s" % [ex["title"], ex["style"]]
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		ranks.add_child(h)
	for r in DraftExperts.RANK_COUNT:
		ranks.add_child(UiTheme.small_label("%d" % (r + 1), 15, UiTheme.TEXT, 800))
		for i in experts.size():
			var ranking: Array = experts[i]["ranking"]
			var key := str(ranking[r]) if r < ranking.size() else ""
			var info: Dictionary = pred.get("info", {}).get(key, {})
			var text := "%s（%s）" % [names.get(key, "-"), DraftView.POS_SHORT.get(str(info.get("pos", "")), "")] \
				if not key.is_empty() else "-"
			ranks.add_child(_name_button(text, by_key.get(key, ""), d, key, false, false))



## 予想の表の名前（押すと右に要約）。印があれば頭に付ける。hit：的中（緑）、miss：外れ（灰）
func _name_button(text: String, id: String, d: Draft, key: String, hit: bool, miss: bool) -> Control:
	var b := Button.new()
	var mark := GameState.draft_board.mark_of(d.year, key) if not key.is_empty() else ""
	b.text = (mark + " " if not mark.is_empty() else "") + text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(EXPERT_NAME_WIDTH, 26)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_font_override("font", UiTheme.font(700))
	b.add_theme_constant_override("outline_size", 0)
	var ink := Color("2e7d32") if hit else (UiTheme.TEXT_SUB if miss else UiTheme.TEXT)
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	if hit:
		b.text = "◯的中 " + b.text
	b.disabled = id.is_empty()
	if not id.is_empty():
		b.pressed.connect(_on_tag_pressed.bind(id))
		if id == _selected:
			b.add_theme_color_override("font_color", MINE_INK)
	return b


# --- 右：要約・印・本命の順番 ----------------------------------------------------------------

func _build_right() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(Color("8ecae6"), 10, 3, 0.97)
	style.bg_color = Color("dff1fb")
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	box.add_child(scroll)
	_summary_box = VBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 3)
	_summary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_summary_box)
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", 3)
	box.add_child(marks)
	for mark: String in DraftBoard.MARKS + [""]:
		var b := Button.new()
		b.text = mark if not mark.is_empty() else "消す"
		b.toggle_mode = not mark.is_empty()
		b.custom_minimum_size = Vector2(42 if not mark.is_empty() else 52, 40)
		b.add_theme_font_size_override("font_size", 22 if not mark.is_empty() else 15)
		UiTheme.style_button(b, DraftBoard.MARK_COLORS.get(mark, Color("8a9199")), Color.WHITE, 8, 4)
		b.tooltip_text = DraftBoard.MARK_NAMES.get(mark, "印を外す")
		b.pressed.connect(_on_mark_pressed.bind(mark))
		marks.add_child(b)
		_mark_buttons[mark] = b
	_memo_edit = LineEdit.new()
	_memo_edit.placeholder_text = "メモ（1行）"
	_memo_edit.max_length = 40
	_memo_edit.add_theme_font_size_override("font_size", 15)
	_memo_edit.text_changed.connect(_on_memo_changed)
	box.add_child(_memo_edit)
	box.add_child(UiTheme.small_label("1位入札の本命の順番（外れ1位もこの順）", 15, Color("b3261e"), 800))
	var fav_scroll := ScrollContainer.new()
	fav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fav_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fav_scroll)
	_fav_box = VBoxContainer.new()
	_fav_box.add_theme_constant_override("separation", 2)
	_fav_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fav_scroll.add_child(_fav_box)
	return panel


func _render_summary(d: Draft) -> void:
	for child in _summary_box.get_children():
		_summary_box.remove_child(child)
		child.queue_free()
	var c: Dictionary = d.by_id.get(_selected, {}) if d != null else {}
	for mark: String in _mark_buttons:
		var b: Button = _mark_buttons[mark]
		b.disabled = c.is_empty()
	_memo_edit.editable = not c.is_empty()
	if c.is_empty():
		var hint := UiTheme.small_label("候補を選ぶと要約が出ます。印：◎本命（1位候補）・○上位候補・△中位・☆掘り出し物・✕回避。" \
			+ "ドラフト会議では印の選手が一覧で目立ち、本命の1番目が1位入札の初期値・おすすめになります（おまかせでも印を優先）。",
			14, UiTheme.TEXT, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 0)
		_summary_box.add_child(hint)
		_memo_edit.text = ""
		for mark: String in _mark_buttons:
			(_mark_buttons[mark] as Button).set_pressed_no_signal(false)
		return
	var key := DraftBoard.key_of(c)
	var mark_now := GameState.draft_board.mark_of(d.year, key)
	for mark: String in _mark_buttons:
		(_mark_buttons[mark] as Button).set_pressed_no_signal(mark == mark_now and not mark.is_empty())
	var memo := GameState.draft_board.memo_of(d.year, key)
	if _memo_edit.text != memo and not _memo_edit.has_focus():
		_memo_edit.text = memo
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.add_child(mark_label(mark_now, 30, 36))
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(150, 38)
	tag.font_size = 22
	var p := GameData.player(c["id"])
	if p.is_empty():
		tag.setup_plain(NameTag.family_name(c["name"]), NameTag.pos_color(c["pos"]))
	else:
		tag.setup_player(p, NameTag.family_name(c["name"]))
		var id: String = c["id"]
		tag.tooltip_text = "Ⓐ／クリックで選手詳細"
		tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, _ids))
	line.add_child(tag)
	var pos := Label.new()
	pos.text = c["pos"]
	UiTheme.heading(pos, 20, NameTag.pos_color(c["pos"]).darkened(0.45), Color.WHITE, 5)
	line.add_child(pos)
	_summary_box.add_child(line)
	var age := ("%d歳" % int(c["age"])) if int(c["age"]) > 0 else "年齢不明"
	_add_text("%s　%s　%s\n%s" % [c["name"], c["career"], age, c["school"]], 15, UiTheme.TEXT)

	# 1年目ブレイク・即戦力選手の見出し
	if is_breakout_rookie(c):
		var first: Dictionary = c.get("first", {})
		var f_ovr: int = int(first.get("overall", -1))
		var banner := PanelContainer.new()
		banner.custom_minimum_size = Vector2(RIGHT_WIDTH - 40, 0)
		var b_style := UiTheme.card(Color("ff9800"), 6, 2, 0.95)
		b_style.bg_color = Color("fff8e1")
		banner.add_theme_stylebox_override("panel", b_style)
		var b_box := VBoxContainer.new()
		b_box.add_theme_constant_override("separation", 1)
		var b_title := UiTheme.small_label("★ 史実1年目から即戦力で大活躍！", 13, Color("e65100"), 800)
		b_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b_box.add_child(b_title)
		var b_detail := UiTheme.small_label("1年目総合 %d（%sランク・%s）" % [
			f_ovr, DraftView.ability_rank(f_ovr), str(first.get("status", "1軍"))], 12, UiTheme.TEXT, 700)
		b_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b_box.add_child(b_detail)
		banner.add_child(b_box)
		_summary_box.add_child(banner)

	# 補強ポイント合致表示
	for n: Dictionary in _needs:
		if n.get("pos") == c["pos"] or NEED_GROUP.get(n.get("pos")) == c["pos"]:
			var n_label := UiTheme.small_label("🎯 補強ポイント【%s】に合致します！" % n.get("pos"), 13, Color("b3261e"), 800)
			n_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			n_label.custom_minimum_size = Vector2(RIGHT_WIDTH - 40, 0)
			_summary_box.add_child(n_label)
			break

	var ranks := HBoxContainer.new()
	ranks.add_theme_constant_override("separation", 4)
	ranks.add_child(UiTheme.small_label("評価", 15, UiTheme.TEXT, 800))
	ranks.add_child(UiTheme.rank_label({"rank": c["hyouka_rank"], "value": 0}, 26))
	ranks.add_child(UiTheme.small_label(" 将来性", 15, UiTheme.TEXT, 800))
	ranks.add_child(UiTheme.rank_label({"rank": c["future_rank"], "value": 0}, 26))
	ranks.add_child(UiTheme.small_label(" 予想", 15, UiTheme.TEXT, 800))
	ranks.add_child(yosou_label(c, 48))
	_summary_box.add_child(ranks)
	_add_text(_ability_text(c), 14, UiTheme.TEXT)
	_add_text("「%s」" % c["intro"], 14, Color("1e63c8"))
	var notes: Array[String] = []
	if c.get("mlb_intent", false):
		notes.append("メジャー志望（指名したら説得の交渉）")
	if not c.get("reincarnation", {}).is_empty():
		notes.append("転生選手：%sの生まれ変わり" % c["reincarnation"]["name"])
	if not str(c["picked_by"]).is_empty():
		notes.append("済：%s %s" % [GameData.short_name(c["picked_by"]), c["pick_label"]])
	if GameState.draft() == null:
		notes.append("※将来性はスカウトの見立て（ドラフト当日に変わることがあります）")
	if not notes.is_empty():
		_add_text("\n".join(notes), 13, UiTheme.TEXT_SUB)


func _add_text(text: String, font_size: int, color: Color) -> void:
	var label := UiTheme.small_label(text, font_size, color, 700)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 0)
	_summary_box.add_child(label)


static func _ability_text(c: Dictionary) -> String:
	var keys: Array = [["overall", "総合"], ["stamina", "ス"], ["k9", "三振"], ["bb9", "制球"]] if c["pitcher"] \
		else [["meet", "ミ"], ["power", "パ"], ["eye", "眼"], ["speed", "走"], ["arm", "肩"], ["defense", "守"]]
	var parts: Array[String] = []
	if c["pitcher"] and int(c.get("velocity", 0)) > 0:
		parts.append("%dkm" % int(c["velocity"]))
	for k: Array in keys:
		var v := int(c["ratings"].get(k[0], -1))
		parts.append("%s%s" % [k[1], DraftView.ability_rank(v) if v >= 0 else "-"])
	return " ".join(parts)


func _render_favorites(d: Draft) -> void:
	for child in _fav_box.get_children():
		_fav_box.remove_child(child)
		child.queue_free()
	if d == null:
		return
	var by_key := _by_key(d)
	var favs := GameState.draft_board.favorite_list(d.year)
	if favs.is_empty():
		var hint := UiTheme.small_label("◎を付けた選手がここに並びます。1番目がドラフト会議の1位入札の初期値です。", 13,
			UiTheme.TEXT_SUB, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 0)
		_fav_box.add_child(hint)
		return
	for i in favs.size():
		var key := str(favs[i])
		var id: String = by_key.get(key, "")
		var c: Dictionary = d.by_id.get(id, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var b := Button.new()
		var name_text: String = c.get("name", key) if not c.is_empty() else key
		var gone := not c.is_empty() and not str(c["picked_by"]).is_empty()
		b.text = "%d. %s（%s）%s" % [i + 1, name_text, DraftView.POS_SHORT.get(str(c.get("pos", "")), "-"),
			"済" if gone else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 15)
		UiTheme.style_button(b, Color("8a9199") if gone else Color("e53935"), Color.WHITE, 6, 4)
		if not id.is_empty():
			b.pressed.connect(_on_tag_pressed.bind(id))
		row.add_child(b)
		for delta: int in [-1, 1]:
			var m := Button.new()
			m.text = "▲" if delta < 0 else "▼"
			m.custom_minimum_size = Vector2(32, 32)
			UiTheme.style_button(m, Color("2f7fd8"), Color.WHITE, 6, 3)
			m.disabled = (delta < 0 and i == 0) or (delta > 0 and i == favs.size() - 1)
			m.pressed.connect(_on_move_favorite.bind(key, delta))
			row.add_child(m)
		_fav_box.add_child(row)


func _render_status(d: Draft) -> void:
	var text := _message
	if text.is_empty():
		if d == null:
			text = "候補が出そろうと、ほしい選手に印を付けられます。"
		elif GameState.draft_open():
			text = "ドラフト会議の途中です。印・本命の順を変えると、ドラフト会議のおすすめ・おまかせにすぐ反映されます。"
		elif GameState.draft_meeting_due() or _draft_button.visible:
			text = "印と本命の順番を決めたら「ドラフト会議へ」。本命の1番目が1位入札の初期値になります。"
		else:
			text = "印と本命の順番はセーブに残り、オフのドラフト会議で使います（ドラフトの直前にもう一度開けます）。"
	_status_label.text = text
	message_changed.emit(text)


# --- 操作 ----------------------------------------------------------------------------------

func _on_tag_pressed(id: String) -> void:
	if _selected == id and not GameData.player(id).is_empty():
		PlayerDetail.open(_tags.get(id, self), id, _ids)
		return
	_selected = id
	_message = ""
	refresh()


func _on_mark_pressed(mark: String) -> void:
	var d := source()
	if d == null or not d.by_id.has(_selected):
		return
	var c: Dictionary = d.by_id[_selected]
	var key := DraftBoard.key_of(c)
	var board := GameState.draft_board
	var now := board.mark_of(d.year, key)
	var next := "" if mark == now else mark
	board.set_mark(d.year, key, next)
	GameState.draft_board_changed()
	if next.is_empty():
		_message = "%sの印を外しました。" % c["name"]
	else:
		_message = "%sに%s（%s）を付けました。" % [c["name"], next, DraftBoard.MARK_NAMES[next]]
		if next == "◎":
			_message += "本命の%d番手です。" % (board.favorite_list(d.year).find(key) + 1)
	refresh()


func _on_memo_changed(text: String) -> void:
	var d := source()
	if d == null or not d.by_id.has(_selected):
		return
	GameState.draft_board.set_memo(d.year, DraftBoard.key_of(d.by_id[_selected]), text)
	_shown_key = ""


func _on_move_favorite(key: String, delta: int) -> void:
	var d := source()
	if d == null:
		return
	if GameState.draft_board.move_favorite(d.year, key, delta):
		GameState.draft_board_changed()
		_message = "本命の順番を変えました。"
		refresh()
