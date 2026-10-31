class_name NewsView
extends VBoxContainer
## 新聞・速報の画面（ハブの右下のニュースの札・月替わりの新聞から。広げて表示。docs/AUTORUN.md 作業25）。
##
## タブ（LB/RB）：新聞（左に号の一覧、右に紙面：大見出しの記事と2段組みの記事）／速報（新しい順）／自球団の話題（新しい順）。
## 記事の下の選手名の札からⒶ／クリックで選手詳細。号はセーブに残る（GameState.news）

signal message_changed(text: String)

const TABS := [["paper", "新聞"], ["flash", "速報"], ["mine", "自球団の話題"]]
const LIST_WIDTH := 250.0
const PAPER_COLOR := Color("fbf7ec")
const INK := Color("1d1d1f")
const MASTHEAD := "オーペナ新報"
const LIST_LIMIT := 120

var _palette: UiTheme.Palette
var _tab := "paper"
var _issue_key := ""
var _tab_buttons := {}
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _paper_scroll: ScrollContainer
var _paper: VBoxContainer
var _shown := ""


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	add_child(tabs)
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 40)
		UiTheme.style_toggle(b, _palette.ink)
		var key: String = t[0]
		b.pressed.connect(func() -> void: set_tab(key))
		tabs.add_child(b)
		_tab_buttons[key] = b
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_list_scroll.add_child(_list)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := UiTheme.box(PAPER_COLOR, 6, Color("c9bfa5"), 2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", style)
	body.add_child(frame)
	_paper_scroll = ScrollContainer.new()
	_paper_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_paper_scroll.custom_minimum_size = Vector2(0, 380)
	frame.add_child(_paper_scroll)
	_paper = VBoxContainer.new()
	_paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paper.add_theme_constant_override("separation", 8)
	_paper_scroll.add_child(_paper)


## 号を指定して開く（空なら最新の号）
func open(issue_key := "") -> void:
	_tab = "paper"
	_issue_key = issue_key
	_shown = ""
	refresh()
	focus_first()


func focus_first() -> void:
	if _tab == "paper":
		for b in _list.get_children():
			if b is Button and (b as Button).button_pressed:
				UiInput.grab(b)
				return
	UiInput.grab(_tab_buttons[_tab])


func switch_tab(delta: int) -> void:
	var i := 0
	for j in TABS.size():
		if TABS[j][0] == _tab:
			i = j
	set_tab(TABS[posmod(i + delta, TABS.size())][0])
	focus_first()


func set_tab(key: String) -> void:
	_tab = key
	_shown = ""
	refresh()


func current_issue() -> String:
	return _issue_key


func refresh() -> void:
	var news: News = GameState.news
	if news == null:
		return
	if _issue_key.is_empty() and not news.issues.is_empty():
		_issue_key = news.issues[-1]["key"]
	var key := "%s|%s|%d" % [_tab, _issue_key, news.articles.size()]
	if key == _shown:
		return
	_shown = key
	for t: String in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(t == _tab)
	_clear(_list)
	_clear(_paper)
	_list_scroll.visible = _tab == "paper"
	_paper_scroll.scroll_vertical = 0
	match _tab:
		"paper":
			_build_issue_list(news)
			_build_paper(news)
			message_changed.emit("号を選ぶと紙面が変わります。選手名の札で選手詳細。LB/RB で速報・自球団の話題へ。")
		"flash":
			_build_articles(news.latest(LIST_LIMIT, "", true), "速報（新しい順）")
			message_changed.emit("記録達成・快挙・優勝争い・ポストシーズンの速報（新しい順）。")
		"mine":
			var mine: Array[Dictionary] = []
			for i in range(news.articles.size() - 1, -1, -1):
				if news.articles[i]["mine"]:
					mine.append(news.articles[i])
					if mine.size() >= LIST_LIMIT:
						break
			_build_articles(mine, "%sの話題（新しい順）" % GameData.short_name(GameState.team))
			message_changed.emit("自球団に関係する記事（新しい順）。")


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _build_issue_list(news: News) -> void:
	if news.issues.is_empty():
		_list.add_child(UiTheme.small_label("まだ新聞はありません", 15, UiTheme.TEXT_SUB, 700))
		return
	for i in range(news.issues.size() - 1, -1, -1):
		var issue: Dictionary = news.issues[i]
		var b := Button.new()
		b.text = str(issue["title"])
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(LIST_WIDTH - 14, 38)
		UiTheme.style_toggle(b, _palette.ink)
		b.set_pressed_no_signal(issue["key"] == _issue_key)
		var key: String = issue["key"]
		b.pressed.connect(func() -> void:
			_issue_key = key
			refresh()
			focus_first())
		_list.add_child(b)


func _build_paper(news: News) -> void:
	var issue := news.get_issue(_issue_key)
	if issue.is_empty():
		_paper.add_child(_masthead("", ""))
		_paper.add_child(UiTheme.small_label("月が替わると新聞が届きます。", 16, UiTheme.TEXT_SUB, 700))
		return
	_paper.add_child(_masthead(str(issue["title"]), News.date_label(str(issue["date"]))))
	var items := news.of_issue(_issue_key)
	if items.is_empty():
		return
	_paper.add_child(_article_box(items[0], true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paper.add_child(grid)
	for i in range(1, items.size()):
		var box := _article_box(items[i], false)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(box)


func _masthead(title: String, date: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = MASTHEAD
	UiTheme.heading(name_label, 30, INK, PAPER_COLOR, 2, false)
	row.add_child(name_label)
	var sub := UiTheme.small_label("　%s　%s" % [title, date], 17, Color("6b5d3f"), 800)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	UiTheme.fit_label(sub)
	row.add_child(sub)
	var box := VBoxContainer.new()
	box.add_child(row)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 3)
	box.add_child(rule)
	return box


func _articles_header(text: String) -> void:
	var label := UiTheme.small_label(text, 18, INK, 800)
	_paper.add_child(label)


func _build_articles(items: Array[Dictionary], title: String) -> void:
	_articles_header(title)
	if items.is_empty():
		_paper.add_child(UiTheme.small_label("まだ記事はありません", 15, UiTheme.TEXT_SUB, 700))
	for a in items:
		_paper.add_child(_article_box(a, false, true))


## 記事の枠：種類の札・見出し・本文・関係する選手の札
func _article_box(a: Dictionary, lead: bool, with_date := false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var kind := Label.new()
	kind.text = News.kind_name(a["kind"])
	kind.add_theme_font_override("font", UiTheme.font(800))
	kind.add_theme_font_size_override("font_size", 12)
	kind.add_theme_color_override("font_color", Color.WHITE)
	var tag := PanelContainer.new()
	var tag_style := UiTheme.box(_kind_color(a), 4)
	tag_style.content_margin_top = 1
	tag_style.content_margin_bottom = 1
	tag_style.content_margin_left = 6
	tag_style.content_margin_right = 6
	tag.add_theme_stylebox_override("panel", tag_style)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(kind)
	head.add_child(tag)
	if with_date:
		head.add_child(UiTheme.small_label("%d年 %s" % [a["year"], News.date_label(a["date"])], 13, Color("6b5d3f"), 700))
	box.add_child(head)
	var headline := Label.new()
	headline.text = a["headline"]
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.custom_minimum_size.x = 200
	headline.add_theme_font_override("font", UiTheme.font(800))
	headline.add_theme_font_size_override("font_size", 28 if lead else 18)
	headline.add_theme_color_override("font_color", Color("b71c1c") if lead else INK)
	box.add_child(headline)
	if not str(a["body"]).is_empty():
		var body := UiTheme.small_label(a["body"], 15 if lead else 14, Color("37352f"), 500)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 200
		box.add_child(body)
	var ids: Array = []
	for id: Variant in a["players"]:
		if not GameData.player(str(id)).is_empty() and str(id) not in ids:
			ids.append(str(id))
	if not ids.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		for id: String in ids:
			var b := Button.new()
			b.text = str(GameData.player(id).get("name", id))
			b.custom_minimum_size = Vector2(0, 30)
			b.add_theme_font_size_override("font_size", 14)
			UiTheme.style_button(b, Color("fff1c9"), INK, 6, 0)
			b.pressed.connect(func() -> void: PlayerDetail.open(b, id, ids))
			row.add_child(b)
		box.add_child(row)
	var rule := ColorRect.new()
	rule.color = Color("c9bfa5")
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	return box


func _kind_color(a: Dictionary) -> Color:
	if a["mine"]:
		return _palette.main.darkened(0.1) if _palette.main.get_luminance() < 0.7 else _palette.sub
	match a["kind"]:
		"milestone", "feat":
			return Color("c62828")
		"pennant", "postseason":
			return Color("b8860b")
		"divergence", "history":
			return Color("5e35b1")
		"amateur":
			return Color("2e7d32")
	return Color("455a64")
