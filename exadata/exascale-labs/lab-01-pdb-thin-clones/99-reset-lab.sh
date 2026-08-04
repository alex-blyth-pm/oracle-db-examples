#!/usr/bin/env bash
#
# Reset Lab 01 objects without interactive SQL prompts.
#
# The wrapper removes Clusterware PDB services and resources before the SQL
# cleanup drops developer clones and Lab 01 snapshots.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

sql_connect=${LAB_DB_CONNECT:-"/ as sysdba"}
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

sql_bin=$(find_sql_client)
read -r -a connect_args <<< "$sql_connect"

echo "Resetting Lab 01 objects"
echo "SQL client: ${sql_bin}"

"$repo_root/common/manage-pdb-clusterware.sh" stop-and-remove \
    "DEV_JORDAN,DEV_SARAH,DEV_ALEX"

(
    cd "$script_dir"
    printf '@10-cleanup.sql\nEXIT SQL.SQLCODE\n' |
        "$sql_bin" -s "${connect_args[@]}"
)

echo "Lab 01 reset complete."
