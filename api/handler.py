import json
import os
import urllib.parse as urlparse

import boto3
import psycopg2

DB_PARAMS = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ.get("DB_PORT", 5432)),
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "dbname": os.environ["DB_NAME"],
}

sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION"))
s3 = boto3.client("s3", region_name=os.getenv("AWS_REGION"))
QUEUE_URL = os.environ["QUEUE_URL"]

def get_conn():
    return psycopg2.connect(**DB_PARAMS)

def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }

def handle_post_scan(event):
    body = json.loads(event.get("body") or "{}")
    bucket = body["bucket"]
    prefix = body.get("prefix", "")

    conn = get_conn()
    cur = conn.cursor()

    # create job
    cur.execute(
        "INSERT INTO jobs(bucket,prefix) VALUES (%s,%s) RETURNING job_id",
        (bucket, prefix)
    )
    job_id = cur.fetchone()[0]

    # enumerate S3 objects
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            etag = obj["ETag"].strip('"')
            # insert job_object
            cur.execute(
                """
                INSERT INTO job_objects(job_id,bucket,key,etag,status)
                VALUES (%s,%s,%s,%s,'queued')
                ON CONFLICT DO NOTHING
                """,
                (job_id, bucket, key, etag)
            )
            # enqueue SQS message
            msg = {
                "job_id": str(job_id),
                "bucket": bucket,
                "key": key,
                "etag": etag,
            }
            sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(msg))

    conn.commit()
    cur.close()
    conn.close()

    return _response(202, {"job_id": str(job_id)})

def handle_get_job(event, job_id):
    conn = get_conn()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT job_id,bucket,prefix,created_at,updated_at
        FROM jobs
        WHERE job_id = %s
        """,
        (job_id,)
    )
    row = cur.fetchone()
    if not row:
        return _response(404, {"error": "job not found"})

    job = {
        "job_id": str(row[0]),
        "bucket": row[1],
        "prefix": row[2],
        "created_at": row[3].isoformat(),
        "updated_at": row[4].isoformat(),
    }

    cur.execute(
        """
        SELECT status, count(*) 
        FROM job_objects
        WHERE job_id = %s
        GROUP BY status
        """,
        (job_id,)
    )
    counts = {r[0]: r[1] for r in cur.fetchall()}

    conn.close()
    return _response(200, {"job": job, "counts": counts})

def handle_get_results(event):
    query = event.get("rawQueryString", "")
    q = dict(urlparse.parse_qsl(query))

    bucket = q.get("bucket")
    prefix = q.get("prefix")
    limit = int(q.get("limit", "100"))
    cursor = q.get("cursor")

    conn = get_conn()
    cur = conn.cursor()

    sql = """
        SELECT id, job_id, bucket, key, detector, masked_match, context, byte_offset, created_at
        FROM findings
        WHERE 1=1
    """
    params = []
    if bucket:
        sql += " AND bucket = %s"
        params.append(bucket)
    if prefix:
        sql += " AND key LIKE %s"
        params.append(prefix + "%")
    if cursor:
        sql += " AND id > %s"
        params.append(int(cursor))

    sql += " ORDER BY id ASC LIMIT %s"
    params.append(limit)

    cur.execute(sql, params)
    rows = cur.fetchall()

    items = []
    next_cursor = None
    for r in rows:
        next_cursor = r[0]
        items.append({
            "id": r[0],
            "job_id": str(r[1]),
            "bucket": r[2],
            "key": r[3],
            "detector": r[4],
            "masked_match": r[5],
            "context": r[6],
            "byte_offset": r[7],
            "created_at": r[8].isoformat(),
        })

    conn.close()
    return _response(200, {"items": items, "next_cursor": next_cursor})

def lambda_handler(event, context):
    method = event["requestContext"]["http"]["method"]
    path = event["rawPath"]

    if method == "POST" and path == "/scan":
        return handle_post_scan(event)

    if method == "GET" and path.startswith("/jobs/"):
        job_id = path.split("/jobs/")[1]
        return handle_get_job(event, job_id)

    if method == "GET" and path == "/results":
        return handle_get_results(event)

    return _response(404, {"error": "not found"})
