#!/usr/bin/env bash
# Validate the source CDB and gDBClone registrations before Lab 04.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

load_lab04_environment
require_gdbclone
require_db_unique_name LAB04_SOURCE_DB_UNIQUE_NAME
require_db_name LAB04_TARGET_DB_NAME
require_db_unique_name LAB04_TARGET_DB_UNIQUE_NAME
require_target_pdb_prefix
require_rac_mode

if [ "$LAB04_SOURCE_DB_UNIQUE_NAME" = "$LAB04_TARGET_DB_UNIQUE_NAME" ]; then
    echo "ERROR: LAB04_SOURCE_DB_UNIQUE_NAME and LAB04_TARGET_DB_UNIQUE_NAME must be different." >&2
    exit 1
fi

verify_source_cdb
verify_source_pdb_rename_prefix
check_source_vault_capacity
check_target_hugepages
require_gdbclone_database "$LAB04_SOURCE_DB_UNIQUE_NAME"
require_gdbclone_database_absent "$LAB04_TARGET_DB_UNIQUE_NAME"

echo "PASS: Source CDB, target PDB names, vault capacity, target hugepages, gDBClone registration, and target CDB name are ready."
