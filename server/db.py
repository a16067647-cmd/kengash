"""Ma’lumotlar bazasi / база данных.

Ishlab chiqarishda: Supabase Postgres (DATABASE_URL). Sinov va lokal: SQLite (KENGASH_DB, standart kengash.db).
В продакшене: Supabase Postgres (DATABASE_URL). Тесты и локально: SQLite.

SQL ikkala bazada ishlaydigan qilib yozilgan: '?' belgilar Postgres uchun '%s' ga almashtiriladi.
SQL написан так, чтобы работать в обеих базах: '?' заменяется на '%s' для Postgres.
"""

import os
import sqlite3
import threading
import time
from contextlib import contextmanager

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
IS_PG = DATABASE_URL.startswith(("postgres://", "postgresql://"))

SCHEMA = """
CREATE TABLE IF NOT EXISTS regions (
  id TEXT PRIMARY KEY, name_uz TEXT NOT NULL, name_ru TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS districts (
  id TEXT PRIMARY KEY, region_id TEXT NOT NULL, name_uz TEXT NOT NULL, name_ru TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'tuman', sort INTEGER NOT NULL DEFAULT 0, hidden INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS schools (
  id TEXT PRIMARY KEY, district_id TEXT NOT NULL, number INTEGER, name TEXT NOT NULL DEFAULT '',
  hidden INTEGER NOT NULL DEFAULT 0, created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS schools_district ON schools(district_id);
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY, tg_id BIGINT UNIQUE, tg_username TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL DEFAULT '', role TEXT NOT NULL DEFAULT 'user',
  level TEXT, place_id TEXT, direction TEXT,
  status TEXT NOT NULL DEFAULT 'active', photo_ver TEXT NOT NULL DEFAULT '',
  paid_until BIGINT NOT NULL DEFAULT 0, consent_version TEXT NOT NULL DEFAULT '', consent_at BIGINT NOT NULL DEFAULT 0,
  created_at BIGINT NOT NULL, last_seen BIGINT NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS users_seat ON users(level, place_id, direction) WHERE level IS NOT NULL;
CREATE TABLE IF NOT EXISTS photos (user_id TEXT PRIMARY KEY, data {BLOB} NOT NULL);
CREATE TABLE IF NOT EXISTS tokens (
  hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS tokens_user ON tokens(user_id);
CREATE TABLE IF NOT EXISTS login_requests (
  id TEXT PRIMARY KEY, created_at BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'new',
  tg_id BIGINT, tg_username TEXT NOT NULL DEFAULT '', first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS invite_keys (
  hash TEXT PRIMARY KEY, hint TEXT NOT NULL, level TEXT NOT NULL, place_id TEXT NOT NULL, direction TEXT NOT NULL,
  created_by TEXT NOT NULL, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL,
  used_by TEXT, used_at BIGINT, revoked INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS keys_creator ON invite_keys(created_by);
CREATE TABLE IF NOT EXISTS seat_contacts (
  level TEXT NOT NULL, place_id TEXT NOT NULL, direction TEXT NOT NULL, tg_username TEXT NOT NULL,
  PRIMARY KEY (level, place_id, direction)
);
CREATE TABLE IF NOT EXISTS settings (k TEXT PRIMARY KEY, v TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS reg_sessions (tg_id BIGINT PRIMARY KEY, step TEXT NOT NULL, data TEXT NOT NULL DEFAULT '{}', updated_at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS channels (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, auto_key TEXT UNIQUE, title_uz TEXT NOT NULL, title_ru TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '', icon TEXT NOT NULL DEFAULT '', mode TEXT NOT NULL DEFAULT 'group',
  created_by TEXT, created_at BIGINT NOT NULL, msg_seq BIGINT NOT NULL DEFAULT 0, last_msg_at BIGINT NOT NULL DEFAULT 0,
  pinned_msg TEXT
);
CREATE TABLE IF NOT EXISTS channel_members (
  channel_id TEXT NOT NULL, user_id TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'member', joined_at BIGINT NOT NULL,
  last_read BIGINT NOT NULL DEFAULT 0, muted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, user_id)
);
CREATE INDEX IF NOT EXISTS members_user ON channel_members(user_id);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, seq BIGINT NOT NULL, user_id TEXT, created_at BIGINT NOT NULL,
  text TEXT NOT NULL DEFAULT '', reply_to TEXT, attachments TEXT NOT NULL DEFAULT '[]',
  edited_at BIGINT NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS messages_seq ON messages(channel_id, seq);
CREATE TABLE IF NOT EXISTS polls (
  id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, question TEXT NOT NULL, options TEXT NOT NULL DEFAULT '[]',
  multi INTEGER NOT NULL DEFAULT 0, closed INTEGER NOT NULL DEFAULT 0, created_by TEXT NOT NULL, created_at BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS poll_votes (
  poll_id TEXT NOT NULL, user_id TEXT NOT NULL, opt INTEGER NOT NULL, at BIGINT NOT NULL, PRIMARY KEY (poll_id, user_id, opt)
);
CREATE INDEX IF NOT EXISTS messages_user ON messages(user_id);
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY, created_by TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
  deadline BIGINT NOT NULL, photo_required INTEGER NOT NULL DEFAULT 1, created_at BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS task_assignees (
  task_id TEXT NOT NULL, user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'new', comment TEXT NOT NULL DEFAULT '',
  photos TEXT NOT NULL DEFAULT '[]', review_note TEXT NOT NULL DEFAULT '', submitted_at BIGINT NOT NULL DEFAULT 0,
  reviewed_at BIGINT NOT NULL DEFAULT 0, PRIMARY KEY (task_id, user_id)
);
CREATE INDEX IF NOT EXISTS task_assignees_user ON task_assignees(user_id);
CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY, created_by TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
  place TEXT NOT NULL DEFAULT '', starts_at BIGINT NOT NULL, ends_at BIGINT NOT NULL DEFAULT 0, created_at BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS event_guests (
  event_id TEXT NOT NULL, user_id TEXT NOT NULL, rsvp TEXT NOT NULL DEFAULT '', PRIMARY KEY (event_id, user_id)
);
CREATE INDEX IF NOT EXISTS event_guests_user ON event_guests(user_id);
CREATE TABLE IF NOT EXISTS points (
  kind TEXT NOT NULL, ref_id TEXT NOT NULL, user_id TEXT NOT NULL, by_id TEXT NOT NULL,
  value INTEGER NOT NULL, created_at BIGINT NOT NULL, PRIMARY KEY (kind, ref_id, user_id)
);
CREATE INDEX IF NOT EXISTS points_user ON points(user_id, created_at);
CREATE TABLE IF NOT EXISTS books (
  direction TEXT PRIMARY KEY, id TEXT NOT NULL, title TEXT NOT NULL, author TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '', month TEXT NOT NULL, cover_path TEXT NOT NULL, pdf_path TEXT NOT NULL,
  pdf_size BIGINT NOT NULL DEFAULT 0, created_by TEXT NOT NULL, created_at BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS ideas (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL, district_id TEXT NOT NULL DEFAULT '', title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'open', reply TEXT NOT NULL DEFAULT '',
  replied_by TEXT NOT NULL DEFAULT '', created_at BIGINT NOT NULL, updated_at BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS idea_votes (idea_id TEXT NOT NULL, user_id TEXT NOT NULL, PRIMARY KEY (idea_id, user_id));
CREATE TABLE IF NOT EXISTS read_log (
  user_id TEXT NOT NULL, book_id TEXT NOT NULL, title TEXT NOT NULL, author TEXT NOT NULL DEFAULT '', at BIGINT NOT NULL,
  PRIMARY KEY (user_id, book_id)
);
CREATE TABLE IF NOT EXISTS book_reads (
  book_id TEXT NOT NULL, user_id TEXT NOT NULL, at BIGINT NOT NULL, PRIMARY KEY (book_id, user_id)
);
CREATE TABLE IF NOT EXISTS push_tokens (
  token TEXT PRIMARY KEY, user_id TEXT NOT NULL, platform TEXT NOT NULL DEFAULT '', created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS push_tokens_user ON push_tokens(user_id);
CREATE TABLE IF NOT EXISTS sent_once (k TEXT PRIMARY KEY, at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY, message_id TEXT NOT NULL, channel_id TEXT NOT NULL, reporter_id TEXT NOT NULL,
  reason TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_at BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'open'
);
"""


