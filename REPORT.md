# Ambleroot: review of the AWS Terraform delivered by the vendor

*Ambleroot is a fictional startup. This report is part of an open-source demo; the flaws were
planted on purpose.*

- **What was reviewed:** the Terraform in `infra/` at the tag
  [`before`](https://github.com/tales-andre/terraform-aws-review-before-after/tree/before), as
  delivered.
- **How:** by reading the code, and with automated checks that run without an AWS account:
  `terraform test` against a mocked AWS provider, Checkov, and conftest policies written for this
  review.
- **What was not reviewed:** the AWS account itself, anything already running in it, and the
  booking app's code. Nothing was planned, applied or run against an AWS account.

## Summary for the owner

The setup works, but as delivered it should not hold customer data. Any one of these is enough
for a serious incident:

- anyone on GitHub can log in to your AWS account as the deploy pipeline, and the pipeline is
  allowed to do anything;
- the database accepts connections from the whole internet, and its password is written in the
  code;
- the documents customers upload can be downloaded by anyone who has a file's address.

Everything below is fixed on the `main` branch, each finding in its own commit. Each fix has a
check that fails on the delivered code and passes on the fixed code, and CI runs both on every
push. A few choices cost money and are yours to make: see [Decisions for you](#decisions-for-you).

## Findings, by what they could do to the business

| Rank | Severity | Finding | Fixed in |
|---|---|---|---|
| 1 | Critical | [Any GitHub repository can use the deploy role](#1-any-github-repository-can-use-the-deploy-role) | Fix 8 |
| 2 | Critical | [The database is open to the internet and not encrypted](#2-the-database-is-open-to-the-internet-and-not-encrypted) | Fix 4 |
| 3 | Critical | [Customers' documents are public](#3-customers-documents-are-public) | Fix 1 |
| 4 | High | [The database password is written in the code](#4-the-database-password-is-written-in-the-code) | Fix 5 |
| 5 | High | [The server and the pipeline may do anything in the account](#5-the-server-and-the-pipeline-may-do-anything-in-the-account) | Fix 2 |
| 6 | High | [Nothing stops the data from being deleted, and there are no backups](#6-nothing-stops-the-data-from-being-deleted-and-there-are-no-backups) | Fix 7 |
| 7 | High | [SSH is open to the internet, and the vendor holds the key](#7-ssh-is-open-to-the-internet-and-the-vendor-holds-the-key) | Fix 3 |
| 8 | Medium | [Terraform's record of what it built lives on one laptop](#8-terraforms-record-of-what-it-built-lives-on-one-laptop) | Fix 6 |
| - | Low | [Smaller items the scanner found](#smaller-items-the-scanner-found) | Lower-risk commit |

The fix numbers follow the order of the commits on `main` (`git log --oneline before..main`).

### 1. Any GitHub repository can use the deploy role

**What we found.** The role GitHub Actions uses to deploy (`ci-role.tf`) checks only that the
login comes from GitHub. It does not check which repository it comes from.

**What could happen.** Anyone with a GitHub account who learns the role's name and your account
number (neither is secret) can run a workflow in their own repository that logs in to your AWS
account as this role. The role may do anything (finding 5), so that is full control of the
account: your data, your servers and your bill.

**What changed.** The role now accepts only jobs from one repository, running in its `production`
GitHub environment (`repo:<owner>/<name>:environment:production`), and the variable that names
the repository refuses wildcards.

**How it is checked.** [`08_ci_trusts_any_repo.tftest.hcl`](infra/tests/08_ci_trusts_any_repo.tftest.hcl)
and [`r8_ci_trust.rego`](policy/r8_ci_trust.rego).

### 2. The database is open to the internet and not encrypted

**What we found.** The database has a public address, sits in the public subnets, and its firewall
accepts PostgreSQL connections from any address. Its storage is not encrypted, and it accepts
connections without TLS.

**What could happen.** Every booking and every customer record is one password away from anyone
on the internet, and that password is in the code (finding 4). Automated scanners look for open
database ports all the time.

**What changed.** The database moved to the private subnets, has no public address, and accepts
connections only from the app server's security group. Storage is encrypted, and a parameter
group refuses connections without TLS.

**How it is checked.** [`04_database_exposed.tftest.hcl`](infra/tests/04_database_exposed.tftest.hcl),
[`r4_database_exposed.rego`](policy/r4_database_exposed.rego), Checkov `CKV_AWS_16` and `CKV_AWS_17`.

**Side effect.** Encryption cannot be turned on in place: see [For your engineer](#for-your-engineer).

### 3. Customers' documents are public

**What we found.** The uploads bucket was opened to the public so the website could show tour
photos. The same bucket holds the documents customers upload when they book.

**What could happen.** Anyone who has a file's address can download it without logging in. Those
addresses leak: in shared links, browser history, or names that are easy to guess. A leak of
customer documents means telling those customers, and possibly a regulator.

**What changed.** All four S3 "Block Public Access" settings are on, the public-read statement is
gone, and the bucket refuses plain HTTP. The app has to hand out short-lived signed links
instead (see [For your engineer](#for-your-engineer)).

**How it is checked.** [`01_public_bucket.tftest.hcl`](infra/tests/01_public_bucket.tftest.hcl),
[`r1_public_bucket.rego`](policy/r1_public_bucket.rego), Checkov `CKV_AWS_53` to `CKV_AWS_56` and
`CKV2_AWS_6`.

### 4. The database password is written in the code

**What we found.** The password is the default value of a Terraform variable. (In this demo it is
an obvious placeholder.)

**What could happen.** Anyone who can read the repository, or any copy of it, has the password, and
it stays in the git history after it is changed. Terraform also writes it in plain text in the
state file (finding 8).

**What changed.** The variable is gone. RDS generates the password and keeps it in AWS Secrets
Manager; the app server's role may read that one secret.

**How it is checked.** [`05_secret_in_code.tftest.hcl`](infra/tests/05_secret_in_code.tftest.hcl)
and [`r5_secrets.rego`](policy/r5_secrets.rego). That no variable keeps a secret default is a
conftest rule, because `terraform test` can only check things that exist, not prove that
something is absent.

### 5. The server and the pipeline may do anything in the account

**What we found.** Both IAM roles allow every action on every resource (`"*"`).

**What could happen.** A bug in the app, or a bad step in the pipeline, becomes control of the
whole account. On the delivered server, a common web bug (one that makes the server fetch a URL
for an attacker) could read the role's credentials, because the server still answered the old,
unauthenticated metadata requests (see the smaller items).

**What changed.** The app role may read and write the uploads bucket, pull the app image, and read
the database password. The pipeline role may push the app image to its one repository. The only
`Resource "*"` left is `ecr:GetAuthorizationToken`, which AWS does not let you limit.

**How it is checked.** [`02_iam_wildcards.tftest.hcl`](infra/tests/02_iam_wildcards.tftest.hcl),
[`r2_iam_wildcards.rego`](policy/r2_iam_wildcards.rego), and the Checkov IAM checks
(`CKV_AWS_1`, `CKV_AWS_49`, `CKV_AWS_356`, `CKV2_AWS_40` and others).

### 6. Nothing stops the data from being deleted, and there are no backups

**What we found.** Deletion protection is off, automated backups are off, deleting the database
skips the final snapshot, and the bucket has `force_destroy` on and no versioning.

**What could happen.** One mistaken `terraform destroy`, a wrong edit, or a compromised pipeline
deletes the database and every uploaded file, with nothing to restore from.

**What changed.** AWS now refuses to delete the database while deletion protection is on. Backups
are kept for 7 days, a final snapshot is taken if the database is ever deleted, and snapshots
carry its tags. The bucket keeps old versions of each file for 30 days.

**How it is checked.** [`07_no_backups.tftest.hcl`](infra/tests/07_no_backups.tftest.hcl),
[`r7_backups.rego`](policy/r7_backups.rego), Checkov `CKV_AWS_293`, `CKV_AWS_133`, `CKV_AWS_21`,
`CKV2_AWS_60` and `CKV2_AWS_61`.

### 7. SSH is open to the internet, and the vendor holds the key

**What we found.** Port 22 on the app server is open to every address, and the server uses a key
pair named after the vendor.

**What could happen.** Anyone can try to log in, and whoever holds the vendor's key can. After the
vendor's work ends, you cannot know who still has a copy.

**What changed.** The SSH rule and the key pair are gone. The team opens a shell through AWS
Systems Manager Session Manager, which needs no open port and logs in with each person's own AWS
access.

**How it is checked.** [`03_ssh_open.tftest.hcl`](infra/tests/03_ssh_open.tftest.hcl),
[`r3_ssh_open.rego`](policy/r3_ssh_open.rego), Checkov `CKV_AWS_24`.

### 8. Terraform's record of what it built lives on one laptop

**What we found.** The state file is local: it lives on whichever machine ran `terraform apply`,
with no lock.

**What could happen.** If that laptop is lost, Terraform no longer knows what it created. Two
people applying at the same time can corrupt the state. The file also held the database password
in plain text.

**What changed.** The state lives in an S3 bucket, encrypted, with a lock file, so two applies
cannot run at once.

**How it is checked.** [`r6_state.rego`](policy/r6_state.rego). `terraform test` ignores the
backend block, so there is no test for this one.

### Smaller items the scanner found

Fixed in one commit: the server now requires the authenticated form of the instance metadata
service (IMDSv2); outbound traffic is limited to HTTPS and to the database port; the VPC's default
security group allows nothing; image tags cannot be overwritten and images are scanned on push;
minor database upgrades are explicit; the server's root volume is encrypted. All but the root
volume are Checkov findings (`CKV_AWS_79`, `CKV_AWS_382`, `CKV2_AWS_12`, `CKV_AWS_51`,
`CKV_AWS_163`, `CKV_AWS_226`, `CKV_AWS_135`).

## Decisions for you

These are not defects. Each costs money or effort, so it is your call.

- **A standby database in a second availability zone (Multi-AZ).** Bookings keep working if one
  AWS zone fails. It costs about twice as much as a single database. Worth it before launch if
  downtime costs you sales.
- **A copy of the files in a second region.** Protects against a regional outage. Adds storage and
  transfer cost.
- **Monitoring and alerts.** Not part of this review. Worth setting up with whoever will run the
  app day to day.
- **Your own encryption keys (KMS).** Data is already encrypted with keys AWS manages. Your own keys
  add a monthly cost and a key policy to maintain; choose them only if a contract or a regulation
  asks for them.
- **Public tour photos.** The bucket is private now. If you want photos to load directly in the
  browser, keep them in a separate bucket or behind a CDN, never next to customer documents.

## For your engineer

**Order of changes on an account that already runs the delivered version.**

1. Create the state bucket once, by hand or from a separate configuration, with versioning on
   and public access blocked. Then `terraform init -migrate-state` moves the local state into it.
   Keep the old local file until the move is confirmed, then delete it: it contains the old
   password.
2. `storage_encrypted` cannot change in place, so the plan replaces the database. Before there is
   data, that is fine. With data: take a snapshot, copy it with encryption, restore the copy with
   the new settings, point the app to it, then remove the old instance.
3. Treat the old database password as leaked: it is in the git history and in the old state.
   Turning on `manage_master_user_password` makes RDS set a new one.
4. Removing the key pair and encrypting the root volume replace the app server, so its public
   address changes. Give it an Elastic IP before the domain points to it.
5. The deploy role accepts only jobs in the GitHub environment `production` of the repository in
   `var.github_repository`. Create that environment with required reviewers, and give the deploy
   job `environment: production` and `permissions: id-token: write`.
6. Image tags are immutable now: tag each image with the commit SHA, not `latest`.
7. The app reads the database password from the secret in the `database_password_secret_arn`
   output, connects with TLS (`sslmode=require` or stricter), and serves files with presigned
   URLs.
8. Shell access: `aws ssm start-session --target <instance-id>`. The SSM agent ships with Amazon
   Linux 2023, and outbound HTTPS is allowed.

**Checks.** `scripts/check.sh` runs everything on `infra/`; `scripts/check.sh before` runs the same
checks on the delivered code. Checkov skips a few checks on purpose; each skip has its reason in
[`.checkov.yaml`](.checkov.yaml). The conftest rules have their own unit tests
(`conftest verify -p policy`).

**Not covered by this review.** The AWS account itself (root user, MFA, CloudTrail, billing alerts),
resources created by hand in the console, the app code, and the HTTPS certificate on the server.
A read-only look at the live account is a separate step.
