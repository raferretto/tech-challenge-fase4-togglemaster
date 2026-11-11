# Backend Remoto S3 para armazenamento do terraform.tfstate
# Conforme requisito do Tech Challenge: "O terraform.tfstate não pode ficar local.
# Configure o Backend Remoto usando um Bucket S3 (e opcionalmente a flag use_lockfile para Lock)"

terraform {
  backend "s3" {
    bucket       = "togglemaster-state-889629667863"
    key          = "fase3/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
