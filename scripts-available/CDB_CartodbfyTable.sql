-- Depends on:
--   * CDB_ExtensionUtils.sql
--   * CDB_TransformToWebmercator.sql
--   * CDB_TableMetadata.sql
--   * CDB_Quota.sql
--   * _CDB_UserQuotaInBytes() function, installed by rails
--     (user.rebuild_quota_trigger, called by rake task cartodb:db:update_test_quota_trigger)

-- 1) Required checks before running cartodbfication
-- Either will pass silenty or raise an exception
CREATE OR REPLACE FUNCTION _CDB_check_prerequisites(schema_name TEXT, reloid REGCLASS)
RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
  IF cartodb.schema_exists(schema_name) = false THEN
    RAISE EXCEPTION 'Invalid schema name "%"', schema_name;
  END IF;

  -- TODO: Check that user quota is set ?
  BEGIN
    EXECUTE FORMAT('SELECT %I._CDB_UserQuotaInBytes();', schema_name::text) INTO sql;
    EXCEPTION WHEN undefined_function THEN
      RAISE EXCEPTION 'Please set user quota before cartodbfying tables.';
  END;
END;
$$ LANGUAGE PLPGSQL;


-- 2) Drop cartodb triggers (might prevent changing columns)
CREATE OR REPLACE FUNCTION _CDB_drop_triggers(reloid REGCLASS)
  RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
  -- "track_updates"
  sql := 'DROP TRIGGER IF EXISTS track_updates ON ' || reloid::text;
  EXECUTE sql;

  -- "update_the_geom_webmercator"
  sql := 'DROP TRIGGER IF EXISTS update_the_geom_webmercator_trigger ON ' || reloid::text;
  EXECUTE sql;

  -- "update_updated_at"
  sql := 'DROP TRIGGER IF EXISTS update_updated_at_trigger ON ' || reloid::text;
  EXECUTE sql;

  -- "test_quota" and "test_quota_per_row"
  sql := 'DROP TRIGGER IF EXISTS test_quota ON ' || reloid::text;
  EXECUTE sql;
  sql := 'DROP TRIGGER IF EXISTS test_quota_per_row ON ' || reloid::text;
  EXECUTE sql;
END;
$$ LANGUAGE PLPGSQL;


-- 3) Cartodb_id creation & validation or renaming if invalid
CREATE OR REPLACE FUNCTION _CDB_create_cartodb_id_column(reloid REGCLASS)
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
      sql := 'ALTER TABLE ' || reloid::text || ' ADD cartodb_id SERIAL NOT NULL UNIQUE';
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
        sql := 'ALTER TABLE ' || reloid::text || ' ALTER COLUMN cartodb_id SET NOT NULL';
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
          sql := 'ALTER TABLE ' || reloid::text || ' RENAME COLUMN cartodb_id TO ' || new_name;
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
      sql := 'ALTER TABLE ' || reloid::text
             || ' ALTER cartodb_id TYPE int USING '
             || new_name || '::int4';
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql;

      -- Find max value
      sql := 'SELECT max(cartodb_id) FROM ' || reloid::text;
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql INTO rec;

      -- Find sequence name
      SELECT pg_catalog.pg_get_serial_sequence(reloid::text, 'cartodb_id')
        AS seq INTO rec2;

      -- Reset sequence name
      sql := 'ALTER SEQUENCE ' || rec2.seq::text
             || ' RESTART WITH ' || rec.max + 1;
      RAISE DEBUG 'Running %', sql;
      EXECUTE sql;

      -- Drop old column (all went fine if we got here)
      sql := 'ALTER TABLE ' || reloid::text || ' DROP ' || new_name;
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
    sql := 'ALTER TABLE ' || reloid::text || ' ADD PRIMARY KEY (cartodb_id)';
    EXECUTE sql;
    EXCEPTION
    WHEN others THEN
      RAISE DEBUG 'Table % Already had PRIMARY KEY', reloid;
  END;

END;
$$ LANGUAGE PLPGSQL;


-- 4) created_at and updated_at creation & validation or renaming if invalid
CREATE OR REPLACE FUNCTION _CDB_create_timestamp_columns(reloid REGCLASS)
  RETURNS void
AS $$
DECLARE
  sql TEXT;
  rec RECORD;
  rec2 RECORD;
  had_column BOOLEAN;
  i INTEGER;
  new_name TEXT;
