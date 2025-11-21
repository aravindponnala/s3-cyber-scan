# S3 Sensitive Data Scanner

AWS-based service that scans S3 files for sensitive data (SSN, credit cards, AWS keys, emails, phone numbers) using ECS Fargate workers and exposes REST APIs for scan management.

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP
       ▼
┌─────────────────────────────────────────────────────────────┐
│                    API Gateway (HTTP API)                   |
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  Lambda Handler  │
                    │  (Private VPC)   │
                    └────┬────────┬────┘
                         │        │
        ┌────────────────┘        └─────────────┐
        │                                       │
        ▼                                       ▼
┌───────────────┐                      ┌──────────────┐
│  RDS Postgres │                      │  SQS Queue   │
│  (Private)    │                      │  scan-jobs   │
│               │                      └──────┬───────┘
│ • jobs        │                             │
│ • job_objects │◄────────────────────────────┤
│ • findings    │                             │
└───────────────┘                             │
        ▲                                     │
        │                                     │
        │                              ┌──────▼──────────┐
        │                              │  ECS Fargate    │
        │                              │  scanner-worker │
        └──────────────────────────────┤  (Private VPC)  │
                                       │                 │
                                       │  • Polls SQS    │
                                       │  • Scans S3     │
                                       │  • Writes RDS   │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │   S3 Bucket     │
                                       │   (test files)  │
                                       └─────────────────┘
                                       
┌────────────────────────────────────────────────────────────┐
│                    SQS Dead Letter Queue                   │
│                      (scan-jobs-dlq)                       │
│              Failed messages after 3 retries               │
└────────────────────────────────────────────────────────────┘
```

## Message Flow

### 1. POST /scan - Initiate Scan
```
Client → API Gateway → Lambda
                        │
                        ├─→ RDS: INSERT job, job_objects
                        │
                        └─→ SQS: Enqueue messages
                             (one per S3 object)
```

**SQS Message Format:**
```json
{
  "job_id": "uuid",
  "bucket": "bucket-name",
  "key": "path/to/file.txt",
  "etag": "object-etag"
}
```

### 2. Worker Processing
```
ECS Fargate Worker (long polling, 20s)
  │
  ├─→ SQS: ReceiveMessage (visibility timeout: 60s)
  │
  ├─→ RDS: UPDATE job_objects SET status='processing'
  │
  ├─→ S3: GetObject (fetch file content)
  │
  ├─→ Scan: Detect sensitive patterns
  │
  ├─→ RDS: INSERT findings (with dedupe)
  │
  ├─→ RDS: UPDATE job_objects SET status='succeeded'
  │
  └─→ SQS: DeleteMessage
  
  On Error (exception):
    - Message becomes visible again
    - After 3 receives → DLQ
```

### 3. GET /jobs/{job_id} - Check Status
```
Client → API Gateway → Lambda → RDS: Query job + counts
                                      (queued/processing/succeeded/failed)
```

### 4. GET /results - Fetch Findings
```
Client → API Gateway → Lambda → RDS: Query findings
                                      (with pagination cursor)
