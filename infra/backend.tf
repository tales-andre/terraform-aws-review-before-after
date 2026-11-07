# State lives in S3, encrypted, with a lock file so two applies never run at once.
# The state bucket is created once, outside this configuration (see REPORT.md).
terraform {
  backend "s3" {
    bucket       = "ambleroot-terraform-state"
    key          = "booking-app/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
