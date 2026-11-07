# terraform-aws-review-before-after

[![CI](https://github.com/tales-andre/terraform-aws-review-before-after/actions/workflows/ci.yml/badge.svg)](https://github.com/tales-andre/terraform-aws-review-before-after/actions/workflows/ci.yml)

**A common request on freelance job boards:** *we inherited the AWS Terraform from the vendor who
built our app. Before we have real customers, can someone tell us what could go wrong, fix it, and
show that it is fixed?*

This repo shows how I answer that, on an **open-source demo** with a **fictional company**:
Ambleroot, a startup that sells guided city tours. Its booking app runs on one EC2 server, with a
PostgreSQL database on RDS, an S3 bucket for uploads, and a role that GitHub Actions uses to push
the app image to ECR. The delivered version was written **on purpose** with risks often found in
Terraform handed over by a vendor. It is not a client's code, and none of it was ever applied to
an AWS account.

- **Before:** tag [`before`](https://github.com/tales-andre/terraform-aws-review-before-after/tree/before),
  the code as delivered. **Never apply it.**
- **After:** branch `main`. Each risk is fixed in its own commit, with a check that fails on the tag
  and passes on `main`.
- **Report for the owner:** [`REPORT.md`](REPORT.md), ranked by what each risk could do to the
  business, with a section for your engineer.

## The findings

| Risk | What could happen to the business | Fix | Checks that prove the fix |
|---|---|---|---|
| Public S3 bucket | Anyone with a file's address downloads the documents customers uploaded | [Fix 1](https://github.com/tales-andre/terraform-aws-review-before-after/commit/1bdaebd) | [test](infra/tests/01_public_bucket.tftest.hcl), [policy](policy/r1_public_bucket.rego), Checkov `CKV_AWS_53` to `56`, `CKV2_AWS_6` |
| Wildcard IAM permissions | A bug in the app or in the pipeline becomes control of the whole AWS account | [Fix 2](https://github.com/tales-andre/terraform-aws-review-before-after/commit/4a0f220) | [test](infra/tests/02_iam_wildcards.tftest.hcl), [policy](policy/r2_iam_wildcards.rego), Checkov `CKV_AWS_1`, `CKV_AWS_49`, `CKV_AWS_356`, `CKV2_AWS_40` |
| SSH open to the internet | Anyone can try to log in, and the vendor still holds a key | [Fix 3](https://github.com/tales-andre/terraform-aws-review-before-after/commit/be28ca5) | [test](infra/tests/03_ssh_open.tftest.hcl), [policy](policy/r3_ssh_open.rego), Checkov `CKV_AWS_24` |
| Database public and unencrypted | Customer data is one password away from anyone on the internet | [Fix 4](https://github.com/tales-andre/terraform-aws-review-before-after/commit/b209a2b) | [test](infra/tests/04_database_exposed.tftest.hcl), [policy](policy/r4_database_exposed.rego), Checkov `CKV_AWS_16`, `CKV_AWS_17` |
| Password as a variable default | Anyone who can read the repository can log in to the database | [Fix 5](https://github.com/tales-andre/terraform-aws-review-before-after/commit/da6ad2b) | [test](infra/tests/05_secret_in_code.tftest.hcl), [policy](policy/r5_secrets.rego) |
| Local state without a lock | Lose one laptop and Terraform no longer knows what it built; two applies at once corrupt it | [Fix 6](https://github.com/tales-andre/terraform-aws-review-before-after/commit/dd7f6f1) | [policy](policy/r6_state.rego) |
| No deletion protection or backups | One wrong command deletes the database and every uploaded file for good | [Fix 7](https://github.com/tales-andre/terraform-aws-review-before-after/commit/414956f) | [test](infra/tests/07_no_backups.tftest.hcl), [policy](policy/r7_backups.rego), Checkov `CKV_AWS_293`, `CKV_AWS_133`, `CKV_AWS_21` |
| CI role trusts any GitHub repository | Anyone on GitHub can log in to the account as the deploy pipeline | [Fix 8](https://github.com/tales-andre/terraform-aws-review-before-after/commit/4f378e8) | [test](infra/tests/08_ci_trusts_any_repo.tftest.hcl), [policy](policy/r8_ci_trust.rego) |

Also fixed, in [one commit](https://github.com/tales-andre/terraform-aws-review-before-after/commit/0cfbfe5):
smaller items Checkov found, such as the old instance metadata service (IMDSv1), unrestricted
outbound traffic, and image tags that can be overwritten.

```text
$ git log --oneline --reverse before..main
906529f Add review checks (terraform test, conftest, Checkov); all fail on the delivered code
1bdaebd Fix 1: make the uploads bucket private and refuse plain HTTP
4a0f220 Fix 2: give the app and CI roles only the actions they use
be28ca5 Fix 3: close SSH to the internet and drop the key pair; use Session Manager
b209a2b Fix 4: move the database to private subnets, encrypt it and require TLS
da6ad2b Fix 5: let RDS generate the database password and keep it in Secrets Manager
dd7f6f1 Fix 6: keep Terraform state in S3, encrypted and locked
414956f Fix 7: turn on deletion protection, database backups and file versioning
4f378e8 Fix 8: let only this repository's production environment assume the CI role
0cfbfe5 Lower-risk items Checkov found: IMDSv2, image tags and scanning, default security group, narrower egress
...
```

The checks were written first, against the delivered code, and each fix commit turns its own
checks green. There are three kinds, because each sees something the others cannot:

- **`terraform test`** ([`infra/tests/`](infra/tests)) runs the code against a mocked AWS provider
  ([`infra/tests/mocks/`](infra/tests/mocks/aws.tfmock.hcl)): nothing is created anywhere and no
  credentials are read. It checks the values the code would send to AWS, for example that the
  trust policy names exactly one repository and environment.
- **conftest** ([`policy/`](policy)) runs policies written for this review on the `.tf` files. It
  covers what `terraform test` cannot: proving that something is absent (no SSH rule, no password
  variable) and reading the backend block. The policies have their own unit tests
  ([`policy/policy_test.rego`](policy/policy_test.rego)).
- **Checkov**, a widely used open-source scanner, with the checks it skips and the reason for each
  in [`.checkov.yaml`](.checkov.yaml).

## Run it yourself

You need git, bash, Python 3, Terraform 1.10 or newer, and Docker (or `checkov` 3.4.3 and
`conftest` 0.71.1 on your PATH). No AWS account and no credentials: `terraform init` downloads the
AWS provider from the public registry, and nothing calls AWS.

```bash
git clone https://github.com/tales-andre/terraform-aws-review-before-after
cd terraform-aws-review-before-after

scripts/check.sh                                       # reviewed code: every check passes
scripts/check.sh before                                # delivered code: test, checkov and conftest fail
python3 scripts/findings.py out/before --expect fail   # which check caught which risk
```

The same checks one at a time, from the repository root, with `checkov` and `conftest` installed:

```bash
terraform -chdir=infra init -backend=false   # the S3 backend would need a real bucket
terraform -chdir=infra test
checkov --config-file .checkov.yaml -d infra
conftest test --parser hcl2 --combine --all-namespaces -p policy infra/*.tf
conftest verify -p policy
```

To read the flawed code, `git checkout before`: it is the code as delivered, without the checks.
`scripts/check.sh before` copies `infra/` from that tag into `.before/` and runs this branch's
checks on it, which is what CI does.

## What CI checks

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) has two jobs, on every push to `main` and
every pull request:

- **Reviewed code (main) passes:** lints the workflow and the script, then runs
  `scripts/check.sh`. Every check must pass.
- **Flawed code (tag before) fails:** runs the same checks on the `before` tag. That step must fail
  (it runs with `continue-on-error`, and the next step requires `outcome == failure`). Then
  `scripts/findings.py` confirms that each risk was caught by each check listed for it, so a run
  that fails for another reason, such as a missing tag or a tool that did not start, turns the job
  red.

Both jobs keep their logs as artifacts and write the table to the job summary. The table for the
delivered code:

| Risk | Finding | terraform test | conftest | Checkov |
|---|---|---|---|---|
| R1 | Public S3 bucket | caught | caught | caught |
| R2 | Wildcard IAM permissions | caught | caught | caught |
| R3 | SSH open to the internet | caught | caught | caught |
| R4 | Database public and unencrypted | caught | caught | caught |
| R5 | Password as a variable default | caught | caught | - |
| R6 | Local state without a lock | - | caught | - |
| R7 | No deletion protection or backups | caught | caught | caught |
| R8 | CI role trusts any repository | caught | caught | - |
| L | Lower-risk items Checkov found | - | - | caught |

A dash means that tool has no check for that risk.

## The report

[`REPORT.md`](REPORT.md) is written for the owner, not for engineers: each risk ranked by what it
could do to the business, what changed, and how it is checked. It ends with the choices that cost
money ("Decisions for you") and a section for your engineer on applying the fixes, in the right
order, to an account that already runs the old version.

To check a live AWS account read-only, Terraform drift included, see
[aws-delivery-gap-assessment](https://github.com/tales-andre/aws-delivery-gap-assessment).

## Limits

- **Never applied.** No `terraform plan` or `apply` ran against an AWS account, for either version.
  The review is of the code, not of an account: it says nothing about resources created by hand,
  the account's root user or CloudTrail, or anything already running.
- `terraform test` runs against a mocked provider. It checks the values in the code, not how AWS
  would respond to them. The mock does not render IAM policy JSON, so the tests read the policy
  statements as written.
- conftest and Checkov read the files without running Terraform. A value that comes from a
  variable or a function reaches them as text.
- Checkov skips the checks listed in [`.checkov.yaml`](.checkov.yaml), each with its reason
  (for example monitoring, which is outside this review, and choices that cost money).
- Ambleroot and its vendor are fictional. The flaws were planted on purpose for this demo.

## License

MIT. See [LICENSE](LICENSE).
