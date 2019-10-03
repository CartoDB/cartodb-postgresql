-- Function that reassign the owner of a table to their ownership_role
CREATE OR REPLACE FUNCTION @extschema@.CDB_OAuthReassignTableOwnerOnCreation()
  RETURNS event_trigger
  SECURITY DEFINER
  AS $$
DECLARE
    obj record;
    owner_role text;
    creator_role text;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
      RAISE DEBUG '% ddl object: % % % %',
                  tg_tag,
                  obj.command_tag,
                  obj.object_type,
                  obj.schema_name,
                  obj.object_identity;
      SELECT rolname FROM pg_class JOIN pg_roles ON relowner = pg_roles.oid WHERE pg_class.oid = obj.objid INTO creator_role;
      SELECT value->>'ownership_role_name' from @extschema@.CDB_Conf_GetConf('api_keys_' || quote_ident(creator_role)) value INTO owner_role;
      IF owner_role IS NULL OR owner_role = '' THEN
        CONTINUE;
      ELSE
        EXECUTE 'ALTER ' || obj.object_type || ' ' || obj.object_identity || ' OWNER TO ' || quote_ident(owner_role);
        EXECUTE 'GRANT ALL ON ' || obj.object_identity || ' TO ' || QUOTE_IDENT(creator_role);
        RAISE DEBUG 'Changing ownership from % to %', creator_role, owner_role;
      END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

-- Creates the trigger on DDL events in order to reassign the owner
CREATE OR REPLACE FUNCTION @extschema@.CDB_EnableOAuthReassignTablesTrigger()
RETURNS void
AS $$
  BEGIN
    DROP EVENT TRIGGER IF EXISTS oauth_reassign_tables_trigger;

    CREATE EVENT TRIGGER oauth_reassign_tables_trigger
    ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'CREATE VIEW', 'CREATE FOREIGN TABLE', 'CREATE MATERIALIZED VIEW', 'CREATE SEQUENCE', 'CREATE FUNCTION')
    EXECUTE PROCEDURE @extschema@.CDB_OAuthReassignTableOwnerOnCreation();
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

-- Deletes the trigger on DDL events in order to reassign the owner
CREATE OR REPLACE FUNCTION @extschema@.CDB_DisableOAuthReassignTablesTrigger()
RETURNS void
AS $$
  BEGIN
    DROP EVENT TRIGGER IF EXISTS oauth_reassign_tables_trigger;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;
