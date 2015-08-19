----------------------------------
-- CONF MANAGEMENT FUNCTIONS
--
-- Meant to be used by superadmin user.
-- Functions needing reading configuration should use SECURITY DEFINER.
----------------------------------

-- This will trigger NOTICE if CDB_CONF already exists
DO LANGUAGE 'plpgsql' $$
BEGIN
    CREATE TABLE IF NOT EXISTS cartodb.CDB_CONF ( PARAM TEXT PRIMARY KEY, CONF TEXT NOT NULL );
END
$$;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_SetConf(param text, conf text)
    RETURNS void AS $$
BEGIN
    PERFORM cartodb.CDB_Conf_RemoveConf(param);
    EXECUTE 'INSERT INTO cartodb.CDB_CONF (PARAM, CONF) VALUES ($1, $2);' USING param, conf;
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_RemoveConf(param text)
    RETURNS void AS $$
BEGIN
    PERFORM cartodb._CDB_Conf_Cache('remove', param);
    EXECUTE 'DELETE FROM cartodb.CDB_CONF WHERE PARAM = $1;' USING param;
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_GetConf(param text)
    RETURNS TEXT AS $$
DECLARE
    conf TEXT;
BEGIN
    EXECUTE 'select cartodb._CDB_Conf_Cache(''get'', $1) as conf;' INTO conf USING param;
    RETURN conf;
END
$$ LANGUAGE PLPGSQL STABLE;

-- Single cache function allowing SD private dict usage
CREATE OR REPLACE
FUNCTION cartodb._CDB_Conf_Cache(operation text, param text)
    RETURNS TEXT AS
$$
    if 'conf' not in SD:
      SD['conf'] = dict()

    if operation == 'remove':
      SD['conf'][param] = None
    elif operation == 'get':
      if param not in SD['conf']:
        value = None
        response = plpy.execute("SELECT conf FROM cartodb.CDB_CONF WHERE PARAM = '%s'" % param);
        if len(response) > 0:
          value = response[0]['conf']
        SD['conf'][param] = value
      return SD['conf'][param]
    else:
      raise Exception('Unknown operation: %s' % operation)
$$ LANGUAGE 'plpythonu' VOLATILE;
