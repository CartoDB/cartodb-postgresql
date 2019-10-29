--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION @extschema@.__fdw_server_type(remote_server name)
RETURNS name
AS $$
    SELECT f.fdwname
        FROM pg_foreign_server s
        JOIN pg_foreign_data_wrapper f ON s.srvfdw = f.oid
        WHERE s.srvname = remote_server;
$$
LANGUAGE SQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@.__fdw_pg_list_foreign_schemas(remote_server name)
RETURNS TABLE(remote_schema name)
AS $$
BEGIN
    RAISE WARNING 'To be implemented';
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--
-- List remote schemas in a federated server that the current user has
-- access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Schemas(remote_server name)
RETURNS TABLE(remote_schema name)
AS $$
DECLARE
    server_type name;
BEGIN
    -- Check the type of the server, fail if not implemented
    server_type := @extschema@.__fdw_server_type(remote_server);
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY SELECT @extschema@.__fdw_pg_list_foreign_schemas(remote_server);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, remote_server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--
-- List remote tables in a federated server that the current user has
-- access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Tables(remote_server name, remote_schema name)
RETURNS TABLE(remote_table name, registered boolean)
AS $$
BEGIN
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
