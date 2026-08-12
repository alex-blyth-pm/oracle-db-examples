-- Idempotently remove the dedicated Lab 03 source-side snapshot after verification.
--
-- Run from CDB$ROOT in the source CDB.

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

    IF UPPER(l_cdb_name) <> UPPER('&&LAB03_SOURCE_CDB') THEN
        raise_application_error(
            -20031,
            'Expected source CDB &&LAB03_SOURCE_CDB. Connected to ' || l_cdb_name
        );
    END IF;
END;
/

DEFINE DROP_SNAPSHOT_NAME = &&LAB03_SNAPSHOT_NAME
COLUMN snapshot_action NEW_VALUE SNAPSHOT_ACTION NOPRINT

SELECT CASE
           WHEN COUNT(*) > 0 THEN 'drop-snapshot.sql'
           ELSE 'skip-snapshot.sql'
       END AS snapshot_action
FROM   dba_pdb_snapshots
WHERE  con_name = UPPER('&&MAIN_PDB')
AND    snapshot_name = UPPER('&&LAB03_SNAPSHOT_NAME');

@@../common/&&SNAPSHOT_ACTION

@@../common/verify-snapshots.sql
