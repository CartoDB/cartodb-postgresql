-- Function returning indexes for a table
CREATE OR REPLACE FUNCTION CDB_TableIndexes(REGCLASS)
RETURNS TABLE(index_name name, index_unique bool, index_primary bool, index_keys text array)
AS $$

  SELECT pg_class.relname as index_name,
         idx.indisunique as index_unique,
         idx.indisprimary as index_primary,
         ARRAY(
         SELECT pg_get_indexdef(idx.indexrelid, k + 1, true)
         FROM generate_subscripts(idx.indkey, 1) as k
         ORDER BY k
         ) as index_keys
  FROM pg_indexes,
       pg_index as idx 
  JOIN pg_class
  ON pg_class.oid = idx.indexrelid 
  WHERE pg_indexes.tablename = '' || $1 || ''
  AND '' || $1 || '' IN (SELECT CDB_UserTables())
  AND pg_class.relname=pg_indexes.indexname
  ;

$$ LANGUAGE SQL STABLE PARALLEL SAFE;

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION CDB_TableIndexes(REGCLASS) TO public;
