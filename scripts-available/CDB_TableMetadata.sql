
CREATE TABLE IF NOT EXISTS
  @extschema@.CDB_TableMetadata (
    tabname regclass not null primary key,
    updated_at timestamp with time zone not null default now()
  );

CREATE OR REPLACE VIEW @extschema@.CDB_TableMetadata_Text AS
       SELECT FORMAT('%I.%I', n.nspname::text, c.relname::text) tabname, updated_at
       FROM @extschema@.CDB_TableMetadata m JOIN pg_catalog.pg_class c ON m.tabname::oid = c.oid
       LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid;

-- No one can see this
-- Updates are only possible trough the security definer trigger
-- GRANT SELECT ON @extschema@.CDB_TableMetadata TO public;

--
-- Trigger logging updated_at in the CDB_TableMetadata
-- and notifying cdb_tabledata_update with table name as payload.
--
-- Attach to tables like this:
--
--   CREATE trigger track_updates
--    AFTER INSERT OR UPDATE OR TRUNCATE OR DELETE ON <tablename>
--    FOR EACH STATEMENT
--    EXECUTE PROCEDURE cdb_tablemetadata_trigger(); 
--
-- NOTE: _never_ attach to CDB_TableMetadata ...
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_TableMetadata_Trigger()
RETURNS trigger AS
$$
BEGIN
  -- Guard against infinite loop
  IF TG_RELID = '@extschema@.CDB_TableMetadata'::regclass::oid THEN
    RETURN NULL;
  END IF;

  -- Cleanup stale entries
  DELETE FROM @extschema@.CDB_TableMetadata
   WHERE NOT EXISTS (
    SELECT oid FROM pg_class WHERE oid = tabname
  );

  WITH nv as (
    SELECT TG_RELID as tabname, now() as t
  ), updated as (
    UPDATE @extschema@.CDB_TableMetadata x SET updated_at = nv.t
    FROM nv WHERE x.tabname = nv.tabname
    RETURNING x.tabname
  )
  INSERT INTO @extschema@.CDB_TableMetadata SELECT nv.*
  FROM nv LEFT JOIN updated USING(tabname)
  WHERE updated.tabname IS NULL;

  RETURN NULL;
END;
$$  LANGUAGE plpgsql
    VOLATILE
    PARALLEL UNSAFE
    SECURITY DEFINER
    SET search_path = @extschema@, pg_temp;

--
-- Trigger invalidating varnish whenever CDB_TableMetadata
-- record change.
--
CREATE OR REPLACE FUNCTION @extschema@._CDB_TableMetadata_Updated()
RETURNS trigger AS
$$
DECLARE
  tabname regclass;
  rec RECORD;
  found BOOL;
  schema_name TEXT;
  table_name TEXT;
BEGIN

  IF TG_OP = 'UPDATE' or TG_OP = 'INSERT' THEN
    tabname = NEW.tabname;
  ELSE
    tabname = OLD.tabname;
  END IF;

  -- Notify table data update
  -- This needs a little bit more of research regarding security issues
  -- see https://github.com/CartoDB/cartodb/pull/241
  -- PERFORM pg_notify('cdb_tabledata_update', tabname);

  --RAISE NOTICE 'Table % was updated', tabname;

  -- This will be needed until we'll have someone listening
  -- on the event we just broadcasted:
  --
  --  LISTEN cdb_tabledata_update;
  --

  -- Call the first varnish invalidation function owned
  -- by a superuser found in @extschema@ or public schema
  -- (in that order)
  found := false;
  FOR rec IN SELECT u.usesuper, u.usename, n.nspname, p.proname
             FROM pg_proc p, pg_namespace n, pg_user u
             WHERE p.proname = 'cdb_invalidate_varnish'
               AND p.pronamespace = n.oid
               AND n.nspname IN ('public', '@extschema@')
               AND u.usesysid = p.proowner
               AND u.usesuper
             ORDER BY n.nspname
  LOOP
    SELECT n.nspname, c.relname FROM pg_class c, pg_namespace n WHERE c.oid=tabname AND c.relnamespace = n.oid INTO schema_name, table_name;
    EXECUTE 'SELECT ' || quote_ident(rec.nspname) || '.'
            || quote_ident(rec.proname)
            || '(' || quote_literal(quote_ident(schema_name) || '.' || quote_ident(table_name)) || ')';
    found := true;
    EXIT;
  END LOOP;
  IF NOT found THEN RAISE WARNING 'Missing cdb_invalidate_varnish()'; END IF;

  RETURN NULL;
END;
$$  LANGUAGE plpgsql
    VOLATILE
    PARALLEL UNSAFE
    SECURITY DEFINER
    SET search_path = @extschema@, pg_temp;

DROP TRIGGER IF EXISTS table_modified ON @extschema@.CDB_TableMetadata;
-- NOTE: on DELETE we would be unable to convert the table
--       oid (regclass) to its name
CREATE TRIGGER table_modified AFTER INSERT OR UPDATE
ON @extschema@.CDB_TableMetadata FOR EACH ROW EXECUTE PROCEDURE
    @extschema@._CDB_TableMetadata_Updated();


-- similar to TOUCH(1) in unix filesystems but for table in cdb_tablemetadata
CREATE OR REPLACE FUNCTION @extschema@.CDB_TableMetadataTouch(tablename regclass)
    RETURNS void AS
    $$
    BEGIN
        WITH upsert AS (
            UPDATE @extschema@.cdb_tablemetadata
            SET updated_at = NOW()
            WHERE tabname = tablename
            RETURNING *
        )
        INSERT INTO @extschema@.cdb_tablemetadata (tabname, updated_at)
            SELECT tablename, NOW()
            WHERE NOT EXISTS (SELECT * FROM upsert);
    END;
    $$
LANGUAGE 'plpgsql' VOLATILE STRICT PARALLEL UNSAFE;
