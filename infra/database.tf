variable "db_password" {
  description = "Master password for the database."
  type        = string
  default     = "CHANGE-ME-NOT-A-REAL-PASSWORD"
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_db_instance" "main" {
  identifier             = "${var.name}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  db_name                = "ambleroot"
  username               = "ambleroot_admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = true
  storage_encrypted      = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
}
