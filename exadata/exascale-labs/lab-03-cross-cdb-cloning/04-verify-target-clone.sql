-- Verify the Lab 03 target PDB after the cross-CDB clone step is validated.
--
-- Run from CDB$ROOT in the target CDB.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
BEGIN
    SELECT sys_context('USERENV', 'CON_NAME'), name
    INTO   l_container_name, l_cdb_name
    FROM   v$database;

    IF l_container_name <> '&&ROOT_CONTAINER' THEN
        raise_application_error(
            -20000,
            'Run this script from &&ROOT_CONTAINER. Current container is ' ||
            l_container_name
        );
    END IF;

    IF UPPER(l_cdb_name) <> UPPER('&&LAB03_TARGET_CDB') THEN
        raise_application_error(
            -20032,
            'Expected target CDB &&LAB03_TARGET_CDB. Connected to ' || l_cdb_name
        );
    END IF;
END;
/

PROMPT Lab 03 target clone state

SELECT p.inst_id,
       i.instance_name,
       p.con_id,
       p.name AS pdb_name,
       p.open_mode,
       p.restricted
FROM   gv$pdbs p
       JOIN gv$instance i
         ON i.inst_id = p.inst_id
WHERE  p.name = UPPER('&&LAB03_TARGET_PDB')
ORDER  BY p.inst_id;

SELECT CASE
           WHEN COUNT(*) > 0 THEN 'PASS: &&LAB03_TARGET_PDB exists in the target CDB.'
           ELSE 'NOT READY: &&LAB03_TARGET_PDB does not exist in the target CDB.'
       END AS target_clone_status
FROM   dba_pdbs
WHERE  pdb_name = UPPER('&&LAB03_TARGET_PDB');

@@../common/verify-pdb-services.sql
@@../common/verify-storage.sql

PROMPT Clone provenance for &&LAB03_TARGET_PDB

SELECT pdb_name,
       operation,
       op_timestamp,
       cloned_from_pdb_name,
       clonetag
FROM   dba_pdb_history
WHERE  pdb_name = UPPER('&&LAB03_TARGET_PDB')
AND    operation = 'SNAP_CLONE'
ORDER  BY op_timestamp;

PROMPT Cloned Lab 03 verification data

ALTER SESSION SET CONTAINER = &&LAB03_TARGET_PDB;

SELECT marker_id,
       marker_name,
       source_created_at
FROM   &&APP_NAME._ADMIN.lab03_clone_seed
ORDER  BY marker_id;

ALTER SESSION SET CONTAINER = &&ROOT_CONTAINER;
