# Risk 3: remote administration ports open to the internet, and SSH key pairs.
package r3_ssh_open

import data.lib
import rego.v1

risk := "R3 SSH open to the internet"

admin_ports := {22: "SSH", 3389: "RDP"}

deny contains msg if {
	some rule in lib.ingress_rules
	some port, name in admin_ports
	lib.open_to_internet(rule, port)
	msg := lib.msg(risk, rule.owner, sprintf("lets anyone on the internet reach %s (port %d)", [name, port]))
}

deny contains msg if {
	some instance in lib.resources("aws_instance")
	object.get(instance.body, "key_name", "") != ""
	msg := lib.msg(risk, instance, sprintf("uses the SSH key pair %q; open a shell with Session Manager instead", [instance.body.key_name]))
}
