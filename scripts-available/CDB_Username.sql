-- Function returning the username of the provided user
CREATE OR REPLACE FUNCTION _CDB_Username(pg_user TEXT)
RETURNS text
AS $$
  SELECT CDB_Conf_GetConf(CONCAT('api_keys_', pg_user))->>'username';
$$ LANGUAGE SQL STRICT IMMUTABLE PARALLEL SAFE SECURITY DEFINER;

-- Function returning the username of the current user
CREATE OR REPLACE FUNCTION CDB_Username()
RETURNS text
AS $$
  SELECT _CDB_Username(current_user);
$$ LANGUAGE SQL STABLE PARALLEL SAFE;
