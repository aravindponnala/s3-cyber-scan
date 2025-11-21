resource "aws_lambda_function" "api" {
  function_name = "scanner-api"
  role          = aws_iam_role.lambda_api.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "build/api.zip"  # or S3 object

  environment {
    variables = {
      DB_HOST    = aws_db_instance.postgres.address
      DB_NAME    = var.db_name
      DB_USER    = var.db_username
      DB_PASSWORD = var.db_password
      QUEUE_URL  = aws_sqs_queue.scan_jobs.id
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "scanner-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "scan_post" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /scan"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "results_get" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /results"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "job_get" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /jobs/{job_id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
