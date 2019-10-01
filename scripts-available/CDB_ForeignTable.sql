---------------------------
-- FDW MANAGEMENT FUNCTIONS
--
-- All the FDW settings are read from the `cdb_conf.fdws` entry json file.
---------------------------

CREATE OR REPLACE FUNCTION @extschema@._CDB_Setup_FDW(fdw_name text, config json)
RETURNS void
AS $$
DECLARE
  row record;
  option record;
  org_role text;
BEGIN
  -- This function tries to be as idempotent as possible, by not creating anything more than once
  -- (not even using IF NOT EXIST to avoid throwing warnings)
  IF NOT EXISTS ( SELECT * FROM pg_extension WHERE extname = 'postgres_fdw') THEN
    CREATE EXTENSION postgres_fdw;
  END IF;
  -- Create FDW first if it does not exist
  IF NOT EXISTS ( SELECT * FROM pg_foreign_server WHERE srvname = fdw_name)
    THEN
    EXECUTE FORMAT('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw', fdw_name);
  END IF;

  -- Set FDW settings
  FOR row IN SELECT p.key, p.value from lateral json_each_text(config->'server') p
    LOOP
      IF NOT EXISTS (WITH a AS (select split_part(unnest(srvoptions), '=', 1) as options from pg_foreign_server where srvname=fdw_name) SELECT * from a where options = row.key)
        THEN
        EXECUTE FORMAT('ALTER SERVER %I OPTIONS (ADD %I %L)', fdw_name, row.key, row.value);
      ELSE
        EXECUTE FORMAT('ALTER SERVER %I OPTIONS (SET %I %L)', fdw_name, row.key, row.value);
      END IF;
    END LOOP;

    -- Create user mappings
    FOR row IN SELECT p.key, p.value from lateral json_each(config->'users') p LOOP
        -- Check if entry on pg_user_mappings exists

        IF NOT EXISTS ( SELECT * FROM pg_user_mappings WHERE srvname = fdw_name AND usename = row.key ) THEN
          EXECUTE FORMAT ('CREATE USER MAPPING FOR %I SERVER %I', row.key, fdw_name);
        END IF;

    -- Update user mapping settings
    FOR option IN SELECT o.key, o.value from lateral json_each_text(row.value) o LOOP
        IF NOT EXISTS (WITH a AS (select split_part(unnest(umoptions), '=', 1) as options from pg_user_mappings WHERE srvname = fdw_name AND usename = row.key) SELECT * from a where options = option.key) THEN
          EXECUTE FORMAT('ALTER USER MAPPING FOR %I SERVER %I OPTIONS (ADD %I %L)', row.key, fdw_name, option.key, option.value);
        ELSE
          EXECUTE FORMAT('ALTER USER MAPPING FOR %I SERVER %I OPTIONS (SET %I %L)', row.key, fdw_name, option.key, option.value);
        END IF;
      END LOOP;
    END LOOP;

    -- Create schema if it does not exist.
    IF NOT EXISTS ( SELECT * from pg_namespace WHERE nspname=fdw_name) THEN
      EXECUTE FORMAT ('CREATE SCHEMA %I', fdw_name);
    END IF;

    -- Give the organization role usage permisions over the schema
    SELECT @extschema@.CDB_Organization_Member_Group_Role_Member_Name() INTO org_role;
    EXECUTE FORMAT ('GRANT USAGE ON SCHEMA %I TO %I', fdw_name, org_role);

    -- Bring here the remote cdb_tablemetadata
    IF NOT EXISTS ( SELECT * FROM PG_CLASS WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname=fdw_name) and relname='cdb_tablemetadata') THEN
      EXECUTE FORMAT ('CREATE FOREIGN TABLE %I.cdb_tablemetadata (tabname text, updated_at timestamp with time zone) SERVER %I OPTIONS (table_name ''cdb_tablemetadata_text'', schema_name ''@extschema@'', updatable ''false'')', fdw_name, fdw_name);
    END IF;
    EXECUTE FORMAT ('GRANT SELECT ON %I.cdb_tablemetadata TO %I', fdw_name, org_role);

