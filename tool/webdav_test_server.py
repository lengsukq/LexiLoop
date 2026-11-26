"""最小可用的 WebDAV 服务器，只实现本应用用到的四个方法。

用途：在没有现成 WebDAV 服务的情况下，对 `WebdavClient` 做一次**真实 HTTP**
的端到端验证（见 test/data/remote_backup/webdav_live_smoke_test.dart）。
刻意不引入第三方依赖：标准库足够表达 PROPFIND / MKCOL / PUT / GET，
而依赖越多，这个脚本越容易在换机器后跑不起来。

用法：
    python3 tool/webdav_test_server.py [port] [root]

行为要点（与真实服务对齐的部分）：
- 一律要求 HTTP Basic 认证，账号密码取自环境变量或默认值；
- `PROPFIND` 支持 Depth: 0 与 1，返回 207 + application/xml；
- 目录 URL 必须带尾斜杠，否则按 404 处理（Apache mod_dav 的行为）；
- `MKCOL` 对已存在的集合返回 405；
- 未知路径 `PUT` 到不存在的父集合时返回 409（与 RFC 4918 一致）。
"""

from __future__ import annotations

import base64
import email.utils
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse
from xml.sax.saxutils import escape

DEFAULT_PORT = 8765
USERNAME = os.environ.get("WEBDAV_SMOKE_USER", "leo")
PASSWORD = os.environ.get("WEBDAV_SMOKE_PASSWORD", "app-pass")


class WebdavHandler(BaseHTTPRequestHandler):
    """把请求映射到本地目录的极简 WebDAV 实现。"""

    server_version = "LexiLoopTestDav/1.0"
    root: Path

    # ── 工具 ──

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            raw = base64.b64decode(header[6:]).decode("utf-8")
        except Exception:
            return False
        return raw == f"{USERNAME}:{PASSWORD}"

    def _resolve(self) -> Path | None:
        """把 URL 路径映射成磁盘路径；越界返回 None。"""
        path = unquote(urlparse(self.path).path)
        candidate = (self.root / path.lstrip("/")).resolve()
        if not str(candidate).startswith(str(self.root.resolve())):
            return None
        return candidate

    def _href(self, path: Path) -> str:
        """返回绝对 URL 形式的 href，带尾斜杠（若是目录）。"""
        relative = path.relative_to(self.root.resolve()).as_posix()
        href = "/" if relative == "." else "/" + relative
        if path.is_dir() and not href.endswith("/"):
            href += "/"
        return href

    def _properties(self, path: Path) -> str:
        is_dir = path.is_dir()
        stat = path.stat()
        modified = email.utils.formatdate(stat.st_mtime, usegmt=True)
        length = 0 if is_dir else stat.st_size
        resource_type = "<D:collection/>" if is_dir else ""
        return (
            "<D:response>"
            f"<D:href>{escape(self._href(path))}</D:href>"
            "<D:propstat><D:prop>"
            f"<D:resourcetype>{resource_type}</D:resourcetype>"
            f"<D:getcontentlength>{length}</D:getcontentlength>"
            f"<D:getlastmodified>{modified}</D:getlastmodified>"
            "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>"
            "</D:response>"
        )

    def _send(self, status: int, body: bytes = b"", content_type: str = "text/plain") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _unauthorized(self) -> None:
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="WebDAV"')
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ── 方法 ──

    def do_PROPFIND(self) -> None:  # noqa: N802 - http.server 的命名约定
        if not self._authorized():
            return self._unauthorized()
        target = self._resolve()
        if target is None or not target.exists():
            return self._send(404)
        # 目录必须带尾斜杠（真实服务的行为）。
        if target.is_dir() and not urlparse(self.path).path.endswith("/"):
            return self._send(404)

        depth = self.headers.get("Depth", "0")
        members: list[Path] = [target]
        if depth != "0" and target.is_dir():
            members.extend(sorted(target.iterdir()))

        body = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<D:multistatus xmlns:D="DAV:">'
            + "".join(self._properties(member) for member in members)
            + "</D:multistatus>"
        ).encode("utf-8")
        self._send(207, body, "application/xml; charset=utf-8")

    def do_MKCOL(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._unauthorized()
        target = self._resolve()
        if target is None:
            return self._send(403)
        if target.exists():
            return self._send(405)
        if not target.parent.exists():
            # RFC 4918：父集合不存在时 409。
            return self._send(409)
        target.mkdir()
        self._send(201)

    def do_PUT(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._unauthorized()
        target = self._resolve()
        if target is None:
            return self._send(403)
        if not target.parent.exists():
            return self._send(409)
        length = int(self.headers.get("Content-Length", "0"))
        target.write_bytes(self.rfile.read(length))
        self._send(201)

    def do_GET(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._unauthorized()
        target = self._resolve()
        if target is None or not target.is_file():
            return self._send(404)
        self._send(200, target.read_bytes(), "application/json")

    def log_message(self, format: str, *args: object) -> None:
        sys.stderr.write("dav: " + (format % args) + "\n")


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/lexiloop-dav-root")
    root.mkdir(parents=True, exist_ok=True)
    WebdavHandler.root = root

    server = ThreadingHTTPServer(("127.0.0.1", port), WebdavHandler)
    print(f"WebDAV 测试服务器：http://127.0.0.1:{port} 根目录 {root}", flush=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        thread.join()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
