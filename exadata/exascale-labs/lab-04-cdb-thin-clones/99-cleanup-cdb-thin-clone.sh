#!/usr/bin/env bash
# Remove the Lab 04 target CDB with gDBClone.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

force_requested=NO
if [ "$#" -eq 1 ] && [ "$1" = -force ]; then
    force_requested=YES
elif [ "$#" -ne 0 ]; then
    echo "ERROR: Unexpected cleanup argument: $1" >&2
    exit 2
fi

load_lab04_environment
require_gdbclone
require_db_unique_name LAB04_SOURCE_DB_UNIQUE_NAME
require_db_name LAB04_TARGET_DB_NAME
require_db_unique_name LAB04_TARGET_DB_UNIQUE_NAME
require_gdbclone_database "$LAB04_SOURCE_DB_UNIQUE_NAME"
require_gdbclone_database "$LAB04_TARGET_DB_UNIQUE_NAME"

target_pdbs=()
force_cleanup=NO
if lab04_state_exists; then
    require_target_pdb_prefix
    require_lab04_managed_target
    mapfile -t target_pdbs < <(get_lab04_state_target_pdbs)
elif [ "$force_requested" = YES ]; then
    force_cleanup=YES
    echo "WARNING: Lab 04 state file is missing. Continuing because -force was specified."

else
    echo "ERROR: Lab 04 state file is missing. Refusing to operate on an unmanaged target CDB." >&2
    echo "Use -force only when deliberately recovering a Lab 04 target CDB." >&2
    exit 1
fi

if [ "${#target_pdbs[@]}" -eq 0 ]; then
    if [ -z "${LAB04_TARGET_DB_CONNECT:-}" ] ||
       [ -z "${LAB04_TARGET_PDB_PREFIX:-}" ]; then
        if [ "$force_cleanup" = YES ]; then
            echo "WARNING: Target connection or PDB prefix is unavailable. Skipping Clusterware PDB resource and service removal."
        else
            echo "ERROR: Target connection and PDB prefix are required to verify cleanup of an interrupted reconciliation." >&2
            exit 1
        fi
    else
        require_target_pdb_prefix
        require_rac_service_preferred
        echo "Discovering target-prefixed PDBs for Clusterware cleanup"
        mapfile -t target_pdbs < <(discover_target_prefixed_pdbs)
    fi
fi

echo "Current gDBClone database registrations:"
run_gdbclone listdbs

if [ "${#target_pdbs[@]}" -gt 0 ]; then
    pdb_list=$(IFS=,; echo "${target_pdbs[*]}")
    echo "Removing target PDB Clusterware resources and services"
    validate_target_rac_service_preferred
    CDB_UNIQUE_NAME="$LAB04_TARGET_DB_UNIQUE_NAME" \
    RAC_SERVICE_PREFERRED="$LAB04_RAC_SERVICE_PREFERRED" \
    PDB_CLUSTERWARE_DERIVE_SERVICE=YES \
    "$script_dir/../common/manage-pdb-clusterware.sh" stop-and-remove "$pdb_list"
fi

if [ "$force_cleanup" = YES ]; then
    confirm_lab04_action "FORCE delete target CDB $LAB04_TARGET_DB_UNIQUE_NAME with gDBClone without Lab 04 state."
else
    confirm_lab04_action "Delete target CDB $LAB04_TARGET_DB_UNIQUE_NAME with gDBClone."
fi

run_gdbclone deldb -tdbname "$LAB04_TARGET_DB_UNIQUE_NAME"

remove_lab04_state

echo "PASS: gDBClone deldb completed."
echo "Remaining gDBClone database registrations:"
run_gdbclone listdbs
