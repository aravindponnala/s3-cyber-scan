resource "aws_sqs_queue" "scan_jobs_dlq" {
  name                      = "scan-jobs-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "scan_jobs" {
  name                       = "scan-jobs"
  visibility_timeout_seconds = 120  # long enough for scan
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.scan_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}
