-- Function returning the column names of a table
CREATE OR REPLACE FUNCTION CDB_ColumnNames(REGCLASS)
RETURNS SETOF information_schema.sql_identifier
AS $$

    SELECT c.column_name
      FROM information_schema.columns c, pg_class _tn, pg_namespace _sn
      WHERE table_name = _tn.relname
        AND table_schema = _sn.nspname
        AND _tn.oid = $1::oid
        AND _sn.oid = _tn.relnamespace
      ORDER BY ordinal_position;

$$ LANGUAGE SQL;

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION CDB_ColumnNames(REGCLASS) TO PUBLIC;
