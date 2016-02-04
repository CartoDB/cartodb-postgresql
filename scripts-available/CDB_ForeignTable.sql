---------------------------
-- FDW MANAGEMENT FUNCTIONS
--
-- All the FDW settings are read from the `cdb_conf.fdws` entry json file.
---------------------------

CREATE OR REPLACE FUNCTION cartodb._CDB_Setup_FDW(fdw_name text, config json)
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

        IF NOT EXISTS ( SELECT * FROM pg_user_mappings WHERE srvname = name AND usename = row.key ) THEN
          EXECUTE FORMAT ('CREATE USER MAPPING FOR %I SERVER %I', row.key, fdw_name);
        END IF;

    -- Update user mapping settings
    FOR option IN SELECT o.key, o.value from lateral json_each_text(row.value) o LOOP
        IF NOT EXISTS (WITH a AS (select split_part(unnest(umoptions), '=', 1) as options from pg_user_mappings WHERE srvname = name AND usename = row.key) SELECT * from a where options = option.key) THEN
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
    SELECT cartodb.CDB_Organization_Member_Group_Role_Member_Name() INTO org_role;
    EXECUTE FORMAT ('GRANT USAGE ON SCHEMA %I TO %I', name, org_role);

    -- Bring here the remote cdb_tablemetadata
    IF NOT EXISTS ( SELECT * FROM PG_CLASS WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname='do') and relname='cdb_tablemetadata') THEN
      EXECUTE FORMAT ('IMPORT FOREIGN SCHEMA cartodb LIMIT TO (cdb_tablemetadata) FROM SERVER %I INTO %I;', fdw_name, fdw_name, fdw_name);
    END IF;
    EXECUTE FORMAT ('GRANT SELECT ON %I.cdb_tablemetadata TO %I', fdw_name, org_role);

END
$$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION cartodb._CDB_Setup_FDWS()
RETURNS VOID AS 
$$
DECLARE
row record;
BEGIN
  FOR row IN SELECT p.key, p.value from lateral json_each(cartodb.CDB_Conf_GetConf('fdws')) p LOOP
      EXECUTE 'SELECT cartodb._CDB_Setup_FDW($1, $2)' USING row.key, row.value;
    END LOOP;
  END
$$
LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION cartodb._CDB_Setup_FDW(fdw_name text)
  RETURNS void AS
$BODY$
DECLARE
config json;
BEGIN
  SELECT p.value FROM LATERAL json_each(cartodb.CDB_Conf_GetConf('fdws')) p WHERE p.key = fdw_name INTO config;
  EXECUTE 'SELECT cartodb._CDB_Setup_FDW($1, $2)' USING fdw_name, config;
END
$BODY$
LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION cartodb.CDB_Add_Remote_Table(source text, table_name text)
  RETURNS void AS
$$
BEGIN
  PERFORM cartodb._CDB_Setup_FDW(source);
  EXECUTE FORMAT ('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I;', source, table_name, source, source);
  --- Grant SELECT to publicuser
  EXECUTE FORMAT ('GRANT SELECT ON %I.%I TO publicuser;', source, table_name);
END
$$
LANGUAGE plpgsql;
