-- Depends on:
--   * CDB_Helper.sql
--   * CDB_ExtensionUtils.sql
--   * CDB_TransformToWebmercator.sql
--   * CDB_TableMetadata.sql
--   * CDB_Quota.sql
--   * _CDB_UserQuotaInBytes() function, installed by rails
--     (user.rebuild_quota_trigger, called by rake task cartodb:db:update_test_quota_trigger)

-- 1) Required checks before running cartodbfication
-- Either will pass silenty or raise an exception
CREATE OR REPLACE FUNCTION @extschema@._CDB_check_prerequisites(schema_name TEXT, reloid REGCLASS)
RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
  IF @extschema@.schema_exists(schema_name) = false THEN
    RAISE EXCEPTION 'Invalid schema name "%"', schema_name;
  END IF;

  -- TODO: Check that user quota is set ?
  BEGIN
    EXECUTE FORMAT('SELECT %I._CDB_UserQuotaInBytes();', schema_name::text) INTO sql;
    EXCEPTION WHEN undefined_function THEN
      RAISE EXCEPTION 'Please set user quota before cartodbfying tables.';
  END;
END;
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Drop cartodb triggers (might prevent changing columns)
CREATE OR REPLACE FUNCTION @extschema@._CDB_drop_triggers(reloid REGCLASS)
  RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
  -- "track_updates"
  sql := Format('DROP TRIGGER IF EXISTS track_updates ON %s', reloid::text);
  EXECUTE sql;

  -- "update_the_geom_webmercator"
  sql := Format('DROP TRIGGER IF EXISTS update_the_geom_webmercator_trigger ON %s', reloid::text);
  EXECUTE sql;

  -- "test_quota" and "test_quota_per_row"
  sql := Format('DROP TRIGGER IF EXISTS test_quota ON %s', reloid::text);
  EXECUTE sql;
  sql := Format('DROP TRIGGER IF EXISTS test_quota_per_row ON %s', reloid::text);
  EXECUTE sql;
END;
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


-- Cartodb_id creation & validation or renaming if invalid
CREATE OR REPLACE FUNCTION @extschema@._CDB_create_cartodb_id_column(reloid REGCLASS)
  RETURNS void
AS $$
DECLARE
  sql TEXT;
  rec RECORD;
  rec2 RECORD;
  had_column BOOLEAN;
  i INTEGER;
  new_name TEXT;
  cartodb_id_name TEXT;
BEGIN
  << cartodb_id_setup >>
  LOOP --{
    had_column := FALSE;
    BEGIN
      sql := Format('ALTER TABLE %s ADD cartodb_id SERIAL NOT NULL UNIQUE', reloid::text);
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql;
      cartodb_id_name := 'cartodb_id';
      EXIT cartodb_id_setup;
      EXCEPTION
      WHEN duplicate_column THEN
        RAISE NOTICE 'Column cartodb_id already exists';
        had_column := TRUE;
      WHEN others THEN
        RAISE EXCEPTION 'Cartodbfying % (cartodb_id): % (%)', reloid, SQLERRM, SQLSTATE;
    END;

    IF had_column THEN
      SELECT pg_catalog.pg_get_serial_sequence(reloid::text, 'cartodb_id')
        AS seq INTO rec2;

      -- Check data type is an integer
      SELECT
        pg_catalog.pg_get_serial_sequence(reloid::text, 'cartodb_id') as seq,
        t.typname, t.oid, a.attnotnull FROM pg_type t, pg_attribute a
      WHERE a.atttypid = t.oid AND a.attrelid = reloid AND NOT a.attisdropped AND a.attname = 'cartodb_id'
      INTO STRICT rec;

      -- 20=int2, 21=int4, 23=int8
      IF rec.oid NOT IN (20,21,23) THEN -- {
        RAISE NOTICE 'Existing cartodb_id field is of invalid type % (need int2, int4 or int8), renaming', rec.typname;
      ELSIF rec.seq IS NULL THEN -- }{
        RAISE NOTICE 'Existing cartodb_id field does not have an associated sequence, renaming';
      ELSE -- }{
        sql := Format('ALTER TABLE %s ALTER COLUMN cartodb_id SET NOT NULL', reloid::text);
        IF NOT EXISTS ( SELECT c.conname FROM pg_constraint c, pg_attribute a
        WHERE c.conkey = ARRAY[a.attnum] AND c.conrelid = reloid
              AND a.attrelid = reloid
              AND NOT a.attisdropped
              AND a.attname = 'cartodb_id'
              AND c.contype IN ( 'u', 'p' ) ) -- unique or pkey
        THEN
          sql := sql || ', ADD unique(cartodb_id)';
        END IF;
        BEGIN
          RAISE DEBUG 'Running %', sql;
          EXECUTE sql;
          cartodb_id_name := 'cartodb_id';
          EXIT cartodb_id_setup;
          EXCEPTION
          WHEN unique_violation OR not_null_violation THEN
            RAISE NOTICE '%, renaming', SQLERRM;
          WHEN others THEN
            RAISE EXCEPTION 'Cartodbfying % (cartodb_id): % (%)', reloid, SQLERRM, SQLSTATE;
        END;
      END IF; -- }

      -- invalid column, need rename and re-create it
      i := 0;
      << rename_column >>
      LOOP --{
        new_name := '_cartodb_id' || i;
        BEGIN
          sql := Format('ALTER TABLE %s RENAME COLUMN cartodb_id TO %I', reloid::text, new_name);
          RAISE DEBUG 'Running %', sql;
          EXECUTE sql;
          EXCEPTION
          WHEN duplicate_column THEN
            i := i+1;
            CONTINUE rename_column;
          WHEN others THEN
            RAISE EXCEPTION 'Cartodbfying % (renaming cartodb_id): % (%)', reloid, SQLERRM, SQLSTATE;
        END;
        cartodb_id_name := new_name;
        EXIT rename_column;
      END LOOP; --}
      CONTINUE cartodb_id_setup;
    END IF;
  END LOOP; -- }

  -- Try to copy data from new name if possible
  IF new_name IS NOT NULL THEN
    RAISE NOTICE 'Trying to recover data from % column', new_name;
    BEGIN
      -- Copy existing values to new field
      -- NOTE: using ALTER is a workaround to a PostgreSQL bug and is also known to be faster for tables with many rows
      -- See http://www.postgresql.org/message-id/20140530143150.GA11051@localhost
      sql := Format('ALTER TABLE %s ALTER cartodb_id TYPE int USING %I::integer', reloid::text, new_name);
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql;

      -- Find max value
      sql := Format('SELECT coalesce(max(cartodb_id), 0) as max FROM %s', reloid::text);
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql INTO rec;

      -- Find sequence name
      SELECT pg_catalog.pg_get_serial_sequence(reloid::text, 'cartodb_id')
        AS seq INTO rec2;

      -- Reset sequence name
      sql := Format('ALTER SEQUENCE %s RESTART WITH %s', rec2.seq::text, rec.max + 1);
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql;

      -- Drop old column (all went fine if we got here)
      sql := Format('ALTER TABLE %s DROP %I', reloid::text, new_name);
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql;

      EXCEPTION
      WHEN others THEN
        RAISE NOTICE 'Could not initialize cartodb_id with existing values: % (%)',
        SQLERRM, SQLSTATE;
    END;
  END IF;

  -- Set primary key of the table if not already present (e.g. tables created from SQL API)
  IF cartodb_id_name IS NULL THEN
    RAISE EXCEPTION 'Cartodbfying % (Didnt get cartodb_id field name)', reloid;
  END IF;
  BEGIN
    sql := Format('ALTER TABLE %s ADD PRIMARY KEY (cartodb_id)', reloid::text);
    EXECUTE sql;
    EXCEPTION
    WHEN others THEN
      RAISE DEBUG 'Table % Already had PRIMARY KEY', reloid;
  END;

