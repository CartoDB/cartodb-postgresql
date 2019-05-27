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

  update_set_clause TEXT;

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

    -- TODO create indexes

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
