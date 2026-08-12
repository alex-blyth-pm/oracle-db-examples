#!/usr/bin/env bash
# Create a complete CDB thin clone and all its PDBs with gDBClone.

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
require_lab04_value LAB04_SYS_PASSWORD_FILE
require_positive_integer_or_empty LAB04_SGA_TARGET_MB
require_positive_integer_or_empty LAB04_SGA_MAX_SIZE_MB

if [ "$LAB04_SOURCE_DB_UNIQUE_NAME" = "$LAB04_TARGET_DB_UNIQUE_NAME" ]; then
    echo "ERROR: LAB04_SOURCE_DB_UNIQUE_NAME and LAB04_TARGET_DB_UNIQUE_NAME must be different." >&2
    exit 1
fi

if [ ! -f "$LAB04_SYS_PASSWORD_FILE" ]; then
    echo "ERROR: Encrypted SYS password file was not found: $LAB04_SYS_PASSWORD_FILE" >&2
    echo "Run 02-create-sys-password-file.sh first." >&2
    exit 1
fi

verify_source_cdb
require_gdbclone_database "$LAB04_SOURCE_DB_UNIQUE_NAME"
require_gdbclone_database_absent "$LAB04_TARGET_DB_UNIQUE_NAME"

if lab04_state_exists; then
    echo "ERROR: Lab 04 state file already exists. Verify or clean up the existing Lab 04 clone before creating another." >&2
    exit 1
fi

echo "Current registered gDBClone databases:"
run_gdbclone listdbs

confirm_lab04_action "Create thin CDB $LAB04_TARGET_DB_NAME with DB_UNIQUE_NAME $LAB04_TARGET_DB_UNIQUE_NAME from source CDB $LAB04_SOURCE_DB_UNIQUE_NAME."

echo "Creating thin CDB $LAB04_TARGET_DB_NAME with DB_UNIQUE_NAME $LAB04_TARGET_DB_UNIQUE_NAME from $LAB04_SOURCE_DB_UNIQUE_NAME"
gdbclone_snap_arguments=(
    snap
    --sdbname "$LAB04_SOURCE_DB_UNIQUE_NAME"
    --tdbname "$LAB04_TARGET_DB_NAME"
    --tdbuniquename "$LAB04_TARGET_DB_UNIQUE_NAME"
    --racmod "$LAB04_RAC_MODE"
)

if [ -n "${LAB04_SGA_TARGET_MB:-}" ]; then
    gdbclone_snap_arguments+=( --sga_target "$LAB04_SGA_TARGET_MB" )
fi
if [ -n "${LAB04_SGA_MAX_SIZE_MB:-}" ]; then
    gdbclone_snap_arguments+=( --sga_max_size "$LAB04_SGA_MAX_SIZE_MB" )
fi
gdbclone_snap_arguments+=( --syspwf "$LAB04_SYS_PASSWORD_FILE" )

run_gdbclone "${gdbclone_snap_arguments[@]}"

write_lab04_state

echo "PASS: gDBClone snap completed. Run 04-reconcile-target-pdb-services.sh next."
