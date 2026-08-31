#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../sources.lock
source "$REPO_ROOT/sources.lock"

die() { echo "ERROR: $*" >&2; exit 1; }

sha256_check() {
	local expected=$1 file=$2 actual
	actual=$(sha256sum "$file" | awk '{print $1}')
	[ "$actual" = "$expected" ] || die "SHA-256 mismatch for $file"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}
