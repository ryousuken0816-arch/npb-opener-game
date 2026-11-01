class_name UiLayoutNode
extends Node
## 画面解像度・アスペクト比・端末タイプを監視し、PC横画面とスマホ縦画面の切り替えを司るシングルトン。
##
## - is_portrait: 縦画面か（画面幅 < 画面高さ）
## - is_mobile: モバイル（タッチ対応、縦画面、または手動設定）
## - safe_area_top: 上部セーフエリア（ノッチ・ダイナミックアイランド・ステータスバー余白）
## - safe_area_bottom: 下部セーフエリア（ホームバー・ナビゲーションバー余白）
## - layout_changed(is_portrait: bool, is_mobile: bool): レイアウト切り替えシグナル
## - force_mode: "auto" / "pc" / "mobile"（手動オーバーライド可能）

signal layout_changed(is_portrait: bool, is_mobile: bool)

const PC_SCALE_SIZE := Vector2i(1280, 720)
const MOBILE_HOME_SCALE_SIZE := Vector2i(580, 960)
const MOBILE_SUB_SCALE_SIZE := Vector2i(860, 1280)

var force_mode: String = "auto"
var is_portrait: bool = false
var is_mobile: bool = false
var sub_screen_active: bool = false
var safe_area_top: float = 0.0
var safe_area_bottom: float = 0.0

var _last_size := Vector2.ZERO
var _updating_scale := false


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_layout()


func _on_viewport_size_changed() -> void:
	if _updating_scale:
		return
	_update_layout()


## サブ画面（采配・日程・ドラフト等の詳細画面）が開いているかを通知し、スケールを最適化する
func set_sub_screen_active(active: bool) -> void:
	if sub_screen_active == active:
		return
	sub_screen_active = active
	_apply_content_scale()


## 手動でモードを切り替える（"auto", "pc", "mobile"）
func set_force_mode(mode: String) -> void:
	if force_mode == mode:
		return
	force_mode = mode
	_update_layout(true)


## PC/スマホの表示をトグルする（デバッグ・UI確認用）
func toggle_mode() -> void:
	if is_portrait:
		set_force_mode("pc")
	else:
		set_force_mode("mobile")


func _apply_content_scale() -> void:
	var root_win := get_tree().root if get_tree() != null else null
	if root_win == null:
		return
	var target_scale := PC_SCALE_SIZE
	if is_portrait:
		target_scale = MOBILE_SUB_SCALE_SIZE if sub_screen_active else MOBILE_HOME_SCALE_SIZE
	if root_win.content_scale_size != target_scale:
		_updating_scale = true
		root_win.content_scale_size = target_scale
		_updating_scale = false


func _update_layout(force_notify := false) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var win_size := DisplayServer.window_get_size()
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return

	var natural_portrait := (win_size.x < win_size.y) if (win_size.x > 0 and win_size.y > 0) else (vp_size.x < vp_size.y)
	var touch := DisplayServer.is_touchscreen_available()
	var os_mobile := (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

	var prev_portrait := is_portrait
	var prev_mobile := is_mobile

	match force_mode:
		"mobile":
			is_portrait = true
			is_mobile = true
		"pc":
			is_portrait = false
			is_mobile = false
		_:
			is_portrait = natural_portrait
			is_mobile = natural_portrait or touch or os_mobile

	_apply_content_scale()
	vp_size = vp.get_visible_rect().size

	# セーフエリアの計算（スマホ縦画面時にノッチとホームバーの安全マージンを確保）
	if is_mobile and is_portrait:
		var sa := DisplayServer.get_display_safe_area()
		if sa.size.y > 0 and sa.position.y > 0 and sa.position.y < vp_size.y:
			safe_area_top = sa.position.y
			safe_area_bottom = maxf(0.0, vp_size.y - (sa.position.y + sa.size.y))
		else:
			# ブラウザや未対応環境向けの標準セーフエリア
			safe_area_top = 12.0
			safe_area_bottom = 14.0
	else:
		safe_area_top = 0.0
		safe_area_bottom = 0.0

	var changed := force_notify or (prev_portrait != is_portrait) or (prev_mobile != is_mobile) or (_last_size != vp_size)
	_last_size = vp_size
	if changed:
		layout_changed.emit(is_portrait, is_mobile)
