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

PORT = 8000
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
    if not os.path.exists(WEB_DIR):
        print(f"[Error] Web build directory not found: {WEB_DIR}")
        print("Please export the web build first.")
        exit(1)

    local_ip = get_local_ip()
    print("=" * 60)
    print("  NPBペナントゲーム Webサーバー起動")
    print(f"  ローカルPC: http://localhost:{PORT}")
    print(f"  スマホ実機: http://{local_ip}:{PORT} (同一Wi-Fiからアクセス)")
    print("=" * 60)

    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nサーバーを停止しました。")
