class_name SaveGame
extends RefCounted
## セーブ／ロード（docs/AUTORUN.md 作業6）。ゲームの状態（GameState.to_save()）を user://saves/ に JSON で保存する。
##
## - 枠：スロット1〜3（slot1〜slot3）とオートセーブ（auto。月替わり・オフの段階の切り替わりで GameState が書く）
## - ファイル：<枠>.json（{version, saved_at, summary, state}）と、一覧表示用の小さな <枠>_info.json（state なし）
## - 能力値ファイル（generated/ratings）は保存しない。ロード時にその年のファイルを読み直してから所属などを当てる
## - JSON にすると整数が小数になる（ints() で戻す）。Dictionary のキーは文字列（ゲームの状態のキーはもともと文字列）。
##   乱数の状態（64ビット）は小数にすると桁が落ちるので文字列で持つ
## - テスト（-s でスクリプトを実行）のときは user://test_saves/ を使い、オートセーブは既定で切る（ユーザーのセーブを消さない）。
##   環境変数 NPB_TEST_SAVE_DIR があればそこを使う（tools/run_tests.py がテストごとに別のフォルダを渡す。同時に流してもぶつからない）

const VERSION := 1
const SLOTS: Array[String] = ["slot1", "slot2", "slot3"]
const AUTO := "auto"
const DIR := "user://saves"
const TEST_DIR := "user://test_saves"
## 一覧の名前
const SLOT_NAMES := {"slot1": "スロット1", "slot2": "スロット2", "slot3": "スロット3", "auto": "オートセーブ"}

## テストのセーブの場所を渡す環境変数（tools/run_tests.py が設定する）
const TEST_DIR_ENV := "NPB_TEST_SAVE_DIR"

## 保存先（空なら DIR、テスト中は test_dir()）
static var dir := ""
## オートセーブを書くか（null＝既定：テスト中は書かない）
static var autosave_enabled: Variant = null


static func save_dir() -> String:
	if dir.is_empty():
		dir = test_dir() if _under_test() else DIR
	return dir


## テストのセーブの場所：NPB_TEST_SAVE_DIR があればそこ、無ければ fallback
static func test_dir(fallback := TEST_DIR) -> String:
	var env := OS.get_environment(TEST_DIR_ENV)
	return fallback if env.is_empty() else env


static func is_autosave_enabled() -> bool:
	if autosave_enabled == null:
		autosave_enabled = not _under_test()
	return bool(autosave_enabled)


## -s（--script）でテストを実行している（メインループがスクリプト付きの SceneTree）
static func _under_test() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null


## 一覧に出す枠（スロット1〜3、オート）
static func all_slots() -> Array[String]:
	var result: Array[String] = SLOTS.duplicate()
	result.append(AUTO)
	return result


static func path(slot: String) -> String:
	return save_dir().path_join(slot + ".json")


static func info_path(slot: String) -> String:
	return save_dir().path_join(slot + "_info.json")


## 枠に保存する。だめなら理由の文（成功は空）
static func save(slot: String) -> String:
	# オートセーブの枠は早送りの途中でも書ける（GameState.can_autosave。作業74）
	if not (GameState.can_autosave() if slot == AUTO else GameState.can_save()):
		return GameState.save_block_reason()
	var header := {"version": VERSION, "slot": slot,
		"saved_at": Time.get_datetime_string_from_system(false, true), "summary": GameState.save_summary()}
	var full := header.duplicate()
	full["state"] = GameState.to_save()
	DirAccess.make_dir_recursive_absolute(save_dir())
	var error := _write(path(slot), JSON.stringify(full, "", false, true))
	if error.is_empty():
		error = _write(info_path(slot), JSON.stringify(header, "", false, true))
	return error


## オートセーブ（書けないときは何もしない）
static func autosave() -> void:
	if is_autosave_enabled() and GameState.can_autosave():
		var error := save(AUTO)
		if not error.is_empty():
			push_warning("オートセーブできませんでした: " + error)


## 枠の概要 {version, slot, saved_at, summary}。空き・読めない枠は {}
static func info(slot: String) -> Dictionary:
	var parsed: Variant = _read(info_path(slot))
	if parsed is Dictionary and parsed.has("summary"):
		return parsed
	if not FileAccess.file_exists(path(slot)):
		return {}
	parsed = _read(path(slot))
	if not parsed is Dictionary:
		return {}
	var header: Dictionary = parsed.duplicate()
	header.erase("state")
	return header


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## セーブが1つでもあるか（タイトルの「続きから」）
static func has_any() -> bool:
	for slot in all_slots():
		if exists(slot):
			return true
	return false


