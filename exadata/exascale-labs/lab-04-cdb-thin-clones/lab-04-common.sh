#!/usr/bin/env bash
# Shared environment and safety helpers for Lab 04 shell scripts.

set -euo pipefail

lab04_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lab04_repo_root=$(cd "$lab04_script_dir/.." && pwd)
lab04_state_file="$lab04_script_dir/.lab04-clone-state"

load_lab04_environment() {
    local environment_file=${LAB_ENV_FILE:-"$lab04_repo_root/.env.local"}

    if [ -n "${LAB_ENV_FILE:-}" ] && [ ! -f "$environment_file" ]; then
        echo "ERROR: LAB_ENV_FILE was specified but does not exist: $environment_file" >&2
        exit 1
    fi

    if [ -f "$environment_file" ]; then
        # The environment file is user-managed and is intentionally not tracked.
        # shellcheck disable=SC1090
        . "$environment_file"
    fi

    if [ -z "${LAB04_SYS_PASSWORD_FILE:-}" ]; then
        LAB04_SYS_PASSWORD_FILE="$lab04_script_dir/SYSpasswd_file"
    fi
}

require_lab04_value() {
    local variable_name=$1
    local variable_value=${!variable_name:-}

    if [ -z "$variable_value" ]; then
        echo "ERROR: Set $variable_name in .env.local or the shell environment." >&2
        exit 1
    fi
}

require_gdbclone() {
    require_lab04_value GDBCLONE_BIN

    if [ ! -x "$GDBCLONE_BIN" ]; then
        echo "ERROR: gDBClone executable was not found: $GDBCLONE_BIN" >&2
        exit 1
    fi

    if ! command -v "${LAB04_SUDO_BIN:-sudo}" >/dev/null 2>&1; then
        echo "ERROR: sudo executable was not found: ${LAB04_SUDO_BIN:-sudo}" >&2
        exit 1
    fi
}

run_lab04_sudo() {
    "${LAB04_SUDO_BIN:-sudo}" -n "$@"
}

run_gdbclone() {
    # Write the command to stderr so callers that capture listdbs output retain
    # only gDBClone's output. Arguments are shell-quoted for safe copy/paste.
    printf 'gDBClone command: ' >&2
    printf '%q ' "${LAB04_SUDO_BIN:-sudo}" -n "$GDBCLONE_BIN" "$@" >&2
    printf '\n' >&2
    run_lab04_sudo "$GDBCLONE_BIN" "$@"
}

require_db_unique_name() {
    local variable_name=$1
    local database_name=${!variable_name:-}

    require_lab04_value "$variable_name"

    case "$database_name" in
        *[![:alnum:]_\$#]* )
            echo "ERROR: $variable_name must be an unquoted DB_UNIQUE_NAME." >&2
            exit 1
            ;;
    esac
}

require_db_name() {
    local variable_name=$1
    local database_name=${!variable_name:-}

    require_lab04_value "$variable_name"

    case "$database_name" in
        [![:alpha:]]*|*[![:alnum:]]*)
            echo "ERROR: $variable_name must begin with a letter and contain only alphanumeric characters." >&2
            exit 1
            ;;
    esac

    if [ "${#database_name}" -gt 8 ]; then
        echo "ERROR: $variable_name must not exceed 8 characters." >&2
        exit 1
    fi
}

require_target_pdb_prefix() {
    require_lab04_value LAB04_TARGET_PDB_PREFIX

    case "$LAB04_TARGET_PDB_PREFIX" in
        [![:alpha:]]*|*[![:alnum:]_]* )
            echo "ERROR: LAB04_TARGET_PDB_PREFIX must begin with a letter and contain only letters, numbers, and underscores." >&2
            exit 1
            ;;
    esac

    if [ "${#LAB04_TARGET_PDB_PREFIX}" -ge 30 ]; then
        echo "ERROR: LAB04_TARGET_PDB_PREFIX must leave room for a PDB name within Oracle's 30-character limit." >&2
        exit 1
    fi
}

