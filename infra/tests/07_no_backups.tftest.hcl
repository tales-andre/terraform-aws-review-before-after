# Risk 7: one wrong command could delete the database and the uploaded files for good.
# Risk 6 (the state file) has no test here: terraform test does not read the backend
# block. conftest checks it (policy/r6_state.rego).

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "database_survives_a_mistake" {
  command = apply

  assert {
    condition     = aws_db_instance.main.deletion_protection == true
    error_message = "Deletion protection must be on, so AWS refuses to delete the database."
  }

  assert {
    condition     = aws_db_instance.main.backup_retention_period >= 7
    error_message = "Automated backups must be kept for at least 7 days."
  }

  assert {
    condition     = aws_db_instance.main.skip_final_snapshot == false && aws_db_instance.main.final_snapshot_identifier != null
    error_message = "Deleting the database must leave a final snapshot."
  }

  assert {
    condition     = aws_db_instance.main.copy_tags_to_snapshot == true
    error_message = "Snapshots must carry the database tags, so they can be found and kept."
  }

  assert {
    condition     = aws_s3_bucket.uploads.force_destroy != true
    error_message = "force_destroy lets terraform destroy empty the uploads bucket."
  }
}

run "deleted_files_can_be_restored" {
  command = apply

  assert {
    condition = (
      aws_s3_bucket_versioning.uploads.bucket == aws_s3_bucket.uploads.id &&
      aws_s3_bucket_versioning.uploads.versioning_configuration[0].status == "Enabled"
    )
    error_message = "Versioning must be on for the uploads bucket."
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_lifecycle_configuration.uploads.rule :
      r.status == "Enabled" && r.noncurrent_version_expiration[0].noncurrent_days >= 30
    ])
    error_message = "Old versions must be kept for at least 30 days before they expire."
  }
}
