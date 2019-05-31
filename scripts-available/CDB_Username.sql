-- Returns the cartodb username of the current PostgreSQL session
CREATE OR REPLACE FUNCTION @extschema@.CDB_Username()
RETURNS text
AS $$
  SELECT @extschema@.CDB_Conf_GetConf(CONCAT('api_keys_', session_user))->>'username';
$$ LANGUAGE SQL STABLE PARALLEL SAFE SECURITY DEFINER;