END;
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


-- Create all triggers
-- NOTE: drop/create has the side-effect of re-enabling disabled triggers
CREATE OR REPLACE FUNCTION @extschema@._CDB_create_triggers(schema_name TEXT, reloid REGCLASS)
RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
-- "track_updates"
  sql := 'CREATE trigger track_updates AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON '
         || reloid::text
         || ' FOR EACH STATEMENT EXECUTE PROCEDURE @extschema@.cdb_tablemetadata_trigger()';
  EXECUTE sql;

-- "update_the_geom_webmercator"
-- TODO: why _before_ and not after ?
  sql := 'CREATE trigger update_the_geom_webmercator_trigger BEFORE INSERT OR UPDATE OF the_geom ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE @extschema@._CDB_update_the_geom_webmercator()';
  EXECUTE sql;

-- "test_quota" and "test_quota_per_row"

  sql := 'CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' EXECUTE PROCEDURE @extschema@.CDB_CheckQuota(0.1, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;

  sql := 'CREATE TRIGGER test_quota_per_row BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE @extschema@.CDB_CheckQuota(0.001, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;
END;
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- 8.b) Create all raster triggers
-- NOTE: drop/create has the side-effect of re-enabling disabled triggers
CREATE OR REPLACE FUNCTION @extschema@._CDB_create_raster_triggers(schema_name TEXT, reloid REGCLASS)
  RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
-- "track_updates"
  sql := 'CREATE trigger track_updates AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON '
         || reloid::text
         || ' FOR EACH STATEMENT EXECUTE PROCEDURE @extschema@.cdb_tablemetadata_trigger()';
  EXECUTE sql;

