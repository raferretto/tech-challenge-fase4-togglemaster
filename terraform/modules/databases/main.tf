# Subnet Group para os 3 bancos RDS PostgreSQL
resource "aws_db_subnet_group" "rds" {
  name        = "togglemaster-rds-subnet-group"
  description = "Subnet group para bancos de dados PostgreSQL do ToggleMaster"
  subnet_ids  = var.database_subnet_ids

  tags = var.tags
}

# 1. RDS PostgreSQL - Auth Service
resource "aws_db_instance" "auth" {
  identifier             = "togglemaster-db-auth"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "authdb"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [var.database_security_group_id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = merge(
    var.tags,
    {
      Name    = "togglemaster-db-auth"
      Service = "auth-service"
    }
  )
}

# 2. RDS PostgreSQL - Flag Service
resource "aws_db_instance" "flag" {
  identifier             = "togglemaster-db-flag"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "flagdb"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [var.database_security_group_id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = merge(
    var.tags,
    {
      Name    = "togglemaster-db-flag"
      Service = "flag-service"
    }
  )
}

# 3. RDS PostgreSQL - Targeting Service
resource "aws_db_instance" "targeting" {
  identifier             = "togglemaster-db-targeting"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "targetingdb"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [var.database_security_group_id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = merge(
    var.tags,
    {
      Name    = "togglemaster-db-targeting"
      Service = "targeting-service"
    }
  )
}

# Subnet Group para o ElastiCache Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "togglemaster-redis-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = var.tags
}

# 4. Cluster ElastiCache Redis
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "togglemaster-cache"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.database_security_group_id]

  tags = merge(
    var.tags,
    {
      Name    = "togglemaster-cache"
      Service = "evaluation-service"
    }
  )
}

# 5. Tabela DynamoDB para Analytics
resource "aws_dynamodb_table" "analytics" {
  name         = "ToggleMasterAnalytics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = merge(
    var.tags,
    {
      Name    = "ToggleMasterAnalytics"
      Service = "analytics-service"
    }
  )
}
