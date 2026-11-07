#!/usr/bin/env bash
# Runs every review check on the Terraform code, offline.
#
#   scripts/check.sh           checks infra/ (the reviewed version, branch main)
#   scripts/check.sh before    checks the flawed version from the `before` tag,
#                              using the tests and policies of this checkout
#
# Needs terraform >= 1.10, git, and docker (or the checkov and conftest binaries).
# No AWS account or credentials are involved: terraform test runs against a mocked
# provider, and checkov and conftest only read the files.
# Logs go to out/<target>/; scripts/findings.py turns them into a table.
set -uo pipefail

CHECKOV_IMAGE="bridgecrew/checkov:3.4.3"
CONFTEST_IMAGE="openpolicyagent/conftest:v0.71.1"

target="${1:-main}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2
# Windows (Git Bash) tools need C:/... paths; elsewhere this is just $root.
root_native="$(pwd -W 2>/dev/null || pwd)"

# Keep any real AWS profile or key away from every tool.
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_CONFIG_FILE="$root_native/.no-aws-config"
export AWS_SHARED_CREDENTIALS_FILE="$root_native/.no-aws-credentials"
export AWS_EC2_METADATA_DISABLED=true
export CHECKPOINT_DISABLE=1 TF_IN_AUTOMATION=1
# Both targets share one provider download (set TF_DATA_DIR to reuse another one).
export TF_DATA_DIR="${TF_DATA_DIR:-$root_native/infra/.terraform}"

case "$target" in
  main)
    dir="infra"
    ;;
  before)
    if ! git rev-parse -q --verify refs/tags/before >/dev/null; then
      echo "The 'before' tag is missing. Run: git fetch --tags" >&2
      exit 2
    fi
    dir=".before/infra"
    rm -rf .before
    mkdir -p .before
    git archive before infra | tar -x -C .before
    rm -rf "$dir/tests"
    cp -R infra/tests "$dir/tests"
    ;;
  *)
    echo "usage: scripts/check.sh [main|before]" >&2
    exit 2
    ;;
esac

out="out/$target"
rm -rf "$out"
mkdir -p "$out"

# These three functions run through check(), which shellcheck cannot follow.
# shellcheck disable=SC2317
use_docker() {
  [ "${USE_DOCKER:-auto}" != 0 ] && command -v docker >/dev/null 2>&1
}

# shellcheck disable=SC2317
checkov_cmd() {
  if use_docker; then
    MSYS_NO_PATHCONV=1 docker run --rm -v "$root_native:/w" -w /w "$CHECKOV_IMAGE" "$@"
  else
    checkov "$@"
  fi
}

# shellcheck disable=SC2317
conftest_cmd() {
  if use_docker; then
    MSYS_NO_PATHCONV=1 docker run --rm -v "$root_native:/w" -w /w "$CONFTEST_IMAGE" "$@"
  else
    conftest "$@"
  fi
}

status=0
check() {
  local name="$1"
  shift
  if "$@" >"$out/$name.log" 2>&1; then
    printf 'PASS  %-16s\n' "$name"
  else
    printf 'FAIL  %-16s %s/%s.log\n' "$name" "$out" "$name"
    status=1
  fi
}

echo "Checking $dir"
check fmt terraform -chdir="$dir" fmt -check -recursive -no-color
check init terraform -chdir="$dir" init -backend=false -input=false -no-color
check validate terraform -chdir="$dir" validate -no-color
check test terraform -chdir="$dir" test -no-color
check checkov checkov_cmd --config-file .checkov.yaml -d "$dir"
check conftest conftest_cmd test --parser hcl2 --combine --all-namespaces --no-color -p policy "$dir"/*.tf
if [ "$target" = main ]; then
  check policy-tests conftest_cmd verify --no-color -p policy
fi

exit "$status"