END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE FUNCTION @extschema@._CDB_Setup_FDWS()
RETURNS VOID AS 
$$
DECLARE
row record;
BEGIN
  FOR row IN SELECT p.key, p.value from lateral json_each(@extschema@.CDB_Conf_GetConf('fdws')) p LOOP
      EXECUTE 'SELECT @extschema@._CDB_Setup_FDW($1, $2)' USING row.key, row.value;
    END LOOP;
  END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@._CDB_Setup_FDW(fdw_name text)
  RETURNS void AS
$BODY$
DECLARE
config json;
BEGIN
  SELECT p.value FROM LATERAL json_each(@extschema@.CDB_Conf_GetConf('fdws')) p WHERE p.key = fdw_name INTO config;
  EXECUTE 'SELECT @extschema@._CDB_Setup_FDW($1, $2)' USING fdw_name, config;
END
$BODY$
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE FUNCTION @extschema@.CDB_Add_Remote_Table(source text, table_name text)
  RETURNS void AS
$$
BEGIN
  PERFORM @extschema@._CDB_Setup_FDW(source);
  EXECUTE FORMAT ('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I;', source, table_name, source, source);
  --- Grant SELECT to publicuser
  EXECUTE FORMAT ('GRANT SELECT ON %I.%I TO publicuser;', source, table_name);
END
$$
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE FUNCTION @extschema@.CDB_Get_Foreign_Updated_At(foreign_table regclass)
  RETURNS timestamp with time zone AS
$$
DECLARE
  remote_table_name text;
  fdw_schema_name text;
  time timestamp with time zone;
BEGIN
  -- This will turn a local foreign table (referenced as regclass) to its fully qualified text remote table reference.
  WITH a AS (SELECT ftoptions FROM pg_foreign_table WHERE ftrelid=foreign_table LIMIT 1),
    b as (SELECT (pg_options_to_table(ftoptions)).* FROM a)
    SELECT FORMAT('%I.%I', (SELECT option_value FROM b WHERE option_name='schema_name'), (SELECT option_value FROM b WHERE option_name='table_name'))
  INTO remote_table_name;

  -- We assume that the remote cdb_tablemetadata is called cdb_tablemetadata and is on the same schema as the queried table.
  SELECT nspname FROM pg_class c, pg_namespace n WHERE c.oid=foreign_table AND c.relnamespace = n.oid INTO fdw_schema_name;
  BEGIN
    EXECUTE FORMAT('SELECT updated_at FROM %I.cdb_tablemetadata WHERE tabname=%L ORDER BY updated_at DESC LIMIT 1', fdw_schema_name, remote_table_name) INTO time;
  EXCEPTION
    WHEN undefined_table THEN
      -- If you add a GET STACKED DIAGNOSTICS text_var = RETURNED_SQLSTATE
      -- you get a code 42P01 which corresponds to undefined_table
      RAISE NOTICE 'CDB_Get_Foreign_Updated_At: could not find %.cdb_tablemetadata while checking % updated_at, returning NULL timestamp', fdw_schema_name, foreign_table;
  END;
  RETURN time;
END
$$
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;


-- Produce a valid DB name for objects created for the user FDW's
CREATE OR REPLACE FUNCTION @extschema@.__CDB_User_FDW_Object_Names(fdw_input_name NAME)
RETURNS NAME AS $$
  -- Note on input we use %s and on output we use %I, in order to
  -- avoid double escaping
  SELECT format('cdb_fdw_%s', fdw_input_name)::NAME;
