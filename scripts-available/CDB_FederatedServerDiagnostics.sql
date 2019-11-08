--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Diagnostics(server TEXT)
RETURNS json -- TODO decide if json or jsonb
AS $$
BEGIN
    RETURN '{}'::json;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
