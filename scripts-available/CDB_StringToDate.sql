-- Convert string to date
--
DROP FUNCTION IF EXISTS @extschema@.CDB_StringToDate(character varying);
CREATE OR REPLACE FUNCTION @extschema@.CDB_StringToDate(input character varying)
RETURNS TIMESTAMP AS $$
DECLARE output TIMESTAMP;
BEGIN
    BEGIN
        output := input::date;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
          SELECT to_timestamp(input::integer) INTO output;
        EXCEPTION WHEN OTHERS THEN
          RETURN NULL;
        END;
    END;
RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL UNSAFE;
