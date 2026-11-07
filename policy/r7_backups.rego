# Risk 7: no deletion protection and no backups.
package r7_backups

import data.lib
import rego.v1

risk := "R7 no deletion protection or backups"

minimum_backup_days := 7

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	object.get(db.body, "deletion_protection", false) != true
	msg := lib.msg(risk, db, "deletion_protection must be true")
}

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	days := object.get(db.body, "backup_retention_period", 0)
	not days >= minimum_backup_days
	msg := lib.msg(risk, db, sprintf("backup_retention_period must be at least %d days", [minimum_backup_days]))
}

deny contains msg if {
	some db in lib.resources("aws_db_instance")
	object.get(db.body, "skip_final_snapshot", false) == true
	msg := lib.msg(risk, db, "skip_final_snapshot must be false, so a deleted database leaves a snapshot")
}

deny contains msg if {
	some bucket in lib.resources("aws_s3_bucket")
	object.get(bucket.body, "force_destroy", false) == true
	msg := lib.msg(risk, bucket, "force_destroy lets terraform destroy delete every object")
}

deny contains msg if {
	some bucket in lib.resources("aws_s3_bucket")
	not versioned(bucket.address)
	msg := lib.msg(risk, bucket, "needs aws_s3_bucket_versioning with status Enabled")
}

versioned(address) if {
	some versioning in lib.resources("aws_s3_bucket_versioning")
	lib.refers_to(versioning.body.bucket, address)
	some config in versioning.body.versioning_configuration
	config.status == "Enabled"
}
