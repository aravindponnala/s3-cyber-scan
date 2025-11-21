import json
import logging
import os
import time

import boto3

from detectors import detect_all
from db import insert_findings, update_job_object_status

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION"))
s3 = boto3.client("s3", region_name=os.getenv("AWS_REGION"))

QUEUE_URL = os.environ["QUEUE_URL"]

def process_message(msg_body: dict):
    bucket = msg_body["bucket"]
    key = msg_body["key"]
    job_id = msg_body["job_id"]
    etag = msg_body["etag"]

    logger.info("Processing %s/%s job=%s", bucket, key, job_id)

    # mark processing
    update_job_object_status(job_id, bucket, key, etag, "processing", None)

    # fetch S3 object
    obj = s3.get_object(Bucket=bucket, Key=key)
    raw = obj["Body"].read()

    # naive: assume text encoding
    try:
        text = raw.decode("utf-8", errors="ignore")
    except Exception:
        text = raw.decode("latin-1", errors="ignore")

    findings = detect_all(text)
    insert_findings(job_id, bucket, key, etag, findings)

    update_job_object_status(job_id, bucket, key, etag, "succeeded", None)

def main_loop():
    while True:
        resp = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20,        # long polling
            VisibilityTimeout=60       # should be < queue visibility timeout
        )
        msgs = resp.get("Messages", [])
        if not msgs:
            continue

        for m in msgs:
            receipt_handle = m["ReceiptHandle"]
            try:
                body = json.loads(m["Body"])
                # if using SQS+Lambda style envelope, you may need to json.loads(body["Message"])
                process_message(body)
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
            except Exception as e:
                logger.exception("Failed processing message: %s", e)
                # let it become visible again; after 3 receives it will go to DLQ
                continue

        time.sleep(1)


if __name__ == "__main__":
    main_loop()