## 枠から読み込んで再開する。だめなら理由の文（成功は空）
static func load_slot(slot: String) -> String:
	if not exists(slot):
		return "%sにはセーブがありません" % SLOT_NAMES.get(slot, slot)
	var parsed: Variant = _read(path(slot))
	if not parsed is Dictionary or not parsed.get("state") is Dictionary:
		return "%sのセーブを読めません（ファイルが壊れています）" % SLOT_NAMES.get(slot, slot)
	if int(parsed.get("version", 0)) > VERSION:
		return "新しい版のセーブなので読めません（版 %d）" % int(parsed["version"])
	GameState.load_state(ints(parsed["state"]))
	return ""


## 枠を消す（テスト用）
static func delete(slot: String) -> void:
	for p in [path(slot), info_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## 一覧の1行目（例：「2008年 6月15日　阪神　32勝 25敗 1分（セ・リーグ 2位）」）
static func summary_text(header: Dictionary) -> String:
	var s: Dictionary = header.get("summary", {})
	if s.is_empty():
		return "（空き）"
	return str(s.get("text", ""))


# --- JSON の補助 -----------------------------------------------------------------------

## JSON で小数になった整数を int に戻す（SaveUtil.ints）
static func ints(v: Variant) -> Variant:
	return SaveUtil.ints(v)


static func _write(file_path: String, text: String) -> String:
	# 書きかけで壊れないよう、いったん別名に書いてから置き換える
	var tmp := file_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "保存できませんでした（%s）" % error_string(FileAccess.get_open_error())
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	var err := DirAccess.rename_absolute(tmp, file_path)
	if err == OK:
		_sync_web_fs()
	return "" if err == OK else "保存できませんでした（%s）" % error_string(err)


## ブラウザの IndexedDB に即時フラッシュ同期
static func _sync_web_fs() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"""
			if (typeof FS !== 'undefined' && FS.syncfs) {
				FS.syncfs(false, function(err) {
					if (err) console.error('IndexedDB sync error:', err);
				});
			}
			"""
		)


## 指定枠のセーブデータ（JSON文字列）を取得（エクスポート用）
static func export_json(slot: String) -> String:
	if not exists(slot):
		return ""
	return FileAccess.get_file_as_string(path(slot))


## 外部JSON文字列を検証し、指定枠に保存（インポート用）。成功なら空文字、失敗ならエラー文
static func import_json(slot: String, json_text: String) -> String:
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary or not parsed.get("state") is Dictionary:
		return "セーブデータの形式が正しくありません"
	var ver: int = int(parsed.get("version", 0))
	if ver > VERSION:
		return "新しいバージョンのセーブデータ（v%d）のため読み込めません" % ver
	var header := {
		"version": ver,
		"slot": slot,
		"saved_at": parsed.get("saved_at", Time.get_datetime_string_from_system(false, true)),
		"summary": parsed.get("summary", {})
	}
	DirAccess.make_dir_recursive_absolute(save_dir())
	var err := _write(path(slot), JSON.stringify(parsed, "", false, true))
	if err.is_empty():
		err = _write(info_path(slot), JSON.stringify(header, "", false, true))
	return err


## セーブデータをファイルとして端末にダウンロード保存（Web/PC両対応）
static func download_save_file(slot: String) -> String:
	var content := export_json(slot)
	if content.is_empty():
		return "エクスポートするセーブデータがありません"
	var filename := "npb_save_%s_%s.json" % [slot, Time.get_date_string_from_system().replace("-", "")]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(content.to_utf8_buffer(), filename, "application/json")
		return ""
	else:
		var export_dir := "user://exports"
		DirAccess.make_dir_recursive_absolute(export_dir)
		var target_path := export_dir.path_join(filename)
		var f := FileAccess.open(target_path, FileAccess.WRITE)
		if f == null:
			return "書き出しに失敗しました"
		f.store_string(content)
		f.close()
		OS.shell_open(ProjectSettings.globalize_path(export_dir))
		return ""


static func _read(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(file_path))
