# Project TODOs

This file tracks repository-level TODOs that are not yet implemented or
validated. Keep short local TODO comments near the relevant code, but record the
project-level owner, context, and acceptance criteria here.

## Open

### Add Exadata Exascale physical storage metrics

- Area: common verification
- References:
  - `common/verify-storage.sql`
  - `common/verify-exascale-storage.sh`
  - `lab-01-pdb-thin-clones/03-create-clones.sql`
  - `lab-01-pdb-thin-clones/05-verify-independence.sql`
  - `lab-01-pdb-thin-clones/08-refresh-clone.sql`
  - `lab-01-pdb-thin-clones/README.md`
- Context: current storage verification reports logical datafile allocation from
  `CDB_DATA_FILES`. It does not yet report Exadata Exascale physical sharing,
  sparse allocation, clone dependency metadata, or changed-block usage.
- Validated interfaces (Oracle AI Database 26ai 23.26.2):
  - `DBA_PDB_SNAPSHOTS.FULL_SNAPSHOT_PATH` identifies the Exascale snapshot
    directory; `CDB_DATA_FILES.FILE_NAME` identifies each PDB datafile.
  - `escli lssnapshots <datafile> --tree` reports the file/snapshot dependency
    tree for a snapshot-copy clone.
  - `escli ls <datafile> --attributes name,size,spaceUsed` reports logical
    file size and physical vault space used. Capture `spaceUsed` before and
    after clone-local writes; its delta is changed-block growth.
- Done when: the on-premises collector maps those validated values to the
  shared report for all lab datafiles and demonstrates physical savings and
  before/after changed-block growth for snapshot-copy clones. ESCLI is not
  available on Exadata Cloud.
