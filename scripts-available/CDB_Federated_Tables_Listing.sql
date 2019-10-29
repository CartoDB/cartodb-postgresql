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
DECLARE
    fdw_objects_name name := @extschema@.__CDB_User_FDW_Object_Names(remote_server);
BEGIN
    -- Import schemata from the information schema
    --
    -- "The view schemata contains all schemas in the current database
    -- that the current user has access to (by way of being the owner
    -- or having some privilege)."
    -- See https://www.postgresql.org/docs/11/infoschema-schemata.html
    --
    -- "The information schema is defined in the SQL standard and can
    -- therefore be expected to be portable and remain stable"
    -- See https://www.postgresql.org/docs/11/information-schema.html

    -- Create local target schema if it does not exists
    IF NOT EXISTS (SELECT * FROM pg_namespace WHERE nspname = fdw_objects_name) THEN
       EXECUTE format('CREATE SCHEMA %I', fdw_objects_name);
    END IF;

    -- Import the foreign schemata if not done
    IF NOT EXISTS (SELECT * FROM pg_class
                   WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = fdw_objects_name)
                      AND relname = 'schemata') THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA information_schema LIMIT TO (schemata) FROM SERVER %I INTO %I', remote_server, fdw_objects_name);
    END IF;

    -- Return the result we're interested in
    RETURN QUERY EXECUTE format('SELECT schema_name::name AS remote_schema FROM %I.schemata', fdw_objects_name);
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
    server_type name := @extschema@.__fdw_server_type(remote_server);
BEGIN
    -- Check the type of the server, fail if not implemented
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
