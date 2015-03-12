-- Function returning list of cartodb user tables
--
-- The optional argument restricts the result to tables
-- of the specified access type.
--
-- Currently accepted permissions are: 'public', 'private' or 'all'
--
CREATE OR REPLACE FUNCTION CDB_UserTables(perm text DEFAULT 'all')
RETURNS SETOF information_schema.sql_identifier
AS $$
  WITH usertables AS ( 
    -- TODO: query CDB_TableMetadata for this ?
    -- See http://github.com/CartoDB/cartodb/issues/254#issuecomment-26044777
    SELECT table_name as t
    FROM information_schema.tables
    WHERE
         table_type='BASE TABLE'
     AND table_schema='public'
     AND table_name NOT IN (
      'cdb_tablemetadata',
      'spatial_ref_sys'
     )
  ), perms AS (
    SELECT t, has_table_privilege('publicuser', 'public'||'.'||t, 'SELECT') as p
    FROM usertables
  )
  SELECT t FROM perms
  WHERE (
    p = CASE WHEN $1 = 'private' THEN false
                 WHEN $1 = 'public' THEN true
                 ELSE not p -- none
            END
    OR $1 = 'all'
  )
  AND has_table_privilege('public'||'.'||t, 'SELECT')
   ;
$$ LANGUAGE 'sql';

-- This is to migrate from pre-0.2.0 version
-- See http://github.com/CartoDB/cartodb-postgresql/issues/36
GRANT EXECUTE ON FUNCTION CDB_UserTables(text) TO public;