-- "test_quota" and "test_quota_per_row"

  sql := 'CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' EXECUTE PROCEDURE @extschema@.CDB_CheckQuota(1, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;

  sql := 'CREATE TRIGGER test_quota_per_row BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE @extschema@.CDB_CheckQuota(0.001, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;
END;
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;



-- Update the_geom_webmercator
CREATE OR REPLACE FUNCTION @extschema@._CDB_update_the_geom_webmercator()
  RETURNS trigger
AS $$
BEGIN
  NEW.the_geom_webmercator := @extschema@.CDB_TransformToWebmercator(NEW.the_geom);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

--- Trigger to update the updated_at column. No longer added by default
--- but kept here for compatibility with old tables which still have this behavior
--- and have it added
CREATE OR REPLACE FUNCTION @extschema@._CDB_update_updated_at()
  RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at := now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Auxiliary function
CREATE OR REPLACE FUNCTION @extschema@._CDB_is_raster_table(schema_name TEXT, reloid REGCLASS)
  RETURNS BOOLEAN
AS $$
DECLARE
  sql TEXT;
  is_raster BOOLEAN;
  rel_name TEXT;
BEGIN
  IF @extschema@.schema_exists(schema_name) = FALSE THEN
    RAISE EXCEPTION 'Invalid schema name "%"', schema_name;
  END IF;

  SELECT relname FROM pg_class WHERE oid=reloid INTO rel_name;

  BEGIN
    sql := 'SELECT the_raster_webmercator FROM '
          || quote_ident(schema_name::TEXT)
          || '.'
          || quote_ident(rel_name::TEXT)
          || ' LIMIT 1';
    is_raster = TRUE;
    EXECUTE sql;

    EXCEPTION WHEN undefined_column THEN
      is_raster = FALSE;
  END;

  RETURN is_raster;
END;
$$ LANGUAGE PLPGSQL STABLE PARALLEL UNSAFE;



-- ////////////////////////////////////////////////////

-- Ensure a table is a "cartodb" table (See https://github.com/CartoDB/cartodb/wiki/CartoDB-user-table)

DROP FUNCTION IF EXISTS CDB_CartodbfyTable(reloid REGCLASS);
CREATE OR REPLACE FUNCTION @extschema@.CDB_CartodbfyTable(reloid REGCLASS)
RETURNS REGCLASS
AS $$
BEGIN
  RETURN @extschema@.CDB_CartodbfyTable('public', reloid);
END;
$$ LANGUAGE PLPGSQL;


-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
--
--    NEW CARTODBFY CODE FROM HERE ON DOWN
--
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
--
--  CDB_CartodbfyTable(destschema TEXT, reloid REGCLASS)
--
--     Main function, calls the following functions, with a little
--     logic before the table re-write to avoid re-writing if the table
--     already has all the necessary columns in place.
--
--     It returns the destoid of the table. If no rewritting is needed
--     the return value will be equal to reloid.
--
--
-- (0) _CDB_check_prerequisites
--     As before, this checks the prerequisites before trying to cartodbfy
--
-- (1) _CDB_drop_triggers
--     As before, this drops all the metadata and geom sync triggers
--
-- (2) _CDB_Has_Usable_Primary_ID()
--     Returns TRUE if it can find a unique and not null integer primary key named
--    'cartodb_id' or can rename an existing key.
--     Returns FALSE otherwise.
--
-- (3) _CDB_Has_Usable_Geom()
--     Looks for existing EPSG:4326 and EPSG:3857 geometry columns, and
--     renames them to the standard names if it can find them, returning TRUE.
--     If it cannot find both columns in the right EPSG, returns FALSE.
--
-- (4) _CDB_Rewrite_Table()
--     If table does not have a usable primary key and both usable geom
--     columns it needs to be re-written. Function constructs an appropriate
--     CREATE TABLE AS SELECT... query and executes it.
--
-- (5) _CDB_Add_Indexes()
--     Checks the primary key column for primary key constraint, adds it if
--     missing. Check geometry columns for GIST indexes and adds them if missing.
--
-- (6) _CDB_create_triggers()
--     Adds the system metadata and geometry column update triggers back
--     onto the table.
--
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=


CREATE OR REPLACE FUNCTION @extschema@._CDB_Columns(OUT pkey TEXT, OUT geomcol TEXT, OUT mercgeomcol TEXT)
RETURNS record
AS $$
BEGIN

pkey := 'cartodb_id';
geomcol := 'the_geom';
mercgeomcol := 'the_geom_webmercator';

END;
$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION @extschema@._CDB_Error(message TEXT, funcname TEXT DEFAULT '_CDB_Error')
RETURNS void
AS $$
BEGIN

  RAISE EXCEPTION 'CDB(%): %', funcname, message;

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION @extschema@._CDB_SQL(sql TEXT, funcname TEXT DEFAULT '_CDB_SQL')
RETURNS void
AS $$
BEGIN

  RAISE DEBUG 'CDB(%): %', funcname, sql;
  EXECUTE sql;

  EXCEPTION
  WHEN others THEN
    RAISE EXCEPTION 'CDB(%:%:%): %', funcname, SQLSTATE, SQLERRM, sql;

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;


-- DEPRECATED: Use _CDB_Unique_Identifier since it's UTF8 Safe and length
-- aware. Find a unique relation name in the given schema, starting from the
-- template given. If the template is already unique, just return it;
-- otherwise, append an increasing integer until you find a unique variant.
CREATE OR REPLACE FUNCTION @extschema@._CDB_Unique_Relation_Name(schemaname TEXT, relationname TEXT)
RETURNS TEXT
AS $$
DECLARE
  rec RECORD;
  i INTEGER;
  newrelname TEXT;
BEGIN

  RAISE EXCEPTION '_CDB_Unique_Relation_Name is DEPRECATED. Use _CDB_Unique_Identifier(prefix TEXT, relname TEXT, suffix TEXT, schema TEXT DEFAULT NULL)';

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL SAFE;


-- DEPRECATED: Use _CDB_Unique_Column_Identifier since it's UTF8 Safe and length
-- aware. Find a unique column name in the given relation, starting from the
-- column name given. If the column name is already unique, just return it;
-- otherwise, append an increasing integer until you find a unique variant.
CREATE OR REPLACE FUNCTION @extschema@._CDB_Unique_Column_Name(reloid REGCLASS, columnname TEXT)
RETURNS TEXT
AS $$
DECLARE
  rec RECORD;
  i INTEGER;
  newcolname TEXT;
BEGIN

  RAISE EXCEPTION '_CDB_Unique_Column_Name is DEPRECATED. Use _CDB_Unique_Column_Identifier(prefix TEXT, relname TEXT, suffix TEXT, reloid REGCLASS DEFAULT NULL)';

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL SAFE;


-- Find out if the table already has a usable primary key
-- If the table has both a usable key and usable geometry
-- we can no-op on the table copy and just ensure that the
-- indexes and triggers are in place
DROP FUNCTION IF EXISTS _CDB_Has_Usable_Primary_ID(reloid REGCLASS);
CREATE OR REPLACE FUNCTION @extschema@._CDB_Has_Usable_Primary_ID(reloid REGCLASS)
  RETURNS BOOLEAN
AS $$
DECLARE
  rec RECORD;
  const RECORD;
  i INTEGER;
  sql TEXT;
  useable_key BOOLEAN = false;
BEGIN

  RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', 'entered function';

  -- Read in the names of the CartoDB columns
  const := @extschema@._CDB_Columns();

  -- Do we already have a properly named column?
  SELECT a.attname, i.indisprimary, i.indisunique, a.attnotnull, a.atttypid
  INTO rec
  FROM pg_class c
  JOIN pg_attribute a ON a.attrelid = c.oid
  JOIN pg_type t ON a.atttypid = t.oid
  LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE c.oid = reloid
  AND NOT a.attisdropped
  AND a.attname = const.pkey;

  -- Found something named right...
  IF FOUND THEN

    -- And it's a unique primary key! Done!
    IF (rec.indisprimary OR rec.indisunique) AND rec.attnotnull THEN
      RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', Format('found good ''%s''', const.pkey);
      RETURN true;

    -- Check and see if the column values are unique and not null,
    -- if they are, we can use this column...
    ELSE

      -- Assume things are OK until proven otherwise...
      useable_key := true;
      BEGIN
        sql := Format('ALTER TABLE %s ADD CONSTRAINT %s_pk PRIMARY KEY (%s)', reloid::text, const.pkey, const.pkey);
        sql := sql || ', ' || Format('ADD CONSTRAINT %s_integer CHECK (%s::integer >=0);', const.pkey, const.pkey);
        RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', sql;
        EXECUTE sql;
        EXCEPTION
        -- Failed unique check...
        WHEN unique_violation THEN
          RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', Format('column %s is not unique', const.pkey);
          useable_key := false;
        -- Failed not null check...
        WHEN not_null_violation THEN
          RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', Format('column %s contains nulls', const.pkey);
          useable_key := false;
        -- Failed integer check...
        WHEN invalid_text_representation THEN
          RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', Format('invalid input syntax for integer %s', const.pkey);
          useable_key := false;
        -- Other fatal error
        WHEN others THEN
          PERFORM _CDB_Error(sql, Format('_CDB_Has_Usable_Primary_ID: %s', SQLERRM));
      END;

      -- Clean up test constraint
      IF useable_key THEN
        PERFORM @extschema@._CDB_SQL(Format('ALTER TABLE %s DROP CONSTRAINT %s_pk', reloid::text, const.pkey));
        PERFORM @extschema@._CDB_SQL(Format('ALTER TABLE %s DROP CONSTRAINT %s_integer', reloid::text, const.pkey));

      -- Move non-valid column out of the way
      ELSE

        RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %',
          Format('found non-valid ''%s''', const.pkey);

        PERFORM @extschema@._CDB_Error(sql, Format('_CDB_Has_Usable_Primary_ID: Error: invalid cartodb_id, %s', const.pkey));

      END IF;

      RETURN useable_key;

    END IF;

  -- There's no column there named pkey
  ELSE

    -- Is there another integer suitable primary key already?
    SELECT a.attname
    INTO rec
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid
    JOIN pg_type t ON a.atttypid = t.oid
    LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE c.oid = reloid AND NOT a.attisdropped
    AND i.indisprimary AND i.indisunique AND a.attnotnull AND a.atttypid IN (20,21,23);

    -- Yes! Ok, rename it.
    IF FOUND THEN
      PERFORM @extschema@._CDB_SQL(Format('ALTER TABLE %s RENAME COLUMN %s TO %s', reloid::text, rec.attname, const.pkey),'_CDB_Has_Usable_Primary_ID');
      RETURN true;
    ELSE
      RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %',
        Format('found no useful column for ''%s''', const.pkey);
    END IF;

  END IF;

  RAISE DEBUG 'CDB(_CDB_Has_Usable_Primary_ID): %', 'function complete';

  -- Didn't find re-usable key, so return FALSE
  RETURN false;
END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@._CDB_Has_Usable_PK_Sequence(reloid REGCLASS)
RETURNS BOOLEAN
AS $$
DECLARE
  seq TEXT;
  const RECORD;
  has_sequence BOOLEAN = false;
BEGIN

  const := @extschema@._CDB_Columns();

  SELECT pg_get_serial_sequence(reloid::text, const.pkey)
  INTO STRICT seq;
  has_sequence := seq IS NOT NULL;

  RETURN has_sequence;
END;
$$ LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

-- Return a set of columns that can be candidates to be the_geom[webmercator]
-- with some extra information to analyze them.
CREATE OR REPLACE FUNCTION @extschema@._cdb_geom_candidate_columns(reloid REGCLASS)
RETURNS TABLE (attname name, srid integer, typname name, desired_attname text, desired_srid integer)
AS $$
DECLARE
  const RECORD;
BEGIN

  const := @extschema@._CDB_Columns();

  RETURN QUERY
    SELECT
    a.attname,
    CASE WHEN t.typname = 'geometry' THEN @postgisschema@.postgis_typmod_srid(a.atttypmod) ELSE NULL END AS srid,
    t.typname,
    f.desired_attname, f.desired_srid
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid
    JOIN pg_type t ON a.atttypid = t.oid,
    (VALUES (const.geomcol, 4326), (const.mercgeomcol, 3857) ) as f(desired_attname, desired_srid)
    WHERE c.oid = reloid
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND @postgisschema@.postgis_typmod_srid(a.atttypmod) IN (4326, 3857, 0)
    ORDER BY t.oid ASC;
END;
$$ LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

DO $$
BEGIN
  SET search_path TO @extschema@;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = '_cdb_has_usable_geom_record') THEN
    CREATE TYPE @extschema@._cdb_has_usable_geom_record
      AS (has_usable_geoms boolean,
        text_geom_column boolean,
        text_geom_column_name text,
        text_geom_column_srid boolean,
        has_geom boolean,
        has_geom_name text,
        has_mercgeom boolean,
        has_mercgeom_name text);
    END IF;
