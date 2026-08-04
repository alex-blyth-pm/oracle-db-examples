-- Create the target-CDB private database link to the source CDB.
--
-- Run from CDB$ROOT in the target CDB after 02-preflight-target.sql.
-- The configured target-side user must have CREATE DATABASE LINK. The source
-- link user must have CREATE SESSION and the privileges validated by this lab.

@@../common/helpers.sql
@@../common/config.sql
@@config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_cdb_name       VARCHAR2(128);
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
    INTO   l_link_count
    FROM   user_db_links
    WHERE  db_link = UPPER('&&LAB03_SOURCE_DB_LINK');

    IF l_link_count > 0 THEN
        raise_application_error(
            -20036,
            'Database link &&LAB03_SOURCE_DB_LINK already exists. Verify it or run 11-cleanup-snapshot-target.sql before recreating it.'
        );
    END IF;
END;
/

PROMPT Checking GLOBAL_NAMES for this session
@@../common/set-global-names-false.sql

PROMPT Creating private database link &&LAB03_SOURCE_DB_LINK
PROMPT SQL/DDL:
PROMPT   CREATE DATABASE LINK &&LAB03_SOURCE_DB_LINK
PROMPT     CONNECT TO &&LAB03_SOURCE_LINK_USER
PROMPT     IDENTIFIED BY "<configured locally>"
PROMPT     USING '&&LAB03_SOURCE_CONNECT_IDENTIFIER';

CREATE DATABASE LINK &&LAB03_SOURCE_DB_LINK
    CONNECT TO &&LAB03_SOURCE_LINK_USER
    IDENTIFIED BY "&&LAB03_SOURCE_LINK_PASSWORD"
    USING '&&LAB03_SOURCE_CONNECT_IDENTIFIER';

SELECT 'PASS: Database link &&LAB03_SOURCE_DB_LINK reaches ' || name AS source_cdb
FROM   v$database@&&LAB03_SOURCE_DB_LINK;
