#!/usr/bin/env bash
# Rename cloned PDBs and manage their distinct services with Clusterware.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

load_lab04_environment
require_db_unique_name LAB04_SOURCE_DB_UNIQUE_NAME
require_db_name LAB04_TARGET_DB_NAME
require_db_unique_name LAB04_TARGET_DB_UNIQUE_NAME
require_target_pdb_prefix
require_rac_service_preferred
require_lab04_managed_target
verify_target_cdb
validate_target_rac_service_preferred

mapfile -t current_pdbs < <(get_target_pdb_names)
if [ "${#current_pdbs[@]}" -eq 0 ]; then
    echo "ERROR: The target CDB contains no user PDBs to reconcile." >&2
    exit 1
fi

target_pdbs=()
for current_pdb in "${current_pdbs[@]}"; do
    case "$current_pdb" in
        [![:alpha:]]*|*[![:alnum:]_\$#]*)
            echo "ERROR: Unsupported PDB name returned by the target CDB: $current_pdb" >&2
            exit 1
            ;;
    esac

    if [[ "$current_pdb" == "$LAB04_TARGET_PDB_PREFIX"* ]]; then
        target_pdbs+=("$current_pdb")
        continue
    fi

    renamed_pdb="${LAB04_TARGET_PDB_PREFIX}${current_pdb}"
    if [ "${#renamed_pdb}" -gt 30 ]; then
        echo "ERROR: Target PDB name exceeds 30 characters: $renamed_pdb" >&2
        exit 1
    fi
    target_pdbs+=("$renamed_pdb")
done

echo
echo "Target PDB and Clusterware service plan"
printf '%-30s %-30s %s\n' "CLONED_PDB" "TARGET_PDB" "SERVICE"
printf '%-30s %-30s %s\n' "------------------------------" "------------------------------" "----------------------------------"
for index in "${!current_pdbs[@]}"; do
    printf '%-30s %-30s %s\n' \
        "${current_pdbs[$index]}" \
        "${target_pdbs[$index]}" \
        "${target_pdbs[$index]}_SVC"
done

echo
echo "The SQL/DDL for each PDB is displayed immediately before it runs."
echo "After renaming, the script creates and starts a Clusterware PDB resource and _SVC service."

confirm_lab04_action "Rename ${#current_pdbs[@]} cloned PDBs with prefix $LAB04_TARGET_PDB_PREFIX and create their Clusterware services."

sql_bin=$(find_lab04_sql_client)
for index in "${!current_pdbs[@]}"; do
    current_pdb=${current_pdbs[$index]}
    target_pdb=${target_pdbs[$index]}

    if [ "$current_pdb" = "$target_pdb" ]; then
        echo "PDB already has the target prefix: $target_pdb"
        continue
    fi

    echo "Renaming cloned PDB $current_pdb to $target_pdb"
    echo "SQL/DDL:"
    echo "  -- Closes the PDB across RAC only when it is currently open."
    echo "  ALTER PLUGGABLE DATABASE $current_pdb CLOSE IMMEDIATE INSTANCES = ALL;"
    echo "  ALTER PLUGGABLE DATABASE $current_pdb OPEN READ WRITE RESTRICTED;"
    echo "  ALTER SESSION SET CONTAINER = $current_pdb;"
    echo "  ALTER PLUGGABLE DATABASE RENAME GLOBAL_NAME TO $target_pdb;"
    echo "  ALTER PLUGGABLE DATABASE CLOSE IMMEDIATE;"
    echo "  ALTER SESSION SET CONTAINER = CDB\$ROOT;"
    "$sql_bin" -L -s "$LAB04_TARGET_DB_CONNECT" <<SQL
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_open_instances PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_open_instances
    FROM   gv\$pdbs
    WHERE  name = '$current_pdb'
    AND    open_mode <> 'MOUNTED';

    IF l_open_instances > 0 THEN
        EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE $current_pdb CLOSE IMMEDIATE INSTANCES = ALL';
    END IF;
END;
/

ALTER PLUGGABLE DATABASE $current_pdb OPEN READ WRITE RESTRICTED;
ALTER SESSION SET CONTAINER = $current_pdb;
ALTER PLUGGABLE DATABASE RENAME GLOBAL_NAME TO $target_pdb;
ALTER PLUGGABLE DATABASE CLOSE IMMEDIATE;
ALTER SESSION SET CONTAINER = CDB\$ROOT;

EXIT SQL.SQLCODE
SQL

    write_lab04_target_pdb_state "${target_pdbs[@]:0:index + 1}"
done

write_lab04_target_pdb_state "${target_pdbs[@]}"

pdb_list=$(IFS=,; echo "${target_pdbs[*]}")
echo "Creating and starting Clusterware PDB resources and services in $LAB04_TARGET_DB_UNIQUE_NAME"
CDB_UNIQUE_NAME="$LAB04_TARGET_DB_UNIQUE_NAME" \
RAC_SERVICE_PREFERRED="$LAB04_RAC_SERVICE_PREFERRED" \
PDB_CLUSTERWARE_DERIVE_SERVICE=YES \
"$repo_root/common/manage-pdb-clusterware.sh" ensure-and-start "$pdb_list"

echo "Verifying target PDB resources and services"
CDB_UNIQUE_NAME="$LAB04_TARGET_DB_UNIQUE_NAME" \
RAC_SERVICE_PREFERRED="$LAB04_RAC_SERVICE_PREFERRED" \
PDB_CLUSTERWARE_DERIVE_SERVICE=YES \
"$repo_root/common/manage-pdb-clusterware.sh" verify "$pdb_list"

echo "PASS: Cloned PDB names, default services, and Clusterware-managed _SVC services are distinct from the source CDB."