END$$;

DROP FUNCTION IF EXISTS _CDB_Has_Usable_Geom(REGCLASS);
CREATE OR REPLACE FUNCTION @extschema@._CDB_Has_Usable_Geom(reloid REGCLASS)
RETURNS @extschema@._cdb_has_usable_geom_record
AS $$
DECLARE
  r1 RECORD;
  r2 RECORD;
  rv RECORD;

  const RECORD;

  has_geom BOOLEAN := false;
  has_mercgeom BOOLEAN := false;
  has_geom_name TEXT;
  has_mercgeom_name TEXT;

  -- In case 'the_geom' is a text column
  text_geom_column BOOLEAN := false;
  text_geom_column_name TEXT := '';
  text_geom_column_srid BOOLEAN := true;

  -- Utility variables
  srid INTEGER;
  str TEXT;
  sql TEXT;
BEGIN

  RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %', 'entered function';

  -- Read in the names of the CartoDB columns
  const := @extschema@._CDB_Columns();

  -- Do we have a column we can use?
  FOR r1 IN
    SELECT * FROM @extschema@._cdb_geom_candidate_columns(reloid)
  LOOP

    RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %', Format('checking column ''%s''', r1.attname);

    -- Name collision: right name (the_geom, the_geomwebmercator?)  but wrong type...
    IF r1.typname != 'geometry' AND r1.attname = r1.desired_attname THEN

      -- Maybe it's a geometry column hiding in a text column?
      IF r1.typname IN ('text','varchar','char') THEN

        RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %', Format('column ''%s'' is a text column', r1.attname);

        BEGIN
          sql := Format('SELECT Max(@postgisschema@.ST_SRID(%I::@postgisschema@.geometry)) AS srid FROM %I', r1.attname, reloid::text);
          EXECUTE sql INTO srid;
          -- This gets skipped if EXCEPTION happens
          -- Let the table writer know we need to convert from text
          RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %', Format('column ''%s'' can be cast from text to geometry', r1.attname);
          text_geom_column := true;
          text_geom_column_name := r1.attname;
          -- Let the table writer know we need to force an SRID
          IF srid = 0 THEN
            text_geom_column_srid := false;
          END IF;
        -- Nope, the text in the column can't be converted into geometry
        -- so rename it out of the way
        EXCEPTION
          WHEN others THEN
            IF SQLERRM = 'parse error - invalid geometry' THEN
              text_geom_column := false;
              str := @extschema@._CDB_Unique_Column_Identifier(NULL, r1.attname, NULL, reloid);
              sql := Format('ALTER TABLE %s RENAME COLUMN %s TO %I', reloid::text, r1.attname, str);
              PERFORM @extschema@._CDB_SQL(sql,'_CDB_Has_Usable_Geom');
              RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %',
                Format('Text column %s is not convertible to geometry, renamed to %s', r1.attname, str);
            ELSE
              RAISE EXCEPTION 'CDB(_CDB_Has_Usable_Geom) UNEXPECTED ERROR';
            END IF;
        END;

      -- Just change its name so we can write a new column into that name.
      ELSE
        str := @extschema@._CDB_Unique_Column_Identifier(NULL, r1.attname, NULL, reloid);
        sql := Format('ALTER TABLE %s RENAME COLUMN %s TO %I', reloid::text, r1.attname, str);
        PERFORM @extschema@._CDB_SQL(sql,'_CDB_Has_Usable_Geom');
        RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %',
          Format('%s is the wrong type, renamed to %s', r1.attname, str);
      END IF;

    -- Found a geometry column!
    ELSIF r1.typname = 'geometry' THEN

      -- If it's the right SRID, we can use it in place without
      -- transforming it!
      IF r1.srid = r1.desired_srid THEN

        RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %', Format('found acceptable ''%s''', r1.attname);

        IF r1.desired_attname = const.geomcol THEN
          has_geom := true;
          has_geom_name := r1.attname;
        ELSIF r1.desired_attname = const.mercgeomcol THEN
          has_mercgeom := true;
          has_mercgeom_name := r1.attname;
        END IF;

      -- If it's an unknown SRID, we need to know that too
      ELSIF r1.srid = 0 THEN

        -- Unknown SRID, we'll have to fill it in later
        text_geom_column_srid := true;

      END IF;

    END IF;

  END LOOP;

  SELECT
    -- If table is perfect (no transforms required), return TRUE!
    has_geom AND has_mercgeom AS has_usable_geoms,
    -- If the geometry column is hiding in a text field, return enough info to deal w/ it.
    text_geom_column, text_geom_column_name, text_geom_column_srid,
    -- Return enough info to rename geom columns if needed
    has_geom, has_geom_name, has_mercgeom, has_mercgeom_name
    INTO rv;

  RAISE DEBUG 'CDB(_CDB_Has_Usable_Geom): %', Format('returning %s', rv);

  RETURN rv;

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;


