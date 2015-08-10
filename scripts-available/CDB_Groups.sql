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

CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_DropGroup(group_name text)
    RETURNS VOID AS $$
BEGIN
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
