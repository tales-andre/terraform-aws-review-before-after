# Risk 4: a database reachable from the internet, not encrypted at rest or in transit.
package r4_database_exposed

import data.lib
import rego.v1

risk := "R4 database exposed"

database_ports := {5432: "PostgreSQL", 3306: "MySQL", 1433: "SQL Server", 1521: "Oracle", 27017: "MongoDB", 6379: "Redis"}

deny contains msg if {
	some rule in lib.ingress_rules
	some port, name in database_ports
	lib.open_to_internet(rule, port)
	msg := lib.msg(risk, rule.owner, sprintf("lets anyone on the internet reach %s (port %d)", [name, port]))
}

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	object.get(db.body, "publicly_accessible", false) == true
	msg := lib.msg(risk, db, "publicly_accessible must be false")
}

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	object.get(db.body, "storage_encrypted", false) != true
	msg := lib.msg(risk, db, "storage_encrypted must be true")
}

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	startswith(object.get(db.body, "engine", ""), "postgres")
	not forces_tls(db)
	msg := lib.msg(risk, db, "needs a parameter group with rds.force_ssl = 1, so connections use TLS")
}

forces_tls(db) if {
	some group in lib.resources("aws_db_parameter_group")
	lib.refers_to(db.body.parameter_group_name, group.address)
	some parameter in object.get(group.body, "parameter", [])
	parameter.name == "rds.force_ssl"
	sprintf("%v", [parameter.value]) == "1"
}
