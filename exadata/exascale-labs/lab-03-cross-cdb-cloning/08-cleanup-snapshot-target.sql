-- Idempotently remove the Lab 03 snapshot-based target clone after verification.
--
-- Run from CDB$ROOT in the target CDB.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
    l_count      NUMBER;
    l_open_count NUMBER;
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
    INTO   l_count
    FROM   dba_pdbs
    WHERE  pdb_name = UPPER('&&LAB03_TARGET_PDB');

    IF l_count = 0 THEN
        dbms_output.put_line('Skipping &&LAB03_TARGET_PDB: not found');
    ELSE
        SELECT COUNT(*)
        INTO   l_open_count
        FROM   gv$pdbs
        WHERE  name = UPPER('&&LAB03_TARGET_PDB')
        AND    open_mode <> 'MOUNTED';

        IF l_open_count > 0 THEN
            EXECUTE IMMEDIATE
                'ALTER PLUGGABLE DATABASE ' ||
                dbms_assert.simple_sql_name(UPPER('&&LAB03_TARGET_PDB')) ||
                ' CLOSE IMMEDIATE INSTANCES = ALL';
        END IF;

        EXECUTE IMMEDIATE
            'DROP PLUGGABLE DATABASE ' ||
            dbms_assert.simple_sql_name(UPPER('&&LAB03_TARGET_PDB')) ||
            ' INCLUDING DATAFILES';
    END IF;
END;
/

DECLARE
    l_link_count NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   l_link_count
    FROM   user_db_links
    WHERE  db_link = UPPER('&&LAB03_SOURCE_DB_LINK');

    IF l_link_count = 0 THEN
        dbms_output.put_line('Skipping database link &&LAB03_SOURCE_DB_LINK: not found');
    ELSE
        EXECUTE IMMEDIATE
            'DROP DATABASE LINK ' ||
            dbms_assert.simple_sql_name(UPPER('&&LAB03_SOURCE_DB_LINK'));
        dbms_output.put_line('Dropped database link &&LAB03_SOURCE_DB_LINK.');
    END IF;
END;
/

PROMPT Snapshot-based target clone and database link cleanup complete.
