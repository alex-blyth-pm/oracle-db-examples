-- Verify the Lab 03 direct thin clone after step 05.
--
-- Run from CDB$ROOT in the target CDB.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION SET CONTAINER = &&ROOT_CONTAINER;

PROMPT Direct clone provenance

SELECT pdb_name,
       operation,
       op_timestamp,
       cloned_from_pdb_name,
       clonetag
FROM   dba_pdb_history
WHERE  pdb_name = UPPER('&&LAB03_DIRECT_TARGET_PDB')
AND    operation = 'SNAP_CLONE'
ORDER  BY op_timestamp;

PROMPT Cloned Lab 03 verification data

ALTER SESSION SET CONTAINER = &&LAB03_DIRECT_TARGET_PDB;

SELECT marker_id,
       marker_name,
       source_created_at
FROM   &&APP_NAME._ADMIN.lab03_clone_seed
ORDER  BY marker_id;

ALTER SESSION SET CONTAINER = &&ROOT_CONTAINER;
