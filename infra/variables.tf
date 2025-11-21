variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "db_username" { type = string }
variable "db_password" { type = string }
variable "db_name" {
  type    = string
  default = "scanner"
}

variable "test_bucket_name" {
  type = string
}

variable "scanner_image" {
  type = string  # ECR image URI for ECS worker
}

variable "api_lambda_image" {
  type    = string
  default = ""   # if you use container lambda
}
variable "ec2_key_name" {
  type = string
}

