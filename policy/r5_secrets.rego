# Risk 5: secrets written in the code. Anything passed to Terraform also ends up in the state file.
package r5_secrets

import data.lib
import rego.v1

risk := "R5 secret in the code"

secret_name := `(?i)(password|passwd|secret|token|api_?key|private_?key)`

deny contains msg if {
	some variable in lib.variables
	regex.match(secret_name, variable.name)
	"default" in object.keys(variable.body)
	msg := lib.msg(risk, variable, "a secret must not have a default value in the code")
}

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	"password" in object.keys(db.body)
	msg := lib.msg(risk, db, "pass no password; set manage_master_user_password = true so RDS keeps it in Secrets Manager")
}

deny contains msg if {
	some file in input
	some type, named in file.contents.resource
	some name, blocks in named
	some body in blocks
	some key, value in body
	regex.match(secret_name, key)
	is_string(value)
	not startswith(value, "${")
	item := {"address": sprintf("%s.%s", [type, name]), "file": file.path}
	msg := lib.msg(risk, item, sprintf("%s is written in the code", [key]))
}
