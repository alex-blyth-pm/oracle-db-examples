#!/usr/bin/env bash
#
# Back up one CDB with RMAN and remove archived redo logs that have a disk
# backup. Run as the Oracle software owner with ORACLE_SID set for the CDB.
#
set -euo pipefail

rman_bin=${RMAN_BIN:-}
sql_bin=${SQL_BIN:-}

if [ -z "${ORACLE_SID:-}" ]; then
    echo "ERROR: Set ORACLE_SID for the CDB to back up." >&2
    exit 1
fi

if [ -z "$rman_bin" ]; then
    if [ -n "${ORACLE_HOME:-}" ] && [ -x "$ORACLE_HOME/bin/rman" ]; then
        rman_bin="$ORACLE_HOME/bin/rman"
    elif command -v rman >/dev/null 2>&1; then
        rman_bin=$(command -v rman)
    else
        echo "ERROR: RMAN was not found. Set ORACLE_HOME or RMAN_BIN." >&2
        exit 1
    fi
fi

if [ ! -x "$rman_bin" ]; then
    echo "ERROR: RMAN_BIN is not executable: $rman_bin" >&2
    exit 1
fi

if [ -z "$sql_bin" ]; then
    if [ -n "${ORACLE_HOME:-}" ] && [ -x "$ORACLE_HOME/bin/sqlplus" ]; then
        sql_bin="$ORACLE_HOME/bin/sqlplus"
    elif command -v sqlplus >/dev/null 2>&1; then
        sql_bin=$(command -v sqlplus)
    elif command -v sql >/dev/null 2>&1; then
        sql_bin=$(command -v sql)
    else
        echo "ERROR: SQL*Plus or SQLcl was not found. Set ORACLE_HOME or SQL_BIN." >&2
        exit 1
    fi
fi

if [ ! -x "$sql_bin" ]; then
    echo "ERROR: SQL_BIN is not executable: $sql_bin" >&2
    exit 1
fi

echo "Backing up CDB instance: $ORACLE_SID"
echo "Backup destination: RMAN default disk location (the FRA when configured)."
echo "Archived redo logs are deleted only after RMAN confirms a disk backup."

"$rman_bin" target / <<RMAN
SHOW ARCHIVELOG DELETION POLICY;

RUN {
    SQL "ALTER SYSTEM ARCHIVE LOG CURRENT";
    BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
    BACKUP CURRENT CONTROLFILE;
    BACKUP SPFILE;
}

CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES TO DEVICE TYPE DISK;
DELETE NOPROMPT OBSOLETE;
LIST BACKUP SUMMARY;

EXIT;
RMAN

echo
echo "Fast recovery area usage after backup and cleanup"
printf '%s\n' \
    'SET LINESIZE 200' \
    'SET PAGESIZE 100' \
    'WHENEVER SQLERROR EXIT SQL.SQLCODE' \
    'SELECT name AS fra_destination,' \
    '       ROUND(space_limit / 1024 / 1024 / 1024, 2) AS fra_limit_gb,' \
    '       ROUND(space_used / 1024 / 1024 / 1024, 2) AS fra_used_gb,' \
    '       ROUND((space_limit - space_used) / 1024 / 1024 / 1024, 2) AS fra_free_gb,' \
    '       CASE WHEN space_limit = 0 THEN NULL' \
    '            ELSE ROUND((space_limit - space_used) / space_limit * 100, 2)' \
    '       END AS fra_free_pct,' \
    '       ROUND(space_reclaimable / 1024 / 1024 / 1024, 2) AS fra_reclaimable_gb' \
    'FROM   v$recovery_file_dest;' \
    '' \
    'SELECT file_type,' \
    '       percent_space_used,' \
    '       percent_space_reclaimable,' \
    '       number_of_files' \
    'FROM   v$recovery_area_usage' \
    'ORDER  BY percent_space_used DESC, file_type;' \
    'EXIT SQL.SQLCODE' |
    "$sql_bin" -s / as sysdba
