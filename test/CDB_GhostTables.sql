-- Create user and enable Ghost tables trigger
\set QUIET on
SET client_min_messages TO error;

-- Recreate the function without extra error messages as it changes depending on the python-redis version
CREATE OR REPLACE FUNCTION cartodb._CDB_LinkGhostTables(username text, db_name text, event_name text)
RETURNS void
AS $$
  if not username:
    return

  if 'json' not in GD:
    import json
    GD['json'] = json
  else:
    json = GD['json']

  tis_config = plpy.execute("select cartodb.CDB_Conf_GetConf('invalidation_service');")[0]['cdb_conf_getconf']
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
          # NOTE: no retries on connection error
          plpy.warning('Error trying to connect to Invalidation Service to link Ghost Tables')
          break

    try:
      client.execute_command('DBSCH', db_name, username, event_name)
      break
    except Exception as err:
      client = GD['invalidation'] = None # force reconnect
      if not tis_retry:
        plpy.warning('Error calling Invalidation Service to link Ghost Tables')
        break
      tis_retry -= 1 # try reconnecting
$$ LANGUAGE '@@plpythonu@@' VOLATILE PARALLEL UNSAFE;

SELECT CDB_EnableGhostTablesTrigger();
CREATE ROLE "fulano" LOGIN;
GRANT ALL ON SCHEMA cartodb TO "fulano";
GRANT SELECT ON cartodb.cdb_ddl_execution TO "fulano";
GRANT EXECUTE ON FUNCTION CDB_Username() TO "fulano";
GRANT EXECUTE ON FUNCTION CDB_LinkGhostTables(text) TO "fulano";
SELECT cartodb.CDB_Conf_SetConf('api_keys_fulano', '{"username": "fulanito", "permissions":[]}');
DELETE FROM cdb_conf WHERE key = 'invalidation_service';
SET SESSION AUTHORIZATION "fulano";
SET client_min_messages TO notice;
\set QUIET off

SELECT CDB_LinkGhostTables(); -- _CDB_LinkGhostTables called (configuration not found)

-- Add TIS configuration
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT cartodb.CDB_Conf_SetConf('invalidation_service', '{"host": "fake-tis-host", "port": 3142}');
SET SESSION AUTHORIZATION "fulano";
\set QUIET off

SELECT CDB_LinkGhostTables(); -- _CDB_LinkGhostTables called

BEGIN;
SELECT to_regclass('cartodb.cdb_ddl_execution'); -- exists
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
CREATE TABLE tmp(id INT);
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 1
END; -- _CDB_LinkGhostTables called

-- Disable Ghost tables trigger
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_DisableGhostTablesTrigger();
SET SESSION AUTHORIZATION "fulano";
\set QUIET off

SELECT to_regclass('cartodb.cdb_ddl_execution'); -- not exists
DROP TABLE tmp; -- _CDB_LinkGhostTables not called

-- Cleanup
\set QUIET on
SET SESSION AUTHORIZATION postgres;
REVOKE EXECUTE ON FUNCTION CDB_LinkGhostTables(text) FROM "fulano";
REVOKE EXECUTE ON FUNCTION CDB_Username() FROM "fulano";
REVOKE ALL ON SCHEMA cartodb FROM "fulano";
DROP ROLE "fulano";
DELETE FROM cdb_conf WHERE key = 'api_keys_fulano' OR key = 'invalidation_service';
\set QUIET off
