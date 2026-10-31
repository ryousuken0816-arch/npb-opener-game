extends SceneTree
## ドラフトの指名発表（中継風の札と読み上げ）の確認（docs/AUTORUN.md 作業28。ヘッドレス可、約1分半）。
## 読み上げはテストでは音を出さない（DraftVoice.muted）。どこから読むかの段取り（last_plan）で確かめる。
## 1) 読み上げの文：「第1巡選択希望選手、とうほくらくてん、宗山塁、内野手、明治大学」の形
## 2) 声の差し替え：wav のフォルダに round_2.wav と team_ロッテ.wav だけ置くと、その2つは録音・残りは OS の音声合成。
##    VOICEVOX 互換のエンジンにつながらない（閉じたポート）と OS の音声合成に戻る
## 3) 2024年開始（巨人）：宗山に入札 → 全球団の1位の入札が1球団ずつ札で出る（球団の帯 → 少し遅れて選手名 → 経歴）。
##    時間が来ると自動で次へ。Ⓐで名前をすぐ出す → もう一度で次へ。Ⓑで発表を飛ばすと抽選（3D）へ。
##    2位以降：CPU球団の指名が1つずつ発表され、読み上げの文が「第2巡選択希望選手、…」。早送りで発表が短くなる。
##    Ⓑで飛ばすと自球団の番まで発表しない。自球団の指名は「★ 自球団の指名」で長めに出る
##
##   godot --headless --path godot -s res://tests/draft_announce_check.gd -- [出力先]
##   （出力先はウィンドウ付きのときだけ。1位の入札の発表と自球団の指名の発表をスクショ）

const USER := "読売ジャイアンツ"
const MUNETAKA := "宗山 塁"
const LIMIT_SEC := 30.0

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _dv: GDScript
var _settings: GDScript
var _announce: GDScript


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	else:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_dv = load("res://scenes/hub/draft_view.gd")
	_settings = load("res://scripts/game_settings.gd")
	_announce = load("res://scenes/draft/pick_announce.gd")
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_settings.call("reset")
	await _check_voice()
	_settings.call("reset")
	await _check_2024()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


# --- 1)・2) 読み上げの文と声の差し替え -------------------------------------------------------------

func _check_voice() -> void:
	print("== 読み上げ ==")
	var info := {"team": "東北楽天ゴールデンイーグルス", "call": "東北楽天", "call_reading": "とうほくらくてん", "round": 1,
		"ikusei": false, "name": MUNETAKA, "reading": "宗山塁", "pos": "内野手", "school": "明治大学", "mine": false}
	var text: String = _announce.call("phrase", info)
	_check(text == "第1巡選択希望選手、とうほくらくてん、宗山塁、内野手、明治大学", "読み上げの文（%s）" % text)
	var voice: Node = load("res://scripts/draft_voice.gd").new()
	root.add_child(voice)
	await _frames(1)
	_check(voice.get("muted"), "テストでは音を出さない")
	var info2 := info.duplicate()
	info2["team"] = "千葉ロッテマリーンズ"
	info2["call_reading"] = "ちばロッテ"
	info2["round"] = 2
	var parts: Array = _announce.call("voice_parts", info2)
	# wav のフォルダ：round_2 と team_ロッテ だけ録音がある
	var dir := "user://test_voice_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	for key: String in ["round_2", "team_ロッテ"]:
		_silent_wav().save_to_wav(dir.path_join(key + ".wav"))
	_settings.call("set_value", "voice", "wav_dir", dir)
	var plan: Array = voice.call("plan", parts, "wav")
	var srcs: Array[String] = []
	for item: Dictionary in plan:
		srcs.append(str(item["src"]) + ("(" + str(item.get("text", item.get("path", "")).get_file()) + ")"
			if item["src"] != "pause" else ""))
	_check(srcs.size() == 4 and plan[0]["src"] == "wav" and plan[2]["src"] == "wav" and plan[3]["src"] == "tts"
		and str(plan[3]["text"]) == "宗山塁、内野手、明治大学",
		"wav：録音のある部品は録音、無い部分はまとめて OS の音声合成（%s）" % " → ".join(srcs))
	for key: String in ["round_2", "team_ロッテ"]:
		DirAccess.remove_absolute(dir.path_join(key + ".wav"))
	DirAccess.remove_absolute(dir)
	var os_plan: Array = voice.call("plan", parts, "os")
	_check(os_plan.size() == 1 and os_plan[0]["src"] == "tts" and str(os_plan[0]["text"]).begins_with("第2巡選択希望選手、ちばロッテ"),
		"os：全体を一度に読む（%s）" % os_plan[0].get("text", ""))
	# VOICEVOX 互換：つながらないと OS に戻る
	_settings.call("set_value", "voice", "voicevox_url", "http://127.0.0.1:1")
	var vv_plan: Array = voice.call("plan", parts, "voicevox")
	_check(vv_plan[0]["engine"] == "voicevox", "voicevox：最初は VOICEVOX 互換のエンジンで読む段取り")
	voice.call("probe_voicevox")
	var t0 := Time.get_ticks_msec()
	while not voice.get("voicevox_down") and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	var after: Array = voice.call("plan", parts, "voicevox")
	_check(voice.get("voicevox_down") and after[0]["engine"] == "os",
		"つながらないと OS の音声合成に戻る（%.1f秒）" % ((Time.get_ticks_msec() - t0) / 1000.0))
	voice.queue_free()


