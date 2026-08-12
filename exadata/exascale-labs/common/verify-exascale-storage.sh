#!/usr/bin/env bash
#
# Report validated Exadata Exascale physical storage metrics for lab PDBs.
#
# This script is intentionally an optional, on-premises companion to
# verify-storage.sql. On Exadata database VMs it uses /usr/bin/escli directly.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  verify-exascale-storage.sh [--pdb PDB]...
  verify-exascale-storage.sh --collector /path/to/validated-collector [--pdb PDB]...
  verify-exascale-storage.sh --metrics-file /path/to/captured-metrics.tsv

By default, run on an on-premises Exadata database VM as the Oracle software
owner. The script uses /usr/bin/escli and SQLcl/sqlplus from PATH. Set
ESCLI_WALLET when the default wallet is not available.

--collector is an optional override. It receives each requested PDB as
"--pdb PDB" and writes tab-separated metrics with this header:

pdb_name\tsnapshot_name\tredundancy\tlogical_bytes\tphysical_bytes\tcow_bytes\tchanged_bytes\tcaptured_at

`physical_bytes` includes redundancy. `cow_bytes` and `changed_bytes` are the
redundancy-normalized copy-on-write footprint. The collector must map only
validated ESCLI fields to those definitions.

Use --metrics-file only to replay a captured result during review or testing.
ESCLI is not available on Exadata Cloud.
EOF
}

collector=
metrics_file=
expected_header=$'pdb_name\tsnapshot_name\tredundancy\tlogical_bytes\tphysical_bytes\tcow_bytes\tchanged_bytes\tcaptured_at'
declare -a pdb_args=()

