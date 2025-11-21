import os
import psycopg2
from contextlib import contextmanager

DB_PARAMS = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ.get("DB_PORT", 5432)),
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "dbname": os.environ["DB_NAME"],
}

@contextmanager
def get_conn():
    conn = psycopg2.connect(**DB_PARAMS)
    try:
        yield conn
    finally:
        conn.close()

def update_job_object_status(job_id, bucket, key, etag, status, last_error=None):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE job_objects
                SET status = %s, last_error = %s, updated_at = now()
                WHERE job_id = %s AND bucket = %s AND key = %s AND etag = %s
                """,
                (status, last_error, job_id, bucket, key, etag)
            )
        conn.commit()

def insert_findings(job_id, bucket, key, etag, findings):
    if not findings:
        return
    with get_conn() as conn:
        with conn.cursor() as cur:
            for f in findings:
                try:
                    cur.execute(
                        """
                        INSERT INTO findings(job_id, bucket, key, detector, masked_match, context, byte_offset)
                        VALUES (%s,%s,%s,%s,%s,%s,%s)
                        ON CONFLICT(bucket,key,etag,detector,byte_offset) DO NOTHING
                        """,
                        (job_id, bucket, key, f["detector"], f["masked_match"], f["context"], f["byte_offset"])
                    )
                except Exception:
                    # swallow per-row dup errors if any
                    continue
        conn.commit()
