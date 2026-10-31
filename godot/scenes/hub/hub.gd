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
		"トレード交渉（シーズン中は7月31日まで）、外国人選手の獲得（外国人市場）、移籍・引退などの出来事を見ます。（スカウティングは未実装）"],
	["records", "記録室", "records", Color("e0a400"),
		"個人成績（セイバー指標）・通算成績、チームのデプス・守備位置ランク、チーム成績の推移、表彰の歴代、ドラフト・達成記録を見ます。"],
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
const TITLE_SCENE := "res://scenes/title/title.tscn"

var _palette: UiTheme.Palette
var _buttons := {}
var _focused_key := "advance"
var _open_key := ""
var _guide := PadGuide.new()
var _scout_view := ScoutView.new()
var _fa_view := FaView.new()
var _trade_view := TradeView.new()
var _comp_view := CompView.new()
var _contract_view := ContractView.new()
var _release_view := ReleaseView.new()
var _draft_view := DraftView.new()
var _save_view := SaveView.new()
var _awards_view := AwardsView.new()
var _records_view := RecordsView.new()

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
	_scout_view.setup(_palette)
	_scout_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scout_view.visible = false
	_placeholder_label.get_parent().add_child(_scout_view)
	_fa_view.setup(_palette)
	_fa_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fa_view.visible = false
	_placeholder_label.get_parent().add_child(_fa_view)
	_trade_view.setup(_palette)
	_trade_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trade_view.visible = false
	_placeholder_label.get_parent().add_child(_trade_view)
	_comp_view.setup(_palette)
	_comp_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_comp_view.visible = false
	_placeholder_label.get_parent().add_child(_comp_view)
	_comp_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "comp":
			_description_label.text = text)
	_scout_view.trade_requested.connect(func() -> void: _open_sub_screen("trade"))
	_trade_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "trade":
			_description_label.text = text)
	_contract_view.setup(_palette)
	_contract_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_contract_view.visible = false
	_placeholder_label.get_parent().add_child(_contract_view)
	_release_view.setup(_palette)
	_release_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_release_view.visible = false
	_placeholder_label.get_parent().add_child(_release_view)
	_draft_view.setup(_palette)
	_draft_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_draft_view.visible = false
	_placeholder_label.get_parent().add_child(_draft_view)
	_save_view.setup(_palette)
	_save_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_view.visible = false
	_placeholder_label.get_parent().add_child(_save_view)
	_awards_view.setup(_palette)
	_awards_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_awards_view.visible = false
	_placeholder_label.get_parent().add_child(_awards_view)
	_awards_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "awards":
			_description_label.text = text)
	_records_view.setup(_palette)
	_records_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_records_view.visible = false
	_placeholder_label.get_parent().add_child(_records_view)
	_records_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "records":
			_description_label.text = text)
	_save_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "system":
			_description_label.text = text)
	# ロードしたらハブを作り直す（球団・年・段階が変わるので）
	_save_view.loaded.connect(func() -> void: get_tree().reload_current_scene.call_deferred())
	_draft_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "draft":
			_description_label.text = text)
	_release_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "release":
			_description_label.text = text)
	_contract_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "contract":
			_description_label.text = text)
	_fa_view.message_changed.connect(func(text: String) -> void:
		if _open_key == "fa":
			_description_label.text = text)
	_tactics_view.title_changed.connect(func(text: String) -> void: _sub_title_label.text = text)
	_tactics_view.description_changed.connect(func(text: String) -> void:
		_description_label.text = text)
	%BackButton.pressed.connect(_on_back)
	GameState.changed.connect(_refresh)
	_refresh()
	_buttons["advance"].grab_button_focus()
	UiFx.fade_in(self)


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
			"system":
				_save_view.switch_tab(delta)
			"awards":
				_awards_view.switch_tab(delta)
			"records":
				_records_view.switch_tab(delta)
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
	if _open_key not in ["tactics", "fa", "trade", "comp", "contract", "release", "draft", "system", "awards", "records"]:
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
	elif _open_key == "system":
		_save_view.refresh()
	elif _open_key == "awards":
		_awards_view.refresh()


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
	if key == "advance":
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
			return
		GameState.advance()
		if GameState.phase == GameState.Phase.AWARDS and GameState.awards_pending:
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
		return
	_open_sub_screen(key)


func _open_sub_screen(key: String) -> void:
	_open_key = key
	_sub_screen.visible = true
	_center_area.visible = false
	_standings.visible = false
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
	var is_system := key == "system"
	var is_awards := key == "awards"
	var is_records := key == "records"
	_awards_view.visible = is_awards
	_records_view.visible = is_records
	_save_view.visible = is_system
	_draft_view.visible = is_draft
	_tactics_view.visible = is_tactics
	_schedule_view.visible = is_schedule
	_scout_view.visible = is_scout
	_fa_view.visible = is_fa
	_trade_view.visible = is_trade
	_comp_view.visible = is_comp
	_contract_view.visible = is_contract
	_release_view.visible = is_release
	_placeholder_label.visible = not is_tactics and not is_schedule and not is_scout and not is_fa 		and not is_trade and not is_comp and not is_contract and not is_release and not is_draft and not is_system and not is_awards and not is_records
	# 采配は画面いっぱいに広げる（パワプロの采配画面のように、ハブのメニューを隠す）
	_set_wide(is_tactics or is_fa or is_trade or is_comp or is_contract or is_release or is_draft or is_awards or is_records)
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
	elif is_system:
		_sub_title_label.text = "システム：セーブ／ロード"
		_save_view.open()
	elif is_awards:
		_sub_title_label.text = "シーズン表彰（%d年）" % GameState.year
		_awards_view.open()
	elif is_records:
		_sub_title_label.text = "記録室"
		_records_view.open()
	else:
		_placeholder_label.text = PLACEHOLDERS.get(key, "") + "\n\n（未実装）"
		%BackButton.grab_focus()


## 采配のサブ画面を開いているときは、戻るで采配メニューの一覧へ戻る。日程表の早送り中は中止だけ
func _on_back() -> void:
	if _open_key == "schedule" and GameState.is_fast_forwarding():
		GameState.stop_fast_forward()
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
func _set_wide(wide: bool) -> void:
	UiFx.stop_slide(_sub_screen)
	_sub_screen.offset_left = WIDE_LEFT if wide else SUB_SCREEN_LEFT
	_sub_screen.offset_top = WIDE_TOP if wide else SUB_SCREEN_TOP
	_sub_screen.offset_right = -SUB_SCREEN_RIGHT
	_sub_screen.offset_bottom = -SUB_SCREEN_BOTTOM
	_menu_box.visible = not wide
	_event_label.visible = not wide
	_move_guide(wide)


func _close_sub_screen() -> void:
	# 早送りは日程表を開いている間だけ（閉じたら止める）
	GameState.stop_fast_forward()
	_set_wide(false)
	var key := _open_key
	_open_key = ""
	_sub_screen.visible = false
	_center_area.visible = true
	_standings.visible = true
	if not key.is_empty():
		UiFx.fade_in(_center_area)
		UiFx.fade_in(_standings)
	_description_label.text = _description(_focused_key)
	if _buttons.has(key):
		_buttons[key].grab_button_focus()
	elif key == "trade":
		_buttons["scout"].grab_button_focus()
	elif key in ["fa", "comp", "contract", "release", "draft", "awards"]:
		_buttons["advance"].grab_button_focus()