func _silent_wav() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	return wav


# --- 3) 2024年・ドラフトの画面 ------------------------------------------------------------------

func _check_2024() -> void:
	print("== 2024年開始・ドラフトの画面（%s） ==" % USER)
	_gs.new_game(USER, 2024)
	_gs.skip_to_phase(_gs.Phase.RELEASE)
	_gs.release_resolve()
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_on_menu_chosen", "advance")
	await _frames(3)
	var d: RefCounted = _gs.draft()
	var view: Node = _find_draft_view(hub)
	if d == null or view == null:
		_check(false, "ドラフトの画面が開く")
		return
	view.call("finish_overlays")
	await _frames(2)
	var mune: Dictionary = _find(d, MUNETAKA)
	view.call("select_candidate", mune["id"])
	await _frames(2)
	view.call("press_action")
	await _frames(2)
	# 1位の入札の発表：入札した全球団が1球団ずつ
	var queue: Array = view.get("_overlay_queue")
	var announces := 1  # いま出ている札
	for it: Dictionary in queue:
		if it["kind"] == "announce":
			announces += 1
	_check(view.call("announcing") and announces == d.last_wave.size(),
		"1位の入札を1球団ずつ発表（%d球団分の札、入札 %d）" % [announces, d.last_wave.size()])
	var card: Control = view.call("announce_card")
	var first_team: String = card.get("info")["team"] if card != null else ""
	_check(card != null and str(card.call("shown_name")).is_empty(), "札は球団の帯から出て、選手名はまだ出ない")
	var card_id := card.get_instance_id() if card != null else 0
	await _wait_until(func() -> bool: return _revealed(card_id))
	_check(card != null and is_instance_valid(card) and card.call("shown_name") == card.get("info")["name"],
		"少し遅れて選手名・経歴が出る（%s %s）" % [_gd.short_name(first_team), card.get("info")["name"] if card != null else ""])
	await _shot("announce_bid")
	# 時間が来ると自動で次の球団へ
	await _wait_until(func() -> bool: return _card_id(view) != card_id)
	var card2: Control = view.call("announce_card")
	_check(card2 != null and card2.get("info")["team"] != first_team, "時間が来ると自動で次の球団の札へ（%s）" % \
		(_gd.short_name(card2.get("info")["team"]) if card2 != null else "なし"))
	# Ⓐ：名前をすぐ出す → もう一度で次へ
	await _accept()
	_check(card2 != null and card2.call("is_revealed") and view.call("announce_card") == card2, "Ⓐで名前・経歴をすぐ出す")
	await _accept()
	_check(view.call("announce_card") != card2, "もう一度Ⓐで次の札へ")
	# Ⓑ：発表を飛ばすと抽選（3D）へ
	view.call("back")
	await _frames(2)
	_check(not view.call("announcing") and view.call("lottery_3d") != null, "Ⓑで発表を飛ばすと抽選の3D演出へ")
	view.call("finish_overlays")
	await _frames(2)
	# 外れ1位があれば片づける（自球団が外れたら評価の高い候補に入札。発表は飛ばす）
	var guard := 0
	while d.stage == _ds.Stage["FIRST"] and guard < 10:
		guard += 1
		if d.first_pick_of(USER).is_empty():
			for c: Dictionary in view.call("sorted_candidates", d):
				if str(c["picked_by"]).is_empty():
					view.call("select_candidate", c["id"])
					break
			view.call("press_action")
		await _frames(2)
		view.call("finish_overlays")
		await _frames(2)
	_check(d.stage == _ds.Stage["WAIVER"], "全球団の1位が決まりウェーバーへ")
	# 2位以降：CPU球団の指名が1つずつ発表される
	await _wait_until(func() -> bool: return view.call("announcing") or d.is_user_turn())
	var cpu_card: Control = view.call("announce_card")
	var plan: Array = view.call("voice").get("last_plan")
	var cpu_info: Dictionary = cpu_card.get("info") if cpu_card != null else {}
	var cpu_id := cpu_card.get_instance_id() if cpu_card != null else 0
	_check(cpu_card != null and not cpu_info["mine"] and cpu_info["round"] == 2
		and not plan.is_empty() and str(plan[0].get("text", "")) == _announce.call("phrase", cpu_info),
		"CPU球団の2位の指名を発表して読み上げ（%s）" % (plan[0].get("text", "") if not plan.is_empty() else "なし"))
	var normal_total: float = view.get("_announce_total")
	# 早送り：発表が短くなる
	view.set("_fast", true)
	await _wait_until(func() -> bool: return _card_id(view) != cpu_id)
	await _wait_until(func() -> bool: return view.call("announcing") or d.is_user_turn())
	var fast_total: float = view.get("_announce_total")
	_check(view.call("announcing") and fast_total < normal_total * 0.5,
		"早送りで発表が短くなる（%.1f秒 → %.1f秒）" % [normal_total, fast_total])
	view.set("_fast", false)
	# Ⓑ：自球団の番まで発表しない
	if view.call("announcing"):
		view.call("back")
	else:
		view.call("skip_announcements")  # 発表と発表の間（Ⓑは発表の札が出ているときに効く）
	var seen_cpu := false
	var t0 := Time.get_ticks_msec()
	while not d.is_user_turn() and Time.get_ticks_msec() - t0 < LIMIT_SEC * 1000.0:
		if view.call("announcing"):
			seen_cpu = true
		await process_frame
	_check(d.is_user_turn() and not seen_cpu, "Ⓑで飛ばすと自球団の番まで他球団の指名は発表しない")
	# 自球団の指名：「★ 自球団の指名」で長めに
	for c: Dictionary in view.call("sorted_candidates", d):
		if str(c["picked_by"]).is_empty():
			view.call("select_candidate", c["id"])
			break
	view.call("press_action")
	await _frames(2)
	var mine_card: Control = view.call("announce_card")
	_check(mine_card != null and mine_card.get("info")["mine"] and float(view.get("_announce_total")) > normal_total,
		"自球団の指名は長めに発表（%.1f秒、%s）" % [float(view.get("_announce_total")),
			mine_card.get("info")["name"] if mine_card != null else "なし"])
	var mine_id := mine_card.get_instance_id() if mine_card != null else 0
	await _wait_until(func() -> bool: return _revealed(mine_id))
	await _shot("announce_mine")
	view.call("finish_overlays")


## いま出ている札のインスタンスID（無ければ 0）。消えた札をラムダで持たないように番号で比べる
func _card_id(view: Node) -> int:
	var card: Node = view.call("announce_card")
	return card.get_instance_id() if card != null else 0


func _revealed(card_id: int) -> bool:
	var card := instance_from_id(card_id)
	return card != null and card.call("is_revealed")


func _find(d: RefCounted, name: String) -> Dictionary:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c
	return {}


func _find_draft_view(node: Node) -> Node:
	if node.get_script() == _dv:
		return node
	for child in node.get_children():
		var found := _find_draft_view(child)
		if found != null:
			return found
	return null


## Ⓐ：フォーカスしたボタンに決定（ui_accept）を送る
func _accept() -> void:
	for pressed: bool in [true, false]:
		var e := InputEventAction.new()
		e.action = "ui_accept"
		e.pressed = pressed
		root.push_input(e)
		await _frames(2)


func _wait_until(cond: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < LIMIT_SEC * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