$$
LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- A function to set up a user-defined foreign data server
-- It does not read from CDB_Conf.
-- Only superuser roles can invoke it successfully
--
-- Sample call:
-- SELECT cartodb.CDB_SetUp_User_PG_FDW_Server('amazon', '{
--    "server": {
--      "extensions": "postgis",
--      "dbname": "testdb",
--      "host": "myhostname.us-east-2.rds.amazonaws.com",
--      "port": "5432"
--    },
--    "user_mapping": {
--      "user": "fdw_user",
--      "password": "secret"
--    }
-- }');
--
-- Underneath it will:
--   * Set up postgresql_fdw
--   * Create a server with the name 'cdb_fdw_amazon'
--   * Create a role called 'cdb_fdw_amazon' to manage access
--   * Create a user mapping with that role 'cdb_fdw_amazon'
--   * Create a schema 'cdb_fdw_amazon' as a convenience to set up all foreign
--     tables over there
--
-- It is the responsibility of the superuser to grant that role to either:
--   * Nobody
--   * Specific roles: GRANT amazon TO role_name;
--   * Members of the organization: SELECT cartodb.CDB_Organization_Grant_Role('cdb_fdw_amazon');
--   * The publicuser: GRANT cdb_fdw_amazon TO publicuser;
CREATE OR REPLACE FUNCTION @extschema@._CDB_SetUp_User_PG_FDW_Server(fdw_input_name NAME, config json)
RETURNS void AS $$
DECLARE
  row record;
  option record;
  fdw_objects_name NAME := @extschema@.__CDB_User_FDW_Object_Names(fdw_input_name);
BEGIN
  -- TODO: refactor with original function
  -- This function tries to be as idempotent as possible, by not creating anything more than once
  -- (not even using IF NOT EXIST to avoid throwing warnings)
  IF NOT EXISTS ( SELECT * FROM pg_extension WHERE extname = 'postgres_fdw') THEN
    CREATE EXTENSION postgres_fdw;
    RAISE NOTICE 'Created postgres_fdw EXTENSION';
  END IF;
  -- Create FDW first if it does not exist
  IF NOT EXISTS ( SELECT * FROM pg_foreign_server WHERE srvname = fdw_objects_name)
    THEN
    EXECUTE FORMAT('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw', fdw_objects_name);
    RAISE NOTICE 'Created SERVER % using postgres_fdw', fdw_objects_name;
  END IF;

  -- Set FDW settings
  FOR row IN SELECT p.key, p.value from lateral json_each_text(config->'server') p
    LOOP
      IF NOT EXISTS (WITH a AS (select split_part(unnest(srvoptions), '=', 1) as options from pg_foreign_server where srvname=fdw_objects_name) SELECT * from a where options = row.key)
        THEN
        EXECUTE FORMAT('ALTER SERVER %I OPTIONS (ADD %I %L)', fdw_objects_name, row.key, row.value);
      ELSE
        EXECUTE FORMAT('ALTER SERVER %I OPTIONS (SET %I %L)', fdw_objects_name, row.key, row.value);
      END IF;
    END LOOP;

    -- Create specific role for this
    IF NOT EXISTS ( SELECT 1 FROM pg_roles WHERE rolname = fdw_objects_name) THEN
       EXECUTE format('CREATE ROLE %I NOLOGIN', fdw_objects_name);
       RAISE NOTICE 'Created special ROLE % to access the correponding FDW', fdw_objects_name;
    END IF;

    -- Transfer ownership of the server to the fdw role
    EXECUTE format('ALTER SERVER %I OWNER TO %I', fdw_objects_name, fdw_objects_name);

    -- Create user mapping
    -- NOTE: we use a PUBLIC user mapping but control access to the SERVER
    -- so that we don't need to create a mapping for every user nor store credentials elsewhere
    IF NOT EXISTS ( SELECT * FROM pg_user_mappings WHERE srvname = fdw_objects_name AND usename = 'public' ) THEN
        EXECUTE FORMAT ('CREATE USER MAPPING FOR public SERVER %I', fdw_objects_name);
        RAISE NOTICE 'Created USER MAPPING for accesing foreign server %', fdw_objects_name;
    END IF;

    -- Update user mapping settings
    FOR option IN SELECT o.key, o.value from lateral json_each_text(config->'user_mapping') o LOOP
        IF NOT EXISTS (WITH a AS (select split_part(unnest(umoptions), '=', 1) as options from pg_user_mappings WHERE srvname = fdw_objects_name AND usename = 'public') SELECT * from a where options = option.key) THEN
          EXECUTE FORMAT('ALTER USER MAPPING FOR PUBLIC SERVER %I OPTIONS (ADD %I %L)', fdw_objects_name, option.key, option.value);
        ELSE
          EXECUTE FORMAT('ALTER USER MAPPING FOR PUBLIC SERVER %I OPTIONS (SET %I %L)', fdw_objects_name, option.key, option.value);
        END IF;
    END LOOP;

    -- Grant usage on the wrapper and server to the fdw role
    EXECUTE FORMAT ('GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO %I', fdw_objects_name);
    RAISE NOTICE 'Granted USAGE on the postgres_fdw to the role %', fdw_objects_name;
    EXECUTE FORMAT ('GRANT USAGE ON FOREIGN SERVER %I TO %I', fdw_objects_name, fdw_objects_name);
    RAISE NOTICE 'Granted USAGE on the foreign server to the role %', fdw_objects_name;

    -- Create schema if it does not exist.
    IF NOT EXISTS ( SELECT * from pg_namespace WHERE nspname=fdw_objects_name) THEN
      EXECUTE FORMAT ('CREATE SCHEMA %I', fdw_objects_name);
      RAISE NOTICE 'Created SCHEMA % to host foreign tables', fdw_objects_name;
    END IF;

    -- Give the fdw role ownership over the schema
    EXECUTE FORMAT ('ALTER SCHEMA %I OWNER TO %I', fdw_objects_name, fdw_objects_name);
    RAISE NOTICE 'Gave ownership on the SCHEMA % to %', fdw_objects_name, fdw_objects_name;

    -- TODO: Bring here the remote cdb_tablemetadata
