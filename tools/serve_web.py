#!/usr/bin/env python3
"""
Godot 4 Web ビルドのローカル検証用 HTTP サーバー
同一LAN内のスマホ（iPhone Safari / Android Chrome）からも
http://<PCのローカルIP>:8000 でアクセスして実機検証できます。

ドラフトの読み上げの録音（部品ごとの <キー>.wav。godot/README.md「ドラフトの読み上げ」）があれば、
/voice/ でスマホのゲームに渡す（ゲームの DraftVoice が部品ごとに取り寄せる。録音はゲームにも GitHub Pages にも入れない）。
録音のフォルダは --voice-dir で渡すか、渡さなければパソコン版のゲームの設定（settings.cfg の [voice] wav_dir）を使う。
  python tools/serve_web.py [--voice-dir <フォルダ>]
"""
import configparser
import http.server
import socketserver
import os
import socket
import sys
from urllib.parse import unquote, urlsplit

DEFAULT_PORTS = [8000, 8080, 8888]
WEB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "build", "web"))
# パソコン版のゲームの設定（Windows）
SETTINGS = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "NPBオーペナゲーム", "settings.cfg")
VOICE_DIR = ""


def find_voice_dir(argv):
    """録音のフォルダ（無ければ空）。--voice-dir が先、無ければパソコン版の設定の wav_dir"""
    if "--voice-dir" in argv:
        i = argv.index("--voice-dir")
        return os.path.abspath(argv[i + 1]) if i + 1 < len(argv) else ""
    if not os.path.exists(SETTINGS):
        return ""
    cfg = configparser.ConfigParser()
    try:
        cfg.read(SETTINGS, encoding="utf-8")
        wav_dir = cfg.get("voice", "wav_dir", fallback="").strip().strip('"')
    except (configparser.Error, UnicodeDecodeError):
        return ""
    # user:// のような Godot の中の場所はここからは見えないので、パソコンのフォルダのときだけ
    return wav_dir if wav_dir and "://" not in wav_dir and os.path.isdir(wav_dir) else ""


def voice_file(name):
    """/voice/ のあとの名前 → 録音のファイル（無ければ空）。出身の「〜大学」が無ければ「〜大」も探す（DraftVoice.wav_path と同じ）"""
    if not VOICE_DIR or not name.endswith(".wav") or "/" in name or "\\" in name or name.startswith("."):
        return ""
    names = [name]
    if name.startswith("school_") and name.endswith("大学.wav"):
        names.append(name[: -len("学.wav")] + ".wav")
    for n in names:
        path = os.path.join(VOICE_DIR, n)
        if os.path.isfile(path):
            return path
    return ""

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if not path.startswith("/voice/"):
            return super().do_GET()
        name = path[len("/voice/"):]
        if name == "ping":
            # 録音を渡せるか（ゲームが最初に1回だけ調べる）
            return self._send(200, b"ok", "text/plain") if VOICE_DIR else self._send(404, b"", "text/plain")
        file = voice_file(name)
        if not file:
            return self._send(404, b"", "text/plain")
        with open(file, "rb") as f:
            self._send(200, f.read(), "audio/wav")

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # 録音の取り寄せは1指名で5件ずつ来るので、うるさくならないよう出さない
        if not str(args[0] if args else "").startswith("GET /voice/"):
            super().log_message(fmt, *args)

    def end_headers(self):
        # クロスオリジン分離ヘッダー（WebAssembly / SharedArrayBuffer 互換性保証）
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

if __name__ == "__main__":
    # Windows のコマンドプロンプト文字化け防止
    if sys.platform == "win32":
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    if not os.path.exists(WEB_DIR):
        print(f"[Error] Web build directory not found: {WEB_DIR}")
        print("Please export the web build first.")
        input("Press Enter to exit...")
        exit(1)

    VOICE_DIR = find_voice_dir(sys.argv[1:])
    local_ip = get_local_ip()

    httpd = None
    selected_port = None
    for port in DEFAULT_PORTS:
        try:
            # 録音の部品を同時に取り寄せるので、1件ずつではなく並べて返す
            httpd = socketserver.ThreadingTCPServer(("", port), Handler)
            selected_port = port
            break
        except OSError:
            continue

    if httpd is None:
        print(f"[Error] Could not bind to any port in {DEFAULT_PORTS}")
        input("Press Enter to exit...")
        exit(1)

    print("=" * 64)
    print("   ★ NPBオーペナゲーム スマホWebサーバー起動中 ★")
    print("=" * 64)
    print(f"  [PCブラウザ]  http://localhost:{selected_port}")
    print(f"  [スマホ実機]  http://{local_ip}:{selected_port}")
    print("=" * 64)
    print("  ※スマホをPCと同じWi-Fiにつないで、上記URLをブラウザで開いてください")
    if VOICE_DIR:
        print(f"  ※ドラフトの読み上げの録音をスマホに渡します：{VOICE_DIR}")
    print("  ※終了するときは、この画面を閉じるか Ctrl+C を押してください")
    print("=" * 64)
    print("アクセス待機中...")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nサーバーを停止しました。")
