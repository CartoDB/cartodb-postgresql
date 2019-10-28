
-- This function is just a placement to store and use the pattern for
-- foreign server names
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Name_Pattern()
RETURNS TEXT
AS $$
    SELECT 'cdb_fs_';
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;


-- Produce a valid DB name for objects created for the user FDW's
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Object_Name(fdw_input_name NAME)
RETURNS NAME
AS $$
DECLARE
    object_name text := format('%s%s', @extschema@.__CDB_FS_Name_Pattern(), fdw_input_name);
BEGIN
  -- We discard anything that would be truncated
  IF (char_length(object_name) < 64) THEN
    RETURN object_name::name;
  ELSE
    RAISE EXCEPTION 'Object name is too long to be used as identifier';
  END IF;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;



-- List registered servers
-- TODO: Decide whether we want to show extra config (extensions, fetch_size, use_remote_estimate)s 
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Servers(fdw_pattern TEXT DEFAULT '%')
RETURNS TABLE (
    name        text,
    driver      text,
    host        text,
    port        text,
    dbname      text,
    readmode    text,
    username    text
)
AS $$
DECLARE
    server_name text := concat(@extschema@.__CDB_FS_Name_Pattern() || fdw_pattern);
BEGIN
    RETURN QUERY SELECT 
        -- Name as shown to the user
        right(s.srvname, char_length(s.srvname::TEXT) - char_length(@extschema@.__CDB_FS_Name_Pattern()))::TEXT AS "Name",

        -- Which driver are we using (postgres_fdw, odbc_fdw...)
        f.fdwname::text AS "Driver",

        -- Read 
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'host') AS "Host",
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'port') AS "Port",
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'dbname') AS "DBName",
        CASE WHEN (SELECT NOT option_value::boolean FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'updatable') THEN 'read-only' ELSE 'read-write' END AS "ReadMode",

        -- Read username from user mappings
        (SELECT option_value FROM pg_options_to_table(u.umoptions) WHERE option_name LIKE 'user') AS "Username"
    FROM pg_foreign_server s
    JOIN pg_foreign_data_wrapper f ON f.oid=s.srvfdw
    LEFT JOIN pg_user_mappings u
    ON u.srvid = s.oid
    WHERE s.srvname ILIKE server_name
    ORDER BY 1;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;