-- Create a copy of the table. Assumes that the "Has usable" functions
-- have already been run, so that if there is a 'cartodb_id' column, it is
-- a "good" one, and the same for the geometry columns. If all the required
-- columns are in place already, it no-ops and just renames the table to
-- the destination if necessary.
CREATE OR REPLACE FUNCTION @extschema@._CDB_Rewrite_Table(reloid REGCLASS, destschema TEXT DEFAULT NULL)
RETURNS BOOLEAN
AS $$
DECLARE

  relname TEXT;
  relschema TEXT;
  relseq TEXT;

  destoid REGCLASS;
  destname TEXT;
  destseq TEXT;
  destseqmax INTEGER;

  copyname TEXT;

  column_name_sql TEXT;
  geom_transform_sql TEXT := NULL;
  geom_column_source TEXT := '';

  rec RECORD;
  const RECORD;
  gc RECORD;
  sql TEXT;
  str TEXT;
  table_srid INTEGER;
  geom_srid INTEGER;

  has_usable_primary_key BOOLEAN;
  has_usable_pk_sequence BOOLEAN;

BEGIN

  RAISE DEBUG 'CDB(_CDB_Rewrite_Table): %', 'entered function';

  -- Read CartoDB standard column names in
  const := @extschema@._CDB_Columns();

  -- Save the raw schema/table names for later
  SELECT n.nspname, c.relname, c.relname
  INTO STRICT relschema, relname, destname
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE c.oid = reloid;

  -- Default the destination to current schema if unspecified
  IF destschema IS NULL THEN
    destschema := relschema;
  END IF;

  -- See if there is a primary key column we need to carry along to the
  -- new table. If this is true, it implies there is an indexed
  -- primary key of integer type named (by default) cartodb_id
  SELECT @extschema@._CDB_Has_Usable_Primary_ID(reloid)
  INTO STRICT has_usable_primary_key;

  RAISE DEBUG 'CDB(_CDB_Rewrite_Table): has_usable_primary_key %', has_usable_primary_key;

  -- See if the candidate primary key column has a sequence for default
  -- values. No usable pk implies has_usable_pk_sequence = false.
  has_usable_pk_sequence := false;
  IF has_usable_primary_key THEN
    SELECT _CDB_Has_Usable_PK_Sequence(reloid)
    INTO STRICT has_usable_pk_sequence;
  END IF;

  -- See if the geometry columns we need are already available
  -- on the table. If they are, we don't need to do any bulk
  -- transformation of the table, we can just ensure proper
  -- indexes are in place and apply a rename
  SELECT *
  FROM @extschema@._CDB_Has_Usable_Geom(reloid)
  INTO STRICT gc;

  -- If geom is the wrong name, just rename it.
  IF gc.has_geom AND gc.has_geom_name != const.geomcol THEN
    sql := Format('ALTER TABLE %s DROP COLUMN IF EXISTS %I', reloid::text, const.geomcol);
    PERFORM @extschema@._CDB_SQL(sql,'_CDB_Rewrite_Table');
    sql := Format('ALTER TABLE %s RENAME COLUMN %I TO %I', reloid::text, gc.has_geom_name, const.geomcol);
    PERFORM @extschema@._CDB_SQL(sql,'_CDB_Rewrite_Table');
  END IF;

  -- If mercgeom is the wrong name, just rename it.
  IF gc.has_mercgeom AND gc.has_mercgeom_name != const.mercgeomcol THEN
    sql := Format('ALTER TABLE %s DROP COLUMN IF EXISTS %I', reloid::text, const.mercgeomcol);
    PERFORM @extschema@._CDB_SQL(sql,'_CDB_Rewrite_Table');
    sql := Format('ALTER TABLE %s RENAME COLUMN %I TO %I', reloid::text, gc.has_mercgeom_name, const.mercgeomcol);
    PERFORM @extschema@._CDB_SQL(sql,'_CDB_Rewrite_Table');
  END IF;


  RAISE DEBUG 'CDB(_CDB_Rewrite_Table): has_usable_geoms %', gc.has_usable_geoms;

  -- We can only avoid a rewrite if both the key and
  -- geometry are usable

  -- No table re-write is required, BUT a rename is required to
  -- a destination schema, so do that now
  IF has_usable_primary_key AND has_usable_pk_sequence AND gc.has_usable_geoms THEN
    IF  destschema != relschema THEN

      RAISE DEBUG 'CDB(_CDB_Rewrite_Table): perfect table needs to be moved to schema (%)', destschema;
      PERFORM @extschema@._CDB_SQL(Format('ALTER TABLE %s SET SCHEMA %I', reloid::text, destschema), '_CDB_Rewrite_Table');

    ELSE

      RAISE DEBUG 'CDB(_CDB_Rewrite_Table): perfect table in the perfect place';

    END IF;

    RETURN true;

  END IF;

  -- We must rewrite, so here we go...

  -- Our desired PK sequence name

  -- We are going to drop the source table when we're done anyways
  -- but it's possible the source PK sequence is living in a name we would like to use
  -- so we check to see if that's the case, and rename it out of the way
  IF has_usable_primary_key AND has_usable_pk_sequence THEN
    -- See if the existing sequence is squatting on our preferred name
    destseq := Format('%s_%s_seq', relname, const.pkey);
    SELECT pg_catalog.pg_get_serial_sequence(Format('%I.%I', relschema, relname), const.pkey)
      INTO relseq;
    -- If it's the name we want, then rename it
    IF relseq IS NOT NULL AND relseq = Format('%I.%I', destschema, destseq) THEN
      PERFORM @extschema@._CDB_SQL(Format('ALTER SEQUENCE %s RENAME TO %I', relseq, Format('tmp_%s', destseq)), '_CDB_Rewrite_Table');
    END IF;
  END IF;

  -- Put the primary key sequence in the right schema
  -- If the new table is not moving, better ensure the sequence name
  -- is unique
  destseq := @extschema@._CDB_Unique_Identifier(NULL, relname, '_' || const.pkey || '_seq', destschema);
  destseq := Format('%I.%I', destschema, destseq);
  PERFORM @extschema@._CDB_SQL(Format('CREATE SEQUENCE %s', destseq), '_CDB_Rewrite_Table');

  -- Temporary table name if we are re-writing in place
  -- Note copyname is already escaped and safe to use as identifier
  IF destschema = relschema THEN
    copyname := Format('%I.%I', destschema, @extschema@._CDB_Unique_Identifier(NULL, destname, NULL), destschema);
  ELSE
    copyname := Format('%I.%I', destschema, destname);
  END IF;

  -- Start building the SQL!
  sql := Format('CREATE TABLE %s AS SELECT ', copyname);

  -- Add cartodb ID!
  IF has_usable_primary_key THEN
    sql := sql || const.pkey || '::integer ';
  ELSE
    sql := sql || 'nextval(''' || destseq || ''') AS ' || const.pkey;
  END IF;

  -- Add the geometry columns!
  IF gc.has_usable_geoms THEN
    sql := sql || ',' || const.geomcol || ',' || const.mercgeomcol;
  ELSE

    -- Arg, this "geometry" column is actually text!!
    -- OK, we tested back in our geometry column research that it could
    -- be safely cast to geometry, so let's do that.
    IF gc.text_geom_column THEN

      WITH t AS (
        SELECT
          a.attname,
          CASE WHEN NOT gc.text_geom_column_srid THEN 'ST_SetSRID(' ELSE '' END AS missing_srid_start,
          CASE WHEN NOT gc.text_geom_column_srid THEN ',4326)' ELSE '' END AS missing_srid_end
        FROM pg_class c
        JOIN pg_attribute a ON a.attrelid = c.oid
        JOIN pg_type t ON a.atttypid = t.oid
        WHERE c.oid = reloid
        AND t.typname IN ('text','varchar','char')
        AND a.attnum > 0
        AND a.attname = gc.text_geom_column_name
        AND NOT a.attisdropped
        ORDER BY a.attnum
        LIMIT 1
      )
      SELECT ', @postgisschema@.ST_Transform('
            || t.missing_srid_start || t.attname || '::geometry' || t.missing_srid_end
            || ',4326)::Geometry(GEOMETRY,4326) AS '
            || const.geomcol
            || ', @extschema@.CDB_TransformToWebmercator('
            || t.missing_srid_start || t.attname || '::geometry' || t.missing_srid_end
            || ')::Geometry(GEOMETRY,3857) AS '
            || const.mercgeomcol,
            t.attname
      INTO geom_transform_sql, geom_column_source
      FROM t;

      IF NOT FOUND THEN
        -- We checked that this column existed already, it bloody well
        -- better be found.
        RAISE EXCEPTION 'CDB(_CDB_Rewrite_Table): Text column % is missing!', gc.text_geom_column_name;
      ELSE
        sql := sql || geom_transform_sql;
      END IF;

    -- There is at least one true geometry column in here, we'll
    -- reproject that into the projections we need.
    ELSE

      -- Find the column we are going to be working with (the first
      -- column with type "geometry")
      SELECT a.attname
      INTO rec
      FROM pg_class c
      JOIN pg_attribute a ON a.attrelid = c.oid
      JOIN pg_type t ON a.atttypid = t.oid
      WHERE c.oid = reloid
      AND t.typname = 'geometry'
      AND a.attnum > 0
      AND NOT a.attisdropped
      ORDER BY a.attnum
      LIMIT 1;

      -- The SRID could be undeclared at the table level, but still
      -- exist in the geometries themselves. We first find our geometry
      -- column and read the first SRID off it it, if there is a row
      -- to read.
      IF FOUND THEN
        EXECUTE Format('SELECT @postgisschema@.ST_SRID(%s) AS srid FROM %s LIMIT 1', rec.attname, reloid::text)
        INTO geom_srid;
      ELSE
        geom_srid := 0;
      END IF;

      -- The geometry columns weren't in the right projection,
      -- so we need to find the first decent geometry column
      -- in the table and wrap it in two transforms, one to 4326
      -- and another to 3857. Then remember its name so we can
      -- ignore it when we build the list of other columns to
      -- add to the output table
      WITH t AS (
        SELECT
          a.attname,
          postgis_typmod_type(a.atttypmod) AS geomtype,
          CASE WHEN postgis_typmod_srid(a.atttypmod) = 0 AND srid.srid = 0 THEN '@postgisschema@.ST_SetSRID(' ELSE '' END AS missing_srid_start,
          CASE WHEN postgis_typmod_srid(a.atttypmod) = 0 AND srid.srid = 0 THEN ',4326)' ELSE '' END AS missing_srid_end
        FROM pg_class c
        JOIN pg_attribute a ON a.attrelid = c.oid
        JOIN pg_type t ON a.atttypid = t.oid,
        ( SELECT geom_srid AS srid ) AS srid
        WHERE c.oid = reloid
        AND t.typname = 'geometry'
        AND a.attnum > 0
        AND NOT a.attisdropped
        ORDER BY a.attnum
        LIMIT 1
      )
      SELECT ', @postgisschema@.ST_Transform('
            || t.missing_srid_start || t.attname || t.missing_srid_end
            || ',4326)::Geometry(GEOMETRY,4326) AS '
            || const.geomcol
            || ', @extschema@.CDB_TransformToWebmercator('
            || t.missing_srid_start || t.attname || t.missing_srid_end
            || ')::Geometry(GEOMETRY,3857) AS '
            || const.mercgeomcol,
            t.attname
      INTO geom_transform_sql, geom_column_source
      FROM t;

      IF NOT FOUND THEN
        -- If there are no geometry columns, we continue making a
        -- non-spatial table. This is important for folks who want
        -- their tables to invalidate the SQL API
        -- cache on update/insert/delete.
        geom_column_source := '';
        sql := sql || ',NULL::geometry(Geometry,4326) AS ' || const.geomcol;
        sql := sql || ',NULL::geometry(Geometry,3857) AS ' || const.mercgeomcol;
      ELSE
        sql := sql || geom_transform_sql;
      END IF;

    END IF;

  END IF;

  -- Add now add all the rest of the columns
  -- by selecting their names into an array and
  -- joining the array with a comma
  SELECT
    ',' || array_to_string(array_agg(Format('%I',a.attname)),',') AS column_name_sql,
    Count(*) AS count
  INTO rec
  FROM pg_class c
  JOIN pg_attribute a ON a.attrelid = c.oid
  JOIN pg_type t ON a.atttypid = t.oid
  WHERE c.oid = reloid
  AND a.attnum > 0
  AND a.attname NOT IN (const.geomcol, const.mercgeomcol, const.pkey, geom_column_source)
  AND NOT a.attisdropped;


  -- No non-cartodb columns? Possible, I guess.
  IF rec.count = 0 THEN
    RAISE DEBUG 'CDB(_CDB_Rewrite_Table): %', 'found no extra columns';
    column_name_sql := '';
  ELSE
    RAISE DEBUG 'CDB(_CDB_Rewrite_Table): %', Format('found extra columns columns ''%s''', rec.column_name_sql);
    column_name_sql := rec.column_name_sql;
  END IF;

  -- Add the source table to the SQL
  sql := sql || column_name_sql || ' FROM ' || reloid::text;
  RAISE DEBUG 'CDB(_CDB_Rewrite_Table): %', sql;

  -- Run it!
  PERFORM @extschema@._CDB_SQL(sql, '_CDB_Rewrite_Table');

  -- Set up the primary key sequence
  -- If we copied the primary key from the original data, we need
  -- to set the sequence to the maximum value of that key
  EXECUTE Format('SELECT max(%s) FROM %s',
          const.pkey, copyname)
     INTO destseqmax;

  IF destseqmax IS NOT NULL THEN
    PERFORM @extschema@._CDB_SQL(Format('SELECT setval(''%s'', %s)', destseq, destseqmax), '_CDB_Rewrite_Table');
  END IF;

   -- Make the primary key use the sequence as its default value
  sql := Format('ALTER TABLE %s ALTER COLUMN %s SET DEFAULT nextval(''%s'')',
          copyname, const.pkey, destseq);
  PERFORM @extschema@._CDB_SQL(sql, '_CDB_Rewrite_Table');

  -- Make the sequence owned by the table, so when the table drops,
  -- the sequence does too
  sql := Format('ALTER SEQUENCE %s OWNED BY %s.%s', destseq, copyname, const.pkey);
  PERFORM @extschema@._CDB_SQL(sql,'_CDB_Rewrite_Table');


  -- We just made a copy, so we can drop the original now
  sql := Format('DROP TABLE %s', reloid::text);
  PERFORM @extschema@._CDB_SQL(sql, '_CDB_Rewrite_Table');

  -- If the table is being created by a SECURITY DEFINER function
  -- make sure the user is set back to the user who is connected
  IF current_user != session_user THEN
    sql := Format('ALTER TABLE IF EXISTS %s OWNER TO %s', copyname, session_user);
    PERFORM @extschema@._CDB_SQL(sql, '_CDB_Rewrite_Table');
    sql := Format('ALTER SEQUENCE IF EXISTS %s OWNER TO %s', destseq, session_user);
    PERFORM @extschema@._CDB_SQL(sql, '_CDB_Rewrite_Table');
  END IF;

  -- If we used a temporary destination table
  -- we can now rename it into place
  IF destschema = relschema THEN
    sql := Format('ALTER TABLE %s RENAME TO %I', copyname, destname);
    PERFORM @extschema@._CDB_SQL(sql, '_CDB_Rewrite_Table');
  END IF;

  RETURN true;

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;


