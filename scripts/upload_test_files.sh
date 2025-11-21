#!/usr/bin/env bash
set -euo pipefail

BUCKET_NAME="aravind-scanner-test-bucket-123"
PREFIX="samples/"

for f in test_files/*.txt; do
  aws s3 cp "$f" "s3://${BUCKET_NAME}/${PREFIX}$(basename "$f")"
done