require_rac_service_preferred() {
    case "${LAB04_RAC_SERVICE_PREFERRED:-}" in
        "")
            return
            ;;
        *[![:alnum:]_,]*|,*|*,,*)
            echo "ERROR: LAB04_RAC_SERVICE_PREFERRED must be a comma-separated list of target RAC instance names." >&2
            exit 1
            ;;
    esac
}

get_target_rac_instance_names() {
    local srvctl_bin=${SRVCTL_BIN:-srvctl}
    local srvctl_output
    local instance_names

    if ! command -v "$srvctl_bin" >/dev/null 2>&1; then
        echo "ERROR: srvctl was not found. Set SRVCTL_BIN or run from the Oracle Grid or database environment." >&2
        exit 1
    fi

    if ! srvctl_output=$("$srvctl_bin" config database -db "$LAB04_TARGET_DB_UNIQUE_NAME" 2>&1); then
        echo "ERROR: Could not determine Clusterware instances for $LAB04_TARGET_DB_UNIQUE_NAME." >&2
        printf '%s\n' "$srvctl_output" >&2
        exit 1
    fi

    instance_names=$(printf '%s\n' "$srvctl_output" |
        awk -F: '/^Database instances:/ { gsub(/[[:space:]]/, "", $2); print $2 }' |
        tr ',' '\n')
    if [ -z "$instance_names" ]; then
        echo "ERROR: Clusterware did not report any instances for $LAB04_TARGET_DB_UNIQUE_NAME." >&2
        printf '%s\n' "$srvctl_output" >&2
        exit 1
    fi

    printf '%s\n' "$instance_names"
}

validate_target_rac_service_preferred() {
    local configured_instance
    local available_instances
    local canonical_instance
    local resolved_instances=
    local -a configured_instances

    available_instances=$(get_target_rac_instance_names)

    if [ -z "${LAB04_RAC_SERVICE_PREFERRED:-}" ]; then
        LAB04_RAC_SERVICE_PREFERRED=$(printf '%s' "$available_instances" | paste -sd, -)
        echo "INFO: LAB04_RAC_SERVICE_PREFERRED is not set. Using target Clusterware instances: $LAB04_RAC_SERVICE_PREFERRED"
        return
    fi

    require_rac_service_preferred
    IFS=',' read -r -a configured_instances <<< "$LAB04_RAC_SERVICE_PREFERRED"

    for configured_instance in "${configured_instances[@]}"; do
        canonical_instance=$(printf '%s\n' "$available_instances" |
            awk -v configured_instance="$configured_instance" \
                'tolower($0) == tolower(configured_instance) { print; exit }')
        if [ -z "$canonical_instance" ]; then
            echo "ERROR: LAB04_RAC_SERVICE_PREFERRED includes $configured_instance, which is not an instance of $LAB04_TARGET_DB_UNIQUE_NAME." >&2
            echo "Available target instances: $(printf '%s' "$available_instances" | paste -sd, -)." >&2
            exit 1
        fi

        if [ -n "$resolved_instances" ]; then
            resolved_instances+=,
        fi
        resolved_instances+="$canonical_instance"
    done

    LAB04_RAC_SERVICE_PREFERRED=$resolved_instances
    echo "PASS: Target RAC service preferred instances: $LAB04_RAC_SERVICE_PREFERRED"
}

require_rac_mode() {
    require_lab04_value LAB04_RAC_MODE

    case "$LAB04_RAC_MODE" in
        0|1|2) ;;
        *)
            echo "ERROR: LAB04_RAC_MODE must be 0, 1, or 2." >&2
            exit 1
            ;;
    esac
}

require_positive_integer_or_empty() {
    local variable_name=$1
    local variable_value=${!variable_name:-}

    if [ -z "$variable_value" ]; then
        return
    fi

    case "$variable_value" in
        *[!0-9]*|0)
            echo "ERROR: $variable_name must be a positive integer in MB when set." >&2
            exit 1
            ;;
    esac
}

