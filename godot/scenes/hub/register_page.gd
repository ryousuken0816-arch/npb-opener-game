class_name RegisterPage
extends VBoxContainer
## 采配 → 投手1軍登録／野手1軍登録（docs/references/README.md「register_pitchers / register_fielders」）。
##
## 左に1軍（投手は 先発／中継ぎ／抑え の枠、空き枠は「あき」）、中央に2軍、右に選んだ選手の要約。
## 選手の札をクリックして選び、続けて入れ替える相手をクリックする：
##   1軍 ⇔ 2軍 … 登録の入れ替え（上げた選手は落とした選手の持ち場・打順に入る）
##   1軍 ⇔ 1軍（投手）… 持ち場の入れ替え ／ 「あき」… その持ち場へ移す・2軍から上げる
## 人数の上限・外国人枠・抹消後10日間の再登録制限は SimTeam（RosterRules）が判定し、できないときは理由を表示する。
## コントローラー：十字キーで札を選び Ⓐ で選択→相手の札で Ⓐ。入れ替えて作り直しても、フォーカスは同じ位置に残る。
## 選んでいる札をもう一度 Ⓐ・クリック（または右クリック、右の「詳細」）で選手詳細。Ⓑ はまず選択を取り消す。

signal roster_changed

const TAG_SIZE := Vector2(138, 34)
## 右の要約の中身の幅。1軍（2列）＋2軍＋要約が采配の広げた画面（1280x720 で幅986）に収まる大きさ
const SUMMARY_WIDTH := 240
const FLAG_WIDTH := 26
const VALUE_WIDTH := 22
const ROLE_SECTIONS := [
	[SimTeam.ROLE_ROTATION, "先発"], [SimTeam.ROLE_RELIEF, "中継ぎ"], [SimTeam.ROLE_CLOSER, "抑え"],
]
const ROLE_NAMES := {
	SimTeam.ROLE_ROTATION: "先発ローテ", SimTeam.ROLE_RELIEF: "中継ぎ", SimTeam.ROLE_CLOSER: "抑え",
}
const SECTION_COLORS := {
	SimTeam.ROLE_ROTATION: Color("fde3e6"), SimTeam.ROLE_RELIEF: Color("f7e6f5"),
	SimTeam.ROLE_CLOSER: Color("efe4fb"),
}
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "内野手": "内",
	"外野手": "外", "左翼手": "左", "中堅手": "中", "右翼手": "右", "指名打者": "指", "投手": "投",
}

var pitchers := true

var _palette: UiTheme.Palette
var _team: SimTeam
var _names := {}
var _selected: SimPlayer = null
var _message := ""
var _message_error := false

var _count_label: Label
var _message_label: Label
var _active_title: Label
var _active_box: VBoxContainer
var _farm_title: Label
var _farm_box: VBoxContainer
var _summary_box: VBoxContainer
## 札の並び（選手詳細の十字キーで送る順）
var _order_ids: Array[String] = []


