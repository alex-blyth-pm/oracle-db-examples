# Prerequisites

This document describes the environment and assumptions used throughout the Exadata Exascale Labs.

All labs in this repository have been developed and tested against the environment described below.

For an execution-oriented guide, including topology, parameter, capacity,
network, and Clusterware setup, see [Prepare Your Environment](environment-setup.md).

## Software Requirements

The labs assume the following software versions.

| Component | Requirement |
|----------|-------------|
| Database | Oracle AI Database 26ai |
| Platform | Exadata Exascale |
| Exadata System Software | **24.1 or later** |
| Architecture | Oracle Multitenant |
| Cluster | Oracle RAC (2 or more instances) |
| Client | SQLcl (recommended) or SQL*Plus |
| CDB thin cloning | gDBClone **5.0.2.2 or later** |

> **Note**
>
> Exadata snapshot and cloning capabilities require **Exadata System Software 24.1 or later**. These labs are developed and validated using the software versions listed in the **Tested Environment** section below.

gDBClone is not used by Labs 01-03, which use SQL PDB snapshot and cloning
operations. Lab 04 uses gDBClone to create a thin clone of a complete CDB.

## Environment Requirements

The following database and environment configuration is assumed throughout the labs.

- Oracle Managed Files (OMF) enabled
- `GLOBAL_NAMES` set to `FALSE` in both CDBs. The Lab 03 database link uses a
  lab-defined name rather than the source database global name.
- A regular RMAN backup schedule and archived-log deletion policy for CDBs
  retained longer than the lab execution window. This keeps recovery-area
  capacity available for normal database operations and remote cloning. The
  repository includes a simple [backup and FRA cleanup helper](../tools/backup-cdb-and-clean-fra.sh)
  for lab CDBs that uses RMAN's default disk location, normally the FRA.
- Two separately named CDBs already created and open:
  - A source CDB for the shared setup environment and Labs 01-02.
  - A target CDB reserved for the Lab 03 cross-CDB clone.
- SYSDBA privileges available
- Ability to create and drop PDBs
- Ability to create snapshots and thin clones
- Exadata Exascale storage configured and available
- Oracle Net connectivity from the database-server VMs in each CDB to the peer
  CDB's SCAN service. Configure a source-CDB SCAN connect identifier for the
  target-side Lab 03 database link.
- For the optional Exadata software check: passwordless SSH equivalence from a
  central database server to each database server as `oracle` and to each
  storage server as `celladmin` or `root`. The database-server account also
  needs passwordless `sudo` access to `dbmcli`.

## Starting Environment

The setup scripts supplied with this repository create the common starting point used by every lab.

Once setup is complete, the environment contains:

- `SALES_MAIN`
  - A development PDB refreshed from production.
  - Sensitive data has been masked to protect security and privacy.
  - Serves as the source for all subsequent snapshot and clone operations.

The setup scripts operate only in the source CDB. The target CDB remains free
of workshop PDBs until Lab 03 creates its cross-CDB clone.

## Repository Assumptions

### Oracle RAC

Examples assume Oracle RAC.

Where appropriate:

- `GV$` views are used instead of `V$`
- Oracle Clusterware PDB resources and PDB services manage routine PDB availability and placement
- Examples are written to operate correctly across all cluster instances

Set `CDB_UNIQUE_NAME` for the target CDB `DB_UNIQUE_NAME`. The account running
the shell runners and manual lifecycle commands must be able to run `srvctl`
for that CDB.

### Clusterware Shell Prerequisite

Before running a shell runner or `setup/99-reset-lab.sh`, set the target CDB
`DB_UNIQUE_NAME` in the environment. This avoids modifying the tracked shared
configuration for a local environment:

```bash
export CDB_UNIQUE_NAME=MYCDB
export RAC_SERVICE_PREFERRED=mycdb1,mycdb2
```

Find the value from `CDB$ROOT` when needed:

```sql
SELECT value
FROM   v$parameter
WHERE  name = 'db_unique_name';
```

Find the RAC instance names for `RAC_SERVICE_PREFERRED` with:

```bash
srvctl config database -db "$CDB_UNIQUE_NAME"
```