BEGIN

  FOR rec IN SELECT * FROM ( VALUES ('created_at'), ('updated_at') ) t(cname)
  LOOP --{
    new_name := null;
    << column_setup >>
    LOOP --{
      had_column := FALSE;
      BEGIN
        sql := 'ALTER TABLE ' || reloid::text || ' ADD ' || rec.cname
               || ' TIMESTAMPTZ NOT NULL DEFAULT now()';
        RAISE DEBUG 'Running %', sql;
        EXECUTE sql;
        EXIT column_setup;
        EXCEPTION
        WHEN duplicate_column THEN
          RAISE NOTICE 'Column % already exists', rec.cname;
          had_column := TRUE;
        WHEN others THEN
          RAISE EXCEPTION 'Cartodbfying % (%): % (%)', reloid, rec.cname, SQLERRM, SQLSTATE;
      END;

      IF had_column THEN
        -- Check data type is a TIMESTAMP WITH TIMEZONE
        SELECT t.typname, t.oid, a.attnotnull FROM pg_type t, pg_attribute a
        WHERE a.atttypid = t.oid AND a.attrelid = reloid AND NOT a.attisdropped AND a.attname = rec.cname
        INTO STRICT rec2;
        IF rec2.oid NOT IN (1184) THEN -- timestamptz {
          RAISE NOTICE 'Existing % field is of invalid type % (need timestamptz), renaming', rec.cname, rec2.typname;
        ELSE -- }{
          -- Ensure data type is a TIMESTAMP WITH TIMEZONE
          sql := 'ALTER TABLE ' || reloid::text
                 || ' ALTER ' || rec.cname
                 || ' SET NOT NULL,'
                 || ' ALTER ' || rec.cname
                 || ' SET DEFAULT now()';
          BEGIN
            RAISE DEBUG 'Running %', sql;
            EXECUTE sql;
            EXIT column_setup;
            EXCEPTION
            WHEN not_null_violation THEN -- failed not-null
              RAISE NOTICE '%, renaming', SQLERRM;
            WHEN cannot_coerce THEN -- failed cast
              RAISE NOTICE '%, renaming', SQLERRM;
            WHEN others THEN
              RAISE EXCEPTION 'Cartodbfying % (%): % (%)', reloid, rec.cname, SQLERRM, SQLSTATE;
          END;
        END IF; -- }

        -- invalid column, need rename and re-create it
        i := 0;
        << rename_column >>
        LOOP --{
          new_name := '_' || rec.cname || i;
          BEGIN
            sql := 'ALTER TABLE ' || reloid::text || ' RENAME COLUMN ' || rec.cname || ' TO ' || new_name;
            RAISE DEBUG 'Running %', sql;
            EXECUTE sql;
            EXCEPTION
            WHEN duplicate_column THEN
              i := i+1;
              CONTINUE rename_column;
            WHEN others THEN
              RAISE EXCEPTION 'Cartodbfying % (renaming %): % (%)',
              reloid, rec.cname, SQLERRM, SQLSTATE;
          END;
          EXIT rename_column;
        END LOOP; --}
        CONTINUE column_setup;
      END IF;
    END LOOP; -- }

    -- Try to copy data from new name if possible
    IF new_name IS NOT NULL THEN -- {
      RAISE NOTICE 'Trying to recover data from % coumn', new_name;
      BEGIN
        -- Copy existing values to new field
        -- NOTE: using ALTER is a workaround to a PostgreSQL bug and is also known to be faster for tables with many rows
        -- See http://www.postgresql.org/message-id/20140530143150.GA11051@localhost
        sql := 'ALTER TABLE ' || reloid::text || ' ALTER ' || rec.cname
               || ' TYPE TIMESTAMPTZ USING '
               || new_name || '::timestamptz';
        RAISE DEBUG 'Running %', sql;
        EXECUTE sql;

        -- Drop old column (all went find if we got here)
        sql := 'ALTER TABLE ' || reloid::text || ' DROP ' || new_name;
        RAISE DEBUG 'Running %', sql;
        EXECUTE sql;

        EXCEPTION
        WHEN others THEN
          RAISE NOTICE 'Could not initialize % with existing values: % (%)', rec.cname, SQLERRM, SQLSTATE;
      END;
    END IF; -- }
  END LOOP; -- }

END;
$$ LANGUAGE PLPGSQL;


-- 5) the_geom and the_geom_webmercator creation & validation or renaming if invalid
CREATE OR REPLACE FUNCTION _CDB_create_the_geom_columns(reloid REGCLASS)
  RETURNS BOOLEAN[]
AS $$
DECLARE
  sql TEXT;
  rec RECORD;
  rec2 RECORD;
  had_column BOOLEAN;
  i INTEGER;
  new_name TEXT;
  exists_geom_cols BOOLEAN[];