require_percentage() {
    local variable_name=$1
    local variable_value=${!variable_name:-}

    require_lab04_value "$variable_name"
    case "$variable_value" in
        *[!0-9]*|"")
            echo "ERROR: $variable_name must be an integer percentage from 0 to 100." >&2
            exit 1
            ;;
    esac

    if [ "$variable_value" -gt 100 ]; then
        echo "ERROR: $variable_name must be an integer percentage from 0 to 100." >&2
        exit 1
    fi
}

require_lab04_vault_thresholds() {
    : "${LAB04_VAULT_WARN_FREE_PCT:=20}"
    : "${LAB04_VAULT_ERROR_FREE_PCT:=10}"
    require_percentage LAB04_VAULT_WARN_FREE_PCT
    require_percentage LAB04_VAULT_ERROR_FREE_PCT

    if [ "$LAB04_VAULT_ERROR_FREE_PCT" -ge "$LAB04_VAULT_WARN_FREE_PCT" ]; then
        echo "ERROR: LAB04_VAULT_ERROR_FREE_PCT must be lower than LAB04_VAULT_WARN_FREE_PCT." >&2
        exit 1
    fi
}

find_lab04_sql_client() {
    local configured_client=${LAB04_SQL_CLIENT:-auto}

    case "$configured_client" in
        auto)
            if [ -n "${LAB_ORACLE_HOME:-}" ] && [ -x "$LAB_ORACLE_HOME/bin/sqlplus" ]; then
                printf '%s\n' "$LAB_ORACLE_HOME/bin/sqlplus"
            elif command -v sqlplus >/dev/null 2>&1; then
                command -v sqlplus
            elif command -v sql >/dev/null 2>&1; then
                command -v sql
            else
                echo "ERROR: SQL*Plus or SQLcl was not found. Set LAB_ORACLE_HOME or LAB04_SQL_CLIENT." >&2
                exit 1
            fi
            ;;
        sqlplus)
            command -v sqlplus
            ;;
        sql|sqlcl)
            command -v sql
            ;;
        *)
            echo "ERROR: LAB04_SQL_CLIENT must be auto, sqlplus, sql, or sqlcl." >&2
            exit 1
            ;;
    esac
}

get_lab04_terminal_columns() {
    local terminal_columns=${COLUMNS:-}

    case "$terminal_columns" in
        *[!0-9]*|"")
            if command -v tput >/dev/null 2>&1; then
                terminal_columns=$(tput cols 2>/dev/null || true)
            fi
            ;;
    esac

    case "$terminal_columns" in
        *[!0-9]*|"") terminal_columns=100 ;;
    esac

    if [ "$terminal_columns" -lt 80 ]; then
        terminal_columns=80
    elif [ "$terminal_columns" -gt 200 ]; then
        terminal_columns=200
    fi

    printf '%s\n' "$terminal_columns"
}

gdbclone_database_is_registered() {
    local database_name=$1
    local database_list

    if ! database_list=$(run_gdbclone listdbs); then
        echo "ERROR: gDBClone listdbs failed while checking $database_name." >&2
        exit 1
    fi

    printf '%s\n' "$database_list" |
        awk -F '│' -v database_name="$database_name" '
            NF >= 6 {
                database_name_field = $2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", database_name_field)
                if (database_name_field == database_name) {
                    found = 1
                }
            }
            END { exit !found }
        '
}

require_gdbclone_database() {
    local database_name=$1

    if ! gdbclone_database_is_registered "$database_name"; then
        echo "ERROR: $database_name is not registered with gDBClone." >&2
        echo "Run 01-list-gdbclone-databases.sh and verify the DB_UNIQUE_NAME." >&2
        exit 1
    fi
}

require_gdbclone_database_absent() {
    local database_name=$1

    if gdbclone_database_is_registered "$database_name"; then
        echo "ERROR: $database_name is already registered with gDBClone." >&2
        echo "Choose a new LAB04_TARGET_DB_UNIQUE_NAME or clean up the existing clone deliberately." >&2
        exit 1
    fi
}

