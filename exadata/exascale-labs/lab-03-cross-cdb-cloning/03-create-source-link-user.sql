-- Create or update the source-CDB common user used by the Lab 03 database link.
--
-- Run from CDB$ROOT in the source CDB after 01-preflight-source.sql.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
    l_user_count     NUMBER;
    l_user_common    VARCHAR2(3);
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
    INTO   l_user_count
    FROM   dba_users
    WHERE  username = UPPER('&&LAB03_SOURCE_LINK_USER');

    IF l_user_count = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE USER &&LAB03_SOURCE_LINK_USER IDENTIFIED BY "&&LAB03_SOURCE_LINK_PASSWORD" CONTAINER = ALL';
        dbms_output.put_line('PASS: Created common user &&LAB03_SOURCE_LINK_USER.');
    ELSE
        SELECT common
        INTO   l_user_common
        FROM   dba_users
        WHERE  username = UPPER('&&LAB03_SOURCE_LINK_USER');

        IF l_user_common <> 'YES' THEN
            raise_application_error(
                -20037,
                'LAB03_SOURCE_LINK_USER must identify a common user.'
            );
        END IF;

        EXECUTE IMMEDIATE
            'ALTER USER &&LAB03_SOURCE_LINK_USER IDENTIFIED BY "&&LAB03_SOURCE_LINK_PASSWORD" CONTAINER = ALL';
        dbms_output.put_line('PASS: Updated password for common user &&LAB03_SOURCE_LINK_USER.');
    END IF;
END;
/

GRANT CREATE SESSION TO &&LAB03_SOURCE_LINK_USER CONTAINER = ALL;
GRANT CREATE PLUGGABLE DATABASE TO &&LAB03_SOURCE_LINK_USER CONTAINER = ALL;
GRANT SELECT ON V_$DATABASE TO &&LAB03_SOURCE_LINK_USER CONTAINER = ALL;

PROMPT Verifying source database-link user privileges

SELECT username,
       common,
       account_status
FROM   dba_users
WHERE  username = UPPER('&&LAB03_SOURCE_LINK_USER');

SELECT privilege
FROM   dba_sys_privs
WHERE  grantee = UPPER('&&LAB03_SOURCE_LINK_USER')
AND    privilege IN ('CREATE PLUGGABLE DATABASE', 'CREATE SESSION')
ORDER  BY privilege;

SELECT owner,
       table_name,
       privilege
FROM   dba_tab_privs
WHERE  grantee = UPPER('&&LAB03_SOURCE_LINK_USER')
AND    owner = 'SYS'
AND    table_name = 'V_$DATABASE'
AND    privilege = 'SELECT';

PROMPT PASS: Source database-link user &&LAB03_SOURCE_LINK_USER is ready.
