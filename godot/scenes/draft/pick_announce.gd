class_name PickAnnounce
extends PanelContainer
## ドラフトの指名発表の札（docs/AUTORUN.md 作業28）。テレビ中継の発表画面のように、白地の札の上に
## 球団カラーの帯（ゲームの紋章 TeamEmblem と球団名、右に「第N巡選択希望選手」）→ 少し間をおいて選手名を大きく →
## 守備位置・出身校、の順に出す。実在のロゴ・スポンサーは使わない。
## 読み上げの文と部品（DraftVoice に渡す）もここで作る：
## 「第1巡選択希望選手、千葉ロッテ、鈴木泰成、投手、青山学院大学」
##
## 使い方：PickAnnounce.info_for(draft, rec, 自球団) で中身を作り、add_child したあと play(info, 名前までの秒, 経歴までの秒)

const WIDTH := 840.0
const NAME_SIZE := 66
## 発表のときの球団の呼び方 [表示, 読み]（中継の言い方。略称より正式に近い）
const TEAM_CALLS := {
	"読売ジャイアンツ": ["読売", "よみうり"],
	"阪神タイガース": ["阪神", "はんしん"],
	"中日ドラゴンズ": ["中日", "ちゅうにち"],
	"横浜ベイスターズ": ["横浜", "よこはま"],
	"横浜DeNAベイスターズ": ["横浜DeNA", "よこはまディーエヌエー"],
	"広島東洋カープ": ["広島東洋", "ひろしまとうよう"],
	"東京ヤクルトスワローズ": ["東京ヤクルト", "とうきょうヤクルト"],
	"埼玉西武ライオンズ": ["埼玉西武", "さいたませいぶ"],
	"オリックス・バファローズ": ["オリックス", "オリックス"],
	"福岡ソフトバンクホークス": ["福岡ソフトバンク", "ふくおかソフトバンク"],
	"北海道日本ハムファイターズ": ["北海道日本ハム", "ほっかいどうにっぽんハム"],
	"千葉ロッテマリーンズ": ["千葉ロッテ", "ちばロッテ"],
	"東北楽天ゴールデンイーグルス": ["東北楽天", "とうほくらくてん"],
}
## 名前の読み（ふりがな）を足すファイル（任意。{"名前": "よみ"}）。候補に kana・yomi があればそちらを使う
const READINGS_PATH := "user://voice/readings.json"

static var _readings: Dictionary

var info := {}
var _name_label: Label
var _sub_label: Label
var _tween: Tween
var _revealed := false


## 発表の中身 {team, call, call_reading, round, ikusei, round_text, name, reading, pos, school, mine, note}
static func info_for(d: Draft, rec: Dictionary, user_team: String, note := "") -> Dictionary:
	var c: Dictionary = d.by_id.get(rec["id"], {})
	var team: String = rec["team"]
	var call: Array = TEAM_CALLS.get(team, [GameData.short_name(team), GameData.short_name(team)])
	var at_round := int(rec.get("round", 1))
	var ikusei := bool(rec.get("ikusei", false))
	var name := str(c.get("name", ""))
	return {"team": team, "call": call[0], "call_reading": call[1], "round": at_round, "ikusei": ikusei,
		"round_text": ("育成選手 " if ikusei else "") + "第%d巡選択希望選手" % at_round, "name": name,
		"reading": reading_of(c), "pos": str(c.get("pos", "")), "school": str(c.get("school", "")),
		"mine": team == user_team, "note": note}


## 名前の読み：候補の kana・yomi → 読みのファイル → 名前（空白は詰める）
static func reading_of(c: Dictionary) -> String:
	for key: String in ["kana", "yomi"]:
		if not str(c.get(key, "")).is_empty():
			return str(c[key])
	var name := str(c.get("name", ""))
	if _readings == null:
		_readings = {}
		if FileAccess.file_exists(READINGS_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(READINGS_PATH))
			if parsed is Dictionary:
				_readings = parsed
	if _readings.has(name):
		return str(_readings[name])
	return name.replace(" ", "").replace("　", "")