while (($# > 0)); do
    case "$1" in
        --collector)
            (($# >= 2)) || { echo "ERROR: --collector requires a path." >&2; exit 2; }
            collector=$2
            shift 2
            ;;
        --metrics-file)
            (($# >= 2)) || { echo "ERROR: --metrics-file requires a path." >&2; exit 2; }
            metrics_file=$2
            shift 2
            ;;
        --pdb)
            (($# >= 2)) || { echo "ERROR: --pdb requires a PDB name." >&2; exit 2; }
            pdb_args+=(--pdb "$2")
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -n "$collector" && -n "$metrics_file" ]]; then
    echo "ERROR: Specify either --collector or --metrics-file, not both." >&2
    exit 2
fi

if [[ -n "$collector" ]]; then
    if [[ ! -x "$collector" ]]; then
        echo "ERROR: Collector is not executable: $collector" >&2
        exit 2
    fi
    metrics_file=$(mktemp "${TMPDIR:-/tmp}/exascale-storage-metrics.XXXXXX")
    trap 'rm -f "$metrics_file"' EXIT
    "$collector" "${pdb_args[@]}" > "$metrics_file"
elif [[ -n "$metrics_file" && ! -r "$metrics_file" ]]; then
    echo "ERROR: Metrics file is not readable: $metrics_file" >&2
    exit 2
fi

if [[ -z "$collector" && -z "$metrics_file" ]]; then
    escli_bin=${ESCLI_BIN:-/usr/bin/escli}
    sql_bin=${SQL_BIN:-sql}
    wallet=${ESCLI_WALLET:-/etc/oracle/cell/network-config/eswallet}
    if [[ ! -x "$escli_bin" ]]; then
        echo "SKIP: $escli_bin is unavailable; ESCLI is on-premises Exadata only." >&2
        exit 0
    fi
    if ! command -v "$sql_bin" >/dev/null 2>&1; then
        echo "ERROR: SQLcl or SQL*Plus is required in PATH." >&2
        exit 2
    fi
    pdb_filter=""
    for pdb_arg in "${pdb_args[@]}"; do
        [[ $pdb_arg == --pdb ]] && continue
        [[ $pdb_arg =~ ^[A-Za-z0-9_\$#]+$ ]] || { echo "ERROR: Invalid PDB name: $pdb_arg" >&2; exit 2; }
        pdb_filter+="'${pdb_arg^^}',"
    done
    if [[ -n "$pdb_filter" ]]; then
        pdb_filter="AND p.pdb_name IN (${pdb_filter%,})"
    fi
    metrics_file=$(mktemp "${TMPDIR:-/tmp}/exascale-storage-metrics.XXXXXX")
    trap 'rm -f "$metrics_file"' EXIT
    printf '%s\n' "$expected_header" > "$metrics_file"
    if ! sql_rows=$(printf '%s\n' "whenever sqlerror exit sql.sqlcode" "set heading off feedback off pagesize 0 linesize 1000 trimspool on" "select p.pdb_name || chr(9) || d.file_name || chr(9) || d.bytes from cdb_data_files d join cdb_pdbs p on p.con_id=d.con_id where p.pdb_name not in ('CDB\$ROOT','PDB\$SEED') $pdb_filter order by p.pdb_name,d.file_id;" "exit sql.sqlcode" | "$sql_bin" -s / as sysdba | sed '/^[[:space:]]*$/d'); then
        printf '%s\n' "$sql_rows" >&2
        echo "ERROR: Could not query CDB datafiles. Confirm ORACLE_HOME, ORACLE_SID, and the SYSDBA connection." >&2
        exit 1
    fi
    while IFS=$'\t' read -r pdb_name file_name logical_bytes; do
        logical_bytes=${logical_bytes//[[:space:]]/}
        if [[ -z "$pdb_name" || -z "$file_name" || ! "$logical_bytes" =~ ^[0-9]+$ ]]; then
            echo "ERROR: SQL did not return a valid PDB datafile row." >&2
            exit 1
        fi
        escli_output=$("$escli_bin" --wallet "$wallet" "ls $file_name --attributes name,size,spaceUsed,redundancy")
        read -r used redundancy < <(awk 'NR == 2 { print $(NF - 1), $NF }' <<< "$escli_output")
        [[ $used =~ ^[0-9.]+[KMGTP]$ ]] || { echo "ERROR: Could not read spaceUsed for $file_name" >&2; exit 1; }
        case "${redundancy,,}" in high) redundancy_factor=3 ;; normal) redundancy_factor=2 ;; none) redundancy_factor=1 ;; *) echo "ERROR: Unknown redundancy for $file_name: $redundancy" >&2; exit 1 ;; esac
        used_bytes=$(awk -v value="$used" 'BEGIN { unit=substr(value,length(value)); n=substr(value,1,length(value)-1); scale=(unit=="K"?1024:unit=="M"?1048576:unit=="G"?1073741824:unit=="T"?1099511627776:unit=="P"?1125899906842624:1); printf "%.0f", n*scale }')
        cow_bytes=$(( used_bytes / redundancy_factor ))
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pdb_name" "-" "${redundancy,,}" "$logical_bytes" "$used_bytes" "$cow_bytes" "$cow_bytes" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$metrics_file"
    done <<< "$sql_rows"
fi

IFS= read -r actual_header < "$metrics_file" || {
    echo "ERROR: Metrics output is empty." >&2
    exit 1
}

if [[ "$actual_header" != "$expected_header" ]]; then
    echo "ERROR: Metrics header does not match the documented collector contract." >&2
    exit 1
fi

awk -F '\t' '
BEGIN {
    printf "%-18s %-24s %-18s %13s %13s %13s %13s %s\n", \
           "PDB", "SNAPSHOT", "REDUNDANCY", "LOGICAL_GB", "PHYSICAL_GB", \
           "COW_GB", "CHANGED_GB", "CAPTURED_AT"
}
NR == 1 { next }
NF != 8 {
    printf "ERROR: Invalid metrics row %d. Expected eight tab-separated columns.\n", NR > "/dev/stderr"
    invalid = 1
    next
}
$4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ || $7 !~ /^[0-9]+$/ {
    printf "ERROR: Non-byte metric in row %d.\n", NR > "/dev/stderr"
    invalid = 1
    next
}
{
    printf "%-18s %-24s %-18s %13.2f %13.2f %13.2f %13.2f %s\n", \
           $1, $2, $3, $4 / 1073741824, $5 / 1073741824, \
           $6 / 1073741824, $7 / 1073741824, $8
}
END { exit invalid }
' "$metrics_file"
