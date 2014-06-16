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
CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Add_Table_Read_Permission(table_name text, to_role_name text)
    RETURNS void
AS $$
DECLARE
    role TEXT;
BEGIN
    role := (SELECT CURRENT_USER);
    EXECUTE 'GRANT USAGE ON SCHEMA ' || role || ' TO ' || to_role_name;
    EXECUTE 'GRANT SELECT ON ' || role || '.' || table_name || ' TO ' || to_role_name || '';
END
$$ LANGUAGE PLPGSQL VOLATILE;


CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Add_Table_Read_Write_Permission(table_name text, to_role_name text)
    RETURNS void
AS $$
DECLARE
    role TEXT;
BEGIN
    role := (SELECT CURRENT_USER);
    EXECUTE 'GRANT USAGE ON SCHEMA ' || role || ' TO ' || to_role_name;
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON ' || role || '.' || table_name || ' TO ' || to_role_name || '';
END
$$ LANGUAGE PLPGSQL VOLATILE;


CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Remove_Access_Permission(table_name text, to_role_name text)
    RETURNS void
AS $$
DECLARE
    role TEXT;
BEGIN
    role := (SELECT CURRENT_USER);
    EXECUTE 'REVOKE ALL PRIVILEGES ON TABLE ' || role || '.' || table_name || ' FROM ' || to_role_name;
    EXECUTE 'REVOKE USAGE ON SCHEMA ' || role || ' FROM ' || to_role_name;
END
$$ LANGUAGE PLPGSQL VOLATILE;


CREATE OR REPLACE FUNCTION cartodb.CDB_Organization_Remove_Write_Permission(table_name text, to_role_name text)
    RETURNS void
AS $$
DECLARE
    role TEXT;
BEGIN
    role := (SELECT CURRENT_USER);
    EXECUTE 'REVOKE ALL INSERT, UPDATE ON TABLE ' || role || '.' || table_name || ' FROM ' || to_role_name;
END
$$ LANGUAGE PLPGSQL VOLATILE;