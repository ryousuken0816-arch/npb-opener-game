extends SceneTree
## Web 版のドラフトの読み上げ（録音の部品をページのサーバーから取り寄せる）の確認（ヘッドレス、数秒）。
## 本物の Web 版のサーバー（tools/serve_web.py の /voice/）の代わりに、このテストの中で小さな HTTP サーバーを立てる。
## 1) Web 版でなければ置き場を調べない（web_voice_url は空のまま。段取りは今までどおり）
## 2) 置き場があるとき：段取りは部品ごとの取り寄せ（間を置いてつなぐ）。部品の URL は日本語を % でくるむ
## 3) round_2.wav と team_ロッテ.wav だけ置くと、その2つは録音が届き、残りは届かない（404）
## 4) 鳴らす：届いた2つは録音、届かなかった3つ（名前・守備位置・出身）は OS の音声合成（まね）で読み、最後まで進む
## 5) サーバーが止まっている（つながらない）ときも、全部を OS の音声合成で読んで最後まで進む
##
##   godot --headless --path godot -s res://tests/draft_voice_web_check.gd

const PORT := 18765
const DIR := "user://test_voice_web"
const LIMIT_MS := 20000

var _failures := 0
var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _settings: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = load("res://scripts/game_settings.gd")
	_settings.call("reset")
	_make_voice_dir()
	_check(_server.listen(PORT, "127.0.0.1") == OK, "テスト用の HTTP サーバー（%d）" % PORT)
	var info := {"team": "千葉ロッテマリーンズ", "call": "千葉ロッテ", "call_reading": "ちばロッテ", "round": 2,
		"ikusei": false, "name": "宗山 塁", "reading": "宗山塁", "pos": "内野手", "school": "明治大学", "mine": false}
	var parts: Array = load("res://scenes/draft/pick_announce.gd").call("voice_parts", info)

	var voice: Node = load("res://scripts/draft_voice.gd").new()
	root.add_child(voice)
	await process_frame
	_check(str(voice.get("web_voice_url")).is_empty(), "Web 版でなければ録音の置き場を調べない")
	voice.call("speak", parts)
	_check(voice.get("last_plan")[0]["src"] != "web_wav", "置き場が無いときは今までどおりの段取り")

	voice.set("web_voice_url", "http://127.0.0.1:%d/voice/" % PORT)
	voice.call("speak", parts)
	var plan: Array = voice.get("last_plan")
	var srcs: Array[String] = []
	for item: Dictionary in plan:
		srcs.append(str(item["src"]))
	_check(srcs == ["web_wav", "pause", "web_wav", "pause", "web_wav", "pause", "web_wav", "pause", "web_wav"],
		"段取りは部品ごとの取り寄せを間を置いてつなぐ（%s）" % ",".join(srcs))
	_check(str(plan[2]["url"]).ends_with("/voice/team_%E3%83%AD%E3%83%83%E3%83%86.wav"),
		"部品の URL は日本語を %% でくるむ（%s）" % plan[2]["url"])

	voice.call("fetch_web", parts)
	await _wait_fetched(voice, parts.size())
	var got: Dictionary = voice.get("web_fetched")
	var arrived: Array[String] = []
	for key: String in got:
		if got[key].get("done", false) and got[key].get("stream") != null:
			arrived.append(key)
	arrived.sort()
	_check(arrived == ["round_2", "team_ロッテ"], "置いた2つだけ録音が届く（%s）" % ",".join(arrived))
	_check(got.size() == parts.size() and got.values().all(func(g: Dictionary) -> bool: return g.get("done", false)),
		"置いていない部品も取り寄せが終わる（404）")

	# 鳴らす（音は出さず、OS の音声合成はまね）
	voice.set("muted", false)
	voice.set("tts_sim", {"sec_per_char": 0.02})
	voice.get("tts_log").clear()
	voice.call("speak", parts)
	var ok := await _wait_idle(voice)
	_check(ok, "録音と OS の声（まね）をつないで最後まで読む")
	var spoken := _spoken(voice)
	_check(spoken == 3, "届かなかった3つ（名前・守備位置・出身）だけ OS の声で読む（%d件）" % spoken)

	# サーバーが止まっている
	_server.stop()
	voice.get("tts_log").clear()
	voice.call("speak", parts)
	ok = await _wait_idle(voice)
	_check(ok and _spoken(voice) == 5, "サーバーにつながらないときは全部 OS の声で読んで最後まで進む（%d件）" % _spoken(voice))
	voice.call("stop")

	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


func _spoken(voice: Node) -> int:
	var n := 0
	for e: Dictionary in voice.get("tts_log"):
		if e["op"] == "speak":
			n += 1
	return n


func _wait_fetched(voice: Node, count: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < LIMIT_MS:
		_pump()
		var got: Dictionary = voice.get("web_fetched")
		if got.size() == count and got.values().all(func(g: Dictionary) -> bool: return g.get("done", false)):
			return
		await process_frame


func _wait_idle(voice: Node) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < LIMIT_MS:
		_pump()
		await process_frame
		if not voice.call("is_busy"):
			return true
	return false


# --- テスト用の小さな HTTP サーバー（/voice/<名前> を DIR から返す。無ければ 404） ----------------------

func _pump() -> void:
	while _server.is_listening() and _server.is_connection_available():
		_peers.append(_server.take_connection())
	for peer: StreamPeerTCP in _peers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(peer)
			continue
		var n := peer.get_available_bytes()
		if n == 0:
			continue
		var request := peer.get_utf8_string(n)
		var path := request.get_slice(" ", 1).uri_decode()
		var body := PackedByteArray()
		var code := "404 Not Found"
		if path.begins_with("/voice/"):
			var file := DIR.path_join(path.trim_prefix("/voice/"))
			if FileAccess.file_exists(file):
				body = FileAccess.get_file_as_bytes(file)
				code = "200 OK"
		var head := "HTTP/1.1 %s\r\nContent-Type: audio/wav\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" \
			% [code, body.size()]
		peer.put_data(head.to_utf8_buffer() + body)
		peer.disconnect_from_host()
		_peers.erase(peer)


func _make_voice_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	# 0.2秒の短い音
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(int(22050 * 0.2) * 2)
	wav.data = data
	for key in ["round_2", "team_ロッテ"]:
		wav.save_to_wav(DIR.path_join(key + ".wav"))
