----------------------------------
-- GROUP MANAGEMENT FUNCTIONS
--
-- Meant to be used by org admin. See CDB_Organization_AddAdmin.
----------------------------------

-- Creates a new group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_CreateGroup(group_name text)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    EXECUTE format('CREATE ROLE %I NOLOGIN;', group_role);
    PERFORM @extschema@._CDB_Group_CreateGroup_API(group_name, group_role);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Drops group and everything that role owns
-- TODO: LIMITATION: in order to drop a role all its owned objects must be dropped before.
-- Right now this is done with DROP OWNED, which can only be done by a superadmin.
-- Not even the role creator can drop the role and the objects it owns.
-- All group owned objects by the group are permissions.
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_DropGroup(group_name text)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    EXECUTE format('DROP OWNED BY %I', group_role);
    EXECUTE format('DROP ROLE IF EXISTS %I', group_role);
    PERFORM @extschema@._CDB_Group_DropGroup_API(group_name);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Renames a group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_RenameGroup(old_group_name text, new_group_name text)
    RETURNS VOID AS $$
DECLARE
    old_group_role TEXT;
    new_group_role TEXT;
BEGIN
    old_group_role = @extschema@._CDB_Group_GroupRole(old_group_name);
    new_group_role = @extschema@._CDB_Group_GroupRole(new_group_name);
    EXECUTE format('ALTER ROLE %I RENAME TO %I', old_group_role, new_group_role);
    PERFORM @extschema@._CDB_Group_RenameGroup_API(old_group_name, new_group_name, new_group_role);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Adds users to a group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_AddUsers(group_name text, usernames text[])
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
    user_role TEXT;
    username TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    foreach username in array usernames
    loop
      user_role := @extschema@._CDB_User_RoleFromUsername(username);
      IF(group_role IS NULL OR user_role IS NULL)
      THEN
        RAISE EXCEPTION 'Group role (%) and user role (%) must be already existing', group_role, user_role;
      END IF;
      EXECUTE format('GRANT %I TO %I', group_role, user_role);
    end loop;
    PERFORM @extschema@._CDB_Group_AddUsers_API(group_name, usernames);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Removes users from a group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_RemoveUsers(group_name text, usernames text[])
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
    user_role TEXT;
    username TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    foreach username in array usernames
    loop
      user_role := @extschema@._CDB_User_RoleFromUsername(username);
      EXECUTE format('REVOKE %I FROM %I', group_role, user_role);
    end loop;
    PERFORM @extschema@._CDB_Group_RemoveUsers_API(group_name, usernames);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

----------------------------------
-- TABLE MANAGEMENT FUNCTIONS
--
-- Meant to be used by table owners.
----------------------------------

-- Grants table read permission to a group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_Table_GrantRead(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    PERFORM @extschema@._CDB_Group_Table_GrantRead(group_name, username, table_name, true);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_Table_GrantRead(group_name text, username text, table_name text, sync boolean)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', username, group_role);
    EXECUTE format('GRANT SELECT ON TABLE %I.%I TO %I', username, table_name, group_role );
    IF(sync) THEN
      PERFORM @extschema@._CDB_Group_Table_GrantPermission_API(group_name, username, table_name, 'r');
    END IF;
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Grants table write permission to a group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_Table_GrantReadWrite(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    PERFORM @extschema@._CDB_Group_Table_GrantReadWrite(group_name, username, table_name, true);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_Table_GrantReadWrite(group_name text, username text, table_name text, sync boolean)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', username, group_role);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I.%I TO %I', username, table_name, group_role);
    PERFORM @extschema@._CDB_Group_TableSequences_Permission(group_name, username, table_name, true);
    IF(sync) THEN
      PERFORM @extschema@._CDB_Group_Table_GrantPermission_API(group_name, username, table_name, 'w');
    END IF;
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Granting and revoking permissions on sequences
CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_TableSequences_Permission(group_name text, username text, table_name text, do_grant bool)
    RETURNS VOID AS $$
DECLARE
    column_name TEXT;
    sequence_name TEXT;
    group_role TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    FOR column_name IN EXECUTE 'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_CATALOG = current_database() AND TABLE_SCHEMA = $1 AND TABLE_NAME = $2 AND COLUMN_DEFAULT LIKE ''nextval%''' USING username, table_name
    LOOP
        EXECUTE format('SELECT PG_GET_SERIAL_SEQUENCE(''%I.%I'', ''%I'')', username, table_name, column_name) INTO sequence_name;
        IF sequence_name IS NOT NULL THEN
          IF do_grant THEN
            -- Here %s is needed since sequence_name has quotes
            EXECUTE format('GRANT USAGE, SELECT, UPDATE ON SEQUENCE %s TO %I', sequence_name, group_role);
          ELSE
            EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM %I', sequence_name, group_role);
          END IF;
        END IF;
    END LOOP;
    RETURN;
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Revokes all permissions on a table from a group
CREATE OR REPLACE
FUNCTION @extschema@.CDB_Group_Table_RevokeAll(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    PERFORM @extschema@._CDB_Group_Table_RevokeAll(group_name, username, table_name, true);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_Table_RevokeAll(group_name text, username text, table_name text, sync boolean)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    group_role := @extschema@._CDB_Group_GroupRole(group_name);
    EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM %I', username, table_name, group_role);
    PERFORM @extschema@._CDB_Group_TableSequences_Permission(group_name, username, table_name, false);
    IF(sync) THEN
      PERFORM @extschema@._CDB_Group_Table_RevokeAllPermission_API(group_name, username, table_name);
    END IF;
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-----------------------
-- Helper functions
-----------------------
-- Given a group name returns a role. group_name must be a valid PostgreSQL idenfifier. See http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_GroupRole(group_name text)
    RETURNS TEXT AS $$
DECLARE
    group_role TEXT;
    prefix TEXT;
    max_length constant INTEGER := 63;
BEGIN
    prefix = format('%s_g_', @extschema@._CDB_Group_ShortDatabaseName());
    group_role := format('%s%s', prefix, group_name);
    IF LENGTH(group_role) > max_length
    THEN
        RAISE EXCEPTION 'Group name must be shorter. It can''t have more than % characters, but it is longer (%): %', max_length - LENGTH(prefix), length(group_name), group_name;
    END IF;
    RETURN group_role;
END
$$ LANGUAGE PLPGSQL STABLE PARALLEL SAFE;

-- Returns the first owner of the schema matching username. Organization user schemas must have one only owner.
CREATE OR REPLACE
FUNCTION @extschema@._CDB_User_RoleFromUsername(username text)
    RETURNS TEXT AS $$
DECLARE
    user_role TEXT;
BEGIN
    -- This was preferred, but non-superadmins won't get results
    -- SELECT SCHEMA_OWNER FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = $1 LIMIT 1'
    SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = username INTO user_role;
    RETURN user_role;
END
$$ LANGUAGE PLPGSQL STABLE PARALLEL SAFE;

-- Database names are too long, we need a shorter version for composing role names
CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_ShortDatabaseName()
    RETURNS TEXT AS $$
DECLARE
    short_database_name TEXT;
BEGIN
    SELECT md5(current_database()) INTO short_database_name;
    RETURN short_database_name;
END
$$ LANGUAGE PLPGSQL STABLE PARALLEL SAFE;
