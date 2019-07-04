/*
   Gets the column names of a given table.

   Sample usage:

     SELECT @extschema@._CDB_GetColumns('public.films');
*/
CREATE OR REPLACE FUNCTION @extschema@._CDB_GetColumns(src_table REGCLASS)
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
      )
  ORDER BY a.attnum;
$$ LANGUAGE sql STABLE PARALLEL UNSAFE;


/*
    Given an array of quoted column names, it generates an UPDATE SET
    clause with the following form:

        the_geom = changed.the_geom,
        id = changed.id,
        elevation = changed.elevation

    Example of usage:

       SELECT @extschema@.__CDB_GetUpdateSetClause('{the_geom, id, elevation}', 'changed');
*/
CREATE OR REPLACE FUNCTION @extschema@.__CDB_GetUpdateSetClause(colnames TEXT[], update_source TEXT)
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

       SELECT @extschema@.__CDB_GenerateUniqueName('src_sync'); --> src_sync_718794_120106

*/
CREATE OR REPLACE FUNCTION @extschema@.__CDB_GenerateUniqueName(prefix TEXT)
RETURNS NAME
AS $$
  SELECT format('%s_%s_%s', prefix, txid_current(), (random()*1000000)::int)::NAME;
$$ LANGUAGE sql VOLATILE PARALLEL UNSAFE;

/*
    Given a table name and an array of column names,
    return array of column names qualified with the table name and quoted when necessary
    tablename and colnames should be properly quoted, and for this reason the type NAME is not
    used for them (with quotes they could exceed the maximum identifier length)

    Example of usage:

       SELECT @extschema@.__CDB_QualifyColumns('t', ARRAY['a','"b-1"']); --> ARRAY['t.a','t."b-1"']

*/
CREATE OR REPLACE FUNCTION @extschema@.__CDB_QualifyColumns(tablename NAME, colnames NAME[]) RETURNS TEXT[] AS
$$
    SELECT array_agg(tablename || '.' || _colname) from unnest(colnames) _colname;
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

/*
   A Table Syncer

   Assumptions:
     - Both tables contain a consistent cartodb_id column
     - Destination table has all columns of the source or does not exist

   Sample usage:

     SELECT CDB_SyncTable('radar_stations', 'public', 'syncdest');
     SELECT CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest', '{the_geom, the_geom_webmercator}');

*/
CREATE OR REPLACE FUNCTION @extschema@.CDB_SyncTable(src_table REGCLASS, dst_schema REGNAMESPACE, dst_table NAME, skip_cols NAME[] = '{}')
RETURNS void
AS $$
DECLARE
  fq_dest_table TEXT;

  colnames TEXT[];
  dst_colnames TEXT;
  src_colnames TEXT;

  update_set_clause TEXT;

  num_rows BIGINT;
  err_context text;

  t timestamptz;
BEGIN
  -- If the destination table does not exist, just copy the source table
  fq_dest_table := format('%s.%I', dst_schema, dst_table);
  EXECUTE format('CREATE TABLE IF NOT EXISTS %s as TABLE %s', fq_dest_table, src_table);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  IF num_rows > 0 THEN
    RAISE NOTICE 'INSERTED % row(s)', num_rows;
    RETURN;
  END IF;

  skip_cols := skip_cols || '{cartodb_id}';

  -- Get the list of columns from the source table, excluding skip_cols
  SELECT ARRAY(SELECT quote_ident(c) FROM @extschema@._CDB_GetColumns(src_table) as c EXCEPT SELECT unnest(skip_cols)) INTO colnames;

  -- Deal with deleted rows: ids in dest but not in source
  t := clock_timestamp();
  EXECUTE format(
    'DELETE FROM %1$s _dst WHERE NOT EXISTS (SELECT * FROM %2$s _src WHERE _src.cartodb_id=_dst.cartodb_id)',
    fq_dest_table, src_table);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  RAISE NOTICE 'DELETED % row(s)', num_rows;
  RAISE DEBUG 'DELETE time (s): %', clock_timestamp() - t;

  -- Deal with inserted rows: ids in source but not in dest
  t := clock_timestamp();
  EXECUTE format('
      INSERT INTO %1$s(cartodb_id, %2$s)
      SELECT cartodb_id, %2$s FROM %3$s _src WHERE NOT EXISTS (SELECT * FROM %1$s _dst WHERE _src.cartodb_id=_dst.cartodb_id)
  ', fq_dest_table, array_to_string(colnames, ','), src_table);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  RAISE NOTICE 'INSERTED % row(s)', num_rows;
  RAISE DEBUG 'INSERT time (s): %', clock_timestamp() - t;

  -- Deal with modified rows: ids in source and dest but different hashes
  t := clock_timestamp();
  update_set_clause :=  @extschema@.__CDB_GetUpdateSetClause(colnames, '_changed');
  dst_colnames := array_to_string(@extschema@.__CDB_QualifyColumns('_dst', colnames), ',');
  src_colnames := array_to_string(@extschema@.__CDB_QualifyColumns('_src', colnames), ',');
  EXECUTE format('
      UPDATE %1$s _update SET %2$s
      FROM (
        SELECT _src.* FROM %3$s _src JOIN %1$s _dst ON (_dst.cartodb_id = _src.cartodb_id)
        WHERE  md5(ROW(%4$s)::text) <> md5(ROW(%5$s)::text)
      ) _changed
      WHERE _update.cartodb_id = _changed.cartodb_id;
  ', fq_dest_table, update_set_clause, src_table, dst_colnames, src_colnames);
  GET DIAGNOSTICS num_rows = ROW_COUNT;
  RAISE NOTICE 'MODIFIED % row(s)', num_rows;
  RAISE DEBUG 'UPDATE time (s): %', clock_timestamp() - t;
END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;
