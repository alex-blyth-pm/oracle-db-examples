-- Create the dedicated Lab 03 source snapshot.
--
-- Run from CDB$ROOT in the source CDB after 00-preflight-source.sql.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT Creating source snapshot &&LAB03_SNAPSHOT_NAME from &&MAIN_PDB

DECLARE
    l_container_name  VARCHAR2(128);
    l_cdb_name        VARCHAR2(128);
    l_snapshot_count NUMBER;
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

    SELECT COUNT(*)
    INTO   l_snapshot_count
    FROM   dba_pdb_snapshots
    WHERE  con_name = UPPER('&&MAIN_PDB')
    AND    snapshot_name = UPPER('&&LAB03_SNAPSHOT_NAME');

    IF l_snapshot_count > 0 THEN
        raise_application_error(
            -20034,
            'Snapshot &&LAB03_SNAPSHOT_NAME already exists. Run 09-cleanup-source.sql first.'
        );
    END IF;
END;
/

ALTER SESSION SET CONTAINER = &&MAIN_PDB;

PROMPT SQL/DDL:
PROMPT   ALTER PLUGGABLE DATABASE SNAPSHOT &&LAB03_SNAPSHOT_NAME;

ALTER PLUGGABLE DATABASE SNAPSHOT &&LAB03_SNAPSHOT_NAME;

ALTER SESSION SET CONTAINER = &&ROOT_CONTAINER;

@@../common/verify-snapshots.sql

PROMPT Source snapshot created
