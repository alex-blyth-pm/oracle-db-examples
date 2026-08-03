#!/usr/bin/env bash
#
# Reset all Lab 03 objects without interactive SQL prompts.
#
# The target-CDB reset removes both target clones and the target-side database
# link. The final source-CDB cleanup removes the dedicated source snapshot.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source_connect=${LAB03_SOURCE_DB_CONNECT:-}
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

if [ ! -f "$script_dir/config.sql" ]; then
    echo "ERROR: Copy config.sql.example to config.sql and configure Lab 03." >&2
    exit 1
fi

if [ -z "$source_connect" ]; then
    echo "ERROR: Set LAB03_SOURCE_DB_CONNECT to a source CDB root connection." >&2
    exit 1
fi

if [ -z "${LAB03_TARGET_DB_CONNECT:-}" ]; then
    echo "ERROR: Set LAB03_TARGET_DB_CONNECT to a target CDB root connection." >&2
    exit 1
fi

sql_bin=$(find_sql_client)

echo "Resetting Lab 03 objects"
"$script_dir/99-reset-target-lab.sh"

echo "Removing the Lab 03 source snapshot"
(
    cd "$script_dir"
    printf '@09-cleanup-source.sql\nEXIT SQL.SQLCODE\n' |
        "$sql_bin" -s "$source_connect"
)

echo "Lab 03 reset complete."
