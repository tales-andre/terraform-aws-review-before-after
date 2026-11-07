# Risk 6: Terraform state on one laptop, unencrypted and without a lock.
package r6_state

import data.lib
import rego.v1

risk := "R6 local state without a lock"

backends contains backend if {
	some block in lib.terraform_blocks
	some type, configs in object.get(block.body, "backend", {})
	some config in configs
	backend := {"address": sprintf("backend %q", [type]), "file": block.file, "type": type, "config": config}
}

uses_hcp_terraform if {
	some block in lib.terraform_blocks
	"cloud" in object.keys(block.body)
}

deny contains msg if {
	count(backends) == 0
	not uses_hcp_terraform
	msg := sprintf("[%s] terraform: no backend block, so the state stays on whichever machine runs apply", [risk])
}

deny contains msg if {
	some backend in backends
	backend.type == "local"
	msg := lib.msg(risk, backend, "state stays on one machine, with no shared copy and no lock")
}

deny contains msg if {
	some backend in backends
	backend.type == "s3"
	object.get(backend.config, "encrypt", false) != true
	msg := lib.msg(risk, backend, "encrypt must be true")
}

deny contains msg if {
	some backend in backends
	backend.type == "s3"
	not locked(backend.config)
	msg := lib.msg(risk, backend, "needs use_lockfile = true, so two applies cannot run at once")
}

locked(config) if config.use_lockfile == true

locked(config) if object.get(config, "dynamodb_table", "") != ""
