-- Returns the cartodb username of the current PostgreSQL session
CREATE OR REPLACE FUNCTION cartodb.CDB_Username()
RETURNS text
AS $$
  SELECT cartodb.CDB_Conf_GetConf(CONCAT('api_keys_', session_user))->>'username';
$$ LANGUAGE SQL STABLE PARALLEL SAFE SECURITY DEFINER;
