-- Create deterministic Lab 03 verification data in SALES_MAIN.
--
-- Run from CDB$ROOT after Clusterware has opened SALES_MAIN read-write.

@@../common/helpers.sql
@@../common/config.sql

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    l_container_name VARCHAR2(128);
    l_pdb_open_count NUMBER;
BEGIN
    SELECT sys_context('USERENV', 'CON_NAME')
    INTO   l_container_name
    FROM   dual;

    IF l_container_name <> '&&ROOT_CONTAINER' THEN
        raise_application_error(
            -20000,
            'Run this script from &&ROOT_CONTAINER. Current container is ' ||
            l_container_name
        );
    END IF;

    SELECT COUNT(*)
    INTO   l_pdb_open_count
    FROM   gv$pdbs
    WHERE  name = UPPER('&&MAIN_PDB')
    AND    open_mode = 'READ WRITE';

    IF l_pdb_open_count = 0 THEN
        raise_application_error(
            -20041,
            '&&MAIN_PDB must be open read-write before creating Lab 03 verification data.'
        );
    END IF;
END;
/

ALTER SESSION SET CONTAINER = &&MAIN_PDB;

DECLARE
    l_tablespace_count NUMBER;
    l_table_count      NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   l_tablespace_count
    FROM   dba_tablespaces
    WHERE  tablespace_name = '&&APP_NAME._LAB_DATA';

    IF l_tablespace_count = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE TABLESPACE &&APP_NAME._LAB_DATA ' ||
            'DATAFILE SIZE 10M AUTOEXTEND ON NEXT 10M MAXSIZE 100M';
    END IF;

    EXECUTE IMMEDIATE
        'ALTER USER &&APP_NAME._ADMIN QUOTA UNLIMITED ON &&APP_NAME._LAB_DATA';

    SELECT COUNT(*)
    INTO   l_table_count
    FROM   dba_tables
    WHERE  owner = UPPER('&&APP_NAME._ADMIN')
    AND    table_name = 'LAB03_CLONE_SEED';

    IF l_table_count = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE TABLE &&APP_NAME._ADMIN.lab03_clone_seed (' ||
            'marker_id NUMBER PRIMARY KEY, ' ||
            'marker_name VARCHAR2(100) NOT NULL, ' ||
            'source_created_at TIMESTAMP NOT NULL) ' ||
            'TABLESPACE &&APP_NAME._LAB_DATA';
    END IF;

    EXECUTE IMMEDIATE 'DELETE FROM &&APP_NAME._ADMIN.lab03_clone_seed';
    EXECUTE IMMEDIATE
        'INSERT INTO &&APP_NAME._ADMIN.lab03_clone_seed ' ||
        '(marker_id, marker_name, source_created_at) ' ||
        'VALUES (1, ''SOURCE_BASELINE'', SYSTIMESTAMP)';
    EXECUTE IMMEDIATE
        'INSERT INTO &&APP_NAME._ADMIN.lab03_clone_seed ' ||
        '(marker_id, marker_name, source_created_at) ' ||
        'VALUES (2, ''CROSS_CDB_READY'', SYSTIMESTAMP)';
    EXECUTE IMMEDIATE
        'INSERT INTO &&APP_NAME._ADMIN.lab03_clone_seed ' ||
        '(marker_id, marker_name, source_created_at) ' ||
        'VALUES (3, ''EXASCALE_LAB'', SYSTIMESTAMP)';
    COMMIT;
END;
/

PROMPT Lab 03 source verification data in &&MAIN_PDB

SELECT marker_id,
       marker_name,
       source_created_at
FROM   &&APP_NAME._ADMIN.lab03_clone_seed
ORDER  BY marker_id;

ALTER SESSION SET CONTAINER = &&ROOT_CONTAINER;
