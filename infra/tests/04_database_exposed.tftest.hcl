# Risk 4: the database was reachable from the internet and not encrypted.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "database_is_private_and_encrypted" {
  command = apply

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "The database must not get a public address."
  }

  assert {
    condition     = aws_db_instance.main.storage_encrypted == true
    error_message = "The database storage, its backups and its snapshots must be encrypted."
  }

  assert {
    condition     = toset(aws_db_subnet_group.main.subnet_ids) == toset(aws_subnet.private[*].id)
    error_message = "The database must sit in the private subnets, which have no route to the internet."
  }

  assert {
    condition = alltrue([
      for r in aws_security_group.db.ingress :
      length(coalesce(r.cidr_blocks, [])) == 0 && length(coalesce(r.ipv6_cidr_blocks, [])) == 0
    ])
    error_message = "No address range may reach the database port, only the app server's security group."
  }

  assert {
    condition     = alltrue([for r in aws_security_group.db.ingress : coalesce(r.security_groups, toset([])) == toset([aws_security_group.app.id])])
    error_message = "Only the app server's security group may connect to the database."
  }
}

run "database_refuses_connections_without_tls" {
  command = apply

  assert {
    condition = (
      aws_db_instance.main.parameter_group_name == aws_db_parameter_group.main.name &&
      anytrue([for p in aws_db_parameter_group.main.parameter : p.name == "rds.force_ssl" && p.value == "1"])
    )
    error_message = "The database must use a parameter group with rds.force_ssl = 1."
  }
}
