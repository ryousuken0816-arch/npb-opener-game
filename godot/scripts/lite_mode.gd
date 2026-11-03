class_name LiteMode
extends RefCounted
## 軽量モード（作業75）：メモリの少ない端末（iPhone SE2 など）の Web 版が落ちにくいよう、メモリを使う所を減らす。
## - ハブのサブ画面を閉じたら捨てる（ふだんは一度開いた画面を持ち続ける。どちらも開くときに作る）
## - 字の画像の覚え（新しい字ごとに増える）を、記録室・ドラフトなど字の多い画面を閉じたときに捨てる（UiTheme.trim_glyphs）
## - 歴代メンバー・歴代ドラフトで持っておく年の数を減らす（RecordsHistory）
## システムの設定でオン・オフ（user://settings.cfg の [display] lite）。決めていなければ、Web 版で端末のメモリが
## 4GB 以下（navigator.deviceMemory。iPhone の Safari には無い）か、取れなければ iPhone の UA ならオン。パソコン版はオフ。
## テスト（-s でスクリプトを実行）は設定のファイルを読まず・書かない。環境変数 NPB_LITE=1／0 で決める（無ければオフ）。

const SECTION := "display"
const KEY := "lite"
## これ以下のメモリ（GB）の端末は最初からオン
const AUTO_MEMORY_GB := 4.0

static var _on: Variant = null


static func on() -> bool:
	if _on == null:
		_on = _initial()
	return _on


## オン・オフを変えて覚える（次の起動でも同じ）
static func set_on(value: bool) -> void:
	_on = value
	if not _under_test():
		UserSettings.set_value(SECTION, KEY, value)


static func _initial() -> bool:
	var env := OS.get_environment("NPB_LITE")
	if not env.is_empty():
		return env == "1"
	if _under_test():
		return false
	var saved: Variant = UserSettings.get_value(SECTION, KEY, "")  # 決めていなければ ""（null だと ConfigFile がエラーを出す）
	if saved is bool:
		return saved
	return auto_detect()


## 決めていないときの既定：Web 版でメモリの少ない端末か
static func auto_detect() -> bool:
	if not OS.has_feature("web"):
		return false
	var gb := float(JavaScriptBridge.eval("navigator.deviceMemory || 0", true))
	if gb > 0.0:
		return gb <= AUTO_MEMORY_GB
	var ua := str(JavaScriptBridge.eval("navigator.userAgent || ''", true))
	return ua.contains("iPhone") or ua.contains("iPod")


static func _under_test() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null
