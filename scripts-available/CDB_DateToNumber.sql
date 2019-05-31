-- Convert timestamp to double precision
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_DateToNumber(input timestamp)
RETURNS double precision AS $$
DECLARE output double precision;
BEGIN
    BEGIN
        SELECT extract (EPOCH FROM input) INTO output;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;
RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL UNSAFE;

-- Convert timestamp with time zone to double precision
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_DateToNumber(input timestamp with time zone)
RETURNS double precision AS $$
DECLARE output double precision;
BEGIN
    BEGIN
        SELECT extract (EPOCH FROM input) INTO output;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;
RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL UNSAFE;
