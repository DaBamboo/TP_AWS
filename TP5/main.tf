data "aws_vpc" "vpc" {
    id = var.VPC_ID
}
data "aws_subnet" "priv1" {
    id = var.PRIV1_ID
}
data "aws_subnet" "priv2" {
    id = var.PRIV2_ID
}
data "aws_subnet" "pub1" {
    id = var.PUB1_ID
}
data "aws_subnet" "pub2" {
    id = var.PUB2_ID
}
data "aws_security_group" "sgweb" {
    id = var.SGWEB_ID
}
data "aws_security_group" "sgapp" {
    id = var.SGAPP_ID
}
data "aws_security_group" "sgdb" {
    id = var.SGDB_ID
}
data "aws_instance" "inst" {
    instance_id = var.INST_ID
}

#Création du Security Group pour le Load Balancer public
resource "aws_security_group" "sg_alb" {
  name        = "tp5-sg-alb"
  description = "Security Group pour le Load Balancer public"
  vpc_id      = var.VPC_ID

  ingress {
    description = "HTTP depuis internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "Port de test fonctionnel TP5"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   
  ingress {
    description = "HTTPS depuis internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Sortie vers les instances privees sur port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name       = "tp5-sg-alb"
    Project    = "FormationAWS"
    Env        = "Dev"
    Owner      = "ops-student"
    CostCenter = "IT-Training"
  }
}

# ============================================================
# LAUNCH TEMPLATE - Modele de creation des instances EC2
# ============================================================
resource "aws_launch_template" "tp5_lt" {
  name          = "tp5-launch-template"
  description   = "Template pour instances web privees du TP5"
  image_id      = var.AMI_ID
  instance_type = "t3.micro"

  # Pas de cle SSH - administration via SSM uniquement (bonne pratique securite)

  iam_instance_profile {
    name = "EC2ProfileSSMTP4"  # Le profil cree au TP4
  }

  # Forcer IMDSv2 (bonne pratique securite)
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  network_interfaces {
    associate_public_ip_address = false          # Pas d'IP publique
    security_groups             = [var.SGAPP_ID] 
    delete_on_termination       = true
  }

  # Script de demarrage : installe Apache et une page de test
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id)
    echo "<h1>VALENTIN Clément - TP5 - Serveur : $INSTANCE_ID</h1>" > /var/www/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name       = "tp5-instance-asg"
      Project    = "FormationAWS"
      Env        = "Dev"
      Owner      = "ops-student"
      CostCenter = "IT-Training"
    }
  }

  tags = {
    Name       = "tp5-launch-template"
    Project    = "FormationAWS"
    Env        = "Dev"
    Owner      = "ops-student"
    CostCenter = "IT-Training"
  }
}


# Mise a jour de SGAPP : autorise uniquement le trafic HTTP depuis l'ALB
resource "aws_security_group_rule" "app_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_alb.id
  security_group_id        = var.SGAPP_ID
  description              = "Autorise le trafic HTTP depuis l ALB vers les instances app"
}

# ============================================================
# TARGET GROUP - Liste des serveurs qui recoivent le trafic
# ============================================================
resource "aws_lb_target_group" "tp5_tg" {
  name        = "tp5-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.VPC_ID
  target_type = "instance"

  # Health check : verifie que le serveur web repond correctement
  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2    # 2 reponses OK = serveur sain
    unhealthy_threshold = 3    # 3 echecs = serveur retire du pool
    timeout             = 5    # secondes avant timeout
    interval            = 30   # verification toutes les 30 secondes
    matcher             = "200" # code HTTP attendu
  }

  tags = {
    Name       = "tp5-target-group"
    Project    = "FormationAWS"
    Env        = "Dev"
    Owner      = "ops-student"
    CostCenter = "IT-Training"
  }
}

# ============================================================
# ALB - Load Balancer public dans les subnets publics
# ============================================================
resource "aws_lb" "tp5_alb" {
  name               = "tp5-alb"
  internal           = false         # Public (exposé sur internet)
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_alb.id]
  subnets            = [var.PUB1_ID, var.PUB2_ID]

  # Securite : activer les logs d'acces
  enable_deletion_protection = false  # false pour pouvoir supprimer en TP

  tags = {
    Name       = "tp5-alb"
    Project    = "FormationAWS"
    Env        = "Dev"
    Owner      = "ops-student"
    CostCenter = "IT-Training"
  }
}

# Listener HTTP port 80 avec redirection vers HTTPS (bonne pratique securite)
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.tp5_alb.arn
  port              = 80
  protocol          = "HTTP"

  # Redirection 80 -> 443 (meme si on n'a pas de vrai certificat)
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"  # Redirection permanente
    }
  }
}

# Listener HTTP port 80 direct vers le Target Group (pour les tests du TP)
resource "aws_lb_listener" "http_forward" {
  load_balancer_arn = aws_lb.tp5_alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tp5_tg.arn
  }
}

# ============================================================
# AUTO SCALING GROUP - Gestion automatique des instances
# ============================================================
resource "aws_autoscaling_group" "tp5_asg" {
  name                = "tp5-asg"
  desired_capacity    = 2   # Nombre d'instances souhaite
  min_size            = 1   # Minimum garanti
  max_size            = 4   # Maximum autorise

  # Subnets PRIVES du TP3 - les instances ne sont jamais exposees
  vpc_zone_identifier = [var.PRIV1_ID, var.PRIV2_ID]

  # Attacher au Target Group de l'ALB
  target_group_arns = [aws_lb_target_group.tp5_tg.arn]

  # Remplacer une instance si le health check echoue
  health_check_type         = "ELB"
  health_check_grace_period = 120  # Laisser 2 min a l'instance pour demarrer

  # Utiliser le Launch Template cree a l'etape 2
  launch_template {
    id      = aws_launch_template.tp5_lt.id
    version = "$Latest"
  }

  # Politique de remplacement : creer le nouveau avant de supprimer l'ancien
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  #aws_autoscaling_group utilise une syntaxe de tag un peu speciale pour propager les tags aux instances creees
  #il faut un bloc tag avec propagate_at_launch = true pour chaque tag a propager
  #cela permet au tag de se propager automatiquement aux instances creees par l'ASG

  tag {
    key                 = "Name"
    value               = "tp5-instance-asg"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "FormationAWS"
    propagate_at_launch = true
  }
  tag {
    key                 = "Env"
    value               = "Dev"
    propagate_at_launch = true
  }
  tag {
    key                 = "Owner"
    value               = "ops-student"
    propagate_at_launch = true
  }
  tag {
    key                 = "CostCenter"
    value               = "IT-Training"
    propagate_at_launch = true
  }
}

/* on peut aussi faire de cette manière, plus lisible et simple : 
dynamic "tag" {
  for_each = {
    Name       = "tp5-instance-asg"
    Project    = "FormationAWS"
    Env        = "Dev"
    Owner      = "ops-student"
    CostCenter = "IT-Training"
  }
  content {
    key                 = tag.key
    value               = tag.value
    propagate_at_launch = true
  }
}
*/