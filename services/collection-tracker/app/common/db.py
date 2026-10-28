import os
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row


def _database_url() -> str:
    return os.environ["DATABASE_URL"]


@contextmanager
def get_conn():
    conn = psycopg.connect(_database_url(), row_factory=dict_row, autocommit=True)
    try:
        yield conn
    finally:
        conn.close()
