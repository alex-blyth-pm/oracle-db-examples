#!/usr/bin/env bash
# Run the Lab 04 CDB thin-clone flow without interactive confirmation prompts.
# Create the encrypted SYS password file with 02-create-sys-password-file.sh
# before using this runner.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

load_lab04_environment

if [ "${LAB04_RUN_CONFIRM:-}" != "YES" ]; then
    echo "ERROR: Set LAB04_RUN_CONFIRM=YES to run the non-interactive Lab 04 flow." >&2
    exit 1
fi

echo "Running Lab 04 non-interactively"
echo
echo "==> Preflight: source CDB identity, vault capacity, target hugepages, and gDBClone registration"
"$script_dir/00-preflight-source-cdb.sh"
echo
echo "==> gDBClone: list registered databases"
"$script_dir/01-list-gdbclone-databases.sh"
echo
echo "==> gDBClone: create CDB thin clone"
LAB04_CONFIRM=YES "$script_dir/03-create-cdb-thin-clone.sh"
echo
echo "==> Target CDB: reconcile cloned PDB names and Clusterware services"
LAB04_CONFIRM=YES "$script_dir/04-reconcile-target-pdb-services.sh"
echo
echo "==> Verify: target CDB, Clusterware resources and services, and gDBClone registration"
"$script_dir/05-verify-cdb-thin-clone.sh"

echo
echo "Lab 04 complete. Target CDB: ${LAB04_TARGET_DB_UNIQUE_NAME}"