```

## Key Configuration

### Visibility Timeout & Retries
- **SQS Queue Visibility Timeout**: 120 seconds
- **Worker ReceiveMessage Timeout**: 60 seconds (< queue timeout)
- **Max Receive Count**: 3 (then → DLQ)
- **DLQ Retention**: 14 days

### Autoscaling
- **Min Tasks**: 1
- **Max Tasks**: 5
- **Metric**: ECS CPU (currently) - should be SQS ApproximateNumberOfMessagesVisible
- **Target**: 50% CPU utilization

### Idempotency
- Unique index on `(bucket, key, etag, detector, byte_offset)` prevents duplicate findings
- Worker checks dedupe key before inserting

## Infrastructure Components

### VPC
- **Public Subnets** (2 AZs): NAT Gateway, Bastion, Internet Gateway
- **Private Subnets** (2 AZs): RDS, ECS Fargate, Lambda

### Compute
- **Lambda**: API handler (Python 3.11, VPC-attached)
- **ECS Fargate**: Scanner worker (256 CPU, 512 MB)
- **EC2 Bastion**: t3.micro for RDS debugging

### Storage
- **RDS Postgres 15.7**: db.t3.micro, 20GB gp2
- **S3**: Test bucket for sample files

### Queuing
- **SQS**: scan-jobs (main), scan-jobs-dlq

## API Endpoints

### POST /scan
Create a new scan job for S3 bucket/prefix.

**Request:**
```json
{
  "bucket": "my-bucket",
  "prefix": "path/to/scan/"
}
```

**Response (202):**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

### GET /jobs/{job_id}
Get job status and object counts.

**Response (200):**
```json
{
  "job": {
    "job_id": "550e8400-e29b-41d4-a716-446655440000",
    "bucket": "my-bucket",
    "prefix": "path/to/scan/",
    "created_at": "2025-11-21T00:00:00Z",
    "updated_at": "2025-11-21T00:05:00Z"
  },
  "counts": {
    "queued": 10,
    "processing": 2,
    "succeeded": 88,
    "failed": 0
  }
}
```

### GET /results
Query findings with optional filters.

**Query Parameters:**
- `bucket` (optional): Filter by bucket
- `prefix` (optional): Filter by key prefix
- `limit` (default: 100): Max results
- `cursor` (optional): Pagination cursor (last id)

**Response (200):**
```json
{
  "items": [
    {
      "id": 123,
      "job_id": "550e8400-e29b-41d4-a716-446655440000",
      "bucket": "my-bucket",
      "key": "file.txt",
      "detector": "ssn",
      "masked_match": "*****6789",
      "context": "SSN: 123-45-6789",
      "byte_offset": 42,
      "created_at": "2025-11-21T00:01:00Z"
    }
  ],
  "next_cursor": 123
}
```

## Detectors

- **SSN**: `\d{3}-\d{2}-\d{4}`
- **Credit Card**: 13-16 digits (Luhn validation recommended)
- **AWS Access Key**: `AKIA[0-9A-Z]{16}`
- **Email**: Standard email regex
- **US Phone**: Various formats including +1, parentheses, dashes

## Database Schema

```sql
jobs (
  job_id uuid PRIMARY KEY,
  bucket text,
  prefix text,
  created_at timestamptz,
  updated_at timestamptz
)

job_objects (
  job_id uuid,
  bucket text,
  key text,
  etag text,
  status enum('queued','processing','succeeded','failed'),
  last_error text,
  updated_at timestamptz,
  PRIMARY KEY (job_id, bucket, key, etag)
)

findings (
  id bigserial PRIMARY KEY,
  job_id uuid,
  bucket text,
  key text,
  etag text,
  detector text,
  masked_match text,
  context text,
  byte_offset int,
  created_at timestamptz,
  UNIQUE (bucket, key, etag, detector, byte_offset)
)
```

## Deployment

See `infra/TODO.md` for manual setup steps:
1. Create ECR repository and push scanner-worker image
2. Create S3 test bucket
3. Update `terraform.tfvars` with your values
4. Update security group with your IP
5. Run `terraform apply`
6. Connect to bastion and run SQL schema

## Project Structure

```
.
├── infra/                    # Terraform infrastructure
│   ├── main.tf
│   ├── vpc.tf
│   ├── rds.tf
│   ├── sqs.tf
│   ├── ecs_scanner.tf
│   ├── apigw_lambda.tf
│   ├── iam.tf
│   ├── security_groups.tf
│   └── bastion.tf
├── scanner-worker/           # ECS Fargate worker
│   ├── main.py
│   ├── detectors.py
│   ├── db.py
│   ├── Dockerfile
│   └── requirements.txt
├── api/                      # Lambda API handler
│   ├── handler.py
│   └── requirements.txt
└── scripts/                  # Testing utilities
    ├── sql_script.sql
    ├── generate_test_files.py
    └── upload_test_files.sh
```
