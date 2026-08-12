#!/usr/bin/env bash
# Verify the gDBClone CDB thin-clone relationship and target PDB services.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

load_lab04_environment
require_gdbclone
require_db_unique_name LAB04_SOURCE_DB_UNIQUE_NAME
require_db_name LAB04_TARGET_DB_NAME
require_db_unique_name LAB04_TARGET_DB_UNIQUE_NAME
require_target_pdb_prefix
require_lab04_managed_target
require_gdbclone_database "$LAB04_SOURCE_DB_UNIQUE_NAME"
require_gdbclone_database "$LAB04_TARGET_DB_UNIQUE_NAME"
verify_target_cdb

mapfile -t target_pdbs < <(get_lab04_state_target_pdbs)
if [ "${#target_pdbs[@]}" -eq 0 ]; then
    echo "ERROR: No reconciled target PDBs are recorded. Run 04-reconcile-target-pdb-services.sh first." >&2
    exit 1
fi

pdb_list=$(IFS=,; echo "${target_pdbs[*]}")
echo "Target PDB and Clusterware service summary"
validate_target_rac_service_preferred
CDB_UNIQUE_NAME="$LAB04_TARGET_DB_UNIQUE_NAME" \
RAC_SERVICE_PREFERRED="$LAB04_RAC_SERVICE_PREFERRED" \
PDB_CLUSTERWARE_DERIVE_SERVICE=YES \
"$repo_root/common/manage-pdb-clusterware.sh" summary "$pdb_list"

echo "Verifying gDBClone registration for target $LAB04_TARGET_DB_UNIQUE_NAME"
run_gdbclone listdbs

echo "PASS: Target $LAB04_TARGET_DB_UNIQUE_NAME is registered, its PDB services are Clusterware-managed, and its PDB names are distinct from the source CDB."
