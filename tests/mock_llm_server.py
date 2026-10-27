"""Local mock of the DeepSeek /chat/completions endpoint for tests only."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = {"calls": 0, "bad_json_calls": 0, "auth_seen": []}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/stats"):
            self._send(200, STATE)
            return
        if self.path.startswith("/reset"):
            with LOCK:
                STATE["calls"] = 0
                STATE["bad_json_calls"] = 0
                STATE["auth_seen"] = []
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": {"message": "not found"}})

    def do_POST(self):
        if not self.path.endswith("/chat/completions"):
            self._send(404, {"error": {"message": "not found"}})
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            req = json.loads(raw)
        except Exception:
            self._send(400, {"error": {"message": "bad request json"}})
            return
        with LOCK:
            STATE["calls"] += 1
            STATE["auth_seen"].append(self.headers.get("Authorization", ""))
            calls = STATE["calls"]
        user = "\n".join(m.get("content", "") for m in req.get("messages", []) if m.get("role") == "user")
        system = "\n".join(m.get("content", "") for m in req.get("messages", []) if m.get("role") == "system")
        if "TRIGGER_500" in user:
            self._send(500, {"error": {"message": "mock 500"}})
            return
        if "TRIGGER_BADJSON" in user:
            with LOCK:
                STATE["bad_json_calls"] += 1
                bad = STATE["bad_json_calls"]
            if bad == 1:
                content = "这不是 JSON，只是一段解释。"
            else:
                content = '{"ok": true, "after_retry": true}'
        elif "只输出 {\\\"ok\\\":true}" in user or "连接测试" in system or req.get("max_tokens", 0) <= 30:
            content = '{"ok": true}'
        else:
            content = json.dumps({"ok": True, "call": calls, "purpose": "mock"}, ensure_ascii=False)
        usage = {"prompt_tokens": 12, "completion_tokens": 7, "total_tokens": 19}
        self._send(200, {
            "id": "mock",
            "object": "chat.completion",
            "model": req.get("model", "deepseek-chat"),
            "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
            "usage": usage,
        })


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
