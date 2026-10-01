"""Transactional local storage for a single server process."""
import json
import os
from pathlib import Path
import sqlite3


class RoomStore:
    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(descriptor)
        os.chmod(path, 0o600)
        self.connection = sqlite3.connect(path, check_same_thread=False)
        self.connection.execute(
            'CREATE TABLE IF NOT EXISTS rooms (code TEXT PRIMARY KEY, payload TEXT NOT NULL)'
        )
        self.connection.commit()
        self.saved = dict(self.connection.execute('SELECT code, payload FROM rooms'))

    def load(self):
        return [json.loads(payload) for payload in self.saved.values()]

    def save(self, code, data):
        payload = json.dumps(data, sort_keys=True)
        if self.saved.get(code) == payload:
            return
        with self.connection:
            self.connection.execute(
                'INSERT INTO rooms(code, payload) VALUES (?, ?) '
                'ON CONFLICT(code) DO UPDATE SET payload=excluded.payload',
                (code, payload),
            )
        self.saved[code] = payload

    def previous(self, code):
        payload = self.saved.get(code)
        return json.loads(payload) if payload is not None else None

    def close(self):
        self.connection.close()
