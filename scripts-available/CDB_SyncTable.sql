/*
   Gets the column names of a given table.

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
    Given an array of quoted column names, it generates an UPDATE SET
    clause with the following form:

        the_geom = changed.the_geom,
        id = changed.id,
        elevation = changed.elevation

    Example of usage:

       SELECT __CDB_GetUpdateSetClause('{the_geom, id, elevation}', 'changed');
*/
CREATE OR REPLACE FUNCTION __CDB_GetUpdateSetClause(colnames TEXT[], update_source TEXT)
RETURNS TEXT
AS $$
DECLARE
  set_clause_list TEXT[];
  col TEXT;
BEGIN
  FOREACH col IN ARRAY colnames
  LOOP
    set_clause_list := array_append(set_clause_list, format('%1$s = %2$s.%1$s', col, update_source));
  END lOOP;
  RETURN array_to_string(set_clause_list, ', ');
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;


/*
    Given a prefix, generate a safe unique NAME for a temp table.

    Example of usage:

       SELECT __CDB_GenerateUniqueName('src_sync'); --> src_sync_718794_120106

*/
CREATE OR REPLACE FUNCTION __CDB_GenerateUniqueName(prefix TEXT)
RETURNS NAME
AS $$
  SELECT format('%s_%s_%s', prefix, txid_current(), (random()*1000000)::int)::NAME;
$$ LANGUAGE sql VOLATILE PARALLEL UNSAFE;


/*
   A Table Syncer

   Assumptions:
     - Both tables contain a consistent cartodb_id column
     - Destination table has all columns of the source or does not exist

   Sample usage:

     SELECT CDB_SyncTable('radar_stations', 'public', 'syncdest');
     SELECT CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest', '{the_geom, the_geom_webmercator}');

*/
CREATE OR REPLACE FUNCTION CDB_SyncTable(src_table REGCLASS, dst_schema REGNAMESPACE, dst_table NAME, skip_cols NAME[] = '{}')
RETURNS void
AS $$
DECLARE
  fq_dest_table TEXT;

  colnames TEXT[];
  quoted_colnames TEXT;

  src_hash_table_name NAME;
  dst_hash_table_name NAME;

  update_set_clause TEXT;

  num_rows BIGINT;
  err_context text;

  t timestamptz;
BEGIN
  -- If the destination table does not exist, just copy the source table
  fq_dest_table := format('%I.%I', dst_schema, dst_table);
  EXECUTE format('CREATE TABLE IF NOT EXISTS %s as TABLE %I', fq_dest_table, src_table);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  IF num_rows > 0 THEN
    RAISE NOTICE 'INSERTED % row(s)', num_rows;
    RETURN;
  END IF;

  skip_cols := skip_cols || '{cartodb_id}';

  -- Get the list of columns from the source table, excluding skip_cols
  SELECT ARRAY(SELECT quote_ident(c) FROM _CDB_GetColumns(src_table) as c EXCEPT SELECT unnest(skip_cols)) INTO colnames;
  quoted_colnames := array_to_string(colnames, ',');

  src_hash_table_name := __CDB_GenerateUniqueName('src_sync');
  dst_hash_table_name := __CDB_GenerateUniqueName('dst_sync');

  EXECUTE format('CREATE TEMP TABLE %I(cartodb_id BIGINT, hash TEXT) ON COMMIT DROP', src_hash_table_name);
  EXECUTE format('CREATE TEMP TABLE %I(cartodb_id BIGINT, hash TEXT) ON COMMIT DROP', dst_hash_table_name);

  -- Compute hash tables for src_table and dst_table h[cartodb_id] = hash(row)
  -- It'll take the form of a temp table with an index (easy to run set operations)
  t := clock_timestamp();
  EXECUTE format('INSERT INTO %I SELECT cartodb_id, md5(ROW(%s)::text) hash FROM %I', src_hash_table_name, quoted_colnames, src_table);
  EXECUTE format('INSERT INTO %I SELECT cartodb_id, md5(ROW(%s)::text) hash FROM %s', dst_hash_table_name, quoted_colnames, fq_dest_table);
  RAISE DEBUG 'Populate hash tables time (s): %', clock_timestamp() - t;

  -- Create indexes
  -- We use hash indexes as they are fit for id comparison.
  t := clock_timestamp();
  EXECUTE format('CREATE INDEX ON %I USING HASH (cartodb_id)', src_hash_table_name);
  EXECUTE format('CREATE INDEX ON %I USING HASH (cartodb_id)', dst_hash_table_name);
  RAISE DEBUG 'Index creation on hash tables time (s): %', clock_timestamp() - t;

  -- Deal with deleted rows: ids in dest but not in source
  t := clock_timestamp();
  EXECUTE format(
    'DELETE FROM %s WHERE cartodb_id IN (SELECT cartodb_id FROM %I EXCEPT SELECT cartodb_id FROM %I)',
    fq_dest_table,
    dst_hash_table_name,
    src_hash_table_name);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  RAISE NOTICE 'DELETED % row(s)', num_rows;
  RAISE DEBUG 'DELETE time (s): %', clock_timestamp() - t;

  -- Deal with inserted rows: ids in source but not in dest
  t := clock_timestamp();
  EXECUTE format('
      INSERT INTO %s (cartodb_id,%s)
      SELECT h.cartodb_id,%s FROM (SELECT cartodb_id FROM %I EXCEPT SELECT cartodb_id FROM %I) h
      LEFT JOIN %I s ON s.cartodb_id = h.cartodb_id;
  ', fq_dest_table, quoted_colnames, quoted_colnames, src_hash_table_name, dst_hash_table_name, src_table);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  RAISE NOTICE 'INSERTED % row(s)', num_rows;
  RAISE DEBUG 'INSERT time (s): %', clock_timestamp() - t;

  -- Deal with modified rows: ids in source and dest but different hashes
  t := clock_timestamp();
  update_set_clause := __CDB_GetUpdateSetClause(colnames, 'changed');
  EXECUTE format('
    UPDATE %1$s dst SET %2$s
    FROM (
      SELECT *
      FROM %3$s src
      WHERE cartodb_id IN
        (SELECT sh.cartodb_id FROM %4$I sh
         LEFT JOIN %5$I dh ON sh.cartodb_id = dh.cartodb_id
         WHERE sh.hash <> dh.hash)
    ) changed
    WHERE dst.cartodb_id = changed.cartodb_id;
  ', fq_dest_table, update_set_clause, src_table, src_hash_table_name, dst_hash_table_name);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  RAISE NOTICE 'MODIFIED % row(s)', num_rows;
  RAISE DEBUG 'UPDATE time (s): %', clock_timestamp() - t;
END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;
