-- Function returning the type of a column
CREATE OR REPLACE FUNCTION CDB_ColumnType(REGCLASS, TEXT)
RETURNS information_schema.character_data
AS $$

    SELECT data_type 
      FROM information_schema.columns 
      WHERE
        table_name IN (SELECT CDB_UserTables())
        AND table_name = '' || $1 || ''
        AND column_name = '' || quote_ident($2) || '';
         
$$ LANGUAGE SQL;

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION CDB_ColumnType(REGCLASS, TEXT) TO public;
