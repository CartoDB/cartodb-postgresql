----------------------------------
-- CONF MANAGEMENT FUNCTIONS
--
-- Meant to be used by superadmin user.
-- Functions needing reading configuration should use SECURITY DEFINER.
----------------------------------

-- This will trigger NOTICE if @extschema@.CDB_CONF already exists
DO LANGUAGE 'plpgsql' $$
BEGIN
    CREATE TABLE IF NOT EXISTS @extschema@.CDB_CONF ( KEY TEXT PRIMARY KEY, VALUE JSON NOT NULL );
END
$$;

-- This can only be called from an SQL script executed by CREATE EXTENSION
DO LANGUAGE 'plpgsql' $$
BEGIN
    PERFORM pg_catalog.pg_extension_config_dump('@extschema@.CDB_CONF', '');
END
$$;

CREATE OR REPLACE
FUNCTION @extschema@.CDB_Conf_SetConf(key text, value JSON)
    RETURNS void AS $$
BEGIN
    PERFORM @extschema@.CDB_Conf_RemoveConf(key);
    EXECUTE 'INSERT INTO @extschema@.CDB_CONF (KEY, VALUE) VALUES ($1, $2);' USING key, value;
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE
FUNCTION @extschema@.CDB_Conf_RemoveConf(key text)
    RETURNS void AS $$
BEGIN
    EXECUTE 'DELETE FROM @extschema@.CDB_CONF WHERE KEY = $1;' USING key;
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE
FUNCTION @extschema@.CDB_Conf_GetConf(key text)
    RETURNS JSON AS $$
DECLARE
    value JSON;
BEGIN
    EXECUTE 'SELECT VALUE FROM @extschema@.CDB_CONF WHERE KEY = $1;' INTO value USING key;
    RETURN value;
END
$$ LANGUAGE PLPGSQL STABLE PARALLEL SAFE;
