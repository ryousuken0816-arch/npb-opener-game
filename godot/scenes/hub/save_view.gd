class_name SaveView
extends VBoxContainer
## セーブ／ロードの画面（ハブの「システム」と、タイトルの「続きから」）。仕組みは SaveGame。
##
## 上に「セーブ」「ロード」の切り替え（LB/RB＝Q/E でも。タイトルではロードだけ）、その下にスロット1〜3と
## オートセーブの札（年・日付・球団・成績と保存日時）。札をⒶ／クリックで選ぶと、上書きセーブ・ロードは
## 下に確認（はい／いいえ。最初は「いいえ」を選んでいる）を出す。空きスロットへのセーブと、タイトルからのロードは確認なし。
## Ⓑ（Esc）はまず確認を閉じる→（ハブなら）ハブへ戻る。早送り中・自動処理の途中はセーブの札を押せない。
## オートセーブの枠にはセーブできない（GameState が月替わり・オフの段階の切り替わりで書く）。

signal message_changed(text: String)
## ロードが終わった（呼び出し元がハブの画面を作り直す）
signal loaded

const MODES := [["save", "セーブ", Color("7e57c2")], ["load", "ロード", Color("1e88e5")]]
const SLOT_HEIGHT := 64
const AUTO_COLOR := Color("5c7a99")

var load_only := false
var _palette: UiTheme.Palette
var _mode := "save"
## 確認を出している枠（空なら確認なし）
var _pending := ""
var _mode_row: HBoxContainer
var _mode_buttons := {}
var _fullscreen_button: Button
var _slot_buttons := {}
var _status_label: Label
var _confirm_panel: PanelContainer
var _confirm_label: Label
var _yes_button: Button
var _no_button: Button


## only_load：タイトルの「続きから」（ロードだけ、確認なし）
func setup(p: UiTheme.Palette, only_load := false) -> void:
	_palette = p
	load_only = only_load
	_mode = "load" if only_load else "save"
	add_theme_constant_override("separation", 8)
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 8)
	_mode_row.add_child(UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800))
	for m: Array in MODES:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_font_override("font", UiTheme.font(800))
		UiTheme.style_toggle(b, p.ink)
		var key: String = m[0]
		b.pressed.connect(func() -> void: set_mode(key))
		_mode_row.add_child(b)
		_mode_buttons[key] = b
	_mode_row.add_child(UiTheme.small_label("RB ▶", 18, UiTheme.TEXT, 800))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_row.add_child(spacer)
	_fullscreen_button = Button.new()
	_fullscreen_button.toggle_mode = true
	_fullscreen_button.custom_minimum_size = Vector2(230, 44)
	_fullscreen_button.add_theme_font_size_override("font_size", 20)
	_fullscreen_button.add_theme_font_override("font", UiTheme.font(800))
	_fullscreen_button.tooltip_text = "フルスクリーン⇔ウィンドウ（F11・Alt+Enter でも切り替わる）。次の起動でも同じになる"
	UiTheme.style_toggle(_fullscreen_button, UiTheme.TEXT_SUB)
	_fullscreen_button.toggled.connect(func(on: bool) -> void:
		if on != UiInput.fullscreen:
			UiInput.set_fullscreen(on))
	_mode_row.add_child(_fullscreen_button)
	UiInput.fullscreen_changed.connect(_sync_fullscreen_button)
	_sync_fullscreen_button(UiInput.fullscreen)
	_mode_row.visible = not only_load
	add_child(_mode_row)
	for slot in SaveGame.all_slots():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_font_override("font", UiTheme.font(700))
		b.clip_text = true
		UiTheme.style_button(b, AUTO_COLOR if slot == SaveGame.AUTO else p.main, Color.TRANSPARENT, 10, 5)
		b.pressed.connect(choose.bind(slot))
		add_child(b)
		_slot_buttons[slot] = b
	_confirm_panel = PanelContainer.new()
	var style := UiTheme.card(Color("e53935"), 10, 3, 0.98)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	_confirm_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_confirm_panel.add_child(row)
	_confirm_label = UiTheme.small_label("", 18, UiTheme.TEXT, 800)
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_confirm_label)
	_yes_button = _small_button("はい", Color("e53935"))
	_yes_button.pressed.connect(_confirm_yes)
	row.add_child(_yes_button)
	_no_button = _small_button("いいえ", Color("8a9199"))
	_no_button.pressed.connect(cancel_confirm)
	row.add_child(_no_button)
	_confirm_panel.visible = false
	add_child(_confirm_panel)
	# ハブでは案内を下の帯（message_changed）に出すので、この画面の案内の行はタイトルの「続きから」のときだけ
	_status_label = UiTheme.small_label("", 17, UiTheme.TEXT, 700)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = only_load
	add_child(_status_label)


## システムの設定「フルスクリーン」の表示を UiInput の状態に合わせる（F11 での切り替えにも追従）
func _sync_fullscreen_button(on: bool) -> void:
	if _fullscreen_button == null:
		return
	_fullscreen_button.set_pressed_no_signal(on)
	_fullscreen_button.text = "フルスクリーン：%s" % ("オン" if on else "オフ")


