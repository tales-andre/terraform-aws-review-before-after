# Unit tests for the policies: `conftest verify -p policy`.
# They cover shapes the demo code does not use, so a policy cannot pass by accident.
package policy_test

import data.checkable
import data.r1_public_bucket
import data.r2_iam_wildcards
import data.r3_ssh_open
import data.r4_database_exposed
import data.r5_secrets
import data.r6_state
import data.r7_backups
import data.r8_ci_trust
import rego.v1

tf(contents) := [{"path": "test.tf", "contents": contents}]

doc(statements) := tf({"data": {"aws_iam_policy_document": {"p": [{"statement": statements}]}}})

sg_ingress(rule) := tf({"resource": {"aws_security_group": {"sg": [{"ingress": [rule]}]}}})

# R1

test_r1_bucket_without_public_access_block if {
	count(r1_public_bucket.deny) == 1 with input as tf({"resource": {"aws_s3_bucket": {"b": [{"bucket": "x"}]}}})
}

test_r1_deny_statement_for_everyone_is_fine if {
	count(r1_public_bucket.deny) == 0 with input as doc([{
		"effect": "Deny",
		"actions": ["s3:*"],
		"principals": [{"type": "*", "identifiers": ["*"]}],
	}])
}

test_r1_statement_without_effect_is_an_allow if {
	count(r1_public_bucket.deny) == 1 with input as doc([{
		"actions": ["s3:GetObject"],
		"principals": [{"type": "AWS", "identifiers": ["*"]}],
	}])
}

# R2

test_r2_service_wildcard if {
	count(r2_iam_wildcards.deny) == 1 with input as doc([{"actions": ["s3:*"], "resources": ["arn:aws:s3:::b/*"]}])
}

test_r2_scoped_action_on_every_resource if {
	count(r2_iam_wildcards.deny) == 1 with input as doc([{"actions": ["s3:GetObject"], "resources": ["*"]}])
}

test_r2_unscopable_action_on_every_resource_is_fine if {
	count(r2_iam_wildcards.deny) == 0 with input as doc([{"actions": ["ecr:GetAuthorizationToken"], "resources": ["*"]}])
}

test_r2_allow_with_not_actions if {
	count(r2_iam_wildcards.deny) == 1 with input as doc([{"not_actions": ["iam:*"], "resources": ["arn:aws:s3:::b"]}])
}

test_r2_administrator_access_attachment if {
	count(r2_iam_wildcards.deny) == 1 with input as tf({"resource": {"aws_iam_role_policy_attachment": {"a": [{
		"role": "${aws_iam_role.ci.name}",
		"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess",
	}]}}})
}

# R3

test_r3_port_range_that_covers_ssh if {
	count(r3_ssh_open.deny) == 1 with input as sg_ingress({"from_port": 0, "to_port": 1024, "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"]})
}

test_r3_all_protocols_from_ipv6_internet if {
	count(r3_ssh_open.deny) == 2 with input as sg_ingress({"from_port": 0, "to_port": 0, "protocol": "-1", "ipv6_cidr_blocks": ["::/0"]})
}

test_r3_standalone_ingress_rule if {
	count(r3_ssh_open.deny) == 1 with input as tf({"resource": {"aws_vpc_security_group_ingress_rule": {"ssh": [{
		"from_port": 22,
		"to_port": 22,
		"ip_protocol": "tcp",
		"cidr_ipv4": "0.0.0.0/0",
	}]}}})
}

test_r3_ssh_from_office_range_is_fine if {
	count(r3_ssh_open.deny) == 0 with input as sg_ingress({"from_port": 22, "to_port": 22, "protocol": "tcp", "cidr_blocks": ["203.0.113.0/24"]})
}

# R4

test_r4_mysql_from_internet if {
	count(r4_database_exposed.deny) == 1 with input as sg_ingress({"from_port": 3306, "to_port": 3306, "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"]})
}

test_r4_encryption_missing_counts_as_off if {
	count(r4_database_exposed.deny) == 1 with input as tf({"resource": {"aws_db_instance": {"db": [{"engine": "mysql"}]}}})
}

