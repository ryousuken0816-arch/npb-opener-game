extends Control
## ハブ画面（パワプロのペナント画面が参考。docs/references/README.md）。
## 左に大きなメニュー、右上に順位表、上にイベント名、下に選択中メニューの説明と日付。
## 配色は自球団のチームカラー。メニューを押すと中央〜右にその画面を開く（未実装はプレースホルダー）。
## コントローラー：十字キーで選択、Ⓐ決定、Ⓑ戻る（日程表の早送り中は中止）、LB/RB でタブ切り替え
## （ハブ・日程表は順位表のセ・パ、采配はサブ画面）。右上に操作ガイド。

## [キー, ボタン名, アイコン, ボタン色, 説明文]。先頭は可変ボタン（文言・説明は GameState から）
const MENUS := [
	["advance", "試合へ", "game", Color("e53935"), ""],
	["schedule", "日程表", "schedule", Color("e84393"),
		"自球団の日程と結果、その日の全カードの結果、セ・パの順位表を見ます。"],
	["tactics", "采配", "tactics", Color("f57c00"),
		"1・2軍の入れ替え、オーダーや起用法の設定、所属選手の確認をします。"],
	["scout", "新戦力", "scout", Color("00a396"),
		"トレード交渉（シーズン中は7月31日まで）、外国人選手の獲得（外国人市場）、移籍・引退などの出来事を見ます。「ドラフト候補」からドラフト前の作戦会議（ほしい選手に印・有識者の予想）を開きます。"],
	["records", "記録室", "records", Color("e0a400"),
		"個人成績（セイバー指標）・通算成績、チームのデプス・位置別の戦力（球団×位置の得失点）、順位の推移、表彰の歴代、達成記録、歴代メンバー・歴代ドラフト（年×球団の顔ぶれと指名）を見ます。"],
	["system", "システム", "system", Color("7e57c2"),
		"セーブ／ロード（スロット3つ＋オートセーブ）をします。（難易度・表示・サウンド・早送り速度の設定は未実装）"],
]

## 未実装画面の内容（docs/SPEC.md「UI/画面構成」）
const PLACEHOLDERS := {}

const ICON_DIR := "res://assets/icons"
## サブ画面の四辺の余白（hub.tscn の SubScreen と同じ値。采配などは広げて表示する）
const SUB_SCREEN_LEFT := 420.0
const SUB_SCREEN_TOP := 100.0
const SUB_SCREEN_RIGHT := 24.0
const SUB_SCREEN_BOTTOM := 104.0
const WIDE_LEFT := 24.0
## 采配を広げたときの上端（操作ガイドは見出しの行の「戻る」の左へ移す）
const WIDE_TOP := 20.0
## 画面いっぱいに広げて、後ろ（ハブ・下の帯・速報の帯）を一切見せない画面。ドラフトは後ろに入団先などのネタバレが
## 透けるので（作業81）、表・手帳・指名の確認・抽選・発表のどれを開いている間もこれ
const FULLSCREEN_KEYS := ["draft"]
const TITLE_SCENE := "res://scenes/title/title.tscn"
## 表の多い画面（ドラフトの候補一覧・FAの表・記録室・順位表など）は、スマホの縦向きのとき横向きをすすめる
## （iOS の Safari は向きを固定できない）
const ROTATE_HINT_KEYS := ["draft", "meeting", "fa", "records", "schedule", "awards", "comp", "contract", "release"]
## 開くときに作るサブ画面（_view）
const VIEW_KEYS := ["scout", "fa", "trade", "comp", "contract", "release", "draft", "meeting", "system", "awards", "records",
	"postseason", "news"]
## 軽量モードで、閉じたら字の画像の覚えを捨てる画面（選手の名前などいろいろな字が出る）
const TRIM_GLYPH_KEYS := ["records", "draft", "meeting", "fa", "awards", "news", "contract", "release", "trade"]
## 軽量モード：字の画像の覚えがこれを超えたら捨てる（作業75。見ている画面の字は次に描くときに作り直す）。
## 2秒ごとと、サブ画面の中身が変わったとき（message_changed）に調べる
const LITE_GLYPH_BUDGET := 16 * 1048576
const LITE_GLYPH_CHECK_SEC := 2.0

var _palette: UiTheme.Palette
var _buttons := {}
var _focused_key := "advance"
var _open_key := ""
var _guide := PadGuide.new()
## サブ画面（采配・日程表は hub.tscn）。開くときに作り（_view）、軽量モードでは閉じたら捨てる（作業75：ハブを開いたときに
## 全部作ると約34MB。ドラフト12MB・作戦会議5MB・トレード4MB など）。下の _draft_view などは _view を通す
var _views := {}
var _scout_view: ScoutView:
	get: return _view("scout")
var _fa_view: FaView:
	get: return _view("fa")
var _trade_view: TradeView:
	get: return _view("trade")
var _comp_view: CompView:
	get: return _view("comp")
var _contract_view: ContractView:
	get: return _view("contract")
var _release_view: ReleaseView:
	get: return _view("release")
var _draft_view: DraftView:
	get: return _view("draft")
var _meeting_view: DraftMeetingView:
	get: return _view("meeting")
## 作戦会議を新戦力から開いた（閉じたら新戦力のボタンへ戻る）
var _meeting_from_scout := false
var _save_view: SaveView:
	get: return _view("system")
var _awards_view: AwardsView:
	get: return _view("awards")
var _records_view: RecordsView:
	get: return _view("records")
var _postseason_view: PostseasonView:
	get: return _view("postseason")
var _news_view: NewsView:
	get: return _view("news")
var _ticker := NewsTicker.new()
## サブ画面の枠（ふつう）と、画面いっぱいのとき（角・縁・影なしで、後ろが透けない）
var _screen_style: StyleBox
var _full_style: StyleBox
## ハブの右下（順位表の下）のニュースの札。押すと新聞の画面
var _news_card: Button
var _news_lines: Array[Label] = []
## まだ開いていない新しい号（「試合へ」のあとに開く）
var _pending_issue := ""
## 大事なニュースで早送りを止めて新聞の画面を開いている（GameState.news_stop の写し。作業35）と、閉じたら戻る画面
var _stop := {}
var _stop_return := ""

