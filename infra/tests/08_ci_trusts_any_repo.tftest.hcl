# Risk 8: the CI role trusted GitHub Actions jobs from any repository on GitHub.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "only_this_repository_and_environment_can_assume_the_role" {
  command = apply

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.ci_trust.statement : contains(
        [for c in s.condition : "${c.test} ${c.variable} ${join(",", c.values)}"],
        "StringEquals token.actions.githubusercontent.com:sub repo:example-org/ambleroot-app:environment:production"
      )
    ])
    error_message = "The CI role must trust exactly repo:<owner>/<name>:environment:production, with StringEquals."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.ci_trust.statement : contains(
        [for c in s.condition : "${c.test} ${c.variable} ${join(",", c.values)}"],
        "StringEquals token.actions.githubusercontent.com:aud sts.amazonaws.com"
      )
    ])
    error_message = "The CI role must check the token audience (sts.amazonaws.com)."
  }

  assert {
    condition = alltrue(flatten([
      for s in data.aws_iam_policy_document.ci_trust.statement : [
        for c in s.condition : !strcontains(join(",", c.values), "*") && c.test != "StringLike"
      ]
    ]))
    error_message = "No trust condition may use wildcards."
  }
}

run "a_wildcard_repository_is_refused" {
  command = plan

  variables {
    github_repository = "example-org/*"
  }

  expect_failures = [var.github_repository]
}
