resource "aws_ecs_cluster" "scanner" {
  name = "scanner-cluster"
}

resource "aws_ecs_task_definition" "scanner_worker" {
  family                   = "scanner-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "scanner-worker",
      image     = var.scanner_image,
      essential = true,
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/scanner-worker"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
      environment = [
        { name = "DB_HOST",  value = aws_db_instance.postgres.address },
        { name = "DB_NAME",  value = var.db_name },
        { name = "DB_USER",  value = var.db_username },
        { name = "DB_PASSWORD", value = var.db_password },
        { name = "QUEUE_URL", value = aws_sqs_queue.scan_jobs.id },
        { name = "AWS_REGION", value = var.aws_region },
      ]
    }
  ])
}

resource "aws_ecs_service" "scanner_worker" {
  name            = "scanner-worker"
  cluster         = aws_ecs_cluster.scanner.id
  task_definition = aws_ecs_task_definition.scanner_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_a.id]
    security_groups = [aws_security_group.ecs_tasks.id]
  }
}

resource "aws_appautoscaling_target" "scanner" {
  max_capacity       = 5
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.scanner.name}/${aws_ecs_service.scanner_worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scanner_queue_scaling" {
  name               = "scanner-queue-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.scanner.resource_id
  scalable_dimension = aws_appautoscaling_target.scanner.scalable_dimension
  service_namespace  = aws_appautoscaling_target.scanner.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 50
    scale_in_cooldown  = 60
    scale_out_cooldown = 60

    predefined_metric_specification {
  predefined_metric_type = "ECSServiceAverageCPUUtilization"
}

  }
}