## スマホ縦画面対応用コンポーネント
var _mode_button: Button
var _mobile_scroll: ScrollContainer
var _mobile_advance_button: Button
var _mobile_menu_buttons := {}
var _mobile_header_label: Label
var _mobile_team_label: Label
var _mobile_standings: StandingsPanel
## スマホ表示の下の操作の帯（戻る・日程表・采配・可変ボタン）と、表の多い画面で縦向きのときの案内
var _nav := MobileNavBar.new()
var _rotate_hint: Label

@onready var _background: TeamBackground = %Background
@onready var _event_label: Label = %EventLabel
@onready var _menu_box: VBoxContainer = %MenuBox
@onready var _emblem: TeamEmblem = %Emblem
@onready var _team_name_label: Label = %TeamNameLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _center_area: Control = %CenterArea
@onready var _standings: StandingsPanel = %Standings
@onready var _sub_screen: PanelContainer = %SubScreen
@onready var _sub_title_label: Label = %SubTitleLabel
@onready var _tactics_view: TacticsView = %TacticsView
@onready var _schedule_view: ScheduleView = %ScheduleView
@onready var _placeholder_label: Label = %PlaceholderLabel
@onready var _bottom_bar: PanelContainer = %BottomBar
@onready var _description_label: Label = %DescriptionLabel
@onready var _year_label: Label = %YearLabel
@onready var _month_label: Label = %MonthLabel


func _ready() -> void:
	if GameState.team.is_empty():
		# ハブを直接実行したときはタイトルへ戻す
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
		return
	_palette = UiTheme.team_palette(GameState.team)
	theme = UiTheme.build(_palette)
	_background.set_palette(_palette)
	_style_labels()
	_build_menu()
	_add_guide()
	UiFx.install(self)
	_standings.setup(_palette, GameData.league_of(GameState.team))
	_schedule_view.setup(_palette)
	_tactics_view.setup(_palette)
	GameState.celebrate.connect(_on_celebrate)
	add_child(_ticker)
	GameState.news_posted.connect(_ticker.push)
	GameState.issue_published.connect(_on_issue_published)
	GameState.news_stopped.connect(func() -> void: _open_news_stop(_open_key))
	_build_news_card()
	var glyph_timer := Timer.new()
	glyph_timer.wait_time = LITE_GLYPH_CHECK_SEC
	glyph_timer.autostart = true
	glyph_timer.timeout.connect(_check_glyphs)
	add_child(glyph_timer)
	_tactics_view.title_changed.connect(func(text: String) -> void: _sub_title_label.text = text)
	_tactics_view.description_changed.connect(func(text: String) -> void:
		_description_label.text = text)
	%BackButton.pressed.connect(_on_back)
	_build_mobile_dashboard()
	_make_mode_toggle_button()
	_build_mobile_nav()
	if not UiLayout.layout_changed.is_connected(_on_layout_changed):
		UiLayout.layout_changed.connect(_on_layout_changed)
	_apply_layout(UiLayout.is_portrait, UiLayout.is_mobile)
	GameState.changed.connect(_refresh)
	_refresh()
	_buttons["advance"].grab_button_focus()
	UiFx.fade_in(self)


## サブ画面（key は _open_key と同じ）。まだ作っていなければ作る
func _view(key: String) -> Control:
	var v: Control = _views.get(key)
	if v != null and is_instance_valid(v) and not v.is_queued_for_deletion():
		return v
	v = _make_view(key)
	_views[key] = v
	return v


func _make_view(key: String) -> Control:
	var v: Control
	match key:
		"scout":
			var scout := ScoutView.new()
			scout.setup(_palette)
			scout.trade_requested.connect(func() -> void: _open_sub_screen("trade"))
			scout.meeting_requested.connect(func() -> void:
				_meeting_from_scout = true
				_open_sub_screen("meeting"))
			v = scout
		"fa":
			var fa := FaView.new()
			fa.setup(_palette)
			fa.close_requested.connect(_close_sub_screen)
			v = fa
		"trade":
			var trade := TradeView.new()
			trade.setup(_palette)
			v = trade
		"comp":
			var comp := CompView.new()
			comp.setup(_palette)
			v = comp
		"contract":
			var contract := ContractView.new()
			contract.setup(_palette)
			v = contract
		"release":
			var release := ReleaseView.new()
			release.setup(_palette)
			v = release
		"draft":
			var draft := DraftView.new()
			draft.setup(_palette)
			# ドラフトのあとの「次へ」：ハブへ戻らずに次の段階（FA）へ（作業65）
			draft.advance_requested.connect(func() -> void:
				_close_sub_screen()
				_on_menu_chosen("advance"))
			v = draft
		"meeting":
			var meeting := DraftMeetingView.new()
			meeting.setup(_palette)
			meeting.draft_requested.connect(func() -> void: _on_menu_chosen("advance"))
			v = meeting
		"system":
			var save := SaveView.new()
			save.setup(_palette)
			# ロードしたらハブを作り直す（球団・年・段階が変わるので）
			save.loaded.connect(func() -> void: get_tree().reload_current_scene.call_deferred())
			v = save
		"awards":
			var awards := AwardsView.new()
			awards.setup(_palette)
			v = awards
		"records":
			var records := RecordsView.new()
			records.setup(_palette)
			v = records
		"postseason":
			var postseason := PostseasonView.new()
			postseason.setup(_palette)
			postseason.advance_requested.connect(func() -> void: _on_menu_chosen("advance"))
			v = postseason
		"news":
			var news := NewsView.new()
			news.setup(_palette)
			news.stop_chosen.connect(_on_stop_chosen)
			v = news
	# 案内は下の帯へ（その画面を開いているときだけ）
	if v.has_signal("message_changed"):
		v.connect("message_changed", func(text: String) -> void:
			_check_glyphs()
			if _open_key == key:
				_description_label.text = text)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.visible = false
	_placeholder_label.get_parent().add_child(v)
	return v


