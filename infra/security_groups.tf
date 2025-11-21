###############################################
# ECS TASKS SG
###############################################
resource "aws_security_group" "ecs_tasks" {
  name        = "scanner-ecs-tasks-sg"
  description = "ECS tasks SG"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################
# LAMBDA SG  (NO INGRESS HERE)
###############################################
resource "aws_security_group" "lambda" {
  name        = "scanner-lambda-sg"
  description = "Lambda outbound access only"
  vpc_id      = aws_vpc.main.id

  # Lambda only needs outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################
# RDS SG  (ALLOW inbound FROM ECS + LAMBDA + BASTION)
###############################################
resource "aws_security_group" "rds" {
  name        = "scanner-rds-sg"
  description = "Allow Postgres from ECS, Lambda, Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Postgres from ECS tasks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.ecs_tasks.id
    ]
  }

  ingress {
    description = "Postgres from Lambda"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.lambda.id
    ]
  }

  ingress {
    description = "Postgres from bastion"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.bastion.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################
# BASTION SG
###############################################
resource "aws_security_group" "bastion" {
  name        = "scanner-bastion-sg"
  description = "SSH from your IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["24.184.200.181/32"]  # Replace!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