-- Assumes the table already has the right metadata columns
-- (primary key and two geometry columns) and adds primary key
-- and geometry indexes if necessary.
CREATE OR REPLACE FUNCTION @extschema@._CDB_Add_Indexes(reloid REGCLASS)
  RETURNS BOOLEAN
AS $$
DECLARE
  rec RECORD;
  const RECORD;
  iname TEXT;
  sql TEXT;
  relname TEXT;
BEGIN

  RAISE DEBUG 'CDB(_CDB_Add_Indexes): %', 'entered function';

  -- Read CartoDB standard column names in
  const := @extschema@._CDB_Columns();

  -- Extract just the relname to use for the index names
  SELECT c.relname
  INTO STRICT relname
  FROM pg_class c
  WHERE c.oid = reloid;

  -- Is there already a primary key on this table for
  -- a column other than our chosen primary key?
  SELECT ci.relname AS pkey
  INTO rec
  FROM pg_class c
  JOIN pg_attribute a ON a.attrelid = c.oid
  LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
  JOIN pg_class ci ON i.indexrelid = ci.oid
  WHERE c.oid = reloid
  AND NOT a.attisdropped
  AND a.attname != const.pkey
  AND i.indisprimary;

  -- Yes? Then drop it, we're adding our own PK to the column
  -- we prefer.
  IF FOUND THEN
    RAISE DEBUG 'CDB(_CDB_Add_Indexes): dropping unwanted primary key ''%''', rec.pkey;
    sql := Format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %s', reloid::text, rec.pkey);
    PERFORM @extschema@._CDB_SQL(sql, '_CDB_Add_Indexes');
  END IF;


  -- Is the default primary key flagged as primary?
  SELECT a.attname
  INTO rec
  FROM pg_class c
  JOIN pg_attribute a ON a.attrelid = c.oid
  JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
  JOIN pg_class ci ON ci.oid = i.indexrelid
  WHERE attnum > 0
  AND c.oid = reloid
  AND a.attname = const.pkey
  AND i.indisprimary
  AND i.indisunique
  AND NOT attisdropped;

  -- No primary key? Add one.
  IF NOT FOUND THEN
    sql := Format('ALTER TABLE %s ADD PRIMARY KEY (%s)', reloid::text, const.pkey);
    PERFORM @extschema@._CDB_SQL(sql, '_CDB_Add_Indexes');
  END IF;

  -- Add geometry indexes to all "special geometry columns" that
  -- don't have one (either have no index at all, or have a non-GIST index)
  FOR rec IN
    SELECT a.attname, n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND attnum > 0
    LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE NOT attisdropped
    AND a.attname IN (const.geomcol, const.mercgeomcol)
    AND c.oid = reloid
    AND i.indexrelid IS NULL
    UNION
    SELECT a.attname, n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND attnum > 0
    JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
    JOIN pg_class ci ON ci.oid = i.indexrelid
    JOIN pg_am am ON ci.relam = am.oid
    WHERE NOT attisdropped
    AND a.attname IN (const.geomcol, const.mercgeomcol)
    AND c.oid = reloid
    AND am.amname != 'gist'
  LOOP
    sql := Format('CREATE INDEX ON %s USING GIST (%s)', reloid::text, rec.attname);
    PERFORM @extschema@._CDB_SQL(sql, '_CDB_Add_Indexes');
  END LOOP;

  RETURN true;

