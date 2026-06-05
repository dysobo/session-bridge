#!/usr/bin/env python3
import argparse
import base64
import gzip
import hashlib
import hmac
import json
import os
import sqlite3
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


DOWNLOAD_CHUNK_SIZE = 256 * 1024
MAX_DOWNLOAD_CHUNK_SIZE = 512 * 1024


SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  account TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  account TEXT NOT NULL,
  source TEXT NOT NULL,
  session_id TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  cwd TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  ai_title TEXT NOT NULL DEFAULT '',
  ai_summary TEXT NOT NULL DEFAULT '',
  ai_tags TEXT NOT NULL DEFAULT '[]',
  category TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT '',
  message_count INTEGER NOT NULL DEFAULT 0,
  file_sha256 TEXT NOT NULL DEFAULT '',
  file_content_base64 TEXT NOT NULL,
  device_name TEXT NOT NULL DEFAULT '',
  server_updated_at TEXT NOT NULL,
  PRIMARY KEY (account, source, session_id, relative_path)
);
"""


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def key_hash(sync_key):
    return hashlib.sha256(sync_key.encode("utf-8")).hexdigest()


def allow_signup():
    return os.environ.get("SESSION_BRIDGE_ALLOW_SIGNUP", "").lower() in (
        "1",
        "true",
        "yes",
    )


class SyncStore:
    def __init__(self, db_path):
        self.db_path = db_path
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as conn:
            conn.executescript(SCHEMA)

    def connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def verify_user(self, account, sync_key):
        if not account or not sync_key:
            raise ValueError("account and syncKey are required")
        hashed = key_hash(sync_key)
        with self.connect() as conn:
            row = conn.execute(
                "SELECT key_hash FROM users WHERE account = ?", (account,)
            ).fetchone()
            current = now_iso()
            if row is None:
                if allow_signup():
                    conn.execute(
                        "INSERT INTO users(account, key_hash, created_at, updated_at) VALUES (?, ?, ?, ?)",
                        (account, hashed, current, current),
                    )
                    return
                raise PermissionError("account is not provisioned")
            if not hmac.compare_digest(row["key_hash"], hashed):
                raise PermissionError("invalid sync key")
            conn.execute(
                "UPDATE users SET updated_at = ? WHERE account = ?",
                (current, account),
            )

    def upload(self, account, device_name, sessions):
        sent = 0
        updated = 0
        skipped = 0
        current = now_iso()
        with self.connect() as conn:
            for item in sessions:
                sent += 1
                source = clean_text(item.get("source"))
                session_id = clean_text(item.get("sessionId"))
                relative_path = clean_relative_path(item.get("relativePath"))
                if source not in ("codex", "claude") or not session_id or not relative_path:
                    skipped += 1
                    continue
                try:
                    raw, content = decode_file_content(item)
                except Exception:
                    skipped += 1
                    continue
                file_sha256 = hashlib.sha256(raw).hexdigest()
                incoming_updated_at = clean_text(item.get("updatedAt"))
                existing = conn.execute(
                    """
                    SELECT updated_at, file_sha256 FROM sessions
                    WHERE account = ? AND source = ? AND session_id = ? AND relative_path = ?
                    """,
                    (account, source, session_id, relative_path),
                ).fetchone()
                if existing is not None and existing["updated_at"] > incoming_updated_at:
                    skipped += 1
                    continue
                conn.execute(
                    """
                    INSERT INTO sessions (
                      account, source, session_id, relative_path, cwd, title, summary,
                      ai_title, ai_summary, ai_tags, category, updated_at, message_count,
                      file_sha256, file_content_base64, device_name, server_updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(account, source, session_id, relative_path) DO UPDATE SET
                      cwd = excluded.cwd,
                      title = excluded.title,
                      summary = excluded.summary,
                      ai_title = excluded.ai_title,
                      ai_summary = excluded.ai_summary,
                      ai_tags = excluded.ai_tags,
                      category = excluded.category,
                      updated_at = excluded.updated_at,
                      message_count = excluded.message_count,
                      file_sha256 = excluded.file_sha256,
                      file_content_base64 = excluded.file_content_base64,
                      device_name = excluded.device_name,
                      server_updated_at = excluded.server_updated_at
                    """,
                    (
                        account,
                        source,
                        session_id,
                        relative_path,
                        clean_text(item.get("cwd")),
                        clean_text(item.get("title")),
                        clean_text(item.get("summary")),
                        clean_text(item.get("aiTitle")),
                        clean_text(item.get("aiSummary")),
                        json.dumps(item.get("aiTags") if isinstance(item.get("aiTags"), list) else [], ensure_ascii=False),
                        clean_text(item.get("category")),
                        incoming_updated_at,
                        int_value(item.get("messageCount")),
                        file_sha256,
                        content,
                        clean_text(device_name),
                        current,
                    ),
                )
                updated += 1
        return {"ok": True, "sent": sent, "updated": updated, "skipped": skipped}

    def download(self, account):
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM sessions
                WHERE account = ?
                ORDER BY server_updated_at DESC
                """,
                (account,),
            ).fetchall()
        return {"ok": True, "sessions": [session_payload(row, True) for row in rows]}

    def download_list(self, account):
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM sessions
                WHERE account = ?
                ORDER BY server_updated_at DESC
                """,
                (account,),
            ).fetchall()
        return {"ok": True, "sessions": [session_payload(row, False) for row in rows]}

    def download_chunk(self, account, item):
        source = clean_text(item.get("source"))
        session_id = clean_text(item.get("sessionId"))
        relative_path = clean_relative_path(item.get("relativePath"))
        offset = max(0, int_value(item.get("offset")))
        length = int_value(item.get("length")) or DOWNLOAD_CHUNK_SIZE
        length = max(1, min(length, MAX_DOWNLOAD_CHUNK_SIZE))
        if source not in ("codex", "claude") or not session_id or not relative_path:
            raise ValueError("invalid session identity")
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT file_content_base64, file_sha256 FROM sessions
                WHERE account = ? AND source = ? AND session_id = ? AND relative_path = ?
                """,
                (account, source, session_id, relative_path),
            ).fetchone()
        if row is None:
            raise FileNotFoundError("session not found")
        content = row["file_content_base64"]
        total_length = len(content)
        if offset > total_length:
            offset = total_length
        next_offset = min(offset + length, total_length)
        return {
            "ok": True,
            "chunkBase64": content[offset:next_offset],
            "offset": offset,
            "nextOffset": next_offset,
            "totalLength": total_length,
            "complete": next_offset >= total_length,
            "fileSha256": row["file_sha256"],
        }

    def upload_chunk(self, account, device_name, item):
        upload_id = clean_upload_id(item.get("uploadId"))
        chunk_index = int_value(item.get("chunkIndex"))
        chunk_total = int_value(item.get("chunkTotal"))
        chunk_data = clean_text(item.get("chunkDataBase64"))
        if not upload_id or chunk_total <= 0 or chunk_index < 0 or chunk_index >= chunk_total:
            raise ValueError("invalid chunk metadata")
        if not chunk_data:
            raise ValueError("chunkDataBase64 is required")
        if self.chunk_session_exists(account, item):
            return {"ok": True, "complete": True, "sent": 1, "updated": 0, "skipped": 1}

        chunk_dir = chunk_upload_dir(account, upload_id)
        chunk_dir.mkdir(parents=True, exist_ok=True)
        (chunk_dir / f"{chunk_index:06d}.part").write_bytes(
            base64.b64decode(chunk_data.encode("ascii"), validate=True)
        )

        parts = list(chunk_dir.glob("*.part"))
        if len(parts) < chunk_total:
            return {"ok": True, "complete": False, "received": len(parts), "total": chunk_total}

        compressed = b"".join(
            (chunk_dir / f"{index:06d}.part").read_bytes()
            for index in range(chunk_total)
        )
        raw = gzip.decompress(compressed)
        session = dict(item)
        session.pop("uploadId", None)
        session.pop("chunkIndex", None)
        session.pop("chunkTotal", None)
        session.pop("chunkDataBase64", None)
        session["fileContentBase64"] = base64.b64encode(raw).decode("ascii")
        result = self.upload(account, device_name, [session])
        for part in parts:
            try:
                part.unlink()
            except OSError:
                pass
        try:
            chunk_dir.rmdir()
        except OSError:
            pass
        return {"ok": True, "complete": True, **result}

    def chunk_session_exists(self, account, item):
        source = clean_text(item.get("source"))
        session_id = clean_text(item.get("sessionId"))
        relative_path = clean_relative_path(item.get("relativePath"))
        updated_at = clean_text(item.get("updatedAt"))
        if source not in ("codex", "claude") or not session_id or not relative_path:
            return False
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT 1 FROM sessions
                WHERE account = ? AND source = ? AND session_id = ?
                  AND relative_path = ? AND updated_at = ?
                """,
                (account, source, session_id, relative_path, updated_at),
            ).fetchone()
        return row is not None


def session_payload(row, include_content):
    try:
        tags = json.loads(row["ai_tags"])
    except Exception:
        tags = []
    payload = {
        "source": row["source"],
        "sessionId": row["session_id"],
        "relativePath": row["relative_path"],
        "cwd": row["cwd"],
        "title": row["title"],
        "summary": row["summary"],
        "aiTitle": row["ai_title"],
        "aiSummary": row["ai_summary"],
        "aiTags": tags if isinstance(tags, list) else [],
        "category": row["category"],
        "updatedAt": row["updated_at"],
        "messageCount": row["message_count"],
        "fileSha256": row["file_sha256"],
        "contentBase64Length": len(row["file_content_base64"]),
        "deviceName": row["device_name"],
        "serverUpdatedAt": row["server_updated_at"],
    }
    if include_content:
        payload["fileContentBase64"] = row["file_content_base64"]
    return payload


class Handler(BaseHTTPRequestHandler):
    store = None

    def do_GET(self):
        if self.path == "/api/health":
            self.write_json({"ok": True, "service": "session-bridge-sync"})
            return
        self.write_json({"ok": False, "error": "not found"}, status=404)

    def do_POST(self):
        try:
            body = self.read_json()
            account = clean_text(body.get("account"))
            sync_key = clean_text(body.get("syncKey"))
            self.store.verify_user(account, sync_key)
            if self.path == "/api/upload":
                sessions = body.get("sessions")
                if not isinstance(sessions, list):
                    raise ValueError("sessions must be a list")
                self.write_json(
                    self.store.upload(account, body.get("deviceName"), sessions)
                )
                return
            if self.path == "/api/upload-chunk":
                session = body.get("session")
                if not isinstance(session, dict):
                    raise ValueError("session must be an object")
                self.write_json(
                    self.store.upload_chunk(account, body.get("deviceName"), session)
                )
                return
            if self.path == "/api/download":
                self.write_json(self.store.download(account))
                return
            if self.path == "/api/download-list":
                self.write_json(self.store.download_list(account))
                return
            if self.path == "/api/download-chunk":
                session = body.get("session")
                if not isinstance(session, dict):
                    raise ValueError("session must be an object")
                self.write_json(self.store.download_chunk(account, session))
                return
            self.write_json({"ok": False, "error": "not found"}, status=404)
        except PermissionError as exc:
            self.write_json({"ok": False, "error": str(exc)}, status=403)
        except FileNotFoundError as exc:
            self.write_json({"ok": False, "error": str(exc)}, status=404)
        except Exception as exc:
            self.write_json({"ok": False, "error": str(exc)}, status=400)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def write_json(self, payload, status=200):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        return


def clean_text(value):
    if isinstance(value, str):
        return value.strip()
    if value is None:
        return ""
    return str(value).strip()


def clean_relative_path(value):
    text = clean_text(value).replace("/", "\\")
    if not text or text.startswith("\\") or ".." in text.split("\\"):
        return ""
    if len(text) > 2 and text[1] == ":":
        return ""
    return text


def clean_upload_id(value):
    text = clean_text(value)
    if not text:
        return ""
    cleaned = "".join(ch if ch.isalnum() or ch in ("-", "_") else "-" for ch in text)
    return cleaned[:120]


def chunk_upload_dir(account, upload_id):
    digest = hashlib.sha256(f"{account}:{upload_id}".encode("utf-8")).hexdigest()
    return Path(tempfile.gettempdir()) / "session-bridge-sync-chunks" / digest


def decode_file_content(item):
    gzip_content = clean_text(item.get("fileContentGzipBase64"))
    if gzip_content:
        compressed = base64.b64decode(gzip_content.encode("ascii"), validate=True)
        raw = gzip.decompress(compressed)
        return raw, base64.b64encode(raw).decode("ascii")
    content = clean_text(item.get("fileContentBase64"))
    if not content:
        raise ValueError("file content is required")
    raw = base64.b64decode(content.encode("ascii"), validate=True)
    return raw, content


def int_value(value):
    try:
        return int(value)
    except Exception:
        return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument(
        "--db",
        default="/opt/session-bridge-sync/session_bridge_sync.sqlite",
    )
    args = parser.parse_args()
    Handler.store = SyncStore(args.db)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
