#!/usr/bin/env bash
# List CDBs registered with gDBClone and show clone relationships.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

load_lab04_environment
require_gdbclone

echo "Listing gDBClone databases and clone relationships"
run_gdbclone listdbs
