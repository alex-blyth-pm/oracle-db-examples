#!/usr/bin/env bash
#
# Run Lab 03 end-to-end without interactive SQL prompts.
#
# The runner removes prior Lab 03 objects, then creates and verifies both the
# source-snapshot and direct cross-CDB thin clones. It leaves both clones
# available for inspection. Use 99-reset-lab.sh for final cleanup.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
source_connect=${LAB03_SOURCE_DB_CONNECT:-}
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
        sqlplus) command -v sqlplus ;;
        *)
            echo "ERROR: LAB_SQL_CLIENT must be auto, sqlcl, sql, or sqlplus." >&2
            return 1
            ;;
    esac
}

lab_config_value() {
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

if [ -z "$source_connect" ] || [ -z "$target_connect" ]; then
    echo "ERROR: Set LAB03_SOURCE_DB_CONNECT and LAB03_TARGET_DB_CONNECT." >&2
    exit 1
fi

target_pdb=$(lab_config_value LAB03_TARGET_PDB)
direct_target_pdb=$(lab_config_value LAB03_DIRECT_TARGET_PDB)
if [ -z "$target_pdb" ] || [ -z "$direct_target_pdb" ]; then
    echo "ERROR: Set LAB03_TARGET_PDB and LAB03_DIRECT_TARGET_PDB in config.sql." >&2
    exit 1
fi

sql_bin=$(find_sql_client)

run_sql() {
    local label=$1
    local connect_string=$2
    local script_name=$3

    echo
    echo "==> ${label}: ${script_name}"
    (
        cd "$script_dir"
        printf '@%s\nEXIT SQL.SQLCODE\n' "$script_name" |
            "$sql_bin" -s "$connect_string"
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

run_clusterware() {
    local command_name=$1
    local pdb_names=$2

    echo
    echo "==> Clusterware: ${command_name} ${pdb_names}"
    PDB_CLUSTERWARE_PDB_CONFIG="$script_dir/config.sql" \
        "$repo_root/common/manage-pdb-clusterware.sh" "$command_name" "$pdb_names"
}

echo "Running Lab 03 without interactive pauses"
echo "SQL client: $sql_bin"

run_sql "Source CDB" "$source_connect" 01-preflight-source.sql
run_sql "Target CDB" "$target_connect" 02-preflight-target.sql
set_target_clusterware_environment

echo
echo "==> Resetting prior Lab 03 objects"
"$script_dir/99-reset-lab.sh"

run_sql "Source CDB" "$source_connect" 03-create-source-link-user.sql
run_sql "Target CDB" "$target_connect" 04-create-source-database-link.sql
run_sql "Source CDB" "$source_connect" 05-create-source-snapshot.sql
run_sql "Target CDB" "$target_connect" 06-create-target-clone.sql
run_clusterware ensure-and-start "$target_pdb"
run_sql "Target CDB" "$target_connect" 07-verify-target-clone.sql
run_sql "Target CDB" "$target_connect" 08-create-direct-target-clone.sql
run_clusterware ensure-and-start "$direct_target_pdb"
run_sql "Target CDB" "$target_connect" 09-verify-direct-target-clone.sql
run_clusterware verify "${target_pdb},${direct_target_pdb}"

echo
echo "Lab 03 complete. Both target clones are available for inspection."
