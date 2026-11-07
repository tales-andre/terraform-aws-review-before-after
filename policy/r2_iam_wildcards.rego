# Risk 2: IAM permissions with wildcard actions, or broader than the role needs.
package r2_iam_wildcards

import data.lib
import rego.v1

risk := "R2 IAM wildcards"

# Actions that AWS does not let you limit to a resource, so Resource "*" is expected.
unscopable_actions := {"ecr:GetAuthorizationToken", "sts:GetCallerIdentity"}

admin_policies := {"AdministratorAccess", "PowerUserAccess", "IAMFullAccess"}

attachment_types := {
	"aws_iam_role_policy_attachment",
	"aws_iam_user_policy_attachment",
	"aws_iam_group_policy_attachment",
	"aws_iam_policy_attachment",
}

deny contains msg if {
	some doc in lib.data_sources("aws_iam_policy_document")
	some statement in lib.statements(doc)
	lib.is_allow(statement)
	some action in object.get(statement, "actions", [])
	wildcard(action)
	msg := lib.msg(risk, doc, sprintf("allows the action %q; list the actions the role uses", [action]))
}

deny contains msg if {
	some doc in lib.data_sources("aws_iam_policy_document")
	some statement in lib.statements(doc)
	lib.is_allow(statement)
	count(object.get(statement, "not_actions", [])) > 0
	msg := lib.msg(risk, doc, "an Allow with not_actions grants every other action")
}

deny contains msg if {
	some doc in lib.data_sources("aws_iam_policy_document")
	some statement in lib.statements(doc)
	lib.is_allow(statement)
	"*" in object.get(statement, "resources", [])
	some action in object.get(statement, "actions", [])
	not action in unscopable_actions
	not wildcard(action)
	msg := lib.msg(risk, doc, sprintf("allows %q on every resource (\"*\"); name the resources", [action]))
}

deny contains msg if {
	some type in attachment_types
	some attachment in lib.resources(type)
	some name in admin_policies
	endswith(attachment.body.policy_arn, sprintf(":policy/%s", [name]))
	msg := lib.msg(risk, attachment, sprintf("attaches %s", [name]))
}

wildcard(action) if action == "*"

wildcard(action) if endswith(action, ":*")
