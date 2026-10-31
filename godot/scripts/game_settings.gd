class_name GameSettings
extends RefCounted
## ドラフトの指名発表と読み上げ（作業28）の設定。保存は UserSettings（user://settings.cfg、[display] などほかの設定と同じファイル）。
## ここは既定の値を持つだけで、読み書きはその都度 UserSettings に任せる（ほかの項目を消さない）。
## テスト（-s でスクリプトを実行）のときはファイルを読まず・書かず、メモリだけで使う（ユーザーの設定を変えない）。
##
## [draft] announce_speed：指名発表の速さ（0 ゆっくり・1 ふつう・2 速め・3 自球団だけ）
## [voice] enabled・volume（0〜100）・backend（os / voicevox / wav）・voicevox_url・voicevox_speaker・wav_dir・rate
## 声の差し込み方は godot/README.md「ドラフトの読み上げ」

const DEFAULTS := {
	"draft": {"announce_speed": 1},
	"voice": {"enabled": true, "volume": 80, "backend": "os", "voicevox_url": "http://127.0.0.1:50021",
		"voicevox_speaker": 3, "wav_dir": "user://voice", "rate": 1.0},
}

## テスト中の設定（"section/key" → 値）
static var _memory := {}


static func get_value(section: String, key: String) -> Variant:
	var default: Variant = DEFAULTS.get(section, {}).get(key)
	if _under_test():
		return _memory.get(section + "/" + key, default)
	return UserSettings.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	if _under_test():
		_memory[section + "/" + key] = value
		return
	UserSettings.set_value(section, key, value)


## テスト用：メモリの設定を既定に戻す
static func reset() -> void:
	_memory = {}


static func _under_test() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null
