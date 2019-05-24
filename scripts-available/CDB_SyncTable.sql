/*
   Sample usage:

     SELECT _CDB_GetColumns('public.films');
*/
CREATE OR REPLACE FUNCTION _CDB_GetColumns(src_table REGCLASS)
RETURNS SETOF NAME
AS $$
  SELECT
    a.attname as "colname"
  FROM
    pg_catalog.pg_attribute a
  WHERE
    a.attnum > 0
      AND NOT a.attisdropped
      AND a.attrelid = (
        SELECT c.oid
          FROM pg_catalog.pg_class c
          LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE c.oid = src_table::oid
            AND pg_catalog.pg_table_is_visible(c.oid)
      );
$$ LANGUAGE sql STABLE PARALLEL UNSAFE;


/*
   A Table Syncer

   Assumptions:
     - Both tables contain a consistent cartodb_id column
     - Destination table has all columns of the source

   Sample usage:

     SELECT CDB_SyncTable('radar_stations', 'public', 'syncdest');

*/
CREATE OR REPLACE FUNCTION CDB_SyncTable(src_table REGCLASS, dst_schema REGNAMESPACE, dst_table NAME)
RETURNS void
AS $$
DECLARE
  fq_dest_table TEXT;

  colnames TEXT[];
  quoted_colnames TEXT;

  src_hash_table_name NAME;
  dst_hash_table_name NAME;

  num_rows BIGINT;
  err_context text;
BEGIN
  -- If the destination table does not exist, just copy the source table
  fq_dest_table := format('%I.%I', dst_schema, dst_table);
  EXECUTE format('CREATE TABLE IF NOT EXISTS %s as TABLE %I', fq_dest_table, src_table);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  IF num_rows > 0 THEN
    RAISE NOTICE 'INSERTED % row(s)', num_rows;
    RETURN;
  END IF;

  -- Get the list of columns from the source table, excluding cartodb_id
  SELECT ARRAY(SELECT quote_ident(c) FROM _CDB_GetColumns(src_table) as c WHERE c <> 'cartodb_id') INTO colnames;
  quoted_colnames := array_to_string(colnames, ',');
  RAISE NOTICE 'quoted_colnames = %', quoted_colnames;

  src_hash_table_name := format('src_sync_%s', txid_current());
  dst_hash_table_name := format('dst_sync_%s', txid_current());

  BEGIN
    -- TODO: use ON COMMIT DROP instead of Cleanup
    EXECUTE format('CREATE TEMP TABLE %I(cartodb_id BIGINT, hash TEXT)', src_hash_table_name);
    EXECUTE format('CREATE TEMP TABLE %I(cartodb_id BIGINT, hash TEXT)', dst_hash_table_name);

    -- Compute hash for src_table h[cartodb_id] = hash(row)
    -- It'll take the form of a temp table with an index (easy to run set operations)
    EXECUTE format('INSERT INTO %I SELECT cartodb_id, md5(ROW(%s)::text) hash FROM %I', src_hash_table_name, quoted_colnames, src_table);

    -- Compute hash for dst_table, only for columns present in src_table
    EXECUTE format('INSERT INTO %I SELECT cartodb_id, md5(ROW(%s)::text) hash FROM %s', dst_hash_table_name, quoted_colnames, fq_dest_table);

    -- Deal with deleted rows: ids in dest but not in source
    EXECUTE format('DELETE FROM %s WHERE cartodb_id in (SELECT cartodb_id FROM %I WHERE cartodb_id NOT IN (SELECT cartodb_id FROM %I))', fq_dest_table, dst_hash_table_name, src_hash_table_name);
    GET DIAGNOSTICS num_rows = ROW_COUNT;
    RAISE NOTICE 'DELETED % row(s)', num_rows;

    -- Deal with inserted rows: ids in source but not in dest
    EXECUTE format('
        INSERT INTO %s (cartodb_id,%s)
        SELECT h.cartodb_id,%s FROM %I h
        LEFT JOIN %I s ON s.cartodb_id = h.cartodb_id
        WHERE h.cartodb_id NOT IN (SELECT cartodb_id FROM %I);
    ', fq_dest_table, quoted_colnames, quoted_colnames, src_hash_table_name, src_table, dst_hash_table_name);
    GET DIAGNOSTICS num_rows = ROW_COUNT;
    RAISE NOTICE 'INSERTED % row(s)', num_rows;

    -- Deal with modified rows: ids in source and dest but different hashes
    /*
      UPDATE syncdes dst SET
        the_geom = changed.the_geom,
        the_geom_webmercator = changed.the_geom_webmercator,
        id = changed.id,
        elevation = changed.elevation,
        latitude = changed.latitude,
        longitude = changed.longitude,
        name = changed.name
      FROM (
        SELECT cartodb_id,the_geom,the_geom_webmercator,id,elevation,latitude,longitude,name
        FROM radar_stations src
        WHERE cartodb_id IN
          (SELECT sh.cartodb_id FROM src_sync_615543 sh
           LEFT JOIN dst_sync_615543 dh ON sh.cartodb_id = dh.cartodb_id
           WHERE sh.hash <> dh.hash)
      ) changed
      WHERE dst.cartodb_id = changed.cartodb_id;
    */
    --GET DIAGNOSTICS num_rows = ROW_COUNT;
    --RAISE NOTICE 'MODIFIED % row(s)', num_rows;

    -- Cleanup
    --EXECUTE format('DROP TABLE IF EXISTS %I', src_hash_table_name);
    --EXECUTE format('DROP TABLE IF EXISTS %I', dst_hash_table_name);
  EXCEPTION
    WHEN others THEN
      -- Cleanup
      EXECUTE format('DROP TABLE IF EXISTS %I', src_hash_table_name);
      EXECUTE format('DROP TABLE IF EXISTS %I', dst_hash_table_name);

      -- Exception reporting
      GET STACKED DIAGNOSTICS err_context = PG_EXCEPTION_CONTEXT;
      RAISE INFO 'Error Name:%',SQLERRM;
      RAISE INFO 'Error State:%', SQLSTATE;
      RAISE INFO 'Error Context:%', err_context;
  END;

END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;