func setup(p: UiTheme.Palette, is_pitchers: bool) -> void:
	_palette = p
	pitchers = is_pitchers
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	_count_label = Label.new()
	UiTheme.heading(_count_label, 19, p.ink, Color.WHITE, 5, false)
	top.add_child(_count_label)
	_message_label = UiTheme.fit_label(UiTheme.small_label("", 16, UiTheme.TEXT_SUB, 700))
	top.add_child(_message_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var active := UiTheme.titled_panel(p, "1軍")
	active["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active["panel"].size_flags_stretch_ratio = 1.9
	_active_title = active["title"]
	_active_box = _scroll_box(active["body"])
	body.add_child(active["panel"])
	var farm := UiTheme.titled_panel(p, "2軍")
	farm["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_farm_title = farm["title"]
	_farm_box = _scroll_box(farm["body"])
	body.add_child(farm["panel"])
	var summary := UiTheme.titled_panel(p, "選手")
	summary["panel"].custom_minimum_size = Vector2(266, 0)
	_summary_box = summary["body"]
	body.add_child(summary["panel"])


## 表示を作り直す。reset_selection で選択とメッセージも消す（画面を開き直したとき）
func refresh(reset_selection: bool = false) -> void:
	_team = GameState.my_team()
	if reset_selection:
		_selected = null
		_message = ""
	if _team == null:
		_count_label.text = "日程データのない年は編成できません"
		return
	if _selected != null and not _team.by_id.has(_selected.id):
		_selected = null
	# 作り直す前のフォーカスの位置（1軍・2軍の枠の何番目か）を覚えておく
	var focus_box: Control = null
	var focus_at := -1
	for box: Control in [_active_box, _farm_box]:
		var i := UiInput.focus_index(box)
		if i >= 0:
			focus_box = box
			focus_at = i
	_names = NameTag.short_names(_team.players)
	_order_ids.clear()
	_render_counts()
	_render_active()
	_render_farm()
	_render_summary()
	if focus_box != null:
		UiInput.focus_nth(focus_box, focus_at)


## 選んでいる札を取り消す（取り消したら true。Ⓑ で画面を戻る前に呼ぶ）
func clear_selection() -> bool:
	if _selected == null:
		return false
	_selected = null
	_message = ""
	refresh()
	return true


## 画面を開いたとき：1軍の最初の札にフォーカス
func focus_first() -> void:
	if not UiInput.focus_first(_active_box):
		UiInput.focus_first(_farm_box)


func _scroll_box(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _render_counts() -> void:
	var fc := _team.foreign_counts()
	var year := _team.year
	_count_label.text = "1軍 %d/%d人　投%d(%d) 野%d(%d)　外国人 %d/%d" % [
		_team.active_count(), RosterRules.roster_limit(year),
		_team.active_players(true).size(), fc[0], _team.active_players(false).size(), fc[1],
		fc[0] + fc[1], RosterRules.foreign_limit(year)]
	_count_label.tooltip_text = ("1軍の登録は%d人まで。外国人は%d人まで（投手・野手それぞれ%d人まで）。\n"
			+ "括弧内は外国人の人数。登録を抹消した選手は10日間再登録できません。") % [
		RosterRules.roster_limit(year), RosterRules.foreign_limit(year),
		RosterRules.foreign_type_limit(year)]
	_count_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not GameState.can_edit_roster():
		_message_label.text = "オフシーズンは編成を変えられません（見るだけ）"
		_message_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	elif _message.is_empty():
		_message_label.text = "選手を選んでから、入れ替える相手（1軍⇔2軍）か「あき」をクリック"
		_message_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	else:
		_message_label.text = _message
		_message_label.add_theme_color_override("font_color",
				Color("d32f2f") if _message_error else Color("2e7d32"))
	_message_label.tooltip_text = _message_label.text


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _render_active() -> void:
	_clear(_active_box)
	var actives := _team.active_players(pitchers)
	_active_title.text = "1軍（%s %d人）" % ["投手" if pitchers else "野手", actives.size()]
	if pitchers:
		var room := _team.active_count() < RosterRules.roster_limit(_team.year)
		for section: Array in ROLE_SECTIONS:
			var role: String = section[0]
			var members: Array = []
			var slots := 0
			match role:
				SimTeam.ROLE_ROTATION:
					members = _team.rotation.duplicate()
					slots = SimTeam.ROTATION_SIZE
				SimTeam.ROLE_RELIEF:
					members = _team.relievers.duplicate()
					slots = members.size() + (2 - members.size() % 2)
				SimTeam.ROLE_CLOSER:
					members = [_team.closer] if _team.closer != null else []
					slots = 1
			_active_box.add_child(_role_section(role, section[1], members, slots, room))
	else:
		actives.sort_custom(_fielder_before)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		for p in actives:
			grid.add_child(_player_item(p, _flags(p)))
		if _team.active_count() < RosterRules.roster_limit(_team.year):
			grid.add_child(_empty_item(""))
		_active_box.add_child(grid)


## 先発／中継ぎ／抑えの枠（左に縦書きの見出し、右に2列の札）
func _role_section(role: String, title: String, members: Array, slots: int, room: bool) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(SECTION_COLORS[role].darkened(0.08), 8, 1)
	style.bg_color = SECTION_COLORS[role]
	style.gradient = 0.04
	style.shadow_size = 0
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var vertical: Array[String] = []
	for i in title.length():
		vertical.append(title[i])
	var head := UiTheme.small_label("\n".join(vertical), 17, Color("c2185b"), 800)
	head.custom_minimum_size = Vector2(26, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	for i in slots:
		if i < members.size():
			var p: SimPlayer = members[i]
			var flags := _flags(p)
			if role == SimTeam.ROLE_RELIEF and i < SimTeam.SETUP_COUNT:
				flags = "SU" + ("外" if p.is_foreign else "")
			grid.add_child(_player_item(p, flags))
		else:
			grid.add_child(_empty_item(role, room or _selected == null or _team.is_active(_selected)))
	return panel


## 札＋右に小さな印（SU=セットアッパー、外=外国人、★=スタメン）と、投手は総合ランク・野手は守備位置
func _player_item(p: SimPlayer, flags: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(GameData.player(p.id), _names.get(p.id, p.name))
	tag.selected = p == _selected
	tag.tooltip_text = _tooltip(p)
	tag.dimmed = _is_waiting(p)
	tag.pressed.connect(_on_player_pressed.bind(p))
	row.add_child(tag)
	_order_ids.append(p.id)
	var flag_label := UiTheme.small_label(flags, 13, Color("c2185b"), 800)
	flag_label.custom_minimum_size = Vector2(FLAG_WIDTH, 0)
	flag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(flag_label)
	if p.is_pitcher:
		var rank := UiTheme.rank_label(_overall_rating(p), 19)
		rank.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
		rank.tooltip_text = "総合 " + rank.tooltip_text
		row.add_child(rank)
	else:
		var pos := UiTheme.small_label(POS_SHORT.get(p.primary_pos, "-"), 16, UiTheme.TEXT_SUB, 800)
		pos.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(pos)
	return row


func _empty_item(role: String, enabled: bool = true) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_empty()
	tag.dimmed = not enabled
	tag.tooltip_text = "選んだ選手をここへ移す／2軍から上げる"
	tag.pressed.connect(_on_empty_pressed.bind(role))
	row.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(FLAG_WIDTH + VALUE_WIDTH + 4, 0)
	row.add_child(spacer)
	return row


func _render_farm() -> void:
	_clear(_farm_box)
	var farm := _team.players_where(false, pitchers)
	farm.sort_custom(_pitcher_before if pitchers else _fielder_before)
	_farm_title.text = "2軍（%d人）" % farm.size()
	for p in farm:
		_farm_box.add_child(_player_item(p, _flags(p)))


func _render_summary() -> void:
	_clear(_summary_box)
	if _selected == null:
		var hint := UiTheme.small_label(
				"札をクリックすると選手の能力と今季の成績を表示します。\n\n"
				+ "札の色は守備位置：投手＝赤、捕手＝水色、内野手＝黄、外野手＝緑（右側の色は他に守れる位置）。\n"
				+ "薄い札は登録抹消から10日たっていない選手です。札の右の「育」は育成選手（支配下に登録すると1軍に上げられます）。", 15)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
		_summary_box.add_child(hint)
		return
	var p := _selected
	var data := GameData.player(p.id)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(SUMMARY_WIDTH, 40)
	tag.font_size = 22
	tag.setup_player(data, p.name)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.focus_mode = Control.FOCUS_NONE
	_summary_box.add_child(tag)
	var line := "%s投%s打" % [p.throws, p.bats]
	if p.is_foreign:
		line += "　外国人"
	if data.get("birth") != null:
		line += "　%d歳" % _age(str(data["birth"]))
	_summary_box.add_child(_summary_line(line, 16, UiTheme.TEXT, 700))
	_summary_box.add_child(_summary_line(_status_text(p), 15, _palette.ink, 700))
	if p.is_pitcher:
		_pitcher_summary(p, data)
	else:
		_fielder_summary(p, data)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_box.add_child(spacer)
	var detail := Button.new()
	detail.text = "詳細を見る"
	detail.custom_minimum_size = Vector2(0, 38)
	detail.tooltip_text = "選手詳細（能力・成績・経歴）。札をもう一度押しても開きます"
	detail.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(detail, Color("1e88e5"), Color.WHITE, 8, 3)
	detail.pressed.connect(_open_detail.bind(p))
	_summary_box.add_child(detail)
	if p.is_ikusei and not _team.is_active(p):
		_ikusei_button()
	elif GameState.can_edit_roster():
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 38)
		if _team.is_active(p):
			button.text = "▼ 2軍へ落とす"
			UiTheme.style_button(button, Color("d84315"), Color.WHITE, 8, 3)
			button.pressed.connect(_demote_selected)
		else:
			button.text = "▲ 1軍へ上げる"
			UiTheme.style_button(button, Color("2e7d32"), Color.WHITE, 8, 3)
			button.pressed.connect(_promote_selected)
		_summary_box.add_child(button)


## 育成選手を選んだとき：「支配下に登録する」（春季キャンプ〜7月31日。期間外は押せず理由を出す。作業19）。
## コントローラーでも押せるようフォーカスを受ける
func _ikusei_button() -> void:
	var block := GameState.ikusei_promote_block()
	var button := Button.new()
	button.text = "支配下に登録する"
	button.disabled = not block.is_empty()
	button.tooltip_text = block if not block.is_empty() 			else "育成選手を支配下（%d人まで）に登録します。登録すると1軍に上げられます" % LeagueRoster.ROSTER_LIMIT
	UiTheme.style_button(button, Color("2e7d32"), Color.WHITE)
	button.pressed.connect(_promote_ikusei_selected)
	_summary_box.add_child(button)
	if not block.is_empty():
		_summary_box.add_child(_summary_line(block, 14, UiTheme.TEXT_SUB, 700))


func _pitcher_summary(p: SimPlayer, data: Dictionary) -> void:
	var pitching: Dictionary = data["pitching"] if data.get("pitching") is Dictionary else {}
	var velocity: Variant = pitching.get("velocity")
	var kmh := "-"
	if velocity is Dictionary and velocity.get("kmh") != null:
		kmh = "%d km/h" % int(velocity["kmh"])
	var role: Variant = pitching.get("role")
	_summary_box.add_child(_summary_line("適性 %s　球速 %s" % [role if role != null else "-", kmh],
			16, UiTheme.TEXT, 700))
	var ratings: Dictionary = pitching["ratings"] if pitching.get("ratings") is Dictionary else {}
	_summary_box.add_child(_rank_grid(ratings, [
		["overall", "総合"], ["bb9", "制球"], ["stamina", "スタミナ"], ["k9", "奪三振"], ["hr9", "被弾抑制"],
	]))
	var s: Dictionary = GameState.season.pitching.get(p.id, {}) if GameState.season != null else {}
	var era := "%.2f" % Season.era(s) if s.get("outs", 0) > 0 else "-"
	_summary_box.add_child(_summary_line("今季　%d登板 %d勝%d敗%dS　防御率 %s" % [
		s.get("g", 0), s.get("w", 0), s.get("l", 0), s.get("sv", 0), era], 15, UiTheme.TEXT, 700))


func _fielder_summary(p: SimPlayer, data: Dictionary) -> void:
	var batting: Dictionary = data["batting"] if data.get("batting") is Dictionary else {}
	var ratings: Dictionary = batting["ratings"] if batting.get("ratings") is Dictionary else {}
	var positions: Array[String] = []
	var fielding: Variant = data.get("fielding")
	if fielding is Dictionary:
		for pos: String in fielding:
			if int(fielding[pos].get("games", 0)) > 0 or pos == data.get("primary_pos"):
				positions.append(POS_SHORT.get(pos, pos))
	_summary_box.add_child(_summary_line("守備 %s　弾道 %s" % [
		"・".join(positions) if not positions.is_empty() else "-",
		str(int(batting["trajectory"])) if batting.get("trajectory") != null else "-"],
		16, UiTheme.TEXT, 700))
	_summary_box.add_child(_rank_grid(ratings, [
		["meet", "ミート"], ["power", "パワー"], ["speed", "走力"],
		["arm", "肩力"], ["defense", "守備力"], ["eye", "選球眼"],
	]))
	var b: Dictionary = GameState.season.batting.get(p.id, {}) if GameState.season != null else {}
	var avg := ("%.3f" % Season.batting_avg(b)).trim_prefix("0") if b.get("ab", 0) > 0 else "-"
	_summary_box.add_child(_summary_line("今季　%d試合 打率%s %d本 %d打点" % [
		b.get("g", 0), avg, b.get("hr", 0), b.get("rbi", 0)], 15, UiTheme.TEXT, 700))


## 要約の1行（UiTheme.small_label と同じ引数）。右の枠の幅で折り返す（今季成績・状態の長い文言で枠が広がり、
## 1軍・2軍の欄を押し出して画面からはみ出していた。作業11）
func _summary_line(text: String, font_size: int, color: Color, weight: int) -> Label:
	var label := UiTheme.small_label(text, font_size, color, weight)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## 能力のランクを2列で並べる
func _rank_grid(ratings: Dictionary, columns: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	for col: Array in columns:
		var name_label := UiTheme.small_label(col[1], 16, UiTheme.TEXT, 700)
		name_label.custom_minimum_size = Vector2(60, 0)
		grid.add_child(name_label)
		var rank := UiTheme.rank_value_box(ratings.get(col[0]), 22)  # ランクと数値（作業64）
		rank.custom_minimum_size = Vector2(52, 0)
		grid.add_child(rank)
	return grid


func _status_text(p: SimPlayer) -> String:
	if _team.is_active(p):
		if p.is_pitcher:
			var role := _team.pitcher_role(p)
			if role[0] == SimTeam.ROLE_ROTATION:
				return "1軍・先発ローテ %d番手" % (role[1] + 1)
			if role[0] == SimTeam.ROLE_RELIEF and role[1] < SimTeam.SETUP_COUNT:
				return "1軍・セットアッパー"
			return "1軍・%s" % ROLE_NAMES.get(role[0], "")
		var parts: Array[String] = []
		for use_dh in [true, false]:
			var order: Array = _team.lineup(use_dh)
			for i in order.size():
				if order[i][0] == p:
					parts.append("%s %d番%s" % ["DHあり" if use_dh else "DHなし", i + 1,
						POS_SHORT.get(order[i][1], "")])
		return "1軍・" + (" / ".join(parts) if not parts.is_empty() else "控え")
	if p.is_ikusei:
		return "育成（支配下に登録すると1軍に上げられます）"
	if _is_waiting(p):
		return "2軍（%sから再登録できます）" % Season.day_label(_team.reregister_day(p))
	return "2軍"


## 登録抹消から10日たっていない2軍の選手か（抹消したその日のうちは取り消せるので対象外）
func _is_waiting(p: SimPlayer) -> bool:
	if _team.is_active(p) or not _team.demoted_day.has(p.id):
		return false
	var today: int = GameState.day
	return today < _team.reregister_day(p) and today != int(_team.demoted_day[p.id])


func _tooltip(p: SimPlayer) -> String:
	return "%s（%s）\n%s" % [p.name, p.primary_pos if not p.primary_pos.is_empty() else "守備位置不明",
		_status_text(p)]


func _overall_rating(p: SimPlayer) -> Variant:
	var pitching: Variant = GameData.player(p.id).get("pitching")
	if pitching is Dictionary and pitching.get("ratings") is Dictionary:
		return pitching["ratings"].get("overall")
	return null


## 札の右の印：外=外国人、育=育成、★=スタメン（DHあり・なしのどちらか）
func _flags(p: SimPlayer) -> String:
	var flags := ("外" if p.is_foreign else "") + ("育" if p.is_ikusei else "")
	if not p.is_pitcher and _team.is_active(p):
		for use_dh in [true, false]:
			for entry: Array in _team.lineup(use_dh):
				if entry[0] == p:
					return "★" + flags
	return flags


func _age(birth: String) -> int:
	var year := GameState.year
	var by := int(birth.substr(0, 4))
	# 4月1日時点の満年齢
	var md := birth.substr(5, 5)
	return year - by - (1 if md > "04-01" else 0)


# --- 操作 --------------------------------------------------------------------------

func _on_player_pressed(p: SimPlayer) -> void:
	if _selected == p:
		# 選んでいる札をもう一度：選手詳細（選択はそのまま）
		_open_detail(p)
		return
	if not GameState.can_edit_roster() or _selected == null:
		_selected = p
		_message = ""
		refresh()
		return
	var a := _selected
	var a_active := _team.is_active(a)
	var b_active := _team.is_active(p)
	if a_active and b_active:
		if pitchers:
			_team.swap_pitcher_roles(a, p)
			_done("%sと%sの持ち場を入れ替えました" % [a.name, p.name])
		else:
			_selected = p
			refresh()
		return
	if not a_active and not b_active:
		_selected = p
		_message = ""
		refresh()
		return
	var out := a if a_active else p
	var in_p := p if a_active else a
	var err := _team.swap_registration(out, in_p, GameState.day)
	if err.is_empty():
		_done("%sを1軍に登録し、%sを2軍に落としました" % [in_p.name, out.name])
	else:
		_fail(err)


func _on_empty_pressed(role: String) -> void:
	if not GameState.can_edit_roster() or _selected == null:
		return
	var p := _selected
	if _team.is_active(p):
		if p.is_pitcher and not role.is_empty():
			_team.move_pitcher(p, role)
			_done("%sを%sに回しました" % [p.name, ROLE_NAMES.get(role, "")])
		return
	var err := _team.promote(p, GameState.day, role if not role.is_empty() else SimTeam.ROLE_RELIEF)
	if err.is_empty():
		_done("%sを1軍に登録しました" % p.name)
	else:
		_fail(err)


func _open_detail(p: SimPlayer) -> void:
	var from: Control = get_viewport().gui_get_focus_owner()
	PlayerDetail.open(from if from != null else self, p.id, _order_ids)


func _promote_selected() -> void:
	if _selected == null:
		return
	var p := _selected
	var err := _team.promote(p, GameState.day)
	if err.is_empty():
		_done("%sを1軍に登録しました" % p.name)
	else:
		_fail(err)


func _promote_ikusei_selected() -> void:
	if _selected == null:
		return
	var p := _selected
	var err := GameState.promote_ikusei(p.id)
	if err.is_empty():
		_done("%sを支配下に登録しました（支配下 %d人）" % [p.name, GameState.league.registered_count(GameState.team)])
	else:
		_fail(err)


func _demote_selected() -> void:
	if _selected == null:
		return
	var p := _selected
	var err := _team.demote(p, GameState.day)
	if err.is_empty():
		_done("%sを2軍に落としました" % p.name)
	else:
		_fail(err)


func _done(message: String) -> void:
	_selected = null
	_message = message
	_message_error = false
	refresh()
	roster_changed.emit()


func _fail(message: String) -> void:
	_message = message
	_message_error = true
	refresh()


# --- 並び順 ------------------------------------------------------------------------

func _pitcher_before(a: SimPlayer, b: SimPlayer) -> bool:
	var sa := a.role == "先発"
	var sb := b.role == "先発"
	if sa != sb:
		return sa
	return a.overall > b.overall


func _fielder_before(a: SimPlayer, b: SimPlayer) -> bool:
	var pa := GameData.pos_index(a.primary_pos if not a.primary_pos.is_empty() else null)
	var pb := GameData.pos_index(b.primary_pos if not b.primary_pos.is_empty() else null)
	if pa != pb:
		return pa < pb
	return a.batting_value() > b.batting_value()
