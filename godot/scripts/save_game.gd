class_name SaveGame
extends RefCounted
## セーブ／ロード（docs/AUTORUN.md 作業6）。ゲームの状態（GameState.to_save()）を user://saves/ に JSON で保存する。
##
## - 枠：スロット1〜3（slot1〜slot3）とオートセーブ（auto。月替わり・オフの段階の切り替わりで GameState が書く）
## - ファイル：<枠>.json（{version, saved_at, summary, state}）と、一覧表示用の小さな <枠>_info.json（state なし）
## - 能力値ファイル（generated/ratings）は保存しない。ロード時にその年のファイルを読み直してから所属などを当てる
## - JSON にすると整数が小数になる（ints() で戻す）。Dictionary のキーは文字列（ゲームの状態のキーはもともと文字列）。
##   乱数の状態（64ビット）は小数にすると桁が落ちるので文字列で持つ
## - テスト（-s でスクリプトを実行）のときは user://test_saves/ を使い、オートセーブは既定で切る（ユーザーのセーブを消さない）

const VERSION := 1
const SLOTS: Array[String] = ["slot1", "slot2", "slot3"]
const AUTO := "auto"
const DIR := "user://saves"
const TEST_DIR := "user://test_saves"
## 一覧の名前
const SLOT_NAMES := {"slot1": "スロット1", "slot2": "スロット2", "slot3": "スロット3", "auto": "オートセーブ"}

## 保存先（空なら DIR、テスト中は TEST_DIR）
static var dir := ""
## オートセーブを書くか（null＝既定：テスト中は書かない）
static var autosave_enabled: Variant = null


static func save_dir() -> String:
	if dir.is_empty():
		dir = TEST_DIR if _under_test() else DIR
	return dir


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
	if not GameState.can_save():
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
	if is_autosave_enabled() and GameState.can_save():
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
	return "" if err == OK else "保存できませんでした（%s）" % error_string(err)


static func _read(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(file_path))