verify_source_cdb() {
    local sql_bin
    local sql_linesize

    require_lab04_value LAB04_SOURCE_DB_CONNECT
    require_db_unique_name LAB04_SOURCE_DB_UNIQUE_NAME
    sql_bin=$(find_lab04_sql_client)
    sql_linesize=$(get_lab04_terminal_columns)

    echo "Verifying source CDB $LAB04_SOURCE_DB_UNIQUE_NAME"
    "$sql_bin" -L -s "$LAB04_SOURCE_DB_CONNECT" <<SQL
SET LINESIZE $sql_linesize
SET PAGESIZE 100
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_db_unique_name VARCHAR2(128);
    l_log_mode       VARCHAR2(20);
    l_container_name VARCHAR2(128);
BEGIN
    SELECT p.value, d.log_mode, sys_context('USERENV', 'CON_NAME')
    INTO   l_db_unique_name, l_log_mode, l_container_name
    FROM   v\$database d CROSS JOIN v\$parameter p
    WHERE  p.name = 'db_unique_name';

    IF UPPER(l_db_unique_name) <> UPPER('$LAB04_SOURCE_DB_UNIQUE_NAME') THEN
        raise_application_error(
            -20061,
            'Expected source DB_UNIQUE_NAME $LAB04_SOURCE_DB_UNIQUE_NAME but connected to ' || l_db_unique_name
        );
    END IF;

    IF l_container_name <> 'CDB\$ROOT' THEN
        raise_application_error(-20062, 'Connect to CDB\$ROOT. Current container is ' || l_container_name);
    END IF;

    IF l_log_mode <> 'ARCHIVELOG' THEN
        raise_application_error(-20063, 'Source CDB must use ARCHIVELOG mode. Current mode is ' || l_log_mode);
    END IF;

    dbms_output.put_line(
        'PASS: Source connection verified. DB_UNIQUE_NAME=' || l_db_unique_name ||
        ', LOG_MODE=' || l_log_mode || ', CONTAINER=' || l_container_name
    );
END;
/

COLUMN setting FORMAT A20
COLUMN configured_value FORMAT A50

SELECT setting,
       configured_value
FROM (
    SELECT 1 AS display_order, 'Database name' AS setting, d.name AS configured_value
    FROM   v\$database d
    UNION ALL
    SELECT 2, 'DB unique name', p.value
    FROM   v\$parameter p
    WHERE  p.name = 'db_unique_name'
    UNION ALL
    SELECT 3, 'DBID', TO_CHAR(d.dbid)
    FROM   v\$database d
    UNION ALL
    SELECT 4, 'Log mode', d.log_mode
    FROM   v\$database d
    UNION ALL
    SELECT 5, 'Current container', sys_context('USERENV', 'CON_NAME')
    FROM   dual
)
ORDER BY display_order;

EXIT SQL.SQLCODE
SQL
}

verify_source_pdb_rename_prefix() {
    local sql_bin

    require_lab04_value LAB04_SOURCE_DB_CONNECT
    require_target_pdb_prefix
    sql_bin=$(find_lab04_sql_client)

    "$sql_bin" -L -s "$LAB04_SOURCE_DB_CONNECT" <<SQL
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   l_count
    FROM   v\$pdbs
    WHERE  name <> 'PDB\$SEED'
    AND    (UPPER(name) LIKE UPPER('${LAB04_TARGET_PDB_PREFIX}%')
            OR LENGTH('${LAB04_TARGET_PDB_PREFIX}' || name) > 30);

    IF l_count > 0 THEN
        raise_application_error(
            -20067,
            'LAB04_TARGET_PDB_PREFIX ${LAB04_TARGET_PDB_PREFIX} conflicts with a source PDB name or exceeds the 30-character PDB-name limit.'
        );
    END IF;

    dbms_output.put_line('PASS: Target PDB prefix ${LAB04_TARGET_PDB_PREFIX} is valid for every source PDB.');
END;
/

EXIT SQL.SQLCODE
SQL
}

