# Risk 1: the bucket with customers' documents was public.
# Runs against the mocked AWS provider in tests/mocks: nothing is created anywhere.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  github_repository = "example-org/ambleroot-app"
}

run "uploads_bucket_blocks_public_access" {
  command = apply

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.uploads.block_public_acls,
      aws_s3_bucket_public_access_block.uploads.block_public_policy,
      aws_s3_bucket_public_access_block.uploads.ignore_public_acls,
      aws_s3_bucket_public_access_block.uploads.restrict_public_buckets,
    ])
    error_message = "All four S3 Block Public Access settings must be on for the uploads bucket."
  }

  assert {
    condition = length([
      for s in data.aws_iam_policy_document.uploads_bucket.statement : s
      if coalesce(s.effect, "Allow") == "Allow" && anytrue([for p in s.principals : contains(p.identifiers, "*")])
    ]) == 0
    error_message = "The bucket policy must not allow everyone (principal \"*\")."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.uploads_bucket.statement :
      s.effect == "Deny" && anytrue([for c in s.condition : c.variable == "aws:SecureTransport" && contains(c.values, "false")])
    ])
    error_message = "The bucket policy must refuse requests that do not use HTTPS."
  }
}