BEGIN
  -- We need the_geom and the_geom_webmercator
  FOR rec IN SELECT * FROM ( VALUES ('the_geom',4326), ('the_geom_webmercator',3857) ) t(cname,csrid) LOOP --{
    << column_setup >> LOOP --{
      BEGIN
        sql := 'ALTER TABLE ' || reloid::text || ' ADD ' || rec.cname
               || ' GEOMETRY(geometry,' || rec.csrid || ')';
        RAISE DEBUG 'Running %', sql;
        EXECUTE sql;
        sql := 'CREATE INDEX ON ' || reloid::text || ' USING GIST ( ' || rec.cname || ')';
        RAISE DEBUG 'Running %', sql;
        EXECUTE sql;
        exists_geom_cols := array_append(exists_geom_cols, false);
        EXIT column_setup;
        EXCEPTION
        WHEN duplicate_column THEN
          exists_geom_cols := array_append(exists_geom_cols, true);
          RAISE NOTICE 'Column % already exists', rec.cname;
        WHEN others THEN
          RAISE EXCEPTION 'Cartodbfying % (%): % (%)', reloid, rec.cname, SQLERRM, SQLSTATE;
      END;

      << column_fixup >>
      LOOP --{
        -- Check data type is a GEOMETRY
        SELECT t.typname, t.oid, a.attnotnull,
          postgis_typmod_srid(a.atttypmod) as srid,
          postgis_typmod_type(a.atttypmod) as gtype
        FROM pg_type t, pg_attribute a
        WHERE a.atttypid = t.oid AND a.attrelid = reloid AND NOT a.attisdropped AND a.attname = rec.cname
        INTO STRICT rec2;

        IF rec2.typname NOT IN ('geometry') THEN -- {
          RAISE NOTICE 'Existing % field is of invalid type % (need geometry), renaming', rec.cname, rec2.typname;
          EXIT column_fixup; -- cannot fix
        END IF; -- }

        IF rec2.srid != rec.csrid THEN -- {
          BEGIN
            sql := 'ALTER TABLE ' || reloid::text || ' ALTER ' || rec.cname
                   || ' TYPE geometry(' || rec2.gtype || ',' || rec.csrid || ') USING ST_Transform('
                   || rec.cname || ',' || rec.csrid || ')';
            RAISE DEBUG 'Running %', sql;
            EXECUTE sql;
            EXCEPTION
            WHEN others THEN
              RAISE NOTICE 'Could not enforce SRID % to column %: %, renaming', rec.csrid, rec.cname, SQLERRM;
              EXIT column_fixup; -- cannot fix, will rename
          END;
        END IF; -- }

        -- add gist indices if not there already
        IF NOT EXISTS ( SELECT ir.relname
                        FROM pg_am am, pg_class ir,
                          pg_class c, pg_index i,
                          pg_attribute a
                        WHERE c.oid  = reloid AND i.indrelid = c.oid
                              AND a.attname = rec.cname
                              AND i.indexrelid = ir.oid AND i.indnatts = 1
                              AND i.indkey[0] = a.attnum AND a.attrelid = c.oid
                              AND NOT a.attisdropped AND am.oid = ir.relam
                              AND am.amname = 'gist' )
        THEN -- {
          BEGIN
            sql := 'CREATE INDEX ON ' || reloid::text || ' USING GIST ( ' || rec.cname || ')';
            RAISE DEBUG 'Running %', sql;
            EXECUTE sql;
            EXCEPTION
            WHEN others THEN
              RAISE EXCEPTION 'Cartodbfying % (% index): % (%)', reloid, rec.cname, SQLERRM, SQLSTATE;
          END;
        END IF; -- }

        -- if we reached this line, all went good
        EXIT column_setup;
      END LOOP; -- } column_fixup

      -- invalid column, need rename and re-create it
      i := 0;
      << rename_column >>
      LOOP --{
        new_name := '_' || rec.cname || i;
        BEGIN
          sql := 'ALTER TABLE ' || reloid::text || ' RENAME COLUMN ' || rec.cname || ' TO ' || new_name;
          RAISE DEBUG 'Running %', sql;
          EXECUTE sql;
          EXCEPTION
          WHEN duplicate_column THEN
            i := i+1;
            CONTINUE rename_column;
          WHEN others THEN
            RAISE EXCEPTION 'Cartodbfying % (rename %): % (%)', reloid, rec.cname, SQLERRM, SQLSTATE;
        END;
        EXIT rename_column;
      END LOOP; --}
      CONTINUE column_setup;
    END LOOP; -- } column_setup
  END LOOP; -- } on expected geometry columns

  RETURN exists_geom_cols;
END;
$$ LANGUAGE PLPGSQL;


-- 6) Initialize the_geom with values from the_geom_webmercator
-- do this only if the_geom_webmercator was found (not created) and the_geom was NOT found.
CREATE OR REPLACE FUNCTION _CDB_populate_the_geom_from_the_geom_webmercator(reloid REGCLASS, geom_columns_exist BOOLEAN[])
  RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
  IF geom_columns_exist[2] AND NOT geom_columns_exist[1] THEN
    sql := 'UPDATE ' || reloid::text || ' SET the_geom = ST_Transform(the_geom_webmercator, 4326) ';
    EXECUTE sql;
  END IF;
END;
$$ LANGUAGE PLPGSQL;


-- 7) Initialize the_geom_webmercator with values from the_geom
-- do this only if the_geom was found (not created) and the_geom_webmercator was NOT found.
CREATE OR REPLACE FUNCTION _CDB_populate_the_geom_webmercator_from_the_geom(reloid REGCLASS, geom_columns_exist BOOLEAN[])
  RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
  IF geom_columns_exist[1] AND NOT geom_columns_exist[2] THEN
    sql := 'UPDATE ' || reloid::text || ' SET the_geom_webmercator = public.CDB_TransformToWebmercator(the_geom) ';
    EXECUTE sql;
  END IF;
END;
$$ LANGUAGE PLPGSQL;


-- 8.a) Create all triggers
-- NOTE: drop/create has the side-effect of re-enabling disabled triggers
CREATE OR REPLACE FUNCTION _CDB_create_triggers(schema_name TEXT, reloid REGCLASS)
RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
-- "track_updates"
  sql := 'CREATE trigger track_updates AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON '
         || reloid::text
         || ' FOR EACH STATEMENT EXECUTE PROCEDURE public.cdb_tablemetadata_trigger()';
  EXECUTE sql;

-- "update_the_geom_webmercator"
-- TODO: why _before_ and not after ?
  sql := 'CREATE trigger update_the_geom_webmercator_trigger BEFORE INSERT OR UPDATE OF the_geom ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE public._CDB_update_the_geom_webmercator()';
  EXECUTE sql;

