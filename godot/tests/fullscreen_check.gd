extends SceneTree
## フルスクリーン切り替えの確認（ヘッドレス。実際にはウィンドウを変えない）。
## - UserSettings：保存・読み戻し・ほかの項目を消さない
## - UiInput：set_fullscreen / toggle_fullscreen が設定を保存し、再起動（load_display_settings）で復元される
## - F11・Alt+Enter のキーイベントで切り替わる（押した瞬間だけ。リピート・離す・Enter だけ・Alt+ほかのキーでは切り替わらない）
## - システムの設定（SaveView）の「フルスクリーン」ボタンが切り替えと表示に追従する
## - project.godot：横長・縦長のモニターで黒い帯を出す（stretch aspect=keep。スマホ表示のときだけ UiLayout が expand にする）
##
##   godot --headless --path godot --script res://tests/fullscreen_check.gd

const TEST_PATH := "user://test_settings.cfg"

var _failures := 0
var _ui: Node
var _changes: Array[bool] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_ui = root.get_node("UiInput")
	UserSettings.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	_ui.fullscreen_changed.connect(func(on: bool) -> void: _changes.append(on))
	_check_settings()
	_check_toggle_and_restore()
	_check_keys()
	_check_system_button()
	_check_project()
	DirAccess.remove_absolute(TEST_PATH)
	UserSettings.path = UserSettings.DEFAULT_PATH
	print("\n%s（失敗 %d件）" % ["すべてOK" if _failures == 0 else "失敗あり", _failures])
	quit(1 if _failures > 0 else 0)


func _check_settings() -> void:
	print("== UserSettings ==")
	_check(UserSettings.get_value("display", "fullscreen", false) == false, "ファイルが無ければ既定値")
	_check(UserSettings.set_value("other", "volume", 7), "別の項目を保存できる")
	_check(UserSettings.set_value("display", "fullscreen", true), "fullscreen を保存できる")
	_check(UserSettings.get_value("display", "fullscreen", false) == true, "fullscreen を読み戻せる")
	_check(UserSettings.get_value("other", "volume", 0) == 7, "ほかの項目は消えない")
	DirAccess.remove_absolute(TEST_PATH)


func _check_toggle_and_restore() -> void:
	print("== 切り替えと保存・復元 ==")
	_ui.set_fullscreen(false)
	_changes.clear()
	_ui.set_fullscreen(true)
	_check(_ui.fullscreen, "set_fullscreen(true) で fullscreen")
	_check(UserSettings.get_value("display", "fullscreen", false) == true, "設定ファイルに true が保存される")
	_check(_changes == [true], "fullscreen_changed が出る（%s）" % [_changes])
	_ui.fullscreen = false  # 再起動の代わり
	_ui.load_display_settings()
	_check(_ui.fullscreen, "再起動で fullscreen が復元される")
	_ui.toggle_fullscreen()
	_check(not _ui.fullscreen and UserSettings.get_value("display", "fullscreen", true) == false,
			"toggle_fullscreen でウィンドウに戻り保存される")
	_ui.fullscreen = true
	_ui.load_display_settings()
	_check(not _ui.fullscreen, "再起動でウィンドウが復元される")


func _check_keys() -> void:
	print("== F11・Alt+Enter ==")
	_ui.set_fullscreen(false)
	_press(KEY_F11)
	_check(_ui.fullscreen, "F11 でフルスクリーン")
	_press(KEY_F11)
	_check(not _ui.fullscreen, "F11 でウィンドウに戻る")
	_press(KEY_ENTER, true)
	_check(_ui.fullscreen, "Alt+Enter でフルスクリーン")
	_press(KEY_KP_ENTER, true)
	_check(not _ui.fullscreen, "Alt+Enter（テンキー）でウィンドウに戻る")
	_press(KEY_ENTER)
	_check(not _ui.fullscreen, "Enter だけでは切り替わらない")
	_press(KEY_F, true)
	_check(not _ui.fullscreen, "Alt+ほかのキーでは切り替わらない")
	_press(KEY_F11, false, true)
	_check(not _ui.fullscreen, "キーリピート（echo）では切り替わらない")
	var up := InputEventKey.new()
	up.keycode = KEY_F11
	up.pressed = false
	root.push_input(up)
	_check(not _ui.fullscreen, "キーを離したときは切り替わらない")


func _check_system_button() -> void:
	print("== システムの設定の「フルスクリーン」 ==")
	_ui.set_fullscreen(false)
	# SaveView・UiTheme は autoload（GameData）に依存するので実行時に読み込む
	var view: Node = load("res://scenes/hub/save_view.gd").new()
	root.add_child(view)
	view.setup(load("res://scripts/ui_theme.gd").neutral_palette())
	var button: Button = view._fullscreen_button
	_check(button != null and "オフ" in button.text and not button.button_pressed, "ボタンの表示：オフ（%s）" % button.text)
	button.button_pressed = true
	_check(_ui.fullscreen and "オン" in button.text, "ボタンを押すとフルスクリーン（%s）" % button.text)
	_press(KEY_F11)
	_check(not _ui.fullscreen and "オフ" in button.text and not button.button_pressed,
			"F11 で切り替えても表示が追従する（%s）" % button.text)
	view.queue_free()
	_ui.set_fullscreen(false)


func _check_project() -> void:
	print("== project.godot ==")
	_check(ProjectSettings.get_setting("display/window/stretch/aspect") == "keep",
			"stretch aspect=keep（横長・縦長は黒い帯で 16:9 のまま。スマホは UiLayout が expand に）")
	_check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1280
			and ProjectSettings.get_setting("display/window/size/viewport_height") == 720, "基準は 1280x720")


func _press(keycode: Key, alt := false, echo := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	e.echo = echo
	e.alt_pressed = alt
	root.push_input(e)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s" % ["OK" if ok else "NG", label])
