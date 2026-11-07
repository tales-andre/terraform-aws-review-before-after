#!/usr/bin/env python3
"""Turns the logs of scripts/check.sh into a findings table.

    python3 scripts/findings.py out/before --expect fail
    python3 scripts/findings.py out/main --expect pass

With --expect fail, every planted risk must be caught by each check listed for it.
A suite that fails for some other reason (a missing tag, a tool that did not run)
does not count. With --expect pass, nothing may fail. In GitHub Actions the table
is also written to the job summary.
"""

import argparse
import os
import re
import sys
from pathlib import Path

# risk id, finding, terraform test file, conftest namespace, Checkov checks
RISKS = [
    ("R1", "Public S3 bucket", "01_public_bucket", "r1_public_bucket",
     ["CKV_AWS_53", "CKV_AWS_54", "CKV_AWS_55", "CKV_AWS_56", "CKV2_AWS_6"]),
    ("R2", "Wildcard IAM permissions", "02_iam_wildcards", "r2_iam_wildcards",
     ["CKV_AWS_1", "CKV_AWS_49", "CKV_AWS_356", "CKV2_AWS_40"]),
    ("R3", "SSH open to the internet", "03_ssh_open", "r3_ssh_open",
     ["CKV_AWS_24"]),
    ("R4", "Database public and unencrypted", "04_database_exposed", "r4_database_exposed",
     ["CKV_AWS_16", "CKV_AWS_17"]),
    ("R5", "Password as a variable default", "05_secret_in_code", "r5_secrets", []),
    ("R6", "Local state without a lock", None, "r6_state", []),
    ("R7", "No deletion protection or backups", "07_no_backups", "r7_backups",
     ["CKV_AWS_293", "CKV_AWS_133", "CKV_AWS_21", "CKV2_AWS_60", "CKV2_AWS_61"]),
    ("R8", "CI role trusts any repository", "08_ci_trusts_any_repo", "r8_ci_trust", []),
    ("L", "Lower-risk items Checkov found", None, None,
     ["CKV_AWS_79", "CKV_AWS_135", "CKV_AWS_51", "CKV_AWS_163", "CKV_AWS_226", "CKV2_AWS_12", "CKV_AWS_382"]),
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def terraform_test_results(log: str) -> dict:
    # "tests/01_public_bucket.tftest.hcl... fail" (backslashes on Windows)
    return {m[1]: m[2] for m in re.finditer(r"tests[\\/](\S+?)\.tftest\.hcl\.\.\. (pass|fail)", log)}


def conftest_failures(log: str) -> set:
    # "FAIL - Combined - r1_public_bucket - [R1 public bucket] ..."
    return set(re.findall(r"^FAIL - \S+ - (\S+) - ", log, re.MULTILINE))


def checkov_results(log: str) -> dict:
    # "Check: CKV_AWS_53: ..." followed by "FAILED for resource: ..." or "PASSED ..."
    results = {}
    for m in re.finditer(r"Check: (CKV2?_AWS_\d+):.*?\n\s*(PASSED|FAILED|SKIPPED)", log):
        if results.get(m[1]) != "FAILED":
            results[m[1]] = m[2]
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("logs", type=Path)
    parser.add_argument("--expect", choices=["pass", "fail"], required=True)
    args = parser.parse_args()

    test_log = read(args.logs / "test.log")
    checkov_log = read(args.logs / "checkov.log")
    conftest_log = read(args.logs / "conftest.log")
    tests = terraform_test_results(test_log)
    policies = conftest_failures(conftest_log)
    checkov = checkov_results(checkov_log)

    problems = []
    if not tests:
        problems.append("terraform test did not run (no results in test.log)")
    if "tests," not in conftest_log:
        problems.append("conftest did not run (no summary in conftest.log)")
    if "Passed checks" not in checkov_log:
        problems.append("Checkov did not run (no summary in checkov.log)")

    caught = "caught" if args.expect == "fail" else "fails"
    clean = "missed" if args.expect == "fail" else "passes"

    def verdict(failed: bool) -> str:
        return caught if failed else clean

    rows = []
    for risk, finding, test_file, namespace, checkov_ids in RISKS:
        cells = []
        if test_file:
            failed = tests.get(test_file) == "fail"
            cells.append(verdict(failed))
            if (args.expect == "fail") != failed:
                problems.append(f"{risk}: terraform test {test_file} {verdict(failed)}")
        else:
            cells.append("-")
        if namespace:
            failed = namespace in policies
            cells.append(verdict(failed))
            if (args.expect == "fail") != failed:
                problems.append(f"{risk}: conftest {namespace} {verdict(failed)}")
        else:
            cells.append("-")
        if checkov_ids:
            failed_ids = [c for c in checkov_ids if checkov.get(c) == "FAILED"]
            if args.expect == "fail":
                missed = [c for c in checkov_ids if c not in failed_ids]
                cells.append(caught if not missed else f"missed {', '.join(missed)}")
                if missed:
                    problems.append(f"{risk}: Checkov did not flag {', '.join(missed)}")
            else:
                cells.append(clean if not failed_ids else f"fails {', '.join(failed_ids)}")
                if failed_ids:
                    problems.append(f"{risk}: Checkov flags {', '.join(failed_ids)}")
        else:
            cells.append("-")
        rows.append((risk, finding, *cells))

    if args.expect == "pass":
        if any(v == "fail" for v in tests.values()):
            problems.append("a terraform test file failed")
        if policies:
            problems.append(f"conftest failures: {', '.join(sorted(policies))}")
        if "FAILED" in checkov.values():
            problems.append("Checkov failures: " + ", ".join(sorted(k for k, v in checkov.items() if v == "FAILED")))

    title = "Flawed code (tag before)" if args.expect == "fail" else "Reviewed code (main)"
    lines = [f"### {title}", "", "| Risk | Finding | terraform test | conftest | Checkov |", "|---|---|---|---|---|"]
    lines += ["| " + " | ".join(row) + " |" for row in rows]
    lines.append("")
    if problems:
        lines.append("**Unexpected:**")
        lines += [f"- {p}" for p in problems]
    else:
        lines.append("Every risk was caught." if args.expect == "fail" else "Every check passes.")
    report = "\n".join(lines) + "\n"

    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(report + "\n")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
