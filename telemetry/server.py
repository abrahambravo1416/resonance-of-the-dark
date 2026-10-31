#!/usr/bin/env python3
"""Local, dependency-free gameplay archive. Python 3.9 or newer."""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
import mimetypes
import os
import sqlite3
import socketserver
import threading
import time
from contextlib import closing
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, unquote, urlencode, urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
MAX_LINE = 512 * 1024
IMPORT_BUDGET = 16 * 1024 * 1024
SAMPLE_KINDS = {"position", "position_sample", "player_position", "movement_sample"}
ALL_SAMPLE_KINDS = SAMPLE_KINDS | {"enemy_position_sample"}
HEATMAP_KINDS = ALL_SAMPLE_KINDS | {
    "level_started", "player_died", "player_death", "enemy_state_changed",
    "hiding_started", "hiding_ended", "hiding_zone_entered", "hiding_zone_left",
    "hide_started", "hide_ended", "hide_exit_completed", "pumpkin_collected",
    "altar_activated", "relic_delivered", "health_skull_collected", "skull_collected",
    "item_collected", "collectible_collected",
}
COMPARISON_KINDS = SAMPLE_KINDS | {
    "level_started", "level_completed", "player_died", "player_death",
    "pumpkin_collected", "altar_activated", "relic_delivered", "item_collected",
    "collectible_collected", "mission_completed", "quest_completed", "exit_unlocked",
}
MAX_HEATMAP_SESSIONS = 30
MAX_HEATMAP_EVENTS = 20000
MAX_COMPARISON_EVENTS = 20000


def number(value, default=None):
    if isinstance(value, bool):
        return default
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError, OverflowError):
        return default


