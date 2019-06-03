-- Function returning the type of a column
CREATE OR REPLACE FUNCTION @extschema@.CDB_ColumnType(REGCLASS, TEXT)
RETURNS information_schema.character_data
AS $$
  SELECT
    format_type(a.atttypid, NULL)::information_schema.character_data data_type
  FROM pg_class c
       LEFT JOIN pg_attribute a ON a.attrelid = c.oid
  WHERE c.oid = $1::oid
  AND a.attname = $2
  AND a.attstattarget < 0; -- exclude system columns
$$ LANGUAGE SQL STABLE PARALLEL SAFE;

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION @extschema@.CDB_ColumnType(REGCLASS, TEXT) TO public;
