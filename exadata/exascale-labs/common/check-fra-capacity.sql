-- Report fast recovery area capacity for the current CDB.
--
-- A full FRA can cause remote PDB cloning to fail with ORA-19809.

PROMPT Checking fast recovery area capacity

DECLARE
    l_space_limit       NUMBER;
    l_space_used        NUMBER;
    l_space_reclaimable NUMBER;
    l_free_space        NUMBER;
BEGIN
    SELECT NVL(MAX(space_limit), 0),
           NVL(MAX(space_used), 0),
           NVL(MAX(space_reclaimable), 0)
    INTO   l_space_limit,
           l_space_used,
           l_space_reclaimable
    FROM   v$recovery_file_dest;

    IF l_space_limit = 0 THEN
        dbms_output.put_line(
            'INFO: No fast recovery area is configured for this CDB.'
        );
    ELSE
        l_free_space := l_space_limit - l_space_used;

        dbms_output.put_line(
            'INFO: FRA limit=' || ROUND(l_space_limit / 1024 / 1024 / 1024, 2) ||
            ' GB, used=' || ROUND(l_space_used / 1024 / 1024 / 1024, 2) ||
            ' GB, free=' || ROUND(l_free_space / 1024 / 1024 / 1024, 2) ||
            ' GB, reclaimable=' ||
            ROUND(l_space_reclaimable / 1024 / 1024 / 1024, 2) || ' GB.'
        );

        IF l_free_space <= 0 THEN
            dbms_output.put_line(
                'WARNING: The FRA is full. Reclaim space with RMAN or increase ' ||
                'DB_RECOVERY_FILE_DEST_SIZE before remote PDB cloning.'
            );
        END IF;
    END IF;
END;
/

SELECT file_type,
       percent_space_used,
       percent_space_reclaimable,
       number_of_files
FROM   v$recovery_area_usage
WHERE  percent_space_used > 0
OR     percent_space_reclaimable > 0
ORDER  BY percent_space_used DESC,
          file_type;
