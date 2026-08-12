-- Reset Lab 03 objects in the target CDB.
--
-- Run 99-reset-target-lab.sh for the supported non-interactive workflow. The
-- wrapper removes Clusterware PDB resources and services before this SQL runs.
-- Run from CDB$ROOT in the configured target CDB.

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

PROMPT Removing Lab 03 target-CDB objects.

@@07-cleanup-direct-target.sql
@@08-cleanup-snapshot-target.sql

PROMPT Lab 03 target reset complete.
