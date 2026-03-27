# ── Lecture du state de base/ ─────────────────────────────────────────
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

# ── ECR Repository ────────────────────────────────────────────────────
resource "aws_ecr_repository" "app" {
  name                 = "tp14-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true    # ← vide et supprime le repo automatiquement

  image_scanning_configuration { scan_on_push = true }

  tags = { Name = "tp14-app" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Garder 3 images max"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# ── Log Group CloudWatch ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/tp14-app"
  retention_in_days = 7
  tags              = { Name = "tp14-ecs-logs" }
}

# ── Security Group ALB ────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "tp14-sg-alb"
  description = "SG ALB public"
  vpc_id      = data.terraform_remote_state.base.outputs.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tp14-sg-alb" }
}

# ── Security Group Tasks ECS ──────────────────────────────────────────
resource "aws_security_group" "tasks" {
  name        = "tp14-sg-tasks"
  description = "SG tasks ECS Fargate"
  vpc_id      = data.terraform_remote_state.base.outputs.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tp14-sg-tasks" }
}

resource "aws_security_group_rule" "tasks_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.tasks.id
  source_security_group_id = aws_security_group.alb.id
  description              = "HTTP depuis ALB uniquement"
}

# ── ALB ───────────────────────────────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "tp14-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets = [
    data.terraform_remote_state.base.outputs.subnet_public_a_id,
    data.terraform_remote_state.base.outputs.subnet_public_b_id,
  ]

  tags = { Name = "tp14-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "tp14-tg-app"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.base.outputs.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "tp14-tg-app" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Rôle IAM ECS Task Execution ───────────────────────────────────────
resource "aws_iam_role" "ecs_exec" {
  name = "tp14-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── ECS Cluster ───────────────────────────────────────────────────────
resource "aws_ecs_cluster" "tp14" {
  name = "tp14-cluster"
  tags = { Name = "tp14-cluster" }
}

# ── Task Definition ───────────────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = "tp14-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_exec.arn

  container_definitions = jsonencode([{
    name  = "tp14-app"
    image = "${aws_ecr_repository.app.repository_url}:v2"

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "APP_VERSION", value = "v2" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.terraform_remote_state.base.outputs.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    essential = true
  }])

  tags = { Name = "tp14-task-def" }
}

# ── Service ECS ───────────────────────────────────────────────────────
resource "aws_ecs_service" "app" {
  name            = "tp14-service"
  cluster         = aws_ecs_cluster.tp14.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets = [
      data.terraform_remote_state.base.outputs.subnet_private_a_id,
      data.terraform_remote_state.base.outputs.subnet_private_b_id,
    ]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "tp14-app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]
  tags       = { Name = "tp14-service" }
}