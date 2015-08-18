-- Requires configuration parameter. Example: SELECT cartodb.CDB_Conf_SetConf('groups_api', '{ "host": "127.0.0.1", "port": 3000, "timeout": 10, "username": "superadmin", "password": "monkey" }');

-- Sends the create group request
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_CreateGroup_API(database_name text, group_name text, group_role text)
    RETURNS VOID AS
$$
    import string

    url = '/api/v1/databases/%s/groups' % database_name
    body = '{ "name": "%s", "database_role": "%s" }' % (group_name, group_role)
    query = "select cartodb._CDB_Group_API_Request('POST', '%s', '%s') as response_status" % (url, body)
    plpy.execute(query)[0]['response_status']
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_DropGroup_API(database_name text, group_name text)
    RETURNS VOID AS
$$
    import string

    url = '/api/v1/databases/%s/groups/%s' % (database_name, group_name)
    query = "select cartodb._CDB_Group_API_Request('DELETE', '%s', '') as response_status" % url
    plpy.execute(query)[0]['response_status']
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_RenameGroup_API(database_name text, old_group_name text, new_group_name text, new_group_role text)
    RETURNS VOID AS
$$
    import string

    url = '/api/v1/databases/%s/groups/%s' % (database_name, old_group_name)
    body = '{ "name": "%s", "database_role": "%s" }' % (new_group_name, new_group_role)
    query = "select cartodb._CDB_Group_API_Request('PUT', '%s', '%s') as response_status" % (url, body)
    plpy.execute(query)[0]['response_status']
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_AddMember_API(database_name text, group_name text, username text)
    RETURNS VOID AS
$$
    import string

    url = '/api/v1/databases/%s/groups/%s/users' % (database_name, group_name)
    body = '{ "username": "%s" }' % username
    query = "select cartodb._CDB_Group_API_Request('POST', '%s', '%s') as response_status" % (url, body)
    plpy.execute(query)[0]['response_status']
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_RemoveMember_API(database_name text, group_name text, username text)
    RETURNS VOID AS
$$
    import string

    url = '/api/v1/databases/%s/groups/%s/users/%s' % (database_name, group_name, username)
    query = "select cartodb._CDB_Group_API_Request('DELETE', '%s', '') as response_status" % url
    plpy.execute(query)[0]['response_status']
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

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_API_Request(method text, url text, body text)
    RETURNS int AS
$$
    import httplib

    params = plpy.execute("select c.host, c.port, c.timeout, c.auth from cartodb._CDB_Group_API_Conf() c;")[0]
    if params['host'] is None:
      return None

    headers = { 'Authorization': params['auth'], 'Content-Type': 'application/json' }

    retry = 3

    last_err = None
    while retry > 0:
      try:
        client = GD['groups_api_client'] = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
        client.request(method, url, body, headers)
        response = client.getresponse()
        assert response.status in [ 200, 409 ]
        return response.status
      except Exception as err:
        retry -= 1
        last_err = err
        plpy.warning('Retrying after: ' + str(err))
        client = GD['groups_api_client'] = None

    if last_err is not None:
      plpy.error('Fatal Group API error: ' + str(last_err))
      raise last_err
$$ LANGUAGE 'plpythonu' VOLATILE;
