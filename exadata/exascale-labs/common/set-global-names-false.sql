-- Ensure the current session does not enforce database-link global names.
--
-- The lab-series prerequisite is GLOBAL_NAMES=FALSE at the database level.
-- This session-level setting protects individual Lab 03 SQL sessions when the
-- database-level parameter has not yet been updated.

DECLARE
    l_global_names VARCHAR2(5);
BEGIN
    SELECT UPPER(value)
    INTO   l_global_names
    FROM   v$parameter
    WHERE  name = 'global_names';

    IF l_global_names = 'TRUE' THEN
        dbms_output.put_line(
            'WARNING: GLOBAL_NAMES is TRUE. Setting it to FALSE for this session.'
        );
        EXECUTE IMMEDIATE 'ALTER SESSION SET GLOBAL_NAMES = FALSE';

        SELECT UPPER(value)
        INTO   l_global_names
        FROM   v$parameter
        WHERE  name = 'global_names';
    END IF;

    IF l_global_names <> 'FALSE' THEN
        raise_application_error(
            -20038,
            'GLOBAL_NAMES must be FALSE for the current session. Current value is ' ||
            l_global_names
        );
    END IF;

    dbms_output.put_line('PASS: GLOBAL_NAMES is FALSE for this session.');
END;
/
