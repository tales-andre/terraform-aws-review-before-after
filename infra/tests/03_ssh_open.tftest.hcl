# Risk 3: SSH was open to the whole internet, with a key pair the vendor holds.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "only_https_is_open_to_the_internet" {
  command = apply

  assert {
    condition = alltrue([
      for r in aws_security_group.app.ingress :
      r.protocol == "tcp" && r.from_port == 443 && r.to_port == 443
      if contains(coalesce(r.cidr_blocks, []), "0.0.0.0/0") || contains(coalesce(r.ipv6_cidr_blocks, []), "::/0")
    ])
    error_message = "Only HTTPS (443) may be open to the internet on the app server."
  }

  assert {
    condition     = aws_instance.app.key_name == ""
    error_message = "The app server must not use an SSH key pair; the team opens a shell with Session Manager."
  }
}

run "session_manager_replaces_ssh" {
  command = apply

  assert {
    condition = (
      aws_iam_role_policy_attachment.app_ssm.role == aws_iam_role.app.name &&
      aws_iam_role_policy_attachment.app_ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    )
    error_message = "The app role needs AmazonSSMManagedInstanceCore so the team can open a shell without SSH."
  }
}
