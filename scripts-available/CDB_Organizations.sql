-------------------------------------------------------------------------------
-- Manage Admin role
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Add_Admin_Role(role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'GRANT cdb_org_admin TO "' || role_name || '";';
END
$$ LANGUAGE PLPGSQL VOLATILE;


CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Remove_Admin_Role(role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'REVOKE cdb_org_admin FROM "' || role_name || '";';
END
$$ LANGUAGE PLPGSQL VOLATILE;


-------------------------------------------------------------------------------
-- Manage Member role
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Add_Member_Role(role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'GRANT cdb_org_member TO "' || role_name || '";';
END
$$ LANGUAGE PLPGSQL VOLATILE;


CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Remove_Member_Role(role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'REVOKE cdb_org_member FROM "' || role_name || '";';
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
FUNCTION cartodb.CDB_Organization_Add_Table_Read_Write_Permission(from_schema text, table_name text, to_role_name text)
    RETURNS void
AS $$
BEGIN
    EXECUTE 'GRANT USAGE ON SCHEMA ' || from_schema || ' TO "' || to_role_name || '"';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON ' || from_schema || '.' || table_name || ' TO "' || to_role_name || '"';
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
