class_name UiLayoutNode
extends Node
## 画面の大きさ・向き・端末を見て、パソコンとスマホ（縦・横）の表示を切り替えるシングルトン（オートロード `UiLayout`）。
##
## - is_mobile：スマホ表示か。スマホのブラウザ（web_ios / web_android）・スマホのアプリ、または縦長のウィンドウ、
##   または手動（force_mode="mobile"）。タッチ画面付きのパソコンはパソコンのまま（見た目と操作を変えない）
## - is_portrait：スマホ表示で縦向きか（is_mobile のときだけ true になりうる）
## - 画面の論理サイズ（content_scale_size）：パソコン 1280x720。スマホの縦は幅 480、横は高さ 592（幅 1280＝パソコンと同じ配置）
## - touch_units()：指で押しやすい大きさ（実寸 44px）が論理サイズで何ピクセルか。TouchAdapt がボタンをこの大きさにそろえる
## - bottom_inset()：画面の下のスマホ用の操作の帯（ハブの MobileNavBar）とホームバーの分の高さ。画面の下端を空けるのに使う
## - layout_changed(is_portrait, is_mobile)：切り替わった・画面の大きさが変わった
## - force_mode："auto" / "pc" / "mobile"（スマホで「PC表示」に切り替えるボタン・テスト用）

signal layout_changed(is_portrait: bool, is_mobile: bool)

const PC_SCALE_SIZE := Vector2i(1280, 720)
## スマホ縦：論理の幅 480（iPhone の幅 390px なら 1px＝約0.81）。高さは画面の比率に合わせて伸びる（aspect=expand）
const PORTRAIT_SCALE_SIZE := Vector2i(480, 800)
## スマホ横：論理の幅 1280（パソコンと同じ配置）・高さ 592（iPhone の横 844x390 とほぼ同じ比率）
const LANDSCAPE_SCALE_SIZE := Vector2i(1280, 592)
## 指で押しやすい大きさ（実寸の CSS ピクセル。Apple の目安）
const TOUCH_PX := 44.0
## スマホ用の操作の帯の高さ（論理ピクセル。ボタンの高さ＋上下の余白。縦はボタンの上に1行の案内が入る）
const NAV_PAD := 14.0
const NAV_MESSAGE_HEIGHT := 26.0

var force_mode: String = "auto"
var is_portrait: bool = false
var is_mobile: bool = false
var sub_screen_active: bool = false
var safe_area_top: float = 0.0
var safe_area_bottom: float = 0.0

var _last_size := Vector2.ZERO
var _updating_scale := false
var _adapt: Node


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_adapt = load("res://scripts/touch_adapt.gd").new()
	add_child(_adapt)
	_update_layout()


func _on_viewport_size_changed() -> void:
	if _updating_scale:
		return
	_update_layout()


## サブ画面を開いているか（ハブが知らせる。表示の切り替えには使っていない。以前の呼び出しのために残す）
func set_sub_screen_active(active: bool) -> void:
	sub_screen_active = active


## 今の画面を TouchAdapt に調べ直させる（表示を切り替えただけでは node_added が来ないので、サブ画面を開いたときに呼ぶ）
func refit() -> void:
	if _adapt != null:
		_adapt.call("mark_dirty")


## 手動でモードを切り替える（"auto", "pc", "mobile"）
func set_force_mode(mode: String) -> void:
	if force_mode == mode:
		return
	force_mode = mode
	_update_layout(true)


## スマホの「PC表示」⇔「スマホ表示」の切り替え（パソコン表示にしたら自動に戻す）
func toggle_mode() -> void:
	if is_mobile:
		set_force_mode("pc")
	elif _os_mobile():
		set_force_mode("auto")
	else:
		set_force_mode("mobile")


## スマホのブラウザ・アプリか（ボタンで PC 表示にしていても true。切り替えのボタンを出すかに使う）
func on_phone() -> bool:
	return _os_mobile() or force_mode != "auto"


static func _os_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## 実寸（CSS ピクセル）で論理の1ピクセルが何ピクセルか
func px_per_unit() -> float:
	var root_win := get_tree().root if get_tree() != null else null
	if root_win == null:
		return 1.0
	var visible := root_win.get_visible_rect().size
	if visible.x <= 0.0:
		return 1.0
	var dpr := maxf(DisplayServer.screen_get_scale(), 1.0) if OS.has_feature("web") else 1.0
	return float(root_win.size.x) / dpr / visible.x


## 指で押しやすい大きさ（実寸 44px）を論理ピクセルにしたもの。パソコンは 0（何もしない）
func touch_units() -> float:
	if not is_mobile:
		return 0.0
	return clampf(ceilf(TOUCH_PX / maxf(px_per_unit(), 0.01)), 36.0, 96.0)


## スマホ用の操作の帯の高さ（ホームバーの余白を含む）。パソコンは 0
func bottom_inset() -> float:
	if not is_mobile:
		return 0.0
	return touch_units() + NAV_PAD + (NAV_MESSAGE_HEIGHT if is_portrait else 0.0) + safe_area_bottom


func _apply_content_scale() -> void:
	var root_win := get_tree().root if get_tree() != null else null
	if root_win == null:
		return
	var target_scale := PC_SCALE_SIZE
	if is_mobile:
		target_scale = PORTRAIT_SCALE_SIZE if is_portrait else LANDSCAPE_SCALE_SIZE
	if root_win.content_scale_size != target_scale:
		_updating_scale = true
		root_win.content_scale_size = target_scale
		_updating_scale = false


func _update_layout(force_notify := false) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var win_size := Vector2(get_tree().root.size)
	if win_size.x <= 0 or win_size.y <= 0:
		win_size = vp.get_visible_rect().size
	if win_size.x <= 0 or win_size.y <= 0:
		return
	var natural_portrait := win_size.x < win_size.y

	var prev_portrait := is_portrait
	var prev_mobile := is_mobile

	match force_mode:
		"mobile":
			is_mobile = true
		"pc":
			is_mobile = false
		_:
			is_mobile = _os_mobile() or natural_portrait
	is_portrait = is_mobile and natural_portrait

	_apply_content_scale()
	var vp_size := vp.get_visible_rect().size

	# セーフエリア（ノッチ・ホームバー）。ブラウザで取れないときは小さな余白
	if is_mobile:
		var sa := DisplayServer.get_display_safe_area()
		var scale := vp_size.y / win_size.y
		if sa.size.y > 0 and sa.position.y > 0 and sa.position.y < win_size.y:
			safe_area_top = sa.position.y * scale
			safe_area_bottom = maxf(0.0, (win_size.y - (sa.position.y + sa.size.y)) * scale)
		else:
			safe_area_top = 8.0 if is_portrait else 0.0
			safe_area_bottom = 8.0 if is_portrait else 4.0
	else:
		safe_area_top = 0.0
		safe_area_bottom = 0.0

	var changed := force_notify or (prev_portrait != is_portrait) or (prev_mobile != is_mobile) or (_last_size != vp_size)
	_last_size = vp_size
	if changed:
		layout_changed.emit(is_portrait, is_mobile)