get_target_pdb_names() {
    local sql_bin

    require_lab04_value LAB04_TARGET_DB_CONNECT
    sql_bin=$(find_lab04_sql_client)

    "$sql_bin" -L -s "$LAB04_TARGET_DB_CONNECT" <<SQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET VERIFY OFF
SET TRIMSPOOL ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

SELECT name
FROM   v\$pdbs
WHERE  name <> 'PDB\$SEED'
ORDER  BY con_id;

EXIT SQL.SQLCODE
SQL
}

discover_target_prefixed_pdbs() {
    local pdb_name

    require_lab04_value LAB04_TARGET_DB_CONNECT
    require_target_pdb_prefix
    verify_target_cdb >&2

    while IFS= read -r pdb_name; do
        if [ -n "$pdb_name" ] && [[ "$pdb_name" == "$LAB04_TARGET_PDB_PREFIX"* ]]; then
            printf '%s\n' "$pdb_name"
        fi
    done < <(get_target_pdb_names)
}

check_source_vault_capacity() {
    local sql_bin
    local sql_linesize

    require_lab04_value LAB04_SOURCE_DB_CONNECT
    require_lab04_vault_thresholds
    sql_bin=$(find_lab04_sql_client)
    sql_linesize=$(get_lab04_terminal_columns)

    echo "Checking Exascale vault capacity for the source CDB"
    "$sql_bin" -L -s "$LAB04_SOURCE_DB_CONNECT" <<SQL
SET LINESIZE $sql_linesize
SET PAGESIZE 100
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_free_percent NUMBER;
    l_checked_media PLS_INTEGER := 0;
BEGIN
    FOR r IN (
        SELECT vault_name, media_type, space_prov, space_used
        FROM (
            SELECT vault_name, 'EF' AS media_type, ef_space_prov AS space_prov, ef_space_used AS space_used
            FROM   v\$exa_vault
            UNION ALL
            SELECT vault_name, 'HC', hc_space_prov, hc_space_used
            FROM   v\$exa_vault
            UNION ALL
            SELECT vault_name, 'XT', xt_space_prov, xt_space_used
            FROM   v\$exa_vault
        )
        WHERE NVL(space_prov, 0) > 0
        ORDER BY vault_name, media_type
    ) LOOP
        l_checked_media := l_checked_media + 1;
        l_free_percent := ROUND(100 * (r.space_prov - NVL(r.space_used, 0)) / r.space_prov, 2);
        dbms_output.put_line(
            'Vault ' || r.vault_name || ' ' || r.media_type || ': ' ||
            ROUND(NVL(r.space_used, 0) / 1024 / 1024) || ' MB used of ' ||
            ROUND(r.space_prov / 1024 / 1024) || ' MB, ' || l_free_percent || '% free.'
        );

        IF l_free_percent <= $LAB04_VAULT_ERROR_FREE_PCT THEN
            raise_application_error(
                -20066,
                'Vault ' || r.vault_name || ' ' || r.media_type || ' free capacity is at or below $LAB04_VAULT_ERROR_FREE_PCT%.'
            );
        ELSIF l_free_percent <= $LAB04_VAULT_WARN_FREE_PCT THEN
            dbms_output.put_line(
                'WARNING: Vault ' || r.vault_name || ' ' || r.media_type ||
                ' free capacity is at or below $LAB04_VAULT_WARN_FREE_PCT%.'
            );
        END IF;
    END LOOP;

    IF l_checked_media = 0 THEN
        dbms_output.put_line(
            'INFO: No finite vault space allocation was reported. Review storage-pool capacity with the Exascale administrator.'
        );
    END IF;
END;
/

COLUMN vault_name FORMAT A24
COLUMN media_type FORMAT A10
COLUMN used_mb FORMAT 9999999990
COLUMN provisioned_mb FORMAT 9999999990
COLUMN free_percent FORMAT 990.00

SELECT vault_name,
       media_type,
       ROUND(space_used / 1024 / 1024) AS used_mb,
       ROUND(space_prov / 1024 / 1024) AS provisioned_mb,
       ROUND(100 * (space_prov - space_used) / space_prov, 2) AS free_percent
FROM (
    SELECT vault_name, 'EF' AS media_type, ef_space_used AS space_used, ef_space_prov AS space_prov
    FROM   v\$exa_vault
    UNION ALL
    SELECT vault_name, 'HC', hc_space_used, hc_space_prov
    FROM   v\$exa_vault
    UNION ALL
    SELECT vault_name, 'XT', xt_space_used, xt_space_prov
    FROM   v\$exa_vault
)
WHERE NVL(space_prov, 0) > 0
ORDER BY vault_name, media_type;

EXIT SQL.SQLCODE
SQL
}

