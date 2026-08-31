#!/bin/bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

require_command git
git ls-remote --tags --refs "$KERNEL_REPOSITORY" 'v[0-9]*' |
	awk -F/ '{print $3}' |
	grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' |
	sort -V |
	tail -n 1
