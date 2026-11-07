# House rule that keeps the other policies honest: IAM and bucket policies must be
# built with aws_iam_policy_document. A jsonencode(...) policy reaches conftest as
# one opaque string, so a wildcard inside it would slip past R1, R2 and R8.
package checkable

import data.lib
import rego.v1

policy_attributes := {
	"aws_iam_role": "assume_role_policy",
	"aws_iam_role_policy": "policy",
	"aws_iam_policy": "policy",
	"aws_iam_user_policy": "policy",
	"aws_iam_group_policy": "policy",
	"aws_s3_bucket_policy": "policy",
}

deny contains msg if {
	some type, attribute in policy_attributes
	some resource in lib.resources(type)
	value := object.get(resource.body, attribute, null)
	value != null
	not regex.match(`^\$\{data\.aws_iam_policy_document\.[A-Za-z0-9_-]+\.json\}$`, value)
	msg := lib.msg("Checkable policies", resource, sprintf("%s must come from an aws_iam_policy_document data source", [attribute]))
}
