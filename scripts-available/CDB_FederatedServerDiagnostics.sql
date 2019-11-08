--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Server_Version_PG(server_internal name)
RETURNS text
AS $$
BEGIN
    -- TODO Implement
    RETURN '14.0';
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Server_Diagnostics_PG(server_internal name)
RETURNS jsonb
AS $$
DECLARE
    remote_server_version text := @extschema@.__CDB_FS_Server_Version_PG(server_internal);
BEGIN
    RETURN jsonb_build_object('server_version', remote_server_version);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;



--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--
-- TODO: function documentation
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Diagnostics(server TEXT)
RETURNS jsonb
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name => server, check_existence => true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN @extschema@.__CDB_FS_Server_Diagnostics_PG(server_internal);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
