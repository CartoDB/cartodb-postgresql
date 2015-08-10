CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_CreateGroup(group_name text)
    RETURNS TEXT AS $$
DECLARE
  cdb_group_role TEXT;
BEGIN
  -- TODO: escape group_name
  cdb_group_role := cartodb.CDB_Group_GroupRole(group_name);
  IF NOT EXISTS ( SELECT 1 FROM pg_roles WHERE rolname = cdb_group_role )
  THEN
    EXECUTE 'CREATE ROLE "' || cdb_group_role || '" NOLOGIN;';
  END IF;
  RETURN cdb_group_role;
END
$$ LANGUAGE PLPGSQL;

-- Drops group and everything that role owns
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_DropGroup(group_name text)
    RETURNS VOID AS $$
BEGIN
  EXECUTE 'DROP OWNED BY "' || cartodb.CDB_Group_GroupRole(group_name) || '"';
  EXECUTE 'DROP ROLE IF EXISTS "' || cartodb.CDB_Group_GroupRole(group_name) || '"';
END
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_RenameGroup(old_group_name text, new_group_name text)
    RETURNS VOID AS $$
BEGIN
  EXECUTE 'ALTER ROLE "' || cartodb.CDB_Group_GroupRole(old_group_name) || '" RENAME TO "' || cartodb.CDB_Group_GroupRole(new_group_name) || '"';
END
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_AddMember(group_name text, username text)
    RETURNS VOID AS $$
DECLARE
  cdb_group_role TEXT;
  cdb_user_role TEXT;
BEGIN
  cdb_group_role := cartodb.CDB_Group_GroupRole(group_name);
  cdb_user_role := cartodb.CDB_User_RoleFromUsername(username);
  EXECUTE 'GRANT "' || cdb_group_role || '" TO "' || cdb_user_role || '"';
END
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_RemoveMember(group_name text, username text)
    RETURNS VOID AS $$
DECLARE
  cdb_group_role TEXT;
  cdb_user_role TEXT;
BEGIN
  cdb_group_role := cartodb.CDB_Group_GroupRole(group_name);
  cdb_user_role := cartodb.CDB_User_RoleFromUsername(username);
  EXECUTE 'REVOKE "' || cdb_group_role || '" FROM "' || cdb_user_role || '"';
END
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_GrantRead(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb.CDB_Group_GroupRole(group_name);
    EXECUTE 'GRANT USAGE ON SCHEMA "' || username || '" TO "' || cdb_group_role || '"';
    EXECUTE 'GRANT SELECT ON TABLE "' || username || '"."' || table_name || '" TO "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_RevokeAll(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb.CDB_Group_GroupRole(group_name);
    EXECUTE 'REVOKE ALL ON TABLE "' || username || '"."' || table_name || '" FROM "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL;

-----------------------
-- Private functions
-----------------------
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_GroupRole(group_name text)
    RETURNS TEXT AS $$
BEGIN
    RETURN cartoDB.CDB_Organization_Member_Group_Role_Member_Name() || '_g_' || group_name;
END
$$ LANGUAGE PLPGSQL;

-- Returns the first owner of the schema matching username. Organization user schemas must have one only owner.
CREATE OR REPLACE
FUNCTION cartodb.CDB_User_RoleFromUsername(username text)
    RETURNS TEXT AS $$
DECLARE
  user_role TEXT;
BEGIN
  EXECUTE 'SELECT SCHEMA_OWNER FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ''' || username || ''' LIMIT 1' INTO user_role;
  RETURN user_role;
END
$$ LANGUAGE PLPGSQL;