-- "update_updated_at"
-- TODO: why _before_ and not after ?
  sql := 'CREATE trigger update_updated_at_trigger BEFORE UPDATE ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE public._CDB_update_updated_at()';
  EXECUTE sql;

-- "test_quota" and "test_quota_per_row"

  sql := 'CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' EXECUTE PROCEDURE public.CDB_CheckQuota(1, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;

  sql := 'CREATE TRIGGER test_quota_per_row BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE public.CDB_CheckQuota(0.001, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;
END;
$$ LANGUAGE PLPGSQL;

-- 8.b) Create all raster triggers
-- NOTE: drop/create has the side-effect of re-enabling disabled triggers
CREATE OR REPLACE FUNCTION _CDB_create_raster_triggers(schema_name TEXT, reloid REGCLASS)
  RETURNS void
AS $$
DECLARE
  sql TEXT;
BEGIN
-- "track_updates"
  sql := 'CREATE trigger track_updates AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON '
         || reloid::text
         || ' FOR EACH STATEMENT EXECUTE PROCEDURE public.cdb_tablemetadata_trigger()';
  EXECUTE sql;

-- "update_updated_at"
-- TODO: why _before_ and not after ?
  sql := 'CREATE trigger update_updated_at_trigger BEFORE UPDATE ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE public._CDB_update_updated_at()';
  EXECUTE sql;

