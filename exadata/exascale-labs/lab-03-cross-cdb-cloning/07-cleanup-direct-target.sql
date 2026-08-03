-- Idempotently remove the Lab 03 direct thin clone after verification.
--
-- Run from CDB$ROOT in the target CDB.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
    l_pdb_count      NUMBER;
    l_open_count     NUMBER;
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
    WHERE pdb_name = UPPER('&&LAB03_DIRECT_TARGET_PDB');

    IF l_pdb_count = 0 THEN
        dbms_output.put_line('Skipping &&LAB03_DIRECT_TARGET_PDB: not found');
    ELSE
        SELECT COUNT(*) INTO l_open_count FROM gv$pdbs
        WHERE name = UPPER('&&LAB03_DIRECT_TARGET_PDB') AND open_mode <> 'MOUNTED';

        IF l_open_count > 0 THEN
            EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ' ||
                dbms_assert.simple_sql_name(UPPER('&&LAB03_DIRECT_TARGET_PDB')) ||
                ' CLOSE IMMEDIATE INSTANCES = ALL';
        END IF;

        EXECUTE IMMEDIATE 'DROP PLUGGABLE DATABASE ' ||
            dbms_assert.simple_sql_name(UPPER('&&LAB03_DIRECT_TARGET_PDB')) ||
            ' INCLUDING DATAFILES';
    END IF;
END;
/
