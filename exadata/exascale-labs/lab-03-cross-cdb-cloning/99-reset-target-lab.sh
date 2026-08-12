#!/usr/bin/env bash
#
# Reset Lab 03 objects in the target CDB without interactive SQL prompts.
#
# The wrapper removes Clusterware PDB services and resources before the SQL
# script drops both target PDBs and the target-side database link.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

target_connect=${LAB03_TARGET_DB_CONNECT:-}
sql_client=${LAB_SQL_CLIENT:-auto}

find_sql_client() {
    is_sqlcl() {
        "${1}" -version 2>&1 | grep -qi 'SQLcl'
    }

    case "$sql_client" in
        auto)
            if command -v sql >/dev/null 2>&1 && is_sqlcl "$(command -v sql)"; then
                command -v sql
            elif command -v sqlplus >/dev/null 2>&1; then
                command -v sqlplus
            else
                echo "ERROR: Oracle SQLcl or SQL*Plus was not found in PATH." >&2
                return 1
            fi
            ;;
        sqlcl|sql)
            if ! command -v sql >/dev/null 2>&1 || ! is_sqlcl "$(command -v sql)"; then
                echo "ERROR: LAB_SQL_CLIENT=sql requires Oracle SQLcl; 'sql' is missing or is a different client." >&2
                return 1
            fi
            command -v sql
            ;;
        sqlplus)
            command -v sqlplus
            ;;
        *)
            echo "ERROR: LAB_SQL_CLIENT must be auto, sqlcl, sql, or sqlplus." >&2
            return 1
            ;;
    esac
}

config_value() {
    local name=$1

    awk -v name="$name" '
        $1 == "DEFINE" && $2 == name {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*--.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$script_dir/config.sql"
}

if [ ! -f "$script_dir/config.sql" ]; then
    echo "ERROR: Copy config.sql.example to config.sql and configure Lab 03." >&2
    exit 1
fi

if [ -z "$target_connect" ]; then
    echo "ERROR: Set LAB03_TARGET_DB_CONNECT to a target CDB root connection." >&2
    exit 1
fi

target_pdb=$(config_value LAB03_TARGET_PDB)
direct_target_pdb=$(config_value LAB03_DIRECT_TARGET_PDB)
if [ -z "$target_pdb" ] || [ -z "$direct_target_pdb" ]; then
    echo "ERROR: Set LAB03_TARGET_PDB and LAB03_DIRECT_TARGET_PDB in config.sql." >&2
    exit 1
fi

sql_bin=$(find_sql_client)

run_sql() {
    local script_name=$1

    (
        cd "$script_dir"
        printf '@%s\nEXIT SQL.SQLCODE\n' "$script_name" |
            "$sql_bin" -s "$target_connect"
    )
}

set_target_clusterware_environment() {
    local clusterware_values
    local cdb_unique_name
    local rac_service_preferred

    clusterware_values=$(
        (
            cd "$script_dir"
            printf '%s\n' \
                'SET HEADING OFF' \
                'SET FEEDBACK OFF' \
                'SET PAGESIZE 0' \
                'SET TRIMSPOOL ON' \
                'SET LINESIZE 1000' \
                "SELECT value FROM v\$parameter WHERE name = 'db_unique_name';" \
                "SELECT LISTAGG(instance_name, ',') WITHIN GROUP (ORDER BY inst_id) FROM gv\$instance;" \
                'EXIT SQL.SQLCODE' |
                "$sql_bin" -s "$target_connect"
        )
    )

    cdb_unique_name=$(printf '%s\n' "$clusterware_values" |
        awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
    rac_service_preferred=$(printf '%s\n' "$clusterware_values" |
        awk 'NF { value = $0 } END { gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value }')

    if [ -z "$cdb_unique_name" ] || [ -z "$rac_service_preferred" ]; then
        echo "ERROR: Could not determine the target CDB Clusterware environment." >&2
        exit 1
    fi

    export CDB_UNIQUE_NAME="$cdb_unique_name"
    export RAC_SERVICE_PREFERRED="$rac_service_preferred"

    echo "Target Clusterware CDB_UNIQUE_NAME: ${CDB_UNIQUE_NAME}"
    echo "Target Clusterware RAC_SERVICE_PREFERRED: ${RAC_SERVICE_PREFERRED}"
}

echo "Resetting Lab 03 target-CDB objects"
echo "SQL client: ${sql_bin}"

run_sql 00-preflight-target.sql
set_target_clusterware_environment

PDB_CLUSTERWARE_PDB_CONFIG="$script_dir/config.sql" \
    "$repo_root/common/manage-pdb-clusterware.sh" stop-and-remove \
        "${direct_target_pdb},${target_pdb}"

(
    cd "$script_dir"
    printf '@99-reset-target-lab.sql\nEXIT SQL.SQLCODE\n' |
        "$sql_bin" -s "$target_connect"
)

echo "Lab 03 target-CDB reset complete."
