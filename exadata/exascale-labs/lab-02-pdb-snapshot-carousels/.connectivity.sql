-- Verify that the selected Oracle client reaches the intended CDB.

WHENEVER OSERROR EXIT 9
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET VERIFY OFF

SELECT 'Connected to CDB=' || name || ', container=' ||
       sys_context('USERENV', 'CON_NAME') || ', version=' || version_full
FROM   v$instance CROSS JOIN v$database;

EXIT SQL.SQLCODE
