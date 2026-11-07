# Risk 8: a role that GitHub Actions jobs from any repository can assume.
package r8_ci_trust

import data.lib
import rego.v1

risk := "R8 CI role trusts any repository"

github_oidc := "token.actions.githubusercontent.com"

sub_claim := "token.actions.githubusercontent.com:sub"

aud_claim := "token.actions.githubusercontent.com:aud"

deny contains msg if {
	some trust in github_trust_statements
	not exact_sub(trust.statement)
	msg := lib.msg(risk, trust.doc, sprintf("trusts GitHub Actions without a StringEquals condition on %s, so jobs from other repositories can assume it", [sub_claim]))
}

deny contains msg if {
	some trust in github_trust_statements
	some condition in object.get(trust.statement, "condition", [])
	condition.variable == sub_claim
	loose(condition)
	msg := lib.msg(risk, trust.doc, sprintf("%s uses %s with %v; name one repository and environment", [sub_claim, condition.test, condition.values]))
}

deny contains msg if {
	some trust in github_trust_statements
	not audience_checked(trust.statement)
	msg := lib.msg(risk, trust.doc, sprintf("needs a StringEquals condition on %s = sts.amazonaws.com", [aud_claim]))
}

# Statements whose principal is GitHub's OIDC provider, with the document they belong to.
github_trust_statements contains {"doc": doc, "statement": statement} if {
	some doc in lib.data_sources("aws_iam_policy_document")
	some statement in lib.statements(doc)
	lib.is_allow(statement)
	some principal in object.get(statement, "principals", [])
	principal.type == "Federated"
	some identifier in principal.identifiers
	github_provider(identifier)
}

github_provider(identifier) if contains(identifier, sprintf("oidc-provider/%s", [github_oidc]))

github_provider(identifier) if {
	some provider in lib.resources("aws_iam_openid_connect_provider")
	provider.body.url == sprintf("https://%s", [github_oidc])
	lib.refers_to(identifier, provider.address)
}

exact_sub(statement) if {
	some condition in object.get(statement, "condition", [])
	condition.test == "StringEquals"
	condition.variable == sub_claim
	count(condition.values) > 0
	every value in condition.values {
		startswith(value, "repo:")
		not contains(value, "*")
	}
}

loose(condition) if condition.test != "StringEquals"

loose(condition) if {
	some value in condition.values
	contains(value, "*")
}

audience_checked(statement) if {
	some condition in object.get(statement, "condition", [])
	condition.test == "StringEquals"
	condition.variable == aud_claim
	condition.values == ["sts.amazonaws.com"]
}
