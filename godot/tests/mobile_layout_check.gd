extends SceneTree
## スマホ対応・レスポンシブUI・セーブエクスポートの自動検証スクリプト

const TITLE_SCENE := "res://scenes/title/title.tscn"
const HUB_SCENE := "res://scenes/hub/hub.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("==================================================")
	print("スマホ対応（レスポンシブ・縦画面・Web機能）検証テスト開始")
	print("==================================================")

	var layout: Node = root.get_node("UiLayout")

	# 1. UiLayout の動作検証
	print("--- 1. UiLayout モード切り替えテスト ---")
	layout.call("set_force_mode", "mobile")
	assert(bool(layout.get("is_portrait")) == true, "mobile mode should be portrait")
	assert(bool(layout.get("is_mobile")) == true, "mobile mode should be mobile")
	assert(float(layout.get("safe_area_top")) > 0, "safe_area_top should be set in mobile mode")
	assert(float(layout.get("safe_area_bottom")) > 0, "safe_area_bottom should be set in mobile mode")
	print("  OK: UiLayout モード切り替え（mobile: portrait=true, safe_area 有効）")

	layout.call("set_force_mode", "pc")
	assert(bool(layout.get("is_portrait")) == false, "pc mode should not be portrait")
	assert(bool(layout.get("is_mobile")) == false, "pc mode should not be mobile")
	assert(float(layout.get("safe_area_top")) == 0.0, "safe_area_top should be 0 in pc mode")
	print("  OK: UiLayout モード切り替え（pc: portrait=false, safe_area=0）")

	# 2. セーブデータのエクスポート/インポート検証
	print("--- 2. セーブデータ エクスポート/インポート テスト ---")
	var gs: Node = root.get_node("GameState")
	var sg: GDScript = load("res://scripts/save_game.gd")
	gs.new_game("阪神タイガース", 2026)
	var save_err: String = sg.call("save", "slot1")
	assert(save_err.is_empty(), "save should succeed: " + save_err)

	var json_str: String = sg.call("export_json", "slot1")
	assert(not json_str.is_empty(), "export_json should return non-empty JSON string")
	var parsed: Variant = JSON.parse_string(json_str)
	assert(parsed is Dictionary, "exported JSON should parse to Dictionary")
	assert(parsed.get("version") == sg.get("VERSION"), "version should match")
	print("  OK: セーブデータのエクスポート（JSON出力）成功")

	var import_err: String = sg.call("import_json", "slot2", json_str)
	assert(import_err.is_empty(), "import_json should succeed: " + import_err)
	assert(sg.call("exists", "slot2"), "imported slot2 should exist")
	var slot2_info: Dictionary = sg.call("info", "slot2")
	assert(not slot2_info.is_empty(), "slot2 info should exist")
	print("  OK: セーブデータのインポート（別スロットへの復元）成功")

	# 3. タイトル画面のスマホ縦画面検証
	print("--- 3. タイトル画面 スマホ縦画面レイアウト検証 ---")
	layout.call("set_force_mode", "mobile")
	var title_packed := load(TITLE_SCENE) as PackedScene
	var title_node: Control = title_packed.instantiate()
	root.add_child(title_node)
	assert(title_node.get_node("%TitleLabel") != null, "TitleLabel must exist")
	print("  OK: タイトル画面（スマホ縦画面モード）生成完了")
	title_node.queue_free()

	# 4. ハブ画面のスマホ縦画面・サブ画面全画面化検証
	print("--- 4. ハブ画面 スマホ縦画面ダッシュボード＆全画面サブスクリーン検証 ---")
	layout.call("set_force_mode", "mobile")
	var hub_packed := load(HUB_SCENE) as PackedScene
	var hub_node: Control = hub_packed.instantiate()
	root.add_child(hub_node)

	# モバイル用ダッシュボードの確認
	var mobile_scroll: ScrollContainer = hub_node.get("_mobile_scroll")
	assert(mobile_scroll != null, "_mobile_scroll must exist")
	assert(mobile_scroll.visible == true, "mobile dashboard should be visible on hub top")
	var mobile_btn: Button = hub_node.get("_mobile_advance_button")
	assert(mobile_btn != null, "_mobile_advance_button must exist")
	print("  OK: ハブ画面（スマホ縦画面モード）モバイルダッシュボード表示確認")

	# サブ画面（采配）を開いたときの全画面化確認
	hub_node.call("_open_sub_screen", "tactics")
	var sub_screen: PanelContainer = hub_node.get_node("%SubScreen")
	assert(sub_screen.visible == true, "SubScreen should be visible")
	assert(mobile_scroll.visible == false, "mobile dashboard should be hidden when sub screen is open")
	UiFx.stop_slide(sub_screen)
	assert(sub_screen.offset_left == 6.0, "SubScreen should expand to mobile full width (6.0)")
	var back_btn: Button = hub_node.get_node("%BackButton")
	assert(back_btn.text == "← 戻る", "Back button text should be '← 戻る' on mobile")
	print("  OK: 采配画面オープン時の全画面展開＆「← 戻る」ボタン表示確認")

	# 戻る操作の確認
	hub_node.call("_on_back")
	assert(mobile_scroll.visible == true, "mobile dashboard should be restored after back")
	assert(sub_screen.visible == false, "SubScreen should be closed")
	print("  OK: 戻る操作によるダッシュボード復帰確認")

	# 日程表を開いたときの確認
	hub_node.call("_open_sub_screen", "schedule")
	assert(sub_screen.visible == true, "Schedule SubScreen should be visible")
	hub_node.call("_on_back")
	print("  OK: 日程表画面オープン＆戻る確認")

	# システム（セーブ）画面を開いたときの確認
	hub_node.call("_open_sub_screen", "system")
	assert(sub_screen.visible == true, "System SubScreen should be visible")
	hub_node.call("_on_back")
	print("  OK: システム（セーブ）画面オープン＆戻る確認")

	hub_node.queue_free()

	# 5. PCモードへの復帰検証
	print("--- 5. PCモード復帰検証 ---")
	layout.call("set_force_mode", "pc")
	var hub_pc: Control = hub_packed.instantiate()
	root.add_child(hub_pc)
	var pc_menu: VBoxContainer = hub_pc.get_node("%MenuBox")
	assert(pc_menu.visible == true, "MenuBox should be visible in PC mode")
	var pc_scroll: ScrollContainer = hub_pc.get("_mobile_scroll")
	assert(pc_scroll.visible == false, "mobile scroll should be hidden in PC mode")
	print("  OK: PCモードでのPCレイアウト復元確認")
	hub_pc.queue_free()

	print("==================================================")
	print("【ALL OK】スマホ対応・Web機能の全検証項目が完全パスしました！")
	print("==================================================")
	quit(0)
