----------------------------------
-- CONF MANAGEMENT FUNCTIONS
--
-- Meant to be used by superadmin user.
-- Functions needing reading configuration should use SECURITY DEFINER.
----------------------------------

-- This will trigger NOTICE if CDB_CONF already exists
DO LANGUAGE 'plpgsql' $$
BEGIN
    CREATE TABLE IF NOT EXISTS cartodb.CDB_CONF ( KEY TEXT PRIMARY KEY, VALUE JSON NOT NULL );
END
$$;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_SetConf(key TEXT, value JSON)
    RETURNS void AS $$
BEGIN
    PERFORM cartodb.CDB_Conf_RemoveConf(key);
    EXECUTE 'INSERT INTO cartodb.CDB_CONF (KEY, VALUE) VALUES ($1, $2);' USING key, value;
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_RemoveConf(key text)
    RETURNS void AS $$
BEGIN
    PERFORM cartodb._CDB_Conf_Cache('remove', key);
    EXECUTE 'DELETE FROM cartodb.CDB_CONF WHERE KEY = $1;' USING key;
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_GetConf(key text)
    RETURNS JSON AS $$
DECLARE
    value JSON;
BEGIN
    EXECUTE 'select cartodb._CDB_Conf_Cache(''get'', $1);' INTO value USING key;
    RETURN value;
END
$$ LANGUAGE PLPGSQL STABLE;

-- Single cache function allowing SD private dict usage
CREATE OR REPLACE
FUNCTION cartodb._CDB_Conf_Cache(operation text, key text)
    RETURNS JSON AS
$$
    if 'conf' not in SD:
      SD['conf'] = {}

    if operation == 'remove':
      if key in SD['conf']:
        del(SD['conf'][key])
    elif operation == 'get':
      if key not in SD['conf'] or SD['conf'][key] == None:
        value = None
        # Execute returns string, not json :(
        response = plpy.execute("SELECT value FROM cartodb.CDB_CONF WHERE KEY = '%s'" % key);
        if len(response) > 0:
          value = response[0]['value']
        SD['conf'][key] = value
      return SD['conf'][key]
    else:
      raise Exception('Unknown operation: %s' % operation)
$$ LANGUAGE 'plpythonu' VOLATILE;
