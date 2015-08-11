-- Creates a new group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_CreateGroup(group_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    -- TODO: escape group_name
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    IF NOT EXISTS ( SELECT 1 FROM pg_roles WHERE rolname = cdb_group_role )
    THEN
        EXECUTE 'CREATE ROLE "' || cdb_group_role || '" NOLOGIN;';
    END IF;
END
$$ LANGUAGE PLPGSQL;

-- Drops group and everything that role owns
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_DropGroup(group_name text)
    RETURNS VOID AS $$
BEGIN
    EXECUTE 'DROP OWNED BY "' || cartodb._CDB_Group_GroupRole(group_name) || '"';
    EXECUTE 'DROP ROLE IF EXISTS "' || cartodb._CDB_Group_GroupRole(group_name) || '"';
END
$$ LANGUAGE PLPGSQL;

-- Renames a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_RenameGroup(old_group_name text, new_group_name text)
    RETURNS VOID AS $$
BEGIN
    EXECUTE 'ALTER ROLE "' || cartodb._CDB_Group_GroupRole(old_group_name) || '" RENAME TO "' || cartodb._CDB_Group_GroupRole(new_group_name) || '"';
END
$$ LANGUAGE PLPGSQL;

-- Adds a user to a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_AddMember(group_name text, username text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
    cdb_user_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    cdb_user_role := cartodb._CDB_User_RoleFromUsername(username);
    EXECUTE 'GRANT "' || cdb_group_role || '" TO "' || cdb_user_role || '"';
END
$$ LANGUAGE PLPGSQL;

-- Removes a user from a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_RemoveMember(group_name text, username text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
    cdb_user_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    cdb_user_role := cartodb._CDB_User_RoleFromUsername(username);
    EXECUTE 'REVOKE "' || cdb_group_role || '" FROM "' || cdb_user_role || '"';
END
$$ LANGUAGE PLPGSQL;

-- Grants table read permission to a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_GrantRead(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    EXECUTE 'GRANT USAGE ON SCHEMA "' || username || '" TO "' || cdb_group_role || '"';
    EXECUTE 'GRANT SELECT ON TABLE "' || username || '"."' || table_name || '" TO "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL;

-- Grants table write permission to a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_GrantReadWrite(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    EXECUTE 'GRANT USAGE ON SCHEMA "' || username || '" TO "' || cdb_group_role || '"';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "' || username || '"."' || table_name || '" TO "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL;

-- Revokes all permissions on a table from a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_RevokeAll(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    EXECUTE 'REVOKE ALL ON TABLE "' || username || '"."' || table_name || '" FROM "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL;

-----------------------
-- Private functions
-----------------------
-- Given a group name returns a role. group_name must be a valid PostgreSQL idenfifier. See http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_GroupRole(group_name text)
    RETURNS TEXT AS $$
DECLARE
    group_role TEXT;
BEGIN
    IF group_name !~ '^[a-zA-Z_][a-zA-Z0-9_]*$'
    THEN
        RAISE EXCEPTION 'Group name (%) must be a valid identifier. See http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS', group_name;
    END IF;
    RETURN 'g_' || md5(current_database()) || '_' || group_name;
END
$$ LANGUAGE PLPGSQL;

-- Returns the first owner of the schema matching username. Organization user schemas must have one only owner.
CREATE OR REPLACE
FUNCTION cartodb._CDB_User_RoleFromUsername(username text)
    RETURNS TEXT AS $$
DECLARE
    user_role TEXT;
BEGIN
    EXECUTE 'SELECT SCHEMA_OWNER FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = $1 LIMIT 1' INTO user_role USING username;
    RETURN user_role;
END
$$ LANGUAGE PLPGSQL;
