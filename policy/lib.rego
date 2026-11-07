# Helpers shared by the review policies.
#
# conftest reads the Terraform files with its hcl2 parser and --combine, so `input`
# is a list of {"path": <file>, "contents": <parsed HCL>}. The policies look at the
# code as written: values that come from a reference arrive as strings like
# "${aws_s3_bucket.uploads.id}", and nothing is evaluated.
package lib

import rego.v1

# Every resource of one type, across all files.
resources(type) := [r |
	some file in input
	some name, blocks in file.contents.resource[type]
	some body in blocks
	r := {"address": sprintf("%s.%s", [type, name]), "file": file.path, "body": body}
]

# Every data source of one type, across all files.
data_sources(type) := [d |
	some file in input
	some name, blocks in file.contents.data[type]
	some body in blocks
	d := {"address": sprintf("data.%s.%s", [type, name]), "file": file.path, "body": body}
]

variables := [v |
	some file in input
	some name, blocks in file.contents.variable
	some body in blocks
	v := {"address": sprintf("var.%s", [name]), "name": name, "file": file.path, "body": body}
]

terraform_blocks := [t |
	some file in input
	some body in file.contents.terraform
	t := {"address": "terraform", "file": file.path, "body": body}
]

msg(risk, item, text) := sprintf("[%s] %s (%s): %s", [risk, item.address, item.file, text])

# True when a value such as "${aws_s3_bucket.uploads.id}" points at `address`.
refers_to(value, address) if {
	is_string(value)
	contains(value, sprintf("%s.", [address]))
}

# Statements of an aws_iam_policy_document. A statement with no effect is an Allow.
statements(doc) := object.get(doc.body, "statement", [])

is_allow(statement) if object.get(statement, "effect", "Allow") == "Allow"

# Ingress rules in the three shapes the AWS provider accepts.
ingress_rules contains rule if {
	some sg in resources("aws_security_group")
	some i in object.get(sg.body, "ingress", [])
	rule := {
		"owner": sg,
		"from": object.get(i, "from_port", 0),
		"to": object.get(i, "to_port", 0),
		"protocol": sprintf("%v", [object.get(i, "protocol", "-1")]),
		"cidrs": array.concat(object.get(i, "cidr_blocks", []), object.get(i, "ipv6_cidr_blocks", [])),
	}
}

ingress_rules contains rule if {
	some r in resources("aws_security_group_rule")
	r.body.type == "ingress"
	rule := {
		"owner": r,
		"from": object.get(r.body, "from_port", 0),
		"to": object.get(r.body, "to_port", 0),
		"protocol": sprintf("%v", [object.get(r.body, "protocol", "-1")]),
		"cidrs": array.concat(object.get(r.body, "cidr_blocks", []), object.get(r.body, "ipv6_cidr_blocks", [])),
	}
}

ingress_rules contains rule if {
	some r in resources("aws_vpc_security_group_ingress_rule")
	rule := {
		"owner": r,
		"from": object.get(r.body, "from_port", 0),
		"to": object.get(r.body, "to_port", 65535),
		"protocol": sprintf("%v", [object.get(r.body, "ip_protocol", "-1")]),
		"cidrs": [c | some k in ["cidr_ipv4", "cidr_ipv6"]; c := r.body[k]],
	}
}

internet_cidrs := {"0.0.0.0/0", "::/0"}

# The rule lets anyone on the internet reach `port`.
open_to_internet(rule, port) if {
	some cidr in rule.cidrs
	cidr in internet_cidrs
	covers(rule, port)
}

covers(rule, _) if rule.protocol in {"-1", "all"}

covers(rule, port) if {
	rule.from <= port
	port <= rule.to
}