# R5

test_r5_token_variable_with_default if {
	count(r5_secrets.deny) == 1 with input as tf({"variable": {"api_token": [{"default": "abc"}]}})
}

test_r5_plain_variable_with_default_is_fine if {
	count(r5_secrets.deny) == 0 with input as tf({"variable": {"region": [{"default": "us-east-1"}]}})
}

test_r5_literal_secret_in_a_resource if {
	count(r5_secrets.deny) == 1 with input as tf({"resource": {"aws_mq_broker": {"b": [{"admin_password": "hunter2"}]}}})
}

# R6

test_r6_no_backend if {
	count(r6_state.deny) == 1 with input as tf({"terraform": [{"required_version": ">= 1.10.0"}]})
}

test_r6_s3_without_lock if {
	count(r6_state.deny) == 1 with input as tf({"terraform": [{"backend": {"s3": [{"bucket": "s", "key": "k", "encrypt": true}]}}]})
}

test_r6_s3_with_dynamodb_lock_is_fine if {
	count(r6_state.deny) == 0 with input as tf({"terraform": [{"backend": {"s3": [{"encrypt": true, "dynamodb_table": "locks"}]}}]})
}

test_r6_hcp_terraform_is_fine if {
	count(r6_state.deny) == 0 with input as tf({"terraform": [{"cloud": [{"organization": "example"}]}]})
}

# R7

test_r7_suspended_versioning if {
	count(r7_backups.deny) == 1 with input as tf({"resource": {
		"aws_s3_bucket": {"b": [{"bucket": "x"}]},
		"aws_s3_bucket_versioning": {"b": [{
			"bucket": "${aws_s3_bucket.b.id}",
			"versioning_configuration": [{"status": "Suspended"}],
		}]},
	}})
}

# R8

github_trust(conditions) := tf({
	"resource": {"aws_iam_openid_connect_provider": {"gh": [{"url": "https://token.actions.githubusercontent.com"}]}},
	"data": {"aws_iam_policy_document": {"trust": [{"statement": [{
		"actions": ["sts:AssumeRoleWithWebIdentity"],
		"principals": [{"type": "Federated", "identifiers": ["${aws_iam_openid_connect_provider.gh.arn}"]}],
		"condition": conditions,
	}]}]}},
})

aud := {"test": "StringEquals", "variable": "token.actions.githubusercontent.com:aud", "values": ["sts.amazonaws.com"]}

test_r8_string_like_on_the_whole_organization if {
	count(r8_ci_trust.deny) == 2 with input as github_trust([
		aud,
		{"test": "StringLike", "variable": "token.actions.githubusercontent.com:sub", "values": ["repo:example-org/*"]},
	])
}

test_r8_one_repository_and_environment_is_fine if {
	count(r8_ci_trust.deny) == 0 with input as github_trust([
		aud,
		{"test": "StringEquals", "variable": "token.actions.githubusercontent.com:sub", "values": ["repo:example-org/app:environment:production"]},
	])
}

test_r8_audience_missing if {
	count(r8_ci_trust.deny) == 1 with input as github_trust([
		{"test": "StringEquals", "variable": "token.actions.githubusercontent.com:sub", "values": ["repo:example-org/app:environment:production"]},
	])
}

test_r8_literal_provider_arn_is_recognised if {
	count(r8_ci_trust.deny) == 1 with input as doc([{
		"actions": ["sts:AssumeRoleWithWebIdentity"],
		"principals": [{"type": "Federated", "identifiers": ["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"]}],
		"condition": [aud],
	}])
}

# Checkable policies

test_jsonencode_policy_is_refused if {
	count(checkable.deny) == 1 with input as tf({"resource": {"aws_iam_role_policy": {"p": [{
		"policy": "${jsonencode({Statement = []})}",
	}]}}})
}

test_policy_document_is_accepted if {
	count(checkable.deny) == 0 with input as tf({"resource": {"aws_iam_role_policy": {"p": [{
		"policy": "${data.aws_iam_policy_document.app.json}",
	}]}}})
}
