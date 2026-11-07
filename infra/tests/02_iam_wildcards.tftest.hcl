# Risk 2: the app role and the CI role could do anything in the account ("*").

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "app_role_names_the_actions_it_uses" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for s in data.aws_iam_policy_document.app.statement : [
        for a in coalesce(s.actions, []) : a != "*" && !endswith(a, ":*")
      ] if coalesce(s.effect, "Allow") == "Allow"
    ]))
    error_message = "The app role must name its actions, not \"*\" or \"service:*\"."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.app.statement :
      !contains(coalesce(s.resources, []), "*") || s.actions == toset(["ecr:GetAuthorizationToken"])
      if coalesce(s.effect, "Allow") == "Allow"
    ])
    error_message = "In the app role, only ecr:GetAuthorizationToken (which cannot be scoped) may use Resource \"*\"."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.app.statement : length(coalesce(s.not_actions, [])) == 0])
    error_message = "NotAction in an Allow statement grants every other action."
  }
}

run "ci_role_names_the_actions_it_uses" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for s in data.aws_iam_policy_document.ci.statement : [
        for a in coalesce(s.actions, []) : a != "*" && !endswith(a, ":*")
      ] if coalesce(s.effect, "Allow") == "Allow"
    ]))
    error_message = "The CI role must name its actions, not \"*\" or \"service:*\"."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.ci.statement :
      !contains(coalesce(s.resources, []), "*") || s.actions == toset(["ecr:GetAuthorizationToken"])
      if coalesce(s.effect, "Allow") == "Allow"
    ])
    error_message = "In the CI role, only ecr:GetAuthorizationToken (which cannot be scoped) may use Resource \"*\"."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.ci.statement : length(coalesce(s.not_actions, [])) == 0])
    error_message = "NotAction in an Allow statement grants every other action."
  }
}