The shell helpers use this environment variable first. If it is not set, they
use the corresponding values from `common/config.sql`. The default
`RAC_PDB_PLACEMENT=AUTO` creates the PDB resource without `-cardinality` and
uses the preferred instance list for its service. This is required when the CDB
already has PDB resources created without `-cardinality`.

### Container Context

Unless otherwise stated, commands are executed from `CDB$ROOT`.

Scripts explicitly change container context where required.

### Database-Link Global Names

Set `GLOBAL_NAMES` to `FALSE` in `CDB$ROOT` of both CDBs before starting the
lab series. In an Oracle RAC environment, apply the setting to all instances:

```sql
ALTER SYSTEM SET GLOBAL_NAMES = FALSE SCOPE = BOTH SID = '*';
```

Verify the effective setting from `CDB$ROOT`:

```sql
SELECT inst_id,
       value
FROM   gv$parameter
WHERE  name = 'global_names'
ORDER BY inst_id;
```

Lab 03 also applies `ALTER SESSION SET GLOBAL_NAMES = FALSE` whenever a
preflight or target database-link creation session finds the effective value is
`TRUE`. This session-level safeguard does not replace the database-level
prerequisite.

### Oracle Managed Files

Examples assume Oracle Managed Files.

Storage locations are intentionally omitted unless they are relevant to the feature being demonstrated.

### Verification

Every significant operation is followed by a verification step.

## Before You Begin

Before starting the lab series, verify that:

- Oracle RAC is healthy.
- All database instances are running.
- The source CDB and target CDB are open and have different names.
- Every database-server VM can resolve and reach the peer CDB's SCAN service.
- Exadata System Software is 24.1 or later on database and storage servers.
- Exadata Exascale storage is available.
- `SALES_MAIN` exists, or execute the setup scripts.
- You are connected as a user with the required administrative privileges.
- For environments retained beyond the labs, confirm that RMAN backups and
  archived-log management run regularly and that the fast recovery area has
  sufficient capacity.

Labs 01 and 02 run only in the source CDB. Lab 03 additionally requires a
target-CDB database link to the source CDB and separate administrative
connections to both CDBs. Configure `LAB03_SOURCE_CONNECT_IDENTIFIER` with the
source CDB's SCAN service, not an individual RAC instance address.

## Exadata Software Version Check

Use the setup pre-flight script to verify Exadata System Software from a central Exadata database server:

```bash
cd setup
./03-verify-exadata-software.sh \
  --dbs-nodes dbnode01,dbnode02 \
  --cells-nodes cell01,cell02,cell03
```

The script uses `dcli` to run `sudo -n dbmcli` across database servers and `cellcli` across storage servers. It fails if any reported version is below 24.1. It requires passwordless SSH equivalence from the central database server: `oracle` for database servers and `celladmin` for storage servers by default. The database-server user must have passwordless sudo access to `dbmcli`; `sudo -n` reports missing access without prompting for a password. Use `--cells-user root` when storage-server SSH equivalence is configured for `root` instead.

Supply either comma-separated node lists or existing `dcli` group files. No group-file location is assumed by default. For example:

```bash
DBS_GROUP=/path/to/dbs_group \
CELLS_GROUP=/path/to/cell_group \
./03-verify-exadata-software.sh
```

## Tested Environment

The labs are developed and validated using the following software and memory
configuration.

| Component | Version |
|----------|---------|
| Oracle AI Database | 23.26.2 (Oracle AI Database 26ai Release Update) |
| Oracle Grid Infrastructure | 26.1.0.0.0 |
| Exadata System Software | 26.1.0.0.0 |
| Exadata Storage Server Software | 26.1.0.0.0 |
| SQLcl | 26.1 |
| gDBClone | 5.0.2.2 |
| Linux memory per database-server VM | 64 GB |
| Kernel huge pages per database-server VM | 12,800 |
| `SGA_TARGET` / `SGA_MAX_SIZE` | 4G / 4G |
| `PGA_AGGREGATE_TARGET` / `PGA_AGGREGATE_LIMIT` | 4G / 10G |
