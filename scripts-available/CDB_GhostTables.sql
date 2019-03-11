-- Table to store the transaction id from DDL events to avoid multiple executions
CREATE TABLE IF NOT EXISTS cartodb.cdb_ddl_execution(txid integer PRIMARY KEY, tag text);

-- Enqueues a job to run Ghost tables linking process for the provided user_id
CREATE OR REPLACE FUNCTION _CDB_LinkGhostTables(username text, db_name text, ddl_tag text) 
RETURNS void
AS $$
  if not username:
    return

  if 'json' not in GD:
    import json
    GD['json'] = json
  else:
    json = GD['json']    

  error = ''
  tis_config = plpy.execute("select cartodb.CDB_Conf_GetConf('invalidation_service');")[0]['cdb_conf_getconf']
  tis_config_dict = json.loads(tis_config) if tis_config else {}
  tis_host = tis_config_dict.get('host', '127.0.0.1')
  tis_port = tis_config_dict.get('port', 3142)
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
          plpy.warning('Invalidation Service connection error: ' +  str(err))
          break

    try:
      client.execute_command('DBSCH', db_name, username, ddl_tag)
      break
    except Exception as err:
      error = "request_error - %s" % str(err)
      client = GD['invalidation'] = None # force reconnect
      if not tis_retry:
        plpy.warning('Invalidation Service error: ' +  str(err))
        break
      tis_retry -= 1 # try reconnecting
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE;

-- Enqueues a job to run Ghost tables linking process for the current user
CREATE OR REPLACE FUNCTION CDB_LinkGhostTables()
RETURNS void
AS $$
  DECLARE
    username TEXT;
    db_name TEXT;
    ddl_tag TEXT;
  BEGIN
    EXECUTE 'SELECT CDB_Username();' INTO username;
    EXECUTE 'SELECT current_database();' INTO db_name;
    EXECUTE 'SELECT tag FROM cartodb.cdb_ddl_execution WHERE txid = txid_current();' INTO ddl_tag;
    PERFORM _CDB_LinkGhostTables(username, db_name, ddl_tag);
    DELETE FROM cartodb.cdb_ddl_execution WHERE txid = txid_current();
    RAISE NOTICE '_CDB_LinkGhostTables() called with username=%, ddl_tag=%', username, ddl_tag;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

-- Trigger function to call CDB_LinkGhostTables()
CREATE OR REPLACE FUNCTION _CDB_LinkGhostTablesTrigger()
RETURNS trigger
AS $$
  BEGIN
    PERFORM CDB_LinkGhostTables();
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

-- Trigger to call CDB_LinkGhostTables() when adding a row in cartodb.cdb_ddl_execution
DROP TRIGGER IF EXISTS check_ddl_update ON cartodb.cdb_ddl_execution;
CREATE CONSTRAINT TRIGGER check_ddl_update
AFTER INSERT ON cartodb.cdb_ddl_execution
INITIALLY DEFERRED
FOR EACH ROW
EXECUTE PROCEDURE _CDB_LinkGhostTablesTrigger();

-- Event trigger to save the current transaction in cartodb.cdb_ddl_execution
CREATE OR REPLACE FUNCTION CDB_SaveDDLTransaction()
RETURNS event_trigger
AS $$
  BEGIN
    INSERT INTO cartodb.cdb_ddl_execution VALUES (txid_current(), tg_tag) ON CONFLICT (txid) DO NOTHING;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

-- Creates the trigger on DDL events to link ghost tables
CREATE OR REPLACE FUNCTION CDB_EnableGhostTablesTrigger()
RETURNS void
AS $$
  BEGIN
    DROP EVENT TRIGGER IF EXISTS link_ghost_tables;
    CREATE EVENT TRIGGER link_ghost_tables
    ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE', 'SELECT INTO', 'DROP TABLE', 'ALTER TABLE', 'CREATE TRIGGER', 'DROP TRIGGER', 'CREATE VIEW', 'DROP VIEW', 'ALTER VIEW')
    EXECUTE PROCEDURE CDB_SaveDDLTransaction();
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

-- Drops the trigger on DDL events to link ghost tables
CREATE OR REPLACE FUNCTION CDB_DisableGhostTablesTrigger()
RETURNS void
AS $$
  BEGIN
    DROP EVENT TRIGGER IF EXISTS link_ghost_tables;
  END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;
