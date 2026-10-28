"""Applies schema.sql then seed.sql. Safe to run on every pod start —
both files are written to be idempotent (IF NOT EXISTS / ON CONFLICT).
Used as the API Deployment's initContainer command.
"""

import logging
import pathlib

from common.db import get_conn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB_DIR = pathlib.Path(__file__).resolve().parent.parent / "db"


def main():
    with get_conn() as conn:
        for filename in ("schema.sql", "seed.sql"):
            sql = (DB_DIR / filename).read_text()
            conn.execute(sql)
            logger.info("Applied %s", filename)


if __name__ == "__main__":
    main()
