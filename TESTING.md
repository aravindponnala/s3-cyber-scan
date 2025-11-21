# Testing Guide

## Prerequisites

- Terraform infrastructure deployed
- API Gateway endpoint from `terraform output api_endpoint`
- S3 bucket created
- RDS schema initialized

## 1. Generate Test Files (500+)

Generate 500 small test files with sensitive data:

```bash
cd scripts
python3 generate_test_files.py
```

This creates `test_files/` directory with 500 files containing:
- SSNs (every 10th file)
- Credit cards (every 7th file)
- Emails (every 5th file)

**Verify:**
```bash
ls test_files/ | wc -l
# Should show 500
```

## 2. Upload Test Files to S3

```bash
cd scripts
export BUCKET_NAME="your-bucket-name"  # Update this
export PREFIX="samples/"

# Upload all files
for f in test_files/*.txt; do
  aws s3 cp "$f" "s3://${BUCKET_NAME}/${PREFIX}$(basename "$f")"
done
```

**Verify upload:**
```bash
aws s3 ls s3://${BUCKET_NAME}/${PREFIX} | wc -l
# Should show 500
```

## 3. Trigger Scan via API

Get your API endpoint:
```bash
cd ../infra
export API_ENDPOINT=$(terraform output -raw api_endpoint)
echo $API_ENDPOINT
```

Create a scan job:
```bash
curl -X POST "${API_ENDPOINT}/scan" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "your-bucket-name",
    "prefix": "samples/"
  }'
```

**Expected Response:**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

Save the job_id:
```bash
export JOB_ID="<job_id_from_response>"
```

## 4. Poll Job Status

Check job progress:
```bash
curl "${API_ENDPOINT}/jobs/${JOB_ID}"
```

**Response:**
```json
{
  "job": {
    "job_id": "550e8400-...",
    "bucket": "your-bucket-name",
    "prefix": "samples/",
    "created_at": "2025-11-21T00:00:00Z",
    "updated_at": "2025-11-21T00:05:00Z"
  },
  "counts": {
    "queued": 450,
    "processing": 2,
    "succeeded": 48,
    "failed": 0
  }
}
```

**Poll until completion:**
```bash
# Poll every 10 seconds
while true; do
  curl -s "${API_ENDPOINT}/jobs/${JOB_ID}" | jq '.counts'
  sleep 10
done
```

Job is complete when `queued + processing = 0`.

## 5. Fetch Results

Get all findings:
```bash
curl "${API_ENDPOINT}/results?bucket=your-bucket-name&limit=100"
```

**Response:**
```json
{
  "items": [
    {
      "id": 1,
      "job_id": "550e8400-...",
      "bucket": "your-bucket-name",
      "key": "samples/sample_0.txt",
      "detector": "ssn",
      "masked_match": "*****6789",
      "context": "SSN: 123-45-6789",
      "byte_offset": 10,
      "created_at": "2025-11-21T00:01:00Z"
    }
  ],
  "next_cursor": 100
}
```

**Paginate through results:**
```bash
# First page
curl "${API_ENDPOINT}/results?limit=100" > page1.json

# Get cursor from response
CURSOR=$(jq -r '.next_cursor' page1.json)

# Next page
curl "${API_ENDPOINT}/results?limit=100&cursor=${CURSOR}" > page2.json
```

**Filter by prefix:**
```bash
curl "${API_ENDPOINT}/results?bucket=your-bucket-name&prefix=samples/sample_1"
```

## 6. Monitor Queue Depth

### AWS Console
1. Navigate to SQS → `scan-jobs`
2. Click "Monitoring" tab
3. View metrics:
   - **ApproximateNumberOfMessagesVisible**: Messages waiting
   - **ApproximateNumberOfMessagesNotVisible**: Messages being processed
   - **NumberOfMessagesSent**: Total enqueued
   - **NumberOfMessagesDeleted**: Successfully processed

### AWS CLI
```bash
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw sqs_queue_url) \
  --attribute-names All \
  --query 'Attributes.{Visible:ApproximateNumberOfMessages,NotVisible:ApproximateNumberOfMessagesNotVisible,Delayed:ApproximateNumberOfMessagesDelayed}' \
  --output table
```

**Watch in real-time:**
```bash
watch -n 5 'aws sqs get-queue-attributes \
  --queue-url $(cd infra && terraform output -raw sqs_queue_url) \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible \
  --output table'
```

## 7. Check Dead Letter Queue

View messages that failed after 3 retries:

```bash
# Get DLQ URL
DLQ_URL=$(aws sqs list-queues --queue-name-prefix scan-jobs-dlq --query 'QueueUrls[0]' --output text)

# Check message count
aws sqs get-queue-attributes \
  --queue-url $DLQ_URL \
  --attribute-names ApproximateNumberOfMessages
```

**Receive DLQ messages:**
```bash
aws sqs receive-message \
  --queue-url $DLQ_URL \
  --max-number-of-messages 10
```

## 8. View ECS Logs

Check scanner-worker logs:

```bash
# Get log group
aws logs tail /ecs/scanner-worker --follow
```

