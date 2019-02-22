-- Returns the cartodb username of the current PostgreSQL session
CREATE OR REPLACE FUNCTION CDB_Username()
RETURNS text
AS $$
  SELECT CDB_Conf_GetConf(CONCAT('api_keys_', session_user))->>'username';
$$ LANGUAGE SQL STABLE PARALLEL SAFE SECURITY DEFINER;
