# Risk 5: the database password was a default value in the code, and so also in the state file.
# That no variable keeps a secret default is checked by conftest (policy/r5_secrets.rego):
# terraform test can only look at things that exist, not prove something is absent.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "rds_generates_and_keeps_the_password" {
  command = apply

  assert {
    condition     = aws_db_instance.main.manage_master_user_password == true
    error_message = "RDS must generate the password and keep it in Secrets Manager (manage_master_user_password)."
  }

  assert {
    condition     = aws_db_instance.main.password == null
    error_message = "No password may be passed to the database from the code."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.app.statement :
      contains(coalesce(s.actions, []), "secretsmanager:GetSecretValue") &&
      contains(coalesce(s.resources, []), aws_db_instance.main.master_user_secret[0].secret_arn)
    ])
    error_message = "The app must read the password from that one secret."
  }
}
