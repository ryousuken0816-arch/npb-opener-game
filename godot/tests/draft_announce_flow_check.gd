extends SceneTree
## ドラフトの外れ1位の発表で「次へ」を押しても固まらないかの確認（docs/AUTORUN.md 作業42。ヘッドレス可、約5分）。
## 不具合：2020年（ソフトバンク）、自球団の1位（伊藤大海）が決まったあと CPU球団の外れ1位の発表で「次へ」を押すとフリーズした。
## 原因：発表の最後の部品を OS の音声合成で読み終えた瞬間に「次へ」で tts_stop() を呼ぶと、Godot 4.7 の Windows（OneCore）は
## 読み終えたときの後始末（別のスレッド）と止める処理（メインのスレッド）が同じ MediaPlayer を同時に閉じて固まる。
## → DraftVoice は終わり際の OS の読み上げを止めず、終わるまで次の OS の読み上げを始めない。
##
## 1) 読み上げのまね（tts_sim。音を出さない）で、止めてよい・止めない（終わり際）の決まりと、終わりの合図が来ないときに先へ進むこと
## 2) 1位の入札から外れ1位がすべて決まるまで、発表・抽選（3D）・結果を実時間で進める。自球団が
##    単独で確定／競合して当選／競合して外れ のあと CPU球団に外れ1位が続く年（2020年 ソフトバンク、2019年 ロッテ）で、
##    進め方（「次へ」で1件ずつ・読み上げが終わる瞬間に押す／時間で自動・早送り・Ⓑで発表を飛ばす）と
##    読み上げ（オフ／終わりの合図が来る／来ない）を組み合わせる。止まらずにウェーバーへ進み、終わり際に止めていないこと。
##    抽選は乱数なので、入札の直前の状態に戻して乱数を変え、狙った結果が出るまでくり返す
##
##   godot --headless --path godot -s res://tests/draft_announce_flow_check.gd -- [出力先]
##   （出力先はウィンドウ付きのときだけ。2020年の最初の通りだけ流し、CPU球団の外れ1位の発表の札をスクショ。音は出さない）

const CASES := [
	{"year": 2020, "team": "福岡ソフトバンクホークス", "flows": [
		{"kind": "single", "mode": "click", "voice": "end"},
		{"kind": "win", "mode": "fast", "voice": "never"},
		{"kind": "lose", "mode": "skip", "voice": "off"},
		{"kind": "single", "mode": "auto", "voice": "never"},
		{"kind": "lose", "mode": "click", "voice": "end"},
	]},
	{"year": 2019, "team": "千葉ロッテマリーンズ", "flows": [
		{"kind": "win", "mode": "click", "voice": "never"},
		{"kind": "lose", "mode": "auto", "voice": "end"},
	]},
]
## 狙った抽選の結果が出るまでのくり返しの上限
const MAX_TRIES := 16
## 演出の時間を速める（読み上げのまね・発表・3D抽選も同じ速さで進む）
const TIME_SCALE := 3.0
## 何も変わらないまま、この秒（実時間）が過ぎたら止まったとみなす
const STUCK_SEC := 25.0
## 読み上げのまねの速さ（1文字あたりの秒。DraftVoice の見込みより遅い＝本物に近い）
const SIM_SEC_PER_CHAR := 0.12
## 止めたときの本当の残りがこれより短ければ「終わり際に止めた」（固まる場面）
const DANGER_SEC := 0.3