## 読み上げの部品 [{key, text}]（DraftVoice。wav のフォルダでは key.wav があれば録音を使う）
static func voice_parts(i: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var prefix := "ikusei_round_" if i["ikusei"] else "round_"
	parts.append({"key": prefix + str(i["round"]),
		"text": ("育成選手、" if i["ikusei"] else "") + "第%d巡選択希望選手" % i["round"]})
	parts.append({"key": "team_" + GameData.short_name(i["team"]), "text": i["call_reading"]})
	parts.append({"key": "name_" + str(i["name"]).replace(" ", ""), "text": i["reading"]})
	parts.append({"key": "pos_" + str(i["pos"]), "text": i["pos"]})
	if not str(i["school"]).is_empty():
		parts.append({"key": "school_" + str(i["school"]), "text": i["school"]})
	return parts


## 読み上げの文（表示・テスト用）
static func phrase(i: Dictionary) -> String:
	var texts: Array[String] = []
	for part in voice_parts(i):
		texts.append(str(part["text"]))
	return "、".join(texts)


func play(p_info: Dictionary, name_delay: float, sub_delay: float) -> void:
	info = p_info
	_build()
	_name_label.modulate.a = 0.0
	_sub_label.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_name_label, "modulate:a", 1.0, 0.18).set_delay(name_delay)
	_tween.tween_property(_name_label, "scale", Vector2.ONE, 0.25).from(Vector2(1.25, 1.25)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(name_delay)
	_tween.tween_property(_sub_label, "modulate:a", 1.0, 0.2).set_delay(sub_delay)
	_tween.tween_callback(func() -> void: _revealed = true).set_delay(sub_delay + 0.2)


## 名前・経歴をすぐ出す
func reveal_all() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_name_label.modulate.a = 1.0
	_name_label.scale = Vector2.ONE
	_sub_label.modulate.a = 1.0
	_revealed = true


func is_revealed() -> bool:
	return _revealed


func shown_name() -> String:
	return _name_label.text if _name_label != null and _name_label.modulate.a > 0.5 else ""


func _build() -> void:
	var palette := UiTheme.team_palette(info["team"])
	var mine: bool = info["mine"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(10)
	style.set_border_width_all(4 if mine else 2)
	style.border_color = Color("e0a800") if mine else Color("c9ced6")
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	# 上の帯：紋章・球団名・第N巡選択希望選手
	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = palette.main
	band_style.corner_radius_top_left = 8
	band_style.corner_radius_top_right = 8
	band_style.border_width_bottom = 5
	band_style.border_color = palette.sub
	band_style.content_margin_left = 16
	band_style.content_margin_right = 16
	band_style.content_margin_top = 8
	band_style.content_margin_bottom = 8
	band.add_theme_stylebox_override("panel", band_style)
	box.add_child(band)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	band.add_child(row)
	var emblem := TeamEmblem.new()
	emblem.custom_minimum_size = Vector2(64, 64)
	emblem.setup(palette, GameData.short_name(info["team"]).substr(0, 2))
	row.add_child(emblem)
	var team_label := Label.new()
	team_label.text = str(info["call"])
	team_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	team_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.heading(team_label, 36, palette.on_main, UiTheme.outline_for(palette.on_main, palette.main), 6, false)
	row.add_child(team_label)
	var round_label := Label.new()
	round_label.text = str(info["round_text"])
	round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	round_label.add_theme_font_override("font", UiTheme.font(800))
	round_label.add_theme_font_size_override("font_size", 20)
	round_label.add_theme_color_override("font_color", UiTheme.TEXT)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color.WHITE
	pill.set_corner_radius_all(16)
	pill.content_margin_left = 14
	pill.content_margin_right = 14
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	round_label.add_theme_stylebox_override("normal", pill)
	row.add_child(round_label)
	# 本文：注記・選手名・守備位置と出身校
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(body)
	box.add_child(margin)
	var note := str(info.get("note", ""))
	if mine:
		note = ("★ 自球団の指名" + ("　" + note if not note.is_empty() else ""))
	var note_label := Label.new()
	note_label.text = note
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.custom_minimum_size = Vector2(0, 26)
	note_label.add_theme_font_override("font", UiTheme.font(800))
	note_label.add_theme_font_size_override("font_size", 18)
	note_label.add_theme_color_override("font_color", Color("c27c00") if mine else UiTheme.TEXT_SUB)
	body.add_child(note_label)
	_name_label = Label.new()
	_name_label.text = str(info["name"])
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_name_label, NAME_SIZE, Color("15171a"), Color.WHITE, 2, false)
	_name_label.pivot_offset = Vector2(WIDTH * 0.5, NAME_SIZE * 0.7)
	body.add_child(_name_label)
	_sub_label = Label.new()
	_sub_label.text = "%s　　%s" % [info["pos"], info["school"]]
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.fit_label(_sub_label)
	UiTheme.heading(_sub_label, 28, Color("3a4049"), Color.WHITE, 2, false)
	body.add_child(_sub_label)