-- "test_quota" and "test_quota_per_row"

  sql := 'CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' EXECUTE PROCEDURE public.CDB_CheckQuota(1, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;

  sql := 'CREATE TRIGGER test_quota_per_row BEFORE UPDATE OR INSERT ON '
         || reloid::text
         || ' FOR EACH ROW EXECUTE PROCEDURE public.CDB_CheckQuota(0.001, ''-1'', '''
         || schema_name::text
         || ''')';
  EXECUTE sql;
END;
$$ LANGUAGE PLPGSQL;



-- Update the_geom_webmercator
CREATE OR REPLACE FUNCTION _CDB_update_the_geom_webmercator()
  RETURNS trigger
AS $$
BEGIN
  NEW.the_geom_webmercator := public.CDB_TransformToWebmercator(NEW.the_geom);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION _CDB_update_updated_at()
  RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at := now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- Auxiliary function
CREATE OR REPLACE FUNCTION cartodb._CDB_is_raster_table(schema_name TEXT, reloid REGCLASS)
  RETURNS BOOLEAN
AS $$
DECLARE
  sql TEXT;
  is_raster BOOLEAN;
  rel_name TEXT;
BEGIN
  IF cartodb.schema_exists(schema_name) = FALSE THEN
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
$$ LANGUAGE PLPGSQL;



-- ////////////////////////////////////////////////////

-- Ensure a table is a "cartodb" table (See https://github.com/CartoDB/cartodb/wiki/CartoDB-user-table)
-- Rails code replicates this call at User.cartodbfy()
CREATE OR REPLACE FUNCTION CDB_CartodbfyTable(schema_name TEXT, reloid REGCLASS)
RETURNS void 
AS $$
DECLARE
  exists_geom_cols BOOLEAN[];
  is_raster BOOLEAN;
BEGIN

  PERFORM cartodb._CDB_check_prerequisites(schema_name, reloid);

  PERFORM cartodb._CDB_drop_triggers(reloid);

  -- Ensure required fields exist
  PERFORM cartodb._CDB_create_cartodb_id_column(reloid);
  PERFORM cartodb._CDB_create_timestamp_columns(reloid);

  SELECT cartodb._CDB_is_raster_table(schema_name, reloid) INTO is_raster;
  IF is_raster THEN
    PERFORM cartodb._CDB_create_raster_triggers(schema_name, reloid);
  ELSE
    SELECT cartodb._CDB_create_the_geom_columns(reloid) INTO exists_geom_cols;

    -- Both only populate if proceeds
    PERFORM cartodb._CDB_populate_the_geom_from_the_geom_webmercator(reloid, exists_geom_cols);
    PERFORM cartodb._CDB_populate_the_geom_webmercator_from_the_geom(reloid, exists_geom_cols);

    PERFORM cartodb._CDB_create_triggers(schema_name, reloid);
  END IF;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION CDB_CartodbfyTable(reloid REGCLASS)
RETURNS void
AS $$
BEGIN
  PERFORM cartodb.CDB_CartodbfyTable('public', reloid);
END;
$$ LANGUAGE PLPGSQL;


-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
--
--    NEW CARTODBFY CODE FROM HERE ON DOWN
--
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
--
--  CDB_CartodbfyTable2(reloid REGCLASS, destschema TEXT DEFAULT NULL)
--    
--     Main function, calls the following functions, with a little
--     logic before the table re-write to avoid re-writing if the table
--     already has all the necessary columns in place.
--
-- (1) _CDB_drop_triggers
--     As before, this drops all the metadata and geom sync triggers
--
-- (2) _CDB_Has_Usable_Primary_ID()
--     Returns TRUE if it can find a unique integer primary key named
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



-- Find out if the table already has a usable primary key
-- If the table has both a usable key and usable geometry
-- we can no-op on the table copy and just ensure that the 
-- indexes and triggers are in place
CREATE OR REPLACE FUNCTION _CDB_Has_Usable_Primary_ID(reloid REGCLASS, keyname TEXT)
  RETURNS BOOLEAN
AS $$
DECLARE
  rec RECORD;
  i INTEGER;
  sql TEXT;
BEGIN

  RAISE DEBUG 'Entered _CDB_Has_Usable_Primary_ID';

  -- Do we already have a properly named column?
  SELECT a.attname, i.indisprimary, i.indisunique, a.attnotnull, a.atttypid
  INTO rec
  FROM pg_class c 
  JOIN pg_attribute a ON a.attrelid = c.oid 
  JOIN pg_type t ON a.atttypid = t.oid
  LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE c.oid = reloid 
  AND NOT a.attisdropped
  AND a.attname = keyname;

  -- It's perfect (named right, right type, right index)!
  IF FOUND AND rec.indisprimary AND rec.indisunique AND rec.attnotnull AND rec.atttypid IN (20,21,23) THEN
    RAISE DEBUG '_CDB_Has_Usable_Primary_ID found good ''%''', keyname;
    RETURN true;
  
  -- It's an integer and it's named 'cartodb_id' maybe it is usable
  -- ELSIF rec.atttypid IN (20,21,23) THEN
  
  
  
  -- It's not suitable (not an integer?, not unique?) to rename it out of the way
  ELSIF FOUND THEN
    RAISE DEBUG '_CDB_Has_Usable_Primary_ID found bad ''%'', renaming it', keyname;
    
    sql := Format('ALTER TABLE %s RENAME COLUMN %s TO %s', 
              reloid::text, rec.attname, _CDB_Unique_Column_Name(reloid, keyname));
    RAISE DEBUG '_CDB_Has_Usable_Primary_ID: %', sql;
    EXECUTE sql;        
    
  -- There's no column there named keyname
  ELSE

    -- Is there another suitable primary key already?
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
      EXECUTE Format('ALTER TABLE %s RENAME COLUMN %s TO %s', reloid::text, rec.attname, keyname);
      RAISE DEBUG '_CDB_Has_Usable_Primary_ID found acceptable primary key ''%s'', renaming to ''%''', rec.attname, keyname;
      RETURN true;
    ELSE
      RAISE DEBUG '_CDB_Has_Usable_Primary_ID found no useful column for ''%''', keyname;
    END IF;
  
  END IF;

  -- Remove any unsuitable primary key constraint that is hanging around, 
  -- because we will be adding one back later
  SELECT ci.relname AS pkey
  INTO rec
  FROM pg_class c 
  JOIN pg_attribute a ON a.attrelid = c.oid 
  LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
  JOIN pg_class ci ON i.indexrelid = ci.oid
  WHERE c.oid = reloid AND NOT a.attisdropped
  AND a.attname != keyname
  AND i.indisprimary AND a.atttypid NOT IN (20,21,23);
  
  IF FOUND THEN
    EXECUTE Format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %s', reloid::text, rec.pkey);
    RAISE DEBUG '_CDB_Has_Usable_Primary_ID dropping unused primary key ''%''', rec.pkey;
  END IF;
  
  RAISE DEBUG '_CDB_Has_Usable_Primary_ID completed';
  
  -- Didn't fine re-usable key, so return FALSE
  RETURN false;

END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION _CDB_Unique_Relation_Name(schemaname TEXT, relationname TEXT)
RETURNS TEXT
AS $$
DECLARE
  rec RECORD;
  i INTEGER;
  newrelname TEXT;
BEGIN

  i := 0;
  newrelname := relationname;
  LOOP

    SELECT c.relname, n.nspname
    INTO rec
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = newrelname
    AND n.nspname = schemaname;
  
    IF NOT FOUND THEN
      RETURN newrelname;
    END IF;
    
    i := i + 1;
    newrelname := relationname || '_' || i;
  
    IF i > 100 THEN
      RAISE EXCEPTION '_CDB_Unique_Relation_Name looping too far';
    END IF;
  
  END LOOP;
  
END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION _CDB_Unique_Column_Name(reloid REGCLASS, columnname TEXT)
RETURNS TEXT
AS $$
DECLARE
  rec RECORD;
  i INTEGER;
  newcolname TEXT;
BEGIN

  i := 0;
  newcolname := columnname;
  LOOP

    SELECT a.attname
    INTO rec
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE NOT a.attisdropped
    AND a.attnum > 0
    AND c.oid = reloid
    AND a.attname = newcolname;
  
    IF NOT FOUND THEN
      RETURN newcolname;
    END IF;
    
    i := i + 1;
    newcolname := columnname || '_' || i;
  
    IF i > 100 THEN
      RAISE EXCEPTION '_CDB_Unique_Column_Name looping too far';
    END IF;
  
  END LOOP;
  
END;
$$ LANGUAGE 'plpgsql';
    

CREATE OR REPLACE FUNCTION _CDB_Geometry_SRID(reloid REGCLASS, columnname TEXT)
RETURNS INTEGER
AS $$
DECLARE
  rec RECORD;
BEGIN

  RAISE DEBUG '_CDB_Geometry_SRID, entered';
  
  EXECUTE Format('SELECT ST_SRID(%s) AS srid FROM %s LIMIT 1', columnname, reloid::text)
  INTO rec;

  IF FOUND THEN 
    RETURN rec.srid;
  ELSE
    RETURN 0;
  END IF;
  
END;
$$ LANGUAGE 'plpgsql';



CREATE OR REPLACE FUNCTION _CDB_Has_Usable_Geom(reloid REGCLASS, geom_name TEXT, mercgeom_name TEXT)
  RETURNS BOOLEAN
AS $$
DECLARE
  r1 RECORD;
  r2 RECORD;
  found_geom BOOLEAN := false;
  has_geom BOOLEAN := false;
  has_mercgeom BOOLEAN := false;
  str TEXT;
BEGIN

  RAISE DEBUG 'Entered _CDB_Has_Usable_Geom';

  -- Do we have a column we can use?
  FOR r1 IN
    SELECT 
    a.attname, 
    CASE WHEN t.typname = 'geometry' THEN postgis_typmod_srid(a.atttypmod) ELSE NULL END AS srid,
    t.typname,
    f.desired_attname, f.desired_srid
    FROM pg_class c 
    JOIN pg_attribute a ON a.attrelid = c.oid 
    JOIN pg_type t ON a.atttypid = t.oid,
    (VALUES (geom_name, 4326), (mercgeom_name, 3857) ) as f(desired_attname, desired_srid)
    WHERE c.oid = reloid
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND postgis_typmod_srid(a.atttypmod) IN (4326, 3857, 0)
    ORDER BY t.oid ASC
  LOOP
  
    RAISE DEBUG '_CDB_Has_Usable_Geom, checking ''%''', r1.attname;
    found_geom := false;

    -- Name collision: right name but wrong type, rename it!
    IF r1.typname != 'geometry' AND r1.attname = r1.desired_attname THEN
      str := _CDB_Unique_Column_Name(reloid, r1.attname);
      EXECUTE Format('ALTER TABLE %s RENAME COLUMN %s TO %s', reloid::text, r1.attname, str);
      RAISE DEBUG '_CDB_Has_Usable_Geom: % is the wrong type, renamed to %', r1.attname, str;

    -- Found a geometry column!
    ELSIF r1.typname = 'geometry' THEN

      -- If it's the right SRID, we can use it in place without
      -- transforming it!
      IF r1.srid = r1.desired_srid OR _CDB_Geometry_SRID(reloid, r1.attname) = r1.desired_srid THEN
        RAISE DEBUG '_CDB_Has_Usable_Geom found acceptable ''%''', r1.attname;

        -- If it's the wrong name, just rename it.
        IF r1.attname != r1.desired_attname THEN
          EXECUTE Format('ALTER TABLE %s RENAME COLUMN %s TO %s', reloid::text, r1.attname, r1.desired_attname);
          RAISE DEBUG '_CDB_Has_Usable_Geom renamed % to %', r1.attname, r1.desired_attname;
        END IF;

        IF r1.desired_attname = geom_name THEN
          has_geom = true;
        ELSIF r1.desired_attname = mercgeom_name THEN
          has_mercgeom = true;
        END IF;
        
      END IF;
      
    END IF;
    
  END LOOP;
  
  -- If table is perfect (no transforms required), return TRUE!
  RETURN has_geom AND has_mercgeom;

END;
$$ LANGUAGE 'plpgsql';



CREATE OR REPLACE FUNCTION _CDB_Rewrite_Table(reloid REGCLASS, destschema TEXT, has_usable_primary_key BOOLEAN, has_usable_geoms BOOLEAN, geom_name TEXT, mercgeom_name TEXT, primary_key_name TEXT)
RETURNS BOOLEAN
AS $$
DECLARE

  relname TEXT;
  relschema TEXT;

  destoid REGCLASS;
  destname TEXT;
  destseq TEXT;
  destseqmax INTEGER;
    
  salt TEXT := md5(random()::text || now());
  copyname TEXT;

  column_name_sql TEXT;
  geom_transform_sql TEXT := NULL;
  geom_column_source TEXT := '';

  rec RECORD;
  sql TEXT;
  str TEXT;
  
BEGIN

  RAISE DEBUG 'Entered _CDB_Rewrite_Table';

  -- Check calling convention
  IF has_usable_primary_key AND has_usable_geoms THEN
    RAISE EXCEPTION '_CDB_Rewrite_Table should not be called, it has good key and geoms';
  END IF;

  -- Save the raw schema/table names for later
  SELECT n.nspname, c.relname, c.relname
  INTO STRICT relschema, relname, destname
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid 
  WHERE c.oid = reloid;
  
  -- Put the primary key sequence in the right schema
  -- If the new table is not moving, better ensure the sequence name
  -- is unique
  destseq := relname || '_' || primary_key_name || '_seq';
  destseq := _CDB_Unique_Relation_Name(destschema, destseq);
  destseq := Format('%s.%s', destschema, destseq);
  EXECUTE Format('CREATE SEQUENCE %s', destseq);

  -- Salt a temporary table name if we are re-writing in place
  IF destschema = relschema THEN
    copyname := destschema || '.' || destname || '_' || salt;
  ELSE
    copyname := destschema || '.' || destname;
  END IF;
  
  -- Start building the SQL!
  sql := 'CREATE TABLE ' || copyname || ' AS SELECT ';

  -- Add cartodb ID!
  IF has_usable_primary_key THEN
    sql := sql || primary_key_name;
  ELSE
    sql := sql || 'nextval(''' || destseq || ''') AS ' || primary_key_name;
  END IF;

  -- Add the geometry columns!
  IF has_usable_geoms THEN
    sql := sql || ',' || geom_name || ',' || mercgeom_name;
  ELSE
    
    -- This gets complicated: we have to make sure the 
    -- geometry column we are using can be transformed into
    -- geographics, which means it needs to have a valid
    -- SRID.  
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
    
    IF NOT FOUND THEN
      -- If there is no geometry column, we continue making a 
      -- non-spatial table. This is important for folks who want
      -- their tables to invalidate the SQL API 
      -- cache on update/insert/delete.
      geom_column_source := '';

    ELSE

      EXECUTE Format('SELECT ST_SRID(%s) AS srid FROM %s LIMIT 1', rec.attname, reloid::text)
      INTO rec;
    
      -- The geometry columns weren't in the right projection,
      -- so we need to find the first decent geometry column
      -- in the table and wrap it in two transforms, one to 4326
      -- and another to 3857. Then remember its name so we can
      -- ignore it when we build the list of other columns to
      -- add to the output table
      SELECT ',ST_Transform(' 
        || a.attname 
        || ',4326)::Geometry(' 
        || postgis_typmod_type(a.atttypmod) 
        || ', 4326) AS '
        || geom_name 
        || ', ST_Transform(' 
        || a.attname 
        || ',3857)::Geometry('
        || postgis_typmod_type(a.atttypmod) 
        || ', 3857) AS '
        || mercgeom_name,
        a.attname
      INTO geom_transform_sql, geom_column_source
      FROM pg_class c 
      JOIN pg_attribute a ON a.attrelid = c.oid 
      JOIN pg_type t ON a.atttypid = t.oid,
      ( SELECT rec.srid AS srid ) AS srid
      WHERE c.oid = reloid
      AND t.typname = 'geometry'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND (postgis_typmod_srid(a.atttypmod) > 0 OR srid.srid > 0)
      ORDER BY a.attnum
      LIMIT 1;
    
      IF FOUND THEN
        sql := sql || geom_transform_sql;
      END IF;

    END IF;
    
  END IF;

  -- Add now add all the rest of the columns
  -- by selecting their names into an array and
  -- joining the array with a comma
  SELECT 
    ',' || array_to_string(array_agg(a.attname),',') AS column_name_sql, 
    Count(*) AS count
  INTO rec
  FROM pg_class c 
  JOIN pg_attribute a ON a.attrelid = c.oid 
  JOIN pg_type t ON a.atttypid = t.oid
  WHERE c.oid = reloid
  AND a.attnum > 0
  AND a.attname NOT IN (geom_name, mercgeom_name, primary_key_name, geom_column_source)
  AND NOT a.attisdropped;


  -- No non-cartodb columns? Possible, I guess.
  IF rec.count = 0 THEN
    RAISE DEBUG '_CDB_Rewrite_Table found no extra columns';
    column_name_sql := '';
  ELSE
    RAISE DEBUG '_CDB_Rewrite_Table found extra columns columns %', rec.column_name_sql;
    column_name_sql := rec.column_name_sql;
  END IF;

  -- Add the source table to the SQL
  sql := sql || column_name_sql || ' FROM ' || reloid::text;
  RAISE DEBUG '_CDB_Rewrite_Table generated SQL: %', sql;

  -- Run it!
  EXECUTE sql;
  
  -- Set up the primary key sequence
  -- If we copied the primary key from the original data, we need
  -- to set the sequence to the maximum value of that key
  IF has_usable_primary_key THEN

    EXECUTE Format('SELECT max(%s) FROM %s',
            primary_key_name, copyname)
       INTO destseqmax;

    IF FOUND AND destseqmax IS NOT NULL THEN
      EXECUTE Format('SELECT setval(''%s'', %s)', destseq, destseqmax);
    END IF;

  END IF;

  -- Make the primary key use the sequence as its default value
  sql := Format('ALTER TABLE %s ALTER COLUMN %I SET DEFAULT nextval(''%s'')', 
          copyname, primary_key_name, destseq);
  RAISE DEBUG '_CDB_Rewrite_Table: %', sql;
  EXECUTE sql;

  -- Make the sequence owned by the table, so when the table drops, 
  -- the sequence does too
  sql := Format('ALTER SEQUENCE %s OWNED BY %s.%s', destseq, copyname, primary_key_name);
  RAISE DEBUG '_CDB_Rewrite_Table: %', sql;
  EXECUTE sql;
  
  -- We just made a copy, so we can drop the original now
  sql := Format('DROP TABLE %s', reloid::text);
  RAISE DEBUG '_CDB_Rewrite_Table: %', sql;
  EXECUTE sql;
  
  -- If we used a temporary destination table
  -- we can now rename it into place
  IF destschema = relschema THEN
    sql := Format('ALTER TABLE %s RENAME TO %s', copyname, destname);
    RAISE DEBUG '_CDB_Rewrite_Table: %', sql;
    EXECUTE sql;
  END IF;

  RETURN true;

END;
$$ LANGUAGE 'plpgsql';



CREATE OR REPLACE FUNCTION _CDB_Add_Indexes(reloid REGCLASS, geom_name TEXT, mercgeom_name TEXT, primary_key_name TEXT)
  RETURNS BOOLEAN
AS $$
DECLARE
  rec RECORD;
  iname TEXT;
  sql TEXT;
  relname TEXT;
BEGIN

  RAISE DEBUG 'Entered _CDB_Add_Indexes';

  -- Extract just the relname to use for the index names
  SELECT c.relname
  INTO STRICT relname
  FROM pg_class c
  WHERE c.oid = reloid;

  -- Is the default primary key flagged as primary?
  SELECT a.attname
  INTO rec
  FROM pg_class c 
  JOIN pg_attribute a ON a.attrelid = c.oid 
  JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
  JOIN pg_class ci ON ci.oid = i.indexrelid
  WHERE attnum > 0 
  AND c.oid = reloid
  AND a.attname = primary_key_name
  AND i.indisprimary
  AND i.indisunique
  AND NOT attisdropped;
  
  -- No primary key? Add one.
  IF NOT FOUND THEN
    sql := Format('ALTER TABLE %s ADD PRIMARY KEY (%s)', reloid::text, primary_key_name);
    RAISE DEBUG '_CDB_Add_Indexes: %', sql;
    EXECUTE sql;
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
    AND a.attname IN (geom_name, mercgeom_name)
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
    AND a.attname IN (geom_name, mercgeom_name)
    AND c.oid = reloid
    AND am.amname != 'gist'
  LOOP
    sql := Format('CREATE INDEX %s_%s_gix ON %s USING GIST (%s)', relname, rec.attname, reloid::text, rec.attname);
    RAISE DEBUG '_CDB_Add_Indexes: %', sql;
    EXECUTE sql;
  END LOOP;
    
  RETURN true;

END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION CDB_CartodbfyTable2(reloid REGCLASS, destschema TEXT DEFAULT NULL)
RETURNS void 
AS $$
DECLARE
  -- Because we're going to change these some day, ha ha ha ha!
  geom_name TEXT := 'the_geom';
  mercgeom_name TEXT := 'the_geom_webmercator';
  primary_key_name TEXT := 'cartodb_id';
  
  relname TEXT;
  relschema TEXT;

  destoid REGCLASS;
  destname TEXT;

  has_usable_primary_key BOOLEAN;
  has_usable_geoms BOOLEAN;
  rewrite_success BOOLEAN;
  rewrite BOOLEAN;
  index_success BOOLEAN;
  rec RECORD;
BEGIN

  -- Save the raw schema/table names for later
  SELECT n.nspname, c.relname, c.relname
  INTO STRICT relschema, relname, destname
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid 
  WHERE c.oid = reloid;

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
  -- PERFORM _CDB_drop_triggers(reloid);
  
  -- See if there is a primary key column we need to carry along to the
  -- new table. If this is true, it implies there is an indexed
  -- primary key of integer type named (by default) cartodb_id
  SELECT _CDB_Has_Usable_Primary_ID(reloid, primary_key_name) AS has_usable_primary_key
  INTO STRICT has_usable_primary_key;

  -- See if the geometry columns we need are already available
  -- on the table. If they are, we don't need to do any bulk
  -- transformation of the table, we can just ensure proper
  -- indexes are in place and apply a rename
  SELECT _CDB_Has_Usable_Geom(reloid, geom_name, mercgeom_name) AS has_usable_geoms
  INTO STRICT has_usable_geoms;
  
  -- We can only avoid a rewrite if both the key and 
  -- geometry are usable
  rewrite := NOT (has_usable_primary_key AND has_usable_geoms);
  
  -- No table re-write is required, BUT a rename is required to 
  -- a destination schema, so do that now
  IF NOT rewrite AND destschema != relschema THEN
    
    RAISE DEBUG 'perfect table needs to be moved to schema (%)', destschema;
    EXECUTE Format('ALTER TABLE %s SET SCHEMA %s', reloid::text, destschema);

  -- Don't move anything, just make sure our destination information is set right
  ELSIF NOT rewrite AND destschema = relschema THEN

    RAISE DEBUG 'perfect table in the perfect place';
  
  -- We must rewrite, so here we go...
  ELSIF rewrite THEN

    SELECT _CDB_Rewrite_Table(reloid, destschema, has_usable_primary_key, has_usable_geoms, geom_name, mercgeom_name, primary_key_name)
    INTO STRICT rewrite_success;
    
    IF NOT rewrite_success THEN
      RAISE EXCEPTION 'Cartodbfying % (rewriting table): % (%)', reloid, SQLERRM, SQLSTATE;
    END IF;
      
  END IF;

  -- The old regclass might not be valid anymore if we re-wrote the table...
  destoid := (destschema || '.' || destname)::regclass;

  -- Add indexes to the destination table, as necessary
  SELECT _CDB_Add_Indexes(destoid, geom_name, mercgeom_name, primary_key_name)
  INTO STRICT index_success;

  IF NOT index_success THEN
    RAISE EXCEPTION 'Cartodbfying % (indexing table): % (%)', destoid, SQLERRM, SQLSTATE;
  END IF;
  
  -- Add triggers to the destination table, as necessary
  -- PERFORM _CDB_create_triggers(destschema, reloid);
  
  
END;
$$ LANGUAGE 'plpgsql';




