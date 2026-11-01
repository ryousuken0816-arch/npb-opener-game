#!/usr/bin/env python3
"""
Godot 4 Web ビルドのローカル検証用 HTTP サーバー
同一LAN内のスマホ（iPhone Safari / Android Chrome）からも
http://<PCのローカルIP>:8000 でアクセスして実機検証できます。
"""
import http.server
import socketserver
import os
import socket
import sys

DEFAULT_PORTS = [8000, 8080, 8888]
WEB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "build", "web"))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

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

    local_ip = get_local_ip()

    httpd = None
    selected_port = None
    for port in DEFAULT_PORTS:
        try:
            httpd = socketserver.TCPServer(("", port), Handler)
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
    print("  ※終了するときは、この画面を閉じるか Ctrl+C を押してください")
    print("=" * 64)
    print("アクセス待機中...")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nサーバーを停止しました。")
