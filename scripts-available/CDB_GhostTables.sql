-- Enqueues a job to run Ghost tables linking process for the provided username
CREATE OR REPLACE FUNCTION @extschema@._CDB_LinkGhostTables(username text, db_name text, event_name text) 
RETURNS void
AS $$
  if not username:
    return

  if 'json' not in GD:
    import json
    GD['json'] = json
  else:
    json = GD['json']    

  tis_config = plpy.execute("select @extschema@.CDB_Conf_GetConf('invalidation_service');")[0]['cdb_conf_getconf']
  if not tis_config:
    plpy.warning('Invalidation service configuration not found. Skipping Ghost Tables linking.')
    return

  tis_config_dict = json.loads(tis_config)
  tis_host = tis_config_dict.get('host')
  tis_port = tis_config_dict.get('port')
  tis_timeout = tis_config_dict.get('timeout', 5)
  tis_retry = tis_config_dict.get('retry', 5)
      
  client = GD.get('invalidation', None)

  while True:

    if not client:
        try:
          import redis
          client = redis.Redis(host=tis_host, port=tis_port, socket_timeout=tis_timeout)
          GD['invalidation'] = client
        except Exception as err:
          error = "client_error - %s" % str(err)
          # NOTE: no retries on connection error
          plpy.warning('Error trying to connect to Invalidation Service to link Ghost Tables: ' +  str(err))
          break

    try:
      client.execute_command('DBSCH', db_name, username, event_name)
      break
    except Exception as err:
      error = "request_error - %s" % str(err)
      client = GD['invalidation'] = None # force reconnect
      if not tis_retry:
        plpy.warning('Error calling Invalidation Service to link Ghost Tables: ' +  str(err))
        break
      tis_retry -= 1 # try reconnecting
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE;

-- Enqueues a job to run Ghost tables linking process for the current user
CREATE OR REPLACE FUNCTION @extschema@.CDB_LinkGhostTables(event_name text DEFAULT 'USER')
RETURNS void
AS $$
  DECLARE
    username TEXT;
    db_name TEXT;
  BEGIN
    EXECUTE 'SELECT @extschema@.CDB_Username();' INTO username;
    EXECUTE 'SELECT current_database();' INTO db_name;

    PERFORM @extschema@._CDB_LinkGhostTables(username, db_name, event_name);
    RAISE NOTICE '_CDB_LinkGhostTables() called with username=%, event_name=%', username, event_name;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

-- Trigger function to call CDB_LinkGhostTables()
CREATE OR REPLACE FUNCTION @extschema@._CDB_LinkGhostTablesTrigger()
RETURNS trigger
AS $$
  DECLARE
    ddl_tag TEXT;
  BEGIN
    EXECUTE 'DELETE FROM @extschema@.cdb_ddl_execution WHERE txid = txid_current() RETURNING tag;' INTO ddl_tag;
    PERFORM @extschema@.CDB_LinkGhostTables(ddl_tag);
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

-- Event trigger to save the current transaction in @extschema@.cdb_ddl_execution
CREATE OR REPLACE FUNCTION @extschema@.CDB_SaveDDLTransaction()
RETURNS event_trigger
AS $$
  BEGIN
    INSERT INTO @extschema@.cdb_ddl_execution VALUES (txid_current(), tg_tag) ON CONFLICT (txid) DO NOTHING;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

-- Creates the trigger on DDL events to link ghost tables
CREATE OR REPLACE FUNCTION @extschema@.CDB_EnableGhostTablesTrigger()
RETURNS void
AS $$
  BEGIN
    DROP EVENT TRIGGER IF EXISTS link_ghost_tables;
    DROP TRIGGER IF EXISTS check_ddl_update ON @extschema@.cdb_ddl_execution;

    -- Table to store the transaction id from DDL events to avoid multiple executions
    CREATE TABLE IF NOT EXISTS @extschema@.cdb_ddl_execution(txid integer PRIMARY KEY, tag text);

    CREATE CONSTRAINT TRIGGER check_ddl_update
    AFTER INSERT ON @extschema@.cdb_ddl_execution
    INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE PROCEDURE @extschema@._CDB_LinkGhostTablesTrigger();

    CREATE EVENT TRIGGER link_ghost_tables
    ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE', 'SELECT INTO', 'DROP TABLE', 'ALTER TABLE', 'CREATE TRIGGER', 'DROP TRIGGER', 'CREATE VIEW', 'DROP VIEW', 'ALTER VIEW')
    EXECUTE PROCEDURE @extschema@.CDB_SaveDDLTransaction();
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

-- Drops the trigger on DDL events to link ghost tables
CREATE OR REPLACE FUNCTION @extschema@.CDB_DisableGhostTablesTrigger()
RETURNS void
AS $$
  BEGIN
    DROP EVENT TRIGGER IF EXISTS link_ghost_tables;
    DROP TRIGGER IF EXISTS check_ddl_update ON @extschema@.cdb_ddl_execution;
    DROP TABLE IF EXISTS @extschema@.cdb_ddl_execution;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;
