# Risk 1: an S3 bucket that anyone on the internet can read.
package r1_public_bucket

import data.lib
import rego.v1

risk := "R1 public bucket"

settings := ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

deny contains msg if {
	some bucket in lib.resources("aws_s3_bucket")
	not has_public_access_block(bucket.address)
	msg := lib.msg(risk, bucket, "has no aws_s3_bucket_public_access_block")
}

deny contains msg if {
	some block in lib.resources("aws_s3_bucket_public_access_block")
	some setting in settings
	object.get(block.body, setting, false) != true
	msg := lib.msg(risk, block, sprintf("%s must be true", [setting]))
}

deny contains msg if {
	some doc in lib.data_sources("aws_iam_policy_document")
	some statement in lib.statements(doc)
	lib.is_allow(statement)
	some principal in object.get(statement, "principals", [])
	"*" in principal.identifiers
	msg := lib.msg(risk, doc, sprintf("statement %q allows everyone (principal \"*\")", [object.get(statement, "sid", "")]))
}

deny contains msg if {
	some acl in lib.resources("aws_s3_bucket_acl")
	acl.body.acl in {"public-read", "public-read-write", "authenticated-read"}
	msg := lib.msg(risk, acl, sprintf("ACL %q makes objects public", [acl.body.acl]))
}

has_public_access_block(address) if {
	some block in lib.resources("aws_s3_bucket_public_access_block")
	lib.refers_to(block.body.bucket, address)
}
