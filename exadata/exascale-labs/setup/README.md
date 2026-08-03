# Setup Scripts

This directory creates and validates the common starting environment used by the Exadata Exascale labs.

Run these scripts from `CDB$ROOT` in the source CDB as a user with privileges
to create, open, close, and drop pluggable databases. The lab series also
requires a separate target CDB for Lab 03; setup does not create objects there.

## Files

| File | Purpose |
|------|---------|
| `00-setup.sh` | Creates `SALES_MAIN`, starts its Clusterware PDB resource and service, seeds Lab 03 verification data, and verifies availability |
| `00-create-sales-main.sql` | Creates the `SALES_MAIN` PDB SQL object; `00-setup.sh` manages its Clusterware availability |
| `00-setup-driver.sql` | Calls `00-create-sales-main.sql` and exits with its SQL status for `00-setup.sh` |
| `01-create-lab-verification-data.sql` | Creates deterministic Lab 03 clone-verification rows in `SALES_MAIN` after it is open read-write |
| `01-mask-data.sql` | Placeholder for site-specific data masking after refresh |
| `02-verify-environment.sql` | Runs shared verification checks from `common/` |
| `03-verify-exadata-software.sh` | Verifies Exadata System Software versions across database and storage servers using `dcli` |
| `99-reset-lab.sh` | Stops and removes Clusterware PDB resources and services, then runs the SQL reset non-interactively |
| `99-reset-lab.sql` | SQL DDL used by `99-reset-lab.sh` to remove workshop PDBs and return the CDB to a clean lab state |

## Usage

Create the starting PDB and configure its Clusterware availability:

```bash
export CDB_UNIQUE_NAME=MYCDB
export RAC_SERVICE_PREFERRED=mycdb1,mycdb2
./00-setup.sh
```

`00-setup.sh` securely prompts for the PDB administrator password, then starts
and verifies the configured PDB service. It also creates the Lab-owned
`SALES_ADMIN.LAB03_CLONE_SEED` table, which Lab 03 queries in `CI_PIPELINE` to
confirm the cloned contents. To inspect or run the SQL DDL alone:

```sql
@00-create-sales-main.sql
```

When running the SQL DDL alone, set the target CDB `DB_UNIQUE_NAME` for the
shell session, then create and start the Clusterware PDB resource and service:

```bash
export CDB_UNIQUE_NAME=MYCDB
export RAC_SERVICE_PREFERRED=mycdb1,mycdb2
../common/manage-pdb-clusterware.sh ensure-and-start SALES_MAIN
../common/manage-pdb-clusterware.sh verify SALES_MAIN
```

Then seed the Lab 03 verification data from `CDB$ROOT`:

```sql
@01-create-lab-verification-data.sql
```

The helper falls back to `CDB_UNIQUE_NAME` in `../common/config.sql` when the
environment variable is not set.

Apply site-specific masking after loading or refreshing data into `SALES_MAIN`:

```sql
@01-mask-data.sql
```

Verify the environment:

```sql
@02-verify-environment.sql
```

Verify Exadata System Software from a central Exadata database server:

```bash
./03-verify-exadata-software.sh \
  --dbs-nodes dbnode01,dbnode02 \
  --cells-nodes cell01,cell02,cell03
```

The script uses `dcli` to run `sudo -n dbmcli` on database servers and `cellcli` on storage servers. By default it connects to database servers as `oracle`; that user must have passwordless sudo access to `dbmcli`. Supply either comma-separated node lists or existing `dcli` group files. No group-file location is assumed by default.

Use command-line options or environment variables when group files, users, or command paths differ:

```bash
DBS_GROUP=/path/to/dbs_group \
CELLS_GROUP=/path/to/cell_group \
DBS_USER=oracle \
CELLS_USER=celladmin \
./03-verify-exadata-software.sh
```

Reset the lab non-interactively:

```bash
./99-reset-lab.sh
```

## Notes

- The labs assume Oracle RAC, Oracle Managed Files, and Exadata Exascale.
- The lab series requires separately named source and target CDBs. These setup
  scripts configure only the source CDB.
- Exadata System Software must be 24.1 or later on database and storage servers.
- `99-reset-lab.sh` drops the workshop PDBs and includes datafiles. It first stops and removes their Clusterware PDB resources and services.
- `99-reset-lab.sql` remains available for inspection or controlled manual use. Before invoking it directly, run `../common/manage-pdb-clusterware.sh stop-and-remove DEV_JORDAN,DEV_SARAH,DEV_ALEX,QA,SALES_MAIN`.
- Lab 03 target-CDB objects are reset separately by `lab-03-cross-cdb-cloning/99-reset-target-lab.sh`.
- `01-mask-data.sql` intentionally contains no customer-specific masking rules.
- Add masking logic only after reviewing local data classification, privacy, and compliance requirements.
