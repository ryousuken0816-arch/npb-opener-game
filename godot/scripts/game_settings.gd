class_name GameSettings
extends RefCounted
## ゲームの設定（user://settings.cfg）。いまはドラフトの指名発表と読み上げ（作業28）だけ。
## テスト（-s でスクリプトを実行）のときはファイルを読まず・書かず、既定の値をメモリだけで使う（ユーザーの設定を変えない）。
##
## [draft] announce_speed：指名発表の速さ（0 ゆっくり・1 ふつう・2 速め・3 自球団だけ）
## [voice] enabled・volume（0〜100）・backend（os / voicevox / wav）・voicevox_url・voicevox_speaker・wav_dir・rate
## 声の差し込み方は godot/README.md「ドラフトの読み上げ」

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"draft": {"announce_speed": 1},
	"voice": {"enabled": true, "volume": 80, "backend": "os", "voicevox_url": "http://127.0.0.1:50021",
		"voicevox_speaker": 3, "wav_dir": "user://voice", "rate": 1.0},
}

static var _cfg: ConfigFile


static func get_value(section: String, key: String) -> Variant:
	_load()
	return _cfg.get_value(section, key, DEFAULTS.get(section, {}).get(key))


static func set_value(section: String, key: String, value: Variant) -> void:
	_load()
	_cfg.set_value(section, key, value)
	if not _under_test():
		_cfg.save(PATH)


## テスト用：メモリの設定を既定に戻す
static func reset() -> void:
	_cfg = ConfigFile.new()


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	if not _under_test() and FileAccess.file_exists(PATH):
		_cfg.load(PATH)


static func _under_test() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null
