class_name UserSettings
extends RefCounted
## ユーザーの設定（セーブデータとは別）。`user://settings.cfg`（ConfigFile）に覚えて次の起動でも同じにする。
## 今ある設定：[display] fullscreen（UiInput が起動時に読む）。システムの設定項目はここに足していく。

const DEFAULT_PATH := "user://settings.cfg"

## 保存先。テストが本物の設定を壊さないよう差し替える
static var path := DEFAULT_PATH


static func get_value(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default
	return cfg.get_value(section, key, default)


## 値を書いて保存する。保存できなければ false
static func set_value(section: String, key: String, value: Variant) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)  # 無ければ空のまま（他の項目は残す）
	cfg.set_value(section, key, value)
	return cfg.save(path) == OK
