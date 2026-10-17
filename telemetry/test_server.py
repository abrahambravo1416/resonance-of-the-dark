"""Run: python3 -m unittest discover -s telemetry -p 'test_*.py' -v"""
import csv
import io
import json
import math
import tempfile
import threading
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

from server import Archive, DashboardServer, normalize_event


def event(seq, kind="position_sample", session="test-session", **changes):
    result = {"event_id": f"{session}:{seq}", "session_id": session, "seq": seq,
              "kind": kind, "ts": 1750000000.0 + seq, "elapsed": float(seq), "level": 1,
              "position": {"x": float(seq), "y": 0.0, "z": 0.0}, "data": {"attempt": 1}}
    result.update(changes)
    return result


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temp.name) / "data"
        self.archive = Archive(self.data_dir)
        self.log = self.archive.spool_dir / "test-session.jsonl"

    def tearDown(self):
        self.temp.cleanup()

    def append(self, *events):
        with self.log.open("ab") as stream:
            for item in events:
                stream.write((json.dumps(item) + "\n").encode())

    def test_schema_and_empty_archive(self):
        self.assertTrue(self.archive.db_path.is_file())
        self.assertEqual([], self.archive.sessions())
        self.assertEqual("SQLite", self.archive.health()["database"])

    def test_incremental_idempotence_and_restart(self):
        self.append(event(1, "session_started", data={"player_name": "Luz", "game_version": "test"}), event(2))
        self.archive.import_pending()
        self.archive.import_pending()
        second = Archive(self.data_dir)
        second.import_pending()
        self.append(event(2), event(3, "session_ended", data={"outcome": "completed"}))
        second.import_pending()
        result = second.session("test-session")
        self.assertEqual(3, len(result["events"]))
        self.assertEqual("Luz", result["session"]["player_name"])
        self.assertEqual("completed", result["session"]["outcome"])
        self.assertEqual("finished", result["session"]["status"])

    def test_partial_last_line_waits_until_newline(self):
        self.append(event(1))
        encoded = json.dumps(event(2, "item_collected", data={"item": "Calabaza ñ"}), ensure_ascii=False).encode()
        with self.log.open("ab") as stream:
            stream.write(encoded[:35])
        self.archive.import_pending()
        self.assertEqual(1, self.archive.health()["event_count"])
        with self.log.open("ab") as stream:
            stream.write(encoded[35:])
        self.archive.import_pending()
        self.assertEqual(1, self.archive.health()["event_count"])
        with self.log.open("ab") as stream:
            stream.write(b"\n")
        self.archive.import_pending()
        self.assertEqual("Calabaza ñ", self.archive.session("test-session")["events"][1]["data"]["item"])

    def test_rejects_bad_records_without_stopping_valid_events(self):
        self.append(event(1))
        with self.log.open("ab") as stream:
            stream.write(b"garbage\n{\"wrong\":1}\n")
        self.append(event(2), event(3, ts=math.inf))
        self.archive.import_pending()
        self.assertEqual(2, self.archive.health()["event_count"])
        self.assertEqual(3, self.archive.health()["rejected_lines"])

    def test_enemy_and_item_positions_do_not_count_as_player_distance(self):
        self.append(event(1), event(2, "enemy_state_changed", position={"x": 900, "y": 0, "z": 900}),
                    event(3, "item_collected", position={"x": -800, "y": 0, "z": 0}), event(4))
        self.archive.import_pending()
        self.assertEqual(3.0, self.archive.session("test-session")["session"]["distance"])

    def test_new_level_and_attempt_do_not_join_routes(self):
        self.append(event(1), event(2), event(3, "level_started", position=None, data={"attempt": 2}),
                    event(4, position={"x": 100, "y": 0, "z": 0}, data={"attempt": 2}),
                    event(5, position={"x": 102, "y": 0, "z": 0}, data={"attempt": 2}),
                    event(6, level=2, position={"x": 1000, "y": 0, "z": 0}, data={"attempt": 3}))
        self.archive.import_pending()
        self.assertEqual(3.0, self.archive.session("test-session")["session"]["distance"])
        self.assertEqual(2, self.archive.session("test-session")["session"]["level_count"])

    def test_enemy_samples_persist_but_do_not_inflate_actions_or_distance(self):
        self.append(event(1), event(2, "enemy_position_sample", position={"x": 900, "y": 0, "z": 900},
                    data={"attempt": 1, "enemy_id": "World/Enemy_1", "enemy": "Enemy_1", "state": "chase", "yaw": 1.2}),
                    event(3, "hide_started", data={"attempt": 1, "hidden": True, "hiding": True}), event(4))
        self.archive.import_pending()
        result = self.archive.session("test-session")
        self.assertEqual(1, result["session"]["action_count"])
        self.assertEqual(3.0, result["session"]["distance"])
        self.assertEqual("World/Enemy_1", result["events"][1]["data"]["enemy_id"])
        self.assertTrue(result["events"][2]["data"]["hidden"])

    def test_append_after_truncation_deduplicates(self):
        self.append(event(1), event(2))
        self.archive.import_pending()
        self.log.write_text("")
        self.archive.import_pending()
        self.append(event(1), event(3))
        self.archive.import_pending()
        self.assertEqual(3, self.archive.health()["event_count"])

    def test_duplicate_cannot_change_player_metadata(self):
        self.append(event(1, "session_started", data={"player_name": "Original"}))
        self.archive.import_pending()
        self.append(event(1, "session_started", data={"player_name": "Changed"}))
        self.archive.import_pending()
        self.assertEqual("Original", self.archive.session("test-session")["session"]["player_name"])

    def test_external_spool_directory_and_symlink_safety(self):
        outside = Path(self.temp.name) / "exported_game"
        archive = Archive(Path(self.temp.name) / "new-data-dir", outside)
        (outside / "external.jsonl").write_text(json.dumps(event(1)) + "\n")
        secret = Path(self.temp.name) / "unrelated.jsonl"
        secret.write_text(json.dumps(event(2)) + "\n")
        (outside / "linked.jsonl").symlink_to(secret)
        archive.import_pending()
        self.assertEqual(1, archive.health()["event_count"])

    def test_invalid_coordinates_are_not_drawn(self):
        self.append(event(1, position={"x": "bad", "y": 0, "z": 0}))
        self.archive.import_pending()
        self.assertIsNone(self.archive.session("test-session")["events"][0]["position"])


class EndpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.archive = Archive(Path(self.temp.name))
        self.server = DashboardServer(("127.0.0.1", 0), self.archive)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temp.cleanup()

    def get(self, path):
        return urlopen(self.base + path, timeout=5)

    def test_http_imports_new_events_and_returns_json(self):
        (self.archive.spool_dir / "http.jsonl").write_text(json.dumps(event(1, "session_started", data={"player_name": "Ana"})) + "\n")
        with self.get("/api/sessions") as response:
            self.assertEqual("Ana", json.load(response)["sessions"][0]["player_name"])
        with self.get("/api/sessions/test-session") as response:
            self.assertEqual(1, len(json.load(response)["events"]))
        with self.get("/api/health") as response:
            self.assertTrue(json.load(response)["ok"])

    def test_static_and_private_paths(self):
        for path in ("/", "/app.js", "/replay.js", "/style.css", "/favicon.svg"):
            with self.get(path) as response:
                self.assertEqual(200, response.status)
                self.assertEqual("nosniff", response.headers["X-Content-Type-Options"])
                self.assertIn("frame-ancestors 'none'", response.headers["Content-Security-Policy"])
        for path in ("/../server.py", "/%2e%2e/schema.sql", "/data/resonance.sqlite3", "/api/sessions/missing"):
            with self.assertRaises(HTTPError) as error:
                self.get(path)
            self.assertEqual(404, error.exception.code)

    def test_export_csv_sanitizes_formula_and_preserves_data(self):
        payload = event(1, kind="=FORMULA", session="=session", data={"item": "Calabaza"})
        (self.archive.spool_dir / "csv.jsonl").write_text(json.dumps(payload) + "\n")
        with self.get("/api/export/%3Dsession?format=csv") as response:
            self.assertIn("attachment", response.headers["Content-Disposition"])
            rows = list(csv.reader(io.StringIO(response.read().decode("utf-8-sig"))))
            self.assertEqual("'=FORMULA", rows[1][3])
            self.assertEqual("Calabaza", json.loads(rows[1][-1])["item"])
        with self.get("/api/export/%3Dsession?format=json") as response:
            self.assertEqual(payload, json.load(response)["events"][0])


if __name__ == "__main__":
    unittest.main()