**Filter for errors:**
```bash
aws logs filter-log-events \
  --log-group-name /ecs/scanner-worker \
  --filter-pattern "ERROR"
```

## 9. Verify Autoscaling

Monitor ECS service scaling:

```bash
aws ecs describe-services \
  --cluster scanner-cluster \
  --services scanner-worker \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount}' \
  --output table
```

**Watch scaling in action:**
```bash
watch -n 5 'aws ecs describe-services \
  --cluster scanner-cluster \
  --services scanner-worker \
  --query "services[0].{Desired:desiredCount,Running:runningCount}" \
  --output table'
```

Expected behavior:
- Starts with 1 task (min)
- Scales up to 5 tasks (max) under load
- Scales down after queue is empty

## 10. Database Verification

Connect to RDS via bastion:

```bash
# Get bastion IP
cd infra
BASTION_IP=$(terraform output -raw bastion_public_ip)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

# SSH tunnel
ssh -i scanner-key.pem -L 5432:${RDS_ENDPOINT}:5432 ec2-user@${BASTION_IP}
```

In another terminal:
```bash
psql -h localhost -U scanner_admin -d scanner
```

**Query job status:**
```sql
SELECT status, COUNT(*) 
FROM job_objects 
WHERE job_id = '<your-job-id>'
GROUP BY status;
```

**Count findings:**
```sql
SELECT detector, COUNT(*) 
FROM findings 
WHERE job_id = '<your-job-id>'
GROUP BY detector;
```

**Check for duplicates (should be 0):**
```sql
SELECT bucket, key, etag, detector, byte_offset, COUNT(*)
FROM findings
GROUP BY bucket, key, etag, detector, byte_offset
HAVING COUNT(*) > 1;
```

## 11. Test Idempotency

Reprocess the same files to verify no duplicate findings:

```bash
# Trigger another scan on same prefix
curl -X POST "${API_ENDPOINT}/scan" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "your-bucket-name",
    "prefix": "samples/"
  }'

# Get new job_id
export JOB_ID2="<new-job-id>"

# Wait for completion
curl "${API_ENDPOINT}/jobs/${JOB_ID2}"

# Count findings for both jobs - should be same
curl "${API_ENDPOINT}/results?bucket=your-bucket-name" | jq '.items | length'
```

## 12. Performance Test

Time a full scan:

```bash
START=$(date +%s)

# Trigger scan
RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/scan" \
  -H "Content-Type: application/json" \
  -d '{"bucket": "your-bucket-name", "prefix": "samples/"}')

JOB_ID=$(echo $RESPONSE | jq -r '.job_id')

# Poll until complete
while true; do
  STATUS=$(curl -s "${API_ENDPOINT}/jobs/${JOB_ID}")
  QUEUED=$(echo $STATUS | jq -r '.counts.queued // 0')
  PROCESSING=$(echo $STATUS | jq -r '.counts.processing // 0')
  
  if [ "$QUEUED" -eq 0 ] && [ "$PROCESSING" -eq 0 ]; then
    break
  fi
  
  echo "Queued: $QUEUED, Processing: $PROCESSING"
  sleep 5
done

END=$(date +%s)
DURATION=$((END - START))

echo "Scan completed in ${DURATION} seconds"
echo "Files: 500"
echo "Rate: $((500 / DURATION)) files/second"
```

## Complete Test Script

Save as `scripts/full_test.sh`:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Configuration
BUCKET_NAME="${BUCKET_NAME:-your-bucket-name}"
PREFIX="samples/"
NUM_FILES=500

echo "=== Generating ${NUM_FILES} test files ==="
python3 generate_test_files.py $NUM_FILES

echo "=== Uploading to S3 ==="
for f in test_files/*.txt; do
  aws s3 cp "$f" "s3://${BUCKET_NAME}/${PREFIX}$(basename "$f")" --quiet
done

echo "=== Triggering scan ==="
cd ../infra
API_ENDPOINT=$(terraform output -raw api_endpoint)
RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/scan" \
  -H "Content-Type: application/json" \
  -d "{\"bucket\": \"${BUCKET_NAME}\", \"prefix\": \"${PREFIX}\"}")

JOB_ID=$(echo $RESPONSE | jq -r '.job_id')
echo "Job ID: ${JOB_ID}"

echo "=== Polling job status ==="
while true; do
  STATUS=$(curl -s "${API_ENDPOINT}/jobs/${JOB_ID}")
  echo $STATUS | jq '.counts'
  
  QUEUED=$(echo $STATUS | jq -r '.counts.queued // 0')
  PROCESSING=$(echo $STATUS | jq -r '.counts.processing // 0')
  
  if [ "$QUEUED" -eq 0 ] && [ "$PROCESSING" -eq 0 ]; then
    break
  fi
  sleep 10
done

echo "=== Fetching results ==="
curl -s "${API_ENDPOINT}/results?bucket=${BUCKET_NAME}&limit=10" | jq '.items[] | {detector, masked_match, key}'

echo "=== Test complete ==="
```

Run with:
```bash
chmod +x scripts/full_test.sh
BUCKET_NAME=your-bucket-name ./scripts/full_test.sh
```