def now():
    return int(time.time())


class _Conn:
    """Bir xil interfeys / единый интерфейс: q(), one(), x()."""

    def memo(self, name):
        """Tranzaksiya ichidagi kesh; har bir x() (yozuv) uni tozalaydi / кэш в транзакции; x() (запись) его сбрасывает."""
        return self.__dict__.setdefault("_memo", {}).setdefault(name, {})

    def __init__(self, raw):
        self.raw = raw

    def _sql(self, sql):
        # literal % (LIKE 'x%') psycopg uchun ikkilanadi / литеральный % экранируется для psycopg
        return sql.replace("%", "%%").replace("?", "%s") if IS_PG else sql

    def q(self, sql, params=()):
        cur = self.raw.cursor()
        cur.execute(self._sql(sql), tuple(params))
        if cur.description is None:
            return []
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]

    def one(self, sql, params=()):
        rows = self.q(sql, params)
        return rows[0] if rows else None

    def x(self, sql, params=()):
        self.__dict__.pop("_memo", None)  # yozuvdan keyin kesh eskiradi / после записи кэш сбрасывается
        cur = self.raw.cursor()
        cur.execute(self._sql(sql), tuple(params))
        return cur.rowcount


_sqlite_lock = threading.RLock()
_sqlite = None
_pool = None