END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;

DROP FUNCTION IF EXISTS @extschema@.CDB_CartodbfyTable(destschema TEXT, reloid REGCLASS);
CREATE OR REPLACE FUNCTION @extschema@.CDB_CartodbfyTable(destschema TEXT, reloid REGCLASS)
RETURNS REGCLASS
AS $$
DECLARE

  is_raster BOOLEAN;
  relname TEXT;
  relschema TEXT;

  destoid REGCLASS;
  destname TEXT;

  rec RECORD;

BEGIN

  -- Save the raw schema/table names for later
  SELECT n.nspname, c.relname, c.relname
  INTO STRICT relschema, relname, destname
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE c.oid = reloid;

  PERFORM @extschema@._CDB_check_prerequisites(destschema, reloid);

  -- Check destination schema exists
  -- Throws an exception of there is no matching schema
  IF destschema IS NOT NULL THEN

    SELECT n.nspname
    INTO rec FROM pg_namespace n WHERE n.nspname = destschema;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Schema ''%'' does not exist', destschema;
    END IF;

  ELSE
    destschema := relschema;
  END IF;

  -- Drop triggers first
  PERFORM @extschema@._CDB_drop_triggers(reloid);

  -- Rasters only get a cartodb_id and a limited selection of triggers
  -- underlying assumption is that they are already formed up correctly
  SELECT @extschema@._CDB_is_raster_table(destschema, reloid) INTO is_raster;
  IF is_raster THEN

    PERFORM @extschema@._CDB_create_cartodb_id_column(reloid);
    PERFORM @extschema@._CDB_create_raster_triggers(destschema, reloid);

  ELSE

    -- Rewrite (or rename) the table to the new location
    PERFORM @extschema@._CDB_Rewrite_Table(reloid, destschema);

    -- The old regclass might not be valid anymore if we re-wrote the table...
    destoid := (destschema || '.' || destname)::regclass;

    -- Add indexes to the destination table, as necessary
    PERFORM @extschema@._CDB_Add_Indexes(destoid);

    -- Add triggers to the destination table, as necessary
    PERFORM @extschema@._CDB_create_triggers(destschema, destoid);

  END IF;

  RETURN (destschema || '.' || destname)::regclass;
END;
$$ LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;
