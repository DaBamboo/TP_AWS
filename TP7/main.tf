# ── Lecture du state de base/ ─────────────────────────────────────────
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}

# ── DB Subnet Group ───────────────────────────────────────────────────
resource "aws_db_subnet_group" "rds" {
  name = "tp7-db-subnet-group"
  subnet_ids = [
    data.terraform_remote_state.base.outputs.subnet_private_a_id,
    data.terraform_remote_state.base.outputs.subnet_private_b_id,
  ]

  tags = { Name = "tp7-db-subnet-group" }
}

# ── Security Group RDS ────────────────────────────────────────────────
resource "aws_security_group" "sg_rds" {
  name        = "tp7-sg-rds"
  description = "Autorise uniquement le SG app sur port 5432"
  vpc_id      = data.terraform_remote_state.base.outputs.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tp7-sg-rds" }
}

resource "aws_security_group_rule" "rds_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_rds.id
  source_security_group_id = data.terraform_remote_state.base.outputs.sg_app_id
  description              = "PostgreSQL depuis SG app uniquement"
}

# ── Instance RDS PostgreSQL ───────────────────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier        = "tp7-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "tp7db"
  username = "admintp7"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.sg_rds.id]

  publicly_accessible     = false
  storage_encrypted       = true
  deletion_protection     = false

  backup_retention_period = 1
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:03:00-Mon:04:00"

  multi_az            = false
  skip_final_snapshot = true

  tags = { Name = "tp7-postgres" }
}

# ── Snapshot manuel ───────────────────────────────────────────────────
resource "aws_db_snapshot" "tp7_snap" {
  db_instance_identifier = aws_db_instance.postgres.identifier
  db_snapshot_identifier = "tp7-snapshot-manuel"

  depends_on = [aws_db_instance.postgres]

  tags = { Name = "tp7-snapshot-manuel" }
}