func _small_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 44)
	b.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(b, color, Color.WHITE, 10, 6)
	return b


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_pending = ""
	_confirm_panel.visible = false
	_set_status(_default_status())
	refresh()
	focus_first()


## 戻る：確認を出していれば閉じて true。何もなければ false（呼び出し元が閉じる）
func back() -> bool:
	if not _pending.is_empty():
		cancel_confirm()
		return true
	return false


func switch_tab(delta: int) -> void:
	if load_only:
		return
	var i := 0 if _mode == "save" else 1
	set_mode(MODES[posmod(i + delta, MODES.size())][0])


func set_mode(mode: String) -> void:
	if load_only:
		mode = "load"
	_mode = mode
	_pending = ""
	_confirm_panel.visible = false
	_set_status(_default_status())
	refresh()
	focus_first()


func mode() -> String:
	return _mode


## 確認を出している枠（テスト用）
func pending() -> String:
	return _pending


func focus_first() -> void:
	if not _pending.is_empty():
		UiInput.grab(_no_button)
		return
	for slot in SaveGame.all_slots():
		if UiInput.grab(_slot_buttons[slot]):
			return
	if not load_only:
		UiInput.grab(_mode_buttons[_mode])


func refresh() -> void:
	for key: String in _mode_buttons:
		_mode_buttons[key].set_pressed_no_signal(key == _mode)
	var can_save := GameState.can_save()
	for slot in SaveGame.all_slots():
		var b: Button = _slot_buttons[slot]
		var header := SaveGame.info(slot)
		var slot_name: String = SaveGame.SLOT_NAMES.get(slot, slot)
		var saved := str(header.get("saved_at", "")).replace("-", "/")
		var line1 := slot_name
		if not saved.is_empty():
			line1 += "　　保存日時 %s" % saved.substr(0, 16)
		b.text = "%s\n%s" % [line1, SaveGame.summary_text(header) if not header.is_empty() else "（空き）"]
		if _mode == "save":
			b.disabled = slot == SaveGame.AUTO or not can_save
			b.tooltip_text = "オートセーブ（月替わり・オフの段階の切り替わりで自動で保存）にはセーブできません" \
				if slot == SaveGame.AUTO else "この枠にセーブします"
		else:
			b.disabled = header.is_empty()
			b.tooltip_text = "この枠をロードして続きから遊びます" if not header.is_empty() else "空きです"
		UiFx.sync_focus_mode(b)


## 枠を選んだ：セーブ（上書きは確認）／ロード（ハブからは確認、タイトルからはすぐ）
func choose(slot: String) -> void:
	var slot_name: String = SaveGame.SLOT_NAMES.get(slot, slot)
	if _mode == "save":
		if slot == SaveGame.AUTO:
			return
		if not GameState.can_save():
			_set_status(GameState.save_block_reason())
			return
		if SaveGame.exists(slot):
			_ask(slot, "%sに上書きセーブしますか？" % slot_name)
		else:
			_do_save(slot)
		return
	if not SaveGame.exists(slot):
		_set_status("%sは空きです" % slot_name)
		return
	if load_only:
		_do_load(slot)
	else:
		_ask(slot, "%sをロードしますか？" % slot_name)


func cancel_confirm() -> void:
	var slot := _pending
	_pending = ""
	_confirm_panel.visible = false
	_set_status(_default_status())
	if _slot_buttons.has(slot) and UiInput.grab(_slot_buttons[slot]):
		return
	focus_first()


# --- 内部 ----------------------------------------------------------------------------

func _ask(slot: String, text: String) -> void:
	_pending = slot
	_confirm_label.text = text
	_confirm_panel.visible = true
	_set_status("はい：上書きセーブ（前のセーブは消えます）　いいえ／Ⓑ：やめる" if _mode == "save"
		else "はい：ロード（セーブしていない今の進行は失われます）　いいえ／Ⓑ：やめる")
	UiInput.grab(_no_button)


func _confirm_yes() -> void:
	var slot := _pending
	_pending = ""
	_confirm_panel.visible = false
	if slot.is_empty():
		return
	if _mode == "save":
		_do_save(slot)
	else:
		_do_load(slot)


func _do_save(slot: String) -> void:
	var error := SaveGame.save(slot)
	refresh()
	if error.is_empty():
		_set_status("%sにセーブしました（%s）" % [SaveGame.SLOT_NAMES.get(slot, slot),
			SaveGame.summary_text(SaveGame.info(slot))])
	else:
		_set_status(error)
	if not UiInput.grab(_slot_buttons[slot]):
		focus_first()


func _do_load(slot: String) -> void:
	_set_status("%sをロードしています…" % SaveGame.SLOT_NAMES.get(slot, slot))
	var error := SaveGame.load_slot(slot)
	if not error.is_empty():
		_set_status(error)
		refresh()
		focus_first()
		return
	loaded.emit()


func _default_status() -> String:
	if _mode == "save":
		if not GameState.can_save():
			return GameState.save_block_reason()
		return "セーブする枠を選んでください（オートセーブは月替わりとオフの段階の切り替わりで自動で保存）。"
	return "ロードする枠を選んでください。"


func _set_status(text: String) -> void:
	_status_label.text = text
	message_changed.emit(text)
