output "api_endpoint" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "sqs_queue_url" {
  value = aws_sqs_queue.scan_jobs.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