def normalize_event(value):
    if not isinstance(value, dict):
        raise ValueError("event must be an object")
    for key in ("event_id", "session_id", "kind"):
        if not isinstance(value.get(key), str) or not 0 < len(value[key]) <= 200:
            raise ValueError("missing or invalid " + key)
    timestamp = number(value.get("ts"))
    sequence = number(value.get("seq"))
    if timestamp is None or timestamp < 0 or sequence is None or sequence < 0 or sequence > 2**53 or sequence != int(sequence):
        raise ValueError("invalid timestamp or sequence")
    level = number(value.get("level"), 0)
    if level < 0 or level > 100000 or level != int(level):
        raise ValueError("invalid level")
    position = value.get("position")
    xyz = (None, None, None)
    if isinstance(position, dict):
        xyz = tuple(number(position.get(key)) for key in ("x", "y", "z"))
    elif isinstance(position, list) and len(position) == 3:
        xyz = tuple(number(item) for item in position)
    if None in xyz:
        xyz = (None, None, None)
    data = value.get("data", {})
    if not isinstance(data, dict):
        raise ValueError("data must be an object")
    # Round-tripping rejects NaN/Infinity in nested data as well as coordinates.
    data_json = json.dumps(data, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
    return (value["event_id"], value["session_id"], int(sequence), value["kind"], timestamp,
            max(0.0, number(value.get("elapsed"), 0.0)), int(level), *xyz, data_json)


class Archive:
    def __init__(self, data_dir, spool_dir=None):
        self.data_dir = Path(data_dir).resolve()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.spool_dir = Path(spool_dir).resolve() if spool_dir else self.data_dir / "spool"
        self.spool_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.data_dir / "resonance.sqlite3"
        self.lock = threading.Lock()
        self.last_error = None
        with closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode = WAL")
            db.executescript((ROOT / "schema.sql").read_text(encoding="utf-8"))
            session_columns = {row["name"] for row in db.execute("PRAGMA table_info(sessions)")}
            if "player_id" not in session_columns:
                db.execute("ALTER TABLE sessions ADD COLUMN player_id TEXT")
            if "platform" not in session_columns:
                db.execute("ALTER TABLE sessions ADD COLUMN platform TEXT NOT NULL DEFAULT 'unknown'")
            db.commit()

    def connect(self):
        db = sqlite3.connect(self.db_path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys = ON")
        return db

    def import_pending(self):
        """Incremental and transactional; the database can be rebuilt from the spool."""
        with self.lock, closing(self.connect()) as db, db:
            remaining = IMPORT_BUDGET
            for source in sorted(self.spool_dir.glob("*.jsonl")):
                # A spool symlink must never make the server read an unrelated file.
                if source.is_symlink() or not source.is_file():
                    continue
                row = db.execute("SELECT * FROM ingestion_sources WHERE source=?", (source.name,)).fetchone()
                offset = row["byte_offset"] if row else 0
                imported = row["imported_count"] if row else 0
                rejected = row["rejected_count"] if row else 0
                if source.stat().st_size < offset:
                    offset = 0
                with source.open("rb") as stream:
                    stream.seek(offset)
                    while remaining > 0:
                        start = stream.tell()
                        line = stream.readline(MAX_LINE + 1)
                        if not line:
                            break
                        if not line.endswith(b"\n"):
                            if len(line) > MAX_LINE:
                                # Skip a complete oversized record. Leave an unfinished
                                # one at its start until the producer finishes writing it.
                                while line and not line.endswith(b"\n"):
                                    line = stream.readline(MAX_LINE + 1)
                                if line.endswith(b"\n"):
                                    rejected += 1
                                    offset = stream.tell()
                                    remaining -= offset - start
                                    continue
                            break
                        offset = stream.tell()
                        remaining -= offset - start
                        try:
                            event = normalize_event(json.loads(line))
                            event_id, session_id, seq, kind, ts, elapsed, level, x, y, z, data_json = event
                            # Do not let a duplicate event alter an existing session.
                            if db.execute("SELECT 1 FROM events WHERE event_id=?", (event_id,)).fetchone():
                                continue
                            db.execute("INSERT OR IGNORE INTO sessions(session_id,started_at,last_seen) VALUES(?,?,?)", (session_id, ts, ts))
                            db.execute("INSERT INTO events VALUES(?,?,?,?,?,?,?,?,?,?,?)", event)
                            db.execute("UPDATE sessions SET started_at=MIN(started_at,?),last_seen=MAX(last_seen,?) WHERE session_id=?", (ts, ts, session_id))
                            data = json.loads(data_json)
                            if kind == "session_started":
                                platform = str(data.get("platform", "unknown")).lower()
                                if platform not in ("pc", "mobile"):
                                    platform = "unknown"
                                db.execute("UPDATE sessions SET player_id=?,player_name=?,game_version=?,platform=? WHERE session_id=?", (str(data.get("player_id", ""))[:100] or None, str(data.get("player_name", ""))[:200], str(data.get("game_version", ""))[:100], platform, session_id))
                            elif kind == "session_ended":
                                db.execute("UPDATE sessions SET ended_at=?,outcome=? WHERE session_id=?", (ts, str(data.get("outcome", "finished"))[:100], session_id))
                            imported += 1
                        except (ValueError, TypeError, UnicodeError, OverflowError):
                            rejected += 1
                db.execute("INSERT INTO ingestion_sources VALUES(?,?,?,?) ON CONFLICT(source) DO UPDATE SET byte_offset=excluded.byte_offset,imported_count=excluded.imported_count,rejected_count=excluded.rejected_count", (source.name, offset, imported, rejected))
                if remaining <= 0:
                    break
            self.last_error = None

    @staticmethod
    def event_dict(row):
        result = {key: row[key] for key in ("event_id", "session_id", "seq", "kind", "ts", "elapsed", "level")}
        result["position"] = {"x": row["x"], "y": row["y"], "z": row["z"]} if row["x"] is not None else None
        result["data"] = json.loads(row["data_json"])
        return result

    @staticmethod
    def summarize(row, events):
        result = dict(row)
        result["event_count"] = len(events)
        result["action_count"] = sum(event["kind"] not in ALL_SAMPLE_KINDS for event in events)
        result["level_count"] = len({event["level"] for event in events if event["level"] > 0})
        result["duration"] = max((event["elapsed"] for event in events), default=0)
        result["status"] = "finished" if row["ended_at"] is not None else ("active" if time.time() - row["last_seen"] < 45 else "inactive")
        distance, previous = 0.0, None
        for event in events:
            if event["kind"] in ("level_started", "player_respawned", "player_teleported"):
                previous = None
            if event["x"] is not None and event["kind"] in SAMPLE_KINDS:
                if previous is not None and previous["level"] == event["level"] and json.loads(previous["data_json"]).get("attempt") == json.loads(event["data_json"]).get("attempt"):
                    distance += math.hypot(event["x"] - previous["x"], event["z"] - previous["z"])
                previous = event
        result["distance"] = round(distance, 2)
        return result

    def sessions(self):
        with closing(self.connect()) as db:
            rows = db.execute("SELECT * FROM sessions ORDER BY started_at DESC").fetchall()
            return [self.summarize(row, db.execute("SELECT * FROM events WHERE session_id=? ORDER BY seq,ts", (row["session_id"],)).fetchall()) for row in rows]

    def session(self, session_id):
        with closing(self.connect()) as db:
            row = db.execute("SELECT * FROM sessions WHERE session_id=?", (session_id,)).fetchone()
            if row is None:
                return None
            events = db.execute("SELECT * FROM events WHERE session_id=? ORDER BY seq,ts", (session_id,)).fetchall()
            return {"session": self.summarize(row, events), "events": [self.event_dict(event) for event in events]}

    def heatmap(self, session_ids, level):
        ids = [value for value in dict.fromkeys(session_ids) if isinstance(value, str) and 0 < len(value) <= 100 and all(char.isalnum() or char in "_-" for char in value)][:MAX_HEATMAP_SESSIONS]
        if not ids:
            return {"events": [], "truncated": False}
        placeholders = ",".join("?" for _ in ids)
        kinds = sorted(HEATMAP_KINDS)
        kind_placeholders = ",".join("?" for _ in kinds)
        query = f"SELECT * FROM events WHERE session_id IN ({placeholders}) AND level=? AND kind IN ({kind_placeholders}) ORDER BY session_id DESC,seq,ts LIMIT ?"
        with closing(self.connect()) as db:
            rows = db.execute(query, (*ids, level, *kinds, MAX_HEATMAP_EVENTS + 1)).fetchall()
        truncated = len(rows) > MAX_HEATMAP_EVENTS
        events = [self.event_dict(row) for row in rows[:MAX_HEATMAP_EVENTS]]
        return {"events": events, "truncated": truncated}

    def comparison(self, session_ids):
        ids = [value for value in dict.fromkeys(session_ids) if isinstance(value, str) and 0 < len(value) <= 100 and all(char.isalnum() or char in "_-" for char in value)][:MAX_HEATMAP_SESSIONS]
        if not ids:
            return {"events": [], "truncated": False}
        placeholders = ",".join("?" for _ in ids)
        kinds = sorted(COMPARISON_KINDS)
        kind_placeholders = ",".join("?" for _ in kinds)
        query = f"SELECT * FROM events WHERE session_id IN ({placeholders}) AND kind IN ({kind_placeholders}) ORDER BY session_id DESC,seq,ts LIMIT ?"
        with closing(self.connect()) as db:
            rows = db.execute(query, (*ids, *kinds, MAX_COMPARISON_EVENTS + 1)).fetchall()
        truncated = len(rows) > MAX_COMPARISON_EVENTS
        events = [self.event_dict(row) for row in rows[:MAX_COMPARISON_EVENTS]]
        return {"events": events, "truncated": truncated}

    def health(self):
        with closing(self.connect()) as db:
            imported, rejected = db.execute("SELECT COALESCE(SUM(imported_count),0),COALESCE(SUM(rejected_count),0) FROM ingestion_sources").fetchone()
            return {"ok": self.last_error is None, "database": "SQLite", "schema_version": 1,
                    "session_count": db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0],
                    "event_count": db.execute("SELECT COUNT(*) FROM events").fetchone()[0],
                    "rejected_lines": rejected, "ingestion_error": self.last_error}


class RemoteArchive:
    """Read-only Supabase adapter for the existing local dashboard."""

    PAGE_SIZE = 1000

    def __init__(self, project_url, secret_key):
        self.project_url = project_url.rstrip("/")
        self.secret_key = secret_key

    def _request_json(self, path, headers=None):
        request_headers = {"apikey": self.secret_key, "Accept": "application/json"}
        if headers:
            request_headers.update(headers)
        request = Request(self.project_url + path, headers=request_headers, method="GET")
        try:
            with urlopen(request, timeout=12) as response:
                return json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, OSError, UnicodeError, json.JSONDecodeError) as error:
            # Never surface request headers or keys in the local dashboard response.
            raise OSError("No se pudo consultar Supabase; revisa URL, clave y conexión.") from error

    def _all_rows(self, resource, query):
        rows = []
        offset = 0
        while True:
            parameters = dict(query)
            parameters.update({"limit": str(self.PAGE_SIZE), "offset": str(offset)})
            encoded = urlencode(parameters, safe=",()*")
            page = self._request_json("/rest/v1/%s?%s" % (resource, encoded))
            if not isinstance(page, list):
                raise OSError("Supabase devolvió una respuesta inesperada.")
            rows.extend(page)
            if len(page) < self.PAGE_SIZE:
                break
            offset += len(page)
        return rows

    @staticmethod
    def _with_status(row):
        result = dict(row)
        ended_at = result.get("ended_at")
        last_seen = number(result.get("last_seen"), 0.0)
        result["status"] = "finished" if ended_at is not None else ("active" if time.time() - last_seen < 45 else "inactive")
        return result

    def sessions(self):
        rows = self._all_rows("game_session_summary", {"select": "*", "order": "started_at.desc"})
        return [self._with_status(row) for row in rows]

    def session(self, session_id):
        rows = self._all_rows("game_session_summary", {
            "select": "*", "session_id": "eq." + session_id,
        })
        if not rows:
            return None
        summary = self._with_status(rows[0])
        raw_events = self._all_rows("game_events", {
            "select": "event_id,session_id,seq,kind,ts,elapsed,level,x,y,z,data",
            "session_id": "eq." + session_id,
            "order": "seq.asc,ts.asc",
        })
        events = []
        for row in raw_events:
            position = None
            if row.get("x") is not None and row.get("y") is not None and row.get("z") is not None:
                position = {"x": row["x"], "y": row["y"], "z": row["z"]}
            events.append({
                "event_id": row["event_id"], "session_id": row["session_id"],
                "seq": row["seq"], "kind": row["kind"], "ts": row["ts"],
                "elapsed": row["elapsed"], "level": row["level"],
                "position": position, "data": row.get("data") or {},
            })
        return {"session": summary, "events": events}

    def heatmap(self, session_ids, level):
        ids = [value for value in dict.fromkeys(session_ids) if isinstance(value, str) and 0 < len(value) <= 100 and all(char.isalnum() or char in "_-" for char in value)][:MAX_HEATMAP_SESSIONS]
        if not ids:
            return {"events": [], "truncated": False}
        escaped_ids = ','.join('"' + value.replace('"', '') + '"' for value in ids)
        query = {
            "select": "event_id,session_id,seq,kind,ts,elapsed,level,x,y,z,data",
            "session_id": "in.(" + escaped_ids + ")",
            "level": "eq." + str(level),
            "kind": "in.(" + ",".join(sorted(HEATMAP_KINDS)) + ")",
            "order": "session_id.desc,seq.asc,ts.asc",
        }
        rows = []
        offset = 0
        while len(rows) <= MAX_HEATMAP_EVENTS:
            page_query = dict(query)
            page_query.update({"limit": str(min(self.PAGE_SIZE, MAX_HEATMAP_EVENTS + 1 - len(rows))), "offset": str(offset)})
            encoded = urlencode(page_query, safe=",()*")
            page = self._request_json("/rest/v1/game_events?%s" % encoded)
            if not isinstance(page, list):
                raise OSError("Supabase devolvió una respuesta inesperada.")
            rows.extend(page)
            if len(page) < min(self.PAGE_SIZE, MAX_HEATMAP_EVENTS + 1 - (len(rows) - len(page))):
                break
            offset += len(page)
        truncated = len(rows) > MAX_HEATMAP_EVENTS
        events = []
        for row in rows[:MAX_HEATMAP_EVENTS]:
            position = None
            if row.get("x") is not None and row.get("y") is not None and row.get("z") is not None:
                position = {"x": row["x"], "y": row["y"], "z": row["z"]}
            events.append({
                "event_id": row["event_id"], "session_id": row["session_id"], "seq": row["seq"],
                "kind": row["kind"], "ts": row["ts"], "elapsed": row["elapsed"],
                "level": row["level"], "position": position, "data": row.get("data") or {},
            })
        return {"events": events, "truncated": truncated}

    def comparison(self, session_ids):
        ids = [value for value in dict.fromkeys(session_ids) if isinstance(value, str) and 0 < len(value) <= 100 and all(char.isalnum() or char in "_-" for char in value)][:MAX_HEATMAP_SESSIONS]
        if not ids:
            return {"events": [], "truncated": False}
        escaped_ids = ','.join('"' + value.replace('"', '') + '"' for value in ids)
        query = {
            "select": "event_id,session_id,seq,kind,ts,elapsed,level,x,y,z,data",
            "session_id": "in.(" + escaped_ids + ")",
            "kind": "in.(" + ",".join(sorted(COMPARISON_KINDS)) + ")",
            "order": "session_id.desc,seq.asc,ts.asc",
        }
        rows = []
        offset = 0
        while len(rows) <= MAX_COMPARISON_EVENTS:
            page_query = dict(query)
            page_limit = min(self.PAGE_SIZE, MAX_COMPARISON_EVENTS + 1 - len(rows))
            page_query.update({"limit": str(page_limit), "offset": str(offset)})
            encoded = urlencode(page_query, safe=",()*")
            page = self._request_json("/rest/v1/game_events?%s" % encoded)
            if not isinstance(page, list):
                raise OSError("Supabase devolvió una respuesta inesperada.")
            rows.extend(page)
            if len(page) < page_limit:
                break
            offset += len(page)
        truncated = len(rows) > MAX_COMPARISON_EVENTS
        events = []
        for row in rows[:MAX_COMPARISON_EVENTS]:
            position = None
            if row.get("x") is not None and row.get("y") is not None and row.get("z") is not None:
                position = {"x": row["x"], "y": row["y"], "z": row["z"]}
            events.append({
                "event_id": row["event_id"], "session_id": row["session_id"],
                "seq": row["seq"], "kind": row["kind"], "ts": row["ts"],
                "elapsed": row["elapsed"], "level": row["level"],
                "position": position, "data": row.get("data") or {},
            })
        return {"events": events, "truncated": truncated}

    def health(self):
        summaries = self._all_rows("game_session_summary", {"select": "event_count"})
        return {"ok": True, "database": "Supabase Postgres", "schema_version": 1,
                "session_count": len(summaries),
                "event_count": sum(int(row.get("event_count") or 0) for row in summaries),
                "rejected_lines": 0, "ingestion_error": None}


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, archive, remote_archive=None):
        self.archive = archive
        self.remote_archive = remote_archive
        super().__init__(address, DashboardHandler)

    def server_bind(self):
        # HTTPServer normally performs a reverse DNS lookup here. This local
        # service needs no DNS and should start immediately while offline.
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "ResonanceArchive/1.0"

    def log_message(self, fmt, *args):
        if args and str(args[1] if len(args) > 1 else "") not in ("200", "304"):
            super().log_message(fmt, *args)

    def respond(self, payload, status=200, content_type="application/json; charset=utf-8", disposition=None):
        if not isinstance(payload, bytes):
            payload = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
        self.send_header("Referrer-Policy", "no-referrer")
        if disposition:
            self.send_header("Content-Disposition", disposition)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        parsed = urlsplit(self.path)
        path = unquote(parsed.path)
        if path == "/config.js":
            # The loopback archive keeps its local API; the hosted static site
            # ships the separate team-login configuration from telemetry/web.
            return self.respond(
                b'window.RESONANCE_ARCHIVE_CONFIG = { mode: "local" };',
                content_type="application/javascript; charset=utf-8",
            )
        if path.startswith("/api/"):
            try:
                self.server.archive.import_pending()
                data_source = self.server.remote_archive or self.server.archive
                if path == "/api/health":
                    return self.respond(data_source.health())
                if path == "/api/sessions":
                    return self.respond({"sessions": data_source.sessions()})
                if path == "/api/heatmap":
                    query = parse_qs(parsed.query)
                    level_value = number(query.get("level", [""])[0])
                    session_ids = [value for value in query.get("sessions", [""])[0].split(",") if value]
                    if level_value is None or level_value != int(level_value) or not 1 <= int(level_value) <= 4:
                        return self.respond({"error": "Nivel inválido para el mapa de calor."}, 400)
                    if len(session_ids) > MAX_HEATMAP_SESSIONS:
                        return self.respond({"error": "Selecciona como máximo 30 partidas."}, 400)
                    if not session_ids or any(not value or len(value) > 100 or not all(char.isalnum() or char in "_-" for char in value) for value in session_ids):
                        return self.respond({"error": "Las partidas seleccionadas no son válidas."}, 400)
                    return self.respond(data_source.heatmap(session_ids, int(level_value)))
                if path == "/api/comparison":
                    query = parse_qs(parsed.query)
                    session_ids = [value for value in query.get("sessions", [""])[0].split(",") if value]
                    if len(session_ids) > MAX_HEATMAP_SESSIONS:
                        return self.respond({"error": "Selecciona como máximo 30 partidas."}, 400)
                    if not session_ids or any(not value or len(value) > 100 or not all(char.isalnum() or char in "_-" for char in value) for value in session_ids):
                        return self.respond({"error": "Las partidas seleccionadas no son válidas."}, 400)
                    return self.respond(data_source.comparison(session_ids))
                prefix = next((prefix for prefix in ("/api/sessions/", "/api/export/") if path.startswith(prefix)), None)
                if prefix:
                    session_id = path[len(prefix):]
                    record = data_source.session(session_id)
                    if record is None:
                        return self.respond({"error": "La partida no existe."}, 404)
                    if prefix == "/api/sessions/":
                        return self.respond(record)
                    fmt = parse_qs(parsed.query).get("format", ["json"])[0]
                    if fmt == "csv":
                        output = io.StringIO(newline="")
                        writer = csv.writer(output)
                        writer.writerow(("event_id", "session_id", "seq", "kind", "ts", "elapsed", "level", "x", "y", "z", "data_json"))
                        for event in record["events"]:
                            position = event["position"] or {}
                            cells = [event[key] for key in ("event_id", "session_id", "seq", "kind", "ts", "elapsed", "level")]
                            cells += [position.get(key, "") for key in ("x", "y", "z")]
                            cells.append(json.dumps(event["data"], ensure_ascii=False))
                            # Prevent spreadsheet formulas in arbitrary player/event text.
                            writer.writerow(["'" + cell if isinstance(cell, str) and cell.startswith(("=", "+", "-", "@", "\t", "\r")) else cell for cell in cells])
                        return self.respond(output.getvalue().encode("utf-8-sig"), content_type="text/csv; charset=utf-8", disposition='attachment; filename="resonance-partida.csv"')
                    if fmt == "json":
                        return self.respond(record, disposition='attachment; filename="resonance-partida.json"')
                    return self.respond({"error": "Formato disponible: json o csv."}, 400)
                return self.respond({"error": "Ruta no encontrada."}, 404)
            except (sqlite3.Error, OSError) as error:
                self.server.archive.last_error = type(error).__name__
                return self.respond({"error": "No se pudo consultar el archivo de partidas. Revisa URL, permisos y conexión del servidor."}, 503)
        # Explicit allowlist avoids exposing SQLite, logs, Python or project files.
        assets = {"/": "index.html", "/index.html": "index.html", "/style.css": "style.css", "/app.js": "app.js", "/replay.js": "replay.js", "/favicon.svg": "favicon.svg"}
        filename = assets.get(path)
        if filename is None:
            return self.respond({"error": "Ruta no encontrada."}, 404)
        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        if filename.endswith((".html", ".css", ".js", ".svg")):
            content_type += "; charset=utf-8"
        return self.respond((ROOT / "web" / filename).read_bytes(), content_type=content_type)


