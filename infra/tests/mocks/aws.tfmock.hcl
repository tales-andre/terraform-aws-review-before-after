# Shared mock values for `terraform test`. The AWS provider is never configured,
# so no account, credentials or network calls are involved.
#
# The provider still validates arguments, so ARNs and JSON policies must look real.

# The rendered JSON is not checked; the tests read the statements instead.
mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_data "aws_ami" {
  defaults = {
    id = "ami-0123456789abcdef0"
  }
}

mock_resource "aws_s3_bucket" {
  defaults = {
    arn = "arn:aws:s3:::ambleroot-uploads"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::123456789012:role/mock-role"
  }
}

mock_resource "aws_iam_openid_connect_provider" {
  defaults = {
    arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
}

mock_resource "aws_ecr_repository" {
  defaults = {
    arn            = "arn:aws:ecr:us-east-1:123456789012:repository/ambleroot-app"
    repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/ambleroot-app"
  }
}

# AWS returns no key pair name for an instance launched without one.
mock_resource "aws_instance" {
  defaults = {
    key_name = ""
  }
}

mock_resource "aws_db_instance" {
  defaults = {
    master_user_secret = [
      {
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-mock-AbCdEf"
        kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
        secret_status = "active"
      },
    ]
  }
}