get_source_sga_sizes_mb() {
    local sql_bin

    require_lab04_value LAB04_SOURCE_DB_CONNECT
    sql_bin=$(find_lab04_sql_client)

    "$sql_bin" -L -s "$LAB04_SOURCE_DB_CONNECT" <<SQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET VERIFY OFF
SET TRIMSPOOL ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

SELECT ROUND(MAX(CASE WHEN name = 'sga_target' THEN TO_NUMBER(value) END) / 1024 / 1024) || '|' ||
       ROUND(MAX(CASE WHEN name = 'sga_max_size' THEN TO_NUMBER(value) END) / 1024 / 1024)
FROM   gv\$parameter
WHERE  name IN ('sga_target', 'sga_max_size');

EXIT SQL.SQLCODE
SQL
}

get_local_free_hugepages_mb() {
    awk '
        /^HugePages_Free:/ { free_pages = $2 }
        /^Hugepagesize:/ { page_size_kb = $2 }
        END {
            if (free_pages == "" || page_size_kb == "") {
                exit 1
            }
            print int(free_pages * page_size_kb / 1024)
        }
    ' /proc/meminfo
}

is_lab04_local_node() {
    local target_node=$1
    local local_short_name
    local local_full_name

    local_short_name=$(hostname -s)
    local_full_name=$(hostname -f 2>/dev/null || true)

    [ "$target_node" = "$local_short_name" ] ||
        [ "$target_node" = "$local_full_name" ] ||
        [ "$target_node" = "$(hostname)" ]
}

check_target_hugepages() {
    local source_sga_sizes
    local source_sga_target_mb
    local source_sga_max_size_mb
    local effective_sga_target_mb
    local effective_sga_max_size_mb
    local target_nodes
    local target_node
    local available_hugepages_mb
    local -a target_node_list

    require_positive_integer_or_empty LAB04_SGA_TARGET_MB
    require_positive_integer_or_empty LAB04_SGA_MAX_SIZE_MB

    source_sga_sizes=$(get_source_sga_sizes_mb | tr -d '[:space:]')
    IFS='|' read -r source_sga_target_mb source_sga_max_size_mb <<< "$source_sga_sizes"

    if [ -z "$source_sga_target_mb" ] || [ -z "$source_sga_max_size_mb" ]; then
        echo "ERROR: Could not determine SGA_TARGET and SGA_MAX_SIZE from the source CDB." >&2
        exit 1
    fi

    effective_sga_target_mb=${LAB04_SGA_TARGET_MB:-$source_sga_target_mb}
    effective_sga_max_size_mb=${LAB04_SGA_MAX_SIZE_MB:-$source_sga_max_size_mb}

    if [ "$effective_sga_max_size_mb" -lt "$effective_sga_target_mb" ]; then
        echo "ERROR: Effective SGA_MAX_SIZE must be greater than or equal to effective SGA_TARGET." >&2
        exit 1
    fi

    target_nodes=${LAB04_TARGET_DB_NODES:-}
    if [ -z "$target_nodes" ]; then
        echo "ERROR: Set LAB04_TARGET_DB_NODES to the target VM-cluster database server VMs." >&2
        exit 1
    fi
    case "$target_nodes" in
        *[![:alnum:].,_-]*)
            echo "ERROR: LAB04_TARGET_DB_NODES must be a comma-separated list of host names." >&2
            exit 1
            ;;
    esac

    echo "Checking target-server free hugepages against effective SGA_TARGET ${effective_sga_target_mb} MB and SGA_MAX_SIZE ${effective_sga_max_size_mb} MB"
    IFS=',' read -r -a target_node_list <<< "$target_nodes"
    for target_node in "${target_node_list[@]}"; do
        if is_lab04_local_node "$target_node"; then
            if ! available_hugepages_mb=$(get_local_free_hugepages_mb); then
                echo "ERROR: Could not determine free hugepages on local server $target_node." >&2
                exit 1
            fi
        else
            if ! available_hugepages_mb=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$target_node" \
                "awk '/^HugePages_Free:/ { free_pages=\$2 } /^Hugepagesize:/ { page_size_kb=\$2 } END { if (free_pages == \"\" || page_size_kb == \"\") exit 1; print int(free_pages * page_size_kb / 1024) }' /proc/meminfo"); then
                echo "ERROR: Could not determine free hugepages on remote server $target_node. Confirm SSH equivalence and hugepage configuration." >&2
                exit 1
            fi
        fi

        case "$available_hugepages_mb" in
            *[!0-9]*|"")
                echo "ERROR: Invalid free hugepages value returned by $target_node: $available_hugepages_mb" >&2
                exit 1
                ;;
        esac

        if [ "$available_hugepages_mb" -lt "$effective_sga_target_mb" ] ||
           [ "$available_hugepages_mb" -lt "$effective_sga_max_size_mb" ]; then
            echo "ERROR: $target_node has ${available_hugepages_mb} MB of free hugepages, below the required effective SGA_TARGET ${effective_sga_target_mb} MB and SGA_MAX_SIZE ${effective_sga_max_size_mb} MB." >&2
            exit 1
        fi

        echo "PASS: $target_node has ${available_hugepages_mb} MB of free hugepages."
    done
}

