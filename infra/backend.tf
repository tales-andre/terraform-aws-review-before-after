# State lives in terraform.tfstate on the laptop that runs `terraform apply`.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
