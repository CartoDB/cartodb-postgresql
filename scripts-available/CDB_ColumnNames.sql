-- Function returning the column names of a table
CREATE OR REPLACE FUNCTION @extschema@.CDB_ColumnNames(REGCLASS)
RETURNS SETOF information_schema.sql_identifier
AS $$
  SELECT
    a.attname::information_schema.sql_identifier column_name
    FROM pg_class c
         LEFT JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE c.oid = $1::oid
    AND a.attstattarget < 0 -- exclude system columns
   ORDER BY a.attnum;
$$ LANGUAGE SQL STABLE PARALLEL SAFE;

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION @extschema@.CDB_ColumnNames(REGCLASS) TO PUBLIC;
