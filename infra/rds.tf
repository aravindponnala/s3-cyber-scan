###############################################
# DB Subnet Group (requires 2 private subnets)
###############################################
resource "aws_db_subnet_group" "postgres" {
  name       = "scanner-postgres-subnets"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "scanner-postgres-subnets"
  }
}

###############################################
# RDS Postgres Instance
###############################################
resource "aws_db_instance" "postgres" {
  identifier              = "scanner-postgres"
  engine                  = "postgres"
  engine_version          = "15.7"
  instance_class          = "db.t3.micro"     # cheapest option
  allocated_storage       = 20
  storage_type            = "gp2"

  username                = var.db_username
  password                = var.db_password
  db_name                 = var.db_name

  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.postgres.name

  skip_final_snapshot     = true
  publicly_accessible     = false

  deletion_protection     = false

  tags = {
    Name = "scanner-postgres"
  }
}