END
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;


-- A function to drop a user-defined foreign server and all related objects
-- It does not read from CDB_Conf
-- It must be executed with a superuser role to succeed
--
-- Sample call:
--   SELECT cartodb.CDB_Drop_User_PG_FDW_Server('amazon')
--
-- Note: if there's any dependent object (i.e. foreign table) this call will fail
CREATE OR REPLACE FUNCTION @extschema@._CDB_Drop_User_PG_FDW_Server(fdw_input_name NAME, force boolean = false)
RETURNS void AS $$
DECLARE
    fdw_objects_name NAME := @extschema@.__CDB_User_FDW_Object_Names(fdw_input_name);
    cascade_clause NAME;
BEGIN
    CASE force
        WHEN true THEN
            cascade_clause := 'CASCADE';
        ELSE
            cascade_clause := 'RESTRICT';
    END CASE;

    EXECUTE FORMAT ('DROP SCHEMA %I %s', fdw_objects_name, cascade_clause);
    RAISE NOTICE 'Dropped schema %', fdw_objects_name;
    EXECUTE FORMAT ('DROP USER MAPPING FOR public SERVER %I', fdw_objects_name);
    RAISE NOTICE 'Dropped user mapping for server %', fdw_objects_name;
    EXECUTE FORMAT ('DROP SERVER %I %s', fdw_objects_name, cascade_clause);
    RAISE NOTICE 'Dropped foreign server %', fdw_objects_name;
    EXECUTE FORMAT ('REVOKE USAGE ON FOREIGN DATA WRAPPER postgres_fdw FROM %I %s', fdw_objects_name, cascade_clause);
    RAISE NOTICE 'Revoked usage on postgres_fdw from %', fdw_objects_name;
    EXECUTE FORMAT ('DROP ROLE %I', fdw_objects_name);
    RAISE NOTICE 'Dropped role %', fdw_objects_name;
END
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;