verify_target_cdb() {
    local sql_bin
    local sql_linesize

    require_lab04_value LAB04_TARGET_DB_CONNECT
    require_db_unique_name LAB04_TARGET_DB_UNIQUE_NAME
    sql_bin=$(find_lab04_sql_client)
    sql_linesize=$(get_lab04_terminal_columns)

    echo "Verifying target CDB $LAB04_TARGET_DB_UNIQUE_NAME and its PDBs"
    "$sql_bin" -L -s "$LAB04_TARGET_DB_CONNECT" <<SQL
SET LINESIZE $sql_linesize
SET PAGESIZE 100
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_db_unique_name VARCHAR2(128);
    l_container_name VARCHAR2(128);
BEGIN
    SELECT p.value, sys_context('USERENV', 'CON_NAME')
    INTO   l_db_unique_name, l_container_name
    FROM   v\$database d CROSS JOIN v\$parameter p
    WHERE  p.name = 'db_unique_name';

    IF UPPER(l_db_unique_name) <> UPPER('$LAB04_TARGET_DB_UNIQUE_NAME') THEN
        raise_application_error(
            -20064,
            'Expected target DB_UNIQUE_NAME $LAB04_TARGET_DB_UNIQUE_NAME but connected to ' || l_db_unique_name
        );
    END IF;

    IF l_container_name <> 'CDB\$ROOT' THEN
        raise_application_error(-20065, 'Connect to CDB\$ROOT. Current container is ' || l_container_name);
    END IF;

    dbms_output.put_line(
        'PASS: Target connection verified. DB_UNIQUE_NAME=' || l_db_unique_name ||
        ', CONTAINER=' || l_container_name
    );
END;
/

COLUMN setting FORMAT A20
COLUMN configured_value FORMAT A50

SELECT setting,
       configured_value
FROM (
    SELECT 1 AS display_order, 'Database name' AS setting, d.name AS configured_value
    FROM   v\$database d
    UNION ALL
    SELECT 2, 'DB unique name', p.value
    FROM   v\$parameter p
    WHERE  p.name = 'db_unique_name'
    UNION ALL
    SELECT 3, 'DBID', TO_CHAR(d.dbid)
    FROM   v\$database d
    UNION ALL
    SELECT 4, 'Open mode', d.open_mode
    FROM   v\$database d
    UNION ALL
    SELECT 5, 'Current container', sys_context('USERENV', 'CON_NAME')
    FROM   dual
)
ORDER BY display_order;

COLUMN pdb_name FORMAT A30
COLUMN open_mode FORMAT A12

SELECT name AS pdb_name,
       open_mode
FROM   v\$pdbs
ORDER  BY con_id;

EXIT SQL.SQLCODE
SQL
}

