-- Display the connected CDB identity before a lab changes database objects.
-- Review this output and stop if it is not the intended CDB.

PROMPT
PROMPT Connected CDB identity: review before continuing

COLUMN database_name FORMAT A18
COLUMN db_unique_name FORMAT A30
COLUMN database_role FORMAT A18
COLUMN open_mode FORMAT A18
COLUMN current_container FORMAT A20
COLUMN current_user_name FORMAT A20

SELECT d.name AS database_name,
       p.value AS db_unique_name,
       d.dbid,
       d.database_role,
       d.open_mode,
       sys_context('USERENV', 'CON_NAME') AS current_container,
       sys_context('USERENV', 'CURRENT_USER') AS current_user_name
FROM   v$database d
       CROSS JOIN v$parameter p
WHERE  p.name = 'db_unique_name';

PROMPT RAC instances visible to this session

COLUMN instance_name FORMAT A18
COLUMN host_name FORMAT A36
COLUMN version_full FORMAT A18

SELECT inst_id,
       instance_name,
       host_name,
       version_full,
       status
FROM   gv$instance
ORDER  BY inst_id;

PROMPT If this is not the intended CDB, stop now and reconnect before continuing.