-- Set up a user foreign table
-- E.g:
--   SELECT cartodb.CDB_SetUp_User_PG_FDW_Table('amazon', 'carto_lite', 'mytable');
--   SELECT * FROM amazon.my_table;
CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_User_PG_FDW_Table(fdw_input_name NAME, foreign_schema NAME, table_name NAME)
RETURNS void AS $$
DECLARE
    fdw_objects_name NAME := @extschema@.__CDB_User_FDW_Object_Names(fdw_input_name);
BEGIN
  EXECUTE FORMAT ('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I;', foreign_schema, table_name, fdw_objects_name, fdw_objects_name);
  --- Grant SELECT to fdw role
  EXECUTE FORMAT ('GRANT SELECT ON %I.%I TO %I;', fdw_objects_name, table_name, fdw_objects_name);
END
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@._cdb_dbname_of_foreign_table(reloid oid)
RETURNS TEXT AS $$
    SELECT option_value FROM pg_options_to_table((

        SELECT fs.srvoptions
        FROM pg_foreign_table ft
        LEFT JOIN pg_foreign_server fs ON ft.ftserver = fs.oid
        WHERE ft.ftrelid = reloid

    )) WHERE option_name='dbname';
$$ LANGUAGE SQL VOLATILE PARALLEL UNSAFE;


-- Return a set of (dbname, schema_name, table_name, updated_at)
-- It is aware of foreign tables
-- It assumes the local (schema_name, table_name) map to the remote ones with the same name
-- Note: dbname is never quoted whereas schema and table names are when needed.
CREATE OR REPLACE FUNCTION @extschema@.CDB_QueryTables_Updated_At(query text)
RETURNS TABLE(dbname text, schema_name text, table_name text, updated_at timestamptz)
AS $$
    WITH query_tables AS (
      SELECT unnest(@extschema@.CDB_QueryTablesText(query)) schema_table_name
    ), query_tables_oid AS (
      SELECT schema_table_name, schema_table_name::regclass::oid AS reloid
      FROM query_tables
    ),
    fqtn AS (
      SELECT
        (CASE WHEN c.relkind = 'f' THEN @extschema@._cdb_dbname_of_foreign_table(query_tables_oid.reloid)
              ELSE current_database()
         END)::text AS dbname,
         quote_ident(n.nspname::text) schema_name,
         quote_ident(c.relname::text) table_name,
         c.relkind,
         query_tables_oid.reloid
      FROM query_tables_oid, pg_catalog.pg_class c
      LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
      WHERE c.oid = query_tables_oid.reloid
    )
    SELECT fqtn.dbname, fqtn.schema_name, fqtn.table_name,
      (CASE WHEN relkind = 'f' THEN @extschema@.CDB_Get_Foreign_Updated_At(reloid)
            ELSE (SELECT md.updated_at FROM @extschema@.CDB_TableMetadata md WHERE md.tabname = reloid)
      END) AS updated_at
    FROM fqtn;
$$ LANGUAGE SQL VOLATILE PARALLEL UNSAFE;


-- Return the last updated time of a set of tables
-- It is aware of foreign tables
-- It assumes the local (schema_name, table_name) map to the remote ones with the same name
CREATE OR REPLACE FUNCTION @extschema@.CDB_Last_Updated_Time(tables text[])
RETURNS timestamptz AS $$
    WITH t AS (
        SELECT unnest(tables) AS schema_table_name
    ), t_oid AS (
        SELECT (t.schema_table_name)::regclass::oid as reloid FROM t
    ), t_updated_at AS (
        SELECT
            (CASE WHEN relkind = 'f' THEN @extschema@.CDB_Get_Foreign_Updated_At(reloid)
                  ELSE (SELECT md.updated_at FROM @extschema@.CDB_TableMetadata md WHERE md.tabname = reloid)
             END) AS updated_at
        FROM t_oid
        LEFT JOIN pg_catalog.pg_class c ON c.oid = reloid
    ) SELECT max(updated_at) FROM t_updated_at;
$$ LANGUAGE SQL VOLATILE PARALLEL UNSAFE;
