DO LANGUAGE 'plpgsql' $$
BEGIN
  IF NOT EXISTS ( SELECT * FROM pg_roles WHERE rolname= 'cdb_org_member' )
  THEN
    CREATE ROLE cdb_org_member NOLOGIN;
  END IF;
END
$$;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Create_Member(role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'GRANT cdb_org_member TO "' || role_name || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;


-------------------------------------------------------------------------------
-- Sharing tables
-------------------------------------------------------------------------------
CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Add_Table_Read_Permission(from_schema text, table_name text, to_role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'GRANT USAGE ON SCHEMA ' || from_schema || ' TO "' || to_role_name || '"';
    EXECUTE 'GRANT SELECT ON ' || from_schema || '.' || table_name || ' TO "' || to_role_name || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Add_Table_Organization_Read_Permission(from_schema text, table_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'SELECT cartodb.CDB_Organization_Add_Table_Read_Permission(''' || from_schema || ''', ''' || table_name || ''', ''cdb_org_member'');';
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Add_Table_Read_Write_Permission(from_schema text, table_name text, to_role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'GRANT USAGE ON SCHEMA ' || from_schema || ' TO "' || to_role_name || '"';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON ' || from_schema || '.' || table_name || ' TO "' || to_role_name || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Add_Table_Organization_Read_Write_Permission(from_schema text, table_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'SELECT cartodb.CDB_Organization_Add_Table_Read_Write_Permission(''' || from_schema || ''', ''' || table_name || ''', ''cdb_org_member'');';
END
$$ LANGUAGE PLPGSQL VOLATILE;


CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Remove_Access_Permission(from_schema text, table_name text, to_role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'REVOKE ALL PRIVILEGES ON TABLE ' || from_schema || '.' || table_name || ' FROM "' || to_role_name || '"';
    -- EXECUTE 'REVOKE USAGE ON SCHEMA ' || from_schema || ' FROM "' || to_role_name || '"';
    -- We need to revoke usage on schema only if we are revoking privileges from the last table where to_role_name has
    -- any permission granted within the schema from_schema
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Organization_Remove_Organization_Access_Permission(from_schema text, table_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'SELECT cartodb.CDB_Organization_Remove_Access_Permission(''' || from_schema || ''', ''' || table_name || ''', ''cdb_org_member'');';
END
$$ LANGUAGE PLPGSQL VOLATILE;
