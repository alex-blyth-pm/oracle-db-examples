-- Validate the Lab 03 target CDB and its source database link.
--
-- Run from CDB$ROOT in the target CDB.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT Checking Lab 03 target prerequisites

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

    IF UPPER(l_cdb_name) = UPPER('&&LAB03_SOURCE_CDB') THEN
        raise_application_error(
            -20033,
            'Source and target CDB names must be different.'
        );
    END IF;
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

PROMPT PASS: Target CDB is ready to create the source database link.
