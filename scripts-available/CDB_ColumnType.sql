-- Function returning the type of a column
CREATE OR REPLACE FUNCTION CDB_ColumnType(REGCLASS, TEXT)
RETURNS information_schema.character_data
AS $$

    SELECT c.data_type
      FROM information_schema.columns c, pg_class _tn, pg_namespace _sn
      WHERE table_name = _tn.relname
        AND table_schema = _sn.nspname
        AND column_name = $2
        AND _tn.oid = $1::oid
        AND _sn.oid = _tn.relnamespace;
         
$$ LANGUAGE SQL;

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION CDB_ColumnType(REGCLASS, TEXT) TO public;
