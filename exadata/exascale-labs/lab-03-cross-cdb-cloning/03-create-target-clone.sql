-- Create the Lab 03 cross-CDB thin clone from the source snapshot.
--
-- Run from CDB$ROOT in the target CDB after 01-create-source-database-link.sql.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
    l_pdb_count      NUMBER;
    l_link_count     NUMBER;
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

    SELECT COUNT(*)
    INTO   l_pdb_count
    FROM   dba_pdbs
    WHERE  pdb_name = UPPER('&&LAB03_TARGET_PDB');

    IF l_pdb_count > 0 THEN
        raise_application_error(
            -20039,
            'Target PDB &&LAB03_TARGET_PDB already exists. Run 08-cleanup-snapshot-target.sql before recreating it.'
        );
    END IF;

    SELECT COUNT(*)
    INTO   l_link_count
    FROM   user_db_links
    WHERE  db_link = UPPER('&&LAB03_SOURCE_DB_LINK');

    IF l_link_count = 0 THEN
        raise_application_error(
            -20040,
            'Database link &&LAB03_SOURCE_DB_LINK does not exist. Run 01-create-source-database-link.sql first.'
        );
    END IF;
END;
/

PROMPT Checking GLOBAL_NAMES for this session
@@../common/set-global-names-false.sql

PROMPT Creating thin clone &&LAB03_TARGET_PDB from &&MAIN_PDB@&&LAB03_SOURCE_DB_LINK
PROMPT SQL/DDL:
PROMPT   CREATE PLUGGABLE DATABASE &&LAB03_TARGET_PDB
PROMPT     FROM &&MAIN_PDB@&&LAB03_SOURCE_DB_LINK
PROMPT     USING SNAPSHOT &&LAB03_SNAPSHOT_NAME
PROMPT     SNAPSHOT COPY;

CREATE PLUGGABLE DATABASE &&LAB03_TARGET_PDB
    FROM &&MAIN_PDB@&&LAB03_SOURCE_DB_LINK
    USING SNAPSHOT &&LAB03_SNAPSHOT_NAME
    SNAPSHOT COPY;

PROMPT PASS: Created &&LAB03_TARGET_PDB in MOUNTED mode.
PROMPT Set the target CDB Clusterware environment before starting the PDB and service:

SELECT 'export CDB_UNIQUE_NAME=' || value AS clusterware_environment
FROM   v$parameter
WHERE  name = 'db_unique_name';

SELECT 'export RAC_SERVICE_PREFERRED=' ||
       LISTAGG(instance_name, ',') WITHIN GROUP (ORDER BY inst_id) AS clusterware_environment
FROM   gv$instance;

PROMPT export PDB_CLUSTERWARE_PDB_CONFIG=./config.sql
PROMPT Then run:
PROMPT   ../common/manage-pdb-clusterware.sh ensure-and-start &&LAB03_TARGET_PDB
PROMPT Then run @04-verify-target-clone.sql from CDB$ROOT in the target CDB.
