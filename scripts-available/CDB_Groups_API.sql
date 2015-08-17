-- Requires configuration parameter. Example: SELECT cartodb.CDB_Conf_SetConf('groups_api', '{ "host": "127.0.0.1", "port": 3000, "timeout": 10, "username": "superadmin", "password": "monkey" }');

-- Sends the create group request
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_CreateGroup_API(database_name text, group_name text, group_role text)
    RETURNS VOID AS
$$
    import httplib
    import string

    try:
      params = plpy.execute("select c.host, c.port, c.timeout, c.auth from cartodb._CDB_Group_API_Conf() c;")[0]
      if params['host'] is None:
        return

      client = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
      body = '{ "name": "%s", "database_role": "%s" }' % (group_name, group_role)
      headers = { 'Authorization': params['auth'], 'Content-Type': 'application/json' }
      client.request('POST', '/api/v1/databases/%s/groups' % database_name, body, headers)
      response = client.getresponse()
      assert response.status == 200
    except Exception as err:
      plpy.warning('group creation error: ' + str(err))
      raise err
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_DropGroup_API(database_name text, group_name text)
    RETURNS VOID AS
$$
    import httplib
    import string

    try:
      params = plpy.execute("select c.host, c.port, c.timeout, c.auth from cartodb._CDB_Group_API_Conf() c;")[0]
      if params['host'] is None:
        return

      client = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
      headers = { 'Authorization': params['auth'], 'Content-Type': 'application/json' }
      client.request('DELETE', '/api/v1/databases/%s/groups/%s' % (database_name, group_name), '', headers)
      response = client.getresponse()
      assert response.status == 200
    except Exception as err:
      plpy.warning('group creation error: ' + str(err))
      raise err
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_RenameGroup_API(database_name text, old_group_name text, new_group_name text, new_group_role text)
    RETURNS VOID AS
$$
    import httplib
    import string

    try:
      params = plpy.execute("select c.host, c.port, c.timeout, c.auth from cartodb._CDB_Group_API_Conf() c;")[0]
      if params['host'] is None:
        return

      client = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
      body = '{ "name": "%s", "database_role": "%s" }' % (new_group_name, new_group_role)
      headers = { 'Authorization': params['auth'], 'Content-Type': 'application/json' }
      client.request('PUT', '/api/v1/databases/%s/groups/%s' % (database_name, old_group_name), body, headers)
      response = client.getresponse()
      assert response.status == 200
    except Exception as err:
      plpy.warning('group creation error: ' + str(err))
      raise err
$$ LANGUAGE 'plpythonu' VOLATILE;

DO LANGUAGE 'plpgsql' $$
BEGIN
    DROP FUNCTION IF EXISTS cartodb._CDB_Group_API_Conf();
    DROP TYPE IF EXISTS _CDB_Group_API_Params;
END
$$;

CREATE TYPE _CDB_Group_API_Params AS (
    host text,
    port int,
    timeout int,
    auth text
);

-- This must be explicitally extracted because "composite types are currently not supported".
-- See http://www.postgresql.org/docs/9.3/static/plpython-database.html.
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_API_Conf()
    RETURNS _CDB_Group_API_Params AS
$$
    conf = plpy.execute("SELECT cartodb.CDB_Conf_GetConf('groups_api') conf")[0]['conf']
    if conf is None:
      return None
    else:
      import json
      params = json.loads(conf)
      auth = 'Basic %s' % plpy.execute("SELECT cartodb._CDB_Group_API_Auth('%s', '%s') as auth" % (params['username'], params['password']))[0]['auth']
      return { "host": params['host'], "port": params['port'], 'timeout': params['timeout'], 'auth': auth }
      # return params
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_API_Auth(username text, password text)
    RETURNS TEXT AS
$$
    import base64
    base64.encodestring('%s:%s' % (username, password)).replace('\n', '')
$$ LANGUAGE 'plpythonu' IMMUTABLE;