def _sqlite_conn():
    global _sqlite
    if _sqlite is None:
        path = os.environ.get("KENGASH_DB", os.path.join(os.path.dirname(__file__), "kengash.db"))
        _sqlite = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        _sqlite.execute("PRAGMA journal_mode=WAL")
        _sqlite.execute("PRAGMA foreign_keys=ON")
    return _sqlite


@contextmanager
def tx():
    """Tranzaksiya / транзакция: `with tx() as c: c.q(...)`."""
    if IS_PG:
        global _pool
        if _pool is None:
            from psycopg_pool import ConnectionPool
            _pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=int(os.environ.get("DB_POOL", "8")),
                                   kwargs={"autocommit": False, "prepare_threshold": None}, open=True)
        with _pool.connection() as raw:
            yield _Conn(raw)  # pool commits on success, rolls back on error
    else:
        with _sqlite_lock:
            raw = _sqlite_conn()
            raw.execute("BEGIN")
            try:
                yield _Conn(raw)
                raw.execute("COMMIT")
            except BaseException:
                raw.execute("ROLLBACK")
                raise


def init():
    schema = SCHEMA.replace("{BLOB}", "BYTEA" if IS_PG else "BLOB")
    with tx() as c:
        for stmt in [s.strip() for s in schema.split(";") if s.strip()]:
            c.x(stmt)
    migrate()
    import seed
    seed.run()


# Yangi ustunlar (eski bazalar uchun) / новые столбцы (для старых баз): (jadval, ustun, tavsif)
COLUMNS = [
    ("users", "notify_tg", "INTEGER NOT NULL DEFAULT 1"),
    ("users", "kind", "TEXT NOT NULL DEFAULT ''"),
    ("users", "class_name", "TEXT NOT NULL DEFAULT ''"),
    ("reports", "kind", "TEXT NOT NULL DEFAULT 'message'"),
    ("reports", "photo_path", "TEXT NOT NULL DEFAULT ''"),
    ("reports", "reply", "TEXT NOT NULL DEFAULT ''"),
    ("channels", "photo_ver", "TEXT NOT NULL DEFAULT ''"),
    ("books", "colors", "TEXT NOT NULL DEFAULT ''"),
    ("books", "cover_hq", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "title", "TEXT NOT NULL DEFAULT ''"),
    ("users", "powers", "TEXT NOT NULL DEFAULT ''"),
    ("events", "checkin_key", "TEXT NOT NULL DEFAULT ''"),
    ("event_guests", "checked_at", "BIGINT NOT NULL DEFAULT 0"),
    ("users", "last_rank", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "share_token", "TEXT NOT NULL DEFAULT ''"),
    ("task_assignees", "voice", "TEXT NOT NULL DEFAULT ''"),       # ovozli hisobot / голосовой отчёт
    ("task_assignees", "voice_sec", "INTEGER NOT NULL DEFAULT 0"),
]


def migrate():
    with tx() as c:
        for table, col, decl in COLUMNS:
            if IS_PG:
                have = c.one("SELECT 1 AS x FROM information_schema.columns WHERE table_name=? AND column_name=? "
                             "AND table_schema=current_schema()", (table, col))
            else:
                have = any(r["name"] == col for r in c.q(f"PRAGMA table_info({table})"))
            if not have:
                c.x(f"ALTER TABLE {table} ADD COLUMN {col} {decl}")


def close():
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def reset_for_tests():
    """Faqat testlar uchun / только для тестов."""
    global _sqlite
    if _sqlite is not None:
        _sqlite.close()
        _sqlite = None