def main():
    parser = argparse.ArgumentParser(description="Archivo local de partidas de Resonance of the Dark")
    parser.add_argument("--host", choices=("127.0.0.1", "localhost", "0.0.0.0"), default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data-dir", type=Path, default=ROOT / "data", help="Directorio SQLite y spool (por defecto telemetry/data)")
    parser.add_argument("--spool-dir", type=Path, help="Lee los JSONL de esta carpeta; útil para el user:// de una exportación")
    parser.add_argument("--supabase-url", default=os.environ.get("SUPABASE_URL", ""), help="URL del proyecto; también puede venir de SUPABASE_URL")
    parser.add_argument("--import-only", action="store_true", help="Importa los logs pendientes y termina")
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("El puerto debe estar entre 0 y 65535.")
    archive = Archive(args.data_dir, args.spool_dir)
    archive.import_pending()
    if args.import_only:
        print(json.dumps(archive.health(), ensure_ascii=False))
        return
    secret_key = os.environ.get("SUPABASE_SECRET_KEY", "") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    remote_archive = None
    if args.supabase_url and secret_key:
        remote_archive = RemoteArchive(args.supabase_url, secret_key)
        print("Panel conectado a Supabase. La clave permanece en este proceso local.", flush=True)
    elif args.supabase_url or secret_key:
        print("Configuración de Supabase incompleta; el panel seguirá usando el archivo SQLite local.", flush=True)
    try:
        server = DashboardServer((args.host, args.port), archive, remote_archive)
    except OSError as error:
        parser.exit(1, f"No se pudo abrir el puerto {args.port}: {error}\nPrueba --port 8766.\n")
    stop = threading.Event()

    def ingest():
        while not stop.wait(1):
            try:
                archive.import_pending()
            except (sqlite3.Error, OSError) as error:
                archive.last_error = type(error).__name__
                print("No se pudo importar el registro:", error, flush=True)

    threading.Thread(target=ingest, daemon=True).start()
    print(f"Archivo de partidas: http://{args.host}:{server.server_port}\nSQLite: {archive.db_path}\nCtrl+C para detener.", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()


if __name__ == "__main__":
    main()