## 軽量モード：字の画像の覚えが LITE_GLYPH_BUDGET を超えていたら捨てる
func _check_glyphs() -> void:
	if LiteMode.on() and UiTheme.glyph_bytes() > LITE_GLYPH_BUDGET:
		UiTheme.trim_glyphs()


## 軽量モード：開いている画面（keep）のほかのサブ画面を捨てる（作業75）
func _drop_views(keep: String) -> void:
	if not LiteMode.on():
		return
	for key: String in _views.keys():
		if key == keep:
			continue
		var v: Control = _views[key]
		_views.erase(key)
		if is_instance_valid(v):
			v.visible = false
			v.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# デバッグ用：F9 でシーズンを自動で消化してその年のオフのドラフトの段階へ（サブ画面を開いていないとき）
	if event is InputEventKey and event.pressed and not event.echo 			and (event as InputEventKey).keycode == KEY_F9 and _open_key.is_empty():
		GameState.skip_to_phase(GameState.Phase.DRAFT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not _open_key.is_empty():
		_on_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(UiInput.TAB_PREV) or event.is_action_pressed(UiInput.TAB_NEXT):
		var delta := -1 if event.is_action_pressed(UiInput.TAB_PREV) else 1
		match _open_key:
			"":
				_standings.turn(delta)
			"schedule":
				_schedule_view.switch_tab(delta)
			"tactics":
				_tactics_view.switch_tab(delta)
			"scout":
				_scout_view.switch_tab(delta)
			"fa":
				_fa_view.switch_tab(delta)
			"trade":
				_trade_view.switch_tab(delta)
			"comp":
				_comp_view.switch_tab(delta)
			"contract":
				_contract_view.switch_tab(delta)
			"release":
				_release_view.switch_tab(delta)
			"draft":
				_draft_view.switch_tab(delta)
			"meeting":
				_meeting_view.switch_tab(delta)
			"system":
				_save_view.switch_tab(delta)
			"awards":
				_awards_view.switch_tab(delta)
			"records":
				_records_view.switch_tab(delta)
			"news":
				_news_view.switch_tab(delta)
		get_viewport().set_input_as_handled()


## 右上の操作ガイド（Ⓐ決定 Ⓑ戻る LB/RB切替）
func _add_guide() -> void:
	add_child(_guide)
	_guide.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_guide.position = Vector2(size.x - _guide.size.x - 24, 5)
	_guide.resized.connect(_place_guide)
	resized.connect(_place_guide)
	_place_guide()


func _place_guide() -> void:
	if _guide.get_parent() == self:
		_guide.position = Vector2(size.x - _guide.size.x - 24, 5)


## 采配を広げたときは右上の操作ガイドが画面の枠に重なるので、見出しの行（「戻る」の左）へ移す
func _move_guide(into_header: bool) -> void:
	var header: Node = %BackButton.get_parent()
	var target: Node = header if into_header else self
	if _guide.get_parent() == target:
		return
	_guide.get_parent().remove_child(_guide)
	target.add_child(_guide)
	if into_header:
		header.move_child(_guide, %BackButton.get_index())
		_guide.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		_guide.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_guide.size = _guide.custom_minimum_size
		_place_guide()


func _style_labels() -> void:
	var p := _palette
	_event_label.label_settings = _label_settings(64, p.ink, 12, Color.WHITE, Color(p.ink, 0.35))
	_team_name_label.label_settings = _label_settings(34, p.ink, 8, Color.WHITE)
	_summary_label.label_settings = _label_settings(20, UiTheme.TEXT, 6, Color.WHITE)
	_year_label.label_settings = _label_settings(32, p.ink, 8, Color.WHITE, Color.TRANSPARENT, 800)
	_month_label.label_settings = _label_settings(44, p.ink, 10, Color.WHITE, Color(p.ink, 0.3))
	_sub_title_label.label_settings = _label_settings(28, p.ink, 7, Color.WHITE)
	UiTheme.fit_label(_sub_title_label)
	_description_label.add_theme_font_size_override("font_size", 21)
	_description_label.add_theme_font_override("font", UiTheme.font(700))

	# 下の帯：白地（ごく薄い縦グラデーション）に球団カラーの上線
	var bar := UiTheme.card(_palette.main, 0, 0, 0.92)
	bar.border_width_top = 5
	bar.shadow_offset = Vector2(0, -2)
	bar.content_margin_left = 32
	bar.content_margin_right = 32
	bar.content_margin_top = 4
	bar.content_margin_bottom = 4
	_bottom_bar.add_theme_stylebox_override("panel", bar)

	var screen := UiTheme.card(_palette.main, 12, 3, 0.97)
	screen.content_margin_left = 16
	screen.content_margin_right = 16
	screen.content_margin_top = 12
	screen.content_margin_bottom = 16
	_sub_screen.add_theme_stylebox_override("panel", screen)
	_screen_style = screen
	var full := UiTheme.card(_palette.main, 0, 0, 1.0)
	full.shadow_size = 0
	full.set_content_margin_all(0)
	_full_style = full
	# サブ画面の中身が枠より大きくなっても、パネルを画面の外へ広げずにスクロールさせる（余白は包みの内側へ）
	UiTheme.fit_scroll(%Fit, %VBox, screen)


func _label_settings(font_size: int, color: Color, outline: int, outline_color: Color,
		shadow := Color.TRANSPARENT, weight := 800) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = UiTheme.font(weight)
	s.font_size = font_size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = outline_color
	# 軽い影（縁取りの外側に落とす）。shadow を指定したときはその色で大きめに
	s.shadow_color = shadow if shadow.a > 0.0 else Color(0, 0, 0, 0.2)
	s.shadow_size = maxi(outline, 2)
	s.shadow_offset = Vector2(3, 4) if shadow.a > 0.0 else Vector2(1, 3)
	return s


func _build_menu() -> void:
	for menu: Array in MENUS:
		var button := HubMenuButton.new()
		var icon: Texture2D = load(ICON_DIR.path_join(menu[2] + ".svg"))
		button.setup(menu[0], menu[1], icon, menu[3], _palette.ink)
		button.focused.connect(_on_menu_focused)
		button.chosen.connect(_on_menu_chosen)
		_menu_box.add_child(button)
		_buttons[menu[0]] = button


func _refresh() -> void:
	_event_label.text = GameState.event_text()
	# 長いフェーズ名（FA・トレード・ポスティング 等）は枠に収まるよう縮める
	var fit_size := int(_event_label.size.x / _event_label.text.length())
	_event_label.label_settings.font_size = clampi(fit_size, 32, 64)
	UiFx.set_text_bump(_year_label, GameState.year_text())
	UiFx.set_text_bump(_month_label, GameState.month_text(), 1.2)
	_buttons["advance"].set_text(GameState.button_text())
	_emblem.setup(_palette, GameData.short_name(GameState.team))
	_team_name_label.text = GameState.team
	UiFx.set_text_bump(_summary_label, _summary_text(), 1.06)
	_standings.refresh()
	if _open_key not in ["tactics", "fa", "trade", "comp", "contract", "release", "draft", "system", "awards", "records",
			"postseason", "news", "meeting"]:
		_description_label.text = _description(_focused_key)
	if _open_key == "tactics":
		_tactics_view.refresh()
	elif _open_key == "schedule":
		_schedule_view.refresh()
	elif _open_key == "scout":
		_scout_view.refresh()
	elif _open_key == "fa":
		_fa_view.refresh()
	elif _open_key == "trade":
		_trade_view.refresh()
	elif _open_key == "comp":
		_comp_view.refresh()
	elif _open_key == "contract":
		_contract_view.refresh()
	elif _open_key == "release":
		_release_view.refresh()
	elif _open_key == "draft":
		_draft_view.refresh()
	elif _open_key == "meeting":
		_meeting_view.refresh()
	elif _open_key == "system":
		_save_view.refresh()
	elif _open_key == "awards":
		_awards_view.refresh()
	elif _open_key == "postseason":
		_postseason_view.refresh()
	elif _open_key == "news":
		_news_view.refresh()
	_refresh_news_card()
	_refresh_mobile_dashboard()


func _summary_text() -> String:
	var league := GameData.league_of(GameState.team)
	var rank := 0
	for row: Dictionary in GameState.standings(league):
		if row["team"] == GameState.team:
			rank = row["rank"]
	var pct := GameState.win_pct({"wins": GameState.wins, "losses": GameState.losses})
	return "%s %d位　%s　勝率 %s" % [
		GameData.LEAGUE_NAMES.get(league, ""), rank, GameState.record_text(),
		("%.3f" % pct).trim_prefix("0")]


func _description(key: String) -> String:
	if key == "advance":
		if GameState.phase == GameState.Phase.SEASON:
			var last_month := GameState.month == GameState.season_months()[-1]
			var goal := "シーズン終了まで進みます" if last_month else "次の月へ進みます"
			if GameState.season == null:
				return "%s。（%d年の日程データがないため試合は行いません）" % [goal, GameState.year]
			return "%d月の残り%d試合（全球団）をまとめて行い、%s。日程表からは1日ずつ進められます。" % [
				GameState.month, GameState.games_left_in_month(), goal]
		if GameState.phase == GameState.Phase.POSTSEASON:
			if GameState.postseason_done():
				return "日本一が決まりました。シーズン終了・表彰へ進みます。"
			return "クライマックスシリーズ・日本シリーズの組み合わせと結果を開きます。1試合ずつ・段階ごとに進められます。"
		if GameState.phase == GameState.Phase.AWARDS and GameState.awards_pending:
			return "%d年のシーズン表彰（MVP・新人王・ベストナイン・ゴールデングラブ・タイトル・沢村賞）を発表します。" % GameState.year
		if GameState.fa_open():
			return "FA宣言した選手への提示と、メジャーへ移籍する自球団の選手の引き留めをします。"
		if GameState.comp_open():
			return "FA移籍の補償：自球団のプロテクト、または相手のプロテクト外から人的補償の選手（か金銭）を選びます。"
		if GameState.contract_open():
			return "自球団の選手の来季の年俸を確認・調整します。12球団の年俸総額と予算上限も見られます。"
		if GameState.release_open():
			return "支配下の上限（70人）に合わせて自球団の戦力外を選びます。史実の引退と他球団の戦力外も見られます。"
		if GameState.draft_open() and GameState.draft().stage == Draft.Stage.DONE \
				and not GameState.draft().pending_talks().is_empty():
			return "ドラフト会議のあと：" + DraftView.talk_notice(GameState.draft(), GameState.draft().pending_talks()) + "。"
		if GameState.draft_open():
			return "ドラフト会議：史実のドラフト指名選手から、1位入札（重複は抽選）・2位以降のウェーバー・育成の指名をします。"
		return "オフシーズンを進めます。次は「%s」です。" % GameState.PHASE_NAMES[GameState.next_phase()]
	for menu: Array in MENUS:
		if menu[0] == key:
			return menu[4]
	return ""


func _on_menu_focused(key: String) -> void:
	_focused_key = key
	_description_label.text = _description(key)


func _on_menu_chosen(key: String) -> void:
	if key == "schedule" and GameState.phase == GameState.Phase.POSTSEASON:
		_open_sub_screen("postseason")
		return
	if key == "advance":
		# ポストシーズンは日本一が決まるまで、可変ボタンでポストシーズンの画面を開く
		if GameState.phase == GameState.Phase.POSTSEASON and not GameState.postseason_done():
			_open_sub_screen("postseason")
			return
		# シーズン終了・表彰の段階は、まず表彰の画面を開く（2回目からは次の段階へ）
		if GameState.phase == GameState.Phase.AWARDS and GameState.awards_pending:
			GameState.awards_pending = false
			_open_sub_screen("awards")
			return
		# FA・トレード・ポスティングの段階は、締め切るまで可変ボタンで FA の画面を開く
		if GameState.fa_open():
			_open_sub_screen("fa")
			return
		if GameState.comp_open():
			_open_sub_screen("comp")
			return
		if GameState.contract_open():
			_open_sub_screen("contract")
			return
		if GameState.release_open():
			_open_sub_screen("release")
			return
		if GameState.draft_open():
			_open_sub_screen("draft")
			if GameState.draft_talk_pending():
				_draft_view.show_talk()  # 説得の待ち：手帳の説得のページを開く（作業65）
			return
		# 戦力外・引退を締めたら、ドラフトの段階へ進む前に作戦会議（その年に一度。作業37）
		if GameState.draft_meeting_due():
			GameState.draft_board.hold(GameState.year)
			_meeting_from_scout = false
			_open_sub_screen("meeting")
			return
		_pending_issue = ""
		# 押したらすぐ進める（1フレーム待つと、押した直後に開くはずの画面が遅れる。248e36d の前の動きに戻した）
		GameState.advance()
		_after_advance()
		return
	_open_sub_screen(key)


## 可変ボタンで進めたあと：大事なニュースで途中で止めたところ（作業35）、次の段階の画面、新しい号のどれかを開く
func _after_advance() -> void:
	var stop := GameState.news_stop
	if int(stop.get("resume_to", -1)) >= 0:
		_open_news_stop("")
	elif GameState.phase == GameState.Phase.POSTSEASON:
		_open_sub_screen("postseason")
	elif GameState.phase == GameState.Phase.AWARDS and GameState.awards_pending:
		GameState.awards_pending = false
		_open_sub_screen("awards")
	elif GameState.fa_open():
		_open_sub_screen("fa")
	elif GameState.contract_open():
		_open_sub_screen("contract")
	elif GameState.release_open():
		_open_sub_screen("release")
	elif GameState.draft_open():
		_open_sub_screen("draft")
	elif not _pending_issue.is_empty():
		open_news(_pending_issue)
	elif not stop.is_empty():
		_open_news_stop("")


## 大事なニュースで早送りを止めた（GameState.news_stop）：その号（速報だけなら速報のタブ）を開いて、
## 帯で「続ける」「ここで止める」を選ばせる。return_key は閉じたら戻る画面（日程表・ポストシーズン。空ならハブ）
func _open_news_stop(return_key: String) -> void:
	if GameState.news_stop.is_empty():
		return
	_stop = GameState.news_stop.duplicate(true)
	_stop_return = return_key if return_key != "news" else _stop_return
	_pending_issue = ""
	for r: Dictionary in _stop["reasons"]:
		if not str(r["issue"]).is_empty():
			_pending_issue = r["issue"]
			break
	_open_sub_screen("news")
	_news_view.show_stop(_stop)


## 止めたあとの「続ける」（resume）／「ここで止める」：元の画面へ戻り、続けるなら早送りの続き
func _on_stop_chosen(resume: bool) -> void:
	var mode := str(_stop.get("mode", ""))
	var back := _stop_return
	_stop = {}
	_stop_return = ""
	if back.is_empty():
		_close_sub_screen()
	else:
		_open_sub_screen(back)
	if not resume:
		GameState.news_stop = {}
		return
	_pending_issue = ""
	GameState.resume_news_stop()
	if mode == "hub":
		_after_advance()


func _open_sub_screen(key: String) -> void:
	_open_key = key
	UiLayout.set_sub_screen_active(true)
	_sub_screen.visible = true
	_center_area.visible = false
	_standings.visible = false
	_news_card.visible = false
	if UiLayout.is_mobile:
		# スマホ：戻るは下の帯の大きなボタン。表の多い画面は縦向きのとき横向きをすすめる
		if _mobile_scroll != null:
			_mobile_scroll.visible = false
		_bottom_bar.visible = false
		_guide.visible = false
	_update_rotate_hint()
	UiLayout.refit()
	for menu: Array in MENUS:
		if menu[0] == key:
			_sub_title_label.text = menu[1]
	var is_tactics := key == "tactics"
	var is_schedule := key == "schedule"
	var is_scout := key == "scout"
	var is_fa := key == "fa"
	var is_trade := key == "trade"
	var is_comp := key == "comp"
	var is_contract := key == "contract"
	var is_release := key == "release"
	var is_draft := key == "draft"
	var is_meeting := key == "meeting"
	var is_system := key == "system"
	var is_awards := key == "awards"
	var is_records := key == "records"
	var is_postseason := key == "postseason"
	var is_news := key == "news"
	_drop_views(key)
	for k: String in _views:
		_views[k].visible = k == key
	var has_view := key in VIEW_KEYS
	if has_view:
		_view(key).visible = true
	_tactics_view.visible = is_tactics
	_schedule_view.visible = is_schedule
	_placeholder_label.visible = not is_tactics and not is_schedule and not has_view
	# 采配は画面いっぱいに広げる（パワプロの采配画面のように、ハブのメニューを隠す）
	_set_wide(is_tactics or is_fa or is_trade or is_comp or is_contract or is_release or is_draft or is_meeting or is_awards or is_records or is_postseason or is_news,
		key in FULLSCREEN_KEYS)
	UiFx.slide_in(_sub_screen)
	if is_tactics:
		_tactics_view.open()
	elif is_schedule:
		_sub_title_label.text = "日程表"
		_schedule_view.refresh()
		_schedule_view.focus_default()
	elif is_scout:
		_scout_view.refresh()
		_scout_view.focus_first()
	elif is_fa:
		_sub_title_label.text = "FA・ポスティング（%d年オフ）" % GameState.year
		_fa_view.open()
	elif is_trade:
		_sub_title_label.text = "新戦力：トレード交渉"
		_trade_view.open()
	elif is_comp:
		_sub_title_label.text = "FAの補償（%d年オフ）" % GameState.year
		_comp_view.open()
	elif is_contract:
		_sub_title_label.text = "契約更改（%d年オフ）" % GameState.year
		_contract_view.open()
	elif is_release:
		_sub_title_label.text = "戦力外・引退（%d年オフ）" % GameState.year
		_release_view.open()
	elif is_draft:
		_sub_title_label.text = "ドラフト会議（%d年）" % GameState.year
		_draft_view.open()
	elif is_meeting:
		_sub_title_label.text = "ドラフト作戦会議（%d年）" % GameState.year
		_meeting_view.open()
	elif is_system:
		_sub_title_label.text = "システム：セーブ／ロード"
		_save_view.open()
	elif is_awards:
		_sub_title_label.text = "シーズン表彰（%d年）" % GameState.year
		_awards_view.open()
	elif is_records:
		_sub_title_label.text = "記録室"
		_records_view.open()
	elif is_postseason:
		_sub_title_label.text = "クライマックスシリーズ・日本シリーズ（%d年）" % GameState.year
		_postseason_view.open()
	elif is_news:
		_sub_title_label.text = "新聞・速報"
		_news_view.open(_pending_issue)
		_pending_issue = ""
	else:
		_placeholder_label.text = PLACEHOLDERS.get(key, "") + "\n\n（未実装）"
		%BackButton.grab_focus()


## 采配のサブ画面を開いているときは、戻るで采配メニューの一覧へ戻る。日程表の早送り中は中止だけ
func _on_back() -> void:
	if _open_key in ["schedule", "postseason"] and GameState.is_fast_forwarding():
		GameState.stop_fast_forward()
		return
	if _open_key == "news" and not _stop.is_empty():
		if not _news_view.stop_back():
			_on_stop_chosen(false)
		return
	if _open_key == "tactics" and _tactics_view.back():
		return
	if _open_key == "fa" and _fa_view.back():
		return
	if _open_key == "contract" and _contract_view.back():
		return
	if _open_key == "release" and _release_view.back():
		return
	if _open_key == "draft" and _draft_view.back():
		return
	if _open_key == "system" and _save_view.back():
		return
	_close_sub_screen()


## サブ画面の配置。切り替えの演出を止めてから四辺の余白をすべて置き直す
## （演出の途中の位置が余白に残ると、開く・閉じるのたびに右へずれて画面の外へはみ出していった。作業11）
func _set_wide(wide: bool, full := false) -> void:
	UiFx.stop_slide(_sub_screen)
	_sub_screen.add_theme_stylebox_override("panel", _full_style if full else _screen_style)
	_ticker.visible = not full  # 速報の帯も後ろに出さない（ドラフトの最中は入団先などが載る）
	if UiLayout.is_mobile:
		# スマホ：どの画面も広げる（縦は画面いっぱい、横はパソコンの広げた配置）。下は操作の帯の分を空ける
		var side := 6.0 if UiLayout.is_portrait else WIDE_LEFT
		var top := 4.0 if UiLayout.is_portrait else 8.0
		var bottom := 4.0
		if full:
			side = 0.0
			top = 0.0
			bottom = 0.0
		_sub_screen.offset_left = side
		_sub_screen.offset_top = UiLayout.safe_area_top + top
		_sub_screen.offset_right = -side
		_sub_screen.offset_bottom = -UiLayout.bottom_inset() - bottom
		_set_fit_side_margin(8.0 if UiLayout.is_portrait else 16.0)
		_menu_box.visible = not UiLayout.is_portrait and _open_key.is_empty()
		_event_label.visible = _menu_box.visible
		_guide.visible = false
	else:
		_sub_screen.offset_left = 0.0 if full else (WIDE_LEFT if wide else SUB_SCREEN_LEFT)
		_sub_screen.offset_top = 0.0 if full else (WIDE_TOP if wide else SUB_SCREEN_TOP)
		_sub_screen.offset_right = 0.0 if full else -SUB_SCREEN_RIGHT
		_sub_screen.offset_bottom = 0.0 if full else -SUB_SCREEN_BOTTOM
		_set_fit_side_margin(16.0)
		_menu_box.visible = not wide
		_event_label.visible = not wide
		if full:
			_bottom_bar.visible = false  # 下の帯の説明文は、ドラフトでは画面の中の1行に出す
		_guide.visible = true
		_move_guide(wide)


## サブ画面の内側の左右の余白（スマホの縦は狭くして、名前札を3列並べられるように）
func _set_fit_side_margin(margin: float) -> void:
	var style: StyleBox = %Fit.get_theme_stylebox("panel")
	if style != null and not is_equal_approx(style.content_margin_left, margin):
		style.content_margin_left = margin
		style.content_margin_right = margin


func _close_sub_screen() -> void:
	# 早送りは日程表を開いている間だけ（閉じたら止める）
	GameState.stop_fast_forward()
	_stop = {}
	_set_wide(false, false)
	var key := _open_key
	_open_key = ""
	if key == "records":
		RecordsHistory.clear_caches()  # 歴代メンバー・歴代ドラフトで見た年のデータ（作業55）
	_drop_views("")
	if LiteMode.on() and key in TRIM_GLYPH_KEYS:
		UiTheme.trim_glyphs()  # 字の多い画面で覚えた字の画像（作業75）
	UiLayout.set_sub_screen_active(false)
	_sub_screen.visible = false
	_update_rotate_hint()
	if UiLayout.is_portrait:
		if _mobile_scroll != null:
			_mobile_scroll.visible = true
		_center_area.visible = false
		_standings.visible = false
		_news_card.visible = false
		_bottom_bar.visible = false
		_guide.visible = false
	else:
		_center_area.visible = true
		_standings.visible = true
		_news_card.visible = true
		_bottom_bar.visible = not UiLayout.is_mobile
		_guide.visible = not UiLayout.is_mobile
		_menu_box.visible = true
		_event_label.visible = true
		if not key.is_empty():
			UiFx.fade_in(_center_area)
			UiFx.fade_in(_standings)
	_description_label.text = _description(_focused_key)
	if _buttons.has(key):
		_buttons[key].grab_button_focus()
	elif key == "trade" or key == "meeting" and _meeting_from_scout:
		_buttons["scout"].grab_button_focus()
	elif key in ["fa", "comp", "contract", "release", "draft", "awards", "postseason", "meeting"]:
		_buttons["advance"].grab_button_focus()
	elif key == "news":
		_news_card.grab_focus()


## 新聞の画面を開く（号のキーが空なら最新の号）
func open_news(issue_key := "") -> void:
	_pending_issue = issue_key
	_open_sub_screen("news")


## 新しい号が出た：早送り中・ほかの画面を開いているときは帯で知らせ、ハブの「試合へ」のあとなら開く
func _on_issue_published(key: String) -> void:
	_pending_issue = key
	var issue := GameState.news.get_issue(key)
	_ticker.push({"headline": "%sが届きました（ハブの右下のニュースから読めます）" % issue.get("title", "新聞"),
		"mine": false})


## 順位表の下のニュースの札（最新の見出し3本）
func _build_news_card() -> void:
	_news_card = Button.new()
	_news_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_news_card.offset_left = -330
	_news_card.offset_right = -24
	_news_card.offset_top = 404
	_news_card.offset_bottom = 612
	_news_card.focus_mode = Control.FOCUS_ALL
	_news_card.set_meta("no_fx", true)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		_news_card.add_theme_stylebox_override(state, UiTheme.card(_palette.main, 12, 2))
	var focus := UiTheme.card(UiTheme.FOCUS, 12, 4)
	_news_card.add_theme_stylebox_override("focus", focus)
	add_child(_news_card)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 8
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news_card.add_child(box)
	var title := Label.new()
	title.text = "ニュース"
	UiTheme.heading(title, 22, _palette.ink, Color.WHITE, 6)
	box.add_child(title)
	for i in 3:
		var label := UiTheme.small_label("", 15, UiTheme.TEXT, 700)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.custom_minimum_size = Vector2(270, 0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
		_news_lines.append(label)
	_news_card.pressed.connect(func() -> void: open_news())
	_news_card.focus_entered.connect(func() -> void:
		_description_label.text = "新聞（月ごとの号・日本シリーズ号など）と速報を読みます。")
	_refresh_news_card()


func _refresh_news_card() -> void:
	if _news_card == null:
		return
	_news_card.visible = _open_key.is_empty() and not UiLayout.is_portrait
	var items: Array[Dictionary] = GameState.news.latest(3) if GameState.news != null else []
	for i in _news_lines.size():
		var label := _news_lines[i]
		if i < items.size():
			var a: Dictionary = items[i]
			label.text = "%s %s" % [News.date_label(a["date"]), a["headline"]]
			label.add_theme_color_override("font_color", Color("c62828") if a["flash"] else UiTheme.TEXT)
		else:
			label.text = "（まだニュースはありません）" if i == 0 else ""


## 優勝・日本一の演出（自球団のリーグ優勝と、日本一はどの球団でも）を重ねる。閉じたら元のフォーカスへ
func _on_celebrate(kind: String, team_name: String, title: String) -> void:
	# 前の演出が残っていれば閉じる（リーグ優勝と日本一が続けて来たときに重ならないように）
	for c in get_children():
		if c is Celebration:
			c.close()
	var owner_focus := get_viewport().gui_get_focus_owner()
	var fx := Celebration.new()
	var text := title
	if kind == "champion" and team_name != GameState.team:
		text = "%d年 日本一" % GameState.year
	fx.setup(team_name, text)
	fx.closed.connect(func() -> void:
		if is_instance_valid(owner_focus) and owner_focus.is_visible_in_tree():
			owner_focus.grab_focus())
	add_child(fx)


# --- スマホ縦画面レイアウト -------------------------------------------------------------

## スマホで「PC表示」にしているときだけ右上に出す、スマホ表示へ戻すボタン（スマホ表示では下の帯の「PC表示」）
func _make_mode_toggle_button() -> void:
	_mode_button = Button.new()
	_mode_button.custom_minimum_size = Vector2(150, 44)
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.text = "📱 スマホ表示"
	UiTheme.style_button(_mode_button, Color("455a64"), Color.WHITE, 6, 2)
	_mode_button.pressed.connect(func() -> void:
		UiLayout.toggle_mode())
	add_child(_mode_button)
	_update_mode_button_position()
	resized.connect(_update_mode_button_position)


func _update_mode_button_position() -> void:
	if _mode_button != null and is_instance_valid(_mode_button):
		_mode_button.visible = not UiLayout.is_mobile and UiLayout.on_phone()
		_mode_button.reset_size()
		_mode_button.position = Vector2(size.x - _mode_button.size.x - 12, 50)


func _build_mobile_nav() -> void:
	_nav.setup(_palette, _description_label,
		func() -> bool: return not _open_key.is_empty() or PlayerDetail.current() != null,
		GameState.button_text)
	add_child(_nav)
	_nav.chosen.connect(_on_nav)
	_rotate_hint = UiTheme.small_label("📱 横向きにすると見やすくなります", 15, Color("8a5a00"), 700)
	_rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rotate_hint.set_meta("rotate_hint", true)
	_rotate_hint.visible = false
	var header: Node = %BackButton.get_parent()
	header.get_parent().add_child(_rotate_hint)
	header.get_parent().move_child(_rotate_hint, header.get_index() + 1)


func _update_rotate_hint() -> void:
	if _rotate_hint != null:
		_rotate_hint.visible = UiLayout.is_portrait and _open_key in ROTATE_HINT_KEYS
	%BackButton.visible = not UiLayout.is_mobile


## スマホの下の帯のボタン
func _on_nav(key: String) -> void:
	if key == "mode":
		UiLayout.toggle_mode()
		return
	var detail := PlayerDetail.current()
	if key == "back":
		if detail != null:
			detail.close()
		elif not _open_key.is_empty():
			_on_back()
		return
	if detail != null:
		detail.close()
	if key == "advance":
		if not _open_key.is_empty():
			_close_sub_screen()
		_on_menu_chosen("advance")
		return
	if _open_key == key:
		if key == "tactics":
			_tactics_view.open()
		return
	if not _open_key.is_empty():
		_close_sub_screen()
	_open_sub_screen(key)


func _on_layout_changed(is_portrait: bool, is_mobile: bool) -> void:
	_update_mode_button_position()
	_apply_layout(is_portrait, is_mobile)
	_refresh()


func _apply_layout(is_portrait: bool, is_mobile: bool) -> void:
	UiLayout.set_sub_screen_active(not _open_key.is_empty())
	_update_rotate_hint()
	if _mobile_scroll != null:
		_mobile_scroll.visible = is_portrait and _open_key.is_empty()
		_mobile_scroll.offset_top = UiLayout.safe_area_top + 6.0
		_mobile_scroll.offset_bottom = -UiLayout.bottom_inset() - 4.0
	var top := _open_key.is_empty()
	_menu_box.visible = top and not is_portrait
	_center_area.visible = top and not is_portrait
	_standings.visible = top and not is_portrait
	_news_card.visible = top and not is_portrait
	_event_label.visible = top and not is_portrait
	_bottom_bar.visible = not is_mobile and (top or not is_portrait)
	_guide.visible = not is_mobile
	# スマホの横：パソコンと同じ配置のまま、下の帯の分だけ下端を上げる（ニュースの札・中央の球団の札）
	var bottom := UiLayout.bottom_inset() + 8.0
	_news_card.offset_bottom = minf(612.0, get_viewport_rect().size.y - bottom) if is_mobile else 612.0
	_center_area.offset_bottom = -bottom if is_mobile else -110.0
	_menu_box.offset_top = 12.0 if is_mobile else 40.0
	_menu_box.offset_bottom = minf(600.0, get_viewport_rect().size.y - bottom) if is_mobile else 600.0
	_sub_screen.visible = not top
	if not top:
		var wide := _open_key in ["tactics", "fa", "trade", "comp", "contract", "release", "draft", "meeting", "awards", "records", "postseason", "news"]
		_set_wide(wide, _open_key in FULLSCREEN_KEYS)


func _build_mobile_dashboard() -> void:
	_mobile_scroll = ScrollContainer.new()
	_mobile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mobile_scroll.set_meta("fit_guard", true)
	_mobile_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mobile_scroll.visible = false
	add_child(_mobile_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 24)
	_mobile_scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# 1. ヘッダーカード
	var header_panel := PanelContainer.new()
	var h_style := UiTheme.card(_palette.main, 12, 3, 0.96)
	h_style.set_content_margin_all(12)
	header_panel.add_theme_stylebox_override("panel", h_style)
	var hvbox := VBoxContainer.new()
	hvbox.add_theme_constant_override("separation", 6)
	header_panel.add_child(hvbox)

	_mobile_header_label = Label.new()
	_mobile_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_mobile_header_label, 25, _palette.ink, Color.WHITE, 6)
	hvbox.add_child(_mobile_header_label)

	_mobile_team_label = Label.new()
	_mobile_team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_mobile_team_label, 19, UiTheme.TEXT, Color.WHITE, 5, false)
	hvbox.add_child(_mobile_team_label)
	vbox.add_child(header_panel)

	# 2. メインアクション巨大ボタン（「試合へ」等）
	_mobile_advance_button = Button.new()
	_mobile_advance_button.custom_minimum_size = Vector2(0, 68)
	_mobile_advance_button.add_theme_font_size_override("font_size", 26)
	_mobile_advance_button.add_theme_font_override("font", UiTheme.font(800))
	UiTheme.style_button(_mobile_advance_button, Color("e53935"), Color.WHITE, 12, 4)
	_mobile_advance_button.pressed.connect(func() -> void: _on_menu_chosen("advance"))
	vbox.add_child(_mobile_advance_button)

	# 3. メニューグリッド（采配・日程表・新戦力・記録室・システム）
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	for menu: Array in MENUS:
		var key: String = menu[0]
		if key == "advance":
			continue
		var btn := Button.new()
		btn.text = menu[1]
		btn.custom_minimum_size = Vector2(0, 60)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 21)
		btn.add_theme_font_override("font", UiTheme.font(800))
		var color: Color = menu[3]
		UiTheme.style_button(btn, color, Color.WHITE, 10, 3)
		var icon: Texture2D = load(ICON_DIR.path_join(menu[2] + ".svg"))
		if icon != null:
			btn.icon = icon
			btn.expand_icon = true
		btn.pressed.connect(func() -> void: _on_menu_chosen(key))
		grid.add_child(btn)
		_mobile_menu_buttons[key] = btn

	# 4. 最新ニュースカード
	var news_btn := Button.new()
	news_btn.custom_minimum_size = Vector2(0, 56)
	news_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(news_btn, Color.WHITE, _palette.ink, 10, 2)
	news_btn.text = "📰 最新ニュース・速報を見る"
	news_btn.add_theme_font_size_override("font_size", 20)
	news_btn.add_theme_font_override("font", UiTheme.font(700))
	news_btn.pressed.connect(func() -> void: open_news())
	vbox.add_child(news_btn)

	# 5. モバイル順位表カード（ホーム画面の下部にそのまま表示）
	_mobile_standings = StandingsPanel.new()
	_mobile_standings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st_card := UiTheme.card(_palette.main, 12, 2, 0.96)
	st_card.set_content_margin_all(10)
	_mobile_standings.add_theme_stylebox_override("panel", st_card)
	vbox.add_child(_mobile_standings)
	_mobile_standings.setup(_palette, GameData.league_of(GameState.team))


func _refresh_mobile_dashboard() -> void:
	if _mobile_advance_button != null and is_instance_valid(_mobile_advance_button):
		_mobile_advance_button.text = "▶ %s" % GameState.button_text()
	if _mobile_header_label != null and is_instance_valid(_mobile_header_label):
		_mobile_header_label.text = "%s年 %s　%s" % [GameState.year_text(), GameState.month_text(), GameState.event_text()]
	if _mobile_team_label != null and is_instance_valid(_mobile_team_label):
		_mobile_team_label.text = "%s （%s）" % [GameState.team, _summary_text()]
	if _mobile_standings != null and is_instance_valid(_mobile_standings):
		_mobile_standings.refresh()