var _out := ""
var _shot_taken := false
var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _dv: GDScript
var _settings: GDScript
var _first := 0
var _waiver := 1


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	else:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		AudioServer.set_bus_mute(0, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 and DisplayServer.get_name() != "headless" else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_dv = load("res://scenes/hub/draft_view.gd")
	_settings = load("res://scripts/game_settings.gd")
	_first = _ds.Stage["FIRST"]
	_waiver = _ds.Stage["WAIVER"]
	_settings.call("reset")
	if _out.is_empty():
		await _check_voice_rule()
	Engine.time_scale = TIME_SCALE
	for c: Dictionary in CASES:
		await _check_year(c["year"], c["team"], c["flows"] if _out.is_empty() else c["flows"].slice(0, 1))
		if not _out.is_empty():
			break
	Engine.time_scale = 1.0
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


# --- 1) 読み上げのまねで、止める・止めないの決まり ----------------------------------------------------

func _check_voice_rule() -> void:
	print("== 読み上げ：終わり際に止めない ==")
	_settings.call("set_value", "voice", "backend", "os")
	var voice: Node = load("res://scripts/draft_voice.gd").new()
	root.add_child(voice)
	await _frames(1)
	voice.set("muted", false)
	voice.set("tts_sim", {"sec_per_char": SIM_SEC_PER_CHAR})
	var parts: Array = [{"key": "round_1", "text": "第1巡選択希望選手"}, {"key": "team_ヤクルト", "text": "とうきょうヤクルト"},
		{"key": "name_鈴木昭太", "text": "すずきしょうた"}, {"key": "pos_投手", "text": "投手"},
		{"key": "school_法政大学", "text": "法政大学"}]
	# 読み始めてすぐ止める → 止める
	voice.call("speak", parts)
	await _wait(0.6)
	voice.call("stop")
	var log: Array = voice.get("tts_log")
	_check(not log.is_empty() and log[-1]["op"] == "stop", "読み始めてすぐ（%.1f秒）なら OS の読み上げを止める" % 0.6)
	# 読み終わる直前に止める → 止めない（自然に終わらせる）
	voice.call("speak", parts)
	var total := 0.0
	for p: Dictionary in parts:
		total += str(p["text"]).length() + 1
	await _wait(total * SIM_SEC_PER_CHAR - 0.15)
	voice.call("stop")
	log = voice.get("tts_log")
	_check(log[-1]["op"] == "hold" and float(log[-1]["left"]) > 0.0,
		"読み終わる直前（残り%.2f秒）なら止めない" % float(log[-1]["left"]))
	# 止めなかった読み上げが続いている間は、次の読み上げを始めない（重ならない）
	voice.call("speak", parts)
	await _frames(2)
	var speaks := 0
	for e: Dictionary in voice.get("tts_log"):
		if e["op"] == "speak":
			speaks += 1
	_check(speaks == 2, "前の読み上げが終わるまで次の OS の読み上げを始めない")
	await _wait(1.0)
	speaks = 0
	for e: Dictionary in voice.get("tts_log"):
		if e["op"] == "speak":
			speaks += 1
	_check(speaks == 3 and voice.call("is_busy"), "前の読み上げが終わったら次を読む")
	# 終わりの合図が来ない（話し中のまま）：止めず、次の読み上げは上限まで待ってあきらめる
	voice.call("stop")
	await _wait(3.0)
	voice.set("tts_sim", {"never_end": true})
	voice.call("speak", parts)
	await _wait(2.6)  # 見込み（35文字×0.08＝2.8秒）の残りが0.8秒を切ったあと
	voice.call("stop")
	_check(voice.get("tts_log")[-1]["op"] == "hold", "終わりの合図が来ないまま見込みの長さを過ぎたら止めない")
	voice.call("speak", parts)
	await _wait(5.5)  # DraftVoice.TTS_BUSY_WAIT ＋ 少し
	_check(not voice.call("is_busy"), "終わりの合図が来なくても読み上げは上限で終わる（発表を待たせ続けない）")
	# 録音の出身は「〜大学」が無ければ「〜大」
	var dir := "user://test_voice_flow_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	wav.save_to_wav(dir.path_join("school_法政大.wav"))
	var path: String = voice.call("wav_path", dir, "school_法政大学")
	_check(path.get_file() == "school_法政大.wav", "録音の出身は「法政大学」が無ければ「法政大」を使う（%s）" % path.get_file())
	DirAccess.remove_absolute(dir.path_join("school_法政大.wav"))
	DirAccess.remove_absolute(dir)
	voice.call("stop")
	voice.queue_free()
	_settings.call("reset")


# --- 2) 外れ1位まで発表を実時間で進める ----------------------------------------------------------------

func _check_year(year: int, team: String, flows: Array) -> void:
	print("\n== %d年 %s ==" % [year, _gd.short_name(team)])
	_gs.new_game(team, year)
	var ok: bool = _gs.skip_to_phase(_gs.Phase.DRAFT)
	_check(ok and _gs.draft() != null, "%d年オフのドラフトに飛べる" % year)
	if _gs.draft() == null:
		return
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	var snap: Dictionary = _gs.draft().to_save().duplicate(true)
	for flow: Dictionary in flows:
		await _play_flow(hub, year, snap, flow)


func _play_flow(hub: Node, year: int, snap: Dictionary, flow: Dictionary) -> void:
	var kind: String = flow["kind"]
	var label := "%d年 %s・%s・読み上げ%s" % [year, _kind_text(kind), _mode_text(flow["mode"]), _voice_text(flow["voice"])]
	var view: Node = null
	var got := ""
	for i in MAX_TRIES:
		_gs.league.draft = _ds.from_save(snap.duplicate(true))
		_gs.draft().get("_rng").seed = hash("%d-%s-%s-%d" % [year, kind, flow["mode"], i])
		view = await _open(hub, flow)
		got = _bid(view, kind)
		if got == kind:
			break
		_quiet_finish(view)
	_check(got == kind, "%s：自球団が「%s」になる" % [label, _kind_text(kind)])
	if got != kind:
		return
	var result := await _drive(view, flow)
	var d: RefCounted = _gs.draft()
	var me: String = _gs.team
	_check(result["stuck"].is_empty() and d.stage == _waiver and d.teams_without_first().is_empty(),
		"%s：止まらずに全球団の1位が決まりウェーバーへ（入札%d回、自球団が決まったあとの外れ1位%d回、%.0f秒）%s"
		% [label, d.wave - 1, result["after_mine"], result["sec"], result["stuck"]])
	_check(d.by_id.has(d.first_pick_of(me)), "%s：自球団の1位（%s）" % [label,
		d.by_id.get(d.first_pick_of(me), {}).get("name", "?")])
	if flow["mode"] != "skip":
		var bids := 12
		for lot: Dictionary in d.lotteries:
			bids += lot["teams"].size() - 1
		_check(result["cards"] == bids, "%s：入札をすべて1球団ずつ発表（%d／%d）" % [label, result["cards"], bids])
	else:
		_check(result["cards"] < 12, "%s：Ⓑで飛ばすと他球団の発表を出さない（発表%d）" % [label, result["cards"]])
	if flow["voice"] != "off":
		var danger: Array = []
		var holds := 0
		for e: Dictionary in view.call("voice").get("tts_log"):
			if e["op"] == "stop" and float(e["left"]) < DANGER_SEC:
				danger.append("%.2f" % float(e["left"]))
			if e["op"] == "hold":
				holds += 1
		_check(danger.is_empty(), "%s：OS の読み上げを終わり際に止めていない（止めなかった%d回、終わり際の停止%s）"
			% [label, holds, danger])


## ドラフトの画面を開き直し、読み上げ・発表の設定をする
func _open(hub: Node, flow: Dictionary) -> Node:
	hub.call("_close_sub_screen")
	await _frames(1)
	_settings.call("reset")
	_settings.call("set_value", "voice", "backend", "os")
	_settings.call("set_value", "voice", "enabled", flow["voice"] != "off")
	_settings.call("set_value", "voice", "volume", 0)  # 自球団のチャイムを鳴らさない
	hub.call("_open_sub_screen", "draft")
	await _frames(2)
	var view: Node = _find_draft_view(hub)
	view.call("finish_overlays")  # 開幕の演出
	view.set("_fast", flow["mode"] == "fast")
	view.set("_announce_skip", false)
	var voice: Node = view.call("voice")
	voice.call("stop")
	voice.set("_tts_elapsed", -1.0)  # 前の通りのまね（合図が来ない読み上げ）を持ち越さない
	voice.set("_sim_left", 0.0)
	voice.set("muted", false)
	voice.set("tts_sim", {"sec_per_char": SIM_SEC_PER_CHAR, "never_end": flow["voice"] == "never"})
	voice.set("tts_log", [] as Array[Dictionary])
	return view


## 1位に入札する（kind に合う候補）。戻り値は実際の結果
func _bid(view: Node, kind: String) -> String:
	var d: RefCounted = _gs.draft()
	var me: String = _gs.team
	var bids: Dictionary = d.cpu_first_bids()
	var count := {}
	for t: String in bids:
		count[bids[t]] = int(count.get(bids[t], 0)) + 1
	var target := ""
	for c: Dictionary in view.call("sorted_candidates", d):
		if not str(c["picked_by"]).is_empty():
			continue
		var n := int(count.get(c["id"], 0))
		if kind == "single" and n == 0:
			target = c["id"]
			break
		var better := n < int(count.get(target, 0)) if kind == "win" else n > int(count.get(target, 0))
		if kind != "single" and n > 0 and (target.is_empty() or better):
			target = c["id"]
	view.call("select_candidate", target)
	view.call("press_action")
	for lot: Dictionary in d.lotteries:
		if lot["wave"] == 1 and me in lot["teams"]:
			return "win" if lot["winner"] == me else "lose"
	return "single" if d.first_pick_of(me) == target else "?"


## 狙った結果でなかったとき：演出を出さずに終わらせる（入札の直前に戻すので中身は捨てる）
func _quiet_finish(view: Node) -> void:
	view.set("instant", true)
	view.call("finish_overlays")
	view.set("instant", false)
	view.call("voice").call("stop")


## 演出を進め方どおりに進める。自球団が外れたら画面で入札し直す。
## 戻り値 {stuck, after_mine（自球団が決まったあとの入札の回数）, cards（出た発表の数）, sec}
func _drive(view: Node, flow: Dictionary) -> Dictionary:
	var d: RefCounted = _gs.draft()
	var me: String = _gs.team
	var mode: String = flow["mode"]
	var voice: Node = view.call("voice")
	var out := {"stuck": "", "after_mine": 0, "cards": 0, "sec": 0.0}
	var t0 := Time.get_ticks_msec()
	var last_change := t0
	var last_key := ""
	var shown_at := 0.0
	var mine_wave := 0
	var last_item: Variant = null
	var now := t0
	while true:
		await process_frame
		var prev := now
		now = Time.get_ticks_msec()
		var visible: bool = view.call("overlay_visible")
		var item: Dictionary = view.get("_overlay").get_meta("item", {}) if visible else {}
		if mine_wave == 0 and not d.first_pick_of(me).is_empty():
			mine_wave = d.wave - 1
		var key := "%s|%d|%d|%d|%s" % [item.get("kind", "-"), d.wave, d.picks.size(), view.get("_overlay_queue").size(),
			str(item.get("revealed", false))]
		if visible and not is_same(item, last_item):
			last_item = item
			shown_at = 0.0
			if item.get("kind", "") == "announce" and int(item["rec"].get("round", 0)) == 1:
				out["cards"] += 1
		if key != last_key:
			last_key = key
			last_change = now
		# 1位が決まったら終わり（ウェーバーの CPU の指名の発表が続けて出ることがある：早送り）
		if d.stage != _first and (not visible or (item.get("kind", "") == "announce"
				and int(item["rec"].get("round", 0)) != 1)):
			break
		if now - last_change > STUCK_SEC * 1000.0:
			out["stuck"] = "（止まった：演出%s・入札%d回目・待ちの演出%d・読み上げ中%s）" % [item.get("kind", "なし"), d.wave,
				view.get("_overlay_queue").size(), voice.call("is_busy")]
			break
		if not visible:
			if d.stage == _first and d.first_pick_of(me).is_empty():
				# 自球団が外れた：外れ1位を画面で入札（評価の高い順の先頭）
				for c: Dictionary in view.call("sorted_candidates", d):
					if str(c["picked_by"]).is_empty():
						view.call("select_candidate", c["id"])
						break
				view.call("press_action")
			continue
		shown_at += (now - prev) / 1000.0 * TIME_SCALE
		var kind: String = item.get("kind", "")
		if kind == "announce":
			var card: Object = view.call("announce_card")
			if not _out.is_empty() and not _shot_taken and mine_wave > 0 and d.wave - 1 > mine_wave 					and card != null and card.call("is_revealed"):
				await _shot("rebid_announce")
				last_change = Time.get_ticks_msec()
			match mode:
				"auto":
					pass  # 時間で次へ
				"skip":
					view.call("back")  # Ⓑ
				"fast":
					if card != null and card.call("is_revealed"):
						view.get("_overlay_next").pressed.emit()
				"click":
					# 読み上げが終わる瞬間に押す（読み上げが無い・合図が来ないときは名前が出たら少し待って押す）
					var left := float(voice.get("_sim_left"))
					var tts_on: bool = float(voice.get("_tts_elapsed")) >= 0.0
					var ready: bool = card != null and card.call("is_revealed")
					if ready and ((tts_on and left > 0.0 and left < 0.12) or (not tts_on and shown_at > 0.5)
							or (left == INF and shown_at > 1.0)):
						view.get("_overlay_next").pressed.emit()
			continue
		# 抽選（1回目で結果、2回目で次へ）・結果の一覧
		if shown_at > 0.4:
			view.get("_overlay_next").pressed.emit()
			shown_at = 0.0
	if mine_wave > 0:
		out["after_mine"] = d.wave - 1 - mine_wave
	out["sec"] = (Time.get_ticks_msec() - t0) / 1000.0
	return out


func _kind_text(kind: String) -> String:
	return {"single": "単独で確定", "win": "競合して当選", "lose": "競合して外れ"}.get(kind, "不明")


func _mode_text(mode: String) -> String:
	return {"click": "次へで1件ずつ", "auto": "時間で自動", "fast": "早送り", "skip": "発表を飛ばす"}.get(mode, mode)


func _voice_text(v: String) -> String:
	return {"off": "オフ", "end": "あり（終わりの合図が来る）", "never": "あり（終わりの合図が来ない）"}.get(v, v)


func _find_draft_view(node: Node) -> Node:
	if node.get_script() == _dv:
		return node
	for child in node.get_children():
		var found := _find_draft_view(child)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	_shot_taken = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)


## ゲームの時間で sec 秒待つ（Engine.time_scale を掛けた時間）
func _wait(sec: float) -> void:
	await create_timer(sec).timeout
