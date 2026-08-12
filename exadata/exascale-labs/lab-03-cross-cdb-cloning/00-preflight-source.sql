-- Validate the Lab 03 source CDB and source PDB.
--
-- Run from CDB$ROOT in the source CDB.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT Checking Lab 03 source prerequisites

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
    l_main_pdbs      NUMBER;
    l_seed_table_count NUMBER;
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
    INTO   l_main_pdbs
    FROM   dba_pdbs
    WHERE  pdb_name = UPPER('&&MAIN_PDB');

    IF l_main_pdbs = 0 THEN
        raise_application_error(
            -20010,
            '&&MAIN_PDB does not exist. Run setup before Lab 03.'
        );
    END IF;

    SELECT COUNT(*)
    INTO   l_seed_table_count
    FROM   cdb_tables t
           JOIN cdb_pdbs p
             ON p.con_id = t.con_id
    WHERE  p.pdb_name = UPPER('&&MAIN_PDB')
    AND    t.owner = UPPER('&&APP_NAME._ADMIN')
    AND    t.table_name = 'LAB03_CLONE_SEED';

    IF l_seed_table_count = 0 THEN
        raise_application_error(
            -20042,
            'Lab 03 verification data is missing. Run setup/01-create-lab-verification-data.sql after opening &&MAIN_PDB read-write.'
        );
    END IF;

    dbms_output.put_line('PASS: Source CDB and &&MAIN_PDB are ready.');
END;
/

PROMPT Checking GLOBAL_NAMES for this session
@@../common/set-global-names-false.sql

@@../common/check-fra-capacity.sql

PROMPT Checking database link capacity parameters across RAC instances

DECLARE
BEGIN
    FOR r_parameter IN (
        SELECT inst_id,
               name,
               value
        FROM   gv$system_parameter
        WHERE  name IN ('open_links', 'open_links_per_instance')
        ORDER BY inst_id, name
    ) LOOP
        IF TO_NUMBER(r_parameter.value) = 0 THEN
            dbms_output.put_line(
                'WARNING: Instance ' || r_parameter.inst_id || ' parameter ' ||
                UPPER(r_parameter.name) || ' is 0. Configure a non-zero value ' ||
                'before creating the cross-CDB database link.'
            );
        ELSE
            dbms_output.put_line(
                'PASS: Instance ' || r_parameter.inst_id || ' parameter ' ||
                UPPER(r_parameter.name) || ' is ' || r_parameter.value || '.'
            );
        END IF;
    END LOOP;
END;
/
