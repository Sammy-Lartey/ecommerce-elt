resource "aws_ecs_cluster" "ecom" {
  name = "ecom"
}

resource "aws_cloudwatch_log_group" "dbt" {
  name              = "/ecs/ecom-dbt"
  retention_in_days = 14
}

resource "aws_security_group" "dbt_task" {
  name        = "ecom-dbt-task"
  description = "dbt Fargate task, outbound only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dbt_execution" {
  name               = "ecom-dbt-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "dbt_execution_base" {
  role       = aws_iam_role.dbt_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "dbt_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_redshiftserverless_namespace.ecom.admin_password_secret_arn]
  }
}

resource "aws_iam_role_policy" "dbt_secret" {
  name   = "read-redshift-admin-secret"
  role   = aws_iam_role.dbt_execution.id
  policy = data.aws_iam_policy_document.dbt_secret.json
}

resource "aws_ecs_task_definition" "dbt" {
  family                   = "ecom-dbt"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.dbt_execution.arn

  container_definitions = jsonencode([{
    name      = "dbt"
    image     = "${aws_ecr_repository.dbt.repository_url}:latest"
    essential = true

    secrets = [{
      name      = "DBT_PASSWORD"
      valueFrom = "${aws_redshiftserverless_namespace.ecom.admin_password_secret_arn}:password::"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.dbt.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "dbt"
      }
    }
  }])
}