write_lab04_state() {
    umask 077
    printf '%s\n' \
        "SOURCE_DB_UNIQUE_NAME=$LAB04_SOURCE_DB_UNIQUE_NAME" \
        "TARGET_DB_NAME=$LAB04_TARGET_DB_NAME" \
        "TARGET_DB_UNIQUE_NAME=$LAB04_TARGET_DB_UNIQUE_NAME" \
        "TARGET_PDB_PREFIX=$LAB04_TARGET_PDB_PREFIX" \
        "RAC_MODE=$LAB04_RAC_MODE" > "$lab04_state_file"
}

write_lab04_target_pdb_state() {
    local pdb_name
    local temporary_state_file

    temporary_state_file=$(mktemp "${lab04_state_file}.XXXXXX")
    awk -F= '$1 != "TARGET_PDB" && $1 != "TARGET_PDB_PREFIX"' "$lab04_state_file" > "$temporary_state_file"
    printf 'TARGET_PDB_PREFIX=%s\n' "$LAB04_TARGET_PDB_PREFIX" >> "$temporary_state_file"
    for pdb_name in "$@"; do
        printf 'TARGET_PDB=%s\n' "$pdb_name" >> "$temporary_state_file"
    done
    chmod 600 "$temporary_state_file"
    mv "$temporary_state_file" "$lab04_state_file"
}

get_lab04_state_target_pdbs() {
    awk -F= '$1 == "TARGET_PDB" { print $2 }' "$lab04_state_file"
}

lab04_state_exists() {
    [ -e "$lab04_state_file" ]
}

remove_lab04_state() {
    rm -f "$lab04_state_file"
}

require_lab04_managed_target() {
    local state_source
    local state_target_name
    local state_target
    local state_target_pdb_prefix

    if [ ! -f "$lab04_state_file" ]; then
        echo "ERROR: Lab 04 state file is missing. Refusing to operate on an unmanaged target CDB." >&2
        exit 1
    fi

    state_source=$(awk -F= '$1 == "SOURCE_DB_UNIQUE_NAME" { print $2; exit }' "$lab04_state_file")
    state_target_name=$(awk -F= '$1 == "TARGET_DB_NAME" { print $2; exit }' "$lab04_state_file")
    state_target=$(awk -F= '$1 == "TARGET_DB_UNIQUE_NAME" { print $2; exit }' "$lab04_state_file")
    state_target_pdb_prefix=$(awk -F= '$1 == "TARGET_PDB_PREFIX" { print $2; exit }' "$lab04_state_file")

    if [ "$state_source" != "$LAB04_SOURCE_DB_UNIQUE_NAME" ] ||
       [ "$state_target_name" != "$LAB04_TARGET_DB_NAME" ] ||
       [ "$state_target" != "$LAB04_TARGET_DB_UNIQUE_NAME" ] ||
       { [ -n "$state_target_pdb_prefix" ] && [ "$state_target_pdb_prefix" != "$LAB04_TARGET_PDB_PREFIX" ]; }; then
        echo "ERROR: Lab 04 state does not match the configured source and target CDBs. Refusing to operate." >&2
        exit 1
    fi
}

confirm_lab04_action() {
    local action=$1
    local response
    local normalized_response

    normalized_response=$(printf '%s' "${LAB04_CONFIRM:-}" | tr '[:lower:]' '[:upper:]')
    if [ "$normalized_response" = YES ]; then
        return
    fi

    if ! read -r -p "$action Type YES to continue: " response; then
        echo "ERROR: Confirmation input was not available." >&2
        exit 1
    fi
    normalized_response=$(printf '%s' "$response" | tr '[:lower:]' '[:upper:]')
    if [ "$normalized_response" != YES ]; then
        echo "Cancelled."
        exit 1
    fi
